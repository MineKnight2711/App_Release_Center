enum ReminderState {
  pending,
  presented,
  snoozed,
  acknowledged,
  cancelled,
  paused,
}

/// A durable schedule. Recurrence advances the date and revision; snoozing
/// keeps its cadence anchor and ID.
class PlanReminder {
  const PlanReminder({
    required this.id,
    required this.itemId,
    required this.scheduledAt,
    required this.eligibleAt,
    this.offsetMinutes,
    this.intervalMinutes,
    this.state = ReminderState.pending,
    this.revision = 0,
  });
  final String id, itemId;
  final DateTime scheduledAt, eligibleAt;
  final int? offsetMinutes;
  final int? intervalMinutes;
  String get repeatLabel => intervalMinutes == null
      ? 'Một lần'
      : 'Lặp mỗi ${reminderDuration(intervalMinutes!)}';
  final ReminderState state;
  final int revision;
  bool get active => [
    ReminderState.pending,
    ReminderState.presented,
    ReminderState.snoozed,
  ].contains(state);
  Map<String, Object?> toJson() => {
    'id': id,
    'item_id': itemId,
    'scheduled_at': scheduledAt.toUtc().toIso8601String(),
    'eligible_at': eligibleAt.toUtc().toIso8601String(),
    'offset_minutes': offsetMinutes,
    'interval_minutes': intervalMinutes,
    'state': state.name,
    'revision': revision,
  };
  factory PlanReminder.fromJson(Map<String, dynamic> j) {
    final r = PlanReminder(
      id: j['id'] as String,
      itemId: j['item_id'] as String,
      scheduledAt: DateTime.parse(j['scheduled_at'] as String).toUtc(),
      eligibleAt: DateTime.parse(j['eligible_at'] as String).toUtc(),
      offsetMinutes: j['offset_minutes'] as int?,
      intervalMinutes: j['interval_minutes'] as int?,
      state: ReminderState.values.byName(j['state'] as String),
      revision: j['revision'] as int,
    );
    if (r.id.isEmpty ||
        r.itemId.isEmpty ||
        r.revision < 0 ||
        (r.offsetMinutes != null && r.offsetMinutes! < 0) ||
        (r.intervalMinutes != null &&
            (r.intervalMinutes! < 1 ||
                r.intervalMinutes! > 525600 ||
                r.offsetMinutes != null))) {
      throw const FormatException('Lịch nhắc không hợp lệ.');
    }
    return r;
  }
}

String studioDate(DateTime date) {
  final d = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

String reminderDuration(int minutes) => minutes % 1440 == 0
    ? '${minutes ~/ 1440} ngày (mỗi ngày 24 giờ)'
    : minutes % 60 == 0
    ? '${minutes ~/ 60} giờ'
    : '$minutes phút';

String reminderCountdown(DateTime at, DateTime now) {
  final minutes = at.difference(now).inMinutes;
  if (!at.isAfter(now)) return 'Đến giờ nhắc';
  if (minutes < 1) return 'Còn dưới 1 phút';
  if (minutes < 60) return 'Còn $minutes phút';
  if (minutes < 1440) return 'Còn ${minutes ~/ 60} giờ ${minutes % 60} phút';
  return 'Còn ${minutes ~/ 1440} ngày ${minutes % 1440 ~/ 60} giờ';
}
