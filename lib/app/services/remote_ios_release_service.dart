import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/data/release_center_connect.dart';
import 'package:app_management_center/app/models/app_store_credentials.dart';
import 'package:app_management_center/app/models/app_store_project.dart';
import 'package:app_management_center/app/models/ios_build_host.dart';
import 'package:app_management_center/app/models/ios_release.dart';
import 'package:app_management_center/app/models/remote_control.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/ios_build_envelope.dart';
import 'package:app_management_center/app/services/ios_build_host_service.dart';
import 'package:app_management_center/app/services/ios_release_backend.dart';
import 'package:app_management_center/app/services/ios_release_workflow_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

typedef GitRunner =
    Future<ProcessResult> Function(List<String> arguments, String directory);

/// Runs the iOS release workflow on a paired Mac, through the relay.
///
/// Each step goes out as one command sealed for the Mac and is followed until
/// the Mac reports it finished; the run snapshots it reports along the way are
/// what the dialog shows, so the timeline moves as the Mac works. Nothing here
/// builds anything: the Mac checks out the commit this machine is on, and the
/// App Store Connect key travels sealed with each step, never stored there.
class RemoteIosReleaseService implements IosReleaseBackend {
  RemoteIosReleaseService({
    required ProjectStoreService store,
    required ReleaseCenterConnect connect,
    required Future<AppStoreCredentials> Function(String projectId) credentials,
    SecureKeyValueStore? secureStore,
    GitRunner? git,
    DateTime Function()? now,
    this.pollInterval = const Duration(milliseconds: 1500),
    this.queryTimeout = const Duration(seconds: 25),
    this.connectionGrace = const Duration(minutes: 3),
    this.staleAfter = const Duration(seconds: 90),
    this.stopGrace = const Duration(seconds: 20),
  }) : _store = store,
       _connect = connect,
       _credentials = credentials,
       _secureStore = secureStore ?? SecureKeyValueStore.platform(),
       _git = git ?? _runGit,
       _now = now ?? DateTime.now;

  final ProjectStoreService _store;
  final ReleaseCenterConnect _connect;
  final Future<AppStoreCredentials> Function(String) _credentials;
  final SecureKeyValueStore _secureStore;
  final GitRunner _git;
  final DateTime Function() _now;
  final Duration pollInterval;

  /// How long a history or log question may wait for the Mac to answer.
  final Duration queryTimeout;

  /// How long the relay may be unreachable before a step stops being followed.
  /// The Mac carries on regardless; reopening the dialog picks it back up.
  final Duration connectionGrace;

  /// How long a claimed step may go without a progress report before the Mac
  /// is asked whether it is still running it. It reports every two seconds.
  final Duration staleAfter;

  /// How long the Mac has to confirm a stop before this desktop stops
  /// following the step anyway. A Mac that already let go of the step never
  /// will, and the dialog must not stay stuck on it.
  final Duration stopGrace;

  /// How long a sealed step stays valid, including time spent queued behind
  /// another build on the Mac.
  static const envelopeLifetime = Duration(hours: 6);
  static const _tokenKey = 'ios_build_host.control_token';

  final link = const IosBuildHostLink().obs;
  final host = Rxn<IosBuildHostState>();
  final hostError = ''.obs;

  /// What the step in flight is waiting on, for the dialog to show.
  final status = ''.obs;

  @override
  final current = Rxn<IosReleaseRun>();
  @override
  final history = <IosReleaseRun>[].obs;
  @override
  final busy = false.obs;
  @override
  final liveLog = <String>[].obs;

  @override
  bool get usesLocalRunner => false;

  /// Projects by id, as this machine knows them: the Mac's runs carry its own
  /// checkout path, and files to send along are read from here.
  final _projects = <String, AppStoreProject>{};
  String? _activeCommandId;
  DateTime? _stopRequestedAt;
  Future<void>? _loading;

  Future<void> _ensureLoaded() => _loading ??= () async {
    final stored = _store.iosBuildHostLink;
    final token = (await _secureStore.read(key: _tokenKey))?.trim() ?? '';
    link.value = stored.copyWith(controlToken: token);
  }();

  bool get isLinked => link.value.isLinked;

