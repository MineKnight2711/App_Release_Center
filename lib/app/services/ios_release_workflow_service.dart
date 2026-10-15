import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_management_center/app/models/app_store_credentials.dart';
import 'package:app_management_center/app/models/app_store_project.dart';
import 'package:app_management_center/app/models/ios_release.dart';
import 'package:app_management_center/app/services/app_store_project_inspector_service.dart';
import 'package:app_management_center/app/services/ios_release_backend.dart';
import 'package:app_management_center/app/services/ios_release_fastfile.dart';
import 'package:app_management_center/app/services/ios_release_script.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class IosReleaseWorkflowService implements IosReleaseBackend {
  IosReleaseWorkflowService({
    required this.runner,
    required this.credentials,
    Directory? root,
    bool Function()? isMacOS,
    this.pollInterval = const Duration(seconds: 20),
    this.processingTimeout = const Duration(minutes: 10),
  }) : _root = root,
       _customRoot = root != null,
       _isMacOS = isMacOS ?? (() => Platform.isMacOS);
  final ReleaseRunnerService runner;
  final Future<AppStoreCredentials> Function(String) credentials;
  Directory? _root;
  final bool _customRoot;
  final bool Function() _isMacOS;
  final Duration pollInterval, processingTimeout;
  @override
  final current = Rxn<IosReleaseRun>();
  @override
  final history = <IosReleaseRun>[].obs;
  @override
  final busy = false.obs;
  bool _canceled = false;
  IosReleaseRun? _loggingRun;
  String? _privateKey;
  Future<void>? _loading;

  Future<Directory> get root async => _root ??= await Directory(
    p.join((await getApplicationSupportDirectory()).path, 'ios_releases'),
  ).create(recursive: true);

  @override
  RxList<String> get liveLog => runner.logLines;

  @override
  bool get usesLocalRunner => true;

  /// Whether this machine has what a build needs. Off macOS a release has to
  /// go to a Mac build host instead.
  bool get canBuildHere => _isMacOS();

  @override
  Future<void> load([AppStoreProject? project]) => _loading ??= _load();
  Future<void> _load() async {
    final directory = await root;
    await directory.create(recursive: true);
    final runs = <IosReleaseRun>[];
    await for (final entity in directory.list()) {
      if (entity is! Directory) continue;
      final file = File(p.join(entity.path, 'manifest.json'));
      if (!await file.exists()) continue;
      try {
        final run = IosReleaseRun.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
        if ([
          IosReleaseStatus.building,
          IosReleaseStatus.uploading,
        ].contains(run.status)) {
          run.status = IosReleaseStatus.verificationRequired;
          run.message =
              'Lần chạy bị gián đoạn. Kiểm tra Apple trước khi tiếp tục.';
        }
        runs.add(run);
      } catch (_) {
        /* An incomplete manifest must not hide other runs. */
      }
    }
    runs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    history.assignAll(runs);
  }

  Future<IosReleaseSettings> readSettings(AppStoreProject project) async {
    final file = await _settingsFile(project.id);
    if (!await file.exists()) {
      final pbx = File(
        p.join(project.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
      );
      if (await pbx.exists()) {
        final teams = RegExp(r'DEVELOPMENT_TEAM\s*=\s*"?([A-Z0-9]+)"?;')
            .allMatches(await pbx.readAsString())
            .map((match) => match.group(1)!)
            .toSet();
        if (teams.length == 1) return IosReleaseSettings(teamId: teams.single);
      }
      return const IosReleaseSettings();
    }
    return IosReleaseSettings.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<void> saveSettings(
    AppStoreProject project,
    IosReleaseSettings settings,
  ) async {
    validateSettings(settings);
    await (await _settingsFile(
      project.id,
    )).writeAsString(jsonEncode(settings.toJson()));
  }

  Future<File> _settingsFile(String id) async {
    final directory = await Directory(
      p.join((await root).path, 'settings'),
    ).create(recursive: true);
    return File(
      p.join(directory.path, '${base64Url.encode(utf8.encode(id))}.json'),
    );
  }

  static void validateSettings(IosReleaseSettings settings) {
    if (settings.scheme.trim().isEmpty ||
        settings.configuration.trim().isEmpty ||
        settings.entrypoint.trim().isEmpty) {
      throw const FormatException(
        'Phải nhập scheme, configuration và entrypoint.',
      );
    }
    if (!settings.useAppStoreLocale &&
        !RegExp(r'^[a-z]{2,3}(?:-[A-Za-z0-9]+)*$').hasMatch(settings.locale)) {
      throw const FormatException('Locale không hợp lệ (ví dụ en-US hoặc vi).');
    }
    // AMC owns version, export and entrypoint. Additional flags cannot change
    // the identity of the artifact after the release preview is accepted.
    const reserved = [
      '--build-name',
      '--build-number',
      '--export-options-plist',
      '--export-method',
      '--flavor',
      '--target',
      '-t',
      '--debug',
      '--profile',
      '--no-codesign',
      '--config-only',
      '--release',
    ];
    if (settings.extraBuildArguments.any(
      (arg) =>
          !arg.startsWith('--') ||
          reserved.any((flag) => arg == flag || arg.startsWith('$flag=')),
    )) {
      throw const FormatException(
        'Build arguments bổ sung phải dạng --flag=value, không ghi đè version, flavor, target hoặc signing.',
      );
    }
    for (final file in settings.remoteFiles) {
      if (remoteFilePath(file) == null) {
        throw FormatException(
          'File gửi kèm phải là đường dẫn tương đối trong project: $file',
        );
      }
    }
    final effectiveConfiguration = settings.flavor.isEmpty
        ? 'Release'
        : 'Release-${settings.flavor}';
    if (settings.configuration != effectiveConfiguration ||
        (settings.flavor.isEmpty && settings.scheme != 'Runner') ||
        (settings.flavor.isNotEmpty && settings.scheme != settings.flavor)) {
      throw const FormatException(
        'Flutter IPA dùng Runner/Release hoặc scheme=flavor và configuration=Release-<flavor>.',
      );
    }
  }

  /// [path] as a forward-slash path inside the project, or null when it could
  /// land outside it or inside `.git`. Checked on both ends of a remote build:
  /// the host writes whatever it is sent, so it cannot trust the sender's check.
  static String? remoteFilePath(String path) {
    final slashed = path.trim().replaceAll(r'\', '/');
    if (slashed.isEmpty ||
        slashed.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(slashed) ||
        slashed.split('/').contains('..')) {
      return null;
    }
    final normalized = p.posix.normalize(slashed);
    if (normalized == '.' ||
        normalized.split('/').first == '.git' ||
        normalized.endsWith('/')) {
      return null;
    }
    return normalized;
  }

  static int proposedBuild(int local, Iterable<IosStoreBuild> builds) =>
      math.max(
        local,
        builds.fold<int>(0, (value, build) => math.max(value, build.number)) +
            1,
      );

  static IosStoreState parseStoreState(String output) {
    final markers = RegExp(r'AMC_IOS_RESULT:(\{[^\r\n]*\})').allMatches(output);
    if (markers.isEmpty) {
      throw StateError('Fastlane không trả về trạng thái iOS.');
    }
    return IosStoreState.fromJson(
      jsonDecode(markers.last.group(1)!) as Map<String, dynamic>,
    );
  }

  static List<Map<String, dynamic>> parseBuildSettings(String output) {
    for (final start in RegExp(r'\[\s*\{').allMatches(output)) {
      var depth = 0;
      var quoted = false, escaped = false;
      for (var index = start.start; index < output.length; index++) {
        final char = output[index];
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (char == r'\') {
            escaped = true;
          } else if (char == '"') {
            quoted = false;
          }
          continue;
        }
        if (char == '"') {
          quoted = true;
        } else if (char == '[') {
          depth++;
        } else if (char == ']') {
          depth--;
          if (depth == 0) {
            try {
              final list =
                  jsonDecode(output.substring(start.start, index + 1)) as List;
              if (list.isNotEmpty &&
                  list.every(
                    (entry) => entry is Map && entry['buildSettings'] is Map,
                  )) {
                return list
                    .map((entry) => Map<String, dynamic>.from(entry as Map))
                    .toList();
              }
            } on FormatException {
              /* Xcode warning text can contain brackets. */
            }
            break;
          }
        }
      }
    }
    throw StateError(
      'Xcode không trả về build settings JSON. Xem log để kiểm tra scheme/dependencies.',
    );
  }

  @override
  Future<IosReleaseRun> prepare({
    required AppStoreProject project,
    required IosReleaseSettings settings,
    String? version,
    IosStoreBuild? existingBuild,
  }) async {
    IosReleaseRun? prepared;
    await _guard(null, 'prepare', () async {
      validateSettings(settings);
      final credential = await _credential(project);
      if (!Directory(p.join(project.path, 'ios')).existsSync()) {
        throw StateError('Dự án không có thư mục ios.');
      }
      final local = await AppStoreProjectInspectorService().readLocalVersion(
        project.path,
      );
      if (local == null) {
        throw StateError('pubspec.yaml cần version dạng name+build.');
      }
      final releaseVersion =
          existingBuild?.version ??
          (version?.trim().isNotEmpty == true ? version!.trim() : local.name);
      if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(releaseVersion)) {
        throw StateError('Version cần dạng 1.2.3.');
      }
      final team = settings.teamId.trim().isNotEmpty
          ? settings.teamId.trim()
          : credential.teamId?.trim() ?? '';
      if (team.isEmpty) {
        throw StateError('Phải cấu hình Team ID cho release iOS.');
      }
      final effective = IosReleaseSettings.fromJson({
        ...settings.toJson(),
        'teamId': team,
      });
      final git = await _command(project.path, 'git', ['rev-parse', 'HEAD']);
      final dirty = await _command(project.path, 'git', [
        'status',
        '--porcelain',
      ]);
      final directory = await Directory(
        p.join((await root).path, '${DateTime.now().microsecondsSinceEpoch}'),
      ).create(recursive: true);
      final run = IosReleaseRun(
        id: p.basename(directory.path),
        project: project,
        settings: effective,
        version: releaseVersion,
        buildNumber: existingBuild?.number ?? local.buildNumber,
        directory: directory.path,
        commit: git.output.trim(),
        dirty: dirty.output.trim().isNotEmpty,
        createdAt: DateTime.now(),
      );
      final state = await _apple(run, 'query');
      if (existingBuild != null &&
          state.findBuild(releaseVersion, existingBuild.number)?.isReady !=
              true) {
        throw StateError(
          'Build đã chọn chưa sẵn sàng hoặc không thuộc app/version này.',
        );
      }
      final result = IosReleaseRun(
        id: run.id,
        project: project,
        settings: effective,
        version: releaseVersion,
        buildNumber:
            existingBuild?.number ??
            proposedBuild(local.buildNumber, state.builds),
        directory: directory.path,
        commit: run.commit,
        dirty: run.dirty,
        createdAt: run.createdAt,
        status: existingBuild == null
            ? IosReleaseStatus.prepared
            : IosReleaseStatus.ready,
        store: state,
        uploadAttempted: existingBuild != null,
      );
      current.value = result;
      _loggingRun = result;
      await _save(result);
      if (existingBuild == null) {
        try {
          await _preflight(result);
          result.sourceHash = await _sourceHash(result);
          result.dirty = (await _command(project.path, 'git', [
            'status',
            '--porcelain',
          ])).output.trim().isNotEmpty;
        } catch (error) {
          await _status(result, IosReleaseStatus.failed, error.toString());
          rethrow;
        }
      }
      result.message = existingBuild == null
          ? 'Sẵn sàng build ${result.version}+${result.buildNumber}.'
          : 'Dùng build TestFlight ${result.version}+${result.buildNumber}.';
      await _save(result);
      await saveSettings(project, settings);
      prepared = result;
    });
    return prepared!;
  }

  @override
  Future<IosStoreState> inspect(
    AppStoreProject project,
    IosReleaseSettings settings,
    String version,
  ) async {
    IosStoreState? result;
    await _guard(null, 'query', () async {
      final temp = await Directory.systemTemp.createTemp('amc_ios_query_');
      try {
        result = await _apple(
          IosReleaseRun(
            id: 'query',
            project: project,
            settings: settings,
            version: version,
            buildNumber: 0,
            directory: temp.path,
            commit: '',
            dirty: false,
            createdAt: DateTime.now(),
          ),
          'query',
        );
      } finally {
        await temp.delete(recursive: true);
      }
    });
    return result!;
  }

  Future<void> _preflight(IosReleaseRun run) async {
    final project = run.project;
    final settings = run.settings;
    await _command(project.path, '/usr/bin/xcodebuild', ['-version']);
    await _command(project.path, _flutter(run), ['pub', 'get']);
    // Flutter can migrate the Xcode project/scheme and resolve Pods/Swift
    // packages. Do that before freezing the source, rather than during IPA
    // archiving where those tool-owned edits look like concurrent source edits.
    await _command(project.path, _flutter(run), [
      'build',
      'ios',
      '--config-only',
      ..._flutterBuildArguments(run),
    ]);
    final identity = await _command(project.path, '/usr/bin/security', [
      'find-identity',
      '-v',
      '-p',
      'codesigning',
    ]);
    if (!RegExp(
      r'"(?:Apple Distribution|iPhone Distribution):',
    ).hasMatch(identity.output)) {
      throw StateError(
        'Keychain chưa có Apple Distribution certificate kèm private key.',
      );
    }
    final workspace = p.join(project.path, 'ios', 'Runner.xcworkspace');
    final result = await _command(project.path, '/usr/bin/xcodebuild', [
      '-workspace',
      workspace,
      '-scheme',
      settings.scheme,
      '-configuration',
      settings.configuration,
      '-showBuildSettings',
      '-json',
    ]);
    final entries = parseBuildSettings(result.output);
    final applications = entries
        .where(
          (entry) =>
              (entry['buildSettings'] as Map)['PRODUCT_TYPE'] ==
              'com.apple.product-type.application',
        )
        .toList();
    if (applications.length != 1) {
      throw StateError('Scheme cần đúng một app target.');
    }
    final buildSettings = applications.single['buildSettings'] as Map;
    if (buildSettings['PRODUCT_BUNDLE_IDENTIFIER'] != project.bundleId ||
        buildSettings['DEVELOPMENT_TEAM'] != settings.teamId) {
      throw StateError(
        'Bundle ID/Team ID của scheme không khớp project đã chọn.',
      );
    }
    if (!File(p.join(project.path, settings.entrypoint)).existsSync()) {
      throw StateError('Entrypoint không tồn tại.');
    }
    if (settings.exportOptionsPath.isNotEmpty &&
        !File(_exportPath(run)).existsSync()) {
      throw StateError('ExportOptions plist không tồn tại.');
    }
  }

  Future<({String source, String updated, String oldVersion})> versionPreview(
    IosReleaseRun run,
  ) async {
    final source = await File(
      p.join(run.project.path, 'pubspec.yaml'),
    ).readAsString();
    final matches = RegExp(
      r'^(\s*version:\s*)([^\s]+)([^\n]*)$',
      multiLine: true,
    ).allMatches(source).toList();
    if (matches.length != 1) {
      throw StateError('pubspec.yaml cần đúng một dòng version.');
    }
    final match = matches.single;
    return (
      source: source,
      oldVersion: match.group(2)!,
      updated: source.replaceRange(
        match.start,
        match.end,
        '${match.group(1)}${run.version}+${run.buildNumber}${match.group(3)}',
      ),
    );
  }

  Future<void> writeVersion(
    IosReleaseRun run, {
    bool commit = false,
    bool push = false,
  }) => _guard(run, 'version', () async {
    if (run.uploadAttempted) {
      throw StateError('Không sửa source của build đã thử upload.');
    }
    if (run.ipaPath != null) {
      throw StateError(
        'Ghi version trước khi build IPA; hoặc chuẩn bị một release mới.',
      );
    }
    if (push && !commit) throw StateError('Phải chọn commit trước khi push.');
    if (run.sourceHash != null && await _sourceHash(run) != run.sourceHash) {
      throw StateError(
        'Source đã đổi; chuẩn bị lại release trước khi ghi version.',
      );
    }
    if (commit) {
      final status = await _command(run.project.path, 'git', [
        'status',
        '--porcelain',
        '--',
        'pubspec.yaml',
      ]);
      if (status.output.trim().isNotEmpty) {
        throw StateError(
          'pubspec.yaml có thay đổi chưa commit. Commit riêng các thay đổi đó trước khi AMC commit version.',
        );
      }
      final branch = await _command(run.project.path, 'git', [
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ]);
      if (branch.output.trim() == 'HEAD') {
        throw StateError('Không commit release tại detached HEAD.');
      }
      if (push) {
        await _command(run.project.path, 'git', [
          'remote',
          'get-url',
          'origin',
        ]);
      }
    }
    final preview = await versionPreview(run);
    await File(
      p.join(run.project.path, 'pubspec.yaml'),
    ).writeAsString(preview.updated);
    run.sourceHash = await _sourceHash(run);
    await _save(run);
    if (commit && preview.source != preview.updated) {
      await _command(run.project.path, 'git', [
        'commit',
        '--only',
        '-m',
        'Release iOS ${run.version}+${run.buildNumber}',
        '--',
        'pubspec.yaml',
      ]);
      run.commit = (await _command(run.project.path, 'git', [
        'rev-parse',
        'HEAD',
      ])).output.trim();
      await _save(run);
    }
    if (push) {
      final branch = (await _command(run.project.path, 'git', [
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ])).output.trim();
      await _command(run.project.path, 'git', ['push', 'origin', branch]);
    }
    run.dirty = (await _command(run.project.path, 'git', [
      'status',
      '--porcelain',
    ])).output.trim().isNotEmpty;
    await _save(run);
  });

  @override
  Future<void> build(IosReleaseRun run) => _guard(run, 'build', () async {
    if (run.uploadAttempted) {
      throw StateError(
        'Build này đã thử upload. Tạo release mới để build lại.',
      );
    }
    final commit = await _command(run.project.path, 'git', [
      'rev-parse',
      'HEAD',
    ]);
    if (commit.output.trim() != run.commit) {
      throw StateError('Commit đã đổi; chuẩn bị lại release.');
    }
    if (run.sourceHash != null && await _sourceHash(run) != run.sourceHash) {
      throw StateError(
        'Source đã thay đổi từ lúc chuẩn bị. Chuẩn bị lại release trước khi build.',
      );
    }
    await _preflight(run);
    if (run.sourceHash != null && await _sourceHash(run) != run.sourceHash) {
      throw StateError(
        'Cấu hình iOS/dependency đã đổi. Chuẩn bị lại release trước khi build.',
      );
    }
    await _status(run, IosReleaseStatus.building, 'Đang build IPA…');
    final started = DateTime.now().subtract(const Duration(seconds: 2));
    final exportPath = _exportPath(run);
    if (run.settings.exportOptionsPath.isEmpty) {
      await File(exportPath).writeAsString(
        '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>method</key><string>app-store-connect</string><key>teamID</key><string>${_xml(run.settings.teamId)}</string><key>signingStyle</key><string>automatic</string></dict></plist>''',
      );
    }
    await _command(run.project.path, _flutter(run), [
      'build',
      'ipa',
      ..._flutterBuildArguments(run),
      '--export-options-plist=$exportPath',
    ]);
    if (run.sourceHash != null && await _sourceHash(run) != run.sourceHash) {
      throw StateError(
        'Source thay đổi trong lúc build. Chuẩn bị lại release để xác định đúng source.',
      );
    }
    final output = Directory(p.join(run.project.path, 'build', 'ios', 'ipa'));
    final files = output.existsSync()
        ? output
              .listSync()
              .whereType<File>()
              .where(
                (file) =>
                    p.extension(file.path) == '.ipa' &&
                    !file.lastModifiedSync().isBefore(started),
              )
              .toList()
        : <File>[];
    if (files.length != 1) {
      throw StateError('Không tìm thấy đúng một IPA mới từ lần build.');
    }
    final ipa = await files.single.copy(p.join(run.directory, 'app.ipa'));
    run.ipaPath = ipa.path;
    await _verifyIpa(run);
    run.ipaHash = await _hash(ipa);
    final archives = Directory(
      p.join(run.project.path, 'build', 'ios', 'archive'),
    );
    if (archives.existsSync()) {
      final candidates = archives
          .listSync()
          .whereType<Directory>()
          .where((folder) => folder.path.endsWith('.xcarchive'))
          .toList();
      if (candidates.length == 1) {
        final destination = Directory(p.join(run.directory, 'app.xcarchive'));
        if (destination.existsSync()) await destination.delete(recursive: true);
        await _copyDirectory(candidates.single, destination);
        run.archivePath = destination.path;
      }
    }
    await _status(run, IosReleaseStatus.built, 'IPA đã tạo và xác minh.');
  });

  List<String> _flutterBuildArguments(IosReleaseRun run) => [
    '--release',
    '--build-name=${run.version}',
    '--build-number=${run.buildNumber}',
    '--target=${run.settings.entrypoint}',
    if (run.settings.flavor.isNotEmpty) '--flavor=${run.settings.flavor}',
    ...run.settings.extraBuildArguments,
  ];

  Future<void> _verifyIpa(IosReleaseRun run) async {
    final entries = await _command(run.directory, '/usr/bin/unzip', [
      '-Z1',
      run.ipaPath!,
    ]);
    final plists = entries.output
        .split('\n')
        .where(
          (name) => RegExp(r'^Payload/[^/]+\.app/Info\.plist$').hasMatch(name),
        )
        .toList();
    if (plists.length != 1) {
      throw StateError('IPA không có đúng một app chính.');
    }
    final folder = await Directory.systemTemp.createTemp('amc_ipa_metadata_');
    try {
      await _command(run.directory, '/usr/bin/unzip', [
        '-q',
        run.ipaPath!,
        plists.single,
        '-d',
        folder.path,
      ]);
      final result = await _command(run.directory, '/usr/bin/plutil', [
        '-convert',
        'json',
        '-o',
        '-',
        p.join(folder.path, plists.single),
      ]);
      final info = jsonDecode(result.output) as Map;
      if (info['CFBundleIdentifier'] != run.project.bundleId ||
          info['CFBundleShortVersionString'] != run.version ||
          info['CFBundleVersion'].toString() != run.buildNumber.toString()) {
        throw StateError(
          'IPA có Bundle ID/version/build khác bản release đã chuẩn bị.',
        );
      }
    } finally {
      await folder.delete(recursive: true);
    }
  }

  @override
  Future<void> upload(
    IosReleaseRun run, {
    bool retryAfterVerification = false,
  }) => _guard(run, 'upload', () async {
    if (run.ipaPath == null ||
        run.ipaHash == null ||
        !File(run.ipaPath!).existsSync()) {
      throw StateError('Phải build IPA trước.');
    }
    if (await _hash(File(run.ipaPath!)) != run.ipaHash) {
      throw StateError('IPA đã thay đổi; không upload artifact khác.');
    }
    final state = await _apple(run, 'query');
    final existing = state.findBuild(run.version, run.buildNumber);
    if (existing != null) {
      if (!run.uploadAttempted) {
        throw StateError(
          'Build number đã được lần release khác sử dụng trên Apple. Chuẩn bị release mới; hoặc chọn rõ build đó để dùng lại.',
        );
      }
      run.store = state;
      await _updateFromStore(run);
      return;
    }
    if (run.uploadAttempted && !retryAfterVerification) {
      await _status(
        run,
        IosReleaseStatus.verificationRequired,
        'Apple chưa hiển thị build. Chờ/làm mới; chỉ thử upload lại khi đã kiểm tra.',
      );
      return;
    }
    run.uploadAttempted = true;
    await _status(run, IosReleaseStatus.uploading, 'Đang upload IPA…');
    try {
      run.store = await _apple(run, 'upload');
    } catch (_) {
      await _status(
        run,
        IosReleaseStatus.verificationRequired,
        'Upload bị gián đoạn. Kiểm tra trạng thái Apple trước khi thử lại.',
      );
      rethrow;
    }
    await _status(
      run,
      IosReleaseStatus.processing,
      'Đã upload. Apple đang xử lý build.',
    );
  });

  /// Runs what is left before TestFlight: build, upload, then waits for Apple
  /// processing. Each step keeps its own checks and the first failure stops
  /// the chain; an upload Apple has not confirmed is never repeated here.
  @override
  Future<void> continueToTestFlight(IosReleaseRun run) async {
    if (!run.uploadAttempted && run.ipaPath == null) await build(run);
    if (!run.uploadAttempted) await upload(run);
    if (run.status == IosReleaseStatus.processing) {
      await waitForProcessing(run);
    }
  }

  @override
  Future<void> refresh(IosReleaseRun run) => _guard(run, 'query', () async {
    run.store = await _apple(run, 'query');
    await _updateFromStore(run);
  });
  @override
  Future<void> waitForProcessing(
    IosReleaseRun run,
  ) => _guard(run, 'query', () async {
    final deadline = DateTime.now().add(processingTimeout);
    do {
      _checkCanceled();
      run.store = await _apple(run, 'query');
      await _updateFromStore(run);
      if (![
        IosReleaseStatus.processing,
        IosReleaseStatus.verificationRequired,
      ].contains(run.status)) {
        return;
      }
      if (DateTime.now().isAfter(deadline)) return;
      // Short waits allow cancel to take effect even when no process is running.
      final until = DateTime.now().add(pollInterval);
      while (DateTime.now().isBefore(until)) {
        _checkCanceled();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } while (!_canceled);
  });
  Future<void> _updateFromStore(IosReleaseRun run) async {
    final build = run.store.findBuild(run.version, run.buildNumber);
    if (build == null) {
      await _status(
        run,
        run.uploadAttempted
            ? IosReleaseStatus.verificationRequired
            : run.status,
        run.uploadAttempted
            ? 'Chưa thấy build trên Apple. Chờ rồi làm mới, không tự upload lại.'
            : 'Build number chưa có trên Apple.',
      );
      return;
    }
    if (['FAILED', 'INVALID'].contains(build.processingState) ||
        build.expired) {
      await _status(
        run,
        IosReleaseStatus.failed,
        'Build bị Apple từ chối/hết hạn: ${build.processingState}. Chuẩn bị build mới.',
      );
    } else if (build.isReady) {
      final version = run.store.versions
          .where((v) => v['version'] == run.version)
          .firstOrNull;
      final state =
          version != null &&
              version['buildNumber']?.toString() == run.buildNumber.toString()
          ? (version['state']?.toString() ?? '')
          : '';
      final status = switch (state) {
        'READY_FOR_SALE' ||
        'READY_FOR_DISTRIBUTION' => IosReleaseStatus.released,
        'WAITING_FOR_REVIEW' ||
        'IN_REVIEW' ||
        'PENDING_DEVELOPER_RELEASE' ||
        'PENDING_APPLE_RELEASE' => IosReleaseStatus.submitted,
        'PREPARE_FOR_SUBMISSION' =>
          run.status == IosReleaseStatus.draft
              ? IosReleaseStatus.draft
              : IosReleaseStatus.ready,
        _ => IosReleaseStatus.ready,
      };
      await _status(
        run,
        status,
        'TestFlight ${run.version}+${run.buildNumber}: VALID${state.isEmpty ? '' : '. App Store: $state'}.',
      );
    } else {
      await _status(
        run,
        IosReleaseStatus.processing,
        'Apple đang xử lý: ${build.processingState}.',
      );
    }
  }

  @override
  Future<void> storeAction(IosReleaseRun run, String action) => _guard(
    run,
    action,
    () async {
      if (!['draft', 'submit', 'release', 'distribute'].contains(action)) {
        throw ArgumentError.value(action);
      }
      run.store = await _apple(run, 'query');
      if (run.store.findBuild(run.version, run.buildNumber)?.isReady != true) {
        throw StateError('Build đã chọn chưa sẵn sàng.');
      }
      run.store = await _apple(run, action);
      await _status(
        run,
        switch (action) {
          'draft' => IosReleaseStatus.draft,
          'submit' => IosReleaseStatus.submitted,
          'release' => IosReleaseStatus.submitted,
          _ => IosReleaseStatus.ready,
        },
        switch (action) {
          'draft' =>
            'Đã chuẩn bị version App Store và gắn đúng build. Chưa gửi review.',
          'submit' => 'Đã gửi review. Apple sẽ xét duyệt.',
          'release' => 'Đã yêu cầu phát hành. Làm mới để kiểm tra Apple.',
          _ => 'Đã yêu cầu phân phối TestFlight tới nhóm đã chọn.',
        },
      );
    },
  );

  @override
  Future<void> cancel() async {
    _canceled = true;
    await runner.stop();
  }

  @override
  Future<List<String>> savedLog(IosReleaseRun run, {int lines = 600}) async {
    final file = File(p.join(run.directory, 'commands.log'));
    if (!await file.exists()) return const <String>[];
    final all = utf8
        .decode(await file.readAsBytes(), allowMalformed: true)
        .trimRight()
        .split('\n');
    return all.length > lines ? all.sublist(all.length - lines) : all;
  }

  Future<void> _guard(
    IosReleaseRun? run,
    String action,
    Future<void> Function() task,
  ) async {
    if (busy.value || runner.isBusy) {
      throw StateError('Đợi luồng đang chạy kết thúc.');
    }
    if (!_isMacOS()) {
      throw StateError('Release iOS cần chạy trên macOS có Xcode.');
    }
    busy.value = true;
    _canceled = false;
    runner.beginWorkflow(totalSteps: 1, label: 'iOS $action');
    bool succeeded = false;
    bool ownsLock = false;
    RandomAccessFile? lock;
    try {
      if (run != null) {
        final lockRoot = !_customRoot
            ? p.join(Platform.environment['HOME']!, '.amc', 'ios_locks')
            : p.join((await root).path, 'locks');
        await Directory(lockRoot).create(recursive: true);
        final digest = await Sha256().hash(
          utf8.encode('${run.settings.teamId}\n${run.project.bundleId}'),
        );
        final key = digest.bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        lock = await File(
          p.join(lockRoot, '$key.lock'),
        ).open(mode: FileMode.append);
        await lock.lock(FileLock.exclusive);
        ownsLock = true;
        _loggingRun = run;
        current.value = run;
        run.lastAction = action;
        await _save(run);
      }
      await task();
      _checkCanceled();
      succeeded = true;
      if (run != null) {
        run.steps = [
          ...run.steps,
          {
            'action': action,
            'status': 'succeeded',
            'at': DateTime.now().toIso8601String(),
          },
        ];
        await _save(run);
      }
    } catch (error) {
      if (run != null && ownsLock) {
        if (run.status != IosReleaseStatus.verificationRequired || _canceled) {
          run.status = _canceled
              ? IosReleaseStatus.canceled
              : IosReleaseStatus.failed;
        }
        run.message = error.toString();
        run.steps = [
          ...run.steps,
          {
            'action': action,
            'status': _canceled ? 'canceled' : 'failed',
            'at': DateTime.now().toIso8601String(),
            'error': error.toString(),
          },
        ];
        await _save(run);
      }
      rethrow;
    } finally {
      await lock?.close();
      runner.finishWorkflow(success: succeeded);
      busy.value = false;
      _loggingRun = null;
    }
  }

  void _checkCanceled() {
    if (_canceled) throw StateError('Đã hủy luồng iOS.');
  }

  Future<void> _status(
    IosReleaseRun run,
    IosReleaseStatus status,
    String message,
  ) async {
    run.status = status;
    run.message = message;
    await _save(run);
  }

  Future<void> _save(IosReleaseRun run) async {
    final file = File(p.join(run.directory, 'manifest.json'));
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(run.toJson()),
    );
    await temp.rename(file.path);
    final index = history.indexWhere((value) => value.id == run.id);
    if (index < 0) {
      history.insert(0, run);
    } else {
      history[index] = run;
    }
    current.refresh();
    history.refresh();
  }

  String _flutter(IosReleaseRun run) => run.settings.flutterExecutable.isEmpty
      ? runner.resolveFlutterExecutable()
      : run.settings.flutterExecutable;
  String _exportPath(IosReleaseRun run) =>
      run.settings.exportOptionsPath.isEmpty
      ? p.join(run.directory, 'ExportOptions.plist')
      : p.isAbsolute(run.settings.exportOptionsPath)
      ? run.settings.exportOptionsPath
      : p.join(run.project.path, run.settings.exportOptionsPath);
  String _xml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  Future<String> _hash(File file) async {
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      _checkCanceled();
      sink.add(chunk);
    }
    sink.close();
    return (await sink.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<String> _sourceHash(IosReleaseRun run) async {
    final files = await _command(run.project.path, 'git', [
      'ls-files',
      '-z',
      '--cached',
      '--others',
      '--exclude-standard',
    ]);
    final names =
        files.output
            .split('\u0000')
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final sink = Sha256().newHashSink();
    for (final name in names) {
      _checkCanceled();
      final path = p.join(run.project.path, name);
      final type = await FileSystemEntity.type(path, followLinks: false);
      final digest = switch (type) {
        FileSystemEntityType.file => await _hash(File(path)),
        FileSystemEntityType.link => await Link(path).target(),
        _ => type.toString(),
      };
      sink.add(utf8.encode(jsonEncode([name, digest])));
    }
    sink.close();
    return (await sink.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      _checkCanceled();
      final target = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      } else if (entity is Link) {
        await Link(target).create(await entity.target());
      }
    }
  }

  Future<AppStoreCredentials> _credential(AppStoreProject project) async {
    final value = await credentials(project.id);
    if (!value.hasRequiredCredentials || value.inHouse) {
      throw StateError(
        'Cần API key App Store Connect (.p8, Key ID, Issuer ID), không dùng Enterprise/in-house.',
      );
    }
    return value;
  }

  Future<String> exportScripts(
    AppStoreProject project,
    IosReleaseSettings settings,
    String parent,
  ) async {
    validateSettings(settings);
    final credential = await _credential(project);
    final effective = IosReleaseSettings.fromJson({
      ...settings.toJson(),
      'teamId': settings.teamId.isEmpty
          ? credential.teamId ?? ''
          : settings.teamId,
    });
    final destination = Directory(
      p.join(
        parent,
        'amc_ios_${p.basename(project.path)}_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await Directory(
      p.join(destination.path, 'fastlane'),
    ).create(recursive: true);
    await File(
      p.join(destination.path, 'fastlane', 'Fastfile'),
    ).writeAsString(iosReleaseFastfile);
    await File(
      p.join(destination.path, 'release_ios.py'),
    ).writeAsString(iosReleasePython);
    await File(p.join(destination.path, 'release_ios.sh')).writeAsString(
      '#!/bin/bash\nset -euo pipefail\nexec python3 "\$(dirname "\$0")/release_ios.py" "\$@"\n',
    );
    await File(p.join(destination.path, 'config.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'template_version': 1,
        'project_path': p.absolute(project.path),
        'bundle_id': project.bundleId,
        'settings': effective.toJson(),
      }),
    );
    await File(
      p.join(destination.path, '.gitignore'),
    ).writeAsString('runs/\n__pycache__/\n');
    await File(p.join(destination.path, 'README.md')).writeAsString(
      '''# AMC iOS scripts

Generated from the same Fastfile as AMC. Requires macOS, Xcode, Flutter,
Fastlane (or project Bundler) and an existing distribution signing identity.
Edit config.json for project paths/signing/groups/notes. No API key is exported.

Set AMC_KEY_ID, AMC_ISSUER_ID and AMC_KEY_FILE in your terminal environment.
Keep the private key outside the repository. Run explicit steps:

    bash release_ios.sh prepare --version 1.2.3
    bash release_ios.sh build --run <ID>
    bash release_ios.sh upload --run <ID>
    bash release_ios.sh status --run <ID>
    bash release_ios.sh draft --run <ID>

Reuse a ready TestFlight build with prepare --version 1.2.3 --build-number 42.
Check the run manifest before distribute / submit / release --confirm.
If upload is interrupted, use status first. --retry-verified is an explicit
retry after checking Apple; processing delays do not require another upload.
Artifacts and manifests stay in runs/. Android scripts are unchanged.
''',
    );
    return destination.path;
  }

  Future<CommandRunResult> _command(
    String directory,
    String executable,
    List<String> arguments, {
    Map<String, String> environment = const {},
  }) async {
    _checkCanceled();
    final result = await runner.runCommandWithOutput(
      workingDirectory: directory,
      statusLabel: 'iOS ${p.basename(executable)}',
      activePath: 'ios-release',
      executable: executable,
      arguments: arguments,
      environment: environment,
      projectName: _loggingRun?.project.name,
      allowDuringWorkflow: true,
      trackWorkflowStep: false,
    );
    if (_loggingRun != null) {
      var output = result.output.replaceAll('\u0000', '\n');
      output = output.replaceAll(
        RegExp(
          r'-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----',
          dotAll: true,
        ),
        '[PRIVATE KEY REDACTED]',
      );
      if (_privateKey != null && _privateKey!.trim().isNotEmpty) {
        output = output.replaceAll(
          _privateKey!.trim(),
          '[PRIVATE KEY REDACTED]',
        );
        output = output.replaceAll(
          _privateKey!.trim().replaceAll('\n', r'\n'),
          '[PRIVATE KEY REDACTED]',
        );
      }
      await File(p.join(_loggingRun!.directory, 'commands.log')).writeAsString(
        '${DateTime.now().toIso8601String()} ${jsonEncode([executable, ...arguments])}\n$output\nexit: ${result.exitCode}\n',
        mode: FileMode.append,
      );
    }
    _checkCanceled();
    if (result.exitCode != 0) {
      throw StateError(
        '${p.basename(executable)} lỗi (exit ${result.exitCode}). Xem log để biết chi tiết.',
      );
    }
    return result;
  }

  Future<IosStoreState> _apple(IosReleaseRun run, String action) async {
    final credential = await _credential(run.project);
    _privateKey = credential.p8PrivateKey;
    final temp = await Directory.systemTemp.createTemp('amc_ios_key_');
    try {
      final folder = await Directory(p.join(temp.path, 'fastlane')).create();
      await File(
        p.join(folder.path, 'Fastfile'),
      ).writeAsString(iosReleaseFastfile);
      final key = File(p.join(temp.path, 'AuthKey.p8'));
      await key.writeAsString(credential.p8PrivateKey!.trim());
      if (Platform.isMacOS || Platform.isLinux) {
        await Process.run('/bin/chmod', ['600', key.path]);
      }
      final input = File(p.join(temp.path, 'input.json'));
      await input.writeAsString(
        jsonEncode({
          'action': action,
          'key_id': credential.keyId,
          'issuer_id': credential.issuerId,
          'key_filepath': key.path,
          'bundle_id': run.project.bundleId,
          'version': run.version,
          'build_number': run.buildNumber,
          'ipa': run.ipaPath,
          'groups': run.settings.groups,
          'external_testing': run.settings.externalTesting,
          'notes': run.settings.notes,
          'locale': run.settings.locale,
          'use_app_store_locale': run.settings.useAppStoreLocale,
          'automatic_release': run.settings.automaticRelease,
        }),
      );
      final gemfiles = [
        File(p.join(run.project.path, 'ios', 'fastlane', 'Gemfile')),
        File(p.join(run.project.path, 'ios', 'Gemfile')),
      ];
      final gemfile = gemfiles.where((file) => file.existsSync()).firstOrNull;
      final bundle = gemfile == null ? null : runner.resolveBundleExecutable();
      if (gemfile != null && bundle == null) {
        throw StateError('Project có Gemfile nhưng chưa có Bundler.');
      }
      final result = await _command(
        temp.path,
        bundle ?? runner.resolveFastlaneExecutable(),
        [
          if (bundle != null) ...['exec', 'fastlane'],
          'ios',
          'amc_ios',
          'input:${input.path}',
        ],
        environment: {
          'FASTLANE_SKIP_UPDATE_CHECK': '1',
          'FASTLANE_SKIP_SCREEN': '1',
          'FASTLANE_OPT_OUT_USAGE': '1',
          'CI': '1',
          if (bundle != null) 'BUNDLE_GEMFILE': gemfile!.absolute.path,
        },
      );
      return parseStoreState(result.output);
    } finally {
      if (temp.existsSync()) await temp.delete(recursive: true);
      _privateKey = null;
    }
  }
}
