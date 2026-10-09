import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/work_item.dart';
import '../repositories/local_plan_repository.dart';
import '../repositories/plan_repository.dart';
import '../services/deadline.dart';
import '../theme/studio_tokens.dart';
import 'studio_popover.dart';

class DuePick {
  const DuePick(this.at, {required this.allDay, this.offsets = const {}});
  const DuePick.clear() : at = null, allDay = true, offsets = const {};

  /// Local day (all-day) or local moment; null clears the deadline.
  final DateTime? at;
  final bool allDay;

  /// New "before due" reminders, in minutes before the reminder anchor.
  final Set<int> offsets;
}

Map<int, String> dueReminderOptions(bool allDay) => allDay
    ? const {0: 'Sáng ngày hạn (9:00)', 1440: 'Trước 1 ngày'}
    : const {
        0: 'Đúng hạn',
        15: 'Trước 15 phút',
        60: 'Trước 1 giờ',
        1440: 'Trước 1 ngày',
      };

Future<DuePick?> showDeadlinePicker(
  BuildContext context,
  WorkItem item, {
  Rect? anchor,
  bool reminders = false,
  Set<int> existingOffsets = const {},
  DateTime? now,
}) => showStudioPopover<DuePick>(
  context,
  anchor: anchor,
  width: 336,
  builder: (_) => DeadlinePicker(
    item: item,
    reminders: reminders,
    existingOffsets: existingOffsets,
    now: now,
  ),
);

/// Saves the deadline, then adds the requested reminders. Reminder failures
/// (past time, three-schedule limit) do not undo the deadline; they are
/// returned for the caller to show.
Future<List<String>> applyDuePick(
  PlanRepository repository,
  WorkItem item,
  DuePick pick,
) async {
  final next = item.clone();
  setDue(next, pick.at, allDay: pick.allDay);
  final saved = await repository.save(next);
  return addDueReminders(repository, saved, pick.offsets);
}

Future<List<String>> addDueReminders(
  PlanRepository repository,
  WorkItem saved,
  Set<int> offsets,
) async {
  final errors = <String>[];
  if (repository is! LocalPlanRepository || saved.dueAtUtc == null) {
    return errors;
  }
  for (final offset in offsets) {
    try {
      await repository.reminders.add(
        saved.id,
        saved.revision,
        DateTime.now(),
        offsetMinutes: offset,
      );
    } catch (e) {
      errors.add('${dueReminderOptions(saved.dueAllDay)[offset]}: $e');
    }
  }
  return errors;
}

class DeadlinePicker extends StatefulWidget {
  const DeadlinePicker({
    super.key,
    required this.item,
    this.reminders = false,
    this.existingOffsets = const {},
    this.now,
  });
  final WorkItem item;
  final bool reminders;
  final Set<int> existingOffsets;
  final DateTime? now;
  @override
  State<DeadlinePicker> createState() => _DeadlinePickerState();
}

class _DeadlinePickerState extends State<DeadlinePicker> {
  late final DateTime now = widget.now ?? DateTime.now();
  late DateTime? day = widget.item.dueAt?.toLocal();
  late bool withTime = widget.item.dueAt != null && !widget.item.dueAllDay;
  late int minutes = withTime ? day!.hour * 60 + day!.minute : 17 * 60;
  late DateTime month = DateTime((day ?? now).year, (day ?? now).month);
  final offsets = <int>{};

  DateTime? get _at => day == null
      ? null
      : withTime
      ? DateTime(day!.year, day!.month, day!.day, minutes ~/ 60, minutes % 60)
      : DateTime(day!.year, day!.month, day!.day);

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _choose(DateTime d) => setState(() {
    day = d;
    month = DateTime(d.year, d.month);
  });

