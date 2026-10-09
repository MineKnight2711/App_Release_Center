import 'dart:async';
import 'dart:io';

import 'package:app_management_center/app/data/release_center_connect.dart';
import 'package:app_management_center/app/models/release_fastlane_lane.dart';
import 'package:app_management_center/app/models/release_project.dart';
import 'package:app_management_center/app/models/release_script.dart';
import 'package:app_management_center/app/models/remote_control.dart';
import 'package:app_management_center/app/models/wake_diagnostics.dart';
import 'package:app_management_center/app/services/app_build_stamp.dart';
import 'package:app_management_center/app/services/machine_power_service.dart';
import 'package:app_management_center/app/services/mobile_control_credential_store_service.dart';
import 'package:app_management_center/app/services/notification_credential_store_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:app_management_center/app/services/remote_unlock_service.dart';
import 'package:app_management_center/app/services/script_catalog_service.dart';
import 'package:app_management_center/app/services/wake_diagnostics_service.dart';
import 'package:app_management_center/app/services/wake_probe_listener.dart';
import 'package:app_management_center/app/services/windows_auto_start_service.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

class RemoteControlService extends GetxService {
  static const relayEndpoint =
      'https://amc-relay.huynhphuocdat2.workers.dev/api';
  static const _legacyRelayHost =
      'app-release-center-notifications.onrender.com';

  RemoteControlService({
    required ProjectStoreService store,
    required ScriptCatalogService catalog,
    required ReleaseRunnerService runner,
    required ReleaseCenterConnect connect,
    required NotificationCredentialStoreService credentialStore,
    required MobileControlCredentialStoreService mobileCredentialStore,
    MachinePowerService? power,
    WakeDiagnosticsService? wakeDiagnostics,
    WindowsAutoStartService? autoStart,
    RemoteUnlockService? remoteUnlock,
    WakeProbeListener? wakeProbe,
  }) : _store = store,
       _catalog = catalog,
       _runner = runner,
       _connect = connect,
       _credentialStore = credentialStore,
       _mobileCredentialStore = mobileCredentialStore,
       _power = power ?? MachinePowerService(),
       _wakeDiagnostics = wakeDiagnostics ?? WakeDiagnosticsService(),
       _autoStart = autoStart ?? WindowsAutoStartService(),
       _remoteUnlock = remoteUnlock ?? RemoteUnlockService(),
       _wakeProbe = wakeProbe ?? WakeProbeListener();

  final ProjectStoreService _store;
  final ScriptCatalogService _catalog;
  final ReleaseRunnerService _runner;
  final ReleaseCenterConnect _connect;
  final NotificationCredentialStoreService _credentialStore;
  final MobileControlCredentialStoreService _mobileCredentialStore;
  final MachinePowerService _power;
  final WakeDiagnosticsService _wakeDiagnostics;
  final WindowsAutoStartService _autoStart;
  final RemoteUnlockService _remoteUnlock;
  final WakeProbeListener _wakeProbe;

  final settings = const RemoteControlSettings().obs;
  final mobileSettings = const MobileControlSettings().obs;
  final agentStatus = 'Điều khiển từ xa đang chờ'.obs;
  final desktopState = Rxn<RemoteDesktopState>();
  final activeMobileCommand = Rxn<RemoteCommand>();
  final mobileStatus = ''.obs;
  final isMobileBusy = false.obs;

  /// A shutdown or restart the machine is counting down to, so the desktop can
  /// offer a cancel button to whoever is sitting in front of it.
  final pendingPowerCommand = Rxn<PendingPowerCommand>();

  Timer? _heartbeatTimer;
  bool _isPollingDesktop = false;
  bool _isPollingControl = false;
  MachineSleepSupport? _sleepSupport;
  WakeDiagnostics? _wake;
  DateTime? _wakeReadAt;

  /// How long a wake-readiness reading stays good for.
  ///
  /// Long enough that the heartbeat is not spawning PowerShell every few
  /// seconds, short enough that swapping Wi-Fi for a cable is picked up
  /// without restarting the app.
  static const _wakeCacheFor = Duration(minutes: 5);

  bool get _isWakeCacheStale {
    final readAt = _wakeReadAt;
    return readAt == null || DateTime.now().difference(readAt) > _wakeCacheFor;
  }

  bool _isExecutingRemoteCommand = false;
  String? _activeDesktopCommandId;
  int _lastInputSequence = 0;
  bool _stopRequested = false;
  Timer? _inputTimer;
  Timer? _publishTimer;

  /// Loads settings before the first frame so the phone never flashes the
  /// pairing form at someone who is already linked.
  Future<RemoteControlService> init() async {
    await _migrateLegacyRelay();
    settings.value = _store.remoteControlSettings;
    mobileSettings.value = await _loadMobileSettings();
    return this;
  }

  /// Moves the desktop off the retired Render relay.
  ///
  /// The two relays never shared a `DESKTOP_API_TOKEN`, so the token left over
  /// from Render cannot authenticate against the Worker. Leaving it in place
  /// turned every call into a bare `HTTP 401: Unauthorized.` that read like a
  /// server fault rather than a credential that has to be re-entered, so the
  /// migration drops it the same way [_loadMobileSettings] drops the phone's
  /// control token. The devices go with it: they lived in the old relay's
  /// store and did not come across.
  Future<void> _migrateLegacyRelay() async {
    final notificationSettings = _store.notificationSettings;
    if (!_usesLegacyRelay(notificationSettings.endpointBaseUrl)) return;

    await _store.saveNotificationSettings(
      notificationSettings.copyWith(
        endpointBaseUrl: relayEndpoint,
        selectedDeviceIds: const [],
      ),
    );
    await _store.saveLinkedNotificationDevices(const []);
    await _credentialStore.saveApiToken(null);
  }

