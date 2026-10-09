import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../controllers/plan_board_controller.dart';
import '../models/work_item.dart';
import '../repositories/local_plan_repository.dart';
import '../repositories/plan_repository.dart';
import '../services/deadline.dart';
import '../services/quick_add_parser.dart';
import '../theme/studio_tokens.dart';
import '../widgets/bulk_create_dialog.dart';
import '../widgets/deadline_picker.dart';
import '../widgets/kanban_column.dart';
import '../widgets/project_dialogs.dart';
import '../widgets/quick_add_field.dart';
import '../widgets/studio_palette.dart';
import '../widgets/studio_popover.dart';
import 'ticket_editor.dart';
import '../services/plan_studio_runtime.dart';
import 'reminder_settings_view.dart';
import 'today_view.dart';

Future<void> showPlanStudio(
  BuildContext context, {
  String? projectPath,
  String? initialItemId,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => PlanStudioView(
      initialProjectPath: projectPath,
      initialItemId: initialItemId,
    ),
  ),
);

enum BoardSort {
  manual('Thủ công'),
  due('Theo hạn'),
  priority('Theo ưu tiên');

  const BoardSort(this.label);
  final String label;
}

class PlanStudioView extends StatefulWidget {
  const PlanStudioView({
    super.key,
    this.initialProjectPath,
    this.repository,
    this.initialItemId,
  });
  final String? initialItemId;
  final String? initialProjectPath;
  final PlanRepository? repository;
  @override
  State<PlanStudioView> createState() => _PlanStudioViewState();
}

class _PlanStudioViewState extends State<PlanStudioView> {
  static const _collapsedKey = 'plan_studio.collapsed_columns';
  PlanBoardController? board;
  String? projectId, initError, label, priority;
  String query = '';
  WorkType? type;
  DueFilter? dueFilter;
  BoardSort sort = BoardSort.manual;
  bool archived = false, onlyBlocked = false;
  Set<String> collapsed = {};
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final scroll = ScrollController();
  final viewport = GlobalKey();
  final dragPosition = ValueNotifier<Offset?>(null);
  Timer? ticker, clockTicker;
  StreamSubscription<void>? changes;
  PlanStudioRuntime? runtime;
  @override
  void initState() {
    super.initState();
    _init();
    _loadCollapsed();
    clockTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    dragPosition.addListener(_dragChanged);
  }

