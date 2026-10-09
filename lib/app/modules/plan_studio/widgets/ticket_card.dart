import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/plan_reminder.dart';
import '../models/work_item.dart';
import '../services/deadline.dart';
import '../services/plan_progress_service.dart';
import '../theme/studio_tokens.dart';
import 'studio_chip.dart';
import 'studio_popover.dart';

/// Card actions. [onDue] receives the card's rect to anchor the picker.
class TicketCard extends StatefulWidget {
  const TicketCard({
    super.key,
    required this.item,
    required this.all,
    required this.onOpen,
    this.onStatus,
    this.onDue,
    this.onClearDue,
    this.onMoveProject,
    this.projectLabel,
    this.reminder,
    this.now,
  });
  final PlanReminder? reminder;
  final WorkItem item;
  final List<WorkItem> all;
  final VoidCallback onOpen;
  final ValueChanged<WorkStatus>? onStatus;
  final ValueChanged<Rect?>? onDue;
  final VoidCallback? onClearDue;
  final VoidCallback? onMoveProject;

  /// Shown next to the code when the board spans several projects.
  final String? projectLabel;
  final DateTime? now;
  @override
  State<TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends State<TicketCard> {
  bool hovered = false, focused = false;
  bool get _actions =>
      widget.onStatus != null ||
      widget.onDue != null ||
      widget.onMoveProject != null;

  Future<void> _menu(Offset position) async {
    final tokens = StudioTokens.of(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final item = widget.item;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (widget.onStatus != null) ...[
          const PopupMenuItem(
            enabled: false,
            height: 28,
            child: Text('Chuyển sang'),
          ),
          for (final s in WorkStatus.values)
            PopupMenuItem(
              value: 'status:${s.name}',
              enabled: s != item.status,
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.circle, size: 9, color: tokens.status(s)),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(s.label, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
        ],
        if (widget.onDue != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'due',
            height: 36,
            child: Row(
              children: [
                const Icon(Icons.event_outlined, size: 17),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    item.dueAtUtc == null ? 'Đặt hạn…' : 'Sửa hạn…',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (item.dueAtUtc != null && widget.onClearDue != null)
            const PopupMenuItem(
              value: 'clear-due',
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.event_busy_outlined, size: 17),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text('Bỏ hạn', overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
        ],
        if (widget.onMoveProject != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'move-project',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.drive_file_move_outline, size: 17),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Chuyển sang dự án…',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'due') {
      widget.onDue?.call(rectOf(context));
    } else if (action == 'clear-due') {
      widget.onClearDue?.call();
    } else if (action == 'move-project') {
      widget.onMoveProject?.call();
    } else if (action.startsWith('status:')) {
      widget.onStatus?.call(WorkStatus.values.byName(action.substring(7)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = StudioTokens.of(context);
    final item = widget.item;
    final now = widget.now ?? DateTime.now();
    final color = tokens.status(item.status);
    final accent = tokens.priority(item.priority);
    final progress = PlanProgress(item, widget.all);
    final parent = widget.all.where((i) => i.id == item.parentId).firstOrNull;
    final childDue = item.type == WorkType.plan && item.dueAtUtc == null
        ? nearestChildDue(item, widget.all)
        : null;
    final lateChildren = item.type == WorkType.plan
        ? overdueChildren(item, widget.all, now)
        : 0;
    final reminder = widget.reminder;
    final muted = tokens.muted;
    final neutral = ToneColors(muted, Colors.transparent, tokens.line);
    final meta = <Widget>[
      if (item.dueAtUtc != null) DeadlineChip(item: item, now: now),
      if (childDue != null)
        StudioChip(
          label: 'Task ${dueLabel(childDue, now)}',
          icon: Icons.subdirectory_arrow_right,
          tone: tokens.due(dueState(childDue, now)),
          tooltip:
              'Hạn gần nhất của task: ${childDue.code} · ${dueFull(childDue)}',
        ),
      if (lateChildren > 0)
        StudioChip(
          label: '$lateChildren task trễ',
          tone: tokens.due(DueState.overdue),
        ),
      if (reminder != null)
        StudioChip(
          label: _reminderShort(reminder.eligibleAt, now),
          icon: reminder.intervalMinutes == null ? Icons.alarm : Icons.repeat,
          tone: ToneColors(
            theme.colorScheme.primary,
            Colors.transparent,
            theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          tooltip:
              '${reminderCountdown(reminder.eligibleAt, now)} · ${studioDate(reminder.eligibleAt)}',
        ),
      if (progress.total > 0)
        StudioChip(
          label: '${progress.done}/${progress.total}',
          leading: SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
              value: progress.fraction,
              strokeWidth: 2,
              color: progress.done == progress.total
                  ? tokens.palette.success
                  : color,
              backgroundColor: tokens.line,
            ),
          ),
          tone: neutral,
          tooltip: progress.label,
        ),
      if (item.notes.isNotEmpty)
        StudioChip(
          label: '${item.notes.length}',
          icon: Icons.chat_bubble_outline,
          tone: neutral,
          tooltip: '${item.notes.length} ghi chú',
        ),
    ];
    final showMenuButton = _actions && (hovered || focused);
    return Semantics(
      label:
          '${item.code}, ${item.title}, ${item.status.label}'
          '${item.dueAtUtc == null ? '' : ', hạn ${dueLabel(item, now)}'}',
      button: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(StudioTokens.cardRadius),
            boxShadow: hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: Material(
            key: ValueKey('ticket-${item.id}'),
            color: theme.colorScheme.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(StudioTokens.cardRadius),
              side: BorderSide(
                color: hovered ? theme.colorScheme.outline : tokens.line,
              ),
            ),
            child: Stack(
              children: [
                CallbackShortcuts(
                  bindings: {
                    if (widget.onDue != null)
                      const SingleActivator(LogicalKeyboardKey.keyD): () =>
                          widget.onDue!(rectOf(context)),
                    if (widget.onMoveProject != null)
                      const SingleActivator(LogicalKeyboardKey.keyM):
                          widget.onMoveProject!,
                    if (widget.onStatus != null)
                      for (var n = 0; n < WorkStatus.values.length; n++)
                        SingleActivator(_digits[n]): () {
                          if (WorkStatus.values[n] != item.status) {
                            widget.onStatus!(WorkStatus.values[n]);
                          }
                        },
                  },
                  child: InkWell(
                    onTap: widget.onOpen,
                    onFocusChange: (v) => setState(() => focused = v),
                    onSecondaryTapUp: _actions
                        ? (d) => _menu(d.globalPosition)
                        : null,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        accent == null ? 12 : 14,
                        10,
                        10,
                        11,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                workTypeIcon(item.type),
                                size: 14,
                                color: color,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  [
                                    item.code,
                                    if (item.type != WorkType.task)
                                      workTypeLabels[item.type],
                                    ?widget.projectLabel,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: muted,
                                  ),
                                ),
                              ),
                              if (accent != null)
                                Tooltip(
                                  message: 'Ưu tiên ${item.priority}',
                                  child: Row(
                                    children: [
                                      Icon(Icons.flag, size: 13, color: accent),
                                      Text(
                                        item.priority,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(color: accent),
                                      ),
                                    ],
                                  ),
                                ),
                              SizedBox(
                                width: showMenuButton ? 26 : 0,
                                height: 22,
                                child: showMenuButton
                                    ? Builder(
                                        builder: (context) => IconButton(
                                          tooltip: 'Thao tác',
                                          padding: EdgeInsets.zero,
                                          iconSize: 17,
                                          onPressed: () {
                                            final r = rectOf(context);
                                            if (r != null) _menu(r.bottomLeft);
                                          },
                                          icon: const Icon(Icons.more_horiz),
                                        ),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                          if (item.type == WorkType.note &&
                              item.body.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                item.body.replaceAll(RegExp(r'[#*`>]'), ''),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  height: 1.45,
                                ),
                              ),
                            ),
                          if (item.status == WorkStatus.blocked &&
                              item.blockedReason.trim().isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                  StudioTokens.chipRadius,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 1),
                                    child: Icon(
                                      Icons.block,
                                      size: 13,
                                      color: color,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item.blockedReason,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: color),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (parent != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.subdirectory_arrow_right,
                                    size: 13,
                                    color: muted,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${parent.code} · ${parent.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(fontSize: 11.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (meta.isNotEmpty || item.labels.isNotEmpty) ...[
                            const SizedBox(height: 9),
                            Wrap(
                              spacing: 5,
                              runSpacing: 5,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ...meta,
                                for (final label in item.labels.take(2))
                                  Text(
                                    '#$label',
                                    style: studioChipText(context, muted),
                                  ),
                                if (item.labels.length > 2)
                                  Tooltip(
                                    message: item.labels.skip(2).join(', '),
                                    child: Text(
                                      '+${item.labels.length - 2}',
                                      style: studioChipText(context, muted),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (accent != null)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 3,
                    child: IgnorePointer(child: ColoredBox(color: accent)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "16:45" today, "Mai 09:00", otherwise "03/10".
String _reminderShort(DateTime at, DateTime now) {
  final l = at.toLocal(), n = now.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final time = '${two(l.hour)}:${two(l.minute)}';
  final hours = DateTime(
    l.year,
    l.month,
    l.day,
  ).difference(DateTime(n.year, n.month, n.day)).inHours;
  if (hours <= 0) return time;
  if (hours < 48) return 'Mai $time';
  return '${two(l.day)}/${two(l.month)}';
}

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
];
