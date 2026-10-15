import 'package:app_management_center/app/models/app_store_project.dart';
import 'package:app_management_center/app/models/ios_release.dart';
import 'package:app_management_center/app/models/release_notification.dart';
import 'package:app_management_center/app/models/release_workflow.dart';
import 'package:app_management_center/app/services/release_push_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android', () {
    ReleaseWorkflowRun run(List<ReleaseWorkflowStepRun> steps) =>
        ReleaseWorkflowRun(
          id: 'run-7',
          projectPath: '/p',
          projectName: 'emed_plus_new',
          track: 'production',
          currentBranch: 'main',
          currentVersion: '2.1.12+40',
          proposedVersion: '2.1.13+41',
          changedFiles: const [],
          supportsSplitBuildDeploy: false,
          steps: steps,
          createdAt: DateTime(2026, 10, 15),
        );

    test('a finished release names the version and track', () {
      final push = androidReleasePush(run(const []), completed: true);
      expect(push.outcome, ReleasePushOutcome.succeeded);
      expect(push.title, 'Release xong · emed_plus_new');
      expect(push.body, 'Android 2.1.13+41 đã lên production.');
      expect(push.tag, 'android-run-7');
    });

    test('a failed release names the step and its first error line', () {
      final push = androidReleasePush(
        run([
          ReleaseWorkflowStepRun(
            kind: ReleaseWorkflowStepKind.values.first,
            label: 'Build AAB',
            status: ReleaseStepStatus.failed,
            error: 'Gradle task bundleRelease failed\nat line 2',
          ),
        ]),
        completed: false,
      );
      expect(push.outcome, ReleasePushOutcome.failed);
      expect(push.title, 'Release lỗi · emed_plus_new');
      expect(
        push.body,
        'Android 2.1.13+41 · Build AAB lỗi: Gradle task bundleRelease failed',
      );
      // Same tag as the success: a retry that works replaces the failure.
      expect(push.tag, 'android-run-7');
    });
  });

  group('iOS', () {
    IosReleaseRun run(IosReleaseStatus status, {String lastAction = 'build'}) =>
        IosReleaseRun(
          id: '42',
          project: const AppStoreProject(
            id: 'app',
            path: '/p',
            displayName: 'emed_plus_new',
            bundleId: 'com.emed.globerdr',
          ),
          settings: const IosReleaseSettings(),
          version: '2.1.13',
          buildNumber: 32,
          directory: '/runs/42',
          commit: 'abc',
          dirty: false,
          createdAt: DateTime(2026, 10, 15),
          status: status,
          lastAction: lastAction,
        );

    test('buzzes on arriving at TestFlight, not on finding it there', () {
      final ready = iosStatusPush(
        run(IosReleaseStatus.ready),
        IosReleaseStatus.processing,
      )!;
      expect(ready.outcome, ReleasePushOutcome.succeeded);
      expect(ready.title, 'TestFlight sẵn sàng · emed_plus_new');
      expect(ready.body, 'iOS 2.1.13+32.');
      expect(ready.tag, 'ios-42');

      expect(
        iosStatusPush(run(IosReleaseStatus.ready), IosReleaseStatus.ready),
        isNull,
      );
      // Choosing an existing TestFlight build is not news.
      expect(
        iosStatusPush(run(IosReleaseStatus.ready), IosReleaseStatus.prepared),
        isNull,
      );
      expect(
        iosStatusPush(
          run(IosReleaseStatus.processing),
          IosReleaseStatus.uploading,
        ),
        isNull,
      );
    });

    test('says which App Store step landed', () {
      expect(
        iosStatusPush(
          run(IosReleaseStatus.draft),
          IosReleaseStatus.ready,
        )!.title,
        'Đã chuẩn bị bản App Store · emed_plus_new',
      );
      expect(
        iosStatusPush(
          run(IosReleaseStatus.submitted, lastAction: 'submit'),
          IosReleaseStatus.draft,
        )!.title,
        startsWith('Đã gửi review'),
      );
      expect(
        iosStatusPush(
          run(IosReleaseStatus.released, lastAction: 'query'),
          IosReleaseStatus.submitted,
        )!.title,
        startsWith('Đã phát hành App Store'),
      );
    });

    test('a failure drops Dart\'s "Bad state:" and keeps it short', () {
      final push = iosFailurePush(
        run(IosReleaseStatus.failed),
        'build',
        'Bad state: flutter lỗi (exit 1). Xem log để biết chi tiết.\nmore',
      );
      expect(push.outcome, ReleasePushOutcome.failed);
      expect(push.title, 'Release iOS lỗi · emed_plus_new');
      expect(
        push.body,
        'iOS 2.1.13+32 · Build IPA lỗi: flutter lỗi (exit 1). Xem log để '
        'biết chi tiết.',
      );
      final long = iosFailurePush(
        run(IosReleaseStatus.failed),
        'upload',
        'x' * 400,
      );
      expect(long.body.length, lessThan(230));
    });
  });
}
