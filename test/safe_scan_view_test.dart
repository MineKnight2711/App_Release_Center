import 'dart:async';
import 'dart:io';

import 'package:app_management_center/app/modules/safe/controllers/safe_controller.dart';
import 'package:app_management_center/app/modules/safe/controllers/safe_scan_controller.dart';
import 'package:app_management_center/app/modules/safe/services/safe_secret_scanner.dart';
import 'package:app_management_center/app/modules/safe/services/safe_vault.dart';
import 'package:app_management_center/app/modules/safe/views/safe_scan_dialog.dart';
import 'package:app_management_center/app/modules/safe/views/safe_view.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'safe_scan_test.dart' show writeFixture;

const _code = 'correct horse battery';

void main() {
  late Directory dir;
  late String root;
  late SecretScanResult scanned;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('amc-safe-scan-view');
    root = p.join(dir.path, 'source');
    await writeFixture(root);
    scanned = SafeSecretScanner.scan(root);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> pumpFor(WidgetTester tester, Duration duration) async {
    const step = Duration(milliseconds: 100);
    for (var elapsed = Duration.zero; elapsed < duration; elapsed += step) {
      await tester.pump(step);
    }
  }

  /// Lets real disk work land between fake-time pumps.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 150 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
  }

  /// An open safe whose vault was made and is used from the test's zone.
  Future<SafeController> openSafe(WidgetTester tester) async {
    final safe = SafeController(
      vault: SafeVault(
        locate: () async => File(p.join(dir.path, 'safe.vault')),
        kdfParams: const SafeKdfParams(
          memoryKiB: 64,
          iterations: 1,
          parallelism: 1,
        ),
        deriveKey: deriveSafeKey,
      ),
      writeClipboard: (_) async {},
      readClipboard: () async => '',
    );
    unawaited(safe.load());
    await settle(tester, () => safe.stage == SafeStage.uncreated);
    unawaited(safe.create(_code, _code));
    await settle(tester, () => safe.isOpen);
    return safe;
  }

  void sizeWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppCyberTheme.activate(AppThemeChoice.console);
  }

  testWidgets('the scan opens from inside the safe', (tester) async {
    sizeWindow(tester);
    final safe = await openSafe(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppCyberTheme.themeData(AppThemeChoice.console),
        home: SafeView(controller: safe),
      ),
    );
    await pumpFor(tester, const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('safe-scan')));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.text('Chọn thư mục chứa các project'), findsOneWidget);
    expect(find.byKey(const Key('safe-scan-pick')), findsOneWidget);

    await tester.tap(find.byTooltip('Đóng'));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.text('Chọn thư mục chứa các project'), findsNothing);

    await safe.lock();
    await pumpFor(tester, const Duration(seconds: 1));
    safe.dispose();
  });

  testWidgets(
    'findings are ticked per project and land in the safe by project',
    (tester) async {
      sizeWindow(tester);
      final safe = await openSafe(tester);
      final scan = SafeScanController(
        safe: safe,
        runner: (root, {onProgress}) =>
            SecretScanJob(Future.value(scanned), () {}),
        readFile: (path) async => File(path).readAsBytesSync(),
      );
      SafeScanImport? imported;
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppCyberTheme.themeData(AppThemeChoice.console),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    imported = await showSafeScanDialog(
                      context,
                      safe,
                      controller: scan,
                    );
                    closed = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await pumpFor(tester, const Duration(milliseconds: 300));

      await scan.scan(root);
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      final total = scanned.findingCount;
      expect(find.text('loose'), findsOneWidget);
      expect(find.text('ShopApp'), findsOneWidget);
      // Folding the long ShopApp group brings web-admin into view.
      await tester.tap(find.text('ShopApp'));
      await tester.pump();
      expect(find.text('web-admin'), findsOneWidget);
      expect(
        find.text('Đã chọn $total/$total khoá từ 3 dự án'),
        findsOneWidget,
      );
      expect(find.text('Cất $total khoá vào két'), findsOneWidget);
      // Values never show in the list.
      expect(find.textContaining('sk_live'), findsNothing);
      expect(find.textContaining('AKIAIOSFODNN7EXAMPLE'), findsNothing);

      // Untick a whole project.
      await tester.tap(find.byKey(const Key('safe-scan-project-loose')));
      await tester.pump();
      expect(
        find.text('Đã chọn ${total - 1}/$total khoá từ 2 dự án'),
        findsOneWidget,
      );

      // Untick one finding.
      final web = scanned.projects.singleWhere((x) => x.name == 'web-admin');
      final aws = web.findings.singleWhere(
        (f) => f.type == SecretFindingType.inlineToken,
      );
      await tester.tap(find.byKey(Key('safe-scan-finding-${aws.id}')));
      await tester.pump();
      expect(
        find.text('Đã chọn ${total - 2}/$total khoá từ 2 dự án'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('safe-scan-import')));
      await settle(tester, () => closed);
      await pumpFor(tester, const Duration(milliseconds: 300));

      expect(imported!.imported, total - 2);
      expect(imported!.projects, 2);
      expect(safe.projects, ['ShopApp', 'web-admin']);
      expect(
        safe.items.any((item) => item.secret == 'AKIAIOSFODNN7EXAMPLE'),
        isFalse,
      );

      // Inside the safe the projects are drawers of their own.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppCyberTheme.themeData(AppThemeChoice.console),
          home: SafeView(controller: safe),
        ),
      );
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('DỰ ÁN'), findsOneWidget);
      await tester.tap(find.byKey(const Key('safe-project-web-admin')));
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(safe.filter, const SafeFilterProject('web-admin'));
      expect(find.text('.env.production'), findsOneWidget);
      expect(find.text('.env'), findsNothing);
      expect(tester.takeException(), isNull);

      await safe.lock();
      await pumpFor(tester, const Duration(seconds: 1));
      safe.dispose();
    },
  );
}
