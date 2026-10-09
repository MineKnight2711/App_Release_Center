import 'dart:async';
import 'package:flutter/material.dart';
import '../models/work_item.dart';
import '../models/plan_reminder.dart';
import '../repositories/local_plan_repository.dart';
import '../services/deadline.dart';
import '../services/plan_progress_service.dart';
import 'ticket_editor.dart';

class TodayView extends StatefulWidget {
  const TodayView({super.key, required this.repository, this.projectId});
  final LocalPlanRepository repository;
  final String? projectId;
  @override
  State<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<TodayView> {
  List<WorkItem> items = [];
  List<StudioProject> projects = [];
  List<PlanReminder> reminders = [];
  String? projectId, error;
  bool loading = true;
  StreamSubscription<void>? subscription;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    projectId = widget.projectId;
    subscription = widget.repository.changes.listen((_) => _load());
    timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.repository.items();
      final scheduled = await widget.repository.reminders.all();
      final registry = await widget.repository.projects();
      if (mounted) {
        setState(() {
          items = all;
          reminders = scheduled;
          projects = registry;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    bool today(DateTime d) {
      final l = d.toLocal();
      return l.year == now.year && l.month == now.month && l.day == now.day;
    }

    final scoped = items
        .where(
          (i) => !i.archived && (projectId == null || i.projectId == projectId),
        )
        .toList();
    final groups = <String, List<WorkItem>>{
      'Quá hạn': scoped
          .where(
            (i) =>
                i.status != WorkStatus.done &&
                i.dueAtUtc != null &&
                DateTime.parse(i.dueAtUtc!).isBefore(now),
          )
          .toList(),
      'Đến hạn hôm nay': scoped
          .where(
            (i) =>
                i.status != WorkStatus.done &&
                i.dueAtUtc != null &&
                today(DateTime.parse(i.dueAtUtc!)),
          )
          .toList(),
      'Nhắc hôm nay': scoped
          .where(
            (i) => reminders.any(
              (r) => r.itemId == i.id && r.active && today(r.eligibleAt),
            ),
          )
          .toList(),
      'Nhắc sắp tới': scoped
          .where(
            (i) => reminders.any(
              (r) =>
                  r.itemId == i.id &&
                  r.active &&
                  r.eligibleAt.isAfter(now) &&
                  !today(r.eligibleAt),
            ),
          )
          .toList(),
      'Bị chặn': scoped.where((i) => i.status == WorkStatus.blocked).toList(),
      'Đã hoàn tất hôm nay': scoped
          .where(
            (i) =>
                i.status == WorkStatus.done &&
                i.completedAt != null &&
                today(DateTime.parse(i.completedAt!)),
          )
          .toList(),
    };
    final count = groups.values
        .expand((v) => v)
        .map((i) => i.id)
        .toSet()
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan Studio · Hôm nay'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: projectId ?? '',
                  decoration: const InputDecoration(labelText: 'Dự án'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Tất cả dự án'),
                    ),
                    for (final p in projects)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (id) =>
                      setState(() => projectId = id == '' ? null : id),
                ),
                const SizedBox(height: 16),
                Text('$count công việc · ${studioDate(now)}'),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                for (final entry in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 24, bottom: 8),
                    child: Text(
                      '${entry.key} · ${entry.value.length}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (entry.value.isEmpty) const Text('Không có công việc.'),
                  ..._sorted(entry.value).map((item) {
                    final p = PlanProgress(item, items);
                    final next = reminders
                        .where((r) => r.itemId == item.id && r.active)
                        .firstOrNull;
                    return Card(
                      child: ListTile(
                        isThreeLine: true,
                        title: Text('${item.code} · ${item.title}'),
                        subtitle: Text(
                          '${item.priority} · ${item.status.label} · ${p.label}\n${next == null
                              ? item.dueAtUtc == null
                                    ? 'Chưa đặt lịch'
                                    : 'Hạn ${dueFull(item)}'
                              : '${next.state == ReminderState.snoozed ? 'Nhắc lại' : 'Nhắc'} ${studioDate(next.eligibleAt)} · ${next.repeatLabel}'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await showTicketEditor(
                            context,
                            widget.repository,
                            item,
                          );
                          await _load();
                        },
                      ),
                    );
                  }),
                ],
              ],
            ),
    );
  }

  List<WorkItem> _sorted(List<WorkItem> values) => values
    ..sort((a, b) {
      final date = (a.dueAtUtc ?? '9999').compareTo(b.dueAtUtc ?? '9999');
      return date == 0 ? a.priority.compareTo(b.priority) : date;
    });
}
