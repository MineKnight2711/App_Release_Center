import 'dart:async';
import 'dart:io';

import 'package:app_release_center/app/models/release_fastlane_lane.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/models/release_script.dart';
import 'package:app_release_center/app/models/release_workflow.dart';
import 'package:app_release_center/app/services/ch_play_project_inspector_service.dart';
import 'package:app_release_center/app/services/ch_play_version_check_service.dart';
import 'package:app_release_center/app/services/release_note_generation_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:app_release_center/app/services/script_catalog_service.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

class ReleaseWorkflowService extends GetxService {
  ReleaseWorkflowService({
    required this.runner,
    required this.catalog,
    required this.chPlayInspector,
    required this.chPlayVersionChecker,
    required this.releaseNotesGenerator,
    this.verificationInterval = const Duration(seconds: 15),
    this.verificationTimeout = const Duration(minutes: 5),
  });

  final ReleaseRunnerService runner;
  final ScriptCatalogService catalog;
  final ChPlayProjectInspectorService chPlayInspector;
  final ChPlayVersionCheckService chPlayVersionChecker;
  final ReleaseNoteGenerationService releaseNotesGenerator;
  final Duration verificationInterval;
  final Duration verificationTimeout;

  final currentRun = Rxn<ReleaseWorkflowRun>();
  final isPreparing = false.obs;

  ReleaseWorkflowConfig? _config;
  ReleaseWorkflowPostProcessor? _postProcessor;
  bool _cancelRequested = false;
  bool _postProcessingCompleted = false;
  String? _postProcessingWarning;

  bool get isRunning => currentRun.value?.isRunning ?? false;
  bool get canRetry => currentRun.value?.retryableStep != null && !isRunning;

