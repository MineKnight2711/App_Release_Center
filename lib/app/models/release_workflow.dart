import 'package:app_release_center/app/models/ch_play_credentials.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/models/release_project.dart';

enum ReleaseStepStatus {
  pending,
  running,
  succeeded,
  failed,
  canceled,
  warning,
  skipped,
}

enum ReleaseWorkflowStepKind {
  preflight,
  versionCode,
  versionName,
  releaseNotes,
  commit,
  build,
  deploy,
  legacyBuildDeploy,
  release,
}

class ReleaseWorkflowConfig {
  const ReleaseWorkflowConfig({
    required this.project,
    required this.playProject,
    required this.credentials,
    required this.track,
    required this.geminiApiKey,
    required this.releaseNotePrompt,
    required this.uploadListingImages,
    required this.validateListingImages,
    this.postReleaseStepCount = 1,
  });

  final ReleaseProject project;
  final ChPlayProject playProject;
  final ChPlayCredentials credentials;
  final String track;
  final String geminiApiKey;
  final String releaseNotePrompt;
  final bool uploadListingImages;
  final bool validateListingImages;
  final int postReleaseStepCount;
}

class ReleaseWorkflowStepRun {
  const ReleaseWorkflowStepRun({
    required this.kind,
    required this.label,
    this.status = ReleaseStepStatus.pending,
    this.startedAt,
    this.finishedAt,
    this.exitCode,
    this.logLines = const [],
    this.error,
    this.artifactPath,
    this.retryable = false,
  });

  final ReleaseWorkflowStepKind kind;
  final String label;
  final ReleaseStepStatus status;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? exitCode;
  final List<String> logLines;
  final String? error;
  final String? artifactPath;
  final bool retryable;

  Duration? get duration {
    final start = startedAt;
    final finish = finishedAt;
    if (start == null) return null;
    return (finish ?? DateTime.now()).difference(start);
  }

  bool get isTerminal => switch (status) {
    ReleaseStepStatus.succeeded ||
    ReleaseStepStatus.failed ||
    ReleaseStepStatus.canceled ||
    ReleaseStepStatus.warning ||
    ReleaseStepStatus.skipped => true,
    ReleaseStepStatus.pending || ReleaseStepStatus.running => false,
  };

  ReleaseWorkflowStepRun copyWith({
    ReleaseStepStatus? status,
    DateTime? startedAt,
    bool clearStartedAt = false,
    DateTime? finishedAt,
    bool clearFinishedAt = false,
    int? exitCode,
    bool clearExitCode = false,
    List<String>? logLines,
    String? error,
    bool clearError = false,
    String? artifactPath,
    bool clearArtifactPath = false,
    bool? retryable,
  }) {
    return ReleaseWorkflowStepRun(
      kind: kind,
      label: label,
      status: status ?? this.status,
      startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
      finishedAt: clearFinishedAt ? null : finishedAt ?? this.finishedAt,
      exitCode: clearExitCode ? null : exitCode ?? this.exitCode,
      logLines: logLines ?? this.logLines,
      error: clearError ? null : error ?? this.error,
      artifactPath: clearArtifactPath
          ? null
          : artifactPath ?? this.artifactPath,
      retryable: retryable ?? this.retryable,
    );
  }
}

class ReleaseWorkflowRun {
  const ReleaseWorkflowRun({
    required this.id,
    required this.projectPath,
    required this.projectName,
    required this.track,
    required this.currentBranch,
    required this.currentVersion,
    required this.proposedVersion,
    required this.changedFiles,
    required this.supportsSplitBuildDeploy,
    required this.steps,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.releaseNotes = '',
    this.artifactPath,
  });

  final String id;
  final String projectPath;
  final String projectName;
  final String track;
  final String currentBranch;
  final String currentVersion;
  final String proposedVersion;
  final List<String> changedFiles;
  final bool supportsSplitBuildDeploy;
  final List<ReleaseWorkflowStepRun> steps;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String releaseNotes;
  final String? artifactPath;

  ReleaseWorkflowStepRun? get activeStep {
    for (final step in steps) {
      if (step.status == ReleaseStepStatus.running) return step;
    }
    return null;
  }

  ReleaseWorkflowStepRun? get retryableStep {
    for (final step in steps) {
      if (step.status == ReleaseStepStatus.failed ||
          step.status == ReleaseStepStatus.canceled ||
          (step.status == ReleaseStepStatus.warning && step.retryable)) {
        return step;
      }
    }
    return null;
  }

  bool get isRunning => activeStep != null;

  bool get isCompleted =>
      steps.isNotEmpty &&
      steps.every(
        (step) =>
            step.status == ReleaseStepStatus.succeeded ||
            step.status == ReleaseStepStatus.warning ||
            step.status == ReleaseStepStatus.skipped,
      );

  bool get hasWarning =>
      steps.any((step) => step.status == ReleaseStepStatus.warning);

  double get progress {
    if (steps.isEmpty) return 0;
    final completed = steps.where((step) => step.isTerminal).length;
    return completed / steps.length;
  }

  Duration? get duration {
    final start = startedAt;
    if (start == null) return null;
    return (finishedAt ?? DateTime.now()).difference(start);
  }

  ReleaseWorkflowRun copyWith({
    List<ReleaseWorkflowStepRun>? steps,
    DateTime? startedAt,
    bool clearStartedAt = false,
    DateTime? finishedAt,
    bool clearFinishedAt = false,
    String? releaseNotes,
    String? artifactPath,
    bool clearArtifactPath = false,
  }) {
    return ReleaseWorkflowRun(
      id: id,
      projectPath: projectPath,
      projectName: projectName,
      track: track,
      currentBranch: currentBranch,
      currentVersion: currentVersion,
      proposedVersion: proposedVersion,
      changedFiles: changedFiles,
      supportsSplitBuildDeploy: supportsSplitBuildDeploy,
      steps: steps ?? this.steps,
      createdAt: createdAt,
      startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
      finishedAt: clearFinishedAt ? null : finishedAt ?? this.finishedAt,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      artifactPath: clearArtifactPath
          ? null
          : artifactPath ?? this.artifactPath,
    );
  }
}

class ReleaseWorkflowPostContext {
  const ReleaseWorkflowPostContext({
    required this.project,
    required this.appDisplayName,
    required this.fullVersion,
    required this.releaseNotes,
  });

  final ReleaseProject project;
  final String appDisplayName;
  final String fullVersion;
  final String releaseNotes;
}

class ReleaseWorkflowPostResult {
  const ReleaseWorkflowPostResult({this.artifactPath, this.warning});

  final String? artifactPath;
  final String? warning;
}

typedef ReleaseWorkflowPostProcessor =
    Future<ReleaseWorkflowPostResult> Function(
      ReleaseWorkflowPostContext context,
    );

class ReleaseWorkflowException implements Exception {
  const ReleaseWorkflowException(this.message);

  final String message;

  @override
  String toString() => message;
}
