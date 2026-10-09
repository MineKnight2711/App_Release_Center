import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_management_center/app/modules/plan_studio/models/work_item.dart';
import 'package:app_management_center/app/modules/plan_studio/repositories/local_plan_repository.dart';
import 'package:app_management_center/app/modules/plan_studio/views/ticket_editor.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';

void main() {
  testWidgets(
    'note reminder tab offers three modes and saves a recurring schedule',
    (tester) async {
      late Directory temp;
      late LocalPlanRepository repo;
      late WorkItem note;
      await tester.runAsync(() async {
        final font = File('C:/Windows/Fonts/segoeui.ttf');
        if (await font.exists()) {
          final bytes = ByteData.sublistView(await font.readAsBytes());
          for (final family in ['StudioQA', 'Segoe UI Variable', 'Segoe UI']) {
            await (FontLoader(family)..addFont(Future.value(bytes))).load();
          }
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        }
        temp = await Directory.systemTemp.createTemp('schedule-ui-');
        repo = await LocalPlanRepository.open(
          path: '${temp.path}/studio.sqlite',
        );
        final project = await repo.ensureProject(temp.path);
        note = await repo.save(
          WorkItem(
            id: 'note',
            projectId: project.id,
            title: 'Ghi chú kiểm tra tiến độ',
            type: WorkType.note,
          ),
        );
      });
      tester.view.physicalSize = const Size(720, 1000);
      tester.view.devicePixelRatio = 1;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppCyberTheme.themeData(AppThemeChoice.console).copyWith(
            textTheme: AppCyberTheme.themeData(
              AppThemeChoice.console,
            ).textTheme.apply(fontFamily: 'StudioQA'),
          ),
          home: RepaintBoundary(
            key: boundary,
            child: TicketEditor(repository: repo, item: note),
          ),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhắc hẹn').first);
      await tester.pumpAndSettle();
      expect(find.text('Ngày & giờ'), findsOneWidget);
      expect(find.text('Sau khoảng thời gian'), findsOneWidget);
      await tester.tap(find.text('Lặp định kỳ'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Số lượng'), '15');
      await tester.pumpAndSettle();
      expect(find.textContaining('sau đó mỗi 15 phút'), findsOneWidget);
      await tester.ensureVisible(find.text('Lưu nhắc hẹn'));
      await tester.tap(find.text('Lưu nhắc hẹn'));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final rows = await repo.reminders.all();
        expect(rows.single.intervalMinutes, 15);
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/qa').create(recursive: true);
        await File(
          'build/qa/plan-studio-reminder-ui.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(420, 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(720, 1000);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sau khoảng thời gian'));
      await tester.tap(find.text('Sau khoảng thời gian'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 phút'));
      await tester.ensureVisible(find.text('Lưu nhắc hẹn'));
      await tester.tap(find.text('Lưu nhắc hẹn'));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final rows = await repo.reminders.all();
        expect(rows.length, 2);
        final once = rows.singleWhere((r) => r.intervalMinutes == null);
        expect(
          once.eligibleAt.difference(DateTime.now()).inSeconds,
          inInclusiveRange(290, 300),
        );
      });
      await tester.ensureVisible(find.text('Ngày & giờ'));
      await tester.tap(find.text('Ngày & giờ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu nhắc hẹn'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Chọn ngày và giờ nhắc trước khi lưu.'),
        findsOneWidget,
      );
      await tester.runAsync(
        () async => expect((await repo.reminders.all()).length, 2),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await repo.close();
        await temp.delete(recursive: true);
      });
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
