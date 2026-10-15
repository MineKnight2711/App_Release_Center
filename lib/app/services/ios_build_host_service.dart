import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_management_center/app/models/app_store_credentials.dart';
import 'package:app_management_center/app/models/app_store_project.dart';
import 'package:app_management_center/app/models/ios_release.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/ios_build_envelope.dart';
import 'package:app_management_center/app/services/ios_release_workflow_service.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Runs iOS release steps on this Mac for a desktop paired through the relay.
///
/// Each step is the same [IosReleaseWorkflowService] call the local dialog
/// makes; what this adds is getting there from a sealed envelope. The source
/// comes from the commit the sender names, checked out into a workspace this
/// service owns, so a build always matches a commit that exists on origin.
/// Gitignored files the project needs ride along in the envelope.
///
/// Its workflow keeps its own run history, apart from the Mac's own releases.
class IosBuildHostService {
  IosBuildHostService({
    required this.runner,
    SecureKeyValueStore? secureStore,
    IosReleaseWorkflowService? workflow,
    Directory? root,
    Directory? workspaces,
    bool Function()? isMacOS,
    DateTime Function()? now,
    @visibleForTesting this.allowLocalRemotes = false,
  }) : _secureStore = secureStore ?? SecureKeyValueStore.platform(),
       _workflow = workflow,
       _root = root,
       _workspaces = workspaces,
       _isMacOS = isMacOS ?? (() => Platform.isMacOS),
       _now = now ?? DateTime.now;

  final ReleaseRunnerService runner;
  final SecureKeyValueStore _secureStore;
  IosReleaseWorkflowService? _workflow;
  Directory? _root;
  Directory? _workspaces;
  final bool Function() _isMacOS;
  final DateTime Function() _now;

  /// Lets tests clone from a path on disk. Never set in the app: a remote
  /// such as `ext::sh -c …` would run a command.
  final bool allowLocalRemotes;

  final _credentials = <String, AppStoreCredentials>{};
  SimpleKeyPair? _keyPair;
  String? _xcode;
  bool _canceled = false;
  String? _activeProjectId;
  String _activeRunId = '';
  DateTime? _activeSince;

  static const _seedKey = 'ios_build_host.x25519_seed';

  /// Total size of the files one envelope may write into a workspace.
  static const maxFileBytes = 256 * 1024;

  Future<Directory> get root async => (_root ??= Directory(
    p.join((await getApplicationSupportDirectory()).path, 'ios_build_host'),
  )).create(recursive: true);

  /// Where checkouts live. Under the home folder rather than application
  /// support so a person can open one in Xcode when a build needs a look.
  Future<Directory> get workspaces async => _workspaces ??= Directory(
    p.join(
      Platform.environment['HOME'] ?? (await root).path,
      'AMC',
      'ios-workspaces',
    ),
  );

  Future<IosReleaseWorkflowService> get workflow async =>
      _workflow ??= IosReleaseWorkflowService(
        runner: runner,
        credentials: _credentialFor,
        root: Directory(p.join((await root).path, 'runs')),
        isMacOS: _isMacOS,
      );

  Future<AppStoreCredentials> _credentialFor(String projectId) async =>
      _credentials[projectId] ?? const AppStoreCredentials();

  Future<SimpleKeyPair> _hostKey() async {
    final cached = _keyPair;
    if (cached != null) return cached;
    final stored = (await _secureStore.read(key: _seedKey))?.trim() ?? '';
    final List<int> seed;
    if (stored.isNotEmpty) {
      seed = base64.decode(stored);
    } else {
      final random = Random.secure();
      seed = List<int>.generate(32, (_) => random.nextInt(256));
      await _secureStore.write(key: _seedKey, value: base64.encode(seed));
    }
    return _keyPair = await X25519().newKeyPairFromSeed(seed);
  }

  Future<List<int>> publicKey() async =>
      (await (await _hostKey()).extractPublicKey()).bytes;