  @override
  void onInit() {
    super.onInit();
    if (!Platform.isAndroid && !Platform.isIOS) {
      unawaited(_syncDesktopAgent());
    }
  }

  /// Reads the phone's link, moving a control token left in preferences by an
  /// older build into secure storage and scrubbing it from preferences.
  ///
  /// The scrub is what makes this worth doing: writing the token to its new
  /// home while leaving a copy in `shared_preferences.json` would add a
  /// storage location instead of replacing one.
  Future<MobileControlSettings> _loadMobileSettings() async {
    final stored = _store.mobileControlSettings;
    if (_usesLegacyRelay(stored.endpointBaseUrl)) {
      await _mobileCredentialStore.clearControlToken();
      const migrated = MobileControlSettings(endpointBaseUrl: relayEndpoint);
      await _store.saveMobileControlSettings(migrated);
      return migrated;
    }
    final secureToken = (await _mobileCredentialStore.readControlToken())
        ?.trim();
    final legacyToken = stored.deviceControlToken.trim();

    if (legacyToken.isEmpty) {
      return stored.copyWith(deviceControlToken: secureToken ?? '');
    }

    if (secureToken == null || secureToken.isEmpty) {
      await _mobileCredentialStore.saveControlToken(legacyToken);
    }
    // toJson no longer serialises the token, so this rewrite drops it.
    await _store.saveMobileControlSettings(stored);
    return stored.copyWith(
      deviceControlToken: secureToken == null || secureToken.isEmpty
          ? legacyToken
          : secureToken,
    );
  }

  static bool _usesLegacyRelay(String endpoint) {
    return Uri.tryParse(endpoint.trim())?.host.toLowerCase() ==
        _legacyRelayHost;
  }

  @override
  void onClose() {
    unawaited(_wakeProbe.stop());
    _heartbeatTimer?.cancel();
    _inputTimer?.cancel();
    _publishTimer?.cancel();
    super.onClose();
  }

  Future<void> setEnabled(bool enabled) async {
    final updated = settings.value.copyWith(enabled: enabled);
    await _store.saveRemoteControlSettings(updated);
    settings.value = updated;
    await _syncDesktopAgent();
  }

  Future<void> setAllowPowerControl(bool allowed) async {
    final updated = settings.value.copyWith(allowPowerControl: allowed);
    await _store.saveRemoteControlSettings(updated);
    settings.value = updated;
  }

  Future<void> setAllowWindowControl(bool allowed) async {
    final updated = settings.value.copyWith(allowWindowControl: allowed);
    await _store.saveRemoteControlSettings(updated);
    settings.value = updated;
  }

  Future<void> setAllowRemoteUnlock(bool allowed) async {
    final updated = settings.value.copyWith(allowRemoteUnlock: allowed);
    await _store.saveRemoteControlSettings(updated);
    settings.value = updated;
  }

  Future<void> installRemoteUnlockProvider() async {
    await _remoteUnlock.launchInstaller();
    agentStatus.value = 'Đã cài Credential Provider mở khóa Windows.';
  }

  Future<void> saveAllowedApps(List<String> apps) async {
    final normalized = apps
        .map((app) => app.trim())
        .where((app) => app.isNotEmpty)
        .map(p.normalize)
        .toSet()
        .toList();
    final updated = settings.value.copyWith(allowedApps: normalized);
    await _store.saveRemoteControlSettings(updated);
    settings.value = updated;
  }

  Future<void> saveAllowedRoots(List<String> roots) async {
    final normalized = roots
        .map((root) => root.trim())
        .where((root) => root.isNotEmpty)
        .map(p.normalize)
        .toSet()
        .toList();
    final updated = settings.value.copyWith(allowedRoots: normalized);
    await _store.saveRemoteControlSettings(updated);
    settings.value = updated;
  }

  Future<void> linkMobileDevice({
    required String endpointBaseUrl,
    required String pairingCode,
    String pairingId = '',
    String deviceName = 'Android phone',
  }) async {
    final endpoint = endpointBaseUrl.trim();
    if (endpoint.isEmpty || pairingCode.trim().isEmpty) {
      throw const RemoteControlException('Phải có endpoint và mã ghép.');
    }

    final response = await _connect.post(
      _endpoint(endpoint, 'control-devices'),
      {
        'pairingId': pairingId.trim(),
        'pairingCode': pairingCode.trim(),
        'deviceName': deviceName.trim().isEmpty
            ? 'Android phone'
            : deviceName.trim(),
        'platform': Platform.operatingSystem,
      },
      headers: const {'Content-Type': 'application/json'},
    );
    _ensureResponseOk(response.statusCode ?? 0, response.body, 'link device');

    final body = _bodyMap(response.body);
    final token = body['deviceControlToken']?.toString() ?? '';
    final device = body['device'] is Map
        ? Map<String, Object?>.from(body['device'] as Map)
        : const <String, Object?>{};
    if (token.isEmpty) {
      throw const RemoteControlException(
        'Phản hồi ghép nối không kèm control token.',
      );
    }

    final updated = MobileControlSettings(
      endpointBaseUrl: endpoint,
      deviceControlToken: token,
      deviceId: device['id']?.toString() ?? '',
    );
    await _mobileCredentialStore.saveControlToken(token);
    await _store.saveMobileControlSettings(updated);
    mobileSettings.value = updated;
    mobileStatus.value = 'Đã liên kết với relay của máy tính.';
  }

