import 'package:app_management_center/app/models/app_store_project.dart';
import 'package:app_management_center/app/models/release_workflow.dart';

class IosReleaseSettings {
  const IosReleaseSettings({
    this.scheme = 'Runner',
    this.configuration = 'Release',
    this.entrypoint = 'lib/main.dart',
    this.flavor = '',
    this.exportOptionsPath = '',
    this.flutterExecutable = '',
    this.teamId = '',
    this.groups = const [],
    this.externalTesting = false,
    this.locale = 'vi-VN',
    this.useAppStoreLocale = false,
    this.notes = '',
    this.automaticRelease = false,
    this.extraBuildArguments = const [],
    this.remoteFiles = const [],
  });
  final String scheme, configuration, entrypoint, flavor, exportOptionsPath;
  final String flutterExecutable, teamId, locale, notes;
  final List<String> groups, extraBuildArguments;
  final bool externalTesting, automaticRelease, useAppStoreLocale;

  /// Gitignored files, relative to the project, that a Mac build host needs
  /// and cannot get from the commit — `.env`, `GoogleService-Info.plist`.
  /// Sent sealed with each remote build; unused when building locally.
  final List<String> remoteFiles;

  Map<String, dynamic> toJson() => {
    'scheme': scheme,
    'configuration': configuration,
    'entrypoint': entrypoint,
    'flavor': flavor,
    'exportOptionsPath': exportOptionsPath,
    'flutterExecutable': flutterExecutable,
    'teamId': teamId,
    'groups': groups,
    'externalTesting': externalTesting,
    'locale': locale,
    'useAppStoreLocale': useAppStoreLocale,
    'notes': notes,
    'automaticRelease': automaticRelease,
    'extraBuildArguments': extraBuildArguments,
    'remoteFiles': remoteFiles,
  };
  factory IosReleaseSettings.fromJson(Map<String, dynamic> json) =>
      IosReleaseSettings(
        scheme: json['scheme'] as String? ?? 'Runner',
        configuration: json['configuration'] as String? ?? 'Release',
        entrypoint: json['entrypoint'] as String? ?? 'lib/main.dart',
        flavor: json['flavor'] as String? ?? '',
        exportOptionsPath: json['exportOptionsPath'] as String? ?? '',
        flutterExecutable: json['flutterExecutable'] as String? ?? '',
        teamId: json['teamId'] as String? ?? '',
        groups: List<String>.from(json['groups'] as List? ?? []),
        externalTesting: json['externalTesting'] == true,
        locale:
            !json.containsKey('useAppStoreLocale') &&
                (json['locale'] == null ||
                    json['locale'] == '' ||
                    json['locale'] == 'en-US')
            ? 'vi-VN'
            : json['locale'] as String? ?? 'vi-VN',
        useAppStoreLocale: json['useAppStoreLocale'] as bool? ?? false,
        notes: json['notes'] as String? ?? '',
        automaticRelease: json['automaticRelease'] == true,
        extraBuildArguments: List<String>.from(
          json['extraBuildArguments'] as List? ?? [],
        ),
        remoteFiles: List<String>.from(json['remoteFiles'] as List? ?? []),
      );
}

enum IosReleaseStatus {
  prepared,
  building,
  built,
  uploading,
  processing,
  ready,
  draft,
  submitted,
  released,
  failed,
  canceled,
  verificationRequired,
}

class IosStoreBuild {
  const IosStoreBuild({
    required this.id,
    required this.version,
    required this.number,
    required this.processingState,
    this.expired = false,
  });
  final String id, version, processingState;
  final int number;
  final bool expired;
  bool get isReady => processingState == 'VALID' && !expired;
  Map<String, dynamic> toJson() => {
    'id': id,
    'version': version,
    'number': number,
    'state': processingState,
    'expired': expired,
  };
  factory IosStoreBuild.fromJson(Map<String, dynamic> json) => IosStoreBuild(
    id: json['id'] as String,
    version: json['version'] as String,
    number: int.parse(json['number'].toString()),
    processingState: json['state'] as String,
    expired: json['expired'] == true,
  );
}

