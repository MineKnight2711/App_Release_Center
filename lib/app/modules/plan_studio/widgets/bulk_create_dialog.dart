import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/work_item.dart';
import '../services/bulk_add_parser.dart';
import '../services/deadline.dart';
import '../theme/studio_tokens.dart';
import 'quick_add_field.dart';
import 'studio_chip.dart';

/// Columns a bulk create can fill. Blocked needs a reason, so only `⏳` lines,
/// which carry [bulkWaitingReason], go there.
const bulkStatuses = [
  WorkStatus.backlog,
  WorkStatus.ready,
  WorkStatus.inProgress,
  WorkStatus.review,
  WorkStatus.done,
];

/// Opens the bulk composer over one project's tickets ([items]) and returns
/// the new task drafts, or null when canceled.
Future<List<WorkItem>?> showBulkCreateDialog(
  BuildContext context, {
  required String projectId,
  required List<WorkItem> items,
  WorkStatus status = WorkStatus.backlog,
}) => showDialog<List<WorkItem>>(
  context: context,
  builder: (_) =>
      BulkCreateDialog(projectId: projectId, items: items, status: status),
);

/// The tasks [lines] describe, repeated titles dropped. A line's own deadline
/// wins over the plan's; a `⏳` line goes to the blocked column.
List<WorkItem> bulkDrafts(
  List<BulkLine> lines, {
  required String projectId,
  required WorkStatus status,
  WorkItem? plan,
  bool inheritDue = false,
}) {
  const uuid = Uuid();
  final planDue = inheritDue ? plan?.dueAt?.toLocal() : null;
  WorkItem draft(BulkLine line) {
    final item = WorkItem(
      id: uuid.v4(),
      projectId: projectId,
      title: line.parsed.title,
      status: line.waiting ? WorkStatus.blocked : status,
      blockedReason: line.waiting ? bulkWaitingReason : '',
      priority: line.parsed.priority ?? 'P2',
      labels: [...line.parsed.labels],
      parentId: plan?.id,
    );
    if (line.parsed.due != null) {
      setDue(item, line.parsed.due, allDay: line.parsed.allDay);
    } else if (planDue != null) {
      setDue(item, planDue, allDay: plan!.dueAllDay);
    }
    return item;
  }

  return [
    for (final line in lines)
      if (!line.duplicate) draft(line),
  ];
}

class BulkCreateDialog extends StatefulWidget {
  const BulkCreateDialog({
    super.key,
    required this.projectId,
    required this.items,
    this.status = WorkStatus.backlog,
  });
  final String projectId;

  /// The project's tickets: plans to attach to and titles already on the board.
  final List<WorkItem> items;
  final WorkStatus status;
  @override
  State<BulkCreateDialog> createState() => _BulkCreateDialogState();
}

class _BulkCreateDialogState extends State<BulkCreateDialog> {
  final input = BulkAddController();
  late WorkStatus status = bulkStatuses.contains(widget.status)
      ? widget.status
      : WorkStatus.backlog;
  String? planId;
  bool inheritDue = false;
  late final plans = widget.items
      .where((i) => i.type == WorkType.plan && !i.archived)
      .toList();
  late final existing = {
    for (final i in widget.items)
      if (!i.archived) i.title.toLowerCase(): i.code,
  };

