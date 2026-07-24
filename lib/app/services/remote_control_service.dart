import 'dart:async';
import 'dart:io';

import 'package:app_release_center/app/data/release_center_connect.dart';
import 'package:app_release_center/app/models/release_fastlane_lane.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/models/release_script.dart';
import 'package:app_release_center/app/models/remote_control.dart';
import 'package:app_release_center/app/services/notification_credential_store_service.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:app_release_center/app/services/script_catalog_service.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

class RemoteControlService extends GetxService {
  RemoteControlService({
    required ProjectStoreService store,
    required ScriptCatalogService catalog,
    required ReleaseRunnerService runner,
    required ReleaseCenterConnect connect,
    required NotificationCredentialStoreService credentialStore,
  }) : _store = store,
       _catalog = catalog,
       _runner = runner,
       _connect = connect,
       _credentialStore = credentialStore;

  final ProjectStoreService _store;
  final ScriptCatalogService _catalog;
  final ReleaseRunnerService _runner;
  final ReleaseCenterConnect _connect;
  final NotificationCredentialStoreService _credentialStore;

  final settings = const RemoteControlSettings().obs;
  final mobileSettings = const MobileControlSettings().obs;
  final agentStatus = 'Remote control idle'.obs;
  final desktopState = Rxn<RemoteDesktopState>();
  final activeMobileCommand = Rxn<RemoteCommand>();
  final mobileStatus = ''.obs;
  final isMobileBusy = false.obs;

  Timer? _heartbeatTimer;
  bool _isPollingDesktop = false;
  bool _isExecutingRemoteCommand = false;
  String? _activeDesktopCommandId;
  int _lastInputSequence = 0;
  bool _stopRequested = false;
  Timer? _inputTimer;
  Timer? _publishTimer;

  @override
  void onInit() {
    super.onInit();
    settings.value = _store.remoteControlSettings;
    mobileSettings.value = _store.mobileControlSettings;
    if (!Platform.isAndroid && !Platform.isIOS) {
      unawaited(_syncDesktopAgent());
    }
  }

  @override
  void onClose() {
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
      throw const RemoteControlException(
        'Endpoint and pairing code are required.',
      );
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
        'Pairing response did not include a control token.',
      );
    }

    final updated = MobileControlSettings(
      endpointBaseUrl: endpoint,
      deviceControlToken: token,
      deviceId: device['id']?.toString() ?? '',
    );
    await _store.saveMobileControlSettings(updated);
    mobileSettings.value = updated;
    mobileStatus.value = 'Linked to desktop relay.';
  }

  Future<void> clearMobileLink() async {
    const cleared = MobileControlSettings();
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
      agentStatus.value = 'Remote control disabled.';
      return;
    }

    agentStatus.value = 'Remote control enabled.';
    await _sendHeartbeat();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_sendHeartbeat()),
    );
    unawaited(_desktopPollLoop());
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

  Future<List<RemoteCommand>> _fetchQueuedDesktopCommands() async {
    try {
      final endpoint = _desktopEndpoint;
      if (endpoint == null) {
        agentStatus.value = 'Remote endpoint is not configured.';
        await Future<void>.delayed(const Duration(seconds: 5));
        return const [];
      }
      final response = await _connect.get(
        _endpoint(
          endpoint,
          'desktop/commands?desktopId=${Uri.encodeQueryComponent(settings.value.desktopId)}&waitMs=20000',
        ),
        headers: await _desktopHeaders(),
      );
      _ensureResponseOk(
        response.statusCode ?? 0,
        response.body,
        'load remote commands',
      );
      final body = _bodyMap(response.body);
      final entries = body['commands'];
      if (entries is! List) return const [];
      return entries
          .whereType<Map>()
          .map(
            (entry) => RemoteCommand.fromJson(Map<String, Object?>.from(entry)),
          )
          .toList();
    } catch (error) {
      agentStatus.value = 'Remote poll failed: $error';
      await Future<void>.delayed(const Duration(seconds: 5));
      return const [];
    }
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
      _runner.appendSystemLog('Remote command failed: $errorMessage');
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
          'Unsupported remote command: ${command.type}.',
        );
    }
  }

  Future<int> _executeShell(Map<String, Object?> payload) {
    final command = payload['command']?.toString().trim() ?? '';
    if (command.isEmpty) {
      throw const RemoteControlException('Remote shell command is empty.');
    }

    final workingDirectory = _allowedWorkingDirectory(
      payload['workingDirectory']?.toString() ?? '',
    );
    return _runner.runCommand(
      workingDirectory: workingDirectory,
      statusLabel: 'Remote shell',
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
      throw RemoteControlException('Script is not available: $scriptPath.');
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
      throw RemoteControlException('Fastlane lane is not available: $laneKey.');
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
      agentStatus.value = 'Remote input poll failed: $error';
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
          ? 'Remote control online.'
          : 'Remote command running.';
    } catch (error) {
      agentStatus.value = 'Remote heartbeat failed: $error';
    }
  }

  Future<Map<String, Object?>> _desktopStatePayload() async {
    return {
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
        'No allowed project roots are configured for remote shell.',
      );
    }

    final candidate = requested.trim().isEmpty
        ? roots.first
        : p.normalize(requested);
    if (roots.any((root) => _sameOrWithin(root, candidate))) {
      return candidate;
    }

    throw RemoteControlException(
      'Remote path is outside allowed project roots: $candidate.',
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
      throw const RemoteControlException('This phone is not linked yet.');
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
    throw const RemoteControlException('Expected JSON object from relay.');
  }

  void _ensureResponseOk(int statusCode, Object? body, String action) {
    if (statusCode >= 200 && statusCode < 300) return;
    final message = body is Map && body['error'] != null
        ? body['error'].toString()
        : 'HTTP $statusCode';
    throw RemoteControlException('Failed to $action: $message');
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