  Future<ReleaseWorkflowRun> prepare(ReleaseWorkflowConfig config) async {
    if (isRunning || runner.isBusy) {
      throw const ReleaseWorkflowException(
        'Wait for the active command before preparing a release.',
      );
    }

    isPreparing.value = true;
    _config = config;
    _postProcessor = null;
    _cancelRequested = false;
    _postProcessingCompleted = false;
    _postProcessingWarning = null;
    final createdAt = DateTime.now();
    try {
      final normalizedTrack = config.track.trim().toLowerCase();
      if (!_supportedTracks.contains(normalizedTrack)) {
        throw ReleaseWorkflowException(
          'Unsupported CH Play track: ${config.track}.',
        );
      }
      if (!config.credentials.hasGooglePlayJson) {
        throw const ReleaseWorkflowException(
          'Google Play service-account credentials are required.',
        );
      }
      if (config.playProject.applicationId.trim().isEmpty) {
        throw const ReleaseWorkflowException(
          'The managed CH Play project needs an application ID.',
        );
      }
      if (!config.project.androidDirectory.existsSync()) {
        throw const ReleaseWorkflowException(
          'The selected project does not contain an android folder.',
        );
      }

      final versionCodeScript = _requiredScript(
        config.project,
        ReleaseScriptKind.versionCode,
      );
      final versionNameScript = _requiredScript(
        config.project,
        ReleaseScriptKind.versionName,
      );
      final commitScript = _requiredScript(
        config.project,
        ReleaseScriptKind.commit,
      );
      if (!versionCodeScript.isShellScript ||
          !versionNameScript.isShellScript ||
          !commitScript.isShellScript) {
        throw const ReleaseWorkflowException(
          'Version and commit automation must use the supported shell scripts.',
        );
      }

      final fastfile = File(
        p.join(config.project.path, 'android', 'fastlane', 'Fastfile'),
      );
      if (!fastfile.existsSync()) {
        throw const ReleaseWorkflowException(
          'android/fastlane/Fastfile is required for release.',
        );
      }

      final gitRoot = await _runGit(
        config.project.path,
        const ['rev-parse', '--show-toplevel'],
        failureMessage: 'The selected project is not a Git repository.',
      );
      if (gitRoot.output.trim().isEmpty) {
        throw const ReleaseWorkflowException(
          'The selected project is not a Git repository.',
        );
      }
      final branchResult = await _runGit(config.project.path, const [
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ]);
      final branch = branchResult.output.trim();
      if (branch.isEmpty || branch == 'HEAD') {
        throw const ReleaseWorkflowException(
          'Release requires a named Git branch, not detached HEAD.',
        );
      }
      await _runGit(
        config.project.path,
        const ['remote', 'get-url', 'origin'],
        failureMessage: 'Git remote origin is required before release.',
      );

      final localVersion = await chPlayInspector.readLocalVersion(
        config.project.path,
      );
      if (localVersion == null) {
        throw const ReleaseWorkflowException(
          'pubspec.yaml version must use <versionName>+<versionCode>.',
        );
      }

      final trackedProject = config.playProject.copyWith(
        track: normalizedTrack,
      );
      final snapshot = await chPlayVersionChecker.refreshProject(
        project: trackedProject,
        credentials: config.credentials,
      );
      final storeCode = snapshot.storeVersionCode;
      if (storeCode == null) {
        throw ReleaseWorkflowException(
          snapshot.message.isEmpty
              ? 'Could not read the current CH Play version code.'
              : snapshot.message,
        );
      }

      final nextCode =
          (localVersion.code > storeCode ? localVersion.code : storeCode) + 1;
      final nextName = _bumpVersionName(localVersion.name);
      final statusResult = await _runGit(config.project.path, const [
        'status',
        '--porcelain',
      ]);
      final changedFiles = statusResult.output
          .split(RegExp(r'\r?\n'))
          .map(
            (line) => line.length > 3 ? line.substring(3).trim() : line.trim(),
          )
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      final supportsSplit = await _supportsSplitBuildDeploy(fastfile);
      if (!supportsSplit) {
        _requiredScript(config.project, ReleaseScriptKind.deploy);
      }

      final steps = <ReleaseWorkflowStepRun>[
        ReleaseWorkflowStepRun(
          kind: ReleaseWorkflowStepKind.preflight,
          label: 'Preflight',
          status: ReleaseStepStatus.succeeded,
          startedAt: createdAt,
          finishedAt: DateTime.now(),
          logLines: [
            'Git branch: $branch',
            'Track: $normalizedTrack',
            'Current version: ${localVersion.raw}',
            'Next version: $nextName+$nextCode',
            if (changedFiles.isEmpty)
              'Working tree is clean.'
            else
              '${changedFiles.length} existing change(s) will be committed.',
            supportsSplit
                ? 'Fastlane supports separate build and upload.'
                : 'Legacy Fastlane contract: build and deploy will run together.',
          ],
        ),
        const ReleaseWorkflowStepRun(
          kind: ReleaseWorkflowStepKind.versionCode,
          label: 'Version code',
        ),
        const ReleaseWorkflowStepRun(
          kind: ReleaseWorkflowStepKind.versionName,
          label: 'Version name',
        ),
        const ReleaseWorkflowStepRun(
          kind: ReleaseWorkflowStepKind.releaseNotes,
          label: 'Release notes',
        ),
        const ReleaseWorkflowStepRun(
          kind: ReleaseWorkflowStepKind.commit,
          label: 'Commit & push',
        ),
        if (supportsSplit) ...const [
          ReleaseWorkflowStepRun(
            kind: ReleaseWorkflowStepKind.build,
            label: 'Build AAB',
          ),
          ReleaseWorkflowStepRun(
            kind: ReleaseWorkflowStepKind.deploy,
            label: 'Deploy',
          ),
        ] else
          const ReleaseWorkflowStepRun(
            kind: ReleaseWorkflowStepKind.legacyBuildDeploy,
            label: 'Build & Deploy (legacy)',
          ),
        const ReleaseWorkflowStepRun(
          kind: ReleaseWorkflowStepKind.release,
          label: 'Release',
        ),
      ];

      final run = ReleaseWorkflowRun(
        id: 'release_${createdAt.microsecondsSinceEpoch}',
        projectPath: config.project.path,
        projectName: config.playProject.name,
        track: normalizedTrack,
        currentBranch: branch,
        currentVersion: localVersion.raw,
        proposedVersion: '$nextName+$nextCode',
        changedFiles: changedFiles,
        supportsSplitBuildDeploy: supportsSplit,
        steps: steps,
        createdAt: createdAt,
      );
      currentRun.value = run;
      return run;
    } catch (error) {
      final message = error.toString();
      currentRun.value = ReleaseWorkflowRun(
        id: 'release_${createdAt.microsecondsSinceEpoch}',
        projectPath: config.project.path,
        projectName: config.playProject.name,
        track: config.track,
        currentBranch: '',
        currentVersion: config.project.pubspecVersion ?? '-',
        proposedVersion: '-',
        changedFiles: const [],
        supportsSplitBuildDeploy: false,
        steps: [
          ReleaseWorkflowStepRun(
            kind: ReleaseWorkflowStepKind.preflight,
            label: 'Preflight',
            status: ReleaseStepStatus.failed,
            startedAt: createdAt,
            finishedAt: DateTime.now(),
            error: message,
            logLines: [message],
          ),
        ],
        createdAt: createdAt,
        finishedAt: DateTime.now(),
      );
      if (error is ReleaseWorkflowException) rethrow;
      throw ReleaseWorkflowException(message);
    } finally {
      isPreparing.value = false;
    }
  }