  /// What the person pairing a desktop compares on both screens.
  Future<String> fingerprint() async =>
      IosBuildEnvelope.fingerprint(await publicKey());

  /// What the heartbeat says about this host. The public key is what a
  /// controlling desktop seals to; the fingerprint is what a person compares.
  Future<Map<String, Object?>> heartbeat({required bool enabled}) async {
    if (!enabled || !_isMacOS()) return const {'enabled': false};
    final key = await publicKey();
    return {
      'enabled': true,
      'publicKey': base64.encode(key),
      'fingerprint': await IosBuildEnvelope.fingerprint(key),
      'xcode': _xcode ??= await _readXcode(),
    };
  }

  Future<String> _readXcode() async {
    try {
      final result = await Process.run('/usr/bin/xcodebuild', ['-version']);
      if (result.exitCode != 0) return '';
      return result.stdout.toString().trim().split('\n').first.trim();
    } catch (_) {
      return '';
    }
  }

  /// The run the step in progress is moving, for the periodic progress report.
  /// Null until that run exists, so a stale run from an earlier step is never
  /// reported as this one.
  Map<String, Object?>? get liveResult {
    final run = _workflow?.current.value;
    final since = _activeSince;
    if (run == null || since == null || run.project.id != _activeProjectId) {
      return null;
    }
    final matches = _activeRunId.isEmpty
        ? !run.createdAt.isBefore(since)
        : run.id == _activeRunId;
    return matches ? {'run': _wire(run)} : null;
  }

  Future<void> cancel() async {
    _canceled = true;
    await _workflow?.cancel();
    await runner.stop();
  }

  /// Runs one release-lane step. [desktopId] is this Mac's id on the relay,
  /// which the envelope was sealed against.
  Future<IosHostOutcome> execute({
    required String desktopId,
    required Map<String, Object?> payload,
  }) async {
    if (!_isMacOS()) {
      throw const IosBuildHostException(
        'Máy này không phải macOS nên không build iOS được.',
      );
    }
    _canceled = false;
    final action = _text(payload['action']);
    final runId = _text(payload['runId']);
    final projectId = _text(payload['projectId']);
    final body = await _open(
      desktopId: desktopId,
      action: action,
      runId: runId,
      projectId: projectId,
      envelope: _text(payload['envelope']),
    );
    final projectJson = _map(body['project']);
    if (_text(projectJson['id']) != projectId) {
      throw const IosBuildHostException('Envelope không khớp project.');
    }
    final credentials = _map(body['credentials']);
    _credentials[projectId] = AppStoreCredentials(
      p8PrivateKey: _optional(credentials['p8PrivateKey']),
      keyId: _optional(credentials['keyId']),
      issuerId: _optional(credentials['issuerId']),
      teamId: _optional(credentials['teamId']),
    );
    final service = await workflow;
    await service.load();
    _activeProjectId = projectId;
    _activeRunId = runId;
    _activeSince = _now().subtract(const Duration(seconds: 1));
    try {
      switch (action) {
        case 'prepare':
          final settings = hostSettings(body['settings']);
          final workspace = await _checkout(_map(body['git']), force: true);
          await _writeFiles(workspace, body['files']);
          final existing = body['existingBuild'];
          final run = await service.prepare(
            project: _project(projectJson, workspace),
            settings: settings,
            version: _optional(body['version']),
            existingBuild: existing is Map
                ? IosStoreBuild.fromJson(Map<String, dynamic>.from(existing))
                : null,
          );
          return IosHostOutcome(result: {'run': _wire(run)});
        case 'inspect':
          final settings = hostSettings(body['settings']);
          final git = _map(body['git']);
          final remote = _text(git['remote']);
          final workspace = remote.isEmpty ? '' : await workspaceFor(remote);
          // Fastlane comes from the project's Gemfile when there is a
          // checkout to find it in, from the Mac's own install otherwise.
          final path = workspace.isNotEmpty && Directory(workspace).existsSync()
              ? workspace
              : (await root).path;
          final state = await service.inspect(
            _project(projectJson, path),
            settings,
            _text(body['version']),
          );
          return IosHostOutcome(result: {'store': _storeWire(state)});
      }
      final run = _findRun(service, runId, projectId);
      switch (action) {
        case 'build':
          await _returnTo(run, body['files']);
          await service.build(run);
        case 'continue':
          if (run.ipaPath == null && !run.uploadAttempted) {
            await _returnTo(run, body['files']);
          }
          await service.continueToTestFlight(run);
        case 'upload':
          await service.upload(
            run,
            retryAfterVerification: body['retryAfterVerification'] == true,
          );
        case 'refresh':
          await service.refresh(run);
        case 'wait':
          await service.waitForProcessing(run);
        case 'draft' || 'submit' || 'release' || 'distribute':
          await service.storeAction(run, action);
        default:
          throw IosBuildHostException('Bước iOS không hỗ trợ: $action.');
      }
      return IosHostOutcome(result: {'run': _wire(run)});
    } finally {
      _credentials.remove(projectId);
    }
  }

