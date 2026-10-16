import 'package:app_management_center/app/models/app_store_project.dart';
import 'package:app_management_center/app/models/ios_release.dart';
import 'package:app_management_center/app/models/release_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a CH Play run crosses the relay intact, with short step logs', () {
    final run = ReleaseWorkflowRun(
      id: 'r1',
      projectPath: 'C:/Work/emed',
      projectName: 'emed',
      track: 'production',
      currentBranch: 'main',
      currentVersion: '2.1.12+40',
      proposedVersion: '2.1.13+41',
      changedFiles: const ['pubspec.yaml'],
      supportsSplitBuildDeploy: true,
      steps: [
        ReleaseWorkflowStepRun(
          kind: ReleaseWorkflowStepKind.build,
          label: 'Build AAB',
          status: ReleaseStepStatus.failed,
          startedAt: DateTime.utc(2026, 10, 15, 9),
          exitCode: 1,
          logLines: [for (var i = 0; i < 100; i++) 'line $i'],
          error: 'Gradle failed',
          retryable: true,
        ),
      ],
      createdAt: DateTime.utc(2026, 10, 15, 8),
      startedAt: DateTime.utc(2026, 10, 15, 9),
      releaseNotes: 'Sửa lỗi',
    );

    final back = ReleaseWorkflowRun.fromJson(run.toJson());

    expect(back.proposedVersion, '2.1.13+41');
    expect(back.track, 'production');
    expect(back.changedFiles, ['pubspec.yaml']);
    expect(back.startedAt, run.startedAt!.toLocal());
    final step = back.steps.single;
    expect(step.kind, ReleaseWorkflowStepKind.build);
    expect(step.status, ReleaseStepStatus.failed);
    expect(step.error, 'Gradle failed');
    expect(step.retryable, isTrue);
    expect(step.logLines, hasLength(40));
    expect(step.logLines.last, 'line 99');
    // The phone decides its buttons from the same getters as the desktop.
    expect(back.retryableStep?.label, 'Build AAB');
    expect(back.isRunning, isFalse);
  });

  group('the next iOS step', () {
    IosReleaseRun run(
      IosReleaseStatus status, {
      String lastAction = 'build',
      List<String> groups = const [],
      String? ipaPath,
    }) => IosReleaseRun(
      id: '1',
      project: const AppStoreProject(
        id: 'app',
        path: '/p',
        displayName: 'Demo',
        bundleId: 'com.example',
      ),
      settings: IosReleaseSettings(groups: groups),
      version: '1.0.0',
      buildNumber: 3,
      directory: '/r',
      commit: 'abc',
      dirty: false,
      createdAt: DateTime(2026),
      status: status,
      lastAction: lastAction,
      ipaPath: ipaPath,
    );

    test('walks a release from preflight to the App Store', () {
      expect(
        iosPrimaryStep(run(IosReleaseStatus.prepared)).label,
        'Build & upload TestFlight',
      );
      expect(
        iosPrimaryStep(run(IosReleaseStatus.built, ipaPath: '/a.ipa')).label,
        'Upload TestFlight',
      );
      expect(iosPrimaryStep(run(IosReleaseStatus.processing)).id, 'wait');
      expect(iosPrimaryStep(run(IosReleaseStatus.ready)).id, 'draft');
      expect(iosPrimaryStep(run(IosReleaseStatus.draft)).id, 'submit');
      expect(iosPrimaryStep(run(IosReleaseStatus.submitted)).id, 'refresh');
      expect(iosPrimaryStep(run(IosReleaseStatus.released)).id, 'new');
    });

    test('offers distribution and a fresh start where the desktop does', () {
      final ready = run(IosReleaseStatus.ready, groups: const ['QA']);
      expect(iosSecondaryStep(ready, iosPrimaryStep(ready))?.id, 'distribute');

      final failed = run(IosReleaseStatus.failed, lastAction: 'submit');
      final primary = iosPrimaryStep(failed);
      expect(primary.id, 'submit');
      expect(primary.label, 'Chạy lại bước lỗi');
      expect(primary.isStoreAction, isTrue);
      expect(iosSecondaryStep(failed, primary)?.id, 'new');

      final broken = run(IosReleaseStatus.failed, lastAction: 'prepare');
      expect(iosPrimaryStep(broken).label, 'Chuẩn bị lại');
      expect(iosSecondaryStep(broken, iosPrimaryStep(broken)), isNull);
    });
  });
}