  Future<ReleaseWorkflowRun> start({
    ReleaseWorkflowPostProcessor? postProcessor,
  }) async {
    final run = currentRun.value;
    final config = _config;
    if (run == null || config == null) {
      throw const ReleaseWorkflowException('Prepare the release first.');
    }
    if (run.steps.first.status != ReleaseStepStatus.succeeded) {
      throw const ReleaseWorkflowException(
        'Preflight must pass before release.',
      );
    }
    if (isRunning || runner.isBusy) {
      throw const ReleaseWorkflowException('A command is already running.');
    }

    _postProcessor = postProcessor;
    _cancelRequested = false;
    runner.clearLog();
    final pendingCount = run.steps
        .where((step) => step.status == ReleaseStepStatus.pending)
        .length;
    final extraPostSteps = config.postReleaseStepCount > 1
        ? config.postReleaseStepCount - 1
        : 0;
    runner.beginWorkflow(
      totalSteps: pendingCount + extraPostSteps,
      label: 'Release ${run.projectName} to ${run.track}',
    );
    currentRun.value = run.copyWith(
      startedAt: run.startedAt ?? DateTime.now(),
      clearFinishedAt: true,
    );
    return _runPendingSteps();
  }

  Future<void> cancel() async {
    if (!isRunning) return;
    _cancelRequested = true;
    await runner.stop();
  }

  Future<ReleaseWorkflowRun> retryFailedStep() async {
    final run = currentRun.value;
    if (run == null || run.retryableStep == null) {
      throw const ReleaseWorkflowException('There is no retryable step.');
    }
    if (isRunning || runner.isBusy) {
      throw const ReleaseWorkflowException('A command is already running.');
    }

    final retryIndex = run.steps.indexOf(run.retryableStep!);
    final steps = run.steps.toList();
    for (var index = retryIndex; index < steps.length; index++) {
      if (steps[index].status == ReleaseStepStatus.succeeded ||
          steps[index].status == ReleaseStepStatus.skipped) {
        continue;
      }
      steps[index] = steps[index].copyWith(
        status: ReleaseStepStatus.pending,
        clearStartedAt: true,
        clearFinishedAt: true,
        clearExitCode: true,
        logLines: const [],
        clearError: true,
        retryable: false,
      );
    }
    currentRun.value = run.copyWith(steps: steps, clearFinishedAt: true);
    return start(postProcessor: _postProcessor);
  }

  Future<ReleaseWorkflowRun> resume() => retryFailedStep();

