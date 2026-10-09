import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../models/plan_reminder.dart';
import '../models/work_item.dart';
import '../services/deadline.dart';

class ReminderStore {
  ReminderStore(this.db, this.changed);
  final Database db;
  final void Function() changed;

  Future<List<PlanReminder>> due(DateTime now) async => (await db.query(
    'reminders',
    where: "state IN ('pending','presented','snoozed') AND eligible_at <= ?",
    whereArgs: [now.toUtc().toIso8601String()],
    orderBy: 'eligible_at, id',
  )).map(PlanReminder.fromJson).toList();

  Future<DateTime?> nextAfter(DateTime now) async {
    final rows = await db.query(
      'reminders',
      columns: ['eligible_at'],
      where: "state IN ('pending','presented','snoozed') AND eligible_at > ?",
      whereArgs: [now.toUtc().toIso8601String()],
      orderBy: 'eligible_at',
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : DateTime.parse(rows.single['eligible_at'] as String);
  }

  static Future<void> migrate(DatabaseExecutor tx) async {
    await tx.execute(
      'CREATE TABLE reminders (id TEXT PRIMARY KEY, '
      'item_id TEXT NOT NULL, scheduled_at TEXT NOT NULL, eligible_at TEXT NOT NULL, '
      'offset_minutes INTEGER, state TEXT NOT NULL, revision INTEGER NOT NULL)',
    );
    await tx.execute(
      'CREATE INDEX reminders_due ON reminders(state, eligible_at)',
    );
    await tx.execute('CREATE INDEX reminders_item ON reminders(item_id)');
    await tx.execute(
      'CREATE TABLE reminder_commands (id TEXT PRIMARY KEY, at TEXT NOT NULL)',
    );
  }

  Future<List<PlanReminder>> all({String? itemId}) async => (await db.query(
    'reminders',
    where: itemId == null ? null : 'item_id = ?',
    whereArgs: itemId == null ? null : [itemId],
    orderBy: 'eligible_at',
  )).map(PlanReminder.fromJson).toList();

  Future<PlanReminder> add(
    String itemId,
    int itemRevision,
    DateTime at, {
    int? offsetMinutes,
    int? intervalMinutes,
    bool allowPast = false,
    DateTime? now,
  }) async {
    if (intervalMinutes != null &&
        (intervalMinutes < 1 ||
            intervalMinutes > 525600 ||
            offsetMinutes != null)) {
      throw ArgumentError(
        'Chu kỳ phải từ 1 phút đến 365 ngày và không kết hợp nhắc trước hạn.',
      );
    }
    final result = await db.transaction((tx) async {
      final rows = await tx.query(
        'tickets',
        where: 'id = ?',
        whereArgs: [itemId],
      );
      if (rows.isEmpty) throw StateError('Ticket không tồn tại.');
      final item = WorkItem.fromJson(
        jsonDecode(rows.single['payload'] as String),
      );
      if (item.revision != itemRevision) {
        throw StateError('Ticket đã thay đổi. Mở lại trước khi đặt lịch.');
      }
      if (item.archived || item.status == WorkStatus.done) {
        throw StateError('Khôi phục hoặc mở lại công việc trước khi đặt lịch.');
      }
      if (offsetMinutes != null) {
        if (offsetMinutes < 0 || item.dueAtUtc == null) {
          throw StateError('Chọn hạn hoàn thành trước.');
        }
        at = reminderAnchor(item)!.subtract(Duration(minutes: offsetMinutes));
      }
      if (!allowPast && !at.isAfter(now ?? DateTime.now())) {
        throw StateError('Giờ nhắc đã qua. Chọn giờ khác hoặc Nhắc ngay.');
      }
      final active = await tx.query(
        'reminders',
        where: "item_id = ? AND state IN ('pending','presented','snoozed')",
        whereArgs: [itemId],
      );
      if (active.length >= 3) {
        throw StateError('Tối đa 3 lịch nhắc đang hoạt động cho mỗi ticket.');
      }
      final reminder = PlanReminder(
        id: const Uuid().v4(),
        itemId: itemId,
        scheduledAt: at.toUtc(),
        eligibleAt: at.toUtc(),
        offsetMinutes: offsetMinutes,
        intervalMinutes: intervalMinutes,
      );
      await tx.insert('reminders', reminder.toJson());
      return reminder;
    });
    changed();
    return result;
  }

  /// State transition and command receipt are committed together. Retrying the
  /// same command after an uncertain bridge response cannot extend a snooze.
  Future<void> act(
    String id,
    int revision,
    String commandId,
    String action, {
    DateTime? now,
    int minutes = 10,
  }) async {
    await db.transaction((tx) async {
      if ((await tx.query(
        'reminder_commands',
        where: 'id = ?',
        whereArgs: [commandId],
      )).isNotEmpty) {
        return;
      }
      final rows = await tx.query(
        'reminders',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('Lịch nhắc không còn tồn tại.');
      final r = PlanReminder.fromJson(rows.single);
      if (r.revision != revision || !r.active) {
        throw StateError(
          'Lịch nhắc đã thay đổi. Vui lòng thử lại với dữ liệu mới.',
        );
      }
      final time = (now ?? DateTime.now()).toUtc();
      final next = switch (action) {
        'ack' => ReminderState.acknowledged,
        'cancel' => ReminderState.cancelled,
        'snooze' => ReminderState.snoozed,
        _ => throw ArgumentError('Thao tác không được hỗ trợ'),
      };
      if (action == 'snooze' && ![10, 30, 60].contains(minutes)) {
        throw ArgumentError('Thời gian nhắc lại không hợp lệ.');
      }
      await tx.update(
        'reminders',
        transition(r, next, time, minutes: minutes),
        where: 'id = ?',
        whereArgs: [id],
      );
      await tx.insert('reminder_commands', {
        'id': commandId,
        'at': time.toIso8601String(),
      });
    });
    changed();
  }

  // The same row represents the recurring schedule; advancing its revision
  // invalidates old popup actions. Missed intervals are skipped, not replayed.
  static Map<String, Object?> transition(
    PlanReminder r,
    ReminderState state,
    DateTime now, {
    int minutes = 10,
  }) {
    if (state == ReminderState.acknowledged && r.intervalMinutes != null) {
      final period = Duration(minutes: r.intervalMinutes!).inMicroseconds;
      final elapsed = now.toUtc().difference(r.scheduledAt).inMicroseconds;
      final steps = elapsed < 0 ? 0 : elapsed ~/ period + 1;
      final next = r.scheduledAt.add(Duration(microseconds: period * steps));
      return {
        'state': 'pending',
        'revision': r.revision + 1,
        'scheduled_at': next.toIso8601String(),
        'eligible_at': next.toIso8601String(),
      };
    }
    return {
      'state': state.name,
      'revision': r.revision + 1,
      if (state == ReminderState.snoozed)
        'eligible_at': now
            .toUtc()
            .add(Duration(minutes: minutes))
            .toIso8601String(),
    };
  }

  Future<void> presented(List<String> ids) async {
    await db.transaction((tx) async {
      for (final id in ids) {
        await tx.rawUpdate(
          "UPDATE reminders SET state = 'presented' WHERE id = ? AND state IN ('pending','snoozed')",
          [id],
        );
      }
    });
  }

  /// Runs inside the ticket write transaction, so no stale reminder can survive
  /// completion/archive or a deadline edit.
  static Future<void> reconcile(
    DatabaseExecutor tx,
    WorkItem item,
    WorkItem? old,
  ) async {
    if (item.archived || item.status == WorkStatus.done) {
      await cancelFor(tx, item.id);
    } else if (old != null && reminderAnchor(old) != reminderAnchor(item)) {
      final rows = await tx.query(
        'reminders',
        where:
            "item_id = ? AND offset_minutes IS NOT NULL AND state IN ('pending','presented','snoozed')",
        whereArgs: [item.id],
      );
      for (final row in rows) {
        final r = PlanReminder.fromJson(row);
        await tx.update(
          'reminders',
          {'state': 'cancelled', 'revision': r.revision + 1},
          where: 'id = ?',
          whereArgs: [r.id],
        );
        if (reminderAnchor(item) case final anchor?) {
          final at = anchor.subtract(Duration(minutes: r.offsetMinutes!));
          await tx.insert(
            'reminders',
            PlanReminder(
              id: const Uuid().v4(),
              itemId: item.id,
              scheduledAt: at,
              eligibleAt: at,
              offsetMinutes: r.offsetMinutes,
            ).toJson(),
          );
        }
      }
    }
  }

  static Future<void> cancelFor(DatabaseExecutor tx, String itemId) => tx
      .rawUpdate(
        "UPDATE reminders SET state = 'cancelled', revision = revision + 1 WHERE item_id = ? AND state IN ('pending','presented','snoozed','paused')",
        [itemId],
      )
      .then((_) {});
}
