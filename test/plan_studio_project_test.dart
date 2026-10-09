import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_management_center/app/modules/plan_studio/models/work_item.dart';
import 'package:app_management_center/app/modules/plan_studio/repositories/local_plan_repository.dart';

void main() {
  late Directory directory;
  late LocalPlanRepository repo;
  late StudioProject a, b;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('plan-project-test-');
    repo = await LocalPlanRepository.open(
      path: '${directory.path}/studio.sqlite',
    );
    a = await repo.ensureProject('${directory.path}/app-a');
    b = await repo.ensureProject('${directory.path}/app-b');
  });
  tearDown(() async {
    await repo.close();
    await directory.delete(recursive: true);
  });

  Future<WorkItem> save(
    String id, {
    WorkType type = WorkType.task,
    String? parent,
    StudioProject? project,
    WorkStatus status = WorkStatus.backlog,
  }) => repo.save(
    WorkItem(
      id: id,
      projectId: (project ?? a).id,
      title: id,
      type: type,
      parentId: parent,
      status: status,
    ),
  );
  Future<WorkItem> get(String id) async =>
      (await repo.items()).firstWhere((i) => i.id == id);

  test('rename trims, keeps the folder and survives relink', () async {
    final renamed = await repo.renameProject(a.id, '  Ứng dụng   bán hàng ');
    expect(renamed.name, 'Ứng dụng bán hàng');
    expect(renamed.path, a.path);
    await repo.relinkProject(a.id, '${directory.path}/moved');
    final project = (await repo.projects()).firstWhere((p) => p.id == a.id);
    expect(project.name, 'Ứng dụng bán hàng');
    expect(project.path, endsWith('moved'));
    // Re-adding the same folder finds the renamed project, not a new one.
    expect((await repo.ensureProject('${directory.path}/moved')).id, a.id);
    expect(() => repo.renameProject(a.id, '   '), throwsStateError);
    expect(() => repo.renameProject(a.id, 'x' * 81), throwsStateError);
    expect(() => repo.renameProject('missing', 'X'), throwsStateError);
  });

  test('plan moves with its tasks, keeping code, status and links', () async {
    final plan = await save('plan', type: WorkType.plan);
    await save('t1', parent: 'plan', status: WorkStatus.inProgress);
    await save('t2', parent: 'plan');
    await save('other', project: b);
    final moved = await repo.moveToProject(plan.id, plan.revision, b.id);
    expect(moved.map((i) => i.id).toSet(), {'plan', 't1', 't2'});
    for (final id in ['plan', 't1', 't2']) {
      expect((await get(id)).projectId, b.id);
    }
    final t1 = await get('t1');
    expect(t1.parentId, 'plan');
    expect(t1.status, WorkStatus.inProgress);
    expect(t1.number, 2);
    expect(t1.activity.last['text'], contains('theo MPS-001'));
    final p = await get('plan');
    expect(p.activity.last['text'], 'Chuyển dự án: app-a → app-b');
    // Appended after what the destination column already had.
    expect(p.order, greaterThan((await get('other')).order));
  });

  test('plan without its tasks detaches them in the old project', () async {
    final plan = await save('plan', type: WorkType.plan);
    await save('t1', parent: 'plan');
    final moved = await repo.moveToProject(
      plan.id,
      plan.revision,
      b.id,
      withChildren: false,
    );
    expect(moved.single.id, 'plan');
    final t1 = await get('t1');
    expect(t1.projectId, a.id);
    expect(t1.parentId, isNull);
    expect(
      t1.activity.last['text'],
      'Bỏ liên kết MPS-001 vì plan chuyển dự án',
    );
  });

  test('task leaves its plan behind; note moves alone', () async {
    await save('plan', type: WorkType.plan);
    final task = await save('t1', parent: 'plan');
    await repo.moveToProject(task.id, task.revision, b.id);
    final t1 = await get('t1');
    expect(t1.projectId, b.id);
    expect(t1.parentId, isNull);
    expect(t1.activity.last['text'], contains('bỏ liên kết MPS-001'));
    expect((await get('plan')).projectId, a.id);

    final note = await save('n', type: WorkType.note);
    expect(
      (await repo.moveToProject(note.id, note.revision, b.id)).single.id,
      'n',
    );
  });

  test('stale revision, missing project and same project', () async {
    final task = await save('t1');
    expect(
      () => repo.moveToProject(task.id, task.revision + 5, b.id),
      throwsStateError,
    );
    expect(
      () => repo.moveToProject(task.id, task.revision, 'missing'),
      throwsStateError,
    );
    expect(await repo.moveToProject(task.id, task.revision, a.id), isEmpty);
    expect((await get('t1')).revision, task.revision);
  });
}
