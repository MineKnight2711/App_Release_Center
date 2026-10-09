import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_management_center/app/modules/plan_studio/models/work_item.dart';
import 'package:app_management_center/app/modules/plan_studio/views/plan_studio_view.dart';
import 'package:app_management_center/app/modules/plan_studio/views/ticket_editor.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'plan_studio_widget_test.dart' show BoardFixture;

/// Two projects; moves follow the repository's rules in memory.
class TwoProjects extends BoardFixture {
  final registry = [
    const StudioProject('project', '/demo/mobile-app', 'Mobile App'),
    const StudioProject('web', '/demo/web-admin', 'Web Admin'),
  ];
  final calls = <String>[];

  @override
  Future<List<StudioProject>> projects() async => [...registry];

  @override
  Future<StudioProject> renameProject(String id, String name) async {
    final i = registry.indexWhere((p) => p.id == id);
    registry[i] = StudioProject(id, registry[i].path, name);
    return registry[i];
  }

  @override
  Future<List<WorkItem>> moveToProject(
    String id,
    int revision,
    String projectId, {
    bool withChildren = true,
  }) async {
    calls.add('$id→$projectId children:$withChildren');
    WorkItem relocate(WorkItem t) {
      final next = WorkItem.fromJson({...t.toJson(), 'projectId': projectId});
      rows[rows.indexOf(t)] = next;
      return next;
    }

    final main = relocate(rows.firstWhere((i) => i.id == id));
    main.parentId = null;
    final moved = [main];
    for (final child in rows.where((i) => i.parentId == id).toList()) {
      if (withChildren) {
        moved.add(relocate(child));
      } else {
        child.parentId = null;
      }
    }
    return moved;
  }
}

void main() {
  Future<void> mount(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1920, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppCyberTheme.themeData(AppThemeChoice.console),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('rename the current project from the project picker', (
    tester,
  ) async {
    final repository = TwoProjects();
    await mount(
      tester,
      PlanStudioView(
        repository: repository,
        initialProjectPath: repository.project.path,
      ),
    );
    await tester.tap(find.byTooltip('Chọn dự án'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đổi tên “Mobile App”…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('rename-project')),
      '  Ứng dụng   bán hàng ',
    );
    await tester.pump();
    await tester.tap(find.text('Đổi tên'));
    await tester.pumpAndSettle();
    expect(repository.registry.first.name, 'Ứng dụng bán hàng');
    expect(find.text('Ứng dụng bán hàng'), findsOneWidget);
    expect(find.text('Mobile App'), findsNothing);
  });

  testWidgets('move a plan with its task from the card menu', (tester) async {
    final repository = TwoProjects();
    await mount(
      tester,
      PlanStudioView(
        repository: repository,
        initialProjectPath: repository.project.path,
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('ticket-plan')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chuyển sang dự án…'));
    await tester.pumpAndSettle();
    expect(find.text('Chuyển kèm 1 task con'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('move-to-web')));
    await tester.pump();
    await tester.tap(find.text('Chuyển'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['plan→web children:true']);
    expect(find.byKey(const ValueKey('ticket-plan')), findsNothing);
    expect(find.byKey(const ValueKey('ticket-task')), findsNothing);
    expect(
      find.text('Đã chuyển MPS-001 và 1 task con sang Web Admin.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Mở dự án'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ticket-plan')), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-task')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all-projects board labels cards and still offers move', (
    tester,
  ) async {
    final repository = TwoProjects();
    await mount(tester, PlanStudioView(repository: repository));
    expect(find.textContaining('MPS-004 · Mobile App'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('ticket-note')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    // Read-only here: no status or deadline actions, but moving works.
    expect(find.text('Đặt hạn…'), findsNothing);
    await tester.tap(find.text('Chuyển sang dự án…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('move-to-web')));
    await tester.pump();
    await tester.tap(find.text('Chuyển'));
    await tester.pumpAndSettle();
    expect(find.textContaining('MPS-007 · Note · Web Admin'), findsOneWidget);
  });

  testWidgets('editor moves a task and warns it leaves its plan', (
    tester,
  ) async {
    final repository = TwoProjects();
    await mount(
      tester,
      TicketEditor(
        repository: repository,
        item: repository.rows.firstWhere((i) => i.id == 'task'),
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('prop-project')),
        matching: find.text('Mobile App'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('prop-project')));
    await tester.pumpAndSettle();
    expect(find.textContaining('bỏ liên kết với plan MPS-001'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('move-to-web')));
    await tester.pump();
    await tester.tap(find.text('Chuyển'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['task→web children:true']);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('prop-project')),
        matching: find.text('Web Admin'),
      ),
      findsOneWidget,
    );
    expect(find.text('Không gắn plan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
