import 'dart:io';
import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/plan_editor_controller.dart';
import '../models/plan_reminder.dart';
import '../models/work_item.dart';
import '../repositories/plan_repository.dart';
import '../repositories/local_plan_repository.dart';
import '../services/deadline.dart';
import '../theme/studio_tokens.dart';
import '../widgets/due_field.dart';
import '../widgets/label_editor.dart';
import '../widgets/markdown_view.dart';
import '../widgets/project_dialogs.dart';
import '../widgets/reminder_schedule_editor.dart';
import '../widgets/studio_chip.dart';
import '../widgets/studio_popover.dart';

Future<void> showTicketEditor(
  BuildContext context,
  PlanRepository repository,
  WorkItem item, {
  bool compose = false,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: false,
  barrierLabel: 'Chi tiết ticket',
  transitionDuration: const Duration(milliseconds: 180),
  pageBuilder: (context, _, _) {
    final width = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: width < 760
            ? double.infinity
            : width >= 1280
            ? 1000
            : 760,
        child: TicketEditor(
          repository: repository,
          item: item,
          compose: compose,
        ),
      ),
    );
  },
  transitionBuilder: (_, animation, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(0.15, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: FadeTransition(opacity: animation, child: child),
  ),
);

const _priorityNames = {
  'P0': 'Khẩn cấp',
  'P1': 'Cao',
  'P2': 'Bình thường',
  'P3': 'Thấp',
};

class TicketEditor extends StatefulWidget {
  const TicketEditor({
    super.key,
    required this.repository,
    required this.item,
    this.compose = false,
  });
  final PlanRepository repository;
  final WorkItem item;
  final bool compose;
  @override
  State<TicketEditor> createState() => _TicketEditorState();
}

