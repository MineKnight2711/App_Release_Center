import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_management_center/app/modules/plan_studio/models/work_item.dart';
import 'package:app_management_center/app/modules/plan_studio/services/deadline.dart';
import 'package:app_management_center/app/modules/plan_studio/views/plan_studio_view.dart';
import 'package:app_management_center/app/modules/plan_studio/views/ticket_editor.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'plan_studio_widget_test.dart' show BoardFixture, withDeadlines;

void main() {
  Future<void> mountBoard(WidgetTester tester, BoardFixture repository) async {
    tester.view.physicalSize = const Size(1920, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppCyberTheme.themeData(AppThemeChoice.console),
        home: PlanStudioView(
          repository: repository,
          initialProjectPath: repository.project.path,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mountEditor(
    WidgetTester tester,
    BoardFixture repository,
    String id, {
    Size size = const Size(1300, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppCyberTheme.themeData(AppThemeChoice.console),
        home: TicketEditor(
          key: ValueKey(id),
          repository: repository,
          item: repository.rows.firstWhere((i) => i.id == id),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('column quick add reads priority, labels and deadline', (
    tester,
  ) async {
    final repository = BoardFixture();
    await mountBoard(tester, repository);
    await tester.tap(find.byTooltip('Thêm vào Chưa xử lý'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('quick-add')),
      'Viết test thanh toán !p1 #qa ^mai',
    );
    await tester.pump();
    expect(find.text('#qa'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final created = repository.rows.firstWhere(
      (i) => i.title == 'Viết test thanh toán',
    );
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(created.priority, 'P1');
    expect(created.labels, ['qa']);
    expect(created.dueAllDay, isTrue);
    expect(
      created.dueAt!.toLocal(),
      endOfLocalDay(DateTime(tomorrow.year, tomorrow.month, tomorrow.day)),
    );
    expect(created.status, WorkStatus.backlog);
    // The field stays open, cleared, for the next task.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('quick-add')))
          .controller!
          .text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+K finds a ticket without diacritics and opens it', (
    tester,
  ) async {
    await mountBoard(tester, BoardFixture());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('palette-input')), findsOneWidget);
    // Commands show first; tickets only once something is typed.
    expect(find.text('Tạo task'), findsWidgets);
    expect(find.text('MPS-004 · Kết nối cổng thanh toán'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('palette-input')),
      'ket noi cong',
    );
    await tester.pumpAndSettle();
    expect(find.text('MPS-004 · Kết nối cổng thanh toán'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(TicketEditor), findsOneWidget);
    expect(find.text('MPS-004 · Task'), findsOneWidget);
  });

  testWidgets('focused card: digit moves it, D opens the deadline picker', (
    tester,
  ) async {
    final repository = BoardFixture();
    await mountBoard(tester, repository);
    Future<void> focusCard(String id) async {
      final content = find
          .descendant(
            of: find.byKey(ValueKey('ticket-$id')),
            matching: find.byType(Padding),
          )
          .first;
      Focus.of(tester.element(content)).requestFocus();
      await tester.pump();
    }

    await focusCard('note');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pumpAndSettle();
    expect(
      repository.rows.firstWhere((i) => i.id == 'note').status,
      WorkStatus.ready,
    );
    await focusCard('review');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(find.text('Lưu hạn'), findsOneWidget);
    await tester.tap(find.text('Hôm nay').last);
    await tester.pump();
    await tester.tap(find.text('Lưu hạn'));
    await tester.pumpAndSettle();
    expect(
      dueState(
        repository.rows.firstWhere((i) => i.id == 'review'),
        DateTime.now(),
      ),
      DueState.today,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('? opens the shortcut sheet', (tester) async {
    await mountBoard(tester, BoardFixture());
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.pumpAndSettle();
    expect(find.text('Phím tắt'), findsWidgets);
    expect(find.text('Bảng lệnh và tìm ticket'), findsOneWidget);
  });

  testWidgets('properties rail edits priority and labels through autosave', (
    tester,
  ) async {
    final repository = BoardFixture();
    await mountEditor(tester, repository, 'working');
    await tester.tap(find.byKey(const ValueKey('prop-priority')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('P0 · Khẩn cấp').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prop-labels')));
    await tester.pumpAndSettle();
    // Suggestions come from other tickets in the project.
    await tester.tap(find.widgetWithText(ActionChip, 'Mobile'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Thêm nhãn rồi Enter'),
      '#perf',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    final saved = repository.rows.firstWhere((i) => i.id == 'working');
    expect(saved.priority, 'P0');
    expect(saved.labels, ['State', 'Mobile', 'perf']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan body previews Markdown; narrow editor stacks the rail', (
    tester,
  ) async {
    final repository = BoardFixture();
    repository.rows.first.body =
        '# Mục tiêu\n\n- [x] Khảo sát\n- [ ] **Triển khai** `api`\n\n1. Bước một';
    await mountEditor(tester, repository, 'plan');
    expect(find.byKey(const ValueKey('body-preview')), findsOneWidget);
    expect(find.text('Mục tiêu'), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    await tester.tap(find.text('Viết'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('body-preview')), findsNothing);

    await mountEditor(
      tester,
      BoardFixture(),
      'task',
      size: const Size(420, 900),
    );
    expect(find.byKey(const ValueKey('prop-status')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('task due after its plan warns on both sides', (tester) async {
    final repository = withDeadlines();
    final plan = repository.rows.firstWhere((i) => i.id == 'plan');
    setDue(plan, DateTime.now().subtract(const Duration(days: 1)));
    await mountEditor(tester, repository, 'task');
    expect(find.textContaining('Sau hạn của plan MPS-001'), findsOneWidget);

    await mountEditor(tester, repository, 'plan');
    expect(find.text('1 task con có hạn sau plan'), findsOneWidget);
    expect(find.textContaining('Task gần hạn nhất: MPS-002'), findsOneWidget);
  });
}