  Future<ReleaseWorkflowRun> _runPendingSteps() async {
    var succeeded = true;
    final initialRun = currentRun.value!;
    try {
      for (var index = 0; index < initialRun.steps.length; index++) {
        final step = currentRun.value!.steps[index];
        if (step.status != ReleaseStepStatus.pending) continue;
        if (_cancelRequested) {
          _updateStep(
            index,
            step.copyWith(
              status: ReleaseStepStatus.canceled,
              startedAt: DateTime.now(),
              finishedAt: DateTime.now(),
              error: 'Release was canceled.',
            ),
          );
          succeeded = false;
          break;
        }

        final outcome = await _executeStep(index, step.kind);
        if (outcome == ReleaseStepStatus.failed ||
            outcome == ReleaseStepStatus.canceled) {
          succeeded = false;
          break;
        }
      }
    } finally {
      final next = currentRun.value!;
      final completed =
          succeeded &&
          next.steps.every(
            (step) =>
                step.status == ReleaseStepStatus.succeeded ||
                step.status == ReleaseStepStatus.warning ||
                step.status == ReleaseStepStatus.skipped,
          );
      currentRun.value = next.copyWith(finishedAt: DateTime.now());
      runner.finishWorkflow(success: completed);
    }
    return currentRun.value!;
  }

  Future<ReleaseStepStatus> _executeStep(
    int index,
    ReleaseWorkflowStepKind kind,
  ) async {
    final startedAt = DateTime.now();
    final original = currentRun.value!.steps[index];
    _updateStep(
      index,
      original.copyWith(
        status: ReleaseStepStatus.running,
        startedAt: startedAt,
        clearFinishedAt: true,
        clearError: true,
      ),
    );

    try {
      final result = await switch (kind) {
        ReleaseWorkflowStepKind.versionCode => _updateVersionCode(),
        ReleaseWorkflowStepKind.versionName => _updateVersionName(),
        ReleaseWorkflowStepKind.releaseNotes => _generateReleaseNotes(),
        ReleaseWorkflowStepKind.commit => _commitAndPush(),
        ReleaseWorkflowStepKind.build => _buildAab(),
        ReleaseWorkflowStepKind.deploy => _deployBuiltAab(),
        ReleaseWorkflowStepKind.legacyBuildDeploy => _legacyBuildAndDeploy(),
        ReleaseWorkflowStepKind.release => _verifyAndPostProcess(),
        ReleaseWorkflowStepKind.preflight => Future.value(const _StepResult()),
      };

      if (_cancelRequested) {
        _updateStep(
          index,
          currentRun.value!.steps[index].copyWith(
            status: ReleaseStepStatus.canceled,
            finishedAt: DateTime.now(),
            exitCode: result.exitCode,
            logLines: result.logLines,
            error: 'Release was canceled.',
            artifactPath: result.artifactPath,
          ),
        );
        return ReleaseStepStatus.canceled;
      }

      final status = result.warning == null
          ? ReleaseStepStatus.succeeded
          : ReleaseStepStatus.warning;
      _updateStep(
        index,
        currentRun.value!.steps[index].copyWith(
          status: status,
          finishedAt: DateTime.now(),
          exitCode: result.exitCode,
          logLines: result.logLines,
          error: result.warning,
          artifactPath: result.artifactPath,
          retryable: result.warning != null && result.retryableWarning,
        ),
      );
      if (result.artifactPath != null) {
        currentRun.value = currentRun.value!.copyWith(
          artifactPath: result.artifactPath,
        );
      }
      return status;
    } catch (error) {
      final message = error.toString();
      _updateStep(
        index,
        currentRun.value!.steps[index].copyWith(
          status: _cancelRequested
              ? ReleaseStepStatus.canceled
              : ReleaseStepStatus.failed,
          finishedAt: DateTime.now(),
          error: message,
          logLines: [...currentRun.value!.steps[index].logLines, message],
        ),
      );
      runner.appendSystemLog(message);
      return _cancelRequested
          ? ReleaseStepStatus.canceled
          : ReleaseStepStatus.failed;
    }
  }

  Future<_StepResult> _updateVersionCode() async {
    final config = _config!;
    final run = currentRun.value!;
    final nextCode = run.proposedVersion.split('+').last;
    return _withPlayEnvironment((environment) async {
      final result = await runner.runWithOutput(
        project: config.project,
        script: _requiredScript(config.project, ReleaseScriptKind.versionCode),
        args: ['manual', nextCode],
        environment: environment,
        clearLog: false,
        allowDuringWorkflow: true,
      );
      _requireSuccess(result, 'Version code update');
      return _StepResult(
        exitCode: result.exitCode,
        logLines: _outputLines(result.output),
      );
    });
  }

