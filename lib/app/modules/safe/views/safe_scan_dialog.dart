import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';

import '../../shared/module_widgets.dart';
import '../controllers/safe_controller.dart';
import '../controllers/safe_scan_controller.dart';
import '../models/safe_item.dart';
import '../services/safe_secret_scanner.dart';
import '../widgets/safe_look.dart';
import '../widgets/safe_metal.dart';

/// Opens the folder scan. Returns what was put in the safe, or null.
Future<SafeScanImport?> showSafeScanDialog(
  BuildContext context,
  SafeController safe, {
  SafeScanController? controller,
}) {
  return showDialog<SafeScanImport>(
    context: context,
    barrierDismissible: false,
    builder: (context) => SafeScanDialog(safe: safe, controller: controller),
  );
}

extension SecretFindingTypeLook on SecretFindingType {
  IconData get icon => switch (this) {
    SecretFindingType.envFile => Icons.tune_rounded,
    SecretFindingType.properties => Icons.settings_applications_outlined,
    SecretFindingType.serviceAccount => Icons.admin_panel_settings_outlined,
    SecretFindingType.firebaseConfig => Icons.local_fire_department_outlined,
    SecretFindingType.secretJson => Icons.data_object_rounded,
    SecretFindingType.keystore => Icons.badge_outlined,
    SecretFindingType.appleConfig => Icons.phone_iphone_rounded,
    SecretFindingType.privateKey => Icons.key_rounded,
    SecretFindingType.inlineToken => Icons.code_rounded,
  };
}

extension SecretProjectKindLook on SecretProjectKind {
  IconData get icon => switch (this) {
    SecretProjectKind.flutter => Icons.flutter_dash,
    SecretProjectKind.node => Icons.javascript_rounded,
    SecretProjectKind.android => Icons.android_rounded,
    SecretProjectKind.ios => Icons.apple_rounded,
    SecretProjectKind.folder => Icons.folder_outlined,
    _ => Icons.source_outlined,
  };
}

class SafeScanDialog extends StatefulWidget {
  const SafeScanDialog({super.key, required this.safe, this.controller});

  final SafeController safe;

  /// Injected by the tests; left null the dialog builds its own.
  final SafeScanController? controller;

  @override
  State<SafeScanDialog> createState() => _SafeScanDialogState();
}

class _SafeScanDialogState extends State<SafeScanDialog> {
  late final SafeScanController _scan =
      widget.controller ?? SafeScanController(safe: widget.safe);
  late final bool _ownsController = widget.controller == null;
  final _search = TextEditingController();
  bool _dropping = false;
  String _importError = '';

  @override
  void initState() {
    super.initState();
    widget.safe.addListener(_closeIfLocked);
  }

