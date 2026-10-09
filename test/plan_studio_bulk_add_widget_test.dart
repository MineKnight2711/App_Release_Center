import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_management_center/app/modules/plan_studio/models/work_item.dart';
import 'package:app_management_center/app/modules/plan_studio/views/plan_studio_view.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'plan_studio_widget_test.dart' show BoardFixture;

/// Records each batch and stores it the way the board reads it back.
class BulkFixture extends BoardFixture {
  final batches = <List<WorkItem>>[];

  @override
  Future<List<WorkItem>> createMany(List<WorkItem> drafts) async {
    batches.add(drafts);
    final created = <WorkItem>[];
    for (final draft in drafts) {
      final item = draft.clone()
        ..number = rows.length + 1
        ..revision = 1;
      rows.add(item);
      created.add(item);
    }
    return created;
  }
}

void main() {
  Future<void> mount(WidgetTester tester, BulkFixture repository) async {
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

  Future<void> openFromMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Tạo loại khác'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tạo hàng loạt'));
    await tester.pumpAndSettle();
  }

  testWidgets('create menu adds the previewed tasks under a plan', (
    tester,
  ) async {
    final repository = BulkFixture();
    await mount(tester, repository);
    await openFromMenu(tester);
    expect(find.text('Tạo task hàng loạt'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('bulk-input')),
      'Viết API !p1\n- viết api\n2. Kiểm thử #qa\nLưu bản nháp khi chuyển màn',
    );
    await tester.pump();
    expect(
      find.text('Xem trước · 3 task · bỏ qua 1 dòng trùng'),
      findsOneWidget,
    );
    expect(find.text('Trùng dòng phía trên, sẽ bỏ qua'), findsOneWidget);
    expect(find.text('Đã có MPS-003 cùng tiêu đề trên board'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bulk-plan')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('MPS-001 · Cải thiện trải nghiệm thanh toán').last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bulk-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(WorkStatus.ready.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tạo 3 task'));
    await tester.pumpAndSettle();
    final batch = repository.batches.single;
    expect(batch.map((i) => i.title), [
      'Viết API',
      'Kiểm thử',
      'Lưu bản nháp khi chuyển màn',
    ]);
    expect(batch.first.priority, 'P1');
    expect(batch[1].labels, ['qa']);
    expect(batch.every((i) => i.parentId == 'plan'), isTrue);
    expect(batch.every((i) => i.status == WorkStatus.ready), isTrue);
    expect(find.text('Tạo task hàng loạt'), findsNothing);
    expect(find.text('Đã tạo 3 task.'), findsOneWidget);
    expect(find.text('Viết API'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shift+N opens the composer and Ctrl+Enter creates', (
    tester,
  ) async {
    final repository = BulkFixture();
    await mount(tester, repository);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Tạo task hàng loạt'), findsOneWidget);
    final submit = find.byKey(const ValueKey('bulk-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.enterText(find.byKey(const ValueKey('bulk-input')), 'A\nB');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(repository.batches.single.map((i) => i.title), ['A', 'B']);
    expect(
      repository.batches.single.every((i) => i.status == WorkStatus.backlog),
      isTrue,
    );
  });

  testWidgets('a pasted status report keeps its priorities', (tester) async {
    final repository = BulkFixture();
    await mount(tester, repository);
    await openFromMenu(tester);
    await tester.enterText(
      find.byKey(const ValueKey('bulk-input')),
      '➡️ 🔴 Cao – Sửa lỗi phát tiếng chụp ảnh khi chụp mặt sau CCCD trên iOS\n'
      '➡️ 🟡 Trung bình – Tích hợp miniapp Numbala và VNetrip vào FizaHUB\n'
      '➡️ ⏳ Chờ phản hồi – Chờ IVAN báo lại kết quả nghiệm thu luồng BHXH',
    );
    await tester.pump();
    expect(find.text('Tạo 3 task'), findsOneWidget);
    expect(find.text('Bị chặn · Chờ phản hồi'), findsOneWidget);
    await tester.tap(find.text('Tạo 3 task'));
    await tester.pumpAndSettle();
    final batch = repository.batches.single;
    expect(batch.map((i) => i.priority), ['P1', 'P2', 'P2']);
    expect(batch.map((i) => i.status), [
      WorkStatus.backlog,
      WorkStatus.backlog,
      WorkStatus.blocked,
    ]);
    expect(batch.last.blockedReason, 'Chờ phản hồi');
    expect(
      batch.first.title,
      'Sửa lỗi phát tiếng chụp ảnh khi chụp mặt sau CCCD trên iOS',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('more than the limit is refused before saving', (tester) async {
    final repository = BulkFixture();
    await mount(tester, repository);
    await openFromMenu(tester);
    await tester.enterText(
      find.byKey(const ValueKey('bulk-input')),
      [for (var n = 0; n < 201; n++) 'Task $n'].join('\n'),
    );
    await tester.pump();
    expect(find.textContaining('Tối đa 200 task mỗi lần'), findsOneWidget);
    final submit = find.byKey(const ValueKey('bulk-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(repository.batches, isEmpty);
  });
}
