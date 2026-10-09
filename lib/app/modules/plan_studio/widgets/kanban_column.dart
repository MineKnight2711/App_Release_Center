import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/work_item.dart';
import '../models/plan_reminder.dart';
import '../theme/studio_tokens.dart';
import '../services/quick_add_parser.dart';
import 'quick_add_field.dart';
import 'ticket_card.dart';

class KanbanColumn extends StatefulWidget {
  const KanbanColumn({
    super.key,
    required this.status,
    required this.items,
    required this.all,
    required this.onOpen,
    required this.onMove,
    required this.onCreate,
    required this.dragPosition,
    this.onQuickAdd,
    this.onDue,
    this.onClearDue,
    this.onMoveProject,
    this.projectLabel,
    this.onToggleCollapse,
    this.collapsed = false,
    this.reminders = const [],
    this.enabled = true,
    this.reorder = true,
  });
  final List<PlanReminder> reminders;
  final WorkStatus status;
  final List<WorkItem> items;
  final List<WorkItem> all;
  final ValueChanged<WorkItem> onOpen;
  final void Function(WorkItem, WorkStatus, String?) onMove;

  /// Full create dialog; [onQuickAdd] is the inline title-only path.
  final VoidCallback? onCreate;
  final Future<void> Function(QuickAdd parsed)? onQuickAdd;
  final void Function(WorkItem, Rect?)? onDue;
  final ValueChanged<WorkItem>? onClearDue;

