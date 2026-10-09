import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_management_center/app/modules/plan_studio/models/work_item.dart';
import 'package:app_management_center/app/modules/plan_studio/repositories/local_plan_repository.dart';
import 'package:app_management_center/app/modules/plan_studio/services/deadline.dart';

void main() {
  // Tuesday 29/09/2026 10:00 local.
  final now = DateTime(2026, 9, 29, 10);
  WorkItem item({
    DateTime? due,
    bool allDay = false,
    WorkStatus status = WorkStatus.inProgress,
    DateTime? completed,
  }) {
    final i = WorkItem(
      id: 'i',
      projectId: 'p',
      title: 't',
      status: status,
      completedAt: completed?.toUtc().toIso8601String(),
    );
    if (due != null) setDue(i, due, allDay: allDay);
    return i;
  }

  group('dueState and dueLabel', () {
    test('no deadline', () {
      expect(dueState(item(), now), DueState.none);
      expect(dueLabel(item(), now), '');
      expect(dueFull(item()), 'Chưa có hạn');
    });

    test('all-day deadline stays due through the end of its day', () {
      final today = item(due: now, allDay: true);
      expect(dueState(today, now), DueState.today);
      expect(dueLabel(today, now), 'Hôm nay');
      expect(
        dueState(today, DateTime(2026, 9, 29, 23, 59, 58)),
        DueState.today,
      );
      final after = DateTime(2026, 9, 30, 0, 30);
      expect(dueState(today, after), DueState.overdue);
      expect(dueLabel(today, after), 'Trễ 1 ngày');
      expect(dueLabel(today, DateTime(2026, 10, 2, 8)), 'Trễ 3 ngày');
    });

    test('timed deadline: today, overdue minutes/hours/days', () {
      final at = item(due: DateTime(2026, 9, 29, 17));
      expect(dueLabel(at, now), 'Hôm nay 17:00');
      expect(dueLabel(at, DateTime(2026, 9, 29, 17, 20)), 'Trễ 20 phút');
      expect(dueLabel(at, DateTime(2026, 9, 29, 20)), 'Trễ 3 giờ');
      // 23:00 → 01:00 crosses midnight but is only two hours late.
      final late = item(due: DateTime(2026, 9, 29, 23));
      expect(dueLabel(late, DateTime(2026, 9, 30, 1)), 'Trễ 2 giờ');
      expect(dueLabel(at, DateTime(2026, 10, 1, 9)), 'Trễ 2 ngày');
    });

    test('tomorrow, this week and later', () {
      expect(
        dueLabel(item(due: DateTime(2026, 9, 30), allDay: true), now),
        'Mai',
      );
      final soon = item(due: DateTime(2026, 9, 30, 9, 5));
      expect(dueState(soon, now), DueState.soon);
      expect(dueLabel(soon, now), 'Mai 09:05');
      final friday = item(due: DateTime(2026, 10, 2), allDay: true);
      expect(dueState(friday, now), DueState.thisWeek);
      expect(dueLabel(friday, now), 'Thứ 6');
      final monday = item(due: DateTime(2026, 10, 5), allDay: true);
      expect(dueState(monday, now), DueState.thisWeek);
      expect(dueLabel(monday, now), 'Thứ 2');
      final later = item(due: DateTime(2026, 10, 6), allDay: true);
      expect(dueState(later, now), DueState.later);
      expect(dueLabel(later, now), '06/10');
      expect(
        dueLabel(item(due: DateTime(2027, 1, 4, 8), allDay: false), now),
        '04/01/2027 08:00',
      );
      expect(dueFull(friday), 'Thứ 6, 02/10/2026');
      expect(
        dueFull(item(due: DateTime(2026, 10, 2, 17))),
        'Thứ 6, 02/10/2026 · 17:00',
      );
    });

    test('done compares completion against the deadline', () {
      final due = DateTime(2026, 9, 28);
      final onTime = item(
        due: due,
        allDay: true,
        status: WorkStatus.done,
        completed: DateTime(2026, 9, 28, 22),
      );
      expect(dueState(onTime, now), DueState.doneOnTime);
      expect(dueLabel(onTime, now), 'Đúng hạn');
      final late = item(
        due: due,
        allDay: true,
        status: WorkStatus.done,
        completed: DateTime(2026, 9, 30, 8),
      );
      expect(dueState(late, now), DueState.doneLate);
      expect(dueLabel(late, now), 'Xong trễ 2 ngày');
    });
  });

  test('filters', () {
    final overdue = item(due: DateTime(2026, 9, 28), allDay: true);
    final today = item(due: now, allDay: true);
    final week = item(due: DateTime(2026, 10, 3), allDay: true);
    final none = item();
    expect(matchesDueFilter(overdue, DueFilter.overdue, now), isTrue);
    expect(matchesDueFilter(today, DueFilter.today, now), isTrue);
    expect(matchesDueFilter(today, DueFilter.week, now), isTrue);
    expect(matchesDueFilter(week, DueFilter.week, now), isTrue);
    expect(matchesDueFilter(overdue, DueFilter.week, now), isFalse);
    expect(matchesDueFilter(none, DueFilter.none, now), isTrue);
    expect(matchesDueFilter(week, DueFilter.none, now), isFalse);
  });

  test('presets from a Tuesday and from a Friday', () {
    expect(duePresets(now).map((p) => p.day.day), [29, 30, 2, 5, 6]);
    final friday = duePresets(DateTime(2026, 10, 2, 18));
    expect(friday[2].label, 'Thứ 6 (hôm nay)');
    expect(friday.map((p) => p.day.day), [2, 3, 2, 5, 9]);
    // Monday: "Tuần sau" is next Monday, not today.
    expect(duePresets(DateTime(2026, 10, 5))[3].day, DateTime(2026, 10, 12));
  });

  test('all-day reminders anchor at 9:00; timed ones at the deadline', () {
    final allDay = item(due: DateTime(2026, 10, 2), allDay: true);
    expect(reminderAnchor(allDay)!.toLocal(), DateTime(2026, 10, 2, 9));
    final timed = item(due: DateTime(2026, 10, 2, 17));
    expect(reminderAnchor(timed)!.toLocal(), DateTime(2026, 10, 2, 17));
    expect(reminderAnchor(item()), isNull);
  });

  test('plan rollup: nearest open child deadline and overdue count', () {
    final plan = WorkItem(
      id: 'plan',
      projectId: 'p',
      title: 'Plan',
      type: WorkType.plan,
    );
    WorkItem child(String id, DateTime due, {WorkStatus s = WorkStatus.ready}) {
      final c = item(due: due, allDay: true, status: s);
      return WorkItem.fromJson({...c.toJson(), 'id': id, 'parentId': 'plan'});
    }

    final all = [
      plan,
      child('a', DateTime(2026, 10, 5)),
      child('b', DateTime(2026, 9, 27)),
      child('c', DateTime(2026, 9, 20), s: WorkStatus.done),
    ];
    expect(nearestChildDue(plan, all)!.id, 'b');
    expect(overdueChildren(plan, all, now), 1);
  });

  test('old payloads without the new fields still load', () {
    final json = item(due: now, allDay: true).toJson()
      ..remove('dueAllDay')
      ..remove('dueHistory');
    final loaded = WorkItem.fromJson(jsonDecode(jsonEncode(json)));
    expect(loaded.dueAllDay, isFalse);
    expect(loaded.dueHistory, isEmpty);
    expect(
      () => WorkItem.fromJson({
        ...item().toJson(),
        'dueHistory': [
          {'at': 5},
        ],
      }),
      throwsFormatException,
    );
  });

  group('repository', () {
    late Directory directory;
    late LocalPlanRepository repo;
    late StudioProject project;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('plan-deadline-test-');
      repo = await LocalPlanRepository.open(
        path: '${directory.path}/studio.sqlite',
      );
      project = await repo.ensureProject('${directory.path}/project');
    });
    tearDown(() async {
      await repo.close();
      await directory.delete(recursive: true);
    });

    test(
      'set, move and clear deadline are logged; only moves are history',
      () async {
        var t = await repo.save(
          WorkItem(id: 'a', projectId: project.id, title: 'A'),
        );
        setDue(t, DateTime(2026, 10, 2));
        t = await repo.save(t);
        expect(t.activity.last['text'], 'Đặt hạn Thứ 6, 02/10/2026');
        expect(t.dueHistory, isEmpty);

        setDue(t, DateTime(2026, 10, 5, 17), allDay: false);
        t = await repo.save(t);
        expect(
          t.activity.last['text'],
          'Dời hạn Thứ 6, 02/10/2026 → Thứ 2, 05/10/2026 · 17:00',
        );
        expect(t.dueHistory, hasLength(1));
        expect(t.dueHistory.single['to'], t.dueAtUtc);

        setDue(t, null);
        t = await repo.save(t);
        expect(t.activity.last['text'], 'Bỏ hạn');
        expect(t.dueHistory, hasLength(1));
      },
    );

    test(
      'before-due reminder on an all-day deadline fires that morning',
      () async {
        final future = DateTime.now().add(const Duration(days: 3));
        var t = WorkItem(id: 'a', projectId: project.id, title: 'A');
        setDue(t, future);
        t = await repo.save(t);
        final r = await repo.reminders.add(
          t.id,
          t.revision,
          DateTime.now(),
          offsetMinutes: 0,
        );
        expect(
          r.scheduledAt.toLocal(),
          DateTime(future.year, future.month, future.day, 9),
        );
        // Switching the same day to a timed deadline moves the relative reminder.
        setDue(
          t,
          DateTime(future.year, future.month, future.day, 15),
          allDay: false,
        );
        await repo.save(t);
        final active = (await repo.reminders.all()).where((r) => r.active);
        expect(
          active.single.scheduledAt.toLocal(),
          DateTime(future.year, future.month, future.day, 15),
        );
      },
    );
  });
}
