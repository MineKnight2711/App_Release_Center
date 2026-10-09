import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/controllers/qa_workspace_controller.dart';
import 'package:app_management_center/app/modules/qa_desk/models/automation_models.dart';
import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/models/scenario_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/account_vault.dart';
import 'package:app_management_center/app/modules/qa_desk/services/automation_runner.dart';
import 'package:app_management_center/app/modules/qa_desk/services/vault_cipher.dart';
import 'package:app_management_center/app/modules/qa_desk/views/automation_dialogs.dart';
import 'package:app_management_center/app/modules/qa_desk/views/qa_desk_view.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'qa_desk_fakes.dart';

const _pixel7 = DeviceInfo(
  id: 'emulator-5554',
  name: 'Pixel 7',
  platform: 'android-x64',
  category: 'mobile',
  isEmulator: true,
);

const _shopApp = QaApp(
  id: 'shop',
  name: 'Shop',
  environments: [
    QaAppEnvironment(name: 'staging', appId: 'vn.example.shop.staging'),
    QaAppEnvironment(name: 'production', appId: 'vn.example.shop'),
  ],
  loginFlow: 'flows/login.yaml',
);

const _viewOrders = TestScenario(
  id: 'xem-don',
  title: 'Xem danh sách đơn',
  module: 'Đơn',
  suiteId: '',
  steps: ['Mở app', 'Đăng nhập bằng tài khoản demo'],
  automation: AutomationSpec(
    app: 'shop',
    role: 'Chủ shop',
    steps: [
      AutomationStep(type: AutomationStepType.launch),
      AutomationStep(type: AutomationStepType.login),
    ],
  ),
);

DemoAccount _account(String environment) => DemoAccount(
  id: 'owner-$environment',
  app: 'shop',
  environment: environment,
  role: 'Chủ shop',
  username: '0912345678',
  password: 'S3cret-Owner',
);