  Future<void> _init() async {
    setState(() => initError = null);
    PlanRepository? repository;
    try {
      if (widget.repository == null) runtime = await PlanStudioRuntime.open();
      repository = widget.repository ?? runtime!.repository;
      if (widget.initialProjectPath != null) {
        projectId = (await repository.ensureProject(
          widget.initialProjectPath!,
        )).id;
      }
      final controller = PlanBoardController(repository);
      await controller.load();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => board = controller);
      if (repository is LocalPlanRepository) {
        changes = repository.changes.listen((_) {
          if (mounted) controller.load();
        });
      }
      if (widget.initialItemId != null) {
        final item = controller.items
            .where((i) => i.id == widget.initialItemId)
            .firstOrNull;
        if (item != null) {
          projectId = item.projectId;
          await _open(item);
        }
      }
    } catch (e) {
      if (mounted) setState(() => initError = '$e');
    }
  }

  // Collapsed columns are a per-machine view preference; losing it is harmless.
  Future<void> _loadCollapsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_collapsedKey);
      if (saved != null && mounted) setState(() => collapsed = saved.toSet());
    } catch (_) {}
  }

  String _columnKey(WorkStatus status) => '${projectId ?? '*'}|${status.name}';

  void _toggleColumn(WorkStatus status) {
    final key = _columnKey(status);
    setState(
      () =>
          collapsed.contains(key) ? collapsed.remove(key) : collapsed.add(key),
    );
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_collapsedKey, collapsed.toList());
      } catch (_) {}
    }());
  }

  void _dragChanged() {
    ticker?.cancel();
    if (dragPosition.value != null) {
      ticker = Timer.periodic(const Duration(milliseconds: 30), (_) {
        final box = viewport.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || dragPosition.value == null || !scroll.hasClients) {
          return;
        }
        final local = box.globalToLocal(dragPosition.value!);
        final delta = local.dx < 65
            ? -16.0
            : local.dx > box.size.width - 65
            ? 16.0
            : 0.0;
        if (delta != 0) {
          scroll.jumpTo(
            (scroll.offset + delta).clamp(0, scroll.position.maxScrollExtent),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    ticker?.cancel();
    dragPosition.removeListener(_dragChanged);
    dragPosition.dispose();
    scroll.dispose();
    search.dispose();
    searchFocus.dispose();
    changes?.cancel();
    clockTicker?.cancel();
    board?.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    try {
      await work();
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> _open(WorkItem item, {bool compose = false}) async {
    await showTicketEditor(context, board!.repository, item, compose: compose);
    if (mounted) await board!.load();
  }

  bool get _reminders => board?.repository is LocalPlanRepository;

  Set<int> _dueOffsets(WorkItem item) => {
    for (final r in board!.reminders)
      if (r.itemId == item.id && r.active && r.offsetMinutes != null)
        r.offsetMinutes!,
  };

  /// Saves a new ticket; blocked needs its reason before the first commit.
  Future<WorkItem?> _insert(
    String title,
    WorkType type,
    WorkStatus status, {
    DuePick? due,
    String? priority,
    List<String> labels = const [],
  }) async {
    if (projectId == null) {
      _message('Chọn một dự án trước khi tạo ticket.');
      return null;
    }
    final project = board!.projects.firstWhere((p) => p.id == projectId);
    final item = WorkItem(
      id: const Uuid().v4(),
      projectId: project.id,
      title: title,
      type: type,
      status: status,
      priority: priority ?? 'P2',
      labels: labels,
      draft: type == WorkType.plan
          ? {'context': '${project.name}\n${project.path}'}
          : {},
    );
    if (due?.at != null) setDue(item, due!.at, allDay: due.allDay);
    if (status == WorkStatus.blocked) {
      final reason = await _textDialog(
        'Lý do bị chặn',
        'Điều gì cần giải quyết để tiếp tục?',
      );
      if (reason == null) return null;
      item.blockedReason = reason;
    }
    final saved = await board!.commit(() => board!.repository.save(item));
    if (due != null && due.offsets.isNotEmpty) {
      final errors = await board!.commit(
        () => addDueReminders(board!.repository, saved, due.offsets),
      );
      if (errors.isNotEmpty) _message(errors.join('\n'));
    }
    return saved;
  }

  Future<void> _create({
    WorkType initialType = WorkType.task,
    WorkStatus status = WorkStatus.backlog,
  }) => _run(() async {
    if (projectId == null) {
      _message('Chọn một dự án trước khi tạo ticket.');
      return;
    }
    final result = await showDialog<_NewTicket>(
      context: context,
      builder: (_) =>
          _CreateTicketDialog(type: initialType, reminders: _reminders),
    );
    if (result == null) return;
    final saved = await _insert(
      result.title,
      result.type,
      status,
      due: result.due,
      priority: result.priority,
      labels: result.labels,
    );
    if (saved != null &&
        mounted &&
        (result.open || saved.type == WorkType.plan)) {
      await _open(saved, compose: saved.type == WorkType.plan);
    }
  });

  Future<void> _quickAdd(QuickAdd parsed, WorkStatus status) async {
    try {
      await _insert(
        parsed.title,
        WorkType.task,
        status,
        priority: parsed.priority,
        labels: parsed.labels,
        due: parsed.due == null
            ? null
            : DuePick(parsed.due, allDay: parsed.allDay),
      );
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> _bulkCreate({WorkStatus status = WorkStatus.backlog}) =>
      _run(() async {
        final projectId = this.projectId;
        if (projectId == null) {
          _message('Chọn một dự án trước khi tạo ticket.');
          return;
        }
        final drafts = await showBulkCreateDialog(
          context,
          projectId: projectId,
          items: board!.items.where((i) => i.projectId == projectId).toList(),
          status: status,
        );
        if (drafts == null || drafts.isEmpty) return;
        final created = await board!.commit(
          () => board!.repository.createMany(drafts),
        );
        _message('Đã tạo ${created.length} task.');
      });

  Future<void> _setDue(WorkItem item, Rect? anchor) => _run(() async {
    final pick = await showDeadlinePicker(
      context,
      item,
      anchor: anchor,
      reminders: _reminders && !item.archived && item.status != WorkStatus.done,
      existingOffsets: _dueOffsets(item),
    );
    if (pick == null) return;
    final errors = await board!.commit(
      () => applyDuePick(board!.repository, item, pick),
    );
    if (errors.isNotEmpty) _message(errors.join('\n'));
  });

  Future<void> _clearDue(WorkItem item) => _run(
    () => board!.commit(
      () => applyDuePick(board!.repository, item, const DuePick.clear()),
    ),
  );

  Future<void> _move(WorkItem item, WorkStatus status, String? before) =>
      _run(() async {
        var reason = item.blockedReason;
        if (status == WorkStatus.blocked && reason.trim().isEmpty) {
          final answer = await _textDialog(
            'Lý do bị chặn',
            'Điều gì cần giải quyết để tiếp tục?',
          );
          if (answer == null) return;
          reason = answer;
        }
        await board!.commit(
          () => board!.repository.move(
            item.id,
            item.revision,
            status,
            beforeId: before,
            reason: reason,
          ),
        );
      });

  Future<String?> _textDialog(String title, String hint, {String value = ''}) =>
      showDialog<String>(
        context: context,
        builder: (_) => _TextDialog(title: title, hint: hint, value: value),
      );

  /// Links a folder as a project (or finds the one already linked).
  Future<StudioProject?> _linkFolder() async {
    final path = await getDirectoryPath();
    if (path == null) return null;
    return board!.commit(() => board!.repository.ensureProject(path));
  }

  Future<void> _addProject() => _run(() async {
    final project = await _linkFolder();
    if (project != null && mounted) setState(() => projectId = project.id);
  });

  Future<void> _renameProject() => _run(() async {
    final project = board!.projects.where((p) => p.id == projectId).firstOrNull;
    if (project == null) return;
    final name = await showRenameProjectDialog(context, project);
    if (name == null) return;
    final renamed = await board!.commit(
      () => board!.repository.renameProject(project.id, name),
    );
    _message('Đã đổi tên dự án thành “${renamed.name}”.');
  });

  Future<void> _moveProject(WorkItem item) => _run(() async {
    final target = await showMoveToProjectDialog(
      context,
      item: item,
      projects: board!.projects,
      all: board!.items,
      addProject: () async {
        try {
          return await _linkFolder();
        } catch (e) {
          _message('$e');
          return null;
        }
      },
    );
    if (target == null) return;
    final moved = await board!.commit(
      () => board!.repository.moveToProject(
        item.id,
        item.revision,
        target.projectId,
        withChildren: target.withChildren,
      ),
    );
    if (!mounted || moved.isEmpty) return;
    final name = board!.projects
        .firstWhere((p) => p.id == target.projectId)
        .name;
    final what = moved.length == 1
        ? item.code
        : '${item.code} và ${moved.length - 1} task con';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã chuyển $what sang $name.'),
        action: projectId == null
            ? null
            : SnackBarAction(
                label: 'Mở dự án',
                onPressed: () => setState(() => projectId = target.projectId),
              ),
      ),
    );
  });

  Future<void> _menu(String action) => _run(() async {
    if (action == 'export') {
      final source = await board!.repository.exportBackup();
      final path = await getSaveLocation(
        suggestedName: 'plan-studio-backup.json',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (path != null) {
        await File(path.path).writeAsString(source, flush: true);
        _message('Đã xuất backup.');
      }
    } else if (action == 'import') {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'JSON backup', extensions: ['json']),
        ],
      );
      if (file == null) return;
      final source = await file.readAsString();
      final parsed = jsonDecode(source) as Map<String, dynamic>;
      if (![1, 2, 3].contains(parsed['schemaVersion']) ||
          parsed['tickets'] is! List ||
          parsed['projects'] is! List) {
        throw const FormatException('Backup không hợp lệ.');
      }
      final current = board!.items.map((i) => i.id).toSet();
      final count = (parsed['tickets'] as List).length;
      final conflicts = (parsed['tickets'] as List)
          .where((i) => current.contains(i['id']))
          .length;
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nhập backup'),
          content: Text(
            '$count ticket trong file; $conflicts ID đã tồn tại sẽ được bỏ qua. Chỉ thêm bản ghi mới. Xung đột dự án sẽ hủy toàn bộ lượt nhập.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Nhập'),
            ),
          ],
        ),
      );
      if (yes == true) {
        final added = await board!.commit(
          () => board!.repository.importBackup(source),
        );
        _message('Đã nhập $added ticket.');
      }
    } else if (action == 'markdown') {
      if (projectId == null) {
        _message('Chọn dự án trước khi nhập plan.');
        return;
      }
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Markdown', extensions: ['md', 'markdown']),
        ],
      );
      if (file == null) return;
      final body = await file.readAsString();
      final item = WorkItem(
        id: const Uuid().v4(),
        projectId: projectId!,
        title: file.name,
        type: WorkType.plan,
        body: body,
      );
      await board!.commit(() => board!.repository.save(item));
    } else if (action == 'relink') {
      if (projectId == null) return;
      final path = await getDirectoryPath();
      if (path != null) {
        await board!.commit(
          () => board!.repository.relinkProject(projectId!, path),
        );
      }
    } else if (action == 'rename') {
      await _renameProject();
    } else if (action == 'palette') {
      _palette();
    } else if (action == 'shortcuts') {
      await showShortcutHelp(context);
    } else if (action == 'reminders' && runtime != null) {
      await showReminderSettings(context, runtime!);
    }
  });

  void _openToday() {
    final repository = board?.repository;
    if (repository is! LocalPlanRepository) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TodayView(repository: repository, projectId: projectId),
      ),
    );
  }

  void _clearFilters() => setState(() {
    search.clear();
    query = '';
    label = priority = null;
    type = null;
    dueFilter = null;
    onlyBlocked = false;
  });

  void _palette() {
    final board = this.board;
    if (board == null) return;
    final now = DateTime.now();
    String projectName(String id) =>
        board.projects.where((p) => p.id == id).firstOrNull?.name ?? '';
    showStudioPalette(context, [
      PaletteEntry(
        icon: Icons.add,
        title: 'Tạo task',
        shortcut: 'N',
        run: () => _create(),
      ),
      PaletteEntry(
        icon: Icons.playlist_add,
        title: 'Tạo task hàng loạt',
        shortcut: 'Shift+N',
        run: () => _bulkCreate(),
      ),
      PaletteEntry(
        icon: Icons.sticky_note_2_outlined,
        title: 'Tạo note',
        run: () => _create(initialType: WorkType.note),
      ),
      PaletteEntry(
        icon: Icons.auto_awesome,
        title: 'Tạo plan bằng AI',
        run: () => _create(initialType: WorkType.plan),
      ),
      if (board.repository is LocalPlanRepository)
        PaletteEntry(
          icon: Icons.today_outlined,
          title: 'Mở Hôm nay',
          run: _openToday,
        ),
      PaletteEntry(
        icon: Icons.warning_amber_rounded,
        title: 'Lọc: quá hạn',
        run: () => setState(() => dueFilter = DueFilter.overdue),
      ),
      PaletteEntry(
        icon: Icons.schedule,
        title: 'Lọc: đến hạn 7 ngày tới',
        run: () => setState(() => dueFilter = DueFilter.week),
      ),
      PaletteEntry(
        icon: Icons.block,
        title: 'Lọc: bị chặn',
        run: () => setState(() => onlyBlocked = true),
      ),
      PaletteEntry(
        icon: Icons.swap_vert,
        title: 'Sắp theo hạn',
        run: () => setState(() => sort = BoardSort.due),
      ),
      PaletteEntry(
        icon: Icons.filter_alt_off_outlined,
        title: 'Xóa bộ lọc',
        run: _clearFilters,
      ),
      PaletteEntry(
        icon: Icons.inventory_2_outlined,
        title: archived ? 'Quay lại board đang làm' : 'Xem ticket lưu trữ',
        run: () => setState(() => archived = !archived),
      ),
      for (final p in board.projects)
        PaletteEntry(
          icon: Icons.folder_outlined,
          title: 'Chuyển dự án: ${p.name}',
          subtitle: p.path,
          run: () => setState(() => projectId = p.id),
        ),
      if (projectId != null)
        PaletteEntry(
          icon: Icons.edit_outlined,
          title: 'Đổi tên dự án hiện tại',
          run: _renameProject,
        ),
      PaletteEntry(
        icon: Icons.keyboard_outlined,
        title: 'Phím tắt',
        shortcut: '?',
        run: () => showShortcutHelp(context),
      ),
      PaletteEntry(
        icon: Icons.download_outlined,
        title: 'Xuất backup JSON',
        run: () => _menu('export'),
      ),
      for (final i in board.items)
        if (!i.archived && (projectId == null || i.projectId == projectId))
          PaletteEntry(
            ticket: true,
            icon: workTypeIcon(i.type),
            title: '${i.code} · ${i.title}',
            subtitle: [
              i.status.label,
              if (i.dueAtUtc != null) 'Hạn ${dueLabel(i, now)}',
              if (projectId == null) projectName(i.projectId),
            ].join(' · '),
            run: () => _open(i),
          ),
    ]);
  }

  /// Board shortcuts. Ctrl+K works everywhere; single keys are skipped while a
  /// text field has focus so typing is never swallowed.
  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || board == null) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyK) {
      _palette();
      return KeyEventResult.handled;
    }
    final focus = FocusManager.instance.primaryFocus?.context;
    final typing =
        focus != null &&
        (focus.widget is EditableText ||
            focus.findAncestorStateOfType<EditableTextState>() != null);
    if (typing ||
        keys.isControlPressed ||
        keys.isAltPressed ||
        keys.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    switch (event.character) {
      case '/':
        searchFocus.requestFocus();
        return KeyEventResult.handled;
      case '?':
        showShortcutHelp(context);
        return KeyEventResult.handled;
      case 'n' || 'N' when !archived:
        if (keys.isShiftPressed) {
          _bulkCreate();
        } else {
          _create();
        }
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: board == null
          ? Center(
              child: initError == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Không mở được kho Plan Studio:\n$initError',
                          textAlign: TextAlign.center,
                        ),
                        TextButton(
                          onPressed: _init,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
            )
          : Focus(
              autofocus: true,
              onKeyEvent: _key,
              child: AnimatedBuilder(
                animation: board!,
                builder: (context, _) => _content(),
              ),
            ),
    ),
  );

  List<WorkItem> _sorted(List<WorkItem> items) {
    int rank(String p) => ['P0', 'P1', 'P2', 'P3'].indexOf(p);
    return switch (sort) {
      BoardSort.manual => items,
      BoardSort.due =>
        items..sort((a, b) {
          final d = (a.dueAt ?? DateTime(9999)).compareTo(
            b.dueAt ?? DateTime(9999),
          );
          return d != 0 ? d : rank(a.priority).compareTo(rank(b.priority));
        }),
      BoardSort.priority =>
        items..sort((a, b) {
          final p = rank(a.priority).compareTo(rank(b.priority));
          return p != 0 ? p : a.order.compareTo(b.order);
        }),
    };
  }

  Widget _content() {
    final board = this.board!;
    final scheme = Theme.of(context).colorScheme;
    final tokens = StudioTokens.of(context);
    final now = DateTime.now();
    final inProject = board.items
        .where((i) => projectId == null || i.projectId == projectId)
        .toList();
    final open = inProject.where((i) => !i.archived).toList();
    final scoped = inProject.where((i) => i.archived == archived).toList();
    final q = query.toLowerCase();
    final filtered = scoped
        .where(
          (i) =>
              (type == null || i.type == type) &&
              (priority == null || i.priority == priority) &&
              (label == null || i.labels.contains(label)) &&
              (dueFilter == null || matchesDueFilter(i, dueFilter!, now)) &&
              (!onlyBlocked || i.status == WorkStatus.blocked) &&
              '${i.code} ${i.title} ${i.body} ${i.labels.join(' ')}'
                  .toLowerCase()
                  .contains(q),
        )
        .toList();
    final filtering =
        query.isNotEmpty ||
        label != null ||
        type != null ||
        priority != null ||
        dueFilter != null ||
        onlyBlocked;
    final reorder = !filtering && sort == BoardSort.manual;
    final canMove =
        projectId != null && !archived && !board.writing && !board.loading;
    final overdue = open
        .where((i) => dueState(i, now) == DueState.overdue)
        .length;
    final week = open
        .where((i) => matchesDueFilter(i, DueFilter.week, now))
        .length;
    final blocked = open.where((i) => i.status == WorkStatus.blocked).length;
    final labels = {for (final i in open) ...i.labels}.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(
          board,
          dueSoon:
              overdue +
              open.where((i) => dueState(i, now) == DueState.today).length,
        ),
        SizedBox(
          height: 2,
          child: board.writing || board.loading
              ? const LinearProgressIndicator(minHeight: 2)
              : null,
        ),
        if (runtime != null) _runtimeBanner(scheme),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (overdue > 0 || dueFilter == DueFilter.overdue)
                _Pill(
                  key: const ValueKey('health-overdue'),
                  icon: Icons.warning_amber_rounded,
                  text: '$overdue quá hạn',
                  tone: tokens.due(DueState.overdue),
                  selected: dueFilter == DueFilter.overdue,
                  onTap: () => setState(
                    () => dueFilter = dueFilter == DueFilter.overdue
                        ? null
                        : DueFilter.overdue,
                  ),
                ),
              if (week > 0 || dueFilter == DueFilter.week)
                _Pill(
                  key: const ValueKey('health-week'),
                  icon: Icons.schedule,
                  text: '$week đến hạn 7 ngày',
                  tone: tokens.due(DueState.today),
                  selected: dueFilter == DueFilter.week,
                  onTap: () => setState(
                    () => dueFilter = dueFilter == DueFilter.week
                        ? null
                        : DueFilter.week,
                  ),
                ),
              if (blocked > 0 || onlyBlocked)
                _Pill(
                  key: const ValueKey('health-blocked'),
                  icon: Icons.block,
                  text: '$blocked bị chặn',
                  tone: tokens.tone(tokens.status(WorkStatus.blocked)),
                  selected: onlyBlocked,
                  onTap: () => setState(() => onlyBlocked = !onlyBlocked),
                ),
              if (overdue + week + blocked > 0 ||
                  dueFilter != null ||
                  onlyBlocked)
                Container(
                  width: 1,
                  height: 20,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: tokens.line,
                ),
              _FilterMenu<WorkType>(
                label: 'Loại',
                value: type,
                options: workTypeLabels,
                onChanged: (v) => setState(() => type = v),
              ),
              _FilterMenu<String>(
                label: 'Ưu tiên',
                value: priority,
                options: const {'P0': 'P0', 'P1': 'P1', 'P2': 'P2', 'P3': 'P3'},
                onChanged: (v) => setState(() => priority = v),
              ),
              _FilterMenu<String>(
                label: 'Nhãn',
                value: label,
                options: {for (final l in labels) l: l},
                empty: 'Chưa có nhãn nào',
                onChanged: (v) => setState(() => label = v),
              ),
              _FilterMenu<DueFilter>(
                label: 'Hạn',
                value: dueFilter,
                options: {for (final f in DueFilter.values) f: f.label},
                onChanged: (v) => setState(() => dueFilter = v),
              ),
              _FilterMenu<BoardSort>(
                label: 'Sắp',
                value: sort,
                options: {for (final s in BoardSort.values) s: s.label},
                clearable: false,
                icon: Icons.swap_vert,
                onChanged: (v) => setState(() => sort = v!),
              ),
              _Pill(
                icon: Icons.inventory_2_outlined,
                text: 'Lưu trữ',
                selected: archived,
                onTap: () => setState(() => archived = !archived),
              ),
              if (filtering)
                TextButton(
                  onPressed: _clearFilters,
                  child: const Text('Xóa lọc'),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  projectId == null
                      ? 'Chọn một dự án để tạo và kéo thả ticket.'
                      : archived
                      ? 'Đang xem lưu trữ · mở ticket để khôi phục.'
                      : reorder
                      ? ''
                      : 'Đang lọc/sắp · kéo chỉ để đổi cột.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        if (board.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: SelectableText(
              board.error!,
              style: TextStyle(color: scheme.error),
            ),
          ),
        Expanded(
          child: SizedBox(
            key: viewport,
            child: Scrollbar(
              controller: scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final status in WorkStatus.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: KanbanColumn(
                          status: status,
                          items: _sorted(
                            filtered.where((i) => i.status == status).toList(),
                          ),
                          all: board.items,
                          reminders: board.reminders,
                          collapsed: collapsed.contains(_columnKey(status)),
                          onToggleCollapse: () => _toggleColumn(status),
                          onOpen: (i) => _open(i),
                          onMove: _move,
                          onDue: _setDue,
                          onClearDue: _clearDue,
                          onMoveProject: board.writing || board.loading
                              ? null
                              : _moveProject,
                          projectLabel: projectId == null
                              ? (i) => board.projects
                                    .where((p) => p.id == i.projectId)
                                    .firstOrNull
                                    ?.name
                              : null,
                          onCreate: canMove
                              ? () => _create(status: status)
                              : null,
                          onQuickAdd: canMove
                              ? (parsed) => _quickAdd(parsed, status)
                              : null,
                          dragPosition: dragPosition,
                          enabled: canMove,
                          reorder: reorder && canMove,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _runtimeBanner(ColorScheme scheme) => ListenableBuilder(
    listenable: runtime!,
    builder: (context, _) {
      final message =
          runtime!.error ??
          runtime!.scheduler?.error ??
          PlanStudioRuntime.startupError.value;
      if (message == null && runtime!.scheduler != null && !runtime!.paused) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Row(
          children: [
            Icon(
              Icons.notifications_paused_outlined,
              size: 16,
              color: message == null ? scheme.onSurfaceVariant : scheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message ??
                    (runtime!.paused
                        ? 'Nhắc hẹn đang tạm ngưng.'
                        : 'Nhắc hẹn chưa khởi động.'),
                style: TextStyle(
                  color: message == null
                      ? scheme.onSurfaceVariant
                      : scheme.error,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _toolbar(PlanBoardController board, {required int dueSoon}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final project = board.projects.where((p) => p.id == projectId).firstOrNull;
    final picker = PopupMenuButton<String>(
      tooltip: 'Chọn dự án',
      enabled: !board.writing,
      onSelected: (v) => switch (v) {
        '+add' => _addProject(),
        '+rename' => _renameProject(),
        _ => setState(() => projectId = v == '' ? null : v),
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: '',
          checked: projectId == null,
          child: const Text('Tất cả dự án'),
        ),
        for (final p in board.projects)
          CheckedPopupMenuItem(
            value: p.id,
            checked: p.id == projectId,
            child: Text(p.name, overflow: TextOverflow.ellipsis),
          ),
        const PopupMenuDivider(),
        if (project != null)
          PopupMenuItem(
            value: '+rename',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined, size: 18),
              title: Text(
                'Đổi tên “${project.name}”…',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        const PopupMenuItem(
          value: '+add',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.create_new_folder_outlined, size: 18),
            title: Text('Thêm dự án…'),
          ),
        ),
      ],
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                project?.name ?? 'Tất cả dự án',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
    final searchField = SizedBox(
      height: 36,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (query.isNotEmpty) setState(() => query = '');
            search.clear();
            searchFocus.unfocus();
          },
        },
        child: TextField(
          controller: search,
          focusNode: searchFocus,
          onChanged: (v) => setState(() => query = v),
          onSubmitted: (_) => searchFocus.unfocus(),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: scheme.surfaceContainerLow,
            hintText: 'Tìm ticket…',
            prefixIcon: const Icon(Icons.search, size: 18),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
            suffixIcon: query.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(9),
                    child: Container(
                      width: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Text('/', style: theme.textTheme.bodySmall),
                    ),
                  )
                : IconButton(
                    tooltip: 'Xóa tìm kiếm',
                    iconSize: 16,
                    onPressed: () => setState(() {
                      search.clear();
                      query = '';
                    }),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
      ),
    );
    final today = board.repository is LocalPlanRepository
        ? IconButton(
            tooltip: 'Hôm nay',
            onPressed: _openToday,
            icon: Badge(
              isLabelVisible: dueSoon > 0,
              label: Text('$dueSoon'),
              child: const Icon(Icons.today_outlined),
            ),
          )
        : null;
    final create = _CreateButton(
      onCreate: archived ? null : (t) => _create(initialType: t),
      onBulk: archived ? null : _bulkCreate,
    );
    final more = PopupMenuButton<String>(
      tooltip: 'Backup và dữ liệu',
      onSelected: _menu,
      icon: const Icon(Icons.more_horiz),
      itemBuilder: (_) => [
        const PopupMenuItem(
          enabled: false,
          height: 32,
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 15),
              SizedBox(width: 8),
              Text('Dữ liệu lưu trên máy này'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'palette',
          child: Text('Bảng lệnh  ·  Ctrl+K'),
        ),
        const PopupMenuItem(value: 'shortcuts', child: Text('Phím tắt  ·  ?')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'export', child: Text('Xuất backup JSON')),
        const PopupMenuItem(value: 'import', child: Text('Nhập backup JSON')),
        const PopupMenuItem(
          value: 'markdown',
          child: Text('Nhập plan Markdown'),
        ),
        PopupMenuItem(
          value: 'rename',
          enabled: projectId != null,
          child: const Text('Đổi tên dự án…'),
        ),
        PopupMenuItem(
          value: 'relink',
          enabled: projectId != null,
          child: const Text('Gắn lại thư mục dự án'),
        ),
        if (Platform.isWindows && runtime != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'reminders',
            child: Text('Cài đặt nhắc hẹn'),
          ),
        ],
      ],
    );
    final title = Text(
      'Plan Studio',
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
    final back = Navigator.of(context).canPop()
        ? const BackButton()
        : const SizedBox(width: 8);
    return Container(
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor ?? scheme.surface,
        border: Border(
          bottom: BorderSide(color: StudioTokens.of(context).line),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return Row(
              children: [
                back,
                title,
                const SizedBox(width: 16),
                Flexible(child: picker),
                const Spacer(),
                SizedBox(width: 280, child: searchField),
                const SizedBox(width: 8),
                ?today,
                const SizedBox(width: 8),
                create,
                more,
              ],
            );
          }
          return Column(
            children: [
              Row(
                children: [back, title, const Spacer(), ?today, create, more],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  children: [
                    Flexible(child: picker),
                    const SizedBox(width: 8),
                    Expanded(child: searchField),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "+ Tạo task" with a menu for the other types and bulk create.
class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.onCreate, required this.onBulk});
  final ValueChanged<WorkType>? onCreate;
  final VoidCallback? onBulk;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onCreate != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Tạo task (N)',
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
              ),
            ),
            onPressed: enabled ? () => onCreate!(WorkType.task) : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Tạo task'),
          ),
        ),
        const SizedBox(width: 1),
        PopupMenuButton<Object>(
          tooltip: 'Tạo loại khác',
          enabled: enabled,
          onSelected: (v) =>
              v == _bulk ? onBulk?.call() : onCreate?.call(v as WorkType),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: WorkType.task,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.check_box_outline_blank, size: 18),
                title: Text('Task'),
              ),
            ),
            PopupMenuItem(
              value: WorkType.note,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.sticky_note_2_outlined, size: 18),
                title: Text('Note'),
              ),
            ),
            PopupMenuItem(
              value: WorkType.plan,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.auto_awesome, size: 18),
                title: Text('Plan bằng AI'),
              ),
            ),
            PopupMenuDivider(),
            PopupMenuItem(
              value: _bulk,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.playlist_add, size: 18),
                title: Text('Tạo hàng loạt'),
                trailing: Text('Shift+N'),
              ),
            ),
          ],
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: enabled
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(8),
              ),
            ),
            child: Icon(
              Icons.expand_more,
              size: 18,
              color: enabled
                  ? scheme.onPrimary
                  : scheme.onSurface.withValues(alpha: 0.38),
            ),
          ),
        ),
      ],
    );
  }
}