  Future<_StepResult> _updateVersionName() async {
    final config = _config!;
    final nextName = currentRun.value!.proposedVersion.split('+').first;
    final result = await runner.runWithOutput(
      project: config.project,
      script: _requiredScript(config.project, ReleaseScriptKind.versionName),
      args: ['manual', nextName],
      environment: _baseEnvironment,
      clearLog: false,
      allowDuringWorkflow: true,
    );
    _requireSuccess(result, 'Version name update');
    return _StepResult(
      exitCode: result.exitCode,
      logLines: _outputLines(result.output),
    );
  }

  Future<_StepResult> _generateReleaseNotes() async {
    final config = _config!;
    runner.beginWorkflowStep('Generate release notes');
    var succeeded = false;
    try {
      final refreshedProject = await catalog.inspect(config.project.path);
      String notes;
      String source;
      if (config.geminiApiKey.trim().isNotEmpty) {
        try {
          final generated = await releaseNotesGenerator.generate(
            project: refreshedProject,
            apiKey: config.geminiApiKey,
            customPrompt: config.releaseNotePrompt,
          );
          notes = generated.notes;
          source =
              'Generated by Gemini from ${generated.gitRangeLabel} (${generated.commitCount} commits).';
        } catch (error) {
          notes = await _fallbackReleaseNotes(config.project.path);
          source = 'Gemini failed; used Git history fallback: $error';
        }
      } else {
        notes = await _fallbackReleaseNotes(config.project.path);
        source = 'Gemini key unavailable; used Git history fallback.';
      }
      notes = _limitPlayReleaseNotes(notes);
      final code = int.parse(currentRun.value!.proposedVersion.split('+').last);
      await _writeChangelogs(config.project.path, code, notes);
      currentRun.value = currentRun.value!.copyWith(releaseNotes: notes);
      runner.appendSystemLog(source);
      runner.appendSystemLog(
        'Prepared CH Play changelog for version code $code.',
      );
      succeeded = true;
      return _StepResult(logLines: [source, notes]);
    } finally {
      runner.completeWorkflowStep(success: succeeded);
    }
  }

  Future<_StepResult> _commitAndPush() async {
    final config = _config!;
    final run = currentRun.value!;
    final status = await _runGit(config.project.path, const [
      'status',
      '--porcelain',
    ]);
    if (status.output.trim().isEmpty) {
      final push = await runner.runCommandWithOutput(
        workingDirectory: config.project.path,
        statusLabel: 'git push origin ${run.currentBranch}',
        activePath: 'release:git-push',
        executable: 'git',
        arguments: ['push', 'origin', run.currentBranch],
        clearLog: false,
        allowDuringWorkflow: true,
      );
      _requireSuccess(push, 'Git push');
      return _StepResult(
        exitCode: push.exitCode,
        logLines: _outputLines(push.output),
      );
    }

    final message = 'chore(release): v${run.proposedVersion}';
    final result = await runner.runWithOutput(
      project: config.project,
      script: _requiredScript(config.project, ReleaseScriptKind.commit),
      args: [
        '--yes',
        message,
        run.currentBranch,
        'Automated Android release to ${run.track}.',
      ],
      environment: _baseEnvironment,
      clearLog: false,
      allowDuringWorkflow: true,
    );
    _requireSuccess(result, 'Commit and push');
    return _StepResult(
      exitCode: result.exitCode,
      logLines: _outputLines(result.output),
    );
  }

  Future<_StepResult> _buildAab() async {
    final config = _config!;
    final lane = _requiredLane(config.project, 'build_aab');
    final flavor = _readAndroidFlavor(config.project.path);
    final result = await runner.runFastlaneLaneWithOutput(
      project: config.project,
      lane: lane,
      args: [if (flavor != null) 'flavor:$flavor'],
      environment: {
        ..._baseEnvironment,
        // ignore: use_null_aware_elements
        if (flavor != null) 'ANDROID_FLAVOR': flavor,
      },
      clearLog: false,
      allowDuringWorkflow: true,
    );
    _requireSuccess(result, 'AAB build');
    final artifact =
        _artifactFromOutput(result.output) ??
        _findNewestAab(config.project.path)?.path;
    if (artifact == null) {
      throw const ReleaseWorkflowException(
        'AAB build completed but no artifact was found.',
      );
    }
    runner.appendSystemLog('AAB ready: $artifact');
    return _StepResult(
      exitCode: result.exitCode,
      logLines: _outputLines(result.output),
      artifactPath: artifact,
    );
  }