class IosStoreState {
  const IosStoreState({
    this.builds = const [],
    this.versions = const [],
    this.primaryLocale,
  });
  final List<IosStoreBuild> builds;
  final List<Map<String, dynamic>> versions;
  final String? primaryLocale;
  Map<String, dynamic> toJson() => {
    'primaryLocale': primaryLocale,
    'builds': builds.map((build) => build.toJson()).toList(),
    'versions': versions,
  };
  factory IosStoreState.fromJson(Map<String, dynamic> json) => IosStoreState(
    primaryLocale: json['primaryLocale'] as String?,
    builds: (json['builds'] as List? ?? [])
        .map((e) => IosStoreBuild.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    versions: (json['versions'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
  );
  IosStoreBuild? findBuild(String version, int number) {
    for (final build in builds) {
      if (build.version == version && build.number == number) return build;
    }
    return null;
  }
}

class IosReleaseRun {
  IosReleaseRun({
    required this.id,
    required this.project,
    required this.settings,
    required this.version,
    required this.buildNumber,
    required this.directory,
    required this.commit,
    required this.dirty,
    required this.createdAt,
    this.status = IosReleaseStatus.prepared,
    this.ipaPath,
    this.ipaHash,
    this.archivePath,
    this.sourceHash,
    this.message = '',
    this.lastAction = 'prepare',
    this.uploadAttempted = false,
    this.steps = const [],
    this.store = const IosStoreState(),
  });
  final String id, version, directory;
  String commit;
  final AppStoreProject project;
  final IosReleaseSettings settings;
  final int buildNumber;
  bool dirty;
  final DateTime createdAt;
  IosReleaseStatus status;
  String? ipaPath, ipaHash, archivePath, sourceHash;
  String message, lastAction;
  bool uploadAttempted;
  List<Map<String, dynamic>> steps;
  IosStoreState store;
  Map<String, dynamic> toJson() => {
    'id': id,
    'project': project.toJson(),
    'settings': settings.toJson(),
    'version': version,
    'buildNumber': buildNumber,
    'directory': directory,
    'commit': commit,
    'dirty': dirty,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'ipaPath': ipaPath,
    'ipaHash': ipaHash,
    'archivePath': archivePath,
    'sourceHash': sourceHash,
    'message': message,
    'lastAction': lastAction,
    'uploadAttempted': uploadAttempted,
    'steps': steps,
  };
  factory IosReleaseRun.fromJson(Map<String, dynamic> json) => IosReleaseRun(
    id: json['id'] as String,
    project: AppStoreProject.fromJson(
      Map<String, dynamic>.from(json['project'] as Map),
    ),
    settings: IosReleaseSettings.fromJson(
      Map<String, dynamic>.from(json['settings'] as Map),
    ),
    version: json['version'] as String,
    buildNumber: json['buildNumber'] as int,
    directory: json['directory'] as String,
    commit: json['commit'] as String,
    dirty: json['dirty'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
    status: IosReleaseStatus.values.byName(json['status'] as String),
    ipaPath: json['ipaPath'] as String?,
    ipaHash: json['ipaHash'] as String?,
    archivePath: json['archivePath'] as String?,
    sourceHash: json['sourceHash'] as String?,
    message: json['message'] as String? ?? '',
    lastAction: json['lastAction'] as String? ?? 'prepare',
    uploadAttempted: json['uploadAttempted'] == true,
    steps: (json['steps'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
  );
}

/// A run as it crosses the relay between a build host and the desktop
/// driving it. The manifest leaves the App Store state out; the remote side
/// needs it to offer the right next step, so it travels alongside.
Map<String, dynamic> iosRunToWire(IosReleaseRun run) => {
  ...run.toJson(),
  'store': run.store.toJson(),
};

IosReleaseRun iosRunFromWire(Map<String, dynamic> json) =>
    IosReleaseRun.fromJson(json)
      ..store = json['store'] is Map
          ? IosStoreState.fromJson(
              Map<String, dynamic>.from(json['store'] as Map),
            )
          : const IosStoreState();

/// The next thing a run offers to do, as a button. Shared by the desktop
/// dialog and the phone, so both offer the same step for the same run.
///
/// [id] is `testflight`, `wait`, `refresh`, `new`, or a store action:
/// `draft`, `submit`, `release`, `distribute`.
class IosNextStep {
  const IosNextStep(this.id, this.label);

  final String id;
  final String label;

  bool get isStoreAction =>
      const ['draft', 'submit', 'release', 'distribute'].contains(id);
}

IosNextStep iosStoreStep(String action, {String? label}) => IosNextStep(
  action,
  label ??
      switch (action) {
        'distribute' => 'Phân phối TestFlight',
        'draft' => 'Chuẩn bị App Store',
        'submit' => 'Gửi review',
        _ => 'Phát hành',
      },
);

IosNextStep iosPrimaryStep(IosReleaseRun run) => switch (run.status) {
  IosReleaseStatus.prepared || IosReleaseStatus.built => IosNextStep(
    'testflight',
    run.ipaPath == null ? 'Build & upload TestFlight' : 'Upload TestFlight',
  ),
  IosReleaseStatus.processing => const IosNextStep(
    'wait',
    'Theo dõi processing',
  ),
  IosReleaseStatus.verificationRequired ||
  IosReleaseStatus.building ||
  IosReleaseStatus.uploading => const IosNextStep(
    'refresh',
    'Kiểm tra lại Apple',
  ),
  IosReleaseStatus.ready => iosStoreStep('draft'),
  IosReleaseStatus.draft => iosStoreStep('submit'),
  IosReleaseStatus.submitted =>
    run.store.versions.any(
          (version) =>
              version['version'] == run.version &&
              version['state'] == 'PENDING_DEVELOPER_RELEASE',
        )
        ? iosStoreStep('release')
        : const IosNextStep('refresh', 'Làm mới trạng thái'),
  IosReleaseStatus.released => const IosNextStep('new', 'Release mới'),
  IosReleaseStatus.failed ||
  IosReleaseStatus.canceled => switch (run.lastAction) {
    'build' || 'upload' => const IosNextStep('testflight', 'Chạy lại bước lỗi'),
    'query' => const IosNextStep('refresh', 'Kiểm tra lại Apple'),
    'draft' ||
    'submit' ||
    'release' ||
    'distribute' => iosStoreStep(run.lastAction, label: 'Chạy lại bước lỗi'),
    _ => const IosNextStep('new', 'Chuẩn bị lại'),
  },
};

IosNextStep? iosSecondaryStep(IosReleaseRun run, IosNextStep primary) {
  if (run.status == IosReleaseStatus.ready && run.settings.groups.isNotEmpty) {
    return iosStoreStep('distribute');
  }
  if ((run.status == IosReleaseStatus.failed ||
          run.status == IosReleaseStatus.canceled) &&
      primary.id != 'new') {
    return const IosNextStep('new', 'Release mới');
  }
  return null;
}

/// The linear path a release follows, as shown on the release timeline.
enum IosReleaseStage {
  prepare,
  build,
  upload,
  processing,
  appStore,
  review,
  release,
}

extension IosReleaseRunStages on IosReleaseRun {
  /// A build picked from TestFlight has no local IPA and was never uploaded
  /// by this run.
  bool get reusesBuild => uploadAttempted && ipaPath == null;

  bool succeeded(String action) => steps.any(
    (step) => step['action'] == action && step['status'] == 'succeeded',
  );

  /// Error of the most recent step, if that step failed or was canceled.
  String? get lastError {
    final last = steps.lastOrNull;
    if (last == null || last['status'] == 'succeeded') return null;
    return last['error']?.toString();
  }

  /// The stage an action belongs to. Distributing to TestFlight groups is a
  /// side action of a processed build, so it has no stage of its own.
  static IosReleaseStage? stageOf(String action) => switch (action) {
    'prepare' || 'version' => IosReleaseStage.prepare,
    'build' => IosReleaseStage.build,
    'upload' => IosReleaseStage.upload,
    'query' => IosReleaseStage.processing,
    'draft' => IosReleaseStage.appStore,
    'submit' => IosReleaseStage.review,
    'release' => IosReleaseStage.release,
    _ => null,
  };

  /// Where each stage stands. [running] is the action executing right now
  /// for this run, if any.
  Map<IosReleaseStage, ReleaseStepStatus> stageStatuses({String? running}) {
    final result = {
      for (final stage in IosReleaseStage.values)
        stage: ReleaseStepStatus.pending,
    };
    void through(IosReleaseStage last) {
      for (final stage in IosReleaseStage.values) {
        if (stage.index > last.index) break;
        result[stage] = ReleaseStepStatus.succeeded;
      }
    }

    switch (status) {
      case IosReleaseStatus.prepared:
        through(IosReleaseStage.prepare);
      case IosReleaseStatus.building:
        through(IosReleaseStage.prepare);
        result[IosReleaseStage.build] = ReleaseStepStatus.running;
      case IosReleaseStatus.built:
        through(IosReleaseStage.build);
      case IosReleaseStatus.uploading:
        through(IosReleaseStage.build);
        result[IosReleaseStage.upload] = ReleaseStepStatus.running;
      case IosReleaseStatus.verificationRequired:
        through(IosReleaseStage.build);
        result[IosReleaseStage.upload] = ReleaseStepStatus.warning;
      case IosReleaseStatus.processing:
        through(IosReleaseStage.upload);
        result[IosReleaseStage.processing] = ReleaseStepStatus.running;
      case IosReleaseStatus.ready:
        through(IosReleaseStage.processing);
      case IosReleaseStatus.draft:
        through(IosReleaseStage.appStore);
      case IosReleaseStatus.submitted:
        // Release requested after approval, or still waiting for review.
        if (succeeded('release')) {
          through(IosReleaseStage.review);
          result[IosReleaseStage.release] = ReleaseStepStatus.running;
        } else {
          through(IosReleaseStage.appStore);
          result[IosReleaseStage.review] = ReleaseStepStatus.running;
        }
      case IosReleaseStatus.released:
        through(IosReleaseStage.release);
      case IosReleaseStatus.failed || IosReleaseStatus.canceled:
        final failed = stageOf(lastAction);
        if (failed != null) {
          if (failed.index > 0) {
            through(IosReleaseStage.values[failed.index - 1]);
          }
          result[failed] = status == IosReleaseStatus.canceled
              ? ReleaseStepStatus.canceled
              : ReleaseStepStatus.failed;
        } else {
          // A failed side action leaves the build processed.
          through(IosReleaseStage.processing);
        }
    }
    if (reusesBuild) {
      result[IosReleaseStage.build] = ReleaseStepStatus.skipped;
      result[IosReleaseStage.upload] = ReleaseStepStatus.skipped;
    }
    // A refresh of a finished stage is not progress on it.
    final active = running == null ? null : stageOf(running);
    if (active != null &&
        result[active] != ReleaseStepStatus.succeeded &&
        result[active] != ReleaseStepStatus.skipped) {
      result[active] = ReleaseStepStatus.running;
    }
    return result;
  }
}
