import 'package:flutter/material.dart';
import '../models/work_item.dart';
import '../services/deadline.dart';
import '../theme/studio_tokens.dart';

/// Compact meta pill used on cards and in filters.
class StudioChip extends StatelessWidget {
  const StudioChip({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.leading,
    this.tooltip,
  });
  final String label;
  final ToneColors tone;
  final IconData? icon;
  final Widget? leading;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(StudioTokens.chipRadius),
        border: Border.all(color: tone.border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?leading,
          if (icon != null) Icon(icon, size: 12, color: tone.fg),
          if (icon != null || leading != null) const SizedBox(width: 4),
          Text(label, style: studioChipText(context, tone.fg)),
        ],
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip, child: chip);
  }
}

TextStyle? studioChipText(BuildContext context, Color color) =>
    Theme.of(context).textTheme.labelMedium?.copyWith(
      fontSize: 11.5,
      height: 1.3,
      color: color,
      fontFeatures: StudioTokens.tabular,
    );

/// The deadline pill: color and wording follow [dueState].
class DeadlineChip extends StatelessWidget {
  const DeadlineChip({super.key, required this.item, this.now});
  final WorkItem item;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final at = now ?? DateTime.now();
    final state = dueState(item, at);
    if (state == DueState.none) return const SizedBox.shrink();
    final moved = item.dueHistory.length;
    return StudioChip(
      key: ValueKey('due-${item.id}'),
      label: dueLabel(item, at),
      tone: StudioTokens.of(context).due(state),
      icon: switch (state) {
        DueState.doneOnTime || DueState.doneLate => Icons.check,
        DueState.overdue => Icons.flag,
        _ => Icons.flag_outlined,
      },
      tooltip:
          'Hạn: ${dueFull(item)}${moved == 0 ? '' : ' · đã dời $moved lần'}',
    );
  }
}