  Future<_StepResult> _deployBuiltAab() async {
    final config = _config!;
    final lane = _requiredLane(config.project, 'upload_to_chplay');
    final flavor = _readAndroidFlavor(config.project.path);
    return _withPlayEnvironment((environment) async {
      final result = await runner.runFastlaneLaneWithOutput(
        project: config.project,
        lane: lane,
        args: [
          'track:${currentRun.value!.track}',
          'skip_build:true',
          if (flavor != null) 'flavor:$flavor',
          if (currentRun.value!.releaseNotes.isNotEmpty)
            'update_description:${currentRun.value!.releaseNotes}',
        ],
        environment: {
          ...environment,
          'SKIP_PLAY_BUILD': '1',
          'UPLOAD_PLAY_IMAGES': config.uploadListingImages ? '1' : '0',
          if (!config.validateListingImages) 'SKIP_PLAY_IMAGE_CHECK': '1',
          // ignore: use_null_aware_elements
          if (flavor != null) 'ANDROID_FLAVOR': flavor,
        },
        clearLog: false,
        allowDuringWorkflow: true,
      );
      _requireSuccess(result, 'CH Play deploy');
      return _StepResult(
        exitCode: result.exitCode,
        logLines: _outputLines(result.output),
        artifactPath: currentRun.value!.artifactPath,
      );
    });
  }

  Future<_StepResult> _legacyBuildAndDeploy() async {
    final config = _config!;
    return _withPlayEnvironment((environment) async {
      final result = await runner.runWithOutput(
        project: config.project,
        script: _requiredScript(config.project, ReleaseScriptKind.deploy),
        args: [
          if (config.project.hasFirebaseDeployTools) 'no',
          'yes',
          if (currentRun.value!.releaseNotes.isNotEmpty)
            currentRun.value!.releaseNotes,
        ],
        environment: {
          ...environment,
          if (config.project.hasFirebaseDeployTools) 'DEPLOY_LEGACY_ARGS': '1',
          'UPLOAD_PLAY_IMAGES': config.uploadListingImages ? '1' : '0',
          if (!config.validateListingImages) 'SKIP_PLAY_IMAGE_CHECK': '1',
        },
        clearLog: false,
        allowDuringWorkflow: true,
      );
      _requireSuccess(result, 'Legacy build and deploy');
      final artifact = _findNewestAab(config.project.path)?.path;
      return _StepResult(
        exitCode: result.exitCode,
        logLines: [
          'Compatibility mode: the legacy deploy command built and uploaded the AAB.',
          ..._outputLines(result.output),
        ],
        artifactPath: artifact,
      );
    });
  }