  @override
  void dispose() {
    widget.safe.removeListener(_closeIfLocked);
    if (_ownsController) _scan.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Nothing about the safe stays on screen once it locks.
  void _closeIfLocked() {
    if (!widget.safe.isOpen && mounted) {
      _scan.cancel();
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _pickFolder() async {
    final path = await file_selector.getDirectoryPath(
      confirmButtonText: 'Dò thư mục này',
    );
    if (path != null) await _scan.scan(path);
  }

  Future<void> _import() async {
    setState(() => _importError = '');
    try {
      final result = await _scan.importSelected();
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) setState(() => _importError = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 860),
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dropping = true),
          onDragExited: (_) => setState(() => _dropping = false),
          onDragDone: (details) async {
            setState(() => _dropping = false);
            for (final file in details.files) {
              if (await FileSystemEntity.isDirectory(file.path)) {
                await _scan.scan(file.path);
              }
            }
          },
          child: ListenableBuilder(
            listenable: _scan,
            builder: (context, _) => Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      scan: _scan,
                      onPick: _pickFolder,
                      onClose: _scan.isImporting
                          ? null
                          : () {
                              _scan.cancel();
                              Navigator.of(context).pop();
                            },
                    ),
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                    if (_scan.stage == SafeScanStage.scanning)
                      _ScanningBanner(scan: _scan),
                    if (_scan.error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: NoticeBox(
                          text: _scan.error,
                          tone: NoticeTone.danger,
                        ),
                      ),
                    Expanded(child: _body()),
                    if (_scan.findingCount > 0)
                      _Footer(
                        scan: _scan,
                        error: _importError,
                        onImport: _import,
                      ),
                  ],
                ),
                if (_dropping)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Thả thư mục để dò',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_scan.stage == SafeScanStage.idle) {
      return _Intro(onPick: _pickFolder);
    }
    if (_scan.findingCount == 0) {
      if (_scan.stage == SafeScanStage.scanning) {
        return const _RadarStage();
      }
      return const _NothingFound();
    }
    return _Results(scan: _scan, search: _search);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.scan,
    required this.onPick,
    required this.onClose,
  });

  final SafeScanController scan;
  final VoidCallback onPick;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = scan.stage == SafeScanStage.scanning || scan.isImporting;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                ),
                child: Icon(
                  Icons.radar_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dò khoá trong thư mục',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Gom .env, key.properties, service account, keystore, private key '
                      'và key viết thẳng trong mã nguồn của mọi project bên trong.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (scan.roots.isNotEmpty)
                FilledButton.tonalIcon(
                  key: const Key('safe-scan-add-folder'),
                  onPressed: busy ? null : onPick,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text('Thêm thư mục…'),
                ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Đóng',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (scan.roots.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final root in scan.roots)
                  Tooltip(
                    message: root,
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.folder_open_rounded, size: 16),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Text(
                          root,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 150,
                height: 150,
                child: _Radar(sweeping: false),
              ),
              const SizedBox(height: 18),
              Text(
                'Chọn thư mục chứa các project',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Mọi thư mục con đều được dò. Mỗi project (có pubspec.yaml, '
                'package.json, Gradle, Xcode, .git…) thành một nhóm riêng.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const Key('safe-scan-pick'),
                onPressed: onPick,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Chọn thư mục…'),
              ),
              const SizedBox(height: 6),
              Text(
                'hoặc kéo thả thư mục vào đây',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    line(
                      Icons.tune_rounded,
                      '.env, .env.production, key.properties, gradle.properties có mật khẩu',
                    ),
                    line(
                      Icons.data_object_rounded,
                      'Service account, google-services.json, JSON chứa secret',
                    ),
                    line(
                      Icons.badge_outlined,
                      'Keystore .jks/.keystore/.p12, GoogleService-Info.plist',
                    ),
                    line(Icons.key_rounded, 'Khoá riêng .p8/.pem/.key, id_rsa'),
                    line(
                      Icons.code_rounded,
                      'Key viết thẳng trong code: AWS, Google, GitHub, Stripe, OpenAI…',
                    ),
                    line(
                      Icons.shield_outlined,
                      'Chỉ đọc trên máy này. Bỏ qua build, node_modules, Pods, .git.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanningBanner extends StatelessWidget {
  const _ScanningBanner({required this.scan});

  final SafeScanController scan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = scan.progress;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
      color: theme.colorScheme.primary.withValues(alpha: 0.08),
      child: Row(
        children: [
          const SizedBox(width: 30, height: 30, child: _Radar(sweeping: true)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  progress == null
                      ? 'Đang bắt đầu dò…'
                      : 'Đã dò ${progress.directories} thư mục · ${progress.files} tệp · '
                            '${progress.findings} khoá khả nghi trong ${progress.projects} dự án',
                  key: const Key('safe-scan-progress'),
                  style: theme.textTheme.labelLarge,
                ),
                if (progress != null)
                  Text(
                    progress.currentPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: scan.cancel,
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('Dừng'),
          ),
        ],
      ),
    );
  }
}

class _RadarStage extends StatelessWidget {
  const _RadarStage();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(width: 180, height: 180, child: _Radar(sweeping: true)),
    );
  }
}