/// Toolbar pill: neutral by default, tinted when [selected] or given a [tone].
class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.text,
    this.icon,
    this.tone,
    this.selected = false,
    this.trailing,
    this.onTap,
  });
  final String text;
  final IconData? icon;
  final ToneColors? tone;
  final bool selected;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = tone?.fg ?? (selected ? scheme.primary : scheme.onSurface);
    final bg = selected
        ? (tone?.fg ?? scheme.primary).withValues(alpha: 0.16)
        : tone?.bg ?? Colors.transparent;
    final border = selected
        ? (tone?.fg ?? scheme.primary).withValues(alpha: 0.6)
        : tone?.border ?? scheme.outlineVariant;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                text,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontFeatures: StudioTokens.tabular,
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.clearable = true,
    this.icon,
    this.empty,
  });
  final String label;
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T?> onChanged;
  final bool clearable;
  final IconData? icon;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final active = clearable && value != null;
    final text = value == null ? label : '$label: ${options[value] ?? value}';
    return PopupMenuButton<Object>(
      tooltip: 'Lọc theo ${label.toLowerCase()}',
      onSelected: (v) => onChanged(v == _clear ? null : v as T),
      itemBuilder: (_) => [
        if (active) const PopupMenuItem(value: _clear, child: Text('Bỏ lọc')),
        if (options.isEmpty && empty != null)
          PopupMenuItem(enabled: false, child: Text(empty!)),
        for (final e in options.entries)
          CheckedPopupMenuItem<Object>(
            value: e.key as Object,
            checked: e.key == value,
            child: Text(e.value),
          ),
      ],
      child: IgnorePointer(
        child: _Pill(
          icon: icon,
          text: text,
          selected: active,
          trailing: const Padding(
            padding: EdgeInsets.only(left: 2),
            child: Icon(Icons.expand_more, size: 16),
          ),
          onTap: () {},
        ),
      ),
    );
  }
}