  Future<_StepResult> _verifyAndPostProcess() async {
    final config = _config!;
    final run = currentRun.value!;
    runner.beginWorkflowStep('Verify CH Play release');
    final expectedCode = int.parse(run.proposedVersion.split('+').last);
    final trackedProject = config.playProject.copyWith(track: run.track);
    final deadline = DateTime.now().add(verificationTimeout);
    String? verificationWarning;
    var verified = false;

    while (!_cancelRequested) {
      final snapshot = await chPlayVersionChecker.refreshProject(
        project: trackedProject,
        credentials: config.credentials,
        clearLog: false,
        allowDuringWorkflow: true,
        trackWorkflowStep: false,
      );
      if ((snapshot.storeVersionCode ?? -1) >= expectedCode) {
        verified = true;
        runner.appendSystemLog(
          'CH Play verified version code ${snapshot.storeVersionCode} on ${run.track}.',
        );
        break;
      }
      if (DateTime.now().isAfter(deadline) ||
          verificationTimeout == Duration.zero) {
        verificationWarning =
            'Upload succeeded, but CH Play did not expose version code $expectedCode within ${verificationTimeout.inMinutes} minute(s).';
        runner.appendSystemLog(verificationWarning);
        break;
      }
      await Future<void>.delayed(verificationInterval);
    }

    String? postWarning;
    String? artifactPath = currentRun.value!.artifactPath;
    final postProcessor = _postProcessor;
    if (!_cancelRequested &&
        postProcessor != null &&
        !_postProcessingCompleted) {
      final refreshedProject = await catalog.inspect(config.project.path);
      final postResult = await postProcessor(
        ReleaseWorkflowPostContext(
          project: refreshedProject,
          appDisplayName: config.playProject.name,
          fullVersion: run.proposedVersion,
          releaseNotes: currentRun.value!.releaseNotes,
        ),
      );
      artifactPath = postResult.artifactPath ?? artifactPath;
      postWarning = postResult.warning;
      _postProcessingCompleted = true;
      _postProcessingWarning = postWarning;
    } else if (_postProcessingCompleted) {
      postWarning = _postProcessingWarning;
      runner.appendSystemLog(
        'Post-processing already completed; verification retry will not resend artifacts.',
      );
    }
    runner.completeWorkflowStep(success: true);

    final warnings = [?verificationWarning, ?postWarning];
    return _StepResult(
      logLines: [
        verified
            ? 'CH Play release verified on ${run.track}.'
            : verificationWarning ?? 'Release verification was canceled.',
        ?postWarning,
      ],
      artifactPath: artifactPath,
      warning: warnings.isEmpty ? null : warnings.join('\n'),
      retryableWarning: verificationWarning != null,
    );
  }

  Future<T> _withPlayEnvironment<T>(
    Future<T> Function(Map<String, String> environment) action,
  ) async {
    final config = _config!;
    final tempDirectory = await Directory.systemTemp.createTemp(
      'app_release_center_workflow_',
    );
    try {
      final jsonFile = File(p.join(tempDirectory.path, 'google-play-key.json'));
      await jsonFile.writeAsString(config.credentials.googlePlayJson!.trim());
      return await action({
        ..._baseEnvironment,
        'FASTLANE_KEY_PATH': jsonFile.path,
        'ANDROID_PACKAGE_NAME': config.playProject.applicationId.trim(),
        'PLAY_TRACK': currentRun.value?.track ?? config.track,
      });
    } finally {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  }

  void _updateStep(int index, ReleaseWorkflowStepRun step) {
    final run = currentRun.value!;
    final steps = run.steps.toList();
    steps[index] = step;
    currentRun.value = run.copyWith(steps: steps);
  }

  ReleaseScript _requiredScript(
    ReleaseProject project,
    ReleaseScriptKind kind,
  ) {
    for (final script in project.scripts) {
      if (script.kind == kind) return script;
    }
    throw ReleaseWorkflowException(
      'Missing required ${kind.name} automation script.',
    );
  }

  ReleaseFastlaneLane _requiredLane(ReleaseProject project, String name) {
    for (final lane in project.fastlaneLanes) {
      if (lane.name == name) return lane;
    }
    throw ReleaseWorkflowException('Missing Fastlane lane: $name.');
  }

  Future<bool> _supportsSplitBuildDeploy(File fastfile) async {
    final source = await fastfile.readAsString();
    return RegExp(r'lane\s+:build_aab\b').hasMatch(source) &&
        RegExp(r'(skip_build|SKIP_PLAY_BUILD)').hasMatch(source);
  }

  String _bumpVersionName(String current) {
    final match = RegExp(r'^(.*_)?([0-9]+(?:\.[0-9]+)*)$').firstMatch(current);
    if (match == null) {
      throw ReleaseWorkflowException(
        'Cannot automatically bump version name "$current".',
      );
    }
    final prefix = match.group(1) ?? '';
    final parts = match.group(2)!.split('.').map(int.parse).toList();
    parts[parts.length - 1]++;
    return '$prefix${parts.join('.')}';
  }

  Future<_GitResult> _runGit(
    String workingDirectory,
    List<String> arguments, {
    String? failureMessage,
  }) async {
    try {
      final result = await Process.run(
        'git',
        arguments,
        workingDirectory: workingDirectory,
        runInShell: false,
      );
      final output = '${result.stdout}${result.stderr}'.trim();
      if (result.exitCode != 0) {
        throw ReleaseWorkflowException(
          failureMessage ?? 'Git command failed: $output',
        );
      }
      return _GitResult(exitCode: result.exitCode, output: output);
    } on ProcessException catch (error) {
      throw ReleaseWorkflowException(
        failureMessage ?? 'Failed to run Git: ${error.message}',
      );
    }
  }

  Future<String> _fallbackReleaseNotes(String projectPath) async {
    final result = await _runGit(projectPath, const [
      'log',
      '-n',
      '12',
      '--pretty=format:%s',
    ]);
    final seen = <String>{};
    final subjects = result.output
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && seen.add(line.toLowerCase()))
        .take(8)
        .toList();
    if (subjects.isEmpty) {
      return 'Cải thiện độ ổn định và hiệu năng.';
    }
    return subjects.map((subject) => '- $subject').join('\n');
  }