class _TicketEditorState extends State<TicketEditor>
    with WidgetsBindingObserver {
  late final PlanEditorController editor;
  late final TextEditingController title, body, source, contextInput;
  final checklist = TextEditingController(), note = TextEditingController();
  List<WorkItem> related = [];
  List<StudioProject> projects = [];
  List<PlanReminder> reminders = [];
  bool closing = false, actionBusy = false, allActivity = false;
  late bool preview =
      widget.item.type == WorkType.plan && widget.item.body.trim().isNotEmpty;
  StreamSubscription<void>? changes;
  LocalPlanRepository? get local => switch (widget.repository) {
    final LocalPlanRepository r => r,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    editor = PlanEditorController(widget.repository, widget.item)
      ..addListener(_changed);
    title = TextEditingController(text: editor.item.title);
    body = TextEditingController(text: editor.item.body);
    source = TextEditingController(
      text: editor.item.draft['source'] as String? ?? '',
    );
    contextInput = TextEditingController(
      text: editor.item.draft['context'] as String? ?? '',
    );
    _related();
    changes = local?.changes.listen((_) => _externalChange());
  }

  Future<void> _externalChange() async {
    try {
      final all = await widget.repository.items();
      final schedule = await local?.reminders.all(itemId: editor.item.id);
      if (!mounted) return;
      final latest = all.where((i) => i.id == editor.item.id).firstOrNull;
      setState(() {
        related = all;
        if (schedule != null) reminders = schedule;
        if (latest == null) {
          editor.error =
              'Ticket đã bị xóa ở nơi khác. Nội dung đang nhập vẫn được giữ.';
        } else if (latest.revision != editor.item.revision && !editor.saving) {
          if (editor.dirty || editor.busy) {
            editor.error =
                'Ticket đã được cập nhật từ nơi khác. Bản nháp đang nhập được giữ; đóng và mở lại để lấy dữ liệu mới.';
          } else {
            editor.item = latest;
            title.text = latest.title;
            body.text = latest.body;
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => editor.error = '$e');
    }
  }

  void _changed() {
    if (!mounted) return;
    if (body.text != editor.item.body) body.text = editor.item.body;
    setState(() {});
  }

  Future<void> _related() async {
    try {
      final list = await widget.repository.items();
      final registry = await widget.repository.projects();
      final schedule = await local?.reminders.all(itemId: editor.item.id);
      if (mounted) {
        setState(() {
          related = list;
          projects = registry;
          if (schedule != null) reminders = schedule;
        });
      }
    } catch (e) {
      if (mounted) _message('$e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      editor.flush();
    }
  }

  @override
  void dispose() {
    changes?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    editor.removeListener(_changed);
    editor.dispose();
    for (final c in [title, body, source, contextInput, checklist, note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _close() async {
    if (closing || actionBusy) return;
    closing = true;
    editor.cancel();
    if (await editor.flush() && mounted) Navigator.of(context).pop();
    closing = false;
  }

  Future<void> _discard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bỏ thay đổi chưa lưu?'),
        content: const Text(
          'Bản đã lưu vẫn được giữ. Bạn có thể copy nội dung trước khi đóng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Tiếp tục sửa'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bỏ thay đổi và đóng'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() => _action(() async {
    final item = editor.item;
    final all = await widget.repository.items();
    final children = all.where((i) => i.parentId == item.id).length;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xóa ${item.type.name} ${item.code}?'),
        content: Text(
          '“${item.title}” sẽ bị xóa vĩnh viễn cùng note, checklist, lịch sử và phiên bản bên trong. Không thể hoàn tác.'
          '${children == 0 ? '' : '\n\n$children task con (kể cả đã lưu trữ) sẽ được giữ lại và bỏ liên kết với plan này.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa vĩnh viễn'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await editor.delete();
    if (mounted) Navigator.of(context).pop();
  });

  Future<void> _action(Future<void> Function() fn) async {
    if (actionBusy) return;
    setState(() => actionBusy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) _message('$e');
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> _export() => _action(() async {
    if (!await editor.flush()) return;
    final location = await getSaveLocation(
      suggestedName: '${editor.item.code}.md',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Markdown', extensions: ['md']),
      ],
    );
    if (location != null) {
      await File(location.path).writeAsString(
        '# ${editor.item.title}\n\n${editor.item.body}',
        flush: true,
      );
      if (mounted) _message('Đã xuất Markdown.');
    }
  });

  Future<void> _tasks() => _action(() async {
    if (!await editor.flush() || !mounted) return;
    final plan = editor.item;
    final result = await showDialog<_TaskListResult>(
      context: context,
      builder: (_) =>
          _TaskListDialog(planDue: plan.dueAt == null ? null : dueFull(plan)),
    );
    if (result == null || result.titles.isEmpty) return;
    final tasks = await widget.repository.createTasks(
      plan.id,
      plan.revision,
      result.titles,
    );
    if (result.inheritDue && plan.dueAt != null) {
      for (final task in tasks) {
        setDue(task, plan.dueAt!.toLocal(), allDay: plan.dueAllDay);
        await widget.repository.save(task);
      }
    }
    final all = await widget.repository.items();
    editor.item = all.firstWhere((i) => i.id == plan.id);
    if (mounted) {
      setState(() => related = all);
      _message('Đã tạo ${tasks.length} task.');
    }
  });

  /// The dialog stays outside [_action] so the panel is not shown as busy
  /// while the user is still choosing.
  Future<void> _moveProject() async {
    if (actionBusy || !await editor.flush() || !mounted) return;
    final item = editor.item;
    final target = await showMoveToProjectDialog(
      context,
      item: item,
      projects: projects,
      all: related,
      addProject: () async {
        try {
          final path = await getDirectoryPath();
          if (path == null) return null;
          final added = await widget.repository.ensureProject(path);
          projects = await widget.repository.projects();
          return added;
        } catch (e) {
          if (mounted) _message('$e');
          return null;
        }
      },
    );
    if (target == null || !mounted) return;
    await _action(() async {
      final moved = await widget.repository.moveToProject(
        item.id,
        item.revision,
        target.projectId,
        withChildren: target.withChildren,
      );
      final all = await widget.repository.items();
      final registry = await widget.repository.projects();
      if (!mounted) return;
      setState(() {
        related = all;
        projects = registry;
        editor.item = all.firstWhere((i) => i.id == item.id);
      });
      final name = registry.where((p) => p.id == target.projectId).firstOrNull;
      _message(
        'Đã chuyển sang ${name?.name ?? 'dự án mới'}'
        '${moved.length > 1 ? ' cùng ${moved.length - 1} task con' : ''}.',
      );
    });
  }

  Future<void> _archive() async {
    editor.change((i) => i.archived = !i.archived);
    if (await editor.flush() && mounted) Navigator.pop(context);
  }

  void _menu(String action) {
    switch (action) {
      case 'copy':
        Clipboard.setData(ClipboardData(text: editor.item.body));
        _message('Đã copy nội dung.');
      case 'export':
        _export();
      case 'checkpoint':
        editor.checkpoint();
        _message('Đã lưu phiên bản.');
      case 'to-task':
        editor.change((i) => i.type = WorkType.task);
        editor.flush();
      case 'move-project':
        _moveProject();
      case 'archive':
        _archive();
      case 'delete':
        _delete();
    }
  }

  void _addNote() {
    if (note.text.trim().isEmpty) return;
    editor.change(
      (i) => i.notes.add({
        'body': note.text.trim(),
        'at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    note.clear();
  }

  void _addChecklist() {
    if (checklist.text.trim().isEmpty) return;
    editor.change(
      (i) => i.checklist.add({'text': checklist.text.trim(), 'done': false}),
    );
    checklist.clear();
  }

  Future<T?> _pick<T>(BuildContext anchor, List<PopupMenuEntry<T>> items) {
    final rect = rectOf(anchor);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(
        rect == null ? Rect.zero : Rect.fromLTWH(rect.left, rect.bottom, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = editor.item;
    final isPlan = item.type == WorkType.plan;
    final disabled = editor.busy || actionBusy;
    final theme = Theme.of(context);
    final tokens = StudioTokens.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: DefaultTabController(
        length: 3,
        initialIndex: widget.compose && isPlan ? 1 : 0,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                editor.flush,
          },
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              titleSpacing: 20,
              title: Row(
                children: [
                  Icon(
                    workTypeIcon(item.type),
                    size: 18,
                    color: tokens.status(item.status),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${item.code} · ${workTypeLabels[item.type]}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _saveState(
                    theme,
                    tokens,
                    label: MediaQuery.sizeOf(context).width >= 600,
                  ),
                ],
              ),
              actions: [
                if (editor.busy)
                  TextButton(
                    onPressed: editor.cancel,
                    child: const Text('Hủy AI'),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Thao tác ticket',
                  icon: const Icon(Icons.more_horiz),
                  enabled: !disabled,
                  onSelected: _menu,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'copy',
                      child: Text('Copy nội dung'),
                    ),
                    const PopupMenuItem(
                      value: 'export',
                      child: Text('Xuất Markdown'),
                    ),
                    if (isPlan)
                      PopupMenuItem(
                        value: 'checkpoint',
                        enabled: item.body.trim().isNotEmpty,
                        child: const Text('Lưu phiên bản'),
                      ),
                    if (item.type == WorkType.note)
                      const PopupMenuItem(
                        value: 'to-task',
                        child: Text('Chuyển thành Task'),
                      ),
                    const PopupMenuItem(
                      value: 'move-project',
                      child: Text('Chuyển sang dự án…'),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(
                        item.archived ? 'Khôi phục ticket' : 'Lưu trữ ticket',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Xóa ${item.type.name}…',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Lưu và đóng',
                  onPressed: actionBusy ? null : _close,
                  icon: const Icon(Icons.close),
                ),
                const SizedBox(width: 8),
              ],
              bottom: isPlan
                  ? TabBar(
                      tabs: [
                        const Tab(text: 'Chi tiết'),
                        const Tab(text: 'Soạn plan'),
                        Tab(
                          text: item.versions.isEmpty
                              ? 'Phiên bản'
                              : 'Phiên bản · ${item.versions.length}',
                        ),
                      ],
                    )
                  : null,
            ),
            body: Column(
              children: [
                SizedBox(
                  height: 2,
                  child: editor.saving || editor.busy || actionBusy
                      ? const LinearProgressIndicator(minHeight: 2)
                      : null,
                ),
                if (editor.error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: theme.colorScheme.errorContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          editor.error!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                        if (editor.dirty && !editor.saving && !disabled)
                          TextButton(
                            onPressed: _discard,
                            child: const Text('Bỏ thay đổi chưa lưu và đóng'),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: isPlan
                      ? TabBarView(
                          children: [
                            _details(disabled),
                            _composer(disabled),
                            _versions(),
                          ],
                        )
                      : _details(disabled),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _saveState(
    ThemeData theme,
    StudioTokens tokens, {
    bool label = true,
  }) => Tooltip(
    message: 'Tự động lưu · Ctrl+S để lưu ngay',
    child: InkWell(
      onTap: editor.busy || actionBusy ? null : editor.flush,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              editor.dirty ? Icons.edit_outlined : Icons.cloud_done_outlined,
              size: 15,
              color: tokens.muted,
            ),
            if (label) ...[
              const SizedBox(width: 6),
              Text(
                editor.saving
                    ? 'Đang lưu…'
                    : editor.dirty
                    ? 'Chưa lưu'
                    : 'Đã lưu trên máy',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _details(bool disabled) => LayoutBuilder(
    builder: (context, constraints) {
      final tokens = StudioTokens.of(context);
      final rail = _rail(disabled);
      if (constraints.maxWidth >= 820) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 40),
                children: [_titleField(disabled), ..._main(disabled)],
              ),
            ),
            Container(
              width: 290,
              decoration: BoxDecoration(
                color: tokens.column.withValues(alpha: 0.55),
                border: Border(left: BorderSide(color: tokens.line)),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
                children: rail,
              ),
            ),
          ],
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
        children: [
          _titleField(disabled),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(StudioTokens.cardRadius),
              border: Border.all(color: tokens.line),
            ),
            child: Column(children: rail),
          ),
          ..._main(disabled),
        ],
      );
    },
  );

  Widget _titleField(bool disabled) => TextField(
    controller: title,
    enabled: !disabled,
    maxLines: null,
    onChanged: (v) => editor.change((i) => i.title = v),
    style: Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(fontSize: 21, height: 1.3),
    decoration: const InputDecoration(
      hintText: 'Tiêu đề',
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      filled: false,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(vertical: 6),
    ),
  );

  Widget _section(String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 8),
    child: Row(
      children: [
        Text(text, style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        ?trailing,
      ],
    ),
  );

  List<Widget> _main(bool disabled) {
    final item = editor.item;
    final theme = Theme.of(context);
    final tokens = StudioTokens.of(context);
    final children = related
        .where((i) => i.parentId == item.id && !i.archived)
        .toList();
    final checked = item.checklist.where((r) => r['done'] == true).length;
    return [
      if (item.status == WorkStatus.blocked)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          decoration: BoxDecoration(
            color: tokens.status(WorkStatus.blocked).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(StudioTokens.cardRadius),
            border: Border.all(
              color: tokens.status(WorkStatus.blocked).withValues(alpha: 0.4),
            ),
          ),
          child: TextFormField(
            initialValue: item.blockedReason,
            enabled: !disabled,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Lý do bị chặn và bước gỡ chặn',
              border: InputBorder.none,
              filled: false,
              icon: Icon(Icons.block, color: tokens.status(WorkStatus.blocked)),
            ),
            onChanged: (v) => editor.change((i) => i.blockedReason = v),
          ),
        ),
      _section(
        'Nội dung',
        trailing: SegmentedButton<bool>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            selectedBackgroundColor: theme.colorScheme.primary.withValues(
              alpha: 0.16,
            ),
            selectedForegroundColor: theme.colorScheme.primary,
          ),
          segments: const [
            ButtonSegment(value: false, label: Text('Viết')),
            ButtonSegment(value: true, label: Text('Xem')),
          ],
          selected: {preview},
          onSelectionChanged: (s) => setState(() => preview = s.single),
        ),
      ),
      if (preview)
        Container(
          key: const ValueKey('body-preview'),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 90),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(StudioTokens.cardRadius),
            border: Border.all(color: tokens.line),
          ),
          child: item.body.trim().isEmpty
              ? Text('Chưa có nội dung.', style: theme.textTheme.bodySmall)
              : MarkdownView(item.body),
        )
      else
        TextField(
          controller: body,
          enabled: !disabled,
          minLines: item.type == WorkType.plan ? 10 : 5,
          maxLines: null,
          onChanged: (v) => editor.change((i) => i.body = v),
          decoration: InputDecoration(
            hintText: item.type == WorkType.plan
                ? 'Nội dung plan · Markdown'
                : 'Mô tả, bước làm, quyết định… (hỗ trợ Markdown)',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(StudioTokens.cardRadius),
            ),
          ),
        ),
      if (item.type == WorkType.plan)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: disabled ? null : _tasks,
                icon: const Icon(Icons.playlist_add, size: 18),
                label: const Text('Tạo task từ plan'),
              ),
              OutlinedButton(
                onPressed: disabled || item.body.trim().isEmpty
                    ? null
                    : editor.checkpoint,
                child: const Text('Lưu phiên bản'),
              ),
            ],
          ),
        ),
      if (item.type == WorkType.note)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: disabled ? null : () => _menu('to-task'),
              icon: const Icon(Icons.check_box_outline_blank, size: 17),
              label: const Text('Chuyển thành Task'),
            ),
          ),
        ),
      if (children.isNotEmpty) ...[
        _section(
          'Task con',
          trailing: Text(
            '${children.where((i) => i.status == WorkStatus.done).length}/${children.length} hoàn tất',
            style: theme.textTheme.bodySmall,
          ),
        ),
        for (final child in children) _childRow(child),
      ],
      _section(
        'Checklist',
        trailing: item.checklist.isEmpty
            ? null
            : Text(
                '$checked/${item.checklist.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: StudioTokens.tabular,
                ),
              ),
      ),
      if (item.checklist.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: LinearProgressIndicator(
            value: checked / item.checklist.length,
            minHeight: 3,
            borderRadius: BorderRadius.circular(3),
            color: tokens.palette.success,
            backgroundColor: tokens.line,
          ),
        ),
      for (var n = 0; n < item.checklist.length; n++)
        Row(
          children: [
            Checkbox(
              value: item.checklist[n]['done'] == true,
              onChanged: disabled
                  ? null
                  : (v) => editor.change(
                      (i) => i.checklist[n]['done'] = v ?? false,
                    ),
            ),
            Expanded(
              child: Text(
                item.checklist[n]['text'] as String,
                style: item.checklist[n]['done'] == true
                    ? TextStyle(
                        color: tokens.muted,
                        decoration: TextDecoration.lineThrough,
                      )
                    : null,
              ),
            ),
            IconButton(
              tooltip: 'Bỏ mục checklist',
              style: tokens.quietIcon,
              onPressed: disabled
                  ? null
                  : () => editor.change((i) => i.checklist.removeAt(n)),
              icon: const Icon(Icons.close, size: 16),
            ),
          ],
        ),
      TextField(
        controller: checklist,
        enabled: !disabled,
        onSubmitted: (_) => _addChecklist(),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Thêm mục cần kiểm tra rồi Enter',
          prefixIcon: const Icon(Icons.add, size: 18),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          filled: false,
          suffixIcon: IconButton(
            tooltip: 'Thêm checklist',
            style: tokens.quietIcon,
            onPressed: disabled ? null : _addChecklist,
            icon: const Icon(Icons.keyboard_return, size: 16),
          ),
        ),
      ),
      ..._timeline(disabled),
    ];
  }

  Widget _childRow(WorkItem child) {
    final tokens = StudioTokens.of(context);
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        await showTicketEditor(context, widget.repository, child);
        await _related();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          children: [
            Icon(
              child.status == WorkStatus.done
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 16,
              color: tokens.status(child.status),
            ),
            const SizedBox(width: 10),
            Text(
              child.code,
              style: theme.textTheme.labelSmall?.copyWith(color: tokens.muted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                child.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (child.dueAtUtc != null) DeadlineChip(item: child),
          ],
        ),
      ),
    );
  }

  List<Widget> _timeline(bool disabled) {
    final item = editor.item;
    final theme = Theme.of(context);
    final tokens = StudioTokens.of(context);
    final entries = [
      for (final n in item.notes)
        (at: n['at'] as String, note: true, text: n['body'] as String),
      for (final a in item.activity)
        (at: a['at'] as String, note: false, text: a['text'] as String),
    ]..sort((a, b) => a.at.compareTo(b.at));
    final shown = allActivity || entries.length <= 12
        ? entries
        : entries.sublist(entries.length - 12);
    return [
      _section('Hoạt động & ghi chú'),
      if (shown.length < entries.length)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => allActivity = true),
            child: Text('Hiện toàn bộ ${entries.length} mục'),
          ),
        ),
      for (final e in shown)
        if (e.note)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: tokens.column,
              borderRadius: BorderRadius.circular(StudioTokens.cardRadius),
              border: Border.all(color: tokens.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 14,
                      color: tokens.muted,
                    ),
                    const SizedBox(width: 6),
                    Text('Ghi chú', style: theme.textTheme.labelMedium),
                    const Spacer(),
                    Text(_date(e.at), style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(e.text),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 6, color: tokens.faint),
                  ),
                ),
                Expanded(child: Text(e.text, style: theme.textTheme.bodySmall)),
                const SizedBox(width: 8),
                Text(_date(e.at), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
      const SizedBox(height: 10),
      CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _addNote,
        },
        child: TextField(
          controller: note,
          enabled: !disabled,
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(
            hintText:
                'Viết ghi chú, quyết định hoặc bước tiếp theo… (Ctrl+Enter)',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(StudioTokens.cardRadius),
            ),
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton.tonalIcon(
            onPressed: disabled ? null : _addNote,
            icon: const Icon(Icons.add_comment_outlined, size: 17),
            label: const Text('Thêm ghi chú'),
          ),
        ),
      ),
    ];
  }

  Widget _prop(
    String label,
    Widget value, {
    Key? key,
    void Function(BuildContext anchor)? onTap,
  }) => Builder(
    builder: (anchor) {
      final theme = Theme.of(context);
      final row = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 86,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(label, style: theme.textTheme.bodySmall),
              ),
            ),
            Expanded(child: value),
          ],
        ),
      );
      if (onTap == null) return KeyedSubtree(key: key, child: row);
      return InkWell(
        key: key,
        borderRadius: BorderRadius.circular(8),
        onTap: () => onTap(anchor),
        child: row,
      );
    },
  );

  List<Widget> _rail(bool disabled) {
    final item = editor.item;
    final theme = Theme.of(context);
    final tokens = StudioTokens.of(context);
    final now = DateTime.now();
    final parent = related.where((i) => i.id == item.parentId).firstOrNull;
    final project = projects.where((p) => p.id == item.projectId).firstOrNull;
    final active = reminders.where((r) => r.active).toList()
      ..sort((a, b) => a.eligibleAt.compareTo(b.eligibleAt));
    final labels = {
      for (final i in related)
        if (i.projectId == item.projectId) ...i.labels,
    }.toList()..sort();
    final accent = tokens.priority(item.priority);
    final canEdit = !disabled && !item.archived;
    final warnings = <(Color, String)>[];
    if (parent?.dueAt != null &&
        item.dueAt != null &&
        item.dueAt!.isAfter(parent!.dueAt!)) {
      warnings.add((
        tokens.palette.warning,
        'Sau hạn của plan ${parent.code} (${dueFull(parent)})',
      ));
    }
    if (item.type == WorkType.plan) {
      final late = overdueChildren(item, related, now);
      final nearest = nearestChildDue(item, related);
      final after = item.dueAt == null
          ? 0
          : related
                .where(
                  (i) =>
                      i.parentId == item.id &&
                      !i.archived &&
                      i.status != WorkStatus.done &&
                      i.dueAt != null &&
                      i.dueAt!.isAfter(item.dueAt!),
                )
                .length;
      if (late > 0) {
        warnings.add((tokens.palette.danger, '$late task con đã trễ hạn'));
      }
      if (after > 0) {
        warnings.add((
          tokens.palette.warning,
          '$after task con có hạn sau plan',
        ));
      }
      if (nearest != null) {
        warnings.add((
          tokens.muted,
          'Task gần hạn nhất: ${nearest.code} · ${dueLabel(nearest, now)}',
        ));
      }
    }
    return [
      _prop(
        'Trạng thái',
        Row(
          children: [
            Icon(Icons.circle, size: 9, color: tokens.status(item.status)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(item.status.label, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        key: const ValueKey('prop-status'),
        onTap: disabled
            ? null
            : (anchor) async {
                final s = await _pick<WorkStatus>(anchor, [
                  for (final s in WorkStatus.values)
                    PopupMenuItem(
                      value: s,
                      enabled: s != item.status,
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 9, color: tokens.status(s)),
                          const SizedBox(width: 10),
                          Text(s.label),
                        ],
                      ),
                    ),
                ]);
                if (s != null) editor.change((i) => i.status = s);
              },
      ),
      _prop(
        'Ưu tiên',
        Row(
          children: [
            Icon(
              accent == null ? Icons.flag_outlined : Icons.flag,
              size: 15,
              color: accent ?? tokens.muted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${item.priority} · ${_priorityNames[item.priority]}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        key: const ValueKey('prop-priority'),
        onTap: disabled
            ? null
            : (anchor) async {
                final p = await _pick<String>(anchor, [
                  for (final e in _priorityNames.entries)
                    CheckedPopupMenuItem(
                      value: e.key,
                      checked: e.key == item.priority,
                      child: Text('${e.key} · ${e.value}'),
                    ),
                ]);
                if (p != null) editor.change((i) => i.priority = p);
              },
      ),
      _prop(
        'Hạn',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Transform.translate(
              offset: const Offset(-6, -6),
              child: DueField(
                editor: editor,
                repository: widget.repository,
                disabled: !canEdit,
                dense: true,
              ),
            ),
            if (item.dueHistory.isNotEmpty)
              Text(
                'Đã dời ${item.dueHistory.length} lần',
                style: theme.textTheme.bodySmall,
              ),
            for (final (color, text) in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
          ],
        ),
      ),
      if (local != null)
        _prop(
          'Nhắc hẹn',
          Text(
            active.isEmpty
                ? 'Chưa đặt'
                : '${active.length} lịch · ${reminderCountdown(active.first.eligibleAt, now)}',
            style: active.isEmpty
                ? theme.textTheme.bodyMedium?.copyWith(color: tokens.muted)
                : null,
          ),
          key: const ValueKey('prop-reminders'),
          onTap: (anchor) => showStudioPopover<void>(
            context,
            anchor: rectOf(anchor),
            width: 480,
            builder: (_) => ListenableBuilder(
              listenable: editor,
              builder: (_, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ReminderScheduleEditor(
                  editor: editor,
                  repository: local!,
                  disabled: editor.busy || actionBusy,
                ),
              ),
            ),
          ).then((_) => _related()),
        ),
      _prop(
        'Nhãn',
        item.labels.isEmpty
            ? Text(
                'Thêm nhãn',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.muted,
                ),
              )
            : Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final l in item.labels)
                    StudioChip(
                      label: '#$l',
                      tone: tokens.tone(tokens.palette.info),
                    ),
                ],
              ),
        key: const ValueKey('prop-labels'),
        onTap: disabled
            ? null
            : (anchor) => showStudioPopover<void>(
                context,
                anchor: rectOf(anchor),
                width: 340,
                builder: (_) =>
                    LabelEditor(editor: editor, suggestions: labels),
              ),
      ),
      if (item.type == WorkType.task)
        _prop(
          'Plan gốc',
          Text(
            parent == null
                ? item.parentId == null
                      ? 'Không gắn plan'
                      : 'Đang tải plan gốc…'
                : '${parent.code} · ${parent.title}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: parent == null
                ? theme.textTheme.bodyMedium?.copyWith(color: tokens.muted)
                : null,
          ),
          key: const ValueKey('prop-parent'),
          onTap: disabled
              ? null
              : (anchor) async {
                  final plans = related.where(
                    (i) =>
                        i.type == WorkType.plan &&
                        i.projectId == item.projectId &&
                        (!i.archived || i.id == item.parentId),
                  );
                  final v = await _pick<String>(anchor, [
                    CheckedPopupMenuItem(
                      value: '',
                      checked: item.parentId == null,
                      child: const Text('Không gắn plan'),
                    ),
                    for (final plan in plans)
                      CheckedPopupMenuItem(
                        value: plan.id,
                        checked: plan.id == item.parentId,
                        child: Text(
                          '${plan.code} · ${plan.title}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ]);
                  if (v != null) {
                    editor.change((i) {
                      i.parentId = v == '' ? null : v;
                      i.sourceRevisionId = null;
                    });
                  }
                },
        ),
      _prop(
        'Dự án',
        Row(
          children: [
            Icon(Icons.folder_outlined, size: 15, color: tokens.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                project?.name ?? '—',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        key: const ValueKey('prop-project'),
        onTap: disabled ? null : (_) => _moveProject(),
      ),
      Divider(height: 24, color: tokens.line),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: DefaultTextStyle.merge(
          style: theme.textTheme.bodySmall,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tạo ${_date(item.createdAt)}'),
              const SizedBox(height: 3),
              Text('Cập nhật ${_date(item.updatedAt)}'),
              if (item.completedAt != null) ...[
                const SizedBox(height: 3),
                Text('Hoàn tất ${_date(item.completedAt!)}'),
              ],
              if (item.archived) ...[
                const SizedBox(height: 3),
                const Text('Đang lưu trữ'),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  Widget _composer(bool disabled) {
    final draft = editor.item.draft;
    final questions = draft['questions'] as List? ?? [];
    final answers = (draft['answers'] as List? ?? []).cast<String>();
    final model = draft['model'] as String?;
    final options = {...editor.models, ?model}.toList();
    Widget field(
      String label,
      TextEditingController controller,
      void Function(String) changed, {
      int lines = 1,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        onChanged: changed,
        enabled: !disabled,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 8,
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Từ yêu cầu đến kế hoạch rõ ràng',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Ollama local · yêu cầu và câu trả lời được lưu trên máy. Đường dẫn dự án là context; AI chưa tự đọc code.',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey(model),
                initialValue: model,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Model local'),
                items: [
                  for (final m in options)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: disabled
                    ? null
                    : (m) => editor.change((i) {
                        i.draft['model'] = m;
                        i.draft.remove('snapshot');
                      }),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Kết nối Ollama / tải model',
              onPressed: disabled ? null : editor.loadModels,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 24),
        field(
          'Yêu cầu gốc',
          source,
          (v) => editor.change((i) {
            i.draft['source'] = v;
            i.draft.remove('snapshot');
          }),
          lines: 4,
        ),
        field(
          'Context dự án',
          contextInput,
          (v) => editor.change((i) {
            i.draft['context'] = v;
            i.draft.remove('snapshot');
          }),
          lines: 2,
        ),
        FilledButton.icon(
          onPressed: disabled ? null : editor.clarify,
          icon: const Icon(Icons.auto_awesome),
          label: Text(
            questions.isEmpty ? '1. Làm rõ yêu cầu' : 'Làm rõ lại yêu cầu',
          ),
        ),
        const SizedBox(height: 24),
        for (var n = 0; n < questions.length; n++) ...[
          Text(
            '${n + 1}. ${questions[n]['question']}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in [
                ...questions[n]['options'] as List,
                'Chưa rõ — cần khảo sát',
              ])
                ChoiceChip(
                  label: Text(option as String),
                  selected: n < answers.length && answers[n] == option,
                  onSelected: disabled
                      ? null
                      : (_) => editor.change(
                          (i) => (i.draft['answers'] as List)[n] = option,
                        ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _AnswerField(
            key: ValueKey('answer-$n-${questions[n]['question']}'),
            value: n < answers.length ? answers[n] : '',
            enabled: !disabled,
            onChanged: (v) =>
                editor.change((i) => (i.draft['answers'] as List)[n] = v),
          ),
          const SizedBox(height: 24),
        ],
        if (draft['snapshot'] != null)
          FilledButton.icon(
            onPressed: disabled ? null : editor.generate,
            icon: const Icon(Icons.description_outlined),
            label: const Text('2. Chốt câu trả lời & tạo plan'),
          ),
        if (editor.item.body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Plan đã được lưu. Mở tab Chi tiết để chỉnh sửa hoặc tạo task.',
                    ),
                    const SizedBox(height: 12),
                    MarkdownView(editor.item.body),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _versions() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      if (editor.item.versions.isEmpty)
        Text(
          'Chưa có phiên bản. Dùng “Lưu phiên bản” hoặc tạo plan bằng AI; mỗi lần tạo lại đều giữ bản trước.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      for (final version in editor.item.versions.reversed)
        ExpansionTile(
          title: Text(version['label'] as String? ?? 'Phiên bản'),
          subtitle: Text(_date(version['at'] as String)),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: MarkdownView(version['body'] as String),
            ),
            TextButton(
              onPressed: editor.busy || actionBusy
                  ? null
                  : () {
                      editor.checkpoint();
                      editor.change((i) => i.body = version['body'] as String);
                    },
              child: const Text('Khôi phục nội dung phiên bản này'),
            ),
          ],
        ),
    ],
  );

  String _date(String value) {
    final d = DateTime.tryParse(value)?.toLocal();
    if (d == null) return value;
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _TaskListResult {
  const _TaskListResult(this.titles, this.inheritDue);
  final List<String> titles;
  final bool inheritDue;
}

class _TaskListDialog extends StatefulWidget {
  const _TaskListDialog({this.planDue});

  /// The plan's deadline, offered as the new tasks' deadline.
  final String? planDue;
  @override
  State<_TaskListDialog> createState() => _TaskListDialogState();
}

class _TaskListDialogState extends State<_TaskListDialog> {
  final input = TextEditingController();
  bool inherit = false;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tạo task từ plan'),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mỗi dòng là một task. Xem lại trước khi tạo; task trùng trong cùng phiên bản sẽ được bỏ qua.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: input,
            autofocus: true,
            minLines: 5,
            maxLines: 10,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Danh sách task'),
          ),
          if (widget.planDue != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: inherit,
              onChanged: (v) => setState(() => inherit = v ?? false),
              title: Text('Dùng hạn của plan (${widget.planDue})'),
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
        onPressed: input.text.trim().isEmpty
            ? null
            : () => Navigator.pop(
                context,
                _TaskListResult(
                  input.text
                      .split('\n')
                      .where((s) => s.trim().isNotEmpty)
                      .toList(),
                  inherit,
                ),
              ),
        child: const Text('Tạo các task'),
      ),
    ],
  );
}

class _AnswerField extends StatefulWidget {
  const _AnswerField({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  @override
  State<_AnswerField> createState() => _AnswerFieldState();
}

class _AnswerFieldState extends State<_AnswerField> {
  late final input = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(covariant _AnswerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (input.text != widget.value) {
      input.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: input,
    enabled: widget.enabled,
    onChanged: widget.onChanged,
    decoration: const InputDecoration(
      labelText: 'Câu trả lời (có thể nhập phương án khác)',
    ),
  );
}
