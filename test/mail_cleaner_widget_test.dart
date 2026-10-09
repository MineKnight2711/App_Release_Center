import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_management_center/app/modules/mail_cleaner/controllers/mail_cleaner_controller.dart';
import 'package:app_management_center/app/modules/mail_cleaner/models/mail_item.dart';
import 'package:app_management_center/app/modules/mail_cleaner/services/mail_cleaner_settings_store.dart';
import 'package:app_management_center/app/modules/mail_cleaner/services/mail_imap_service.dart';
import 'package:app_management_center/app/modules/mail_cleaner/views/mail_cleaner_view.dart';
import 'package:app_management_center/app/modules/shared/module_widgets.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers the module without a server, so layout can be checked at any window
/// size. Deletion behaviour lives in the controller test.
class ViewFixture extends MailImapService {
  final folders = <String>[
    'INBOX',
    'Sent',
    'Trash',
    // Names as long as Gmail's — the case that used to overflow the picker.
    '[Gmail]/All Mail',
    '[Gmail]/Thùng rác quá dài để vừa ô chọn',
  ];

  @override
  Future<void> connect({
    required String host,
    required int port,
    required String account,
    required String password,
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<String>> listFolders() async => folders;

  @override
  Future<int> openFolder(String path) async => 65923;

  @override
  Future<MailboxQuota?> readQuota() async =>
      const MailboxQuota(used: 4400000000, limit: 5000000000);

  @override
  Future<int> countFlagged() async => 0;

  @override
  Future<List<MailItem>> scanFolder({MailProgressCallback? onProgress}) async {
    return [
      MailItem(uid: 1, subject: '[YÊU CẦU MỞ] TÀI KHOẢN VOS', size: 20000),
      MailItem(uid: 2, subject: 'Re: [YÊU CẦU MỞ] TÀI KHOẢN VOS', size: 21000),
      MailItem(uid: 3, subject: '[GTEL-VOICE] CƯỚC THÁNG 9', size: 900000),
    ];
  }

  @override
  Future<void> flagDeleted(
    List<int> uids, {
    MailProgressCallback? onProgress,
  }) async {}

  @override
  Future<void> deleteForever({List<int>? uids}) async {}
}

class MemorySecureStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async => values.remove(key);
}

MailCleanerController buildController() => MailCleanerController(
  imap: ViewFixture(),
  settingsStore: MailCleanerSettingsStore(secureStore: MemorySecureStore()),
);

/// Brings the module up on screen; [scan] also fills the group table.
Future<MailCleanerController> pumpModule(
  WidgetTester tester, {
  Size size = const Size(1040, 700),
  bool connect = true,
  bool scan = false,
  AppThemeChoice theme = AppThemeChoice.cyber,
  GlobalKey? boundary,
  String? fontFamily,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final controller = buildController();
  if (connect) {
    await controller.connect(
      host: 'pro216.emailserver.vn',
      port: 993,
      account: 'nganty@gtelcts.vn',
      password: 'secret',
    );
    if (scan) await controller.scan();
  }

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
        home: MailCleanerView(controller: controller),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SectionLabel', () {
    testWidgets('không sập khi nằm trong Row có bề rộng vô hạn', (
      tester,
    ) async {
      // Chính là lỗi đã làm vỡ màn hình khi bấm "Nhật ký": nhãn vốn là Row có
      // Spacer, đặt làm con thường của một Row khác thì ràng buộc bề rộng là vô
      // hạn và Spacer làm sập layout.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                const SectionLabel('Nhật ký'),
                const Spacer(),
                TextButton(onPressed: () {}, child: const Text('Chép')),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('NHẬT KÝ'), findsOneWidget);
    });

    testWidgets('vẫn đẩy được hành động sang phải khi có hành động', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: SectionLabel(
                'Nhật ký',
                action: TextButton(onPressed: () {}, child: const Text('X')),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final label = tester.getTopLeft(find.text('NHẬT KÝ'));
      final action = tester.getTopLeft(find.text('X'));
      expect(action.dx, greaterThan(label.dx));
    });
  });

  group('Màn kết nối', () {
    testWidgets('hiện đủ preset và mặc định không lưu mật khẩu', (
      tester,
    ) async {
      final controller = await pumpModule(tester, connect: false);
      addTearDown(controller.dispose);

      expect(find.text('Kết nối máy chủ'), findsOneWidget);
      expect(find.text('Email Pro GTEL'), findsOneWidget);
      expect(find.text('Google Gmail'), findsOneWidget);
      expect(find.text('Tùy chỉnh'), findsOneWidget);
      expect(find.text('Nhớ mật khẩu trên máy này'), findsOneWidget);
      expect(controller.rememberPassword, isFalse);
      expect(find.textContaining('chỉ dùng cho phiên này'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chọn Gmail thì đổi host và nhắc App Password', (tester) async {
      final controller = await pumpModule(tester, connect: false);
      addTearDown(controller.dispose);

      await tester.tap(find.text('Google Gmail'));
      await tester.pumpAndSettle();

      expect(find.text('imap.gmail.com'), findsOneWidget);
      expect(find.textContaining('Mật khẩu ứng dụng'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('không nhập gì thì chặn lại, không gọi server', (tester) async {
      final controller = await pumpModule(tester, connect: false);
      addTearDown(controller.dispose);

      await tester.tap(find.text('Bắt đầu kết nối'));
      await tester.pumpAndSettle();

      expect(find.text('Chưa nhập tài khoản email'), findsOneWidget);
      expect(controller.stage, MailCleanerStage.disconnected);
      expect(tester.takeException(), isNull);
    });
  });

  group('Vùng làm việc', () {
    testWidgets('dựng được ở kích thước cửa sổ tối thiểu', (tester) async {
      final controller = await pumpModule(tester);
      addTearDown(controller.dispose);

      expect(find.text('nganty@gtelcts.vn'), findsOneWidget);
      expect(find.text('pro216.emailserver.vn:993'), findsOneWidget);
      expect(find.text('Quét hộp thư'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cửa sổ hẹp bất thường vẫn không ném lỗi tràn', (tester) async {
      final controller = await pumpModule(
        tester,
        size: const Size(900, 640),
        scan: true,
      );
      addTearDown(controller.dispose);

      expect(tester.takeException(), isNull);
    });

    testWidgets('ô chọn thư mục không tràn dù tên thư mục rất dài', (
      tester,
    ) async {
      final controller = await pumpModule(tester);
      addTearDown(controller.dispose);

      await controller.changeFolder('[Gmail]/Thùng rác quá dài để vừa ô chọn');
      await tester.pumpAndSettle();

      // Bất kỳ lỗi tràn nào của RenderFlex đều nổi lên thành exception.
      expect(tester.takeException(), isNull);
    });

    testWidgets('dựng được với giao diện Default', (tester) async {
      final controller = await pumpModule(
        tester,
        scan: true,
        theme: AppThemeChoice.defaultTheme,
      );
      addTearDown(() {
        controller.dispose();
        AppCyberTheme.activate(AppThemeChoice.cyber);
      });

      expect(find.text('[GTEL-VOICE]'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mở rồi đóng panel Nhật ký đều sạch', (tester) async {
      final controller = await pumpModule(tester);
      addTearDown(controller.dispose);

      await tester.tap(find.text('Nhật ký'));
      await tester.pumpAndSettle();
      expect(find.text('NHẬT KÝ'), findsOneWidget);
      expect(
        find.textContaining('Thư mục INBOX có 65.923 thư.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Nhật ký'));
      await tester.pumpAndSettle();
      expect(find.text('NHẬT KÝ'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bảng nhóm hiện số liệu và tick chọn được', (tester) async {
      final controller = await pumpModule(tester, scan: true);
      addTearDown(controller.dispose);

      expect(find.text('[GTEL-VOICE]'), findsOneWidget);
      expect(find.text('[YEU CAU MO]'), findsOneWidget);
      expect(find.textContaining('có 1 thư Re:/Fwd:'), findsOneWidget);

      await tester.tap(find.text('[GTEL-VOICE]'));
      await tester.pumpAndSettle();

      expect(controller.selectedGroups, {'[GTEL-VOICE]'});
      expect(controller.matchedCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lọc nhóm không khớp thì nói rõ là không có', (tester) async {
      final controller = await pumpModule(tester, scan: true);
      addTearDown(controller.dispose);

      await tester.enterText(find.byType(TextField).last, 'KHONG-CO-NHOM-NAY');
      await tester.pumpAndSettle();

      expect(find.textContaining('Không có nhóm nào khớp'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Xác nhận xoá', () {
    testWidgets('xoá vĩnh viễn bị chặn cho tới khi gõ đúng câu xác nhận', (
      tester,
    ) async {
      final controller = await pumpModule(tester, scan: true);
      addTearDown(controller.dispose);
      controller.selectGroup('[GTEL-VOICE]', true);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bước 2 — Xoá vĩnh viễn'));
      await tester.pumpAndSettle();

      expect(find.text('Xoá vĩnh viễn?'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, 'Xoá vĩnh viễn');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(find.byType(TextField).last, 'XOA 1');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      expect(find.text('Xoá vĩnh viễn?'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chưa chọn gì thì cả hai bước xoá đều tắt', (tester) async {
      final controller = await pumpModule(tester, scan: true);
      addTearDown(controller.dispose);

      final flag = find.widgetWithText(OutlinedButton, 'Bước 1 — Gắn cờ');
      final delete = find.widgetWithText(
        FilledButton,
        'Bước 2 — Xoá vĩnh viễn',
      );
      expect(tester.widget<OutlinedButton>(flag).onPressed, isNull);
      expect(tester.widget<FilledButton>(delete).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('soát giao diện vùng làm việc trên cả hai theme AMC', (
    tester,
  ) async {
    // Ảnh chụp chỉ để soát mắt thường khi cần, không phải golden test.
    final capture = Platform.environment['MAIL_CLEANER_SCREENSHOTS'];
    if (capture != null) {
      await tester.runAsync(() async {
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        final font = File('C:/Windows/Fonts/segoeui.ttf');
        if (await font.exists()) {
          final data = ByteData.sublistView(await font.readAsBytes());
          for (final family in ['MailQA', 'Segoe UI Variable', 'Segoe UI']) {
            final loader = FontLoader(family)..addFont(Future.value(data));
            await loader.load();
          }
        }
      });
    }

    for (final theme in AppThemeChoice.values) {
      for (final connected in [false, true]) {
        final boundary = GlobalKey();
        final controller = await pumpModule(
          tester,
          size: const Size(1440, 900),
          connect: connected,
          scan: connected,
          theme: theme,
          boundary: boundary,
          fontFamily: capture == null ? null : 'MailQA',
        );
        if (connected) {
          controller.selectGroup('[GTEL-VOICE]', true);
          await tester.pumpAndSettle();
          expect(find.text('[GTEL-VOICE]'), findsOneWidget);
        } else {
          expect(find.text('Kết nối máy chủ'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);

        if (capture != null) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 1);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(capture).create(recursive: true);
            final screen = connected ? 'workspace' : 'connect';
            await File(
              '$capture/mail-cleaner-$screen-${theme.name}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }

        controller.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    }
    AppCyberTheme.activate(AppThemeChoice.cyber);
  });
}
