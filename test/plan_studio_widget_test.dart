import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_management_center/app/modules/plan_studio/models/work_item.dart';
import 'package:app_management_center/app/modules/plan_studio/repositories/plan_repository.dart';
import 'package:app_management_center/app/modules/plan_studio/services/deadline.dart';
import 'package:app_management_center/app/modules/plan_studio/views/plan_studio_view.dart';
import 'package:app_management_center/app/modules/plan_studio/views/ticket_editor.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';

// A synchronous I/O substitute keeps gesture tests independent of SQLite's
// isolate. Persistence and transaction invariants use the real DB in other tests.
class BoardFixture implements PlanRepository {
  final project = const StudioProject(
    'project',
    '/demo/mobile-app',
    'Mobile App',
  );
  final rows = <WorkItem>[
    WorkItem(
      id: 'plan',
      projectId: 'project',
      number: 1,
      title: 'Cải thiện trải nghiệm thanh toán',
      type: WorkType.plan,
      body: 'Làm rõ luồng thanh toán, kiểm tra lỗi và chia nhỏ công việc.',
      labels: ['Mobile', 'UX'],
      priority: 'P1',
    ),
    WorkItem(
      id: 'task',
      projectId: 'project',
      number: 2,
      title: 'Thiết kế màn xác nhận đơn hàng',
      status: WorkStatus.ready,
      parentId: 'plan',
      labels: ['Flutter'],
      priority: 'P1',
    ),
    WorkItem(
      id: 'working',
      projectId: 'project',
      number: 3,
      title: 'Lưu bản nháp khi chuyển màn',
      status: WorkStatus.inProgress,
      labels: ['State'],
    ),
    WorkItem(
      id: 'blocked',
      projectId: 'project',
      number: 4,
      title: 'Kết nối cổng thanh toán',
      status: WorkStatus.blocked,
      blockedReason: 'Chờ tài khoản sandbox từ đối tác.',
      priority: 'P0',
    ),
    WorkItem(
      id: 'review',
      projectId: 'project',
      number: 5,
      title: 'Kiểm tra giao diện trên màn nhỏ',
      status: WorkStatus.review,
      labels: ['QA'],
    ),
    WorkItem(
      id: 'done',
      projectId: 'project',
      number: 6,
      title: 'Bổ sung thông báo lỗi rõ ràng',
      status: WorkStatus.done,
      labels: ['Android'],
    ),
    WorkItem(
      id: 'note',
      projectId: 'project',
      number: 7,
      title: 'Ghi chú buổi trao đổi với team',
      type: WorkType.note,
      body: 'Ưu tiên hoàn tất luồng chính trước. Kiểm tra lại khi mạng yếu.',
      labels: ['Quyết định'],
    ),
  ];
  bool failMove = false;
  bool failDelete = false;
  @override
  Future<void> delete(String id, int revision) async {
    if (failDelete) throw StateError('Không xóa được dữ liệu');
    rows.removeWhere((i) => i.id == id);
    for (final child in rows.where((i) => i.parentId == id)) {
      child.parentId = null;
      child.sourceRevisionId = null;
    }
  }

  @override
  Future<List<StudioProject>> projects() async => [project];
  @override
  Future<StudioProject> ensureProject(String path) async => project;
  @override
  Future<List<WorkItem>> items() async => rows.map((i) => i.clone()).toList();
  @override
  Future<WorkItem> save(
    WorkItem item, {
    String action = 'Cập nhật nội dung',
  }) async {
    final saved = item.clone()..revision = item.revision + 1;
    if (saved.number == 0) saved.number = rows.length + 1;
    rows.removeWhere((i) => i.id == saved.id);
    rows.add(saved);
    return saved;
  }

