import 'dart:async';

import 'package:app_management_center/app/modules/qa_desk/controllers/qa_workspace_controller.dart';
import 'package:app_management_center/app/modules/qa_desk/models/preflight.dart';
import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/views/qa_desk_view.dart';
import 'package:app_management_center/app/modules/qa_desk/views/qa_shell_status.dart';
import 'package:app_management_center/app/modules/shared/device_run_lock.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_desk_fakes.dart';

const _emulator = DeviceInfo(
  id: 'emulator-5554',
  name: 'Pixel 7',
  platform: 'android-x64',
  category: 'mobile',
  isEmulator: true,
);

const _shopPath = r'C:\projects\shop_app';
const _adminPath = r'C:\projects\admin_web';

const _shop = QaSource(
  id: 'shop',
  name: 'Shop App',
  path: _shopPath,
  type: SourceType.flutter,
  suites: [analyzeSuite],
);

void main() {
  group('the device lock shared with the AAB checker', () {
    test('a mobile suite waits for a device job from another module', () async {
      final release = Completer<void>();
      // What the AAB checker holds while it installs on the emulator.
      final aabJob = DeviceRunLock.run(() => release.future);
      final runner = FakeRunner({'analyze': 0, 'smoke': 0});
      final controller = fakeController(
        runner: runner,
        devices: const [_emulator],
        sources: [
          appSource(
            suites: [analyzeSuite, smokeSuite.copyWith(selected: true)],
          ),
        ],
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.refreshDevices();

      final run = controller.runSelected();
      await pumpEventQueue();
      // Suites that need no device are not held up.
      expect(runner.started, ['analyze']);
      expect(DeviceRunLock.busy, isTrue);

      release.complete();
      await aabJob;
      await run;
      expect(runner.started, ['analyze', 'smoke']);
      expect(DeviceRunLock.busy, isFalse);
    });

    test('an AAB device run waits for a mobile suite in progress', () async {
      final runner = FakeRunner();
      final controller = fakeController(
        runner: runner,
        devices: const [_emulator],
        sources: [
          appSource(suites: [smokeSuite.copyWith(selected: true)]),
        ],
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.refreshDevices();
      final run = controller.runSelected();
      await pumpEventQueue();
      expect(runner.started, ['smoke']);

      var aabRan = false;
      final aabJob = DeviceRunLock.run(() async => aabRan = true);
      await pumpEventQueue();
      expect(aabRan, isFalse);

      runner.processes['smoke']!.finish(0);
      await run;
      await aabJob;
      expect(aabRan, isTrue);
    });
  });

  test('a release in the same project is a warning, not a blocker', () async {
    final host = FakeHost();
    final controller = fakeController(runner: FakeRunner());
    addTearDown(controller.dispose);
    controller.busyProjectPaths = () => host.busyProjectPaths;
    await controller.initialize();
    expect(controller.preflight(), isEmpty);

    // AMC normalises its own paths; letter case must not matter on Windows.
    host.setBusy([r'c:\Projects\FIZAHUB_APP']);

    final issue = controller.preflight().single;
    expect(issue.kind, PreflightKind.projectBusy);
    expect(issue.blocking, isFalse);
  });

  group('the page inside AMC', () {
    Future<QaWorkspaceController> open(
      WidgetTester tester, {
      FakeRunner? runner,
      List<QaSource>? sources,
      List<DeviceInfo> devices = const [],
    }) async {
      final controller = fakeController(
        runner: runner ?? FakeRunner({'analyze': 0, 'unit': 1}),
        sources: sources,
        devices: devices,
        discovery: const MapDiscovery({_shopPath: _shop}),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      return controller;
    }

    Future<void> mount(
      WidgetTester tester,
      QaWorkspaceController controller, {
      FakeHost? host,
      String? projectPath,
      QaDeskIntent intent = QaDeskIntent.open,
      QaSection section = QaSection.run,
      bool settle = true,
    }) async {
      final amc = host ?? FakeHost();
      controller.busyProjectPaths = () => amc.busyProjectPaths;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppCyberTheme.themeData(AppThemeChoice.defaultTheme),
          home: QaDeskView(
            controller: controller,
            host: amc,
            projectPath: projectPath,
            intent: intent,
            initialSection: section,
          ),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
        await tester.pump();
      }
    }

    testWidgets('the add menu offers AMC projects that are not sources yet', (
      tester,
    ) async {
      final controller = await open(tester);
      final host = FakeHost(
        currentProjectPath: _shopPath,
        recentProjectPaths: [r'C:\projects\fizahub_app', _adminPath, _shopPath],
      );
      await mount(tester, controller, host: host);

      await tester.tap(find.byKey(const Key('qa-add-source')));
      await tester.pumpAndSettle();
      expect(find.text('shop_app · đang mở'), findsOneWidget);
      expect(find.text('admin_web'), findsOneWidget);
      // Already a source, so not offered again.
      expect(find.text('fizahub_app'), findsNothing);
      expect(find.byKey(const Key('qa-add-folder')), findsOneWidget);

      await tester.tap(find.text('shop_app · đang mở'));
      await tester.pumpAndSettle();
      expect(controller.sources.map((source) => source.id), ['app', 'shop']);
      expect(find.text('Đã thêm Shop App (1 suite).'), findsOneWidget);
      expect(find.byKey(const Key('qa-source-shop')), findsOneWidget);
    });

    testWidgets('a folder that is not a project says so', (tester) async {
      final controller = await open(tester);
      await mount(
        tester,
        controller,
        host: FakeHost(recentProjectPaths: [_adminPath]),
      );

      await tester.tap(find.byKey(const Key('qa-add-source')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('admin_web'));
      await tester.pumpAndSettle();

      expect(find.text('Không nhận ra loại dự án.'), findsOneWidget);
      expect(controller.sources, hasLength(1));
    });

    testWidgets('opened from a project that is not a source, offers it', (
      tester,
    ) async {
      final controller = await open(tester);
      await mount(tester, controller, projectPath: _shopPath);

      expect(find.byKey(const Key('qa-project-suggestion')), findsOneWidget);
      await tester.tap(find.byKey(const Key('qa-add-suggested')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('qa-project-suggestion')), findsNothing);
      expect(find.byKey(const Key('qa-source-shop')), findsOneWidget);
    });

    testWidgets('opened from a project that is a source, says nothing', (
      tester,
    ) async {
      final controller = await open(tester);
      await mount(tester, controller, projectPath: r'C:\projects\fizahub_app');

      expect(find.byKey(const Key('qa-project-suggestion')), findsNothing);
    });

    testWidgets('an empty workspace adds an AMC project in one click', (
      tester,
    ) async {
      final controller = await open(tester, sources: const []);
      await mount(
        tester,
        controller,
        host: FakeHost(recentProjectPaths: [_shopPath]),
      );

      await tester.tap(find.byKey(const ValueKey('qa-quick-add:$_shopPath')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('qa-source-shop')), findsOneWidget);
    });

    testWidgets('a release starting in the project shows beside Chạy', (
      tester,
    ) async {
      final controller = await open(tester);
      final host = FakeHost();
      await mount(tester, controller, host: host);
      expect(find.byKey(const Key('qa-preflight-projectBusy')), findsNothing);

      host.setBusy([r'C:\projects\fizahub_app']);
      await tester.pump();

      expect(find.byKey(const Key('qa-preflight-projectBusy')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('qa-run-button')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('the run command starts the saved selection', (tester) async {
      final runner = FakeRunner({'analyze': 0, 'unit': 1});
      final controller = await open(tester, runner: runner);
      await mount(tester, controller, intent: QaDeskIntent.run);

      expect(runner.started, ['analyze', 'unit']);
      expect(find.byKey(const Key('qa-result-card')), findsOneWidget);
    });

    testWidgets('the run command says why it cannot run', (tester) async {
      final runner = FakeRunner();
      final controller = await open(
        tester,
        runner: runner,
        sources: [
          appSource(suites: [smokeSuite.copyWith(selected: true)]),
        ],
      );
      await mount(tester, controller, intent: QaDeskIntent.run);

      expect(runner.started, isEmpty);
      expect(find.textContaining('Chưa chạy được:'), findsOneWidget);
    });

    testWidgets('the re-run command re-runs the latest failures', (
      tester,
    ) async {
      final runner = FakeRunner({'analyze': 0, 'unit': 1});
      final controller = await open(tester, runner: runner);
      await controller.runSelected();
      runner.started.clear();

      await mount(tester, controller, intent: QaDeskIntent.rerunFailed);

      expect(runner.started, ['unit']);
    });

    testWidgets('the report command opens the latest run and its report', (
      tester,
    ) async {
      final controller = await open(tester);
      await controller.runSelected();

      await mount(
        tester,
        controller,
        intent: QaDeskIntent.lastReport,
        settle: false,
      );
      // The report reads the saved log from disk, outside fake time.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('qa-issue-report')), findsOneWidget);
      expect(
        find.text('[FizaHUB Flutter] Unit tests thất bại'),
        findsOneWidget,
      );
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('qa-batch-report')), findsOneWidget);
    });

    testWidgets('commands with nothing to act on say so', (tester) async {
      final controller = await open(tester);
      await mount(tester, controller, intent: QaDeskIntent.lastReport);

      expect(find.text('Chưa có lượt chạy nào.'), findsOneWidget);
    });
  });

  testWidgets('the shell chip follows a run and keeps an unseen result', (
    tester,
  ) async {
    final runner = FakeRunner();
    final controller = fakeController(
      runner: runner,
      sources: [
        appSource(suites: [analyzeSuite]),
      ],
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final seen = ValueNotifier<String?>(null);
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppCyberTheme.themeData(AppThemeChoice.console),
        home: Scaffold(
          body: Center(
            child: QaShellRunChip(
              controller: controller,
              seenBatch: seen,
              onTap: () => opened++,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('qa-shell-status')), findsNothing);

    unawaited(controller.runSelected());
    await tester.pump();
    expect(find.text('QA 0/1'), findsOneWidget);

    runner.processes['analyze']!.finish(0);
    await tester.pumpAndSettle();
    expect(find.text('QA xong · 1/1 qua'), findsOneWidget);
    await tester.tap(find.byKey(const Key('qa-shell-status')));
    expect(opened, 1);

    seen.value = controller.runs.first.batchId;
    await tester.pump();
    expect(find.byKey(const Key('qa-shell-status')), findsNothing);
  });
}
