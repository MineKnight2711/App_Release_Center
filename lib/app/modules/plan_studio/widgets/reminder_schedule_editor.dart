import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../controllers/plan_editor_controller.dart';
import '../models/plan_reminder.dart';
import '../models/work_item.dart';
import '../repositories/local_plan_repository.dart';
import '../services/plan_studio_runtime.dart';
import 'deadline_picker.dart';
import 'due_field.dart';

enum ScheduleMode { at, after, repeat }

class ReminderScheduleEditor extends StatefulWidget {
  const ReminderScheduleEditor({
    super.key,
    required this.editor,
    required this.repository,
    required this.disabled,
  });
  final PlanEditorController editor;
  final LocalPlanRepository repository;
  final bool disabled;
  @override
  State<ReminderScheduleEditor> createState() => _ReminderScheduleEditorState();
}

class _ReminderScheduleEditorState extends State<ReminderScheduleEditor> {
  List<PlanReminder> reminders = [];
  StreamSubscription<void>? subscription;
  Timer? ticker;
  bool busy = false;
  String? error, success;
  ScheduleMode mode = ScheduleMode.after;
  final amount = TextEditingController(text: '30');
  int unit = 1;
  DateTime? selectedAt;
  bool customStart = false;
  @override
  void initState() {
    super.initState();
    subscription = widget.repository.changes.listen((_) => _load());
    ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.repository.reminders.all(
        itemId: widget.editor.item.id,
      );
      if (mounted) setState(() => reminders = rows);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    ticker?.cancel();
    amount.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick({DateTime? initial}) async {
    final now = DateTime.now();
    final chosen = (initial ?? now.add(const Duration(hours: 1))).toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: chosen,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(chosen),
    );
    if (time == null) return null;
    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      success = null;
    });
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _flush() async {
    if (!await widget.editor.flush()) {
      throw StateError(widget.editor.error ?? 'Chưa lưu được công việc.');
    }
  }

  int? get minutes {
    final value = int.tryParse(amount.text.trim());
    return value != null && value > 0 && value * unit <= 525600
        ? value * unit
        : null;
  }

  Future<void> _save() => _run(() async {
    if (mode != ScheduleMode.at && minutes == null) {
      throw StateError('Nhập số nguyên dương, tối đa 365 ngày.');
    }
    if ((mode == ScheduleMode.at ||
            customStart && mode == ScheduleMode.repeat) &&
        selectedAt == null) {
      throw StateError('Chọn ngày và giờ nhắc trước khi lưu.');
    }
    await _flush();
    final at =
        mode == ScheduleMode.at || mode == ScheduleMode.repeat && customStart
        ? selectedAt!
        : DateTime.now().add(Duration(minutes: minutes!));
    final item = widget.editor.item;
    final saved = await widget.repository.reminders.add(
      item.id,
      item.revision,
      at,
      intervalMinutes: mode == ScheduleMode.repeat ? minutes : null,
    );
    if (mounted) {
      setState(
        () => success =
            'Đã lưu · ${studioDate(saved.eligibleAt)} · ${saved.repeatLabel}',
      );
    }
  });
  @override
  Widget build(BuildContext context) {
    final item = widget.editor.item;
    final disabled =
        busy ||
        widget.disabled ||
        item.archived ||
        item.status == WorkStatus.done;
    final current = reminders
        .where((r) => r.active || r.state == ReminderState.paused)
        .toList();
    final active = current.where((r) => r.active).length;
    final scheme = Theme.of(context).colorScheme;
    final due = item.dueAtUtc == null ? null : DateTime.parse(item.dueAtUtc!);
    final previewAt =
        mode == ScheduleMode.at || mode == ScheduleMode.repeat && customStart
        ? selectedAt
        : minutes == null
        ? null
        : DateTime.now().add(Duration(minutes: minutes!));
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Nhắc hẹn',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '$active/3 lịch',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Đặt nhắc cho công việc hoặc ghi chú. Đến giờ, popup Windows sẽ hiện tiến độ và thao tác nhanh.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in {
                  ScheduleMode.at: 'Ngày & giờ',
                  ScheduleMode.after: 'Sau khoảng thời gian',
                  ScheduleMode.repeat: 'Lặp định kỳ',
                }.entries)
                  ChoiceChip(
                    selectedColor: scheme.primaryContainer,
                    checkmarkColor: scheme.onPrimaryContainer,
                    labelStyle: TextStyle(
                      color: mode == entry.key
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                    label: Text(entry.value),
                    selected: mode == entry.key,
                    onSelected: disabled
                        ? null
                        : (_) => setState(() {
                            mode = entry.key;
                            error = null;
                            success = null;
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (mode != ScheduleMode.at) ...[
              Text(
                mode == ScheduleMode.repeat ? 'Lặp mỗi' : 'Nhắc sau',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: amount,
                      enabled: !disabled,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Số lượng',
                        hintText: 'Ví dụ: 30',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      key: ValueKey(unit),
                      initialValue: unit,
                      decoration: const InputDecoration(
                        labelText: 'Đơn vị',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Phút')),
                        DropdownMenuItem(value: 60, child: Text('Giờ')),
                        DropdownMenuItem(value: 1440, child: Text('Ngày')),
                      ],
                      onChanged: disabled
                          ? null
                          : (v) => setState(() => unit = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final m in [5, 15, 30, 60])
                    ActionChip(
                      label: Text(m == 60 ? '1 giờ' : '$m phút'),
                      onPressed: disabled
                          ? null
                          : () => setState(() {
                              amount.text = (m ~/ unit > 0 ? m ~/ unit : m)
                                  .toString();
                              if (m < unit) unit = 1;
                            }),
                    ),
                ],
              ),
            ],
            if (mode == ScheduleMode.repeat)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Chọn thời điểm bắt đầu'),
                value: customStart,
                onChanged: disabled
                    ? null
                    : (v) => setState(() => customStart = v!),
              ),
            if (mode == ScheduleMode.at ||
                mode == ScheduleMode.repeat && customStart)
              OutlinedButton.icon(
                onPressed: disabled
                    ? null
                    : () async {
                        final at = await _pick(initial: selectedAt);
                        if (at != null && mounted) {
                          setState(() => selectedAt = at);
                        }
                      },
                icon: const Icon(Icons.calendar_month),
                label: Text(
                  selectedAt == null
                      ? 'Chọn ngày và giờ'
                      : studioDate(selectedAt!),
                ),
              ),
            const SizedBox(height: 12),
            if (previewAt != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${mode == ScheduleMode.repeat ? 'Lần đầu' : 'Sẽ nhắc'}: ${studioDate(previewAt)}${mode == ScheduleMode.repeat && minutes != null ? ' · sau đó mỗi ${reminderDuration(minutes!)}' : ''}',
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ),
            if (mode == ScheduleMode.repeat)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Đã xem sẽ chuyển sang kỳ tiếp theo. Kỳ bị lỡ được gom lại; không mở dồn popup. Hoàn tất hoặc lưu trữ sẽ dừng lịch. Ngày = 24 giờ, không phải lịch theo giờ địa phương.',
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: disabled || active >= 3 ? null : _save,
                  icon: const Icon(Icons.add_alarm),
                  label: const Text('Lưu nhắc hẹn'),
                ),
                TextButton(
                  onPressed: disabled || active >= 3
                      ? null
                      : () => _run(() async {
                          await _flush();
                          final i = widget.editor.item;
                          await widget.repository.reminders.add(
                            i.id,
                            i.revision,
                            DateTime.now(),
                            allowPast: true,
                          );
                        }),
                  child: const Text('Nhắc ngay'),
                ),
                if (Platform.isWindows)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _run(
                            () async =>
                                (await PlanStudioRuntime.open()).preview(),
                          ),
                    child: const Text('Thử popup'),
                  ),
              ],
            ),
            if (disabled && !busy)
              const Text(
                'Công việc đã hoàn tất hoặc lưu trữ: mở lại để đặt lịch mới.',
              ),
            if (active >= 3)
              const Text(
                'Đã đủ 3 lịch. Hủy một lịch bên dưới để thêm lịch mới.',
              ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Text(error!, style: TextStyle(color: scheme.error)),
            if (success != null)
              Text(success!, style: TextStyle(color: scheme.primary)),
            const Divider(height: 28),
            Text('Lịch đã đặt', style: Theme.of(context).textTheme.titleSmall),
            if (current.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Chưa có nhắc hẹn. Chọn chế độ và bấm Lưu nhắc hẹn.',
                ),
              ),
            for (final r in current)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  r.intervalMinutes == null ? Icons.alarm : Icons.repeat,
                  color: scheme.primary,
                ),
                title: Text(
                  r.state == ReminderState.paused
                      ? 'Đang tạm tắt'
                      : reminderCountdown(r.eligibleAt, DateTime.now()),
                ),
                subtitle: Text(
                  '${studioDate(r.eligibleAt)} · ${r.repeatLabel}${r.state == ReminderState.snoozed ? ' · Đã hoãn' : ''}${r.state == ReminderState.paused ? ' · Lịch nhập: tạo lịch mới để bật' : ''}',
                ),
                trailing: r.active
                    ? IconButton(
                        tooltip: r.intervalMinutes == null
                            ? 'Hủy nhắc hẹn'
                            : 'Dừng lịch lặp',
                        icon: const Icon(Icons.close),
                        onPressed: busy
                            ? null
                            : () => _run(
                                () => widget.repository.reminders.act(
                                  r.id,
                                  r.revision,
                                  const Uuid().v4(),
                                  'cancel',
                                ),
                              ),
                      )
                    : null,
              ),
            const Divider(height: 28),
            Text(
              'Hạn hoàn thành & nhắc trước hạn',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            DueField(
              editor: widget.editor,
              repository: widget.repository,
              disabled: disabled,
            ),
            if (due != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in dueReminderOptions(item.dueAllDay).entries)
                    ActionChip(
                      avatar: const Icon(Icons.alarm, size: 16),
                      label: Text(e.value),
                      onPressed: disabled || active >= 3
                          ? null
                          : () => _run(() async {
                              await _flush();
                              final i = widget.editor.item;
                              await widget.repository.reminders.add(
                                i.id,
                                i.revision,
                                DateTime.now(),
                                offsetMinutes: e.key,
                              );
                            }),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
