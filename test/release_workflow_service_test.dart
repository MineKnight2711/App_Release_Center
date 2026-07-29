import 'dart:async';
import 'dart:io';

import 'package:app_release_center/app/models/ch_play_credentials.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/models/ch_play_version_snapshot.dart';
import 'package:app_release_center/app/models/release_fastlane_lane.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/models/release_script.dart';
import 'package:app_release_center/app/models/release_workflow.dart';
import 'package:app_release_center/app/services/ch_play_project_inspector_service.dart';
import 'package:app_release_center/app/services/ch_play_version_check_service.dart';
import 'package:app_release_center/app/services/release_note_generation_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:app_release_center/app/services/release_workflow_service.dart';
import 'package:app_release_center/app/services/script_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'runs split release steps with monotonic version and existing AAB upload',
    () async {
      final harness = await _WorkflowHarness.create();
      addTearDown(harness.dispose);

      final prepared = await harness.prepare();
      expect(prepared.currentVersion, '1.2.3+11');
      expect(prepared.proposedVersion, '1.2.4+12');
      expect(prepared.supportsSplitBuildDeploy, isTrue);

      final completed = await harness.service.start(
        postProcessor: (context) async {
          expect(context.fullVersion, '1.2.4+12');
          expect(context.releaseNotes, isNotEmpty);
          return const ReleaseWorkflowPostResult(
            artifactPath: 'release/app-release.apk',
          );
        },
      );

      expect(completed.isCompleted, isTrue);
      expect(
        completed.steps.map((step) => step.status),
        everyElement(ReleaseStepStatus.succeeded),
      );
      expect(harness.runner.versionCodeRuns, 1);
      expect(harness.runner.versionNameRuns, 1);
      expect(harness.runner.commitRuns, 1);
      expect(harness.runner.buildRuns, 1);
      expect(harness.runner.deployRuns, 1);
      expect(harness.runner.lastDeployArgs, contains('skip_build:true'));
      expect(harness.runner.lastDeployArgs, contains('track:internal'));
      expect(
        File(
          p.join(
            harness.project.path,
            'android',
            'fastlane',
            'metadata',
            'android',
            'vi',
            'changelogs',
            '12.txt',
          ),
        ).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'retry resumes at deploy without repeating version, notes, commit, or build',
    () async {
      final harness = await _WorkflowHarness.create(failDeployOnce: true);
      addTearDown(harness.dispose);
      await harness.prepare();

      final failed = await harness.service.start();
      expect(
        failed.steps
            .firstWhere((step) => step.kind == ReleaseWorkflowStepKind.deploy)
            .status,
        ReleaseStepStatus.failed,
      );
      expect(harness.service.canRetry, isTrue);

      final retried = await harness.service.retryFailedStep();
      expect(retried.isCompleted, isTrue);
      expect(harness.runner.deployRuns, 2);
      expect(harness.runner.versionCodeRuns, 1);
      expect(harness.runner.versionNameRuns, 1);
      expect(harness.runner.commitRuns, 1);
      expect(harness.runner.buildRuns, 1);
    },
  );

  test(
    'verification timeout completes upload with a retryable warning',
    () async {
      final harness = await _WorkflowHarness.create(verificationCode: 9);
      addTearDown(harness.dispose);
      await harness.prepare();
      var postProcessingRuns = 0;

      final completed = await harness.service.start(
        postProcessor: (context) async {
          postProcessingRuns++;
          return const ReleaseWorkflowPostResult(
            artifactPath: 'release/app-release.apk',
          );
        },
      );
      final release = completed.steps.firstWhere(
        (step) => step.kind == ReleaseWorkflowStepKind.release,
      );

      expect(release.status, ReleaseStepStatus.warning);
      expect(release.error, contains('Upload succeeded'));
      expect(completed.isCompleted, isTrue);
      expect(harness.service.canRetry, isTrue);
      expect(harness.runner.deployRuns, 1);
      expect(postProcessingRuns, 1);

      final retried = await harness.service.retryFailedStep();
      expect(
        retried.steps
            .firstWhere((step) => step.kind == ReleaseWorkflowStepKind.release)
            .status,
        ReleaseStepStatus.warning,
      );
      expect(harness.runner.deployRuns, 1);
      expect(postProcessingRuns, 1);
    },
  );

  test(
    'post-processing warning completes release without a retry loop',
    () async {
      final harness = await _WorkflowHarness.create();
      addTearDown(harness.dispose);
      await harness.prepare();

      final completed = await harness.service.start(
        postProcessor: (context) async => const ReleaseWorkflowPostResult(
          warning: 'Telegram delivery failed.',
        ),
      );
      final release = completed.steps.firstWhere(
        (step) => step.kind == ReleaseWorkflowStepKind.release,
      );

      expect(release.status, ReleaseStepStatus.warning);
      expect(release.error, contains('Telegram delivery failed'));
      expect(release.retryable, isFalse);
      expect(completed.isCompleted, isTrue);
      expect(harness.service.canRetry, isFalse);
    },
  );

  test('legacy compatibility deploy explicitly skips Firebase', () async {
    final harness = await _WorkflowHarness.create(
      splitContract: false,
      legacyIncludesFirebase: true,
    );
    addTearDown(harness.dispose);

    final prepared = await harness.prepare();
    expect(prepared.supportsSplitBuildDeploy, isFalse);
    expect(
      prepared.steps.any(
        (step) => step.kind == ReleaseWorkflowStepKind.legacyBuildDeploy,
      ),
      isTrue,
    );

    final completed = await harness.service.start();
    expect(completed.isCompleted, isTrue);
    expect(harness.runner.legacyDeployRuns, 1);
    expect(harness.runner.lastLegacyArgs.take(2), ['no', 'yes']);
    expect(harness.runner.lastLegacyEnvironment['DEPLOY_LEGACY_ARGS'], '1');
  });

  test('cancel marks the active step and does not start later steps', () async {
    final harness = await _WorkflowHarness.create(blockVersionCode: true);
    addTearDown(harness.dispose);
    await harness.prepare();

    final running = harness.service.start();
    await harness.runner.versionCodeStarted.future;
    await harness.service.cancel();
    harness.runner.releaseVersionCode();
    final canceled = await running;

    expect(
      canceled.steps
          .firstWhere(
            (step) => step.kind == ReleaseWorkflowStepKind.versionCode,
          )
          .status,
      ReleaseStepStatus.canceled,
    );
    expect(harness.runner.versionNameRuns, 0);
    expect(harness.runner.commitRuns, 0);
    expect(harness.runner.buildRuns, 0);
  });
}

