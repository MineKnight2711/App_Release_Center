import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/models/app_store_credentials.dart';
import 'package:app_management_center/app/models/app_store_project.dart';
import 'package:app_management_center/app/models/ios_release.dart';
import 'package:app_management_center/app/models/release_workflow.dart';
import 'package:app_management_center/app/services/ios_release_workflow_service.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp, projectDirectory;
  late AppStoreProject project;
  late _Runner runner;
  late IosReleaseWorkflowService service;
  const credentials = AppStoreCredentials(
    p8PrivateKey: 'PRIVATE TEST FIXTURE',
    keyId: 'KEY',
    issuerId: 'ISSUER',
    teamId: 'TEAM',
  );
  const settings = IosReleaseSettings(
    teamId: 'TEAM',
    notes: 'Test notes',
    groups: ['Internal'],
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ios_release_test_');
    projectDirectory = await Directory(p.join(temp.path, 'project')).create();
    await Directory(
      p.join(projectDirectory.path, 'ios', 'Runner.xcworkspace'),
    ).create(recursive: true);
    await Directory(p.join(projectDirectory.path, 'lib')).create();
    await File(
      p.join(projectDirectory.path, 'lib', 'main.dart'),
    ).writeAsString('void main() {}');
    await File(
      p.join(projectDirectory.path, 'pubspec.yaml'),
    ).writeAsString('name: demo\nversion: 1.2.3+10\n');
    project = AppStoreProject(
      id: 'test',
      path: projectDirectory.path,
      displayName: 'Demo',
      bundleId: 'com.example.demo',
    );
    runner = _Runner(projectDirectory);
    service = IosReleaseWorkflowService(
      runner: runner,
      credentials: (_) async => credentials,
      root: Directory(p.join(temp.path, 'history')),
      isMacOS: () => true,
      processingTimeout: Duration.zero,
      pollInterval: Duration.zero,
    );
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('defaults to vi-VN and migrates the old implicit en-US setting', () {
    const defaultSettings = IosReleaseSettings();
    expect(defaultSettings.locale, 'vi-VN');
    expect(defaultSettings.useAppStoreLocale, isFalse);
    IosReleaseWorkflowService.validateSettings(defaultSettings);
    final migrated = IosReleaseSettings.fromJson({'locale': 'en-US'});
    expect(migrated.locale, 'vi-VN');
    expect(migrated.useAppStoreLocale, isFalse);
    expect(IosReleaseSettings.fromJson({'locale': 'fr-FR'}).locale, 'fr-FR');
  });

  test(
    'supports App Store primary language without requiring an explicit locale',
    () {
      final automatic = IosReleaseSettings.fromJson({
        'locale': '',
        'useAppStoreLocale': true,
      });
      IosReleaseWorkflowService.validateSettings(automatic);
      expect(
        IosReleaseSettings.fromJson(automatic.toJson()).useAppStoreLocale,
        isTrue,
      );
      expect(
        () => IosReleaseWorkflowService.validateSettings(
          const IosReleaseSettings(locale: '', useAppStoreLocale: false),
        ),
        throwsFormatException,
      );
    },
  );

  test('reads JSON results prefixed by Fastlane timestamps and ANSI colors', () {
    final state = IosReleaseWorkflowService.parseStoreState(
      '\u001b[32m[19:28:44]: AMC_IOS_RESULT:{"builds":[{"id":"build","version":"1.2.3","number":"12","state":"VALID"}],"versions":[]}\u001b[0m\n',
    );
    expect(state.findBuild('1.2.3', 12)?.isReady, isTrue);
    expect(
      () => IosReleaseWorkflowService.parseStoreState('fastlane finished'),
      throwsStateError,
    );
  });

  test('does not adopt a build uploaded by another project/run', () async {
    final run = await service.prepare(project: project, settings: settings);
    await service.build(run);
    runner.uploaded = true;
    await expectLater(service.upload(run), throwsStateError);
    expect(run.uploadAttempted, isFalse);
    expect(runner.appleActions.where((action) => action == 'upload'), isEmpty);
  });

  test('parses Xcode settings with warnings before and after JSON', () {
    final settings = IosReleaseWorkflowService.parseBuildSettings(
      'warning [MT]: text\n[{"target":"Runner","buildSettings":{"VALUE":"[escaped]"}}]\nwarning [done]',
    );
    expect(settings.single['target'], 'Runner');
  });

  test(
    'prepares without auto scripts, includes processing builds, binds scheme identity',
    () async {
      final run = await service.prepare(project: project, settings: settings);
      expect(run.buildNumber, 12);
      expect(run.status, IosReleaseStatus.prepared);
      expect(run.commit, 'abc123');
      expect(File(p.join(run.directory, 'manifest.json')).existsSync(), isTrue);
      expect(
        await File(p.join(project.path, 'pubspec.yaml')).readAsString(),
        contains('1.2.3+10'),
      );
      expect(
        runner.keyDirectories.every((path) => !Directory(path).existsSync()),
        isTrue,
      );
      expect(
        await File(p.join(run.directory, 'manifest.json')).readAsString(),
        isNot(contains('PRIVATE TEST FIXTURE')),
      );
      expect(runner.appleActions, ['query']);
    },
  );

  test(
    'rejects a scheme with mismatched bundle ID before build/upload',
    () async {
      runner.bundleId = 'com.other.app';
      await expectLater(
        service.prepare(project: project, settings: settings),
        throwsStateError,
      );
      expect(runner.appleActions, ['query']);
      expect(service.history.single.status, IosReleaseStatus.failed);
      expect(service.busy.value, isFalse);
      expect(runner.isBusy, isFalse);
    },
  );

  test(
    'builds exact IPA, uploads once, processing timeout can resume without rebuilding',
    () async {
      final run = await service.prepare(project: project, settings: settings);
      await service.build(run);
      expect(run.status, IosReleaseStatus.built);
      expect(
        await File(p.join(run.archivePath!, 'Info.plist')).readAsString(),
        'archive fixture',
      );
      expect(run.ipaHash, isNotEmpty);
      expect(runner.buildArguments, contains('--build-name=1.2.3'));
      expect(runner.buildArguments, contains('--build-number=12'));
      await service.upload(run);
      expect(run.status, IosReleaseStatus.processing);
      await service.waitForProcessing(run);
      expect(run.status, IosReleaseStatus.processing);
      expect(runner.appleActions.where((a) => a == 'upload').length, 1);
      runner.processingState = 'VALID';
      await service.refresh(run);
      expect(run.status, IosReleaseStatus.ready);
      await service.storeAction(run, 'draft');
      expect(run.status, IosReleaseStatus.draft);
      expect(runner.inputs.last['build_number'], 12);
      expect(runner.inputs.last['automatic_release'], isFalse);
      expect(runner.inputs.last['locale'], 'vi-VN');
      expect(runner.inputs.last['use_app_store_locale'], isFalse);
      expect(runner.buildCalls, 1);
      final reloaded = IosReleaseWorkflowService(
        runner: runner,
        credentials: (_) async => credentials,
        root: Directory(p.join(temp.path, 'history')),
      );
      await reloaded.load();
      expect(reloaded.history.single.ipaPath, run.ipaPath);
      expect(reloaded.history.single.status, IosReleaseStatus.draft);
      expect(
        runner.keyDirectories.every((path) => !Directory(path).existsSync()),
        isTrue,
      );
    },
  );

  test(
    'continues to TestFlight in one call and resumes without rebuilding',
    () async {
      final run = await service.prepare(project: project, settings: settings);
      await service.continueToTestFlight(run);
      expect(run.status, IosReleaseStatus.processing);
      expect(runner.buildCalls, 1);
      expect(runner.appleActions.where((a) => a == 'upload').length, 1);
      expect(
        run.stageStatuses()[IosReleaseStage.processing],
        ReleaseStepStatus.running,
      );

      runner.processingState = 'VALID';
      await service.continueToTestFlight(run);
      expect(run.status, IosReleaseStatus.ready);
      expect(runner.buildCalls, 1);
      expect(runner.appleActions.where((a) => a == 'upload').length, 1);
    },
  );

  test('stops the TestFlight chain at the first failing step', () async {
    final run = await service.prepare(project: project, settings: settings);
    runner.ipaVersion = '9.9.9';
    await expectLater(service.continueToTestFlight(run), throwsStateError);
    expect(run.status, IosReleaseStatus.failed);
    expect(run.lastAction, 'build');
    expect(runner.appleActions, isNot(contains('upload')));
    final stages = run.stageStatuses();
    expect(stages[IosReleaseStage.prepare], ReleaseStepStatus.succeeded);
    expect(stages[IosReleaseStage.build], ReleaseStepStatus.failed);
    expect(stages[IosReleaseStage.upload], ReleaseStepStatus.pending);
    expect(run.lastError, contains('IPA'));
  });

  test('maps run state to release stages', () {
    IosReleaseRun run(
      IosReleaseStatus status, {
      String lastAction = 'query',
      String? ipaPath = '/tmp/app.ipa',
      bool uploadAttempted = true,
      List<Map<String, dynamic>> steps = const [],
    }) => IosReleaseRun(
      id: 'stages',
      project: project,
      settings: settings,
      version: '1.2.3',
      buildNumber: 12,
      directory: temp.path,
      commit: 'abc123',
      dirty: false,
      createdAt: DateTime(2026),
      status: status,
      ipaPath: ipaPath,
      uploadAttempted: uploadAttempted,
      lastAction: lastAction,
      steps: steps,
    );
    List<ReleaseStepStatus> stages(IosReleaseRun run, {String? running}) => [
      for (final stage in IosReleaseStage.values)
        run.stageStatuses(running: running)[stage]!,
    ];
    const s = ReleaseStepStatus.succeeded, p = ReleaseStepStatus.pending;
    const r = ReleaseStepStatus.running, k = ReleaseStepStatus.skipped;

    expect(
      stages(
        run(IosReleaseStatus.prepared, ipaPath: null, uploadAttempted: false),
      ),
      [s, p, p, p, p, p, p],
    );
    expect(
      stages(
        run(IosReleaseStatus.prepared, ipaPath: null, uploadAttempted: false),
        running: 'build',
      ),
      [s, r, p, p, p, p, p],
    );
    expect(stages(run(IosReleaseStatus.verificationRequired)), [
      s,
      s,
      ReleaseStepStatus.warning,
      p,
      p,
      p,
      p,
    ]);
    // A build picked from TestFlight skips local build and upload.
    expect(stages(run(IosReleaseStatus.ready, ipaPath: null)), [
      s,
      k,
      k,
      s,
      p,
      p,
      p,
    ]);
    // Refreshing a processed build is not progress on processing.
    expect(stages(run(IosReleaseStatus.ready), running: 'query'), [
      s,
      s,
      s,
      s,
      p,
      p,
      p,
    ]);
    expect(stages(run(IosReleaseStatus.submitted)), [s, s, s, s, s, r, p]);
    expect(
      stages(
        run(
          IosReleaseStatus.submitted,
          steps: [
            {'action': 'release', 'status': 'succeeded'},
          ],
        ),
      ),
      [s, s, s, s, s, s, r],
    );
    expect(stages(run(IosReleaseStatus.failed, lastAction: 'submit')), [
      s,
      s,
      s,
      s,
      s,
      ReleaseStepStatus.failed,
      p,
    ]);
    // Distribution has no stage of its own; its failure leaves the build ready.
    expect(stages(run(IosReleaseStatus.failed, lastAction: 'distribute')), [
      s,
      s,
      s,
      s,
      p,
      p,
      p,
    ]);
    expect(stages(run(IosReleaseStatus.released)), List.filled(7, s));
  });

  test('rejects wrong IPA metadata and a tampered artifact', () async {
    final run = await service.prepare(project: project, settings: settings);
    runner.ipaVersion = '9.9.9';
    await expectLater(service.build(run), throwsStateError);
    expect(runner.appleActions, ['query']);
    runner.ipaVersion = '1.2.3';
    await service.build(run);
    await File(run.ipaPath!).writeAsString('changed');
    await expectLater(service.upload(run), throwsStateError);
    expect(runner.appleActions, ['query']);
  });

  test('rejects source edits after the release preview', () async {
    final run = await service.prepare(project: project, settings: settings);
    await File(
      p.join(project.path, 'lib', 'main.dart'),
    ).writeAsString('void main() { print("edited"); }');
    await expectLater(service.build(run), throwsStateError);
    expect(runner.buildCalls, 0);
  });

  test(
    'writes version only on request and preserves the rest of pubspec',
    () async {
      final run = await service.prepare(project: project, settings: settings);
      final preview = await service.versionPreview(run);
      expect(preview.oldVersion, '1.2.3+10');
      await service.writeVersion(run);
      expect(
        await File(p.join(project.path, 'pubspec.yaml')).readAsString(),
        'name: demo\nversion: 1.2.3+12\n',
      );
      expect(
        runner.gitArguments.any(
          (arguments) => ['commit', 'push'].contains(arguments.first),
        ),
        isFalse,
      );
      await service.build(run);
      expect(run.status, IosReleaseStatus.built);
      await expectLater(service.writeVersion(run), throwsStateError);
    },
  );

  test('does not commit pre-existing pubspec changes', () async {
    final run = await service.prepare(project: project, settings: settings);
    runner.pubspecDirty = true;
    await expectLater(
      service.writeVersion(run, commit: true),
      throwsStateError,
    );
    expect(
      await File(p.join(project.path, 'pubspec.yaml')).readAsString(),
      contains('1.2.3+10'),
    );
    expect(
      runner.gitArguments.any((arguments) => arguments.first == 'commit'),
      isFalse,
    );
  });

  test('persists diagnostic logs with private key contents redacted', () async {
    final run = await service.prepare(project: project, settings: settings);
    runner.echoPrivateKey = true;
    await service.refresh(run);
    final log = await File(
      p.join(run.directory, 'commands.log'),
    ).readAsString();
    expect(log, contains('PRIVATE KEY REDACTED'));
    expect(log, isNot(contains('PRIVATE TEST FIXTURE')));
  });

  test(
    'uncertain upload does not retry automatically and cleans up credentials',
    () async {
      final run = await service.prepare(project: project, settings: settings);
      await service.build(run);
      runner.failUpload = true;
      await expectLater(service.upload(run), throwsStateError);
      expect(run.status, IosReleaseStatus.verificationRequired);
      expect(run.uploadAttempted, isTrue);
      runner.failUpload = false;
      await service.upload(run);
      expect(runner.appleActions.where((a) => a == 'upload').length, 1);
      await service.upload(run, retryAfterVerification: true);
      expect(runner.appleActions.where((a) => a == 'upload').length, 2);
      expect(
        runner.keyDirectories.every((path) => !Directory(path).existsSync()),
        isTrue,
      );
    },
  );

  test(
    'reuses existing ready build without certificate preflight or IPA build',
    () async {
      final existing = const IosStoreBuild(
        id: 'existing',
        version: '1.2.3',
        number: 10,
        processingState: 'VALID',
      );
      final run = await service.prepare(
        project: project,
        settings: settings,
        existingBuild: existing,
      );
      await service.storeAction(run, 'draft');
      expect(runner.buildCalls, 0);
      expect(runner.executables, isNot(contains('/usr/bin/security')));
      expect(run.buildNumber, 10);
      expect(run.ipaPath, isNull);
    },
  );

  test('does not label another selected build as publicly released', () async {
    final existing = const IosStoreBuild(
      id: 'existing',
      version: '1.2.3',
      number: 10,
      processingState: 'VALID',
    );
    final run = await service.prepare(
      project: project,
      settings: settings,
      existingBuild: existing,
    );
    runner.versions = [
      {
        'version': '1.2.3',
        'state': 'READY_FOR_DISTRIBUTION',
        'buildNumber': '11',
      },
    ];
    await service.refresh(run);
    expect(run.status, IosReleaseStatus.ready);
    runner.versions.single['buildNumber'] = '10';
    await service.refresh(run);
    expect(run.status, IosReleaseStatus.released);
  });

  test('rejects Enterprise keys and non-macOS release', () async {
    final enterprise = IosReleaseWorkflowService(
      runner: runner,
      credentials: (_) async => const AppStoreCredentials(
        p8PrivateKey: 'key',
        keyId: 'KEY',
        issuerId: 'ISSUER',
        inHouse: true,
      ),
      root: temp,
      isMacOS: () => true,
    );
    await expectLater(
      enterprise.prepare(project: project, settings: settings),
      throwsStateError,
    );
    final windows = IosReleaseWorkflowService(
      runner: runner,
      credentials: (_) async => credentials,
      root: temp,
      isMacOS: () => false,
    );
    await expectLater(
      windows.prepare(project: project, settings: settings),
      throwsStateError,
    );
    expect(runner.appleActions, isEmpty);
  });

  test(
    'cancellation preserves the artifact and verifies upload before resuming',
    () async {
      final run = await service.prepare(project: project, settings: settings);
      await service.build(run);
      runner.onApple = (action) async {
        if (action == 'upload') await service.cancel();
      };
      await expectLater(service.upload(run), throwsStateError);
      expect(run.status, IosReleaseStatus.canceled);
      expect(run.uploadAttempted, isTrue);
      expect(File(run.ipaPath!).existsSync(), isTrue);
      expect(
        runner.keyDirectories.every((path) => !Directory(path).existsSync()),
        isTrue,
      );
      runner.onApple = null;
      await service.refresh(run);
      expect(run.status, IosReleaseStatus.processing);
      expect(
        runner.appleActions.where((action) => action == 'upload').length,
        1,
      );
    },
  );

  test('holds an app lock compatible with exported Python scripts', () async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final run = await service.prepare(project: project, settings: settings);
    const probe =
        'import fcntl,sys\nf=open(sys.argv[1],"a+")\ntry: fcntl.lockf(f,fcntl.LOCK_EX|fcntl.LOCK_NB)\nexcept BlockingIOError: sys.exit(7)\n';
    String? lockPath;
    runner.onBuild = () async {
      lockPath = Directory(
        p.join(temp.path, 'history', 'locks'),
      ).listSync().whereType<File>().single.path;
      final result = await Process.run('python3', ['-c', probe, lockPath!]);
      expect(
        result.exitCode,
        7,
        reason: 'Another process must not release the same app concurrently',
      );
    };
    await service.build(run);
    expect(
      (await Process.run('python3', ['-c', probe, lockPath!])).exitCode,
      0,
    );
  });

  test('blocks version/signing overrides in additional arguments', () {
    for (final arg in [
      '--build-number=2',
      '--no-codesign',
      '-t',
      '--flavor=wrong',
    ]) {
      expect(
        () => IosReleaseWorkflowService.validateSettings(
          IosReleaseSettings(extraBuildArguments: [arg]),
        ),
        throwsFormatException,
      );
    }
  });

  test('restores interrupted upload without executing any command', () async {
    final run = await service.prepare(project: project, settings: settings);
    final manifest = File(p.join(run.directory, 'manifest.json'));
    final json =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    json['status'] = 'uploading';
    json['uploadAttempted'] = true;
    await manifest.writeAsString(jsonEncode(json));
    final count = runner.executables.length;
    final reloaded = IosReleaseWorkflowService(
      runner: runner,
      credentials: (_) async => credentials,
      root: Directory(p.join(temp.path, 'history')),
    );
    await reloaded.load();
    expect(
      reloaded.history.single.status,
      IosReleaseStatus.verificationRequired,
    );
    expect(runner.executables.length, count);
  });

  test(
    'exports standalone scripts without credentials and validates their syntax',
    () async {
      final folder = await service.exportScripts(project, settings, temp.path);
      expect(
        await File(p.join(folder, 'config.json')).readAsString(),
        isNot(contains('PRIVATE TEST FIXTURE')),
      );
      expect(runner.appleActions, isEmpty);
      if (Platform.isMacOS || Platform.isLinux) {
        final help = await Process.run('python3', [
          p.join(folder, 'release_ios.py'),
          '--help',
        ]);
        expect(help.exitCode, 0, reason: help.stderr.toString());
        expect(help.stdout, contains('prepare'));
        final shell = await Process.run('bash', [
          '-n',
          p.join(folder, 'release_ios.sh'),
        ]);
        expect(shell.exitCode, 0, reason: shell.stderr.toString());
      }
    },
  );
}