  Future<void> clearMobileLink() async {
    const cleared = MobileControlSettings();
    await _mobileCredentialStore.clearControlToken();
    await _store.saveMobileControlSettings(cleared);
    mobileSettings.value = cleared;
    desktopState.value = null;
    activeMobileCommand.value = null;
  }

  Future<void> refreshMobileDesktopState() async {
    final settings = _requireMobileSettings();
    final response = await _connect.get(
      _endpoint(settings.endpointBaseUrl, 'mobile/desktop-state'),
      headers: _mobileHeaders(settings),
    );
    _ensureResponseOk(
      response.statusCode ?? 0,
      response.body,
      'load desktop state',
    );
    final body = _bodyMap(response.body);
    desktopState.value = body['desktop'] is Map
        ? RemoteDesktopState.fromJson(
            Map<String, Object?>.from(body['desktop'] as Map),
          )
        : null;
  }

  Future<RemoteCommand> enqueueShellCommand({
    required String command,
    required String workingDirectory,
  }) {
    return _enqueueMobileCommand({
      'type': 'shell',
      'payload': {'command': command, 'workingDirectory': workingDirectory},
    });
  }

  Future<RemoteCommand> enqueueScript({
    required RemoteProjectSummary project,
    required RemoteScriptSummary script,
  }) {
    return _enqueueMobileCommand({
      'type': 'script',
      'payload': {'projectPath': project.path, 'scriptPath': script.path},
    });
  }

  Future<RemoteCommand> enqueueFastlaneLane({
    required RemoteProjectSummary project,
    required RemoteFastlaneSummary lane,
  }) {
    return _enqueueMobileCommand({
      'type': 'fastlane',
      'payload': {'projectPath': project.path, 'laneKey': lane.key},
    });
  }

  /// Queues a power command for [desktopId].
  ///
  /// The desktop is named explicitly because the relay refuses a power command
  /// that does not say which machine it is for — there is no sane default for
  /// "shut down whichever one answered first".
  Future<RemoteCommand> enqueuePowerCommand({
    required String desktopId,
    required MachinePowerAction action,
    int delaySeconds = 0,
    bool force = false,
  }) {
    return _enqueueMobileCommand({
      'type': 'power',
      'targetDesktopId': desktopId,
      'payload': {
        'action': action.name,
        'delaySeconds': delaySeconds,
        'force': force,
      },
    });
  }

  Future<RemoteCommand> enqueueUnlockCommand({
    required String desktopId,
    required String encryptedEnvelope,
  }) {
    return _enqueueMobileCommand({
      'type': 'unlock',
      'targetDesktopId': desktopId,
      'payload': {'envelope': encryptedEnvelope},
    });
  }

  Future<RemoteCommand> refreshMobileCommand(String commandId) async {
    final settings = _requireMobileSettings();
    final response = await _connect.get(
      _endpoint(settings.endpointBaseUrl, 'mobile/commands/$commandId'),
      headers: _mobileHeaders(settings),
    );
    _ensureResponseOk(response.statusCode ?? 0, response.body, 'load command');
    final command = RemoteCommand.fromJson(
      Map<String, Object?>.from(_bodyMap(response.body)['command'] as Map),
    );
    activeMobileCommand.value = command;
    return command;
  }

  Future<void> sendMobileInput(String commandId, String value) async {
    final settings = _requireMobileSettings();
    final response = await _connect.post(
      _endpoint(settings.endpointBaseUrl, 'mobile/commands/$commandId/input'),
      {'value': value},
      headers: _mobileHeaders(settings),
    );
    _ensureResponseOk(response.statusCode ?? 0, response.body, 'send input');
  }

  Future<void> stopMobileCommand(String commandId) async {
    final settings = _requireMobileSettings();
    final response = await _connect.post(
      _endpoint(settings.endpointBaseUrl, 'mobile/commands/$commandId/stop'),
      const {},
      headers: _mobileHeaders(settings),
    );
    _ensureResponseOk(response.statusCode ?? 0, response.body, 'stop command');
  }

  Future<RemoteCommand> _enqueueMobileCommand(Map<String, Object?> body) async {
    final settings = _requireMobileSettings();
    final response = await _connect.post(
      _endpoint(settings.endpointBaseUrl, 'mobile/commands'),
      body,
      headers: _mobileHeaders(settings),
    );
    _ensureResponseOk(
      response.statusCode ?? 0,
      response.body,
      'enqueue command',
    );
    final command = RemoteCommand.fromJson(
      Map<String, Object?>.from(_bodyMap(response.body)['command'] as Map),
    );
    activeMobileCommand.value = command;
    return command;
  }

  Future<void> _syncDesktopAgent() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    if (Platform.isAndroid || Platform.isIOS || !settings.value.enabled) {
      agentStatus.value = 'Đã tắt điều khiển từ xa.';
      return;
    }

