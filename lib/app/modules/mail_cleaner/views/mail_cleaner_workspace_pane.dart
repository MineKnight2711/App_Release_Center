import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/mail_cleaner_controller.dart';
import '../models/mail_item.dart';
import '../../shared/module_widgets.dart';
import '../widgets/mail_cleaner_widgets.dart';

/// The working surface once a mailbox is open: what the scan found on the
/// right, the rules that pick messages out on the left, and the two-step
/// deletion along the bottom.
class MailCleanerWorkspacePane extends StatefulWidget {
  const MailCleanerWorkspacePane({
    super.key,
    required this.controller,
    required this.showLog,
  });

  final MailCleanerController controller;

  /// Whether the log console is pulled open; the page's app bar toggles it.
  final bool showLog;

  @override
  State<MailCleanerWorkspacePane> createState() =>
      _MailCleanerWorkspacePaneState();
}

class _MailCleanerWorkspacePaneState extends State<MailCleanerWorkspacePane> {
  final _groupFilter = TextEditingController();

  MailCleanerController get controller => widget.controller;

  @override
  void dispose() {
    _groupFilter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ContextBar(controller: controller),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 330, child: _SidePanel(controller: controller)),
              const VerticalDivider(width: 1),
              Expanded(
                child: _MainArea(
                  controller: controller,
                  groupFilter: _groupFilter,
                  onFilterChanged: () => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        if (widget.showLog) ...[
          const Divider(height: 1),
          _LogPanel(controller: controller),
        ],
        const Divider(height: 1),
        _ActionBar(controller: controller),
      ],
    );
  }
}

// ------------------------------------------------------------- context bar

class _ContextBar extends StatelessWidget {
  const _ContextBar({required this.controller});