class _NothingFound extends StatelessWidget {
  const _NothingFound();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 10),
          Text('Không thấy khoá nào', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Thử thư mục khác, hoặc kiểm tra file có đuôi .example/.sample (luôn bị bỏ qua).',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.scan, required this.search});

  final SafeScanController scan;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projects = scan.visibleProjects;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('safe-scan-search'),
                  controller: search,
                  onChanged: scan.setQuery,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    hintText: 'Lọc theo dự án, đường dẫn, loại khoá…',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                key: const Key('safe-scan-select-all'),
                onPressed: () => scan.selectAll(true),
                child: const Text('Chọn hết'),
              ),
              TextButton(
                key: const Key('safe-scan-select-none'),
                onPressed: () => scan.selectAll(false),
                child: const Text('Bỏ chọn hết'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (final type in scan.typesFound)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(type.icon, size: 16, color: type.kind.tint),
                    label: Text('${type.label} ${scan.countOfType(type)}'),
                    selected: scan.isTypeShown(type),
                    onSelected: (_) => scan.toggleType(type),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: projects.isEmpty
              ? Center(
                  child: Text(
                    'Không có gì khớp bộ lọc.',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  itemCount: projects.length,
                  itemBuilder: (context, index) => _ProjectGroup(
                    key: ValueKey(projects[index].root),
                    scan: scan,
                    project: projects[index],
                  ),
                ),
        ),
      ],
    );
  }
}

/// One project: a drawer front with a tri-state tick, and its findings
/// beneath it.
class _ProjectGroup extends StatelessWidget {
  const _ProjectGroup({super.key, required this.scan, required this.project});

  final SafeScanController scan;
  final SecretProject project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steel = SafeSteel.of(context);
    final findings = scan.visibleFindings(project);
    final collapsed = scan.isCollapsed(project);
    final selected = scan.selectedIn(project);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: steel.boxEdge),
        color: theme.colorScheme.surface,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => scan.toggleCollapsed(project),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: steel.boxFace,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                child: Row(
                  children: [
                    Checkbox(
                      key: Key('safe-scan-project-${project.name}'),
                      tristate: true,
                      value: scan.projectState(project),
                      onChanged: (_) => scan.toggleProject(project),
                    ),
                    Icon(
                      project.kind.icon,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${project.kind.label} · ${project.root}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    StatusChip(
                      label: '$selected/${project.findings.length} đã chọn',
                      icon: Icons.check_box_outlined,
                      color: selected > 0
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      collapsed
                          ? Icons.expand_more_rounded
                          : Icons.expand_less_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!collapsed)
            for (final finding in findings)
              _FindingRow(scan: scan, project: project, finding: finding),
        ],
      ),
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({
    required this.scan,
    required this.project,
    required this.finding,
  });

  final SafeScanController scan;
  final SecretProject project;
  final SecretFinding finding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final known = scan.isKnown(finding);
    final type = finding.type;
    final tint = type.kind.tint;
    final muted = theme.colorScheme.onSurfaceVariant;
    final mono = TextStyle(
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      fontSize: 12,
      color: muted,
    );

    return InkWell(
      onTap: known ? null : () => scan.toggleFinding(project, finding),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(30, 4, 14, 4),
        child: Row(
          children: [
            Checkbox(
              key: Key('safe-scan-finding-${finding.id}'),
              value: known ? false : scan.isSelected(project, finding),
              onChanged: known
                  ? null
                  : (_) => scan.toggleFinding(project, finding),
            ),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.14),
              ),
              child: Icon(type.icon, size: 16, color: tint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          finding.line == null
                              ? finding.relativePath
                              : '${finding.relativePath}:${finding.line}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: known ? muted : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Tag(
                        text: type == SecretFindingType.inlineToken
                            ? finding.label
                            : type.label,
                        color: tint,
                      ),
                      if (finding.otherPlaces > 0) ...[
                        const SizedBox(width: 6),
                        _Tag(
                          text: '+${finding.otherPlaces} nơi khác',
                          color: muted,
                        ),
                      ],
                      if (known) ...[
                        const SizedBox(width: 6),
                        _Tag(
                          text: 'Đã có trong két',
                          color: const Color(0xFF3DBE7A),
                        ),
                      ],
                    ],
                  ),
                  if (finding.preview.isNotEmpty)
                    Text(
                      finding.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              type == SecretFindingType.inlineToken
                  ? '${finding.size} ký tự'
                  : formatByteSize(finding.size),
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.scan,
    required this.error,
    required this.onImport,
  });

  final SafeScanController scan;
  final String error;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warnings = [
      if (scan.truncated)
        'Thư mục quá lớn: chỉ dò ${SafeSecretScanner.maxFiles} tệp đầu.',
      if (scan.tooLarge.isNotEmpty)
        '${scan.tooLarge.length} tệp quá ${formatByteSize(SafeSecretScanner.maxSecretBytes)} bị bỏ qua.',
    ];
    final count = scan.selectedCount;
    final busy = scan.isImporting || scan.stage == SafeScanStage.scanning;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Đã chọn $count/${scan.findingCount} khoá từ ${scan.selectedProjectCount} dự án',
                  key: const Key('safe-scan-summary'),
                  style: theme.textTheme.titleSmall,
                ),
                for (final warning in warnings)
                  Text(
                    warning,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFE0A526),
                    ),
                  ),
                if (error.isNotEmpty)
                  Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            key: const Key('safe-scan-import'),
            onPressed: count == 0 || busy ? null : onImport,
            icon: scan.isImporting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_rounded, size: 18),
            label: Text('Cất $count khoá vào két'),
          ),
        ],
      ),
    );
  }
}

