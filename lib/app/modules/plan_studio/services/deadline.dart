import '../models/work_item.dart';

/// How a deadline reads right now. Ordered from most to least urgent for the
/// open states; the two done states come last.
enum DueState {
  overdue,
  today,
  soon,
  thisWeek,
  later,
  none,
  doneOnTime,
  doneLate,
}

enum DueFilter {
  overdue('Quá hạn'),
  today('Hôm nay'),
  week('7 ngày tới'),
  none('Không có hạn');

  const DueFilter(this.label);
  final String label;
}

const _weekdays = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'CN'];
String _two(int n) => n.toString().padLeft(2, '0');
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendar-day distance in local time, so 23:00 → 01:00 counts as one day.
int _days(DateTime from, DateTime to) =>
    (_day(to.toLocal()).difference(_day(from.toLocal())).inHours / 24).round();

/// An all-day deadline is due at the last second of that local day.
DateTime endOfLocalDay(DateTime day) {
  final l = day.toLocal();
  return DateTime(l.year, l.month, l.day, 23, 59, 59);
}

/// Where "before due" reminders count back from. An all-day deadline has no
/// meaningful clock time, so the reminder lands in the morning of that day.
DateTime? reminderAnchor(WorkItem item) {
  final due = item.dueAt;
  if (due == null) return null;
  if (!item.dueAllDay) return due;
  final l = due.toLocal();
  return DateTime(l.year, l.month, l.day, 9).toUtc();
}

/// Sets or clears the deadline. [at] is local; [allDay] drops its clock time.
void setDue(WorkItem item, DateTime? at, {bool allDay = true}) {
  if (at == null) {
    item.dueAtUtc = null;
    item.dueAllDay = false;
    return;
  }
  item.dueAllDay = allDay;
  item.dueAtUtc = (allDay ? endOfLocalDay(at) : at).toUtc().toIso8601String();
}

DueState dueState(WorkItem item, DateTime now) {
  final due = item.dueAt;
  if (due == null) return DueState.none;
  if (item.status == WorkStatus.done) {
    final done = DateTime.tryParse(item.completedAt ?? '') ?? now;
    return done.isAfter(due) ? DueState.doneLate : DueState.doneOnTime;
  }
  if (due.isBefore(now)) return DueState.overdue;
  final days = _days(now, due);
  if (days == 0) return DueState.today;
  if (days == 1) return DueState.soon;
  if (days <= 6) return DueState.thisWeek;
  return DueState.later;
}

bool matchesDueFilter(WorkItem item, DueFilter filter, DateTime now) {
  final state = dueState(item, now);
  return switch (filter) {
    DueFilter.overdue => state == DueState.overdue,
    DueFilter.today => state == DueState.today,
    DueFilter.week => [
      DueState.today,
      DueState.soon,
      DueState.thisWeek,
    ].contains(state),
    DueFilter.none => state == DueState.none,
  };
}

/// A missed all-day deadline is late by whole days; a timed one by the
/// smallest unit that reads naturally.
String _late(DateTime due, DateTime at, bool allDay) {
  final minutes = at.difference(due).inMinutes;
  if (allDay || minutes >= 1440) {
    final days = _days(due, at);
    return '${days < 1 ? 1 : days} ngày';
  }
  if (minutes >= 60) return '${minutes ~/ 60} giờ';
  return '${minutes < 1 ? 1 : minutes} phút';
}

/// Short relative label for chips: "Hôm nay 17:00", "Mai", "Thứ 6", "Trễ 2 ngày".
String dueLabel(WorkItem item, DateTime now) {
  final due = item.dueAt;
  if (due == null) return '';
  final l = due.toLocal();
  final time = item.dueAllDay ? '' : ' ${_two(l.hour)}:${_two(l.minute)}';
  return switch (dueState(item, now)) {
    DueState.none => '',
    DueState.overdue => 'Trễ ${_late(due, now, item.dueAllDay)}',
    DueState.today => 'Hôm nay$time',
    DueState.soon => 'Mai$time',
    DueState.thisWeek => '${_weekdays[l.weekday - 1]}$time',
    DueState.later =>
      '${_two(l.day)}/${_two(l.month)}'
          '${l.year == now.toLocal().year ? '' : '/${l.year}'}$time',
    DueState.doneOnTime => 'Đúng hạn',
    DueState.doneLate =>
      'Xong trễ ${_late(due, DateTime.parse(item.completedAt!), item.dueAllDay)}',
  };
}

/// Full date for tooltips and the properties rail: "Thứ 6, 03/10/2026 · 17:00".
String dueFull(WorkItem item) {
  final due = item.dueAt;
  return due == null ? 'Chưa có hạn' : dueFullAt(due, allDay: item.dueAllDay);
}

String dueFullAt(DateTime at, {required bool allDay}) {
  final l = at.toLocal();
  return '${_weekdays[l.weekday - 1]}, ${_two(l.day)}/${_two(l.month)}/${l.year}'
      '${allDay ? '' : ' · ${_two(l.hour)}:${_two(l.minute)}'}';
}

String dueDate(DateTime day) {
  final l = day.toLocal();
  return '${_weekdays[l.weekday - 1]} ${_two(l.day)}/${_two(l.month)}';
}

class DuePreset {
  const DuePreset(this.label, this.day);
  final String label;
  final DateTime day;
}

/// Quick picks, each a local calendar day. "Thứ 6" is this week's Friday, or
/// next week's once Friday has passed.
List<DuePreset> duePresets(DateTime now) {
  final today = _day(now.toLocal());
  DateTime plus(int n) => DateTime(today.year, today.month, today.day + n);
  final toFriday = (DateTime.friday - today.weekday) % 7;
  final toMonday = (DateTime.monday - today.weekday) % 7;
  return [
    DuePreset('Hôm nay', today),
    DuePreset('Ngày mai', plus(1)),
    DuePreset(toFriday == 0 ? 'Thứ 6 (hôm nay)' : 'Thứ 6', plus(toFriday)),
    DuePreset('Tuần sau', plus(toMonday == 0 ? 7 : toMonday)),
    DuePreset('+1 tuần', plus(7)),
  ];
}

/// Earliest open deadline among a plan's children, for plans without their own.
WorkItem? nearestChildDue(WorkItem plan, List<WorkItem> all) {
  final open =
      all
          .where(
            (i) =>
                i.parentId == plan.id &&
                !i.archived &&
                i.status != WorkStatus.done &&
                i.dueAtUtc != null,
          )
          .toList()
        ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  return open.firstOrNull;
}

int overdueChildren(WorkItem plan, List<WorkItem> all, DateTime now) => all
    .where(
      (i) =>
          i.parentId == plan.id &&
          !i.archived &&
          dueState(i, now) == DueState.overdue,
    )
    .length;

/// Activity text for a deadline edit, or null when nothing changed.
String? dueChange(WorkItem before, WorkItem after) {
  if (before.dueAtUtc == after.dueAtUtc &&
      before.dueAllDay == after.dueAllDay) {
    return null;
  }
  if (after.dueAtUtc == null) return 'Bỏ hạn';
  if (before.dueAtUtc == null) return 'Đặt hạn ${dueFull(after)}';
  return 'Dời hạn ${dueFull(before)} → ${dueFull(after)}';
}