  final MailCleanerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Flexible plus ellipsis: a long address or host must not be allowed
          // to push the folder picker off the bar.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  controller.account,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  '${controller.host}:${controller.port}',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _FolderPicker(controller: controller),
          const SizedBox(width: 10),
          if (controller.isGmail)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: StatusChip(label: 'Gmail', icon: Icons.mail_outline),
            ),
          StatusChip(
            label: controller.deleteIsRecoverable
                ? 'Khôi phục được'
                : 'Xoá vĩnh viễn',
            icon: controller.deleteIsRecoverable
                ? Icons.restore_from_trash_outlined
                : Icons.dangerous_outlined,
            color: controller.deleteIsRecoverable
                ? null
                : theme.colorScheme.error,
            tooltip: controller.deleteIsRecoverable
                ? 'Thư được chuyển vào "${controller.trashName}" nên còn lấy '
                      'lại được.'
                : 'Server không có lệnh MOVE hoặc không có Thùng rác nhận thư.',
          ),
          const Spacer(),
          TextButton.icon(
            onPressed:
                controller.stage == MailCleanerStage.scanning ||
                    controller.stage == MailCleanerStage.deleting
                ? null
                : () => controller.scan(),
            icon: const Icon(Icons.radar, size: 17),
            label: Text(
              controller.allMail.isEmpty ? 'Quét hộp thư' : 'Quét lại',
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderPicker extends StatelessWidget {
  const _FolderPicker({required this.controller});

  final MailCleanerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folders = controller.folders.contains(controller.folder)
        ? controller.folders
        : [controller.folder, ...controller.folders];
    final locked =
        controller.stage == MailCleanerStage.scanning ||
        controller.stage == MailCleanerStage.deleting;

    // Built by hand rather than with DropdownButtonFormField: an
    // InputDecorator keeps its prefix icon at the 48px minimum tap target, so
    // it cannot shrink and a long folder name ("[Gmail]/All Mail") overflows
    // the field instead of being clipped.
    return Container(
      width: 250,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_outlined,
            size: 17,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: controller.folder,
                isDense: true,
                isExpanded: true,
                borderRadius: BorderRadius.circular(6),
                items: [
                  for (final folder in folders)
                    DropdownMenuItem(
                      value: folder,
                      child: Text(
                        folder,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                ],
                onChanged: locked
                    ? null
                    : (value) =>
                          value == null ? null : controller.changeFolder(value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- side panel

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.controller});

  final MailCleanerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (controller.quota != null) ...[
            ModuleCard(child: QuotaBar(quota: controller.quota!)),
            const SizedBox(height: 12),
          ],
          ModuleCard(
            child: Row(
              children: [
                Expanded(
                  child: MailStat(
                    label: 'Thư trong thư mục',
                    value: formatCount(controller.folderTotal),
                  ),
                ),
                Expanded(
                  child: MailStat(
                    label: 'Đã quét',
                    value: formatCount(controller.allMail.length),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionLabel('Mẫu tiêu đề tự nhập'),
          const SizedBox(height: 8),
          _RuleBox(controller: controller),
          const SizedBox(height: 18),
          const SectionLabel('Tuỳ chọn an toàn'),
          const SizedBox(height: 6),
          ModuleCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: SwitchListTile(
              value: controller.keepReplies,
              onChanged: controller.setKeepReplies,
              dense: true,
              title: const Text('Giữ lại thư trả lời'),
              subtitle: Text(
                'Bỏ qua thư có tiền tố Re: / Fwd: — thường là trao đổi của '
                'người thật',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (controller.deleteIsRecoverable)
            NoticeBox(
              icon: Icons.restore_from_trash_outlined,
              text:
                  'Chế độ an toàn: thư được chuyển vào '
                  '"${controller.trashName}" nên còn lấy lại được. '
                  '${controller.isGmail ? "Gmail lưu Thùng rác 30 ngày. " : ""}'
                  'Dọn Thùng rác mới thật sự giải phóng dung lượng.',
            )
          else ...[
            const NoticeBox(
              tone: NoticeTone.danger,
              text:
                  'Server này không có lệnh MOVE và Thùng rác không nhận thư, '
                  'nên mọi thao tác xoá là VĨNH VIỄN.',
            ),
            if (!controller.hasUidPlus) ...[
              const SizedBox(height: 10),
              const NoticeBox(
                tone: NoticeTone.warning,
                text:
                    'Server không hỗ trợ UIDPLUS. Lệnh xoá cuối cùng sẽ xoá '
                    'mọi thư đang gắn cờ \\Deleted trong thư mục này, kể cả '
                    'thư bạn đã đánh dấu từ trước.',
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _RuleBox extends StatefulWidget {
  const _RuleBox({required this.controller});

  final MailCleanerController controller;

  @override
  State<_RuleBox> createState() => _RuleBoxState();
}

class _RuleBoxState extends State<_RuleBox> {
  final _pattern = TextEditingController();
  MatchKind _kind = MatchKind.startsWith;

  @override
  void dispose() {
    _pattern.dispose();
    super.dispose();
  }

  void _add() {
    final pattern = _pattern.text.trim();
    if (pattern.isEmpty) return;
    final rule = SubjectRule(pattern: pattern, kind: _kind);
    if (rule.regexError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Biểu thức không hợp lệ: ${rule.regexError}')),
      );
      return;
    }
    widget.controller.addRule(rule);
    _pattern.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rules = widget.controller.rules;

    return ModuleCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _pattern,
            onSubmitted: (_) => _add(),
            decoration: const InputDecoration(
              hintText: 'Ví dụ: [GTEL-VOICE]',
              prefixIcon: Icon(Icons.text_fields, size: 18),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<MatchKind>(
                  initialValue: _kind,
                  isDense: true,
                  isExpanded: true,
                  items: [
                    for (final kind in MatchKind.values)
                      DropdownMenuItem(
                        value: kind,
                        child: Text(
                          kind.label,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _kind = value ?? _kind),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _add,
                icon: const Icon(Icons.add, size: 19),
                tooltip: 'Thêm mẫu',
              ),
            ],
          ),
          if (rules.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Chưa có mẫu nào. Bạn có thể tick trực tiếp các nhóm ở bảng '
              'bên phải, hoặc nhập mẫu tiêu đề vào đây.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            const Divider(),
            const SizedBox(height: 6),
            for (var index = 0; index < rules.length; index++)
              _RuleRow(
                rule: rules[index],
                onToggle: () => widget.controller.toggleRule(index),
                onRemove: () => widget.controller.removeRule(index),
              ),
          ],
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,
    required this.onToggle,
    required this.onRemove,
  });

  final SubjectRule rule;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Checkbox(
              value: rule.enabled,
              onChanged: (_) => onToggle(),
              visualDensity: VisualDensity.compact,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.pattern,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: rule.enabled
                        ? null
                        : TextDecoration.lineThrough,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  rule.kind.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'Bỏ mẫu này',
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- main area

class _MainArea extends StatelessWidget {
  const _MainArea({
    required this.controller,
    required this.groupFilter,
    required this.onFilterChanged,
  });

  final MailCleanerController controller;
  final TextEditingController groupFilter;
  final VoidCallback onFilterChanged;

  @override
  Widget build(BuildContext context) {
    if (controller.stage == MailCleanerStage.scanning ||
        controller.stage == MailCleanerStage.deleting) {
      return _ProgressView(controller: controller);
    }
    if (controller.allMail.isEmpty) {
      return _EmptyView(controller: controller);
    }
    return _GroupTable(
      controller: controller,
      groupFilter: groupFilter,
      onFilterChanged: onFilterChanged,
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.controller});

  final MailCleanerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.travel_explore_outlined,
                size: 52,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Quét hộp thư để bắt đầu',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'App sẽ đọc tiêu đề và dung lượng của '
                '${formatCount(controller.folderTotal)} thư trong thư mục '
                '"${controller.folder}", rồi gom thành các nhóm để bạn thấy '
                'nhóm nào đang chiếm nhiều dung lượng nhất.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => controller.scan(),
                icon: const Icon(Icons.radar, size: 18),
                label: const Text('Quét hộp thư'),
              ),
              if (controller.error != null) ...[
                const SizedBox(height: 18),
                NoticeBox(text: controller.error!, tone: NoticeTone.danger),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.controller});

  final MailCleanerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = controller.progress;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                progress?.message ?? 'Đang xử lý…',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (progress == null || progress.total <= 1)
                      ? null
                      : progress.ratio,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
              if (progress != null && progress.total > 1)
                Text(
                  '${formatCount(progress.done)} / '
                  '${formatCount(progress.total)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupTable extends StatelessWidget {
  const _GroupTable({
    required this.controller,
    required this.groupFilter,
    required this.onFilterChanged,
  });

  final MailCleanerController controller;
  final TextEditingController groupFilter;
  final VoidCallback onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scannedBytes = controller.allMail.fold<int>(
      0,
      (sum, mail) => sum + mail.size,
    );
    final query = groupFilter.text.trim().toUpperCase();
    final groups = query.isEmpty
        ? controller.groups
        : controller.groups
              .where((group) => group.name.contains(query))
              .toList();
    final heaviest = controller.groups.isEmpty
        ? 1
        : controller.groups.first.totalBytes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  'Nhóm tiêu đề',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  '${controller.groups.length} nhóm · '
                  '${formatBytes(scannedBytes)}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: groupFilter,
                  onChanged: (_) => onFilterChanged(),
                  decoration: const InputDecoration(
                    hintText: 'Tìm kiếm nhóm…',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: controller.selectedGroups.isEmpty
                    ? null
                    : () => controller.clearSelection(),
                child: const Text('Bỏ chọn hết'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: const [
              SizedBox(width: 42),
              Expanded(flex: 4, child: _ColumnLabel('Nhóm')),
              Expanded(flex: 3, child: _ColumnLabel('Tỉ trọng dung lượng')),
              SizedBox(
                width: 90,
                child: _ColumnLabel('Tổng', alignRight: true),
              ),
              SizedBox(
                width: 76,
                child: _ColumnLabel('Số thư', alignRight: true),
              ),
              SizedBox(
                width: 76,
                child: _ColumnLabel('Cỡ TB', alignRight: true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Divider(height: 1),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Text(
                    'Không có nhóm nào khớp "${groupFilter.text.trim()}".',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: groups.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => _GroupRow(
                    group: groups[index],
                    controller: controller,
                    heaviestBytes: heaviest,
                  ),
                ),
        ),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.controller,
    required this.heaviestBytes,
  });

  final SubjectGroup group;
  final MailCleanerController controller;
  final int heaviestBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = controller.selectedGroups.contains(group.name);

    return InkWell(
      onTap: () => controller.selectGroup(group.name, !selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: Checkbox(
                value: selected,
                onChanged: (value) =>
                    controller.selectGroup(group.name, value ?? false),
              ),
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (group.replyCount > 0)
                    Text(
                      'có ${formatCount(group.replyCount)} thư Re:/Fwd:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppCyberTheme.amber,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: ShareBar(
                  ratio: heaviestBytes == 0
                      ? 0
                      : group.totalBytes / heaviestBytes,
                  highlighted: selected,
                ),
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                formatBytes(group.totalBytes),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                formatCount(group.count),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                formatBytes(group.averageBytes),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColumnLabel extends StatelessWidget {
  const _ColumnLabel(this.text, {this.alignRight = false});

  final String text;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// --------------------------------------------------------------- log panel

class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.controller});

  final MailCleanerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 170,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                const SectionLabel('Nhật ký'),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: controller.logText()),
                  ),
                  icon: const Icon(Icons.copy, size: 15),
                  label: const Text('Chép'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              itemCount: controller.logLines.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  controller.logLines[index],
                  style: AppCyberTheme.dataTextStyle(
                    size: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- action bar

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller});

  final MailCleanerController controller;

  Future<void> _confirmDelete(BuildContext context) async {
    final matched = controller.matchedCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _ConfirmDialog(matchedCount: matched, controller: controller),
    );
    if (confirmed != true) return;
    if (controller.deleteIsRecoverable) {
      await controller.moveToTrash();
    } else {
      await controller.deleteForever();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy =
        controller.stage == MailCleanerStage.scanning ||
        controller.stage == MailCleanerStage.deleting;
    final scanned = controller.allMail.isNotEmpty;
    final matched = scanned ? controller.matchedCount : 0;
    final matchedBytes = scanned ? controller.matchedBytes : 0;
    final keptReplies = scanned ? controller.keptReplyCount : 0;

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // The buttons on the right must always be fully visible; the figures
          // on the left are the part allowed to shrink and scroll sideways when
          // the window is narrow.
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  MailStat(
                    label: 'Sẽ xoá',
                    value: formatCount(matched),
                    suffix: 'thư',
                    icon: Icons.delete_sweep_outlined,
                    valueColor: matched > 0 ? theme.colorScheme.error : null,
                  ),
                  const SizedBox(width: 28),
                  MailStat(
                    label: 'Giải phóng',
                    value: formatBytes(matchedBytes),
                    icon: Icons.cloud_done_outlined,
                  ),
                  if (keptReplies > 0) ...[
                    const SizedBox(width: 28),
                    MailStat(
                      label: 'Giữ lại Re:/Fwd:',
                      value: formatCount(keptReplies),
                      suffix: 'thư',
                      icon: Icons.shield_outlined,
                      valueColor: AppCyberTheme.amber,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          if (controller.deleteIsRecoverable)
            // Gmail and any server carrying MOVE: one step, recoverable.
            FilledButton.icon(
              onPressed: busy || matched == 0
                  ? null
                  : () => _confirmDelete(context),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(
                'Chuyển vào ${controller.trashName ?? "Thùng rác"}'
                '${matched > 0 ? " (${formatCount(matched)})" : ""}',
              ),
            )
          else ...[
            if (controller.flaggedCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => controller.clearFlags(),
                  icon: const Icon(Icons.undo, size: 17),
                  label: const Text('Gỡ cờ'),
                ),
              ),
            OutlinedButton.icon(
              onPressed: busy || matched == 0 ? null : () => controller.flag(),
              icon: const Icon(Icons.flag_outlined, size: 17),
              label: const Text('Bước 1 — Gắn cờ'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: busy || matched == 0
                  ? null
                  : () => _confirmDelete(context),
              icon: const Icon(Icons.delete_forever, size: 18),
              label: const Text('Bước 2 — Xoá vĩnh viễn'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({required this.matchedCount, required this.controller});

  final int matchedCount;
  final MailCleanerController controller;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recoverable = widget.controller.deleteIsRecoverable;
    final phrase = 'XOA ${widget.matchedCount}';
    // Only an irreversible step is worth making the user type it out.
    final allowed = recoverable || _typed.text.trim() == phrase;
    final trash = widget.controller.trashName ?? 'Thùng rác';

    return AlertDialog(
      icon: Icon(
        recoverable ? Icons.delete_outline : Icons.dangerous_outlined,
        color: recoverable
            ? theme.colorScheme.primary
            : theme.colorScheme.error,
      ),
      title: Text(recoverable ? 'Chuyển vào $trash?' : 'Xoá vĩnh viễn?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${recoverable ? "Sắp chuyển" : "Sắp xoá"} '
              '${formatCount(widget.matchedCount)} thư '
              '(${formatBytes(widget.controller.matchedBytes)}) khỏi '
              '${widget.controller.folder}.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (recoverable)
              NoticeBox(
                text:
                    'Thư vào "$trash" nên vẫn lấy lại được. Dung lượng chỉ '
                    'thật sự được giải phóng sau khi bạn dọn $trash.',
              )
            else ...[
              const NoticeBox(
                tone: NoticeTone.danger,
                text:
                    'Máy chủ này không có Thùng rác. Thư bị xoá sẽ không thể '
                    'khôi phục bằng bất kỳ cách nào.',
              ),
              const SizedBox(height: 14),
              Text(
                'Gõ chính xác "$phrase" để xác nhận:',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _typed,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(hintText: phrase),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          style: recoverable
              ? null
              : FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
          onPressed: allowed ? () => Navigator.pop(context, true) : null,
          child: Text(recoverable ? 'Chuyển vào $trash' : 'Xoá vĩnh viễn'),
        ),
      ],
    );
  }
}
