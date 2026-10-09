import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/plan_reminder.dart';
import '../models/work_item.dart';
import '../repositories/local_plan_repository.dart';
import 'plan_progress_service.dart';
import 'deadline.dart';

/// The main isolate owns this scheduler. No scheduling work runs in a view or
/// secondary Flutter engine. A presented reminder remains pending user action
/// across restarts, which intentionally provides at-least-once presentation.
class ReminderScheduler extends ChangeNotifier {
  ReminderScheduler(
    this.repository, {
    required this.publish,
    DateTime Function()? clock,
    bool Function(DateTime)? suppressed,
  }) : clock = clock ?? DateTime.now,
       suppressed = suppressed ?? ((_) => false);
  final LocalPlanRepository repository;
  final Future<void> Function(Map<String, dynamic>?) publish;
  final DateTime Function() clock;
  final bool Function(DateTime) suppressed;
  String? error;
  bool _running = false, _again = false, _closed = false;
  bool _forceAgain = false;
  String? _last;
  Timer? _timer, _watchdog;
  StreamSubscription<void>? _subscription;
  Map<String, dynamic>? snapshot;

  void start() {
    if (_subscription != null || _closed) return;
    _subscription = repository.changes.listen((_) => unawaited(scan()));
    _watchdog = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(scan(force: true)),
    );
    unawaited(scan());
  }

  Future<void> scan({bool force = false}) async {
    if (_closed) return;
    if (force) _forceAgain = true;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        if (_forceAgain) {
          _last = null;
          _forceAgain = false;
        }
        _timer?.cancel();
        final now = clock().toUtc();
        final active = await repository.reminders.due(now);
        final next = await repository.reminders.nextAfter(now);
        if (next != null && !_closed) {
          var delay = next.difference(now);
          if (delay < const Duration(milliseconds: 100)) {
            delay = const Duration(milliseconds: 100);
          }
          _timer = Timer(delay, () => unawaited(scan()));
        }
        final items = active.isEmpty ? <WorkItem>[] : await repository.items();
        final projects = active.isEmpty
            ? <StudioProject>[]
            : await repository.projects();
        final grouped = <String, List<PlanReminder>>{};
        for (final r in active.where((r) => !r.eligibleAt.isAfter(now))) {
          final item = items.where((i) => i.id == r.itemId).firstOrNull;
          if (item == null || item.archived || item.status == WorkStatus.done) {
            continue;
          }
          grouped.putIfAbsent(r.itemId, () => []).add(r);
        }
        final cards = <Map<String, dynamic>>[];
        for (final entry in grouped.entries) {
          final item = items.firstWhere((i) => i.id == entry.key);
          final progress = PlanProgress(item, items);
          cards.add({
            'itemId': item.id,
            'revision': item.revision,
            'code': item.code,
            'title': item.title,
            'project':
                projects
                    .where((p) => p.id == item.projectId)
                    .firstOrNull
                    ?.name ??
                '',
            'status': item.status.label,
            'statusName': item.status.name,
            'priority': item.priority,
            'dueAt': item.dueAtUtc,
            'dueLabel': item.dueAtUtc == null ? null : dueFull(item),
            'scheduledAt': entry.value.first.scheduledAt.toIso8601String(),
            'progress': progress.fraction,
            'progressLabel': progress.label,
            'blocked': progress.blocked,
            'next': progress.next,
            'repeatLabel': entry.value
                .where((r) => r.intervalMinutes != null)
                .map((r) => r.repeatLabel)
                .join(' · '),
            'blockedReason': item.blockedReason,
            'note': item.notes.lastOrNull?['body'],
            'reminders': entry.value
                .map((r) => {'id': r.id, 'revision': r.revision})
                .toList(),
          });
        }
        snapshot = cards.isEmpty || suppressed(now.toLocal())
            ? null
            : {'cards': cards};
        final encoded = jsonEncode(snapshot);
        if (_last != encoded && !_closed) {
          await publish(snapshot);
          _last = encoded;
        }
        error = null;
      } while (_again && !_closed);
    } catch (e) {
      error = 'Bộ nhắc hẹn: $e';
      _last = null;
    } finally {
      _running = false;
      if (!_closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    _watchdog?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