    agentStatus.value = 'Đã bật điều khiển từ xa.';
    await _sendHeartbeat();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_sendHeartbeat()),
    );
    unawaited(_desktopPollLoop());
    unawaited(_controlPollLoop());
  }

  /// Drains the control lane.
  ///
  /// Deliberately does not wait on [_runner]: locking or shutting the machine
  /// down is most wanted exactly while a release holds the runner, which is
  /// the one moment [_desktopPollLoop] refuses to act.
  Future<void> _controlPollLoop() async {
    if (_isPollingControl || !settings.value.enabled) return;
    _isPollingControl = true;
    try {
      while (settings.value.enabled && !Platform.isAndroid && !Platform.isIOS) {
        final commands = await _fetchQueuedControlCommands();
        for (final command in commands) {
          await _claimAndExecuteControl(command);
        }
      }
    } finally {
      _isPollingControl = false;
    }
  }

  Future<List<RemoteCommand>> _fetchQueuedControlCommands() {
    return _longPollCommands(
      path: 'desktop/control-commands',
      label: 'lệnh điều khiển',
    );
  }

  /// Long-polls one of the relay's command queues.
  ///
  /// A poll that comes back with nothing is the normal idle case, not a
  /// failure: treating it as one used to paint an error across the agent
  /// status of a perfectly healthy machine and add a five second backoff
  /// before the next poll, which queued commands waited out.
  Future<List<RemoteCommand>> _longPollCommands({
    required String path,
    required String label,
  }) async {
    final endpoint = _desktopEndpoint;
    if (endpoint == null) {
      agentStatus.value = 'Chưa cấu hình endpoint điều khiển từ xa.';
      await Future<void>.delayed(const Duration(seconds: 5));
      return const [];
    }

    final startedAt = DateTime.now();
    try {
      final query =
          'desktopId=${Uri.encodeQueryComponent(settings.value.desktopId)}'
          '&waitMs=${remoteLongPollWindow.inMilliseconds}';
      final response = await _connect.get(
        _endpoint(endpoint, '$path?$query'),
        headers: await _desktopHeaders(),
      );
      _ensureResponseOk(response.statusCode ?? 0, response.body, 'load $label');

      final entries = _bodyMap(response.body)['commands'];
      if (entries is! List) return const [];
      return entries
          .whereType<Map>()
          .map(
            (entry) => RemoteCommand.fromJson(Map<String, Object?>.from(entry)),
          )
          .toList();
    } catch (error) {
      // A request that ran at least the whole window and then gave up is the
      // relay holding an idle connection, not a broken link.
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed >= remoteLongPollWindow) return const [];

      agentStatus.value = 'Lấy $label lỗi: $error';
      await Future<void>.delayed(const Duration(seconds: 5));
      return const [];
    }
  }

  Future<void> _claimAndExecuteControl(RemoteCommand command) async {
    final endpoint = _desktopEndpoint;
    if (endpoint == null) return;

    try {
      final claimResponse = await _connect.post(
        _endpoint(endpoint, 'desktop/commands/${command.commandId}/claim'),
        {'desktopId': settings.value.desktopId},
        headers: await _desktopHeaders(),
      );
      if ((claimResponse.statusCode ?? 0) == 409) return;
      _ensureResponseOk(
        claimResponse.statusCode ?? 0,
        claimResponse.body,
        'claim control command',
      );
    } catch (error) {
      agentStatus.value = 'Nhận lệnh điều khiển lỗi: $error';
      return;
    }

    final startedAt = DateTime.now();
    String? errorMessage;
    final log = <String>[];
    try {
      await _publishControlState(
        command.commandId,
        status: 'running',
        startedAt: startedAt,
      );
      log.addAll(await _executeControlCommand(command));
    } catch (error) {
      errorMessage = error.toString();
      log.add(errorMessage);
    }

    // Whoever is at the machine should be able to see what the phone did,
    // successful or not.
    for (final line in log) {
      _runner.appendSystemLog(line);
    }

    final finishedAt = DateTime.now();
    await _publishControlState(
      command.commandId,
      status: errorMessage == null ? 'completed' : 'failed',
      startedAt: startedAt,
      finishedAt: finishedAt,
      durationMs: finishedAt.difference(startedAt).inMilliseconds,
      exitCode: errorMessage == null ? 0 : 1,
      error: errorMessage,
      logLines: log,
    );
  }

  Future<List<String>> _executeControlCommand(RemoteCommand command) {
    switch (command.type) {
      case 'power':
        return _executePower(command.payload);
      case 'unlock':
        return _executeUnlock(command.payload);
      default:
        throw RemoteControlException(
          'Lệnh điều khiển không hỗ trợ: ${command.type}.',
        );
    }
  }

  Future<List<String>> _executeUnlock(Map<String, Object?> payload) async {
    if (!settings.value.allowRemoteUnlock) {
      throw const RemoteControlException(
        'Máy tính chưa bật quyền mở khóa từ xa.',
      );
    }
    if (!await _power.isSessionLocked()) {
      throw const RemoteControlException(
        'Máy tính hiện không ở màn hình khóa.',
      );
    }
    final envelope = payload['envelope']?.toString().trim() ?? '';
    if (envelope.isEmpty) {
      throw const RemoteControlException('Thiếu payload mở khóa đã mã hóa.');
    }
    try {
      await _remoteUnlock.acceptEncryptedEnvelope(envelope);
    } on RemoteUnlockException catch (error) {
      throw RemoteControlException(error.message);
    }
    return const ['Đã chuyển yêu cầu mã hóa tới Windows LogonUI.'];
  }

  Future<List<String>> _executePower(Map<String, Object?> payload) {
    final action = machinePowerActionFromName(
      payload['action']?.toString() ?? '',
    );
    if (action == null) {
      throw RemoteControlException(
        'Hành động nguồn không hợp lệ: ${payload['action']}.',
      );
    }

    return applyPowerCommand(
      action: action,
      delaySeconds: _int(payload['delaySeconds']) ?? 0,
      force: payload['force'] == true,
    );
  }

  /// Runs a power action after checking it is allowed right now.
  ///
  /// Returns the lines to log. Throws [RemoteControlException] when the
  /// machine refuses, so the phone gets a reason rather than silence.
  Future<List<String>> applyPowerCommand({
    required MachinePowerAction action,
    int delaySeconds = 0,
    bool force = false,
  }) async {
    final rejection = powerCommandRejection(
      action: action,
      allowPowerControl: settings.value.allowPowerControl,
      powerSupported: _power.isSupported,
      runnerBusy: _runner.isBusy,
      force: force,
      runnerStatus: _runner.status.value,
    );
    if (rejection != null) throw RemoteControlException(rejection);

    if (action == MachinePowerAction.cancel) {
      await _power.perform(action);
      pendingPowerCommand.value = null;
      return ['Đã huỷ lệnh nguồn đang chờ.'];
    }

    final delay = delaySeconds < 0 ? 0 : delaySeconds;
    await _power.perform(action, delaySeconds: delay, force: force);

    if (isDelayablePowerAction(action) && delay > 0) {
      pendingPowerCommand.value = PendingPowerCommand(
        action: action,
        firesAt: DateTime.now().add(Duration(seconds: delay)),
      );
    }

    return [
      'Lệnh nguồn từ điện thoại: ${action.name}'
          '${delay > 0 ? ' sau ${delay}s' : ''}'
          '${force ? ' (buộc)' : ''}.',
    ];
  }

  /// Cancels a shutdown or restart that is still counting down.
  Future<void> cancelPendingPowerCommand() async {
    await _power.perform(MachinePowerAction.cancel);
    pendingPowerCommand.value = null;
    _runner.appendSystemLog('Đã huỷ lệnh nguồn tại máy.');
  }

  Future<void> _publishControlState(
    String commandId, {
    required String status,
    DateTime? startedAt,
    DateTime? finishedAt,
    int? durationMs,
    int? exitCode,
    String? error,
    List<String> logLines = const [],
  }) async {
    final endpoint = _desktopEndpoint;
    if (endpoint == null) return;

    try {
      final response = await _connect.post(
        _endpoint(endpoint, 'desktop/commands/$commandId/events'),
        {
          'status': status,
          'startedAt': startedAt?.toUtc().toIso8601String(),
          'finishedAt': finishedAt?.toUtc().toIso8601String(),
          'durationMs': durationMs,
          'exitCode': exitCode,
          'error': error,
          'logLines': logLines,
        },
        headers: await _desktopHeaders(),
      );
      _ensureResponseOk(
        response.statusCode ?? 0,
        response.body,
        'publish control state',
      );
    } catch (publishError) {
      // The machine may already be shutting down; losing the receipt must not
      // take the loop down with it.
      agentStatus.value = 'Báo trạng thái điều khiển lỗi: $publishError';
    }
  }

  Future<void> _desktopPollLoop() async {
    if (_isPollingDesktop || !settings.value.enabled) return;
    _isPollingDesktop = true;
    try {
      while (settings.value.enabled && !Platform.isAndroid && !Platform.isIOS) {
        if (_runner.isBusy || _isExecutingRemoteCommand) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }

        final commands = await _fetchQueuedDesktopCommands();
        for (final command in commands) {
          if (!_runner.isBusy && !_isExecutingRemoteCommand) {
            await _claimAndExecute(command);
          }
        }
      }
    } finally {
      _isPollingDesktop = false;
    }
  }

  Future<List<RemoteCommand>> _fetchQueuedDesktopCommands() {
    return _longPollCommands(path: 'desktop/commands', label: 'lệnh từ xa');
  }

  Future<void> _claimAndExecute(RemoteCommand queuedCommand) async {
    final endpoint = _desktopEndpoint;
    if (endpoint == null) return;

    final claimResponse = await _connect.post(
      _endpoint(endpoint, 'desktop/commands/${queuedCommand.commandId}/claim'),
      {'desktopId': settings.value.desktopId},
      headers: await _desktopHeaders(),
    );
    if ((claimResponse.statusCode ?? 0) == 409) return;
    _ensureResponseOk(
      claimResponse.statusCode ?? 0,
      claimResponse.body,
      'claim command',
    );

    _activeDesktopCommandId = queuedCommand.commandId;
    _lastInputSequence = 0;
    _stopRequested = false;
    _isExecutingRemoteCommand = true;
    final startedAt = DateTime.now();
    _startInputPolling(queuedCommand.commandId);
    _startRunPublishing(queuedCommand.commandId, startedAt);

    int exitCode = -1;
    String? errorMessage;
    try {
      await _publishCommandState(
        queuedCommand.commandId,
        status: 'running',
        startedAt: startedAt,
      );
      exitCode = await _executeRemoteCommand(queuedCommand);
    } catch (error) {
      errorMessage = error.toString();
      _runner.appendSystemLog('Lệnh từ xa lỗi: $errorMessage');
    } finally {
      _inputTimer?.cancel();
      _publishTimer?.cancel();
      final finishedAt = DateTime.now();
      await _publishCommandState(
        queuedCommand.commandId,
        status: _stopRequested
            ? 'canceled'
            : exitCode == 0 && errorMessage == null
            ? 'completed'
            : 'failed',
        startedAt: startedAt,
        finishedAt: finishedAt,
        durationMs: finishedAt.difference(startedAt).inMilliseconds,
        exitCode: exitCode,
        error: errorMessage,
      );
      _activeDesktopCommandId = null;
      _isExecutingRemoteCommand = false;
      await _sendHeartbeat();
    }
  }

  Future<int> _executeRemoteCommand(RemoteCommand command) async {
    switch (command.type) {
      case 'shell':
        return _executeShell(command.payload);
      case 'script':
        return _executeScript(command.payload);
      case 'fastlane':
        return _executeFastlane(command.payload);
      default:
        throw RemoteControlException(
          'Lệnh từ xa không hỗ trợ: ${command.type}.',
        );
    }
  }

  Future<int> _executeShell(Map<String, Object?> payload) {
    final command = payload['command']?.toString().trim() ?? '';
    if (command.isEmpty) {
      throw const RemoteControlException('Lệnh shell từ xa trống.');
    }

    final workingDirectory = _allowedWorkingDirectory(
      payload['workingDirectory']?.toString() ?? '',
    );
    return _runner.runCommand(
      workingDirectory: workingDirectory,
      statusLabel: 'Shell từ xa',
      activePath: 'remote:shell:${DateTime.now().microsecondsSinceEpoch}',
      executable: Platform.isWindows ? 'powershell.exe' : 'sh',
      arguments: Platform.isWindows
          ? ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command]
          : ['-lc', command],
      clearLog: true,
      projectName: p.basename(workingDirectory),
    );
  }

  Future<int> _executeScript(Map<String, Object?> payload) async {
    final project = await _projectFromPayload(payload);
    final scriptPath = payload['scriptPath']?.toString() ?? '';
    final script = _firstOrNull(
      project.scripts,
      (entry) =>
          _samePath(entry.path, scriptPath) || entry.fileName == scriptPath,
    );
    if (script == null) {
      throw RemoteControlException('Không có script: $scriptPath.');
    }

    return _runner.run(
      project: project,
      script: script,
      args: _stringList(payload['args']),
      clearLog: true,
      environment: const {
        'FASTLANE_SKIP_SCREEN': '1',
        'TTY_SCREEN_WIDTH': '120',
        'TTY_SCREEN_HEIGHT': '40',
      },
    );
  }

  Future<int> _executeFastlane(Map<String, Object?> payload) async {
    final project = await _projectFromPayload(payload);
    final laneKey = payload['laneKey']?.toString() ?? '';
    final lane = _firstOrNull(
      project.fastlaneLanes,
      (entry) => entry.key == laneKey || entry.name == laneKey,
    );
    if (lane == null) {
      throw RemoteControlException('Không có lane Fastlane: $laneKey.');
    }

    return _runner.runFastlaneLane(
      project: project,
      lane: lane,
      args: _stringList(payload['args']),
      clearLog: true,
      environment: const {
        'FASTLANE_SKIP_SCREEN': '1',
        'TTY_SCREEN_WIDTH': '120',
        'TTY_SCREEN_HEIGHT': '40',
      },
    );
  }

  Future<ReleaseProject> _projectFromPayload(Map<String, Object?> payload) {
    final projectPath = payload['projectPath']?.toString() ?? '';
    final allowedPath = _allowedWorkingDirectory(projectPath);
    return _catalog.inspect(allowedPath);
  }

  void _startInputPolling(String commandId) {
    _inputTimer?.cancel();
    _inputTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_pollCommandInputs(commandId)),
    );
  }

  Future<void> _pollCommandInputs(String commandId) async {
    final endpoint = _desktopEndpoint;
    if (endpoint == null) return;

    try {
      final response = await _connect.get(
        _endpoint(
          endpoint,
          'desktop/commands/$commandId/inputs?afterSequence=$_lastInputSequence',
        ),
        headers: await _desktopHeaders(),
      );
      _ensureResponseOk(
        response.statusCode ?? 0,
        response.body,
        'load command inputs',
      );
      final entries = _bodyMap(response.body)['inputs'];
      if (entries is! List) return;
      for (final entry in entries.whereType<Map>()) {
        final sequence = _int(entry['sequence']) ?? _lastInputSequence;
        _lastInputSequence = sequence > _lastInputSequence
            ? sequence
            : _lastInputSequence;
        final kind = entry['kind']?.toString() ?? '';
        if (kind == 'stdin') {
          _runner.sendInput(entry['value']?.toString() ?? '');
        } else if (kind == 'stop') {
          _stopRequested = true;
          await _runner.stop();
        }
      }
    } catch (error) {
      agentStatus.value = 'Lấy input từ xa lỗi: $error';
    }
  }

  void _startRunPublishing(String commandId, DateTime startedAt) {
    _publishTimer?.cancel();
    _publishTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(
        _publishCommandState(
          commandId,
          status: 'running',
          startedAt: startedAt,
        ),
      ),
    );
  }

  Future<void> _publishCommandState(
    String commandId, {
    required String status,
    DateTime? startedAt,
    DateTime? finishedAt,
    int? durationMs,
    int? exitCode,
    String? error,
  }) async {
    final endpoint = _desktopEndpoint;
    if (endpoint == null) return;

    final response = await _connect.post(
      _endpoint(endpoint, 'desktop/commands/$commandId/events'),
      {
        'status': status,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'finishedAt': finishedAt?.toUtc().toIso8601String(),
        'durationMs': durationMs,
        'exitCode': exitCode,
        'error': error,
        'yesNoPrompt': _runner.yesNoPrompt.value,
        'logLines': _runner.logLines.toList(),
      },
      headers: await _desktopHeaders(),
    );
    _ensureResponseOk(
      response.statusCode ?? 0,
      response.body,
      'publish command state',
    );
  }

  Future<void> _sendHeartbeat() async {
    final endpoint = _desktopEndpoint;
    if (endpoint == null || !settings.value.enabled) return;

    try {
      final response = await _connect
          .post(_endpoint(endpoint, 'desktop/heartbeat'), {
            'desktopId': settings.value.desktopId,
            'displayName': Platform.localHostname,
            'remoteControlEnabled': settings.value.enabled,
            'state': await _desktopStatePayload(),
          }, headers: await _desktopHeaders());
      _ensureResponseOk(
        response.statusCode ?? 0,
        response.body,
        'send heartbeat',
      );
      agentStatus.value = _activeDesktopCommandId == null
          ? 'Điều khiển từ xa đang online.'
          : 'Lệnh từ xa đang chạy.';
    } catch (error) {
      agentStatus.value = 'Tín hiệu điều khiển từ xa lỗi: $error';
    }
  }

  Future<Map<String, Object?>> _desktopStatePayload() async {
    // Sleep states are a machine property, not a per-heartbeat one; reading
    // powercfg every ten seconds would spawn a process for no new answer.
    _sleepSupport ??= await _power.readSleepSupport();
    // Same reasoning, plus one more: the phone needs these precisely when the
    // machine is asleep and cannot be asked, so they must already be up here.
    //
    // Re-read periodically rather than once per process. Plugging in an
    // Ethernet cable changes which adapter the packet has to be aimed at, and
    // a cache that never expired kept sending the phone a stale Wi-Fi MAC
    // until the app was restarted — with no sign that anything was wrong.
    if (_wake == null || _isWakeCacheStale) {
      _wake = await _wakeDiagnostics.read(
        autoStartEnabled: _autoStart.isEnabled(),
        sleepSupport: _sleepSupport!,
      );
      _wakeReadAt = DateTime.now();
      // Only now is the MAC known, and the listener needs it to tell this
      // machine's wake packets from a neighbour's.
      unawaited(_wakeProbe.start(_wake!.macAddress));
    }

    // Carried separately from the cached reading: this changes every time the
    // phone taps wake, which is the whole point of recording it.
    final wake = _wake!.withProbe(
      probeListening: _wakeProbe.isListening,
      lastPacketAt: _wakeProbe.lastPacketAt,
      lastPacketFrom: _wakeProbe.lastPacketFrom,
    );

    final sessionLocked = await _power.isSessionLocked();
    final remoteUnlock = await _remoteUnlock.diagnostics(
      sessionLocked: sessionLocked,
      enabled: settings.value.allowRemoteUnlock,
    );

    return {
      // Lets the phone show which build the desktop is on, so a stale copy is
      // visible rather than something to be inferred from missing behaviour.
      'buildStamp': const AppBuildStamp().read()?.toUtc().toIso8601String(),
      'wake': wake.toJson(),
      'sessionLocked': sessionLocked,
      'powerControlEnabled': settings.value.allowPowerControl,
      'windowControlEnabled': settings.value.allowWindowControl,
      'remoteUnlock': remoteUnlock.toJson(),
      'sleepSupport': _sleepSupport!.toJson(),
      'isRunning': _runner.isBusy,
      'status': _runner.status.value,
      'activeScriptPath': _runner.activeScriptPath.value,
      'exitCode': _runner.exitCode.value,
      'yesNoPrompt': _runner.yesNoPrompt.value,
      'logLines': _runner.logLines.takeLast(80).toList(),
      'projects': await _projectSummaries(),
    };
  }

  Future<List<Map<String, Object?>>> _projectSummaries() async {
    final paths = <String>[
      if (_store.lastProjectPath != null) _store.lastProjectPath!,
      ..._store.recentProjectPaths,
    ];
    final seen = <String>{};
    final summaries = <Map<String, Object?>>[];

    for (final rawPath in paths) {
      final path = p.normalize(rawPath);
      if (!seen.add(path.toLowerCase())) continue;
      if (!Directory(path).existsSync()) continue;
      try {
        final project = await _catalog.inspect(path);
        summaries.add({
          'path': project.path,
          'name': project.name,
          'scripts': project.scripts.map(_scriptJson).toList(),
          'fastlaneLanes': project.fastlaneLanes.map(_laneJson).toList(),
        });
      } catch (_) {
        // Skip projects that cannot be inspected during heartbeat.
      }
      if (summaries.length >= 8) break;
    }

    return summaries;
  }

  Map<String, Object?> _scriptJson(ReleaseScript script) {
    return {
      'path': script.path,
      'fileName': script.fileName,
      'label': script.label,
      'description': script.description,
    };
  }

  Map<String, Object?> _laneJson(ReleaseFastlaneLane lane) {
    return {
      'key': lane.key,
      'name': lane.name,
      'label': lane.label,
      'command': lane.command,
    };
  }

  String _allowedWorkingDirectory(String requested) {
    final roots = _allowedRoots();
    if (roots.isEmpty) {
      throw const RemoteControlException(
        'Chưa cấu hình thư mục dự án nào cho phép chạy shell từ xa.',
      );
    }

    final candidate = requested.trim().isEmpty
        ? roots.first
        : p.normalize(requested);
    if (roots.any((root) => _sameOrWithin(root, candidate))) {
      return candidate;
    }

    throw RemoteControlException(
      'Đường dẫn nằm ngoài các thư mục dự án được phép: $candidate.',
    );
  }

  List<String> _allowedRoots() {
    final roots = <String>[
      ...settings.value.allowedRoots,
      if (_store.lastProjectPath != null) _store.lastProjectPath!,
      ..._store.recentProjectPaths,
    ];
    final seen = <String>{};
    return roots
        .map((root) => p.normalize(root))
        .where((root) => Directory(root).existsSync())
        .where((root) => seen.add(root.toLowerCase()))
        .toList();
  }

  bool _sameOrWithin(String root, String child) {
    final normalizedRoot = p.normalize(root);
    final normalizedChild = p.normalize(child);
    if (Platform.isWindows) {
      final rootLower = normalizedRoot.toLowerCase();
      final childLower = normalizedChild.toLowerCase();
      return childLower == rootLower || p.isWithin(rootLower, childLower);
    }
    return normalizedChild == normalizedRoot ||
        p.isWithin(normalizedRoot, normalizedChild);
  }

  bool _samePath(String left, String right) {
    if (Platform.isWindows) {
      return p.normalize(left).toLowerCase() ==
          p.normalize(right).toLowerCase();
    }
    return p.normalize(left) == p.normalize(right);
  }

  String? get _desktopEndpoint {
    final endpoint = _store.notificationSettings.endpointBaseUrl.trim();
    return endpoint.isEmpty ? null : endpoint;
  }

  Future<Map<String, String>> _desktopHeaders() async {
    final token = (await _credentialStore.readApiToken())?.trim();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  MobileControlSettings _requireMobileSettings() {
    final settings = mobileSettings.value;
    if (!settings.isLinked) {
      throw const RemoteControlException('Điện thoại này chưa được liên kết.');
    }
    return settings;
  }

  Map<String, String> _mobileHeaders(MobileControlSettings settings) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${settings.deviceControlToken}',
    };
  }

  String _endpoint(String base, String path) {
    final normalizedBase = base.trim().replaceFirst(RegExp(r'/+$'), '');
    final normalizedPath = path.replaceFirst(RegExp(r'^/+'), '');
    return '$normalizedBase/$normalizedPath';
  }

  Map<String, Object?> _bodyMap(Object? body) {
    if (body is Map<String, Object?>) return body;
    if (body is Map) return Map<String, Object?>.from(body);
    throw const RemoteControlException('Relay phải trả về một object JSON.');
  }

  void _ensureResponseOk(int statusCode, Object? body, String action) {
    if (statusCode >= 200 && statusCode < 300) return;
    final message = body is Map && body['error'] != null
        ? body['error'].toString()
        : 'HTTP $statusCode';
    throw RemoteControlException('$action lỗi: $message');
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.map((entry) => entry.toString()).toList();
  }

  int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  T? _firstOrNull<T>(Iterable<T> entries, bool Function(T entry) test) {
    for (final entry in entries) {
      if (test(entry)) return entry;
    }
    return null;
  }
}