  /// Links this desktop to the Mac that showed [pairingCode], and pins that
  /// Mac's key. Returns the link so the fingerprint can be compared with the
  /// one the Mac shows.
  Future<IosBuildHostLink> linkHost({
    required String endpointBaseUrl,
    required String pairingCode,
    String deviceName = '',
  }) async {
    await _ensureLoaded();
    final endpoint = endpointBaseUrl.trim();
    final code = pairingCode.trim().toUpperCase();
    if (endpoint.isEmpty || code.isEmpty) {
      throw const RemoteIosReleaseException(
        'Cần endpoint relay và mã ghép hiển thị trên Mac.',
      );
    }
    final response = await _connect.post(
      _url(endpoint, 'control-devices'),
      {
        'pairingCode': code,
        'deviceName': deviceName.trim().isEmpty
            ? 'AMC ${Platform.localHostname}'
            : deviceName.trim(),
        'platform': Platform.operatingSystem,
      },
      headers: const {'Content-Type': 'application/json'},
    );
    _ensureOk(response.statusCode, response.body, 'Ghép Mac');
    final body = _bodyMap(response.body);
    final token = _text(body['deviceControlToken']);
    final desktopId = _text(body['desktopId']);
    if (token.isEmpty) {
      throw const RemoteIosReleaseException(
        'Relay không trả về control token.',
      );
    }
    if (desktopId.isEmpty) {
      throw const RemoteIosReleaseException(
        'Mã ghép không gắn với máy build nào. Cập nhật relay và AMC trên Mac, '
        'rồi tạo mã mới.',
      );
    }
    final provisional = IosBuildHostLink(
      endpointBaseUrl: endpoint,
      deviceId: _text(_map(body['device'])['id']),
      desktopId: desktopId,
      controlToken: token,
    );
    final state = await _fetchHost(provisional);
    if (state == null || !state.enabled || state.publicKey.isEmpty) {
      throw RemoteIosReleaseException(
        'Relay chưa thấy Mac "$desktopId" bật nhận build iOS. Bật trên Mac, '
        'đợi vài giây rồi tạo mã mới.',
      );
    }
    final key = base64.decode(state.publicKey);
    final linked = IosBuildHostLink(
      endpointBaseUrl: endpoint,
      deviceId: provisional.deviceId,
      desktopId: desktopId,
      displayName: state.displayName,
      publicKey: state.publicKey,
      fingerprint: await IosBuildEnvelope.fingerprint(key),
      linkedAt: _now(),
      controlToken: token,
    );
    await _secureStore.write(key: _tokenKey, value: token);
    await _store.saveIosBuildHostLink(linked);
    link.value = linked;
    host.value = state;
    hostError.value = '';
    return linked;
  }

  Future<void> unlink() async {
    await _ensureLoaded();
    await _secureStore.delete(key: _tokenKey);
    await _store.saveIosBuildHostLink(null);
    await _store.saveIosBuildHostActiveStep(null);
    link.value = const IosBuildHostLink();
    host.value = null;
    hostError.value = '';
    history.clear();
    current.value = null;
  }

  /// Re-reads the Mac's heartbeat: online, busy, which Xcode, which key.
  Future<IosBuildHostState?> refreshHost() async {
    await _ensureLoaded();
    final linked = link.value;
    if (!linked.isLinked) {
      host.value = null;
      return null;
    }
    try {
      final state = await _fetchHost(linked);
      host.value = state;
      hostError.value = state == null
          ? 'Relay chưa thấy Mac "${linked.desktopId}". Mở AMC trên Mac và bật '
                'điều khiển từ xa.'
          : !state.enabled
          ? 'Mac đang tắt "Nhận build iOS từ máy khác".'
          : state.publicKey.isNotEmpty && state.publicKey != linked.publicKey
          ? 'Khóa của Mac đã đổi so với lúc ghép (cài lại AMC?). Ghép lại để '
                'xác nhận trước khi gửi API key.'
          : '';
      return state;
    } catch (error) {
      hostError.value = error.toString();
      return null;
    }
  }

  /// What the Mac will build: the commit this checkout is on.
  Future<IosRemoteSource> inspectSource(String projectPath) async {
    Future<String> read(List<String> arguments) async {
      final result = await _git(arguments, projectPath);
      return result.exitCode == 0 ? result.stdout.toString().trim() : '';
    }

    final commit = await read(['rev-parse', 'HEAD']);
    final status = await read(['status', '--porcelain']);
    final containing = commit.isEmpty
        ? ''
        : await read(['branch', '-r', '--contains', commit]);
    return IosRemoteSource(
      commit: commit,
      branch: await read(['rev-parse', '--abbrev-ref', 'HEAD']),
      remote: sanitizeRemote(await read(['remote', 'get-url', 'origin'])),
      changedFiles: status.isEmpty ? 0 : status.split('\n').length,
      pushed: containing.isNotEmpty,
    );
  }