class _Runner extends ReleaseRunnerService {
  _Runner(this.project);
  final Directory project;
  final List<String> executables = [], appleActions = [], keyDirectories = [];
  final List<Map<String, dynamic>> inputs = [];
  List<String> buildArguments = [];
  final List<List<String>> gitArguments = [];
  List<Map<String, dynamic>> versions = [];
  String bundleId = 'com.example.demo',
      ipaVersion = '1.2.3',
      processingState = 'PROCESSING';
  int buildCalls = 0;
  Future<void> Function()? onBuild;
  Future<void> Function(String)? onApple;
  bool uploaded = false,
      failUpload = false,
      pubspecDirty = false,
      echoPrivateKey = false;
  @override
  String resolveFlutterExecutable() => 'flutter';
  @override
  String resolveFastlaneExecutable() => 'fastlane';
  @override
  String? resolveBundleExecutable() => 'bundle';
  @override
  Future<CommandRunResult> runCommandWithOutput({
    required String workingDirectory,
    required String statusLabel,
    required String activePath,
    required String executable,
    List<String> arguments = const [],
    List<String>? displayArguments,
    Map<String, String> environment = const {},
    bool clearLog = false,
    String? projectName,
    bool allowDuringWorkflow = false,
    bool trackWorkflowStep = true,
  }) async {
    executables.add(executable);
    String output = '';
    if (executable == 'git') {
      gitArguments.add(arguments);
      output = arguments.first == 'rev-parse' ? 'abc123\n' : '';
      if (arguments.first == 'status' &&
          arguments.contains('pubspec.yaml') &&
          pubspecDirty) {
        output = ' M pubspec.yaml\n';
      }
      if (arguments.first == 'ls-files') {
        output = 'pubspec.yaml\u0000lib/main.dart\u0000';
      }
    }
    if (executable == '/usr/bin/security') {
      output =
          '1) ABC "Apple Distribution: Demo (TEAM)"\n1 valid identities found';
    }
    if (executable == '/usr/bin/xcodebuild' &&
        arguments.contains('-showBuildSettings')) {
      output = jsonEncode([
        {
          'target': 'Runner',
          'buildSettings': {
            'PRODUCT_TYPE': 'com.apple.product-type.application',
            'PRODUCT_BUNDLE_IDENTIFIER': bundleId,
            'DEVELOPMENT_TEAM': 'TEAM',
          },
        },
      ]);
    }
    if (executable == 'flutter' && arguments.first == 'build') {
      await onBuild?.call();
      buildCalls++;
      buildArguments = arguments;
      final directory = await Directory(
        p.join(project.path, 'build', 'ios', 'ipa'),
      ).create(recursive: true);
      await File(
        p.join(directory.path, 'demo.ipa'),
      ).writeAsString('IPA fixture');
      final archive = await Directory(
        p.join(project.path, 'build', 'ios', 'archive', 'Runner.xcarchive'),
      ).create(recursive: true);
      await File(
        p.join(archive.path, 'Info.plist'),
      ).writeAsString('archive fixture');
    }
    if (executable == '/usr/bin/unzip' && arguments.first == '-Z1') {
      output = 'Payload/Runner.app/Info.plist\n';
    }
    if (executable == '/usr/bin/plutil') {
      output = jsonEncode({
        'CFBundleIdentifier': bundleId,
        'CFBundleShortVersionString': ipaVersion,
        'CFBundleVersion': '12',
      });
    }
    if (executable == 'fastlane' || executable == 'bundle') {
      expect(
        File(p.join(workingDirectory, 'fastlane', 'Fastfile')).existsSync(),
        isTrue,
      );
      keyDirectories.add(workingDirectory);
      final input =
          jsonDecode(
                await File(
                  arguments.last.substring('input:'.length),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(File(input['key_filepath'] as String).existsSync(), isTrue);
      inputs.add(input);
      final action = input['action'] as String;
      appleActions.add(action);
      await onApple?.call(action);
      if (action == 'upload') {
        if (failUpload) return const CommandRunResult(exitCode: 1);
        uploaded = true;
      }
      output =
          '${echoPrivateKey ? 'PRIVATE TEST FIXTURE\n' : ''}AMC_IOS_RESULT:${jsonEncode({
            'builds': [
              {'id': 'existing', 'version': '1.2.3', 'number': '10', 'state': 'VALID', 'expired': false},
              {'id': 'processing', 'version': '1.2.3', 'number': '11', 'state': 'PROCESSING', 'expired': false},
              if (uploaded) {'id': 'new', 'version': '1.2.3', 'number': '12', 'state': processingState, 'expired': false},
            ],
            'versions': versions,
          })}\n';
    }
    return CommandRunResult(exitCode: 0, output: output);
  }
}