void main() {
  Future<(QaWorkspaceController, FakeRunner, LocalAccountVault)> open(
    WidgetTester tester, {
    String path = r'C:\projects\shop',
    List<DemoAccount> accounts = const [],
  }) async {
    final runner = FakeRunner();
    final controller = fakeController(
      runner: runner,
      devices: const [_pixel7],
      sources: [
        appSource(
          path: path,
          suites: const [analyzeSuite],
        ).copyWith(apps: const [_shopApp]),
      ],
      catalogs: MemoryCatalogs({
        'app': const SourceScenarioCatalog(
          sourceId: 'app',
          scenarios: [_viewOrders],
        ),
      }),
    );
    final vault = LocalAccountVault(store: MemorySecretStore(), machine: 'pc');
    await vault.load();
    for (final account in accounts) {
      await vault.save(account);
    }
    controller.attachAutomation(
      AutomationRunner(
        vault: vault,
        maestro: ReadyMaestro(),
        processRunner: runner,
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.refreshDevices();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return (controller, runner, vault);
  }

  Future<void> mount(
    WidgetTester tester,
    QaWorkspaceController controller, {
    QaSection section = QaSection.run,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppCyberTheme.themeData(AppThemeChoice.defaultTheme),
        home: QaDeskView(controller: controller, initialSection: section),
      ),
    );
    await tester.pumpAndSettle();
  }

  String runLabel(WidgetTester tester) {
    final button = find.byKey(const Key('qa-run-button'));
    return tester
        .widget<Text>(
          find.descendant(of: button, matching: find.byType(Text)).last,
        )
        .data!;
  }

  testWidgets('automated test cases are ticked beside suites and counted', (
    tester,
  ) async {
    final (controller, _, _) = await open(
      tester,
      accounts: [_account('staging')],
    );
    await mount(tester, controller);

    expect(find.text('QA Desk tự thao tác'), findsOneWidget);
    expect(find.text('Xem danh sách đơn'), findsOneWidget);
    expect(runLabel(tester), 'Chạy 1 suite');
    expect(
      find.text('Tài khoản demo: 1 tài khoản', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Môi trường app: staging', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('qa-automation-app-xem-don')));
    await tester.pumpAndSettle();
    expect(controller.selectedAutomationCount, 1);
    expect(runLabel(tester), 'Chạy 2 mục');
    expect(find.textContaining('1 tự thao tác'), findsWidgets);

    await tester.tap(find.byKey(const Key('qa-suite-app-analyze')));
    await tester.pumpAndSettle();
    expect(runLabel(tester), 'Chạy 1 kịch bản');

    // The source box covers both kinds.
    await tester.tap(find.byKey(const Key('qa-source-app')));
    await tester.pumpAndSettle();
    expect(runLabel(tester), 'Chạy 2 mục');
    await tester.tap(find.byKey(const Key('qa-source-app')));
    await tester.pumpAndSettle();
    expect(controller.selectedRunCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing account blocks the run and points to the vault', (
    tester,
  ) async {
    final (controller, _, _) = await open(tester);
    await controller.setAutomationSelected('app', 'xem-don', true);
    await mount(tester, controller);

    expect(
      find.byKey(const Key('qa-preflight-accountMissing')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('qa-run-button')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Mở kho tài khoản'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qa-vault-sheet')), findsOneWidget);
    expect(find.textContaining('Sẵn sàng · Java 21'), findsOneWidget);
  });

  testWidgets('running on production asks first', (tester) async {
    final (controller, runner, _) = await open(
      tester,
      accounts: [_account('production')],
    );
    await controller.setSourceSelected('app', false);
    await controller.setAutomationSelected('app', 'xem-don', true);
    controller.selectAppEnvironment('production');
    await mount(tester, controller);

    expect(find.byKey(const Key('qa-preflight-productionRun')), findsOneWidget);
    await tester.tap(find.byKey(const Key('qa-run-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qa-production-confirm')), findsOneWidget);
    expect(find.text('Chạy 1 kịch bản trên production?'), findsOneWidget);

    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    expect(runner.started, isEmpty);
    expect(controller.isRunning, isFalse);
  });

  testWidgets('the environment chip switches the app environment', (
    tester,
  ) async {
    final (controller, _, _) = await open(tester);
    await mount(tester, controller);

    await tester.tap(find.byKey(const Key('qa-app-env-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qa-app-env-production')));
    await tester.pumpAndSettle();

    expect(controller.appEnvironment, 'production');
    expect(
      find.text('Môi trường app: production · production', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('the vault sheet adds an account without showing it', (
    tester,
  ) async {
    final (controller, _, vault) = await open(tester);
    await mount(tester, controller);

    await tester.tap(find.byKey(const Key('qa-open-vault')));
    await tester.pumpAndSettle();
    expect(find.text('KHO TRÊN MÁY NÀY'), findsOneWidget);
    await tester.tap(find.byKey(const Key('qa-add-account')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('qa-account-role')),
      'Chủ shop',
    );
    await tester.enterText(
      find.byKey(const Key('qa-account-username')),
      '0912345678',
    );
    await tester.enterText(
      find.byKey(const Key('qa-account-password')),
      'S3cret-Owner',
    );
    await tester.tap(find.byKey(const Key('qa-account-save')));
    await tester.pumpAndSettle();

    final saved = vault.accounts.single;
    expect(saved.app, 'shop');
    expect(saved.environment, 'staging');
    expect(saved.role, 'Chủ shop');
    expect(saved.password, 'S3cret-Owner');
    expect(find.text('Shop · 0912•••678'), findsOneWidget);
    expect(find.textContaining('S3cret-Owner'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the editor saves steps QA Desk runs and writes their flow', (
    tester,
  ) async {
    final sandbox = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('qa_editor_'),
    ))!;
    addTearDown(() => tester.runAsync(() => sandbox.delete(recursive: true)));
    final (controller, _, _) = await open(tester, path: sandbox.path);
    await mount(tester, controller, section: QaSection.scenarios);

    await tester.tap(find.byKey(const Key('qa-new-scenario')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('qa-scenario-title')),
      'Đăng nhập thấy trang chủ',
    );
    await tester.tap(find.text('QA Desk tự thao tác'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('qa-scenario-role')),
      'Chủ shop',
    );

    // Starts with opening the app and logging in; add a check.
    expect(find.byKey(const Key('qa-step-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('qa-add-step')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thấy').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('qa-step-2-target')),
      'Trang chủ',
    );
    await tester.pumpAndSettle();

    // Saving writes the flow file: real IO, so the tap runs outside the
    // fake clock.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('qa-form-save')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    final saved = controller
        .catalogFor('app')!
        .scenarios
        .firstWhere((item) => item.title == 'Đăng nhập thấy trang chủ');
    expect(saved.suiteId, isEmpty);
    expect(saved.automation!.role, 'Chủ shop');
    expect(saved.automation!.steps.map((step) => step.type), [
      AutomationStepType.launch,
      AutomationStepType.login,
      AutomationStepType.assertVisible,
    ]);
    expect(saved.steps.last, 'Thấy "Trang chủ"');
    final flow = File(p.join(sandbox.path, '.fiza-qa', saved.automation!.flow));
    final text = (await tester.runAsync(flow.readAsString))!;
    expect(
      text,
      contains(r"- assertVisible: '(?s)(?:.*\n)?Trang chủ(?:\n.*)?'"),
    );
    expect(text, contains("- runFlow: 'login.yaml'"));
    expect(find.byKey(const Key('qa-scenario-editor')), findsNothing);
  });

  testWidgets('the steps dialog shows where a run stopped', (tester) async {
    final sandbox = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('qa_steps_'),
    ))!;
    addTearDown(() => tester.runAsync(() => sandbox.delete(recursive: true)));
    final details = File(p.join(sandbox.path, 'steps.json'));
    await tester.runAsync(
      () => details.writeAsString(
        jsonEncode({
          'loginFailed': true,
          'steps': [
            {'label': 'Mở app', 'status': 'COMPLETED', 'durationMs': 900},
            {
              'label': 'Chạy flow login.yaml',
              'status': 'FAILED',
              'durationMs': 3000,
            },
            {
              'label': 'Nhập "\${MAESTRO_QA_PASSWORD}"',
              'status': 'FAILED',
              'durationMs': 2000,
              'depth': 1,
              'error': 'Element not found: Mật khẩu',
            },
          ],
        }),
      ),
    );
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppCyberTheme.themeData(AppThemeChoice.defaultTheme),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAutomationSteps(
              context,
              title: 'Shop · Đăng nhập',
              detailsPath: details.path,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // The dialog reads steps.json from disk: let the real IO finish.
    for (var turn = 0; turn < 10; turn++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qa-automation-steps')), findsOneWidget);
    expect(find.text('Chạy flow login.yaml'), findsOneWidget);
    expect(find.text('Element not found: Mật khẩu'), findsOneWidget);
    expect(find.textContaining('kiểm tra tài khoản'), findsOneWidget);
  });
}