  @override
  Future<void> move(
    String id,
    int revision,
    WorkStatus status, {
    String? beforeId,
    String reason = '',
  }) async {
    if (failMove) throw StateError('Không ghi được dữ liệu');
    rows.firstWhere((i) => i.id == id).status = status;
  }

  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Deadlines in every state, relative to the real clock the board reads.
BoardFixture withDeadlines() {
  final repository = BoardFixture();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  WorkItem row(String id) => repository.rows.firstWhere((i) => i.id == id);
  setDue(row('task'), today);
  setDue(row('blocked'), today.subtract(const Duration(days: 2)));
  setDue(
    row('working'),
    today.add(const Duration(days: 1, hours: 17)),
    allDay: false,
  );
  row('working').checklist.addAll([
    {'text': 'A', 'done': true},
    {'text': 'B', 'done': false},
    {'text': 'C', 'done': false},
  ]);
  setDue(row('review'), today.add(const Duration(days: 4)));
  setDue(row('done'), today.subtract(const Duration(days: 1)));
  row('done').completedAt = today
      .subtract(const Duration(days: 1, hours: -9))
      .toUtc()
      .toIso8601String();
  return repository;
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    BoardFixture repository, {
    Size size = const Size(1400, 950),
    AppThemeChoice theme = AppThemeChoice.defaultTheme,
    GlobalKey? boundary,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppCyberTheme.themeData(theme).copyWith(
            textTheme: AppCyberTheme.themeData(
              theme,
            ).textTheme.apply(fontFamily: 'StudioQA'),
          ),
          home: PlanStudioView(
            repository: repository,
            initialProjectPath: repository.project.path,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'delete asks confirmation, preserves children and refreshes board',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = BoardFixture();
      await mount(tester, repository);
      await tester.tap(find.byKey(const ValueKey('ticket-plan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thao tác ticket'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa plan…'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.textContaining('1 task con'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(repository.rows.any((i) => i.id == 'plan'), isTrue);
      await tester.tap(find.byTooltip('Thao tác ticket'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa plan…'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Xóa vĩnh viễn'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ticket-plan')), findsNothing);
      expect(
        repository.rows.firstWhere((i) => i.id == 'task').parentId,
        isNull,
      );
      expect(find.byKey(const ValueKey('ticket-task')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('delete error keeps ticket and editor available', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = BoardFixture()..failDelete = true;
    await mount(tester, repository);
    await tester.tap(find.byKey(const ValueKey('ticket-task')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Thao tác ticket'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa task…'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Xóa vĩnh viễn'));
    await tester.pumpAndSettle();
    expect(find.byType(TicketEditor), findsOneWidget);
    expect(find.textContaining('Không xóa được dữ liệu'), findsWidgets);
    expect(repository.rows.any((i) => i.id == 'task'), isTrue);
  });

  testWidgets(
    '200 tickets remain scrollable and edge drag scrolls horizontally',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = BoardFixture();
      for (var n = 8; n <= 200; n++) {
        repository.rows.add(
          WorkItem(
            id: 'bulk-$n',
            projectId: 'project',
            number: n,
            title: 'Công việc $n',
            status: WorkStatus.values[n % 6],
          ),
        );
      }
      await mount(tester, repository);
      expect(tester.takeException(), isNull);
      final horizontal = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('ticket-plan'))),
      );
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveTo(const Offset(1380, 420));
      await tester.pump(const Duration(milliseconds: 600));
      expect(horizontal.position.pixels, greaterThan(0));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'board drag to empty part of destination persists and failure preserves card',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = BoardFixture();
      await mount(tester, repository);
      final from = tester.getCenter(find.byKey(const ValueKey('ticket-note')));
      final target = tester.getRect(find.byKey(const ValueKey('column-ready')));
      final gesture = await tester.startGesture(from);
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveTo(Offset(target.center.dx, target.bottom - 70));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        repository.rows.firstWhere((i) => i.id == 'note').status,
        WorkStatus.ready,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('column-ready')),
          matching: find.byKey(const ValueKey('ticket-note')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      repository.failMove = true;
      final again = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('ticket-note'))),
      );
      await again.moveBy(const Offset(-20, 0));
      await tester.pump();
      final backlog = tester.getRect(
        find.byKey(const ValueKey('column-backlog')),
      );
      await again.moveTo(Offset(backlog.center.dx, backlog.bottom - 70));
      await tester.pump(const Duration(milliseconds: 100));
      await again.up();
      await tester.pumpAndSettle();
      expect(
        repository.rows.firstWhere((i) => i.id == 'note').status,
        WorkStatus.ready,
      );
      expect(find.textContaining('Không ghi được dữ liệu'), findsOneWidget);
    },
  );

  testWidgets('narrow board, search and linked task editor avoid overflow', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = BoardFixture();
    await mount(tester, repository, size: const Size(600, 900));
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField).first, 'Ghi chú');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ticket-plan')), findsNothing);
    expect(find.byKey(const ValueKey('ticket-note')), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: TicketEditor(repository: repository, item: repository.rows[1]),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField).first, 'Tiêu đề đã sửa');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(
      repository.rows.firstWhere((i) => i.id == 'task').title,
      'Tiêu đề đã sửa',
    );
    expect(find.text('Đã lưu trên máy'), findsOneWidget);
  });

  testWidgets('deadline chips, health filter and card deadline picker', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = withDeadlines();
    await mount(tester, repository);
    expect(find.text('Trễ 2 ngày'), findsOneWidget);
    expect(find.text('Hôm nay'), findsWidgets);
    expect(find.text('Đúng hạn'), findsOneWidget);
    expect(find.text('Task Hôm nay'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('health-overdue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ticket-blocked')), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-task')), findsNothing);
    expect(find.text('Xóa lọc'), findsOneWidget);
    await tester.tap(find.text('Xóa lọc'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ticket-task')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('ticket-note')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đặt hạn…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ngày mai'));
    await tester.pump();
    await tester.tap(find.text('Lưu hạn'));
    await tester.pumpAndSettle();
    final note = repository.rows.firstWhere((i) => i.id == 'note');
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(note.dueAllDay, isTrue);
    expect(
      note.dueAt!.toLocal(),
      DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 23, 59, 59),
    );
    expect(find.text('Mai'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed column keeps its drop target and expands on tap', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, BoardFixture(), size: const Size(1920, 950));
    final done = find.byKey(const ValueKey('column-done'));
    await tester.tap(
      find.descendant(of: done, matching: find.byTooltip('Thu gọn cột')),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(done).width, 44);
    expect(find.byKey(const ValueKey('ticket-done')), findsNothing);
    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ticket-done')), findsOneWidget);
  });

  testWidgets('light and dark board visual QA with all six columns', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final capture = Platform.environment['STUDIO_SCREENSHOTS'];
    if (capture != null) {
      await tester.runAsync(() async {
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        final font = File('C:/Windows/Fonts/segoeui.ttf');
        if (await font.exists()) {
          final data = ByteData.sublistView(await font.readAsBytes());
          for (final family in ['StudioQA', 'Segoe UI Variable', 'Segoe UI']) {
            final loader = FontLoader(family)..addFont(Future.value(data));
            await loader.load();
          }
        }
      });
    }
    for (final theme in AppThemeChoice.values) {
      final key = GlobalKey();
      await mount(
        tester,
        withDeadlines(),
        size: const Size(1920, 1000),
        theme: theme,
        boundary: key,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('column-done')), findsOneWidget);
      if (capture != null) {
        await tester.runAsync(() async {
          final render =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(capture).create(recursive: true);
          await File(
            '$capture/plan-studio-${theme.name}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