  void _save() {
    final at = _at;
    if (at == null) return;
    Navigator.pop(context, DuePick(at, allDay: !withTime, offsets: offsets));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = StudioTokens.of(context);
    final at = _at;
    final past =
        at != null && (withTime ? at : endOfLocalDay(at)).isBefore(now);
    final options = dueReminderOptions(!withTime);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): _save},
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('Đặt hạn', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    at == null
                        ? 'Chưa chọn ngày'
                        : dueFullAt(at, allDay: !withTime),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFeatures: StudioTokens.tabular,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final preset in duePresets(now))
                    _Pill(
                      label: preset.label,
                      selected: day != null && _same(day!, preset.day),
                      tooltip: dueDate(preset.day),
                      onTap: () => _choose(preset.day),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _MonthGrid(
                month: month,
                selected: day,
                today: now,
                onPick: _choose,
                onMonth: (delta) => setState(
                  () => month = DateTime(month.year, month.month + delta),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(
                    height: 32,
                    child: FittedBox(
                      child: Switch(
                        value: withTime,
                        onChanged: (v) => setState(() {
                          withTime = v;
                          offsets.clear();
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('Có giờ'),
                  const Spacer(),
                  if (withTime)
                    DropdownButton<int>(
                      value: minutes,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      menuMaxHeight: 320,
                      items: [
                        for (final m in {
                          for (var n = 0; n < 48; n++) n * 30,
                          minutes,
                        }.toList()..sort())
                          DropdownMenuItem(
                            value: m,
                            child: Text(
                              '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontFeatures: StudioTokens.tabular,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => minutes = v!),
                    ),
                ],
              ),
              if (withTime)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final m in [9 * 60, 12 * 60, 17 * 60])
                      _Pill(
                        label: '${m ~/ 60}:00',
                        selected: minutes == m,
                        onTap: () => setState(() => minutes = m),
                      ),
                  ],
                ),
              if (past)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Hạn đã qua — ticket sẽ hiện là quá hạn.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.palette.danger,
                    ),
                  ),
                ),
              if (widget.reminders) ...[
                const Divider(height: 22),
                Text('Nhắc trước hạn', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in options.entries)
                      _Pill(
                        label: e.value,
                        icon: Icons.alarm,
                        selected:
                            offsets.contains(e.key) ||
                            widget.existingOffsets.contains(e.key),
                        tooltip: widget.existingOffsets.contains(e.key)
                            ? 'Đã đặt · tự dời theo hạn'
                            : null,
                        onTap: widget.existingOffsets.contains(e.key)
                            ? null
                            : () => setState(
                                () => offsets.contains(e.key)
                                    ? offsets.remove(e.key)
                                    : offsets.add(e.key),
                              ),
                      ),
                  ],
                ),
              ],
              const Divider(height: 22),
              Row(
                children: [
                  if (widget.item.dueAtUtc != null)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: tokens.palette.danger,
                      ),
                      onPressed: () =>
                          Navigator.pop(context, const DuePick.clear()),
                      child: const Text('Bỏ hạn'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: at == null ? null : _save,
                    child: const Text('Lưu hạn'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    this.onTap,
    this.icon,
    this.tooltip,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurface;
    final pill = Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.14)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StudioTokens.chipRadius),
        side: BorderSide(
          color: selected
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(StudioTokens.chipRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected || icon != null) ...[
                Icon(selected ? Icons.check : icon, size: 13, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.onPick,
    required this.onMonth,
  });
  final DateTime month;
  final DateTime? selected;
  final DateTime today;
  final ValueChanged<DateTime> onPick;
  final ValueChanged<int> onMonth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lead = month.weekday - 1;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((lead + count) / 7).ceil() * 7;
    final t = DateTime(today.year, today.month, today.day);
    bool same(DateTime a, DateTime? b) =>
        b != null && a.year == b.year && a.month == b.month && a.day == b.day;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Tháng trước',
              style: StudioTokens.of(context).quietIcon,
              onPressed: () => onMonth(-1),
              icon: const Icon(Icons.chevron_left, size: 20),
            ),
            Expanded(
              child: Text(
                'Tháng ${month.month}, ${month.year}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge,
              ),
            ),
            IconButton(
              tooltip: 'Tháng sau',
              style: StudioTokens.of(context).quietIcon,
              onPressed: () => onMonth(1),
              icon: const Icon(Icons.chevron_right, size: 20),
            ),
          ],
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.25,
          children: [
            for (final w in ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'])
              Center(
                child: Text(
                  w,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ),
            for (var n = 0; n < cells; n++)
              if (n < lead || n >= lead + count)
                const SizedBox.shrink()
              else
                Builder(
                  builder: (context) {
                    final d = DateTime(month.year, month.month, n - lead + 1);
                    final isSelected = same(d, selected);
                    final isToday = same(d, t);
                    return Padding(
                      padding: const EdgeInsets.all(1.5),
                      child: Material(
                        color: isSelected ? scheme.primary : Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: isToday && !isSelected
                              ? BorderSide(color: scheme.primary)
                              : BorderSide.none,
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => onPick(d),
                          child: Center(
                            child: Text(
                              '${d.day}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontFeatures: StudioTokens.tabular,
                                fontWeight: isToday || isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: isSelected
                                    ? scheme.onPrimary
                                    : d.isBefore(t)
                                    ? scheme.onSurfaceVariant.withValues(
                                        alpha: 0.6,
                                      )
                                    : scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
          ],
        ),
      ],
    );
  }
}
