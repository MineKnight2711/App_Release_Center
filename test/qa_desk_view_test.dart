import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_management_center/app/modules/qa_desk/controllers/network_test_controller.dart';
import 'package:app_management_center/app/modules/qa_desk/controllers/qa_workspace_controller.dart';
import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/models/scenario_models.dart';
import 'package:app_management_center/app/modules/qa_desk/views/network_sheet.dart';
import 'package:app_management_center/app/modules/qa_desk/views/qa_desk_view.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_desk_fakes.dart';

const _pixel7 = DeviceInfo(
  id: 'emulator-5554',
  name: 'Pixel 7',
  platform: 'android-x64',
  category: 'mobile',
  isEmulator: true,
);

void main() {
  Future<void> mount(
    WidgetTester tester,
    QaWorkspaceController controller, {
    QaSection section = QaSection.run,
    AppThemeChoice theme = AppThemeChoice.defaultTheme,
    Size size = const Size(1440, 900),
    GlobalKey? boundary,
    String? fontFamily,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final data = AppCyberTheme.themeData(theme);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: fontFamily == null
              ? data
              : data.copyWith(
                  textTheme: data.textTheme.apply(fontFamily: fontFamily),
                ),
          home: QaDeskView(controller: controller, initialSection: section),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<QaWorkspaceController> open(
    WidgetTester tester, {
    FakeRunner? runner,
    List<QaSource>? sources,
    List<DeviceInfo> devices = const [],
    MemoryCatalogs? catalogs,
  }) async {
    final controller = fakeController(
      runner: runner ?? FakeRunner(),
      sources: sources,
      devices: devices,
      catalogs: catalogs,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return controller;
  }

  bool? checkbox(WidgetTester tester, String key) =>
      tester.widget<Checkbox>(find.byKey(Key(key))).value;

  VoidCallback? runButton(WidgetTester tester) => tester
      .widget<FilledButton>(find.byKey(const Key('qa-run-button')))
      .onPressed;

  testWidgets('an empty workspace starts with the three steps', (tester) async {
    final controller = await open(tester, sources: const []);
    await mount(tester, controller);

    expect(find.byKey(const Key('qa-add-source')), findsOneWidget);
    expect(find.text('Thêm nguồn'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tree ticks a whole source and shows a partial one', (
    tester,
  ) async {
    final controller = await open(tester);
    await mount(tester, controller);

    // Analyze and unit are ticked, the device suite is not.
    expect(checkbox(tester, 'qa-source-app'), isNull);
    expect(find.text('Chạy 2 suite'), findsOneWidget);

    await tester.tap(find.byKey(const Key('qa-suite-app-unit')));
    await tester.pumpAndSettle();
    expect(checkbox(tester, 'qa-suite-app-unit'), isFalse);
    expect(find.text('Chạy 1 suite'), findsOneWidget);

    await tester.tap(find.byKey(const Key('qa-source-app')));
    await tester.pumpAndSettle();
    expect(checkbox(tester, 'qa-source-app'), isTrue);
    expect(find.text('Chạy 3 suite'), findsOneWidget);

    await tester.tap(find.byKey(const Key('qa-source-app')));
    await tester.pumpAndSettle();
    expect(checkbox(tester, 'qa-source-app'), isFalse);
    expect(find.textContaining('Chưa chọn gì'), findsOneWidget);
    expect(runButton(tester), isNull);

    // Ticking one suite of a cleared source brings back that suite alone.
    await tester.tap(find.byKey(const Key('qa-suite-app-analyze')));
    await tester.pumpAndSettle();
    expect(find.text('Chạy 1 suite'), findsOneWidget);
    expect(checkbox(tester, 'qa-suite-app-unit'), isFalse);
  });

  testWidgets('the filter narrows the tree to matching suites', (tester) async {
    final controller = await open(tester);
    await mount(tester, controller);

    await tester.enterText(find.byKey(const Key('qa-suite-filter')), 'smoke');
    await tester.pumpAndSettle();

    // "smoke" matches the Android suite by name and unit tests by tag.
    expect(find.byKey(const Key('qa-suite-app-smoke')), findsOneWidget);
    expect(find.byKey(const Key('qa-suite-app-unit')), findsOneWidget);
    expect(find.byKey(const Key('qa-suite-app-analyze')), findsNothing);
  });

  testWidgets('a device suite is blocked until a device is chosen', (
    tester,
  ) async {
    final controller = await open(
      tester,
      sources: [
        appSource(suites: [smokeSuite.copyWith(selected: true)]),
      ],
      devices: const [_pixel7],
    );
    await mount(tester, controller);

    expect(find.byKey(const Key('qa-preflight-deviceMissing')), findsOneWidget);
    expect(runButton(tester), isNull);

    await tester.tap(find.text('Chọn thiết bị'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qa-devices-sheet')), findsOneWidget);
    // Opening the sheet scans, and the first device found is taken.
    expect(find.byKey(const Key('qa-device-emulator-5554')), findsOneWidget);

    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qa-preflight-deviceMissing')), findsNothing);
    expect(find.textContaining('Pixel 7 · máy ảo'), findsOneWidget);
    expect(runButton(tester), isNotNull);
  });

  testWidgets('missing secrets block the run until entered', (tester) async {
    final controller = await open(
      tester,
      catalogs: MemoryCatalogs({
        'app': const SourceScenarioCatalog(
          sourceId: 'app',
          environments: [
            EnvironmentProfile(
              id: 'staging',
              name: 'Staging',
              variables: {'API_URL': 'https://staging.example'},
              secretKeys: ['API_TOKEN'],
            ),
          ],
        ),
      }),
    );
    await mount(tester, controller);

    expect(
      find.byKey(const Key('qa-preflight-secretsMissing')),
      findsOneWidget,
    );
    expect(runButton(tester), isNull);

    await tester.tap(find.text('Nhập secret'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('qa-secret-API_TOKEN')), 's3');
    await tester.tap(find.byKey(const Key('qa-secrets-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qa-preflight-secretsMissing')), findsNothing);
    expect(runButton(tester), isNotNull);
    expect(find.text('1/1'), findsOneWidget);
    expect(find.textContaining('môi trường Staging'), findsOneWidget);
  });

  testWidgets('a finished run leaves a result card that re-runs failures', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final runner = FakeRunner({'analyze': 0, 'unit': 1});
    final controller = await open(tester, runner: runner);
    await mount(tester, controller);

    await tester.tap(find.byKey(const Key('qa-run-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qa-result-card')), findsOneWidget);
    expect(find.text('Có 1 suite lỗi'), findsOneWidget);
    // The log opens on the failure without being asked.
    expect(find.text('output of unit'), findsOneWidget);
    expect(find.text('Lượt vừa xong: 1/2 qua'), findsOneWidget);

    await tester.tap(find.byKey(const Key('qa-result-report')));
    await tester.pumpAndSettle();
    expect(find.text('[FizaHUB Flutter] Unit tests thất bại'), findsOneWidget);
    await tester.tap(find.byKey(const Key('qa-copy-report')));
    await tester.pump();
    expect(clipboard, contains('Unit tests thất bại'));
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('qa-result-rerun')));
    await tester.pumpAndSettle();
    expect(runner.started, ['analyze', 'unit', 'unit']);
    expect(controller.historyBatches, hasLength(2));
  });

  testWidgets('changing the selection puts the result card away', (
    tester,
  ) async {
    final controller = await open(tester, runner: FakeRunner({'analyze': 0}));
    await mount(tester, controller);
    await tester.tap(find.byKey(const Key('qa-suite-app-unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qa-run-button')));
    await tester.pumpAndSettle();
    expect(find.text('Tất cả suite đều qua'), findsOneWidget);

    await tester.tap(find.byKey(const Key('qa-suite-app-unit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qa-result-card')), findsNothing);
  });

  testWidgets('a run that ends elsewhere is announced with the way back', (
    tester,
  ) async {
    // Analyze has no scripted exit: it runs until the test finishes it.
    final runner = FakeRunner();
    final controller = await open(
      tester,
      runner: runner,
      sources: [
        appSource(suites: [analyzeSuite]),
      ],
    );
    await mount(tester, controller);
    await tester.tap(find.byKey(const Key('qa-run-button')));
    await tester.pump();
    expect(find.text('Đang chạy 0/1'), findsWidgets);

    await tester.tap(find.byKey(const Key('qa-section-results')));
    // The status spinner turns until the run ends, so nothing settles yet.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('qa-run-status')), findsOneWidget);
    runner.processes['analyze']!.finish(0);
    await tester.pumpAndSettle();

    expect(find.text('Lượt chạy xong: 1 qua.'), findsOneWidget);
    await tester.tap(find.text('Xem'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qa-result-card')), findsOneWidget);
  });

  testWidgets('results compare with the run just before by default', (
    tester,
  ) async {
    final runner = FakeRunner({'analyze': 0, 'unit': 1});
    final controller = await open(tester, runner: runner);
    await controller.runSelected();
    // Batches sort by start time, which Windows reads at coarse resolution.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    runner.exitCodes['unit'] = 0;
    await controller.runSelected();
    final [newest, older] = controller.historyBatches;
    await mount(tester, controller, section: QaSection.results);

    expect(controller.selectedBatchId, newest.id);
    expect(find.byKey(const Key('qa-history-run-unit')), findsOneWidget);
    // Nothing failed in the newest run, so there is nothing to re-run.
    expect(find.byKey(const Key('qa-batch-rerun')), findsNothing);

    await tester.tap(find.text('So sánh'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const Key('qa-compare-with')),
          )
          .value,
      older.id,
    );
    expect(find.text('1 suite đổi trạng thái'), findsOneWidget);

    await tester.tap(find.byKey(Key('qa-batch-${older.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qa-batch-rerun')), findsOneWidget);
    await tester.tap(find.text('Xu hướng'));
    await tester.pumpAndSettle();
    expect(find.text('TỶ LỆ QUA THEO LƯỢT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a test case is written in the side sheet and run from the list',
    (tester) async {
      final runner = FakeRunner({'unit': 0});
      final controller = await open(tester, runner: runner);
      await mount(tester, controller, section: QaSection.scenarios);

      expect(find.text('Chưa có test case'), findsOneWidget);
      await tester.tap(find.byKey(const Key('qa-new-scenario')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('qa-scenario-editor')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('qa-scenario-title')),
        'Đăng nhập OTP',
      );
      await tester.tap(find.byKey(const Key('qa-scenario-suite')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unit tests').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('qa-form-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('qa-scenario-editor')), findsNothing);
      final scenario = controller.catalogFor('app')!.scenarios.single;
      expect(scenario.title, 'Đăng nhập OTP');
      expect(scenario.suiteId, 'unit');

      await tester.tap(find.byKey(Key('qa-run-scenario-${scenario.id}')));
      await tester.pumpAndSettle();
      expect(runner.started, ['unit']);
      // Running lands on the run page, where the outcome is.
      expect(find.byKey(const Key('qa-result-card')), findsOneWidget);
      // The saved selection is untouched by a single test case run.
      expect(find.text('Chạy 2 suite'), findsOneWidget);
    },
  );

  testWidgets('an environment is added and chosen for the next run', (
    tester,
  ) async {
    final controller = await open(tester);
    await mount(tester, controller, section: QaSection.scenarios);

    await tester.tap(find.byKey(const Key('qa-add-environment')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('qa-environment-name')),
      'Staging',
    );
    await tester.enterText(
      find.byKey(const Key('qa-environment-variables')),
      'API_URL=https://staging.example',
    );
    await tester.tap(find.byKey(const Key('qa-form-save')));
    await tester.pumpAndSettle();

    final staging = controller
        .catalogFor('app')!
        .environments
        .firstWhere((item) => item.name == 'Staging');
    await tester.tap(find.byKey(Key('qa-environment-${staging.id}')));
    await tester.pumpAndSettle();
    expect(controller.selectedEnvironmentId('app'), staging.id);

    await tester.tap(find.byKey(const Key('qa-section-run')));
    await tester.pumpAndSettle();
    expect(find.textContaining('môi trường Staging'), findsOneWidget);
  });

  testWidgets(
    'network presets need the simulation off; the probe needs it on',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(700, 1100);
      tester.view.devicePixelRatio = 1;
      final model = NetworkTestController();
      addTearDown(model.dispose);
      Future<void> show({required bool suitesRunning}) => tester.pumpWidget(
        MaterialApp(
          theme: AppCyberTheme.themeData(AppThemeChoice.defaultTheme),
          home: Scaffold(
            body: NetworkPanel(network: model, suitesRunning: suitesRunning),
          ),
        ),
      );
      await show(suitesRunning: false);

      expect(model.profile.bytesPerSecond, 512);
      expect(find.text('Siêu yếu · 0,5 KB/s'), findsOneWidget);
      await tester.tap(find.text('Yếu · 8 KB/s'));
      await tester.pump();
      expect(model.profile.bytesPerSecond, 8192);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('qa-api-test')))
            .onPressed,
        isNull,
      );

      await show(suitesRunning: true);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('qa-network-toggle')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a narrow window splits choosing and running into tabs', (
    tester,
  ) async {
    final controller = await open(tester, runner: FakeRunner({'analyze': 0}));
    await mount(tester, controller, size: const Size(900, 760));

    expect(find.text('Chọn suite'), findsOneWidget);
    expect(find.byKey(const Key('qa-suite-app-analyze')), findsOneWidget);
    await tester.tap(find.byKey(const Key('qa-suite-app-unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qa-run-button')));
    await tester.pumpAndSettle();
    // Starting a run shows it.
    expect(find.byKey(const Key('qa-result-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every section reads in all three themes', (tester) async {
    final capture = Platform.environment['QA_DESK_SCREENSHOTS'];
    String? font;
    if (capture != null) {
      await tester.runAsync(() async {
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        // The theme asks for Segoe UI Variable and JetBrains Mono; the test
        // engine only knows fonts loaded by name, so lend it the system ones.
        Future<void> lend(String path, List<String> families) async {
          final file = File(path);
          if (!await file.exists()) return;
          final data = ByteData.sublistView(await file.readAsBytes());
          for (final family in families) {
            await (FontLoader(family)..addFont(Future.value(data))).load();
          }
        }

        await lend('C:/Windows/Fonts/segoeui.ttf', [
          'QaDeskQA',
          'Segoe UI Variable',
          'Segoe UI',
        ]);
        await lend('C:/Windows/Fonts/segoeuib.ttf', ['QaDeskQA']);
        await lend('C:/Windows/Fonts/consola.ttf', ['JetBrains Mono']);
        font = 'QaDeskQA';
      });
    }
    final runner = FakeRunner({'analyze': 0, 'unit': 1, 'smoke': 0});
    final controller = await open(
      tester,
      runner: runner,
      devices: const [_pixel7],
      catalogs: MemoryCatalogs({
        'app': const SourceScenarioCatalog(
          sourceId: 'app',
          environments: [
            EnvironmentProfile(
              id: 'staging',
              name: 'Staging',
              variables: {'API_URL': 'https://staging.example'},
              secretKeys: ['API_TOKEN'],
            ),
            EnvironmentProfile(id: 'local', name: 'Local'),
          ],
          scenarios: [
            TestScenario(
              id: 'otp',
              title: 'Đăng nhập bằng OTP',
              module: 'Auth',
              suiteId: 'unit',
              preconditions: ['Tài khoản đã đăng ký số điện thoại'],
              steps: ['Mở app', 'Nhập số điện thoại', 'Nhập mã OTP'],
              expectedResult: 'Vào màn hình chính',
              tags: ['smoke'],
            ),
            TestScenario(
              id: 'card',
              title: 'Thanh toán bằng thẻ',
              module: 'Payment',
              suiteId: 'smoke',
            ),
          ],
        ),
      }),
      sources: [
        appSource(),
        QaSource(
          id: 'miniapp',
          name: 'FizaHUB Mini App',
          path: r'C:\projectsizahub_miniapp',
          type: SourceType.node,
          suites: const [
            QaSuite(
              id: 'build',
              name: 'Production build',
              executable: 'npm',
              arguments: ['run', 'build'],
              tags: ['build'],
            ),
          ],
        ),
      ],
    );
    controller.updateSessionSecrets('app', 'staging', {'API_TOKEN': 'x'});
    await controller.refreshDevices();
    await controller.setSuiteSelected('app', 'smoke', true);
    runner.exitCodes['build'] = 0;
    // Batches are keyed and sorted by start time; keep the runs apart.
    Future<void> gap() => tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await controller.runSelected();
    await gap();
    runner.exitCodes['unit'] = 0;
    await controller.runSelected();
    await gap();
    runner.exitCodes['unit'] = 1;
    await controller.runSelected();
    expect(controller.historyBatches, hasLength(3));

    Future<void> shoot(GlobalKey key, String name) async {
      expect(tester.takeException(), isNull, reason: name);
      if (capture == null) return;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(capture).create(recursive: true);
        await File(
          '$capture/qa-desk-$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> close() async {
      await tester.tap(find.byTooltip('Đóng').last);
      await tester.pumpAndSettle();
    }

    for (final theme in AppThemeChoice.values) {
      for (final section in QaSection.values) {
        final key = GlobalKey();
        await mount(
          tester,
          controller,
          section: section,
          theme: theme,
          boundary: key,
          fontFamily: font,
        );
        await shoot(key, '${section.name}-${theme.name}');
        switch (section) {
          case QaSection.run:
            await tester.tap(find.byKey(const Key('qa-device-chip')));
            await tester.pumpAndSettle();
            await shoot(key, 'devices-${theme.name}');
            await close();
            await tester.tap(find.byKey(const Key('qa-network-chip')));
            await tester.pumpAndSettle();
            await shoot(key, 'network-${theme.name}');
            await close();
          case QaSection.scenarios:
            await tester.tap(find.byKey(const Key('qa-new-scenario')));
            await tester.pumpAndSettle();
            await shoot(key, 'editor-${theme.name}');
            await tester.tap(find.text('Huỷ'));
            await tester.pumpAndSettle();
          case QaSection.results:
            await tester.tap(find.text('Xu hướng'));
            await tester.pumpAndSettle();
            await shoot(key, 'trend-${theme.name}');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    }
  });
}