  /// Available even when the column is read-only (all projects, archive).
  final ValueChanged<WorkItem>? onMoveProject;
  final String? Function(WorkItem)? projectLabel;
  final VoidCallback? onToggleCollapse;
  final bool collapsed;
  final ValueNotifier<Offset?> dragPosition;
  final bool enabled, reorder;
  @override
  State<KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends State<KanbanColumn> {
  final scroll = ScrollController();
  final viewport = GlobalKey();
  Timer? ticker;
  bool adding = false;
  @override
  void initState() {
    super.initState();
    widget.dragPosition.addListener(_dragChanged);
  }

  void _dragChanged() {
    ticker?.cancel();
    if (widget.dragPosition.value != null) {
      ticker = Timer.periodic(
        const Duration(milliseconds: 30),
        (_) => _autoScroll(),
      );
    }
  }

  void _autoScroll() {
    final position = widget.dragPosition.value;
    final box = viewport.currentContext?.findRenderObject() as RenderBox?;
    if (position == null || box == null || !scroll.hasClients) return;
    final local = box.globalToLocal(position);
    if (local.dx < 0 ||
        local.dx > box.size.width ||
        local.dy < 0 ||
        local.dy > box.size.height) {
      return;
    }
    final delta = local.dy < 60
        ? -14.0
        : local.dy > box.size.height - 60
        ? 14.0
        : 0.0;
    if (delta != 0) {
      scroll.jumpTo(
        (scroll.offset + delta).clamp(0, scroll.position.maxScrollExtent),
      );
    }
  }

  @override
  void dispose() {
    ticker?.cancel();
    widget.dragPosition.removeListener(_dragChanged);
    scroll.dispose();
    super.dispose();
  }

  bool _accept(WorkItem item, {bool insertion = false}) =>
      widget.enabled &&
      !item.archived &&
      (widget.reorder || item.status != widget.status) &&
      (!insertion || widget.reorder);

  void _add() {
    if (widget.onQuickAdd == null) {
      widget.onCreate?.call();
    } else {
      setState(() => adding = true);
    }
  }

  Widget _dropZone(String? before, Color color) => DragTarget<WorkItem>(
    onWillAcceptWithDetails: (details) =>
        _accept(details.data, insertion: true) && details.data.id != before,
    onAcceptWithDetails: (details) =>
        widget.onMove(details.data, widget.status, before),
    builder: (context, candidates, _) => AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      height: candidates.isNotEmpty ? 36 : 8,
      decoration: BoxDecoration(
        color: candidates.isEmpty
            ? Colors.transparent
            : color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
      ),
      child: candidates.isEmpty
          ? null
          : const Center(child: Icon(Icons.add, size: 18)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = StudioTokens.of(context);
    final color = tokens.status(widget.status);
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return DragTarget<WorkItem>(
      onWillAcceptWithDetails: (d) => _accept(d.data),
      onAcceptWithDetails: (d) => widget.onMove(d.data, widget.status, null),
      builder: (context, candidates, _) {
        final decoration = BoxDecoration(
          color: candidates.isEmpty
              ? tokens.column
              : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(StudioTokens.panelRadius),
          border: Border.all(
            color: candidates.isEmpty
                ? scheme.outlineVariant.withValues(alpha: 0.35)
                : color,
          ),
        );
        if (widget.collapsed) {
          // Width switches instantly: animating it would squeeze the
          // expanded header through the rail's width.
          return Container(
            key: ValueKey('column-${widget.status.name}'),
            width: StudioTokens.railWidth,
            decoration: decoration,
            child: Tooltip(
              message: 'Mở rộng ${widget.status.label}',
              child: InkWell(
                borderRadius: BorderRadius.circular(StudioTokens.panelRadius),
                onTap: widget.onToggleCollapse,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    children: [
                      Icon(Icons.circle, size: 9, color: color),
                      const SizedBox(height: 10),
                      Text(
                        '${widget.items.length}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tokens.muted,
                          fontFeatures: StudioTokens.tabular,
                        ),
                      ),
                      const SizedBox(height: 12),
                      RotatedBox(
                        quarterTurns: 1,
                        child: Text(
                          widget.status.label,
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return Container(
          key: ValueKey('column-${widget.status.name}'),
          width: StudioTokens.columnWidth,
          decoration: decoration,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 4, 2),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 9, color: color),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.status.label,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.items.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: tokens.muted,
                        fontFeatures: StudioTokens.tabular,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Thêm vào ${widget.status.label}',
                      style: tokens.quietIcon,
                      onPressed: widget.onCreate == null ? null : _add,
                      icon: const Icon(Icons.add, size: 18),
                    ),
                    if (widget.onToggleCollapse != null)
                      IconButton(
                        tooltip: 'Thu gọn cột',
                        style: tokens.quietIcon,
                        onPressed: widget.onToggleCollapse,
                        icon: const Icon(Icons.unfold_less, size: 18),
                      ),
                  ],
                ),
              ),
              if (adding && widget.onQuickAdd != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
                  child: _QuickAdd(
                    onSubmit: widget.onQuickAdd!,
                    onFull: widget.onCreate,
                    onClose: () => setState(() => adding = false),
                  ),
                ),
              Expanded(
                child: SizedBox(
                  key: viewport,
                  child: Scrollbar(
                    controller: scroll,
                    child: ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      children: [
                        if (widget.items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.inbox_outlined,
                                  color: tokens.faint,
                                  size: 26,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  widget.enabled
                                      ? 'Thả ticket vào đây'
                                      : 'Trống',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        for (final item in widget.items) ...[
                          if (widget.reorder)
                            _dropZone(item.id, color)
                          else
                            const SizedBox(height: 8),
                          _ticket(item),
                        ],
                        if (widget.reorder) _dropZone(null, color),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ticket(WorkItem item) {
    final card = TicketCard(
      item: item,
      reminder: widget.reminders
          .where((r) => r.itemId == item.id && r.active)
          .firstOrNull,
      all: widget.all,
      onOpen: () => widget.onOpen(item),
      onStatus: widget.enabled ? (s) => widget.onMove(item, s, null) : null,
      onDue: widget.enabled && widget.onDue != null
          ? (rect) => widget.onDue!(item, rect)
          : null,
      onClearDue: widget.enabled && widget.onClearDue != null
          ? () => widget.onClearDue!(item)
          : null,
      onMoveProject: widget.onMoveProject == null
          ? null
          : () => widget.onMoveProject!(item),
      projectLabel: widget.projectLabel?.call(item),
    );
    if (!widget.enabled) return card;
    return Draggable<WorkItem>(
      data: item,
      maxSimultaneousDrags: 1,
      onDragUpdate: (d) => widget.dragPosition.value = d.globalPosition,
      onDragEnd: (_) => widget.dragPosition.value = null,
      onDraggableCanceled: (_, _) => widget.dragPosition.value = null,
      feedback: Material(
        elevation: 16,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(StudioTokens.cardRadius),
        child: SizedBox(
          width: StudioTokens.columnWidth - 24,
          child: Opacity(
            opacity: 0.94,
            child: TicketCard(item: item, all: widget.all, onOpen: () {}),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: card),
      child: card,
    );
  }
}

/// Inline title entry with the quick syntax: Enter creates and stays open for
/// the next one, Esc or leaving an empty field closes it.
class _QuickAdd extends StatefulWidget {
  const _QuickAdd({required this.onSubmit, required this.onClose, this.onFull});
  final Future<void> Function(QuickAdd) onSubmit;
  final VoidCallback onClose;
  final VoidCallback? onFull;
  @override
  State<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<_QuickAdd> {
  final input = QuickAddController();
  final focus = FocusNode();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    input.addListener(() => setState(() {}));
    focus.addListener(() {
      if (!focus.hasFocus && input.text.trim().isEmpty && !busy) {
        widget.onClose();
      }
    });
  }

  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final parsed = input.parsed;
    if (parsed.title.isEmpty || busy) return;
    setState(() => busy = true);
    try {
      await widget.onSubmit(parsed);
      input.clear();
    } finally {
      if (mounted) {
        setState(() => busy = false);
        focus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('quick-add'),
          controller: input,
          focusNode: focus,
          autofocus: true,
          enabled: !busy,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Tiêu đề  $quickAddHint',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(StudioTokens.cardRadius),
            ),
            suffixIcon: widget.onFull == null
                ? null
                : IconButton(
                    tooltip: 'Tạo với đầy đủ thuộc tính',
                    iconSize: 17,
                    onPressed: () {
                      widget.onClose();
                      widget.onFull!();
                    },
                    icon: const Icon(Icons.open_in_full),
                  ),
          ),
        ),
        if (input.parsed.hasProperties)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: QuickAddSummary(input.parsed),
          ),
      ],
    ),
  );
}
