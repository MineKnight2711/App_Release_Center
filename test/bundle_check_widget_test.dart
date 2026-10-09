import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_management_center/app/modules/bundle_check/controllers/bundle_check_controller.dart';
import 'package:app_management_center/app/modules/bundle_check/models/bundle_check_models.dart';
import 'package:app_management_center/app/modules/bundle_check/services/android_toolchain.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_check_service.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_check_store.dart';
import 'package:app_management_center/app/modules/bundle_check/views/bundle_check_view.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'bundle_check_fixtures.dart';

/// Stands in for adb and bundletool: no devices, nothing installed. Widget
/// tests must never reach the real adb on the machine running them.
class _NoDevices implements BundleProcessRunner {
  @override
  Future<BundleProcessResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    Duration timeout = const Duration(minutes: 2),
  }) async => const BundleProcessResult(
    exitCode: 0,
    stdout: 'List of devices attached\n',
  );

  @override
  Future<bool> startDetached(String executable, List<String> arguments) async =>
      false;
}

class _NoProjects implements BundleProjectSource {
  @override
  Future<List<BundleProjectCandidate>> candidates() async => const [];

  @override
  Future<KeystoreRef?> savedKeystore(BundleProjectCandidate candidate) async =>
      null;
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('bundle_widget'));
  tearDown(() => temp.deleteSync(recursive: true));

  Future<BundleCheckController> pumpChecked(
    WidgetTester tester, {
    required Size size,
    AppThemeChoice theme = AppThemeChoice.cyber,
    GlobalKey? boundary,
    String? fontFamily,
    bool deviceRun = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = BundleCheckController(
      service: BundleCheckService(
        store: BundleCheckStore(root: Directory(p.join(temp.path, 'store'))),
        projects: _NoProjects(),
        runner: _NoDevices(),
        tools: const JavaTools(java: 'java', keytool: 'keytool'),
        inspectInBackground: false,
      ),
    );
    addTearDown(controller.dispose);

    await tester.runAsync(() async {
      final aab = writeAab(
        p.join(temp.path, 'app-release.aab'),
        signatureBlock: debugSignatureBlock,
        signatureName: 'META-INF/ANDROIDD.EC',
        envFiles: const {'.env': 'API_URL=http://10.0.2.2:8080\n'},
      );
      await controller.init();
      await controller.checkFile(aab.path);
      if (deviceRun) {
        // A finished run as the device card shows it: results, two
        // screenshots in the job folder and the log.
        final report = controller.report!;
        final job = await controller.service.store.jobDirectory(report.id);
        File(
          p.join(job.path, 'screen_1.png'),
        ).writeAsBytesSync(pngOf(90, 180, (x, y) => [240, 90, 60]));
        File(
          p.join(job.path, 'screen_2.png'),
        ).writeAsBytesSync(pngOf(90, 180, (x, y) => [x * 2, y, 200]));
        File(p.join(job.path, 'logcat.txt')).writeAsStringSync('log');
        final updated = report.withDeviceRun(
          const [
            CheckResult(
              id: 'R04',
              group: CheckGroup.run,
              status: CheckStatus.pass,
              title: 'Mở app',
              detail: 'Cold start 1602ms.',
            ),
            CheckResult(
              id: 'R05',
              group: CheckGroup.run,
              status: CheckStatus.warn,
              title: 'Chạy ổn định',
              detail: 'App vẫn chạy sau 20 giây. Log có 1 lỗi đáng xem.',
              items: [
                'flutter: Unhandled Exception: Null check operator used on a null value',
                '    #0      Navigator.of (package:flutter/src/widgets/navigator.dart:2937)',
              ],
            ),
          ],
          DeviceRunSummary(
            deviceLabel: 'ZFold_3 (máy ảo · Android 16)',
            serial: 'emulator-5554',
            startedAt: DateTime(2026, 9, 30, 8, 37),
            durationMs: 33500,
            coldStartMs: 1602,
            screenshots: const ['screen_1.png', 'screen_2.png'],
            logcatFile: 'logcat.txt',
            signedWith: 'android/env.properties',
          ),
        );
        await controller.service.store.save(updated);
        controller.showReport(updated);
      }
    });

    AppCyberTheme.activate(theme);
    final themeData = AppCyberTheme.themeData(theme);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: fontFamily == null
              ? themeData
              : themeData.copyWith(
                  textTheme: themeData.textTheme.apply(fontFamily: fontFamily),
                ),
          home: BundleCheckView(controller: controller),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  testWidgets('hiện báo cáo ba nhóm với lỗi chữ ký và env', (tester) async {
    final controller = await pumpChecked(tester, size: const Size(1280, 900));

    expect(controller.stage, BundleCheckStage.done);
    expect(find.text('app-release.aab'), findsWidgets);
    expect(find.text('BUILD ĐÚNG KHÔNG'), findsOneWidget);
    expect(find.text('ĐỦ ENV KHÔNG'), findsOneWidget);
    expect(find.byKey(const Key('bundle-check-result-B04')), findsOneWidget);
    expect(find.textContaining('Ký bằng debug key'), findsOneWidget);
    expect(find.byKey(const Key('bundle-check-result-E02')), findsOneWidget);
    // Env values are shown masked, never in full.
    expect(find.textContaining('10.0.2.2:8080/'), findsNothing);
    // A debug-signed bundle is never offered for pinning.
    expect(find.byKey(const Key('bundle-check-pin-signer')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thẻ chạy thử: kết quả, ảnh chụp, nút chạy', (tester) async {
    await pumpChecked(tester, size: const Size(1280, 1400), deviceRun: true);
    // Two rounds: the job folder resolves, then the screenshots read.
    for (var i = 0; i < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    expect(find.text('CHẠY ĐƯỢC KHÔNG'), findsOneWidget);
    expect(find.byKey(const Key('bundle-check-result-R05')), findsOneWidget);
    expect(find.textContaining('Navigator.of'), findsOneWidget);
    expect(find.text('Lúc kết thúc'), findsOneWidget);
    expect(find.text('Mở logcat'), findsOneWidget);
    // No bundletool in the test's store: the run button stays disabled and
    // says why.
    final run = tester.widget<FilledButton>(
      find.byKey(const Key('bundle-check-run-device')),
    );
    expect(run.onPressed, isNull);
    expect(find.textContaining('Chạy thử cần bundletool'), findsOneWidget);
    expect(find.textContaining('Không thấy thiết bị'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('màn hẹp xếp dọc, không tràn', (tester) async {
    await pumpChecked(tester, size: const Size(700, 1000));
    expect(find.text('Kéo file .aab vào đây'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('soát giao diện trên cả ba theme AMC', (tester) async {
    // Ảnh chụp chỉ để soát mắt thường khi cần, không phải golden test.
    final capture = Platform.environment['BUNDLE_CHECK_SCREENSHOTS'];
    if (capture == null) return;
    await tester.runAsync(() async {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final font = File('C:/Windows/Fonts/segoeui.ttf');
      if (await font.exists()) {
        final data = ByteData.sublistView(await font.readAsBytes());
        for (final family in ['BundleQA', 'Segoe UI Variable', 'Segoe UI']) {
          final loader = FontLoader(family)..addFont(Future.value(data));
          await loader.load();
        }
      }
    });

    for (final theme in AppThemeChoice.values) {
      final boundary = GlobalKey();
      await pumpChecked(
        tester,
        size: const Size(1440, 2400),
        theme: theme,
        boundary: boundary,
        fontFamily: 'BundleQA',
        deviceRun: true,
      );
      // Let the job folder resolve and the screenshots read and decode.
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(capture).create(recursive: true);
        await File(
          '$capture/bundle-check-${theme.name}.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      temp.deleteSync(recursive: true);
      temp.createSync();
    }
    AppCyberTheme.activate(AppThemeChoice.cyber);
  });
}