  /// Answers a control-lane question. Reads only: runs while a build holds
  /// the runner.
  Future<IosHostOutcome> query(Map<String, Object?> payload) async {
    final service = await workflow;
    await service.load();
    final projectId = _text(payload['projectId']);
    switch (_text(payload['action'])) {
      case 'history':
        final runs = service.history
            .where((run) => run.project.id == projectId)
            .take(20)
            .toList();
        final active = service.busy.value ? service.current.value : null;
        return IosHostOutcome(
          result: {
            // App Store state only rides with the newest few; older runs are
            // there to be picked from, and picking one refreshes it.
            'runs': [
              for (var index = 0; index < runs.length; index++)
                index < 3 ? _wire(runs[index]) : runs[index].toJson(),
            ],
            'busy': service.busy.value || runner.isBusy,
            'currentRunId': active?.project.id == projectId ? active!.id : null,
          },
        );
      case 'log':
        final run = _findRun(service, _text(payload['runId']), projectId);
        return IosHostOutcome(
          result: const {},
          logLines: await service.savedLog(run, lines: 400),
        );
      default:
        throw IosBuildHostException(
          'Câu hỏi iOS không hỗ trợ: ${payload['action']}.',
        );
    }
  }

  /// Settings as the sender saved them, minus what only means something on
  /// the sender's machine.
  static IosReleaseSettings hostSettings(Object? raw) {
    final settings = IosReleaseSettings.fromJson(
      Map<String, dynamic>.from(_map(raw)),
    );
    final export = settings.exportOptionsPath;
    if (export.isNotEmpty &&
        IosReleaseWorkflowService.remoteFilePath(export) == null) {
      throw const IosBuildHostException(
        'Khi build trên Mac, ExportOptions plist phải là đường dẫn tương đối '
        'trong project.',
      );
    }
    // The sender's Flutter path names a binary on another machine.
    return IosReleaseSettings.fromJson({
      ...settings.toJson(),
      'flutterExecutable': '',
    });
  }

  /// Remotes a build host may clone. Credentials in the URL and local paths
  /// are refused, and so is anything git would treat as a helper command.
  static bool isAllowedGitRemote(String remote) {
    if (remote.isEmpty ||
        remote.length > 500 ||
        remote.contains(RegExp(r'\s'))) {
      return false;
    }
    return RegExp(r'^https://[^/@]+/.+').hasMatch(remote) ||
        RegExp(
          r'^ssh://([A-Za-z0-9._-]+@)?[A-Za-z0-9.-]+(:\d+)?/.+',
        ).hasMatch(remote) ||
        RegExp(r'^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[^/].*').hasMatch(remote);
  }