  /// Drops credentials embedded in an https remote. The Mac signs in to git
  /// its own way; a token typed into this machine's remote stays here.
  static String sanitizeRemote(String remote) {
    final uri = Uri.tryParse(remote.trim());
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isEmpty) {
      return remote.trim();
    }
    return uri.replace(userInfo: '').toString();
  }

  @override
  Future<void> load([AppStoreProject? project]) async {
    await _ensureLoaded();
    if (project != null) _projects[project.id] = project;
    final linked = link.value;
    if (!linked.isLinked || project == null) return;
    // An offline Mac would only time the question out; say so straight away
    // and keep whatever history this session already has.
    final state = await refreshHost();
    if (state == null || !state.online) return;
    await _syncHistory(linked, project.id);
    final runs = history.where((run) => run.project.id == project.id);
    final active = _store.iosBuildHostActiveStep;
    if (!busy.value &&
        active != null &&
        active['projectId'] == project.id &&
        active['desktopId'] == linked.desktopId) {
      final run = runs.where((run) => run.id == active['runId']).firstOrNull;
      if (run != null) current.value = run;
      unawaited(_resume(linked, active));
    }
  }

  @override
  Future<IosReleaseRun> prepare({
    required AppStoreProject project,
    required IosReleaseSettings settings,
    String? version,
    IosStoreBuild? existingBuild,
  }) async {
    IosReleaseWorkflowService.validateSettings(settings);
    _projects[project.id] = project;
    final source = await inspectSource(project.path);
    if (source.commit.isEmpty || source.remote.isEmpty) {
      throw const RemoteIosReleaseException(
        'Build trên Mac cần project là git repo có remote origin.',
      );
    }
    final result = await _step(
      projectId: project.id,
      action: 'prepare',
      runId: '',
      body: {
        ...await _baseBody(project),
        'settings': settings.toJson(),
        'git': source.toJson(),
        'version': version,
        'existingBuild': existingBuild?.toJson(),
        'files': await _files(project.path, settings.remoteFiles),
      },
    );
    return _runFrom(result) ??
        (throw const RemoteIosReleaseException('Mac không trả về run.'));
  }

  @override
  Future<IosStoreState> inspect(
    AppStoreProject project,
    IosReleaseSettings settings,
    String version,
  ) async {
    _projects[project.id] = project;
    final source = await inspectSource(project.path);
    final result = await _step(
      projectId: project.id,
      action: 'inspect',
      runId: '',
      body: {
        ...await _baseBody(project),
        'settings': settings.toJson(),
        'git': {'remote': source.remote},
        'version': version,
      },
    );
    final store = result['store'];
    return store is Map
        ? IosStoreState.fromJson(Map<String, dynamic>.from(store))
        : const IosStoreState();
  }

  @override
  Future<void> build(IosReleaseRun run) =>
      _runStep(run, 'build', withFiles: true);

  @override
  Future<void> upload(
    IosReleaseRun run, {
    bool retryAfterVerification = false,
  }) => _runStep(
    run,
    'upload',
    extra: {'retryAfterVerification': retryAfterVerification},
  );

  @override
  Future<void> continueToTestFlight(IosReleaseRun run) =>
      _runStep(run, 'continue', withFiles: true);

  @override
  Future<void> refresh(IosReleaseRun run) => _runStep(run, 'refresh');

  @override
  Future<void> waitForProcessing(IosReleaseRun run) => _runStep(run, 'wait');

  @override
  Future<void> storeAction(IosReleaseRun run, String action) {
    if (!['draft', 'submit', 'release', 'distribute'].contains(action)) {
      throw ArgumentError.value(action);
    }
    return _runStep(run, action);
  }

  @override
  Future<void> cancel() async {
    final commandId = _activeCommandId;
    final linked = link.value;
    if (commandId == null || !linked.isLinked) return;
    // Counted from now even if the request fails: the follow loop lets go
    // after [stopGrace] whether or not the Mac ever hears about it.
    _stopRequestedAt = _now();
    status.value = 'Đã gửi yêu cầu dừng tới Mac…';
    final response = await _connect.post(
      _url(linked.endpointBaseUrl, 'mobile/commands/$commandId/stop'),
      const {},
      headers: _headers(linked),
    );
    _ensureOk(response.statusCode, response.body, 'Gửi lệnh dừng');
  }

  @override
  Future<List<String>> savedLog(IosReleaseRun run) async {
    await _ensureLoaded();
    final linked = link.value;
    if (!linked.isLinked) return const [];
    final answer = await _query(
      linked,
      action: 'log',
      projectId: run.project.id,
      runId: run.id,
    );
    return answer.logLines;
  }

  Future<void> _runStep(
    IosReleaseRun run,
    String action, {
    bool withFiles = false,
    Map<String, Object?> extra = const {},
  }) async {
    final local = _projects[run.project.id];
    if (withFiles && local == null) {
      throw const RemoteIosReleaseException(
        'Mở lại bảng release từ project để AMC đọc được file gửi kèm.',
      );
    }
    final result = await _step(
      projectId: run.project.id,
      action: action,
      runId: run.id,
      body: {
        ...await _baseBody(local ?? run.project),
        if (withFiles)
          'files': await _files(local!.path, run.settings.remoteFiles),
        ...extra,
      },
    );
    _runFrom(result);
  }

  Future<Map<String, Object?>> _baseBody(AppStoreProject project) async {
    final credential = await _credentials(project.id);
    if (!credential.hasRequiredCredentials || credential.inHouse) {
      throw const RemoteIosReleaseException(
        'Cần API key App Store Connect (.p8, Key ID, Issuer ID), không dùng '
        'Enterprise/in-house.',
      );
    }
    return {
      'project': {
        'id': project.id,
        'displayName': project.displayName,
        'bundleId': project.bundleId,
      },
      'credentials': {
        'p8PrivateKey': credential.p8PrivateKey,
        'keyId': credential.keyId,
        'issuerId': credential.issuerId,
        'teamId': credential.teamId,
      },
    };
  }

  Future<List<Map<String, Object?>>> _files(
    String projectPath,
    List<String> paths,
  ) async {
    final files = <Map<String, Object?>>[];
    var total = 0;
    for (final path in paths) {
      final relative = IosReleaseWorkflowService.remoteFilePath(path);
      if (relative == null) {
        throw RemoteIosReleaseException('File gửi kèm không hợp lệ: $path');
      }
      final file = File(p.joinAll([projectPath, ...relative.split('/')]));
      if (!await file.exists()) {
        throw RemoteIosReleaseException(
          'Không thấy file gửi kèm trên máy này: $relative',
        );
      }
      final bytes = await file.readAsBytes();
      total += bytes.length;
      if (total > IosBuildHostService.maxFileBytes) {
        throw const RemoteIosReleaseException(
          'File gửi kèm vượt 256 KB. Chỉ gửi file cấu hình nhỏ.',
        );
      }
      files.add({'path': relative, 'data': base64.encode(bytes)});
    }
    return files;
  }

  IosReleaseRun? _runFrom(Map<String, Object?> result) {
    final json = result['run'];
    if (json is! Map) return null;
    final run = iosRunFromWire(Map<String, dynamic>.from(json));
    _absorb(run);
    return run;
  }

  void _absorb(IosReleaseRun run) {
    final index = history.indexWhere((entry) => entry.id == run.id);
    if (index < 0) {
      history.insert(0, run);
    } else {
      history[index] = run;
    }
    current.value = run;
    current.refresh();
    history.refresh();
  }

  Future<Map<String, Object?>> _step({
    required String projectId,
    required String action,
    required String runId,
    required Map<String, Object?> body,
  }) async {
    await _ensureLoaded();
    if (busy.value) {
      throw const RemoteIosReleaseException(
        'Đợi bước iOS đang chạy trên Mac kết thúc.',
      );
    }
    final linked = link.value;
    if (!linked.isLinked) {
      throw const RemoteIosReleaseException(
        'Chưa ghép Mac build. Ghép Mac trong bảng release iOS trước.',
      );
    }
    busy.value = true;
    liveLog.clear();
    status.value = 'Đang gửi lệnh tới ${linked.displayName}…';
    try {
      final envelope = await IosBuildEnvelope.seal(
        hostPublicKey: base64.decode(linked.publicKey),
        body: {
          ...body,
          'id': IosBuildEnvelope.randomId(),
          'exp': _now().add(envelopeLifetime).toUtc().toIso8601String(),
        },
        associatedData: IosBuildEnvelope.associatedData(
          desktopId: linked.desktopId,
          action: action,
          runId: runId,
          projectId: projectId,
        ),
      );
      final command = await _enqueue(linked, {
        'type': 'ios',
        'targetDesktopId': linked.desktopId,
        'payload': {
          'action': action,
          'runId': runId,
          'projectId': projectId,
          'envelope': envelope,
        },
      });
      await _store.saveIosBuildHostActiveStep({
        'commandId': command.commandId,
        'desktopId': linked.desktopId,
        'projectId': projectId,
        'runId': runId,
        'action': action,
      });
      return await _follow(linked, command.commandId, projectId: projectId);
    } finally {
      busy.value = false;
      status.value = '';
    }
  }

  /// Picks up a step a previous session sent and did not see finish.
  Future<void> _resume(
    IosBuildHostLink linked,
    Map<String, Object?> active,
  ) async {
    final commandId = _text(active['commandId']);
    if (commandId.isEmpty || busy.value) return;
    busy.value = true;
    try {
      await _follow(linked, commandId, projectId: _text(active['projectId']));
    } on RemoteIosReleaseException catch (error) {
      // The run snapshot already says how a step that failed on the Mac
      // ended; this is for losing the relay while following it.
      if (error.connectionLost) hostError.value = error.message;
    } finally {
      busy.value = false;
      status.value = '';
    }
  }

  Future<Map<String, Object?>> _follow(
    IosBuildHostLink linked,
    String commandId, {
    required String projectId,
  }) async {
    _activeCommandId = commandId;
    _stopRequestedAt = null;
    DateTime? lostSince;
    var lastUpdate = '';
    var lastProgressAt = _now();
    try {
      while (true) {
        final RemoteCommand command;
        try {
          command = await _fetchCommand(linked, commandId);
          lostSince = null;
        } on _RelayUnavailable catch (error) {
          lostSince ??= _now();
          if (_now().difference(lostSince) > connectionGrace) {
            throw RemoteIosReleaseException(
              'Mất kết nối relay: ${error.message}. Bước này có thể vẫn đang '
              'chạy trên Mac; mở lại bảng release để theo dõi tiếp.',
              connectionLost: true,
            );
          }
          status.value = 'Mất kết nối relay, đang thử lại…';
          await Future<void>.delayed(pollInterval);
          continue;
        }
        if (command.logLines.isNotEmpty) liveLog.assignAll(command.logLines);
        final run = command.result['run'];
        if (run is Map) {
          _absorb(iosRunFromWire(Map<String, dynamic>.from(run)));
        }
        status.value = switch (command.status) {
          _ when command.isActive && _stopRequestedAt != null =>
            'Đang chờ ${linked.displayName} dừng…',
          'queued' => 'Đang chờ ${linked.displayName} nhận lệnh…',
          'claimed' || 'running' => '${linked.displayName} đang chạy…',
          _ => '',
        };
        if (command.updatedAt != lastUpdate) {
          lastUpdate = command.updatedAt;
          lastProgressAt = _progressTime(command.updatedAt);
        }
        if (command.isActive) {
          final stopAt = _stopRequestedAt;
          if (stopAt != null && _now().difference(stopAt) > stopGrace) {
            await _letGo(linked, projectId);
            throw RemoteIosReleaseException(
              '${linked.displayName} chưa xác nhận lệnh dừng sau '
              '${stopGrace.inSeconds} giây. AMC ngừng theo dõi bước này; nếu '
              'Mac vẫn đang build, dừng trực tiếp trên Mac.',
            );
          }
          // A queued step waits on the Mac being free and reports nothing.
          if (command.status != 'queued' &&
              _now().difference(lastProgressAt) > staleAfter) {
            if (!await _hostStillRunning(linked, commandId)) {
              await _letGo(linked, projectId);
              throw RemoteIosReleaseException(
                '${linked.displayName} không còn chạy bước này (AMC trên Mac '
                'đã dừng, khởi động lại hoặc offline) nên kết quả sẽ không '
                'về nữa. Trạng thái run đã được đọc lại từ Mac.',
              );
            }
            lastProgressAt = _now();
          }
        }
        if (!command.isActive) {
          await _store.saveIosBuildHostActiveStep(null);
          return switch (command.status) {
            'completed' => command.result,
            'canceled' => throw const RemoteIosReleaseException(
              'Đã hủy luồng iOS trên Mac.',
            ),
            _ => throw RemoteIosReleaseException(
              command.error ?? 'Mac báo lỗi (exit ${command.exitCode}).',
            ),
          };
        }
        await Future<void>.delayed(pollInterval);
      }
    } on RemoteIosReleaseException catch (error) {
      // The relay no longer knows the command: nothing left to come back to.
      if (error.definitive) await _store.saveIosBuildHostActiveStep(null);
      rethrow;
    } finally {
      _activeCommandId = null;
      _stopRequestedAt = null;
    }
  }

  /// The relay's clock for a report, kept from running ahead of this one so a
  /// skewed clock cannot make a live step look stale or a dead one fresh
  /// forever.
  DateTime _progressTime(String updatedAt) {
    final now = _now();
    final at = DateTime.tryParse(updatedAt)?.toLocal();
    return at == null || at.isAfter(now) ? now : at;
  }

  /// Whether the Mac is still working on [commandId], as its heartbeat says.
  /// A Mac too old to name its command counts as running it while busy.
  Future<bool> _hostStillRunning(
    IosBuildHostLink linked,
    String commandId,
  ) async {
    try {
      final state = await _fetchHost(linked);
      if (state != null) host.value = state;
      if (state == null || !state.online) return false;
      return state.activeCommandId.isNotEmpty
          ? state.activeCommandId == commandId
          : state.busy;
    } catch (_) {
      // Not hearing from the relay is no evidence the Mac stopped.
      return true;
    }
  }

  /// Stops tracking a step that will not report back, and shows what the Mac
  /// actually has for the run instead of the last snapshot that arrived.
  Future<void> _letGo(IosBuildHostLink linked, String projectId) async {
    await _store.saveIosBuildHostActiveStep(null);
    if (projectId.isEmpty) return;
    try {
      await _syncHistory(linked, projectId);
    } catch (_) {
      // The message says what happened; history refreshes on the next open.
    }
  }

  Future<void> _syncHistory(IosBuildHostLink linked, String projectId) async {
    final answer = await _query(
      linked,
      action: 'history',
      projectId: projectId,
    );
    final runs = <IosReleaseRun>[];
    for (final entry in (answer.result['runs'] as List? ?? const [])) {
      if (entry is! Map) continue;
      try {
        runs.add(iosRunFromWire(Map<String, dynamic>.from(entry)));
      } catch (_) {
        /* A run from a newer host must not hide the others. */
      }
    }
    history
      ..removeWhere((run) => run.project.id == projectId)
      ..insertAll(0, runs);
    final shown = current.value;
    if (shown != null && shown.project.id == projectId) {
      current.value =
          runs.where((run) => run.id == shown.id).firstOrNull ?? shown;
    }
  }

  /// Asks the Mac a read-only question on the control lane and waits briefly.
  Future<RemoteCommand> _query(
    IosBuildHostLink linked, {
    required String action,
    required String projectId,
    String runId = '',
  }) async {
    final command = await _enqueue(linked, {
      'type': 'iosQuery',
      'targetDesktopId': linked.desktopId,
      'payload': {'action': action, 'projectId': projectId, 'runId': runId},
    });
    final deadline = _now().add(queryTimeout);
    while (true) {
      await Future<void>.delayed(
        pollInterval < const Duration(milliseconds: 600)
            ? pollInterval
            : const Duration(milliseconds: 600),
      );
      final RemoteCommand answer;
      try {
        answer = await _fetchCommand(linked, command.commandId);
      } on _RelayUnavailable {
        if (_now().isAfter(deadline)) rethrow;
        continue;
      }
      if (!answer.isActive) {
        if (answer.status == 'completed') return answer;
        throw RemoteIosReleaseException(
          answer.error ?? 'Mac không trả lời được.',
        );
      }
      if (_now().isAfter(deadline)) {
        throw RemoteIosReleaseException(
          '${linked.displayName} không phản hồi. Kiểm tra Mac đang mở AMC và '
          'online.',
        );
      }
    }
  }

  Future<RemoteCommand> _enqueue(
    IosBuildHostLink linked,
    Map<String, Object?> body,
  ) async {
    final response = await _connect.post(
      _url(linked.endpointBaseUrl, 'mobile/commands'),
      body,
      headers: _headers(linked),
    );
    _ensureOk(response.statusCode, response.body, 'Gửi lệnh tới Mac');
    return RemoteCommand.fromJson(_map(_bodyMap(response.body)['command']));
  }

  Future<RemoteCommand> _fetchCommand(
    IosBuildHostLink linked,
    String commandId,
  ) async {
    final response = await _connect.get(
      _url(linked.endpointBaseUrl, 'mobile/commands/$commandId'),
      headers: _headers(linked),
    );
    _ensureOk(response.statusCode, response.body, 'Đọc trạng thái lệnh');
    return RemoteCommand.fromJson(_map(_bodyMap(response.body)['command']));
  }

  Future<IosBuildHostState?> _fetchHost(IosBuildHostLink linked) async {
    final response = await _connect.get(
      _url(linked.endpointBaseUrl, 'mobile/desktops'),
      headers: _headers(linked),
    );
    if (response.statusCode == 404) {
      throw const RemoteIosReleaseException(
        'Relay chưa hỗ trợ build iOS từ xa. Deploy bản relay mới.',
      );
    }
    _ensureOk(response.statusCode, response.body, 'Đọc trạng thái Mac');
    final desktops = _bodyMap(response.body)['desktops'];
    if (desktops is! List) return null;
    return desktops
        .whereType<Map>()
        .map((entry) => IosBuildHostState.fromDesktopJson(_map(entry)))
        .where((state) => state.desktopId == linked.desktopId)
        .firstOrNull;
  }

  Map<String, String> _headers(IosBuildHostLink linked) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${linked.controlToken}',
  };

  static String _url(String base, String path) =>
      '${base.trim().replaceFirst(RegExp(r'/+$'), '')}/$path';

  /// A missing answer or a server fault is worth waiting out; a refusal is
  /// not.
  static void _ensureOk(int? statusCode, Object? body, String action) {
    final code = statusCode ?? 0;
    if (code >= 200 && code < 300) return;
    final message = body is Map && body['error'] != null
        ? body['error'].toString()
        : code == 0
        ? 'không kết nối được relay'
        : 'HTTP $code';
    if (code == 0 || code >= 500) throw _RelayUnavailable('$action: $message');
    throw RemoteIosReleaseException(
      '$action lỗi: ${explainRemoteControlError(_explainIos(message))}',
      definitive: code == 404 || code == 403,
    );
  }

  static String _explainIos(String message) {
    if (message.contains('desktop that paired it')) {
      return '$message\n\nMáy này chỉ gửi được lệnh tới đúng Mac đã tạo mã '
          'ghép. Ghép lại với Mac muốn dùng.';
    }
    return message;
  }

  static Map<String, Object?> _bodyMap(Object? body) {
    if (body is Map) return Map<String, Object?>.from(body);
    throw const RemoteIosReleaseException('Relay phải trả về một object JSON.');
  }

  static Future<ProcessResult> _runGit(
    List<String> arguments,
    String directory,
  ) => Process.run('git', arguments, workingDirectory: directory);
}

/// The commit a remote build will use, as read on this machine.
class IosRemoteSource {
  const IosRemoteSource({
    required this.commit,
    required this.branch,
    required this.remote,
    required this.changedFiles,
    required this.pushed,
  });

  final String commit;
  final String branch;
  final String remote;

  /// Uncommitted changes here, which the Mac will not see.
  final int changedFiles;

  /// Whether a remote branch this machine knows of contains [commit]. Based on
  /// the last fetch, so a hint rather than proof; the Mac has the last word.
  final bool pushed;

  String get shortCommit => commit.length > 7 ? commit.substring(0, 7) : commit;

  Map<String, Object?> toJson() => {
    'commit': commit,
    'branch': branch,
    'remote': remote,
  };
}

class RemoteIosReleaseException implements Exception {
  const RemoteIosReleaseException(
    this.message, {
    this.definitive = false,
    this.connectionLost = false,
  });

  final String message;

  /// The relay refused outright; retrying the same request will not help.
  final bool definitive;

  /// The relay stopped answering while a step was being followed.
  final bool connectionLost;

  @override
  String toString() => message;
}

class _RelayUnavailable implements Exception {
  const _RelayUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

String _text(Object? value) => value?.toString().trim() ?? '';

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};
