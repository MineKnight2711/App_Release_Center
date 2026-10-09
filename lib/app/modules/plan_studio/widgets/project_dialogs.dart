import 'package:flutter/material.dart';
import '../models/work_item.dart';
import '../theme/studio_tokens.dart';

Future<String?> showRenameProjectDialog(
  BuildContext context,
  StudioProject project,
) => showDialog<String>(
  context: context,
  builder: (_) => _RenameDialog(project: project),
);

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.project});
  final StudioProject project;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final input = TextEditingController(text: widget.project.name)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.project.name.length,
    );

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  String get _clean => input.text.trim().replaceAll(RegExp(r'\s+'), ' ');
  String? get _error => _clean.isEmpty
      ? 'Nhập tên dự án.'
      : _clean.length > 80
      ? 'Tối đa 80 ký tự.'
      : null;

  void _submit() {
    if (_error == null) Navigator.pop(context, _clean);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Đổi tên dự án'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('rename-project'),
            controller: input,
            autofocus: true,
            maxLength: 80,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Tên hiển thị',
              errorText: input.text.isEmpty ? null : _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.folder_outlined, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.project.path,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Chỉ đổi tên hiển thị. Thư mục và ticket giữ nguyên.',
            style: Theme.of(context).textTheme.bodySmall,
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
        onPressed: _error == null && _clean != widget.project.name
            ? _submit
            : null,
        child: const Text('Đổi tên'),
      ),
    ],
  );
}

class MoveTarget {
  const MoveTarget(this.projectId, {this.withChildren = true});
  final String projectId;
  final bool withChildren;
}

/// Picks the destination project for [item]. [addProject] lets the user link a
/// new folder without leaving the dialog; it returns null when cancelled.
Future<MoveTarget?> showMoveToProjectDialog(
  BuildContext context, {
  required WorkItem item,
  required List<StudioProject> projects,
  required List<WorkItem> all,
  Future<StudioProject?> Function()? addProject,
}) => showDialog<MoveTarget>(
  context: context,
  builder: (_) => _MoveDialog(
    item: item,
    projects: projects,
    all: all,
    addProject: addProject,
  ),
);

class _MoveDialog extends StatefulWidget {
  const _MoveDialog({
    required this.item,
    required this.projects,
    required this.all,
    this.addProject,
  });
  final WorkItem item;
  final List<StudioProject> projects;
  final List<WorkItem> all;
  final Future<StudioProject?> Function()? addProject;
  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  late final projects = [...widget.projects];
  String? target;
  bool withChildren = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = StudioTokens.of(context);
    final item = widget.item;
    final others = projects.where((p) => p.id != item.projectId).toList();
    final current = projects.where((p) => p.id == item.projectId).firstOrNull;
    final children = widget.all.where((i) => i.parentId == item.id).length;
    final parent = widget.all.where((i) => i.id == item.parentId).firstOrNull;
    return AlertDialog(
      title: Text('Chuyển ${item.code} sang dự án khác'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '“${item.title}” · đang ở ${current?.name ?? 'dự án không xác định'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (others.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Chưa có dự án nào khác. Thêm thư mục dự án để chuyển tới.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: Material(
                  color: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      StudioTokens.cardRadius,
                    ),
                    side: BorderSide(color: tokens.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in others)
                        ListTile(
                          key: ValueKey('move-to-${p.id}'),
                          dense: true,
                          selected: target == p.id,
                          selectedTileColor: theme.colorScheme.primary
                              .withValues(alpha: 0.12),
                          leading: Icon(
                            target == p.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 20,
                          ),
                          title: Text(p.name),
                          subtitle: Text(
                            p.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => setState(() => target = p.id),
                        ),
                    ],
                  ),
                ),
              ),
            if (widget.addProject != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final added = await widget.addProject!();
                    if (added == null || !mounted) return;
                    setState(() {
                      projects.removeWhere((p) => p.id == added.id);
                      projects.add(added);
                      if (added.id != item.projectId) target = added.id;
                    });
                  },
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text('Thêm dự án…'),
                ),
              ),
            if (item.type == WorkType.plan && children > 0)
              CheckboxListTile(
                key: const ValueKey('move-with-children'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: withChildren,
                onChanged: (v) => setState(() => withChildren = v ?? true),
                title: Text('Chuyển kèm $children task con'),
                subtitle: Text(
                  withChildren
                      ? 'Task con giữ liên kết với plan.'
                      : 'Task con ở lại dự án cũ và bỏ liên kết với plan.',
                ),
              ),
            if (parent != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.link_off,
                      size: 16,
                      color: tokens.palette.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Task sẽ bỏ liên kết với plan ${parent.code} vì plan vẫn ở dự án cũ.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.palette.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Mã ticket, trạng thái, hạn và nhắc hẹn được giữ nguyên.',
              style: theme.textTheme.bodySmall,
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
          onPressed: target == null
              ? null
              : () => Navigator.pop(
                  context,
                  MoveTarget(target!, withChildren: withChildren),
                ),
          child: const Text('Chuyển'),
        ),
      ],
    );
  }
}