  String _limitPlayReleaseNotes(String notes) {
    final normalized = notes.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');
    if (normalized.length <= _playReleaseNoteLimit) return normalized;
    final truncated = normalized.substring(0, _playReleaseNoteLimit - 1);
    final lastBreak = truncated.lastIndexOf('\n');
    return '${lastBreak > 100 ? truncated.substring(0, lastBreak) : truncated}…';
  }

  Future<void> _writeChangelogs(
    String projectPath,
    int versionCode,
    String notes,
  ) async {
    final directory = Directory(
      p.join(
        projectPath,
        'android',
        'fastlane',
        'metadata',
        'android',
        'vi',
        'changelogs',
      ),
    );
    await directory.create(recursive: true);
    await File(
      p.join(directory.path, '$versionCode.txt'),
    ).writeAsString('$notes\n');
    await File(p.join(directory.path, 'default.txt')).writeAsString('$notes\n');
  }

  String? _readAndroidFlavor(String projectPath) {
    final envFile = File(p.join(projectPath, 'android', 'env.properties'));
    if (!envFile.existsSync()) return null;
    for (final line in envFile.readAsLinesSync()) {
      final match = RegExp(
        r'^\s*ANDROID_FLAVOR\s*=\s*(.*?)\s*$',
      ).firstMatch(line);
      final flavor = match?.group(1)?.trim();
      if (flavor != null && flavor.isNotEmpty) return flavor;
    }
    return null;
  }

  String? _artifactFromOutput(String output) {
    final matches = RegExp(
      r'ARC_AAB_PATH:(.+)',
      multiLine: true,
    ).allMatches(output);
    if (matches.isEmpty) return null;
    final path = matches.last.group(1)?.trim();
    return path == null || path.isEmpty ? null : path;
  }

  File? _findNewestAab(String projectPath) {
    final root = Directory(
      p.join(projectPath, 'build', 'app', 'outputs', 'bundle'),
    );
    if (!root.existsSync()) return null;
    final files =
        root
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.aab'))
            .toList()
          ..sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
          );
    return files.isEmpty ? null : files.first;
  }

  void _requireSuccess(CommandRunResult result, String label) {
    if (result.exitCode != 0) {
      throw ReleaseWorkflowException(
        '$label failed with exit code ${result.exitCode}.',
      );
    }
  }

  List<String> _outputLines(String output) {
    return output
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }
}

class _StepResult {
  const _StepResult({
    this.exitCode,
    this.logLines = const [],
    this.artifactPath,
    this.warning,
    this.retryableWarning = false,
  });

  final int? exitCode;
  final List<String> logLines;
  final String? artifactPath;
  final String? warning;
  final bool retryableWarning;
}

class _GitResult {
  const _GitResult({required this.exitCode, required this.output});

  final int exitCode;
  final String output;
}

const _supportedTracks = {'internal', 'alpha', 'beta', 'production'};
const _playReleaseNoteLimit = 500;
const _baseEnvironment = {
  'FASTLANE_SKIP_SCREEN': '1',
  'TTY_SCREEN_WIDTH': '120',
  'TTY_SCREEN_HEIGHT': '40',
};