  WorkItem? get plan => plans.where((p) => p.id == planId).firstOrNull;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void _submit() {
    final lines = input.lines;
    final count = lines.where((l) => !l.duplicate).length;
    if (count == 0 || count > bulkAddLimit) return;
    Navigator.pop(
      context,
      bulkDrafts(
        lines,
        projectId: widget.projectId,
        status: status,
        plan: plan,
        inheritDue: inheritDue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = StudioTokens.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: tokens.muted);
    final lines = input.lines;
    final count = lines.where((l) => !l.duplicate).length;
    final repeats = lines.length - count;
    final over = count > bulkAddLimit;
    final plan = this.plan;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
      },
      child: AlertDialog(
        title: const Text('Tạo task hàng loạt'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('bulk-input'),
                controller: input,
                autofocus: true,
                minLines: 6,
                maxLines: 10,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Danh sách task · mỗi dòng một task',
                  alignLabelWithHint: true,
                  hintText:
                      'Thiết kế màn đăng nhập !p1 #mobile\n'
                      '➡️ 🔴 Cao – Sửa lỗi chụp CCCD trên iOS ^t6\n'
                      '⏳ Chờ phản hồi – Đối tác nghiệm thu luồng BHXH',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<WorkStatus>(
                      key: const ValueKey('bulk-status'),
                      initialValue: status,
                      decoration: const InputDecoration(
                        labelText: 'Cột',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in bulkStatuses)
                          DropdownMenuItem(value: s, child: Text(s.label)),
                      ],
                      onChanged: (s) => setState(() => status = s ?? status),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      key: const ValueKey('bulk-plan'),
                      initialValue: planId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Thuộc plan',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Không thuộc plan'),
                        ),
                        for (final p in plans)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              '${p.code} · ${p.title}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: plans.isEmpty
                          ? null
                          : (id) => setState(() => planId = id),
                    ),
                  ),
                ],
              ),
              if (plan?.dueAt != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: inheritDue,
                  onChanged: (v) => setState(() => inheritDue = v ?? false),
                  title: Text(
                    'Dùng hạn của plan (${dueFull(plan!)}) cho task chưa đặt hạn',
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                lines.isEmpty
                    ? 'Dấu đầu dòng (-, *, ➡️, 1.), ô checkbox và tiêu đề Markdown được bỏ qua khi dán.'
                    : 'Xem trước · $count task'
                          '${repeats == 0 ? '' : ' · bỏ qua $repeats dòng trùng'}',
                style: lines.isEmpty ? muted : theme.textTheme.labelLarge,
              ),
              if (lines.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    key: const ValueKey('bulk-preview'),
                    shrinkWrap: true,
                    itemCount: lines.length,
                    itemBuilder: (_, n) => _PreviewRow(
                      index: n,
                      line: lines[n],
                      existing: existing[lines[n].parsed.title.toLowerCase()],
                    ),
                  ),
                ),
              if (over)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Tối đa $bulkAddLimit task mỗi lần. Hãy chia nhỏ danh sách.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Ctrl+Enter để tạo · Ưu tiên: !p0–!p3 hoặc đầu dòng “🔴 Cao –”, '
                '“🟡 Trung bình –”, “Thấp –” · “⏳ Chờ phản hồi –” vào cột '
                '${WorkStatus.blocked.label} · #nhãn · ^mai, ^25/10 17h cho hạn',
                style: muted,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const ValueKey('bulk-submit'),
            onPressed: count == 0 || over ? null : _submit,
            child: Text(count == 0 ? 'Tạo task' : 'Tạo $count task'),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.index, required this.line, this.existing});
  final int index;
  final BulkLine line;

  /// Code of a ticket on the board with the same title.
  final String? existing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = StudioTokens.of(context);
    final note = theme.textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${index + 1}.',
              style: note?.copyWith(
                color: tokens.muted,
                fontFeatures: StudioTokens.tabular,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.parsed.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: line.duplicate
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.muted,
                          decoration: TextDecoration.lineThrough,
                        )
                      : theme.textTheme.bodyMedium,
                ),
                if (line.duplicate)
                  Text(
                    'Trùng dòng phía trên, sẽ bỏ qua',
                    style: note?.copyWith(color: tokens.muted),
                  )
                else ...[
                  if (existing != null)
                    Text(
                      'Đã có $existing cùng tiêu đề trên board',
                      style: note?.copyWith(color: tokens.palette.warning),
                    ),
                  if (line.waiting || line.parsed.hasProperties)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          if (line.waiting)
                            StudioChip(
                              icon: Icons.block,
                              label:
                                  '${WorkStatus.blocked.label} · $bulkWaitingReason',
                              tone: tokens.tone(tokens.palette.danger),
                            ),
                          QuickAddSummary(line.parsed),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