/// Why a power command must not run now, or null when it may.
///
/// Pulled out of the service so the rule that protects a running release can
/// be read and tested on its own, without a relay or a machine to shut down.
String? powerCommandRejection({
  required MachinePowerAction action,
  required bool allowPowerControl,
  required bool powerSupported,
  required bool runnerBusy,
  required bool force,
  required String runnerStatus,
}) {
  if (!allowPowerControl) {
    return 'Máy tính chưa bật quyền điều khiển nguồn.';
  }
  if (!powerSupported) {
    return 'Máy này không hỗ trợ điều khiển nguồn.';
  }
  if (interruptsRunningWork(action) && runnerBusy && !force) {
    return 'Đang chạy: $runnerStatus. Lệnh ${action.name} bị bỏ qua để không '
        'làm hỏng việc đang dở.';
  }
  return null;
}

/// Everything but locking the screen and aborting a countdown cuts a build off.
bool interruptsRunningWork(MachinePowerAction action) {
  return action != MachinePowerAction.lock &&
      action != MachinePowerAction.cancel;
}

/// Only `shutdown.exe /s` and `/g` take a timer, so only those can be aborted.
bool isDelayablePowerAction(MachinePowerAction action) {
  return action == MachinePowerAction.shutdown ||
      action == MachinePowerAction.restart;
}

/// A power command that has been handed to Windows but has not fired yet.
class PendingPowerCommand {
  const PendingPowerCommand({required this.action, required this.firesAt});

  final MachinePowerAction action;
  final DateTime firesAt;

  Duration remaining({DateTime? now}) {
    final left = firesAt.difference(now ?? DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}

class RemoteControlException implements Exception {
  const RemoteControlException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension _IterableTail<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList();
    if (list.length <= count) return list;
    return list.sublist(list.length - count);
  }
}