class _WorkflowHarness {
  _WorkflowHarness({
    required this.root,
    required this.project,
    required this.runner,
    required this.versionChecker,
    required this.service,
    required this.releaseProject,
  });

  final Directory root;
  final Directory project;
  final _FakeWorkflowRunner runner;
  final _FakeChPlayVersionChecker versionChecker;
  final ReleaseWorkflowService service;
  final ReleaseProject releaseProject;

  static Future<_WorkflowHarness> create({
    bool failDeployOnce = false,
    int verificationCode = 12,
    bool splitContract = true,
    bool legacyIncludesFirebase = false,
    bool blockVersionCode = false,
  }) async {
    final root = await Directory.systemTemp.createTemp('arc_release_workflow_');
    final project = await Directory(p.join(root.path, 'demo_app')).create();
    await Directory(p.join(project.path, 'auto')).create();
    await Directory(
      p.join(project.path, 'android', 'fastlane'),
    ).create(recursive: true);
    await File(
      p.join(project.path, 'pubspec.yaml'),
    ).writeAsString('name: demo_app\nversion: 1.2.3+11\n');
    await File(
      p.join(project.path, 'android', 'fastlane', 'Fastfile'),
    ).writeAsString('''
default_platform(:android)
platform :android do
  lane :fetch_version_code_from_play_store do
    puts "STORE_CODE_ONLY:9"
  end
${splitContract ? '''
  lane :build_aab do
    puts "ARC_AAB_PATH:build/app-release.aab"
  end
  lane :upload_to_chplay do |options|
    skip_build = options[:skip_build] || ENV["SKIP_PLAY_BUILD"]
  end
''' : ''}
end
''');
    for (final name in [
      'control_ver_code.sh',
      'control_ver_name.sh',
      'commit.sh',
      'deploy.sh',
    ]) {
      await File(p.join(project.path, 'auto', name)).writeAsString(
        name == 'deploy.sh' && legacyIncludesFirebase
            ? '#!/bin/bash\ndeploy_firebase_dis\nupload_to_chplay\n'
            : '#!/bin/bash\n',
      );
    }
    await _git(project.path, const ['init']);
    await _git(project.path, const [
      'config',
      'user.email',
      'test@example.com',
    ]);
    await _git(project.path, const ['config', 'user.name', 'Release Test']);
    await _git(project.path, const [
      'remote',
      'add',
      'origin',
      'https://example.com/demo.git',
    ]);
    await _git(project.path, const ['add', '.']);
    await _git(project.path, const ['commit', '-m', 'initial']);

    final runner = _FakeWorkflowRunner(
      failDeployOnce: failDeployOnce,
      blockVersionCode: blockVersionCode,
    );
    final inspector = ChPlayProjectInspectorService();
    final versionChecker = _FakeChPlayVersionChecker(
      inspector: inspector,
      runner: runner,
      verificationCode: verificationCode,
    );
    final catalog = ScriptCatalogService();
    final releaseProject = await catalog.inspect(project.path);
    final service = ReleaseWorkflowService(
      runner: runner,
      catalog: catalog,
      chPlayInspector: inspector,
      chPlayVersionChecker: versionChecker,
      releaseNotesGenerator: ReleaseNoteGenerationService(),
      verificationInterval: Duration.zero,
      verificationTimeout: Duration.zero,
    );
    return _WorkflowHarness(
      root: root,
      project: project,
      runner: runner,
      versionChecker: versionChecker,
      service: service,
      releaseProject: releaseProject,
    );
  }