/// A radar dish: rings and, while scanning, a sweeping beam.
class _Radar extends StatefulWidget {
  const _Radar({required this.sweeping});

  final bool sweeping;

  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Radar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate =
        widget.sweeping && !MediaQuery.of(context).disableAnimations;
    if (animate && !_sweep.isAnimating) {
      unawaited(_sweep.repeat());
    } else if (!animate && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _sweep,
        builder: (context, _) => CustomPaint(
          painter: _RadarPainter(
            color: color,
            angle: _sweep.value * 2 * math.pi,
            sweeping: widget.sweeping,
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({
    required this.color,
    required this.angle,
    required this.sweeping,
  });

  final Color color;
  final double angle;
  final bool sweeping;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withValues(alpha: 0.08),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, radius / 60)
      ..color = color.withValues(alpha: 0.35);
    for (final share in [1.0, 0.66, 0.33]) {
      canvas.drawCircle(center, radius * share - ring.strokeWidth, ring);
    }
    canvas.drawLine(
      center.translate(-radius, 0),
      center.translate(radius, 0),
      ring,
    );
    canvas.drawLine(
      center.translate(0, -radius),
      center.translate(0, radius),
      ring,
    );
    if (sweeping) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        angle - math.pi / 2.5,
        math.pi / 2.5,
        true,
        Paint()
          ..shader = SweepGradient(
            startAngle: angle - math.pi / 2.5,
            endAngle: angle,
            colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.55)],
          ).createShader(rect),
      );
    }
    // Blips where secrets were "found".
    final blip = Paint()..color = color;
    for (final (dx, dy) in const [(0.35, -0.4), (-0.5, 0.2), (0.15, 0.55)]) {
      canvas.drawCircle(
        center.translate(radius * dx, radius * dy),
        math.max(2, radius / 25),
        blip,
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.angle != angle ||
      oldDelegate.color != color ||
      oldDelegate.sweeping != sweeping;
}
