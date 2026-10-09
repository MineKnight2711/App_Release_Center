import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_management_center/app/modules/plan_studio/models/work_item.dart';
import 'package:app_management_center/app/modules/plan_studio/repositories/local_plan_repository.dart';

void main() {
  late Directory directory;
  late LocalPlanRepository repository;
  late StudioProject project;
  var counter = 0;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('plan-studio-test-');
    repository = await LocalPlanRepository.open(
      path: '${directory.path}/studio.sqlite',
    );
    project = await repository.ensureProject('${directory.path}/project');
  });
  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });
  Future<WorkItem> create({
    WorkType type = WorkType.task,
    String? parent,
    WorkStatus status = WorkStatus.backlog,
  }) => repository.save(
    WorkItem(
      id: 'ticket-${counter++}',
      projectId: project.id,
      title: 'Công việc $counter',
      type: type,
      parentId: parent,
      status: status,
    ),
  );

  test(
    'durable draft, notes, revision and reorder survive reopening',
    () async {
      final a = await create(type: WorkType.plan);
      final b = await create();
      a.body = '## Tiêu chí\nNội dung tiếng Việt';
      a.draft = {
        'source': 'Yêu cầu',
        'answers': ['Android'],
        'step': 1,
      };
      a.notes.add({'at': a.createdAt, 'body': 'Bước tiếp theo'});
      await repository.save(a);
      await repository.move(
        b.id,
        b.revision,
        WorkStatus.backlog,
        beforeId: a.id,
      );
      await repository.close();
      repository = await LocalPlanRepository.open(
        path: '${directory.path}/studio.sqlite',
      );
      final all = await repository.items();
      expect(all.map((i) => i.id), [b.id, a.id]);
      expect(all.last.draft['answers'], ['Android']);
      expect(all.last.notes.single['body'], 'Bước tiếp theo');
      expect(all.last.body, contains('tiếng Việt'));
      expect(all.first.activity.last['text'], 'Sắp xếp vị trí');
    },
  );

  test(
    'delete plan retains and detaches active and archived tasks durably',
    () async {
      final plan = await create(type: WorkType.plan);
      final active = await create(parent: plan.id);
      var archived = await create(parent: plan.id);
      archived.archived = true;
      archived.sourceRevisionId = 'old-version';
      archived = await repository.save(archived);
      await repository.delete(plan.id, plan.revision);
      await repository.close();
      repository = await LocalPlanRepository.open(
        path: '${directory.path}/studio.sqlite',
      );
      final all = await repository.items();
      expect(all.map((i) => i.id).toSet(), {active.id, archived.id});
      expect(
        all.every((i) => i.parentId == null && i.sourceRevisionId == null),
        isTrue,
      );
      expect(all.firstWhere((i) => i.id == archived.id).archived, isTrue);
      expect(
        all.every(
          (i) => i.activity.last['text'].toString().contains('xóa plan'),
        ),
        isTrue,
      );
      await expectLater(repository.save(plan), throwsStateError);
    },
  );

  test(
    'delete task updates parent history and does not reuse its ticket number',
    () async {
      final plan = await create(type: WorkType.plan);
      final task = await create(parent: plan.id);
      await repository.delete(task.id, task.revision);
      final remaining = (await repository.items()).single;
      expect(remaining.id, plan.id);
      expect(
        remaining.activity.last['text'],
        contains('Xóa task ${task.code}'),
      );
      expect(remaining.status, WorkStatus.backlog);
      final next = await create();
      expect(next.number, greaterThan(task.number));
    },
  );

  test('stale delete rolls back without detaching any children', () async {
    final plan = await create(type: WorkType.plan);
    await create(parent: plan.id);
    plan.title = 'New title';
    await repository.save(plan);
    final before = await repository.exportBackup();
    await expectLater(
      repository.delete(plan.id, plan.revision),
      throwsStateError,
    );
    expect(await repository.exportBackup(), before);
  });

  test(
    'invalid Done transition is atomic, including parent and history',
    () async {
      final plan = await create(type: WorkType.plan);
      await create(parent: plan.id);
      final before = await repository.exportBackup();
      await expectLater(
        repository.move(plan.id, plan.revision, WorkStatus.done),
        throwsStateError,
      );
      expect(await repository.exportBackup(), before);
    },
  );

  test(
    'reopening or restoring unfinished child reopens completed plan',
    () async {
      var plan = await create(type: WorkType.plan);
      var task = await create(parent: plan.id, status: WorkStatus.done);
      await repository.move(plan.id, plan.revision, WorkStatus.done);
      await repository.move(task.id, task.revision, WorkStatus.inProgress);
      var all = await repository.items();
      expect(
        all.firstWhere((i) => i.id == plan.id).status,
        WorkStatus.inProgress,
      );
      task = all.firstWhere((i) => i.id == task.id)..archived = true;
      await repository.save(task);
      plan = (await repository.items()).firstWhere((i) => i.id == plan.id);
      await repository.move(plan.id, plan.revision, WorkStatus.done);
      task = (await repository.items()).firstWhere((i) => i.id == task.id)
        ..archived = false;
      await repository.save(task);
      all = await repository.items();
      expect(
        all.firstWhere((i) => i.id == plan.id).status,
        WorkStatus.inProgress,
      );
      expect(all.firstWhere((i) => i.id == plan.id).completedAt, isNull);
    },
  );

  test(
    'checklist and blocked reason gate transitions without losing record',
    () async {
      var item = await create();
      await expectLater(
        repository.move(item.id, item.revision, WorkStatus.blocked),
        throwsStateError,
      );
      item.checklist.add({'text': 'Kiểm thử', 'done': false});
      item = await repository.save(item);
      await expectLater(
        repository.move(item.id, item.revision, WorkStatus.review),
        throwsStateError,
      );
      await repository.move(
        item.id,
        item.revision,
        WorkStatus.blocked,
        reason: 'Chờ API',
      );
      expect((await repository.items()).single.blockedReason, 'Chờ API');
    },
  );

  test('stale editor cannot overwrite newer board changes', () async {
    final item = await create();
    await repository.move(item.id, item.revision, WorkStatus.ready);
    item.title = 'Stale title';
    await expectLater(repository.save(item), throwsStateError);
    expect((await repository.items()).single.title, isNot('Stale title'));
  });

  test('task extraction is idempotent and retains source revision', () async {
    var plan = await create(type: WorkType.plan, status: WorkStatus.done);
    plan.versions.add({
      'id': 'version-1',
      'body': 'Nội dung',
      'at': plan.createdAt,
    });
    plan = await repository.save(plan);
    final tasks = await repository.createTasks(plan.id, plan.revision, [
      'UI',
      'API',
      'UI',
    ]);
    expect(tasks, hasLength(2));
    expect(tasks.first.sourceRevisionId, 'version-1');
    plan = (await repository.items()).firstWhere((i) => i.id == plan.id);
    expect(plan.status, WorkStatus.inProgress);
    expect(
      await repository.createTasks(plan.id, plan.revision, ['UI', 'API']),
      isEmpty,
    );
  });

  test(
    'backup merges without overwriting, invalid relationships roll back',
    () async {
      final item = await create();
      final backup = await repository.exportBackup();
      expect(await repository.importBackup(backup), 0);
      final data = jsonDecode(backup) as Map<String, dynamic>;
      final row = Map<String, dynamic>.from(
        (data['tickets'] as List).single as Map,
      );
      row['id'] = 'imported';
      row['parentId'] = 'missing-parent';
      data['tickets'] = [row];
      await expectLater(
        repository.importBackup(jsonEncode(data)),
        throwsStateError,
      );
      expect((await repository.items()).single.id, item.id);
    },
  );

  test(
    'new import allocates unique numbers and project relinking preserves IDs',
    () async {
      final first = await create();
      final data =
          jsonDecode(await repository.exportBackup()) as Map<String, dynamic>;
      (data['tickets'] as List).single['id'] = 'new-id';
      expect(await repository.importBackup(jsonEncode(data)), 1);
      expect(
        (await repository.items()).map((i) => i.number).toSet(),
        hasLength(2),
      );
      await repository.relinkProject(project.id, '${directory.path}/moved');
      expect((await repository.projects()).single.id, project.id);
      expect((await repository.items()).first.projectId, first.projectId);
    },
  );

  test(
    'task cannot reference another project or turn a parent plan into note',
    () async {
      final plan = await create(type: WorkType.plan);
      await create(parent: plan.id);
      plan.type = WorkType.note;
      await expectLater(repository.save(plan), throwsStateError);
      final other = await repository.ensureProject('${directory.path}/other');
      await expectLater(
        repository.save(
          WorkItem(
            id: 'cross-project',
            projectId: other.id,
            title: 'Cross',
            parentId: plan.id,
          ),
        ),
        throwsStateError,
      );
    },
  );
}
