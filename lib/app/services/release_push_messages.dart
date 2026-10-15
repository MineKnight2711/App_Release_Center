import 'package:app_management_center/app/models/ios_release.dart';
import 'package:app_management_center/app/models/release_notification.dart';
import 'package:app_management_center/app/models/release_workflow.dart';

/// What the phone says when a release ends.
///
/// Kept apart from the workflows so every message can be read, and tested, in
/// one place. A title names the outcome and the project, because that is all
/// a lock screen shows; the body carries the version and, on failure, why.

ReleasePushEvent androidReleasePush(
  ReleaseWorkflowRun run, {
  required bool completed,
}) {
  final version = run.proposedVersion.trim().isNotEmpty
      ? run.proposedVersion.trim()
      : run.currentVersion.trim();
  final failed = run.steps
      .where((step) => step.status == ReleaseStepStatus.failed)
      .firstOrNull;
  return ReleasePushEvent(
    outcome: completed
        ? ReleasePushOutcome.succeeded
        : ReleasePushOutcome.failed,
    title: completed
        ? 'Release xong · ${run.projectName}'
        : 'Release lỗi · ${run.projectName}',
    body: completed
        ? 'Android $version đã lên ${run.track}.'
        : 'Android $version · ${failed?.label ?? 'Một bước'} lỗi'
              '${_reason(failed?.error)}',
    tag: 'android-${run.id}',
    projectName: run.projectName,
    platform: 'android',
    version: version,
  );
}

/// A change of an iOS run worth buzzing about, or null. Only arrivals count:
/// a refresh that finds the run where it already was says nothing.
ReleasePushEvent? iosStatusPush(IosReleaseRun run, IosReleaseStatus previous) {
  if (run.status == previous) return null;
  final what = switch (run.status) {
    IosReleaseStatus.ready
        when const [
          IosReleaseStatus.processing,
          IosReleaseStatus.uploading,
          IosReleaseStatus.verificationRequired,
          IosReleaseStatus.built,
        ].contains(previous) =>
      'TestFlight sẵn sàng',
    IosReleaseStatus.draft => 'Đã chuẩn bị bản App Store',
    IosReleaseStatus.submitted =>
      run.lastAction == 'release' ? 'Đã yêu cầu phát hành' : 'Đã gửi review',
    IosReleaseStatus.released => 'Đã phát hành App Store',
    _ => null,
  };
  if (what == null) return null;
  return _ios(
    run,
    ReleasePushOutcome.succeeded,
    '$what · ${run.project.name}',
    'iOS ${run.version}+${run.buildNumber}'
        '${run.status == IosReleaseStatus.draft ? ' · chưa gửi review.' : '.'}',
  );
}

ReleasePushEvent iosFailurePush(
  IosReleaseRun run,
  String action,
  String error,
) => _ios(
  run,
  ReleasePushOutcome.failed,
  'Release iOS lỗi · ${run.project.name}',
  'iOS ${run.version}+${run.buildNumber} · ${_iosAction(action)} lỗi'
      '${_reason(error)}',
);

ReleasePushEvent _ios(
  IosReleaseRun run,
  ReleasePushOutcome outcome,
  String title,
  String body,
) => ReleasePushEvent(
  outcome: outcome,
  title: title,
  body: body,
  tag: 'ios-${run.id}',
  projectName: run.project.name,
  platform: 'ios',
  version: '${run.version}+${run.buildNumber}',
);

String _iosAction(String action) => switch (action) {
  'prepare' => 'Preflight',
  'version' => 'Ghi version',
  'build' => 'Build IPA',
  'upload' => 'Upload',
  'query' => 'Kiểm tra Apple',
  'draft' => 'Chuẩn bị App Store',
  'submit' => 'Gửi review',
  'release' => 'Phát hành',
  'distribute' => 'Phân phối TestFlight',
  _ => action,
};

/// The first line of an error, short enough for a notification, without the
/// "Bad state:" Dart puts in front of a StateError.
String _reason(String? error) {
  final line = (error ?? '')
      .trim()
      .split('\n')
      .first
      .replaceFirst(RegExp(r'^(Bad state|Exception): '), '')
      .trim();
  if (line.isEmpty) return '.';
  return ': ${line.length > 180 ? '${line.substring(0, 179)}…' : line}';
}