  static String normalizeGitRemote(String remote) => remote
      .trim()
      .replaceFirst(RegExp(r'/+$'), '')
      .replaceFirst(RegExp(r'\.git$'), '');

  /// One workspace per repository, named so a person can tell them apart.
  Future<String> workspaceFor(String remote) async {
    final normalized = normalizeGitRemote(remote);
    final name = normalized
        .split(RegExp(r'[/:\\]'))
        .where((part) => part.isNotEmpty)
        .lastOrNull;
    final slug = (name ?? 'project').replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final digest = (await Sha256().hash(utf8.encode(normalized))).bytes
        .take(4)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return p.join((await workspaces).path, '$slug-$digest');
  }

  Future<Map<String, Object?>> _open({
    required String desktopId,
    required String action,
    required String runId,
    required String projectId,
    required String envelope,
  }) async {
    if (envelope.isEmpty) {
      throw const IosBuildHostException('Lệnh iOS thiếu envelope.');
    }
    final Map<String, Object?> body;
    try {
      body = await IosBuildEnvelope.open(
        hostKeyPair: await _hostKey(),
        envelope: envelope,
        associatedData: IosBuildEnvelope.associatedData(
          desktopId: desktopId,
          action: action,
          runId: runId,
          projectId: projectId,
        ),
      );
    } on FormatException catch (error) {
      throw IosBuildHostException(
        '${error.message} Nếu Mac vừa cài lại AMC, ghép lại máy điều khiển.',
      );
    }
    final id = _text(body['id']);
    final expires = DateTime.tryParse(_text(body['exp']));
    if (id.isEmpty || expires == null) {
      throw const IosBuildHostException('Envelope thiếu id hoặc hạn dùng.');
    }
    if (expires.isBefore(_now())) {
      throw const IosBuildHostException(
        'Lệnh iOS đã quá hạn khi tới Mac. Gửi lại từ máy điều khiển.',
      );
    }
    await _rememberEnvelope(id, expires);
    return body;
  }

