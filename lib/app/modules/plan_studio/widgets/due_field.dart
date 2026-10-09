import 'package:flutter/material.dart';
import '../controllers/plan_editor_controller.dart';
import '../models/work_item.dart';
import '../repositories/local_plan_repository.dart';
import '../repositories/plan_repository.dart';
import '../services/deadline.dart';
import 'deadline_picker.dart';
import 'studio_chip.dart';
import 'studio_popover.dart';

/// Deadline property for the ticket editor. Edits go through the editor's
/// autosave so they share its revision checks and pending-save ordering.
class DueField extends StatefulWidget {
  const DueField({
    super.key,
    required this.editor,
    required this.repository,
    this.disabled = false,
    this.dense = false,
  });
  final PlanEditorController editor;
  final PlanRepository repository;
  final bool disabled;

  /// Borderless row for the properties rail instead of a form field.
  final bool dense;
  @override
  State<DueField> createState() => _DueFieldState();
}

class _DueFieldState extends State<DueField> {
  bool busy = false;

  Future<void> _edit() async {
    if (busy) return;
    setState(() => busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final item = widget.editor.item;
      final repository = widget.repository;
      final canRemind =
          repository is LocalPlanRepository &&
          !item.archived &&
          item.status != WorkStatus.done;
      final existing = canRemind
          ? {
              for (final r in await repository.reminders.all(itemId: item.id))
                if (r.active && r.offsetMinutes != null) r.offsetMinutes!,
            }
          : <int>{};
      if (!mounted) return;
      final pick = await showDeadlinePicker(
        context,
        item,
        anchor: rectOf(context),
        reminders: canRemind,
        existingOffsets: existing,
      );
      if (pick == null) return;
      widget.editor.change((i) => setDue(i, pick.at, allDay: pick.allDay));
      if (!await widget.editor.flush()) {
        throw StateError(widget.editor.error ?? 'Chưa lưu được hạn.');
      }
      final errors = await addDueReminders(
        repository,
        widget.editor.item,
        pick.offsets,
      );
      if (errors.isNotEmpty) {
        messenger?.showSnackBar(SnackBar(content: Text(errors.join('\n'))));
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.editor.item;
    final theme = Theme.of(context);
    final moved = item.dueHistory.length;
    if (widget.dense) {
      return InkWell(
        key: const ValueKey('due-field'),
        onTap: widget.disabled || busy ? null : _edit,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: item.dueAtUtc == null
              ? Text(
                  'Đặt hạn',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DeadlineChip(item: item),
                    Text(dueFull(item), style: theme.textTheme.bodySmall),
                  ],
                ),
        ),
      );
    }
    return InkWell(
      key: const ValueKey('due-field'),
      onTap: widget.disabled || busy ? null : _edit,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Hạn',
          enabled: !widget.disabled,
          helperText: moved == 0 ? null : 'Đã dời $moved lần',
          suffixIcon: const Icon(Icons.event_outlined, size: 18),
        ),
        child: item.dueAtUtc == null
            ? Text(
                'Chưa có hạn',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Row(
                children: [
                  DeadlineChip(item: item),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      dueFull(item),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
