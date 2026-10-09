import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:app_management_center/app/modules/plan_studio/models/work_item.dart';
import 'package:app_management_center/app/modules/plan_studio/models/plan_reminder.dart';
import 'package:app_management_center/app/modules/plan_studio/repositories/local_plan_repository.dart';
import 'package:app_management_center/app/modules/plan_studio/repositories/reminder_store.dart';
import 'package:app_management_center/app/modules/plan_studio/services/reminder_scheduler.dart';
import 'package:app_management_center/app/modules/plan_studio/services/plan_progress_service.dart';

void main() {
  late Directory directory;
  late LocalPlanRepository repo;
  late StudioProject project;
  final now = DateTime.utc(2026, 9, 21, 10);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('plan-reminder-test-');
    repo = await LocalPlanRepository.open(
      path: '${directory.path}/studio.sqlite',
    );
    project = await repo.ensureProject('${directory.path}/project');
  });
  tearDown(() async {
    await repo.close();
    await directory.delete(recursive: true);
  });
  Future<WorkItem> ticket(
    String id, {
    WorkType type = WorkType.task,
    String? parent,
  }) => repo.save(
    WorkItem(
      id: id,
      projectId: project.id,
      title: id,
      type: type,
      parentId: parent,
      dueAtUtc: now.add(const Duration(hours: 1)).toIso8601String(),
    ),
  );

  test(
    'v1 database and ticket payload migrate without losing revision or sequence',
    () async {
      await repo.close();
      final path = '${directory.path}/v1.sqlite';
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE projects (id TEXT PRIMARY KEY, path TEXT UNIQUE NOT NULL, name TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE tickets (id TEXT PRIMARY KEY, number INTEGER UNIQUE NOT NULL, payload TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE metadata (key TEXT PRIMARY KEY, value INTEGER NOT NULL)',
            );
            await db.insert('projects', project.toJson());
            final old = WorkItem(
              id: 'legacy',
              projectId: project.id,
              title: 'Old',
              number: 7,
              revision: 4,
            ).toJson()..remove('dueAtUtc');
            await db.insert('tickets', {
              'id': 'legacy',
              'number': 7,
              'payload': jsonEncode(old),
            });
            await db.insert('metadata', {'key': 'sequence', 'value': 7});
          },
        ),
      );
      await db.close();
      repo = await LocalPlanRepository.open(path: path);
      final old = (await repo.items()).single;
      expect(old.revision, 4);
      expect(old.dueAtUtc, isNull);
      expect(await repo.reminders.all(), isEmpty);
      expect((await ticket('new')).number, 8);
    },
  );

  test(
    'snooze persists, duplicate command does not extend it, stale command fails',
    () async {
      final item = await ticket('a');
      final r = await repo.reminders.add(
        item.id,
        item.revision,
        now,
        now: now,
        allowPast: true,
      );
      await repo.reminders.act(
        r.id,
        0,
        'same-command',
        'snooze',
        now: now,
        minutes: 30,
      );
      await repo.reminders.act(
        r.id,
        0,
        'same-command',
        'snooze',
        now: now.add(const Duration(minutes: 5)),
        minutes: 30,
      );
      await expectLater(
        repo.reminders.act(r.id, 0, 'stale', 'ack'),
        throwsStateError,
      );
      await repo.close();
      repo = await LocalPlanRepository.open(
        path: '${directory.path}/studio.sqlite',
      );
      final saved = (await repo.reminders.all()).single;
      expect(saved.state, ReminderState.snoozed);
      expect(saved.eligibleAt, now.add(const Duration(minutes: 30)));
      expect(saved.revision, 1);
    },
  );

  test(
    'deadline change replaces relative schedules; clearing cancels only relative',
    () async {
      var item = await ticket('a');
      await repo.reminders.add(
        item.id,
        item.revision,
        now,
        now: now,
        offsetMinutes: 15,
      );
      final absolute = await repo.reminders.add(
        item.id,
        item.revision,
        now.add(const Duration(hours: 3)),
        now: now,
      );
      item.dueAtUtc = now.add(const Duration(hours: 2)).toIso8601String();
      item = await repo.save(item);
      var rows = await repo.reminders.all();
      expect(rows.where((r) => r.active).length, 2);
      expect(
        rows
            .singleWhere((r) => r.active && r.offsetMinutes != null)
            .scheduledAt,
        now.add(const Duration(minutes: 105)),
      );
      item.dueAtUtc = null;
      await repo.save(item);
      rows = await repo.reminders.all();
      expect(rows.where((r) => r.active).single.id, absolute.id);
    },
  );

  test(
    'completion validation rolls back cancellation; done stops reminders and reopen does not restore',
    () async {
      var item = await ticket('a');
      item.checklist.add({'text': 'Verify', 'done': false});
      item = await repo.save(item);
      await repo.reminders.add(
        item.id,
        item.revision,
        now,
        now: now,
        allowPast: true,
      );
      await expectLater(
        repo.move(item.id, item.revision, WorkStatus.done),
        throwsStateError,
      );
      expect((await repo.reminders.all()).single.active, isTrue);
      item.checklist.single['done'] = true;
      item.status = WorkStatus.done;
      item = await repo.save(item);
      expect(
        (await repo.reminders.all()).single.state,
        ReminderState.cancelled,
      );
      await repo.move(item.id, item.revision, WorkStatus.inProgress);
      expect((await repo.reminders.all()).single.active, isFalse);
    },
  );

  test(
    'delete plan preserves child schedules; archive cancels its own schedules',
    () async {
      final plan = await ticket('plan', type: WorkType.plan);
      var child = await ticket('child', parent: plan.id);
      await repo.reminders.add(
        plan.id,
        plan.revision,
        now,
        now: now,
        allowPast: true,
      );
      await repo.reminders.add(
        child.id,
        child.revision,
        now,
        now: now,
        allowPast: true,
      );
      await repo.delete(plan.id, plan.revision);
      expect(
        (await repo.reminders.all(itemId: child.id)).single.active,
        isTrue,
      );
      child = (await repo.items()).single..archived = true;
      await repo.save(child);
      expect(
        (await repo.reminders.all(itemId: child.id)).single.active,
        isFalse,
      );
    },
  );

  test(
    'backup v2 imports reminders paused and merge does not duplicate schedules',
    () async {
      final item = await ticket('a');
      await repo.reminders.add(
        item.id,
        item.revision,
        now,
        now: now,
        allowPast: true,
      );
      final backup = await repo.exportBackup();
      final target = await LocalPlanRepository.open(
        path: '${directory.path}/target.sqlite',
      );
      try {
        expect(await target.importBackup(backup), 1);
        expect(
          (await target.reminders.all()).single.state,
          ReminderState.paused,
        );
        expect(await target.importBackup(backup), 0);
        expect((await target.reminders.all()).length, 1);
      } finally {
        await target.close();
      }
      final v1 = jsonDecode(backup) as Map<String, dynamic>;
      v1['schemaVersion'] = 1;
      v1.remove('reminders');
      expect(await repo.importBackup(jsonEncode(v1)), 0);
    },
  );

  test(
    'scheduler groups missed reminders, suppresses during quiet, recovers and does not replay ack',
    () async {
      final a = await ticket('a');
      final b = await ticket('b');
      for (final item in [a, a, b]) {
        await repo.reminders.add(
          item.id,
          item.revision,
          now.subtract(const Duration(hours: 1)),
          now: now,
          allowPast: true,
        );
      }
      var quiet = true;
      final published = <Map<String, dynamic>?>[];
      final scheduler = ReminderScheduler(
        repo,
        clock: () => now,
        suppressed: (_) => quiet,
        publish: (value) async {
          published.add(value);
        },
      );
      await scheduler.scan();
      expect(published.single, isNull);
      quiet = false;
      await scheduler.scan();
      expect((published.last!['cards'] as List).length, 2);
      expect(
        ((published.last!['cards'] as List).firstWhere(
                  (c) => c['itemId'] == a.id,
                )['reminders']
                as List)
            .length,
        2,
      );
      final count = published.length;
      await scheduler.scan();
      expect(published.length, count);
      for (final r in await repo.reminders.all()) {
        await repo.reminders.act(r.id, r.revision, r.id, 'ack', now: now);
      }
      await scheduler.scan();
      expect(published.last, isNull);
      scheduler.dispose();
    },
  );

  test(
    'scheduler retries failed window publish without losing reminder',
    () async {
      final item = await ticket('a');
      await repo.reminders.add(
        item.id,
        item.revision,
        now,
        now: now,
        allowPast: true,
      );
      var fails = true;
      final scheduler = ReminderScheduler(
        repo,
        clock: () => now,
        publish: (_) async {
          if (fails) throw StateError('window');
        },
      );
      await scheduler.scan();
      expect(scheduler.error, contains('window'));
      fails = false;
      await scheduler.scan();
      expect(scheduler.error, isNull);
      expect((await repo.reminders.all()).single.active, isTrue);
      scheduler.dispose();
    },
  );

  test(
    'schedule cap, past times and stale editor revision are rejected',
    () async {
      var item = await ticket('a');
      await expectLater(
        repo.reminders.add(item.id, item.revision, now, now: now),
        throwsStateError,
      );
      for (var n = 1; n <= 3; n++) {
        await repo.reminders.add(
          item.id,
          item.revision,
          now.add(Duration(hours: n)),
          now: now,
        );
      }
      await expectLater(
        repo.reminders.add(
          item.id,
          item.revision,
          now.add(const Duration(hours: 4)),
          now: now,
        ),
        throwsStateError,
      );
      final old = item.revision;
      item = await repo.save(item..title = 'Changed');
      await expectLater(
        repo.reminders.add(item.id, old, now, now: now, allowPast: true),
        throwsStateError,
      );
    },
  );

  test(
    'progress excludes archived children and does not infer completion from checklist',
    () async {
      final plan = WorkItem(
        id: 'p',
        projectId: 'pr',
        title: 'Plan',
        type: WorkType.plan,
      );
      expect(PlanProgress(plan, []).fraction, isNull);
      final child = WorkItem(
        id: 'c',
        projectId: 'pr',
        title: 'Child',
        parentId: 'p',
        status: WorkStatus.done,
      );
      final archived = WorkItem(
        id: 'x',
        projectId: 'pr',
        title: 'Old',
        parentId: 'p',
        archived: true,
      );
      expect(PlanProgress(plan, [child, archived]).fraction, 1);
      final task = WorkItem(
        id: 't',
        projectId: 'pr',
        title: 'Task',
        checklist: [
          {'text': 'Done', 'done': true},
        ],
      );
      expect(PlanProgress(task, []).fraction, 1);
      expect(task.status, WorkStatus.backlog);
    },
  );

  test(
    'popup grouped action is atomic, idempotent and rejects cancelled snapshots',
    () async {
      final item = await ticket('atomic');
      final a = await repo.reminders.add(
        item.id,
        item.revision,
        now,
        now: now,
        allowPast: true,
      );
      final b = await repo.reminders.add(
        item.id,
        item.revision,
        now,
        now: now,
        allowPast: true,
      );
      await repo.reminders.act(b.id, b.revision, 'cancel-b', 'cancel');
      await expectLater(
        repo.applyReminderAction(
          itemId: item.id,
          itemRevision: item.revision,
          reminderRevisions: {a.id: 0, b.id: 0},
          commandId: 'invalid',
          action: 'start',
          now: now,
        ),
        throwsStateError,
      );
      expect((await repo.items()).single.status, WorkStatus.backlog);
      expect(
        (await repo.reminders.all()).firstWhere((r) => r.id == a.id).active,
        isTrue,
      );
      await repo.applyReminderAction(
        itemId: item.id,
        itemRevision: item.revision,
        reminderRevisions: {a.id: 0},
        commandId: 'valid',
        action: 'start',
        now: now,
      );
      final saved = (await repo.items()).single;
      expect(saved.status, WorkStatus.inProgress);
      await repo.applyReminderAction(
        itemId: item.id,
        itemRevision: item.revision,
        reminderRevisions: {a.id: 0},
        commandId: 'valid',
        action: 'start',
        now: now,
      );
      expect((await repo.items()).single.revision, saved.revision);
      expect(
        (await repo.reminders.all()).firstWhere((r) => r.id == a.id).state,
        ReminderState.acknowledged,
      );
    },
  );

  test('backup after deleting scheduled ticket remains importable', () async {
    final item = await ticket('deleted');
    await repo.reminders.add(
      item.id,
      item.revision,
      now,
      now: now,
      allowPast: true,
    );
    await repo.delete(item.id, item.revision);
    final backup = await repo.exportBackup();
    expect((jsonDecode(backup) as Map)['reminders'], isEmpty);
    expect(await repo.importBackup(backup), 0);
  });
  test(
    'notes support recurring reminders; ack skips missed intervals and survives restart',
    () async {
      final item = await ticket('note', type: WorkType.note);
      final r = await repo.reminders.add(
        item.id,
        item.revision,
        now,
        now: now,
        allowPast: true,
        intervalMinutes: 15,
      );
      final later = now.add(const Duration(hours: 2, minutes: 7));
      await repo.applyReminderAction(
        itemId: item.id,
        itemRevision: item.revision,
        reminderRevisions: {r.id: 0},
        commandId: 'repeat-ack',
        action: 'ack',
        now: later,
      );
      var saved = (await repo.reminders.all()).single;
      expect(saved.state, ReminderState.pending);
      expect(saved.eligibleAt, now.add(const Duration(hours: 2, minutes: 15)));
      await repo.applyReminderAction(
        itemId: item.id,
        itemRevision: item.revision,
        reminderRevisions: {r.id: 0},
        commandId: 'repeat-ack',
        action: 'ack',
        now: later,
      );
      expect((await repo.reminders.all()).single.revision, 1);
      await repo.close();
      repo = await LocalPlanRepository.open(
        path: '${directory.path}/studio.sqlite',
      );
      saved = (await repo.reminders.all()).single;
      expect(saved.intervalMinutes, 15);
      expect(saved.eligibleAt, now.add(const Duration(hours: 2, minutes: 15)));
      final updated = await repo.save(item..body = 'Updated note');
      expect((await repo.reminders.all()).single.active, isTrue);
      await repo.move(updated.id, updated.revision, WorkStatus.done);
      expect((await repo.reminders.all()).single.active, isFalse);
    },
  );

  test(
    'snooze does not shift recurring anchor; cancel ends all future repeats',
    () async {
      final item = await ticket('repeat');
      final r = await repo.reminders.add(
        item.id,
        item.revision,
        now,
        now: now,
        allowPast: true,
        intervalMinutes: 15,
      );
      await repo.reminders.act(
        r.id,
        0,
        'snooze-repeat',
        'snooze',
        now: now,
        minutes: 30,
      );
      var saved = (await repo.reminders.all()).single;
      expect(saved.scheduledAt, now);
      await repo.reminders.act(
        r.id,
        1,
        'ack-repeat',
        'ack',
        now: now.add(const Duration(minutes: 31)),
      );
      saved = (await repo.reminders.all()).single;
      expect(saved.eligibleAt, now.add(const Duration(minutes: 45)));
      await repo.reminders.act(r.id, 2, 'cancel-repeat', 'cancel');
      expect(
        await repo.reminders.due(now.add(const Duration(days: 2))),
        isEmpty,
      );
    },
  );

  test(
    'repeat validation and backup preserve interval but import stays paused',
    () async {
      final item = await ticket('repeat-backup');
      for (final interval in [0, -1, 525601]) {
        await expectLater(
          repo.reminders.add(
            item.id,
            item.revision,
            now,
            now: now,
            allowPast: true,
            intervalMinutes: interval,
          ),
          throwsArgumentError,
        );
      }
      await expectLater(
        repo.reminders.add(
          item.id,
          item.revision,
          now,
          now: now,
          allowPast: true,
          intervalMinutes: 15,
          offsetMinutes: 15,
        ),
        throwsArgumentError,
      );
      await repo.reminders.add(
        item.id,
        item.revision,
        now,
        now: now,
        allowPast: true,
        intervalMinutes: 60,
      );
      final target = await LocalPlanRepository.open(
        path: '${directory.path}/repeat-import.sqlite',
      );
      try {
        await target.importBackup(await repo.exportBackup());
        final saved = (await target.reminders.all()).single;
        expect(saved.intervalMinutes, 60);
        expect(saved.state, ReminderState.paused);
      } finally {
        await target.close();
      }
    },
  );
  test('schema v2 migration preserves existing one-time reminders', () async {
    final path = '${directory.path}/v2.sqlite';
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE projects (id TEXT PRIMARY KEY, path TEXT UNIQUE NOT NULL, name TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE tickets (id TEXT PRIMARY KEY, number INTEGER UNIQUE NOT NULL, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE metadata (key TEXT PRIMARY KEY, value INTEGER NOT NULL)',
          );
          await ReminderStore.migrate(db);
          await db.insert('projects', project.toJson());
          final item = WorkItem(
            id: 'v2',
            projectId: project.id,
            title: 'Existing',
            number: 1,
            revision: 1,
          );
          await db.insert('tickets', {
            'id': 'v2',
            'number': 1,
            'payload': jsonEncode(item.toJson()),
          });
          await db.insert('metadata', {'key': 'sequence', 'value': 1});
          final row = PlanReminder(
            id: 'old-reminder',
            itemId: 'v2',
            scheduledAt: now,
            eligibleAt: now,
          ).toJson()..remove('interval_minutes');
          await db.insert('reminders', row);
        },
      ),
    );
    await db.close();
    final upgraded = await LocalPlanRepository.open(path: path);
    try {
      final r = (await upgraded.reminders.all()).single;
      expect(r.intervalMinutes, isNull);
      expect(r.eligibleAt, now);
      expect(r.active, isTrue);
      await upgraded.reminders.add(
        'v2',
        1,
        now,
        now: now,
        allowPast: true,
        intervalMinutes: 5,
      );
      expect((await upgraded.reminders.all()).length, 2);
    } finally {
      await upgraded.close();
    }
  });
}