const _clear = Object();
const _bulk = Object();

class _NewTicket {
  const _NewTicket(
    this.title,
    this.type, {
    this.due,
    this.priority,
    this.labels = const [],
    this.open = false,
  });
  final String title;
  final WorkType type;
  final DuePick? due;
  final String? priority;
  final List<String> labels;

  /// Ctrl+Enter / "Tạo & mở": open the editor after creating.
  final bool open;
}

class _CreateTicketDialog extends StatefulWidget {
  const _CreateTicketDialog({required this.type, this.reminders = false});
  final WorkType type;
  final bool reminders;
  @override
  State<_CreateTicketDialog> createState() => _CreateTicketDialogState();
}

class _CreateTicketDialogState extends State<_CreateTicketDialog> {
  final title = QuickAddController();
  late WorkType type = widget.type;
  DuePick? due;
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  WorkItem get _draft {
    final item = WorkItem(id: '', projectId: '', title: '-');
    if (due?.at != null) setDue(item, due!.at, allDay: due!.allDay);
    return item;
  }

  Future<void> _pickDue(BuildContext button) async {
    final pick = await showDeadlinePicker(
      context,
      _draft,
      anchor: rectOf(button),
      reminders: widget.reminders,
    );
    if (pick != null) setState(() => due = pick.at == null ? null : pick);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            _submit(open: true),
      },
      child: AlertDialog(
        title: const Text('Tạo mới'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<WorkType>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: scheme.primary.withValues(
                    alpha: 0.16,
                  ),
                  selectedForegroundColor: scheme.primary,
                  foregroundColor: scheme.onSurface,
                ),
                segments: [
                  for (final t in [WorkType.task, WorkType.note, WorkType.plan])
                    ButtonSegment(
                      value: t,
                      icon: Icon(workTypeIcon(t), size: 16),
                      label: Text(
                        t == WorkType.plan
                            ? 'Plan bằng AI'
                            : workTypeLabels[t]!,
                      ),
                    ),
                ],
                selected: {type},
                onSelectionChanged: (s) => setState(() => type = s.single),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: title,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Tiêu đề',
                  hintText: 'Viết test thanh toán  $quickAddHint',
                  border: OutlineInputBorder(),
                ),
              ),
              if (title.parsed.hasProperties)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: QuickAddSummary(title.parsed),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Builder(
                    builder: (button) => OutlinedButton.icon(
                      key: const ValueKey('create-due'),
                      onPressed: () => _pickDue(button),
                      icon: const Icon(Icons.event_outlined, size: 17),
                      label: Text(
                        due?.at == null
                            ? 'Đặt hạn'
                            : '${dueFullAt(due!.at!, allDay: due!.allDay)}'
                                  '${due!.offsets.isEmpty ? '' : ' · ${due!.offsets.length} nhắc'}',
                      ),
                    ),
                  ),
                  if (due != null)
                    IconButton(
                      tooltip: 'Bỏ hạn',
                      iconSize: 17,
                      onPressed: () => setState(() => due = null),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Enter để tạo · Ctrl+Enter để tạo và mở chi tiết\n'
                '!p0–!p3 ưu tiên · #nhãn · ^mai, ^t6, ^25/10 17h cho hạn',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: title.parsed.title.isEmpty
                ? null
                : () => _submit(open: true),
            child: const Text('Tạo & mở'),
          ),
          FilledButton(
            onPressed: title.parsed.title.isEmpty ? null : _submit,
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
  }

  /// A deadline picked with the button wins over one typed inline.
  void _submit({bool open = false}) {
    final parsed = title.parsed;
    if (parsed.title.isEmpty) return;
    Navigator.pop(
      context,
      _NewTicket(
        parsed.title,
        type,
        due:
            due ??
            (parsed.due == null
                ? null
                : DuePick(parsed.due, allDay: parsed.allDay)),
        priority: parsed.priority,
        labels: parsed.labels,
        open: open,
      ),
    );
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.hint, this.value = ''});
  final String title, hint, value;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final input = TextEditingController(text: widget.value);
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: input,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(hintText: widget.hint),
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
            : () => Navigator.pop(context, input.text.trim()),
        child: const Text('Lưu'),
      ),
    ],
  );
}