  Future<ReleaseWorkflowRun> prepare() {
    return service.prepare(
      ReleaseWorkflowConfig(
        project: releaseProject,
        playProject: ChPlayProject(
          id: 'play-demo',
          path: project.path,
          displayName: 'Demo App',
          applicationId: 'com.example.demo',
          track: 'internal',
        ),
        credentials: const ChPlayCredentials(googlePlayJson: '{}'),
        track: 'internal',
        geminiApiKey: '',
        releaseNotePrompt: '',
        uploadListingImages: false,
        validateListingImages: false,
      ),
    );
  }

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

class _FakeWorkflowRunner extends ReleaseRunnerService {
  _FakeWorkflowRunner({
    required this.failDeployOnce,
    required this.blockVersionCode,
  });

  final bool failDeployOnce;
  final bool blockVersionCode;
  final Completer<void> versionCodeStarted = Completer<void>();
  final Completer<void> _versionCodeGate = Completer<void>();
  int versionCodeRuns = 0;
  int versionNameRuns = 0;
  int commitRuns = 0;
  int buildRuns = 0;
  int deployRuns = 0;
  int legacyDeployRuns = 0;
  List<String> lastDeployArgs = const [];
  List<String> lastLegacyArgs = const [];
  Map<String, String> lastLegacyEnvironment = const {};

  void releaseVersionCode() {
    if (!_versionCodeGate.isCompleted) _versionCodeGate.complete();
  }