  /// Refuses an envelope seen before. The relay keeps every command it
  /// carried, so without this one sealed "submit" could be queued again.
  Future<void> _rememberEnvelope(String id, DateTime expires) async {
    final file = File(p.join((await root).path, 'seen_envelopes.json'));
    final seen = <String, String>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final until = DateTime.tryParse(entry.value.toString());
            if (until != null && until.isAfter(_now())) {
              seen[entry.key.toString()] = entry.value.toString();
            }
          }
        }
      } catch (_) {
        /* A damaged file only forgets ids that have mostly expired. */
      }
    }
    if (seen.containsKey(id)) {
      throw const IosBuildHostException('Lệnh iOS này đã được chạy một lần.');
    }
    seen[id] = expires.toUtc().toIso8601String();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(seen));
    await temp.rename(file.path);
  }

  /// Puts the workspace for [git] at its commit and returns its path.
  ///
  /// [force] resets it even when it is already there: a new release must
  /// build the commit and nothing an earlier build left behind.
  Future<String> _checkout(
    Map<String, Object?> git, {
    required bool force,
  }) async {
    final remote = _text(git['remote']);
    final commit = _text(git['commit']).toLowerCase();
    if (!isAllowedGitRemote(remote) &&
        !(allowLocalRemotes && p.isAbsolute(remote))) {
      throw IosBuildHostException(
        'Remote git không dùng được để build trên Mac: "$remote". Cần origin '
        'dạng https:// hoặc SSH, không kèm mật khẩu/token.',
      );
    }
    if (!RegExp(r'^[0-9a-f]{40}(?:[0-9a-f]{24})?$').hasMatch(commit)) {
      throw const IosBuildHostException('Commit gửi sang Mac không hợp lệ.');
    }
    final directory = await workspaceFor(remote);
    if (!Directory(p.join(directory, '.git')).existsSync()) {
      final folder = Directory(directory);
      if (folder.existsSync() && folder.listSync().isNotEmpty) {
        throw IosBuildHostException(
          'Thư mục $directory đã có dữ liệu nhưng không phải git checkout.',
        );
      }
      await folder.parent.create(recursive: true);
      runner.appendSystemLog('Clone $remote vào $directory');
      await _git(folder.parent.path, [
        'clone',
        '--no-checkout',
        '--',
        remote,
        directory,
      ]);
    } else {
      final origin = await _gitRead(directory, ['remote', 'get-url', 'origin']);
      if (normalizeGitRemote(origin ?? '') != normalizeGitRemote(remote)) {
        throw IosBuildHostException(
          'Workspace $directory đang trỏ tới "${origin ?? '-'}", không phải '
          '"$remote". Đổi tên hoặc xoá thư mục đó rồi chạy lại.',
        );
      }
    }
    if (!await _hasCommit(directory, commit)) {
      await _git(directory, ['fetch', '--prune', 'origin']);
      if (!await _hasCommit(directory, commit)) {
        // Hosts that allow it can serve a commit no branch points at.
        await _git(directory, ['fetch', 'origin', commit], allowFailure: true);
      }
      if (!await _hasCommit(directory, commit)) {
        throw IosBuildHostException(
          'Commit ${commit.substring(0, 7)} chưa có trên origin. Push commit '
          'từ máy điều khiển rồi thử lại.',
        );
      }
    }
    await _moveTo(directory, commit, force: force);
    return directory;
  }

  /// Brings a prepared run's workspace back to its commit if another release
  /// moved it, and rewrites the files sent along.
  ///
  /// Left alone when already there, so what preflight did to it — `pub get`
  /// refreshing a lock file — stays exactly as the run's source hash saw it.
  Future<void> _returnTo(IosReleaseRun run, Object? files) async {
    await _moveTo(run.project.path, run.commit, force: false);
    await _writeFiles(run.project.path, files);
  }

  Future<void> _moveTo(
    String directory,
    String commit, {
    required bool force,
  }) async {
    final head = await _gitRead(directory, ['rev-parse', 'HEAD']);
    if (!force && head == commit) return;
    await _git(directory, ['checkout', '--force', '--detach', commit]);
    // Untracked files go; ignored ones (.env, Pods, build caches) stay.
    await _git(directory, ['clean', '-fd']);
    if (File(p.join(directory, '.gitmodules')).existsSync()) {
      await _git(directory, ['submodule', 'update', '--init', '--recursive']);
    }
  }

  Future<void> _writeFiles(String directory, Object? files) async {
    if (files is! List) return;
    var total = 0;
    final rootReal = await Directory(directory).resolveSymbolicLinks();
    for (final entry in files.whereType<Map>()) {
      final relative = IosReleaseWorkflowService.remoteFilePath(
        _text(entry['path']),
      );
      if (relative == null) {
        throw IosBuildHostException(
          'Đường dẫn file gửi kèm không hợp lệ: ${entry['path']}',
        );
      }
      final List<int> bytes;
      try {
        bytes = base64.decode(_text(entry['data']));
      } on FormatException {
        throw IosBuildHostException('File gửi kèm hỏng: $relative');
      }
      total += bytes.length;
      if (total > maxFileBytes) {
        throw const IosBuildHostException(
          'File gửi kèm vượt 256 KB. Chỉ gửi file cấu hình nhỏ.',
        );
      }
      // A tracked file would make the build differ from the commit it names.
      final ignored = await Process.run('git', [
        'check-ignore',
        '-q',
        '--',
        relative,
      ], workingDirectory: directory);
      if (ignored.exitCode != 0) {
        throw IosBuildHostException(
          'File gửi kèm phải nằm trong .gitignore và không được track: '
          '$relative',
        );
      }
      final file = File(p.joinAll([directory, ...relative.split('/')]));
      await file.parent.create(recursive: true);
      final parentReal = await file.parent.resolveSymbolicLinks();
      if (parentReal != rootReal && !p.isWithin(rootReal, parentReal)) {
        throw IosBuildHostException(
          'File gửi kèm trỏ ra ngoài workspace: $relative',
        );
      }
      if (await FileSystemEntity.isLink(file.path)) {
        throw IosBuildHostException('File gửi kèm là symlink: $relative');
      }
      await file.writeAsBytes(bytes, flush: true);
      runner.appendSystemLog('Đã ghi file gửi kèm: $relative');
    }
  }

  Future<String> _git(
    String directory,
    List<String> arguments, {
    bool allowFailure = false,
  }) async {
    _checkCanceled();
    final result = await runner.runCommandWithOutput(
      workingDirectory: directory,
      statusLabel: 'git ${arguments.first}',
      activePath: 'ios-build-host',
      executable: 'git',
      arguments: arguments,
      environment: _gitEnvironment,
      allowDuringWorkflow: true,
      trackWorkflowStep: false,
    );
    _checkCanceled();
    if (result.exitCode != 0 && !allowFailure) {
      throw IosBuildHostException(
        'git ${arguments.first} lỗi (exit ${result.exitCode}). Xem log để '
        'biết chi tiết; Mac cần quyền đọc repo (SSH key hoặc credential '
        'helper).',
      );
    }
    return result.output;
  }

  /// A short read that does not belong in the log.
  Future<String?> _gitRead(String directory, List<String> arguments) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: directory,
      environment: _gitEnvironment,
    );
    return result.exitCode == 0 ? result.stdout.toString().trim() : null;
  }

  Future<bool> _hasCommit(String directory, String commit) async {
    final result = await Process.run('git', [
      'cat-file',
      '-e',
      '$commit^{commit}',
    ], workingDirectory: directory);
    return result.exitCode == 0;
  }

  /// Nobody is at the Mac to answer a prompt, so git must fail instead of
  /// waiting for a password forever.
  static Map<String, String> get _gitEnvironment => {
    'GIT_TERMINAL_PROMPT': '0',
    if (!Platform.environment.containsKey('GIT_SSH_COMMAND'))
      'GIT_SSH_COMMAND': 'ssh -o BatchMode=yes',
  };

  void _checkCanceled() {
    if (_canceled) throw const IosBuildHostException('Đã hủy luồng iOS.');
  }

  IosReleaseRun _findRun(
    IosReleaseWorkflowService service,
    String runId,
    String projectId,
  ) {
    final run = service.history.where((entry) => entry.id == runId).firstOrNull;
    if (run == null) {
      throw IosBuildHostException('Mac không có run $runId.');
    }
    if (run.project.id != projectId) {
      throw IosBuildHostException('Run $runId không thuộc project này.');
    }
    return run;
  }

  AppStoreProject _project(Map<String, Object?> json, String path) =>
      AppStoreProject(
        id: _text(json['id']),
        path: path,
        displayName: _text(json['displayName']),
        bundleId: _text(json['bundleId']),
      );

  /// The relay keeps results under a size limit; a long build list is cut to
  /// the newest builds, which are the ones a release is choosing between.
  static Map<String, dynamic> _wire(IosReleaseRun run) => {
    ...iosRunToWire(run),
    'store': _storeWire(run.store),
  };

  static Map<String, dynamic> _storeWire(IosStoreState state) => IosStoreState(
    primaryLocale: state.primaryLocale,
    builds: (state.builds.toList()..sort((a, b) => b.number - a.number))
        .take(80)
        .toList(),
    versions: state.versions.take(10).toList(),
  ).toJson();
}

class IosHostOutcome {
  const IosHostOutcome({required this.result, this.logLines = const []});

  final Map<String, Object?> result;
  final List<String> logLines;
}

class IosBuildHostException implements Exception {
  const IosBuildHostException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _text(Object? value) => value?.toString().trim() ?? '';

String? _optional(Object? value) {
  final text = _text(value);
  return text.isEmpty ? null : text;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};