  @override
  Future<CommandRunResult> runWithOutput({
    required ReleaseProject project,
    required ReleaseScript script,
    List<String> args = const [],
    Map<String, String> environment = const {},
    bool clearLog = false,
    bool allowDuringWorkflow = false,
  }) async {
    switch (script.kind) {
      case ReleaseScriptKind.versionCode:
        versionCodeRuns++;
        if (!versionCodeStarted.isCompleted) versionCodeStarted.complete();
        if (blockVersionCode) await _versionCodeGate.future;
        await _rewriteVersion(project.path, code: int.parse(args[1]));
      case ReleaseScriptKind.versionName:
        versionNameRuns++;
        await _rewriteVersion(project.path, name: args[1]);
      case ReleaseScriptKind.commit:
        commitRuns++;
      case ReleaseScriptKind.deploy:
        legacyDeployRuns++;
        lastLegacyArgs = args;
        lastLegacyEnvironment = environment;
        final artifact = File(
          p.join(
            project.path,
            'build',
            'app',
            'outputs',
            'bundle',
            'release',
            'app-release.aab',
          ),
        );
        await artifact.parent.create(recursive: true);
        await artifact.writeAsString('legacy aab');
      case ReleaseScriptKind.release:
      case ReleaseScriptKind.merge:
      case ReleaseScriptKind.imageValidation:
      case ReleaseScriptKind.shell:
      case ReleaseScriptKind.dartTool:
        break;
    }
    return const CommandRunResult(exitCode: 0, output: 'ok\n');
  }

  @override
  Future<CommandRunResult> runFastlaneLaneWithOutput({
    required ReleaseProject project,
    required ReleaseFastlaneLane lane,
    List<String> args = const [],
    Map<String, String> environment = const {},
    bool clearLog = false,
    bool allowDuringWorkflow = false,
  }) async {
    if (lane.name == 'build_aab') {
      buildRuns++;
      final artifact = File(
        p.join(
          project.path,
          'build',
          'app',
          'outputs',
          'bundle',
          'release',
          'app-release.aab',
        ),
      );
      await artifact.parent.create(recursive: true);
      await artifact.writeAsString('aab');
      return CommandRunResult(
        exitCode: 0,
        output: 'ARC_AAB_PATH:${artifact.path}\n',
      );
    }
    if (lane.name == 'upload_to_chplay') {
      deployRuns++;
      lastDeployArgs = args;
      if (failDeployOnce && deployRuns == 1) {
        return const CommandRunResult(exitCode: 1, output: 'deploy failed\n');
      }
    }
    return const CommandRunResult(exitCode: 0, output: 'uploaded\n');
  }

  Future<void> _rewriteVersion(
    String projectPath, {
    String? name,
    int? code,
  }) async {
    final file = File(p.join(projectPath, 'pubspec.yaml'));
    final source = await file.readAsString();
    final match = RegExp(
      r'^version:\s*([^+]+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(source)!;
    final nextName = name ?? match.group(1)!;
    final nextCode = code ?? int.parse(match.group(2)!);
    await file.writeAsString(
      source.replaceFirst(match.group(0)!, 'version: $nextName+$nextCode'),
    );
  }
}

class _FakeChPlayVersionChecker extends ChPlayVersionCheckService {
  _FakeChPlayVersionChecker({
    required super.inspector,
    required super.runner,
    required this.verificationCode,
  });

  final int verificationCode;
  int calls = 0;

  @override
  Future<ChPlayVersionSnapshot> refreshProject({
    required ChPlayProject project,
    required ChPlayCredentials credentials,
    bool clearLog = true,
    bool allowDuringWorkflow = false,
    bool trackWorkflowStep = true,
  }) async {
    calls++;
    final local = await inspector.readLocalVersion(project.path);
    final storeCode = calls == 1 ? 9 : verificationCode;
    return ChPlayVersionSnapshot(
      localVersion: local,
      storeVersionCode: storeCode,
      status: ChPlayVersionCheckService.compare(local!.code, storeCode),
      message: 'Checked ${project.track}.',
    );
  }
}

Future<void> _git(String workingDirectory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}
