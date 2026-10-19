import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../shared/module_widgets.dart';
import '../controllers/safe_controller.dart';
import '../models/safe_item.dart';
import '../services/safe_password_tools.dart';
import '../services/safe_zip_packer.dart';
import '../widgets/safe_look.dart';
import 'safe_dialogs.dart';

/// The outside world the pack dialog touches, swapped out by the tests.
class SafePackIo {
  const SafePackIo({
    this.pickDestination = _pickDestination,
    this.encode = _encode,
    this.write = _write,
    this.reveal = _reveal,
  });

  /// Where to save, given a suggested file name. Null when cancelled.
  final Future<String?> Function(String suggestedName) pickDestination;
  final Future<Uint8List> Function(
    List<SafeZipEntry> entries,
    String password,
    SafeZipEncryption encryption,
  )
  encode;
  final Future<void> Function(String path, Uint8List bytes) write;

  /// Shows the file in Finder or Explorer.
  final Future<void> Function(String path) reveal;

  static Future<String?> _pickDestination(String suggestedName) async {
    final location = await file_selector.getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        file_selector.XTypeGroup(label: 'ZIP', extensions: ['zip']),
      ],
    );
    return location?.path;
  }

  static Future<Uint8List> _encode(
    List<SafeZipEntry> entries,
    String password,
    SafeZipEncryption encryption,
  ) => encodeSafeZipInIsolate(
    entries,
    password: password,
    encryption: encryption,
  );

  static Future<void> _write(String path, Uint8List bytes) =>
      File(path).writeAsBytes(bytes, flush: true);

  static Future<void> _reveal(String path) async {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', ['/select,', path]);
    } else if (Platform.isMacOS) {
      await Process.start('open', ['-R', path]);
    }
  }
}

class SafePackResult {
  const SafePackResult({
    required this.path,
    required this.size,
    required this.project,
    required this.encryption,
    required this.itemCount,
  });

  final String path;
  final int size;
  final String project;
  final SafeZipEncryption encryption;
  final int itemCount;
}

/// Opens the pack dialog, on [project] when given.
Future<SafePackResult?> showSafePackDialog(
  BuildContext context,
  SafeController safe, {
  String? project,
  SafePackIo io = const SafePackIo(),
}) {
  return showDialog<SafePackResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        SafePackDialog(safe: safe, initialProject: project, io: io),
  );
}

/// The message to send beside the zip: how to open it, never the password.
String safePackMessage(SafePackResult result) {
  final name = p.basename(result.path);
  final project = result.project.isEmpty ? 'dự án' : result.project;
  final how = switch (result.encryption) {
    SafeZipEncryption.aes256 =>
      'File mã hoá AES-256. Windows: mở bằng 7-Zip hoặc WinRAR (Explorer có '
          'sẵn không mở được). macOS: mở bằng Keka hoặc The Unarchiver, hoặc '
          'Terminal: tar -xf "$name" --passphrase "<mật khẩu>".',
    SafeZipEncryption.zipCrypto =>
      'Windows: nhấp đúp file rồi nhập mật khẩu. macOS: mở Terminal, chạy '
          'unzip "$name" rồi nhập mật khẩu (hoặc dùng Keka).',
  };
  return 'Mình gửi bộ keys của $project: $name. $how '
      'Mật khẩu mình gửi riêng qua kênh khác.';
}

class SafePackDialog extends StatefulWidget {
  const SafePackDialog({
    super.key,
    required this.safe,
    this.initialProject,
    this.io = const SafePackIo(),
  });

  final SafeController safe;
  final String? initialProject;
  final SafePackIo io;

  /// Stands for the items that belong to no project.
  static const looseProject = '';

  @override
  State<SafePackDialog> createState() => _SafePackDialogState();
}

class _SafePackDialogState extends State<SafePackDialog> {
  late String _project = _initialProject();
  final _unticked = <String>{};
  SafeZipEncryption _encryption = SafeZipEncryption.aes256;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String _error = '';
  SafePackResult? _result;

  SafeController get _safe => widget.safe;

  @override
  void initState() {
    super.initState();
    _safe.addListener(_closeIfLocked);
  }

  @override
  void dispose() {
    _safe.removeListener(_closeIfLocked);
    // The zip password lives only as long as this dialog.
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _closeIfLocked() {
    if (!_safe.isOpen && mounted) Navigator.of(context).maybePop();
  }

  /// The projects to choose from, plus the loose items when there are any.
  List<String> get _projects => [
    ..._safe.projects,
    if (_safe.items.any((item) => item.project.isEmpty))
      SafePackDialog.looseProject,
  ];

  String _initialProject() {
    final projects = _projects;
    final wanted = widget.initialProject;
    if (wanted != null && projects.contains(wanted)) return wanted;
    return projects.isEmpty ? SafePackDialog.looseProject : projects.first;
  }

  String _label(String project) =>
      project.isEmpty ? '(Không thuộc dự án)' : project;

  List<SafeItem> get _items {
    final items = _safe.items.where((item) => item.project == _project).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return items;
  }

  List<SafeItem> get _chosen =>
      _items.where((item) => !_unticked.contains(item.id)).toList();

  void _generate() {
    final value = generatePassword(const PasswordRecipe(length: 20));
    setState(() {
      _password.text = value;
      _confirm.text = value;
      _showPassword = true;
      _error = '';
    });
  }

  Future<void> _copyPassword() async {
    if (_password.text.isEmpty) return;
    await _safe.copySecret(_password.text);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          'Đã sao chép mật khẩu nén · tự xoá sau '
          '${_safe.settings.clipboardSeconds} giây.',
        ),
      ),
    );
  }

  Future<void> _pack() async {
    final chosen = _chosen;
    if (chosen.isEmpty) {
      setState(() => _error = 'Chọn ít nhất một mục để đóng gói.');
      return;
    }
    final problem = validateSafeZipPassword(_password.text, _confirm.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _error = '';
      _busy = true;
    });
    try {
      final kit = SafeProjectKit.build(project: _project, items: chosen);
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final base = kit.folder.replaceAll(' ', '-');
      final picked = await widget.io.pickDestination(
        '$base-keys-${now.year}${two(now.month)}${two(now.day)}.zip',
      );
      if (picked == null) return;
      final path = picked.toLowerCase().endsWith('.zip')
          ? picked
          : '$picked.zip';
      final bytes = await widget.io.encode(
        kit.entries,
        _password.text,
        _encryption,
      );
      await widget.io.write(path, bytes);
      _safe.touch();
      if (!mounted) return;
      setState(
        () => _result = SafePackResult(
          path: path,
          size: bytes.length,
          project: _project,
          encryption: _encryption,
          itemCount: chosen.length,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Không đóng gói được: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 860),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary.withValues(alpha: 0.14),
                    ),
                    child: Icon(
                      Icons.folder_zip_outlined,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Đóng gói ZIP bộ keys',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Nén khoá của một dự án thành một file ZIP có mật '
                          'khẩu để gửi đi.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(_result),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Flexible(child: _result == null ? _form(theme) : _done(theme)),
          ],
        ),
      ),
    );
  }

  Widget _form(ThemeData theme) {
    final projects = _projects;
    final items = _items;
    final chosen = _chosen;
    final kit = SafeProjectKit.build(project: _project, items: chosen);
    final mono = TextStyle(
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      fontSize: 12,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final placements = {
      for (final placement in kit.placements) placement.item.id: placement.path,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (projects.isEmpty)
                  const NoticeBox(text: 'Két chưa có mục nào để đóng gói.')
                else
                  DropdownButtonFormField<String>(
                    key: const Key('safe-pack-project'),
                    initialValue: _project,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Dự án',
                      prefixIcon: Icon(Icons.folder_special_outlined),
                    ),
                    items: [
                      for (final project in projects)
                        DropdownMenuItem(
                          value: project,
                          child: Text(
                            '${_label(project)} · '
                            '${_safe.items.where((i) => i.project == project).length} mục',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _project = value ?? _project;
                            _unticked.clear();
                            _error = '';
                          }),
                  ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const SectionLabel('Nội dung'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${chosen.length}/${items.length} mục · '
                        '${kit.fileCount} file'
                        '${kit.secretCount > 0 ? ' + ${SafeProjectKit.secretsFile}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(_unticked.clear),
                      child: const Text('Chọn hết'),
                    ),
                    TextButton(
                      onPressed: () => setState(
                        () => _unticked.addAll(items.map((item) => item.id)),
                      ),
                      child: const Text('Bỏ chọn'),
                    ),
                  ],
                ),
                Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final item in items)
                        CheckboxListTile(
                          key: Key('safe-pack-item-${item.id}'),
                          dense: true,
                          value: !_unticked.contains(item.id),
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    _unticked.remove(item.id);
                                  } else {
                                    _unticked.add(item.id);
                                  }
                                }),
                          controlAffinity: ListTileControlAffinity.leading,
                          secondary: Icon(
                            item.kind.icon,
                            size: 18,
                            color: item.kind.tint,
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            placements[item.id] == null
                                ? '— không đóng gói'
                                : '→ ${kit.folder}/${placements[item.id]}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SectionLabel('Mã hoá'),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = [
                      _EncryptionCard(
                        key: const Key('safe-pack-aes'),
                        icon: Icons.shield_outlined,
                        title: 'AES-256',
                        subtitle: 'Mạnh nhất · người nhận cần 7-Zip hoặc Keka',
                        selected: _encryption == SafeZipEncryption.aes256,
                        onTap: _busy
                            ? null
                            : () => setState(
                                () => _encryption = SafeZipEncryption.aes256,
                              ),
                      ),
                      _EncryptionCard(
                        key: const Key('safe-pack-zipcrypto'),
                        icon: Icons.devices_outlined,
                        title: 'Tương thích Windows/macOS',
                        subtitle: 'Mở sẵn bằng Explorer, unzip · yếu hơn',
                        selected: _encryption == SafeZipEncryption.zipCrypto,
                        onTap: _busy
                            ? null
                            : () => setState(
                                () => _encryption = SafeZipEncryption.zipCrypto,
                              ),
                      ),
                    ];
                    if (constraints.maxWidth < 520) {
                      return Column(
                        children: [
                          cards[0],
                          const SizedBox(height: 8),
                          cards[1],
                        ],
                      );
                    }
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: 10),
                          Expanded(child: cards[1]),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                NoticeBox(
                  tone: _encryption == SafeZipEncryption.aes256
                      ? NoticeTone.info
                      : NoticeTone.warning,
                  text: switch (_encryption) {
                    SafeZipEncryption.aes256 =>
                      'Mạnh nhất. Người nhận cần 7-Zip/WinRAR trên Windows, '
                          'Keka/The Unarchiver hoặc lệnh tar trên macOS. Explorer '
                          'và Finder không tự mở được.',
                    SafeZipEncryption.zipCrypto =>
                      'Mở ngay bằng Explorer của Windows và lệnh unzip của macOS, '
                          'không cần cài gì. Kiểu mã hoá ZIP cũ, yếu hơn AES: chỉ '
                          'dùng với mật khẩu dài (từ 16 ký tự).',
                  },
                ),
                const SizedBox(height: 16),
                const SectionLabel('Mật khẩu nén'),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('safe-pack-password'),
                  controller: _password,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !_busy,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu',
                    helperText:
                        'Chữ không dấu, số, ký hiệu ASCII; ít nhất '
                        '$safeZipMinPasswordLength ký tự. Không được lưu lại.',
                    prefixIcon: const Icon(Icons.key_rounded),
                    suffixIcon: IconButton(
                      tooltip: _showPassword ? 'Ẩn' : 'Hiện',
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('safe-pack-confirm'),
                  controller: _confirm,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !_busy,
                  onSubmitted: (_) => _pack(),
                  decoration: const InputDecoration(
                    labelText: 'Nhập lại mật khẩu',
                    prefixIcon: Icon(Icons.key_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                PasswordStrengthBar(strength: ratePassword(_password.text)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('safe-pack-generate'),
                      onPressed: _busy ? null : _generate,
                      icon: const Icon(Icons.casino_outlined, size: 18),
                      label: const Text('Tạo mật khẩu mạnh'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _password.text.isEmpty ? null : _copyPassword,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Sao chép mật khẩu'),
                    ),
                  ],
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  NoticeBox(
                    key: const Key('safe-pack-error'),
                    text: _error,
                    tone: NoticeTone.danger,
                  ),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Gửi mật khẩu qua kênh khác với file ZIP.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: const Key('safe-pack-submit'),
                onPressed: _busy || chosen.isEmpty ? null : _pack,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_zip_outlined, size: 18),
                label: Text('Đóng gói ${chosen.length} mục…'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _done(ThemeData theme) {
    final result = _result!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 52,
            color: Color(0xFF3DBE7A),
          ),
          const SizedBox(height: 10),
          Text(
            'Đã đóng gói ${result.itemCount} mục',
            key: const Key('safe-pack-done'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          SelectableText(
            '${p.basename(result.path)} · ${formatByteSize(result.size)} · '
            '${result.encryption == SafeZipEncryption.aes256 ? 'AES-256' : 'ZipCrypto'}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 2),
          SelectableText(
            p.dirname(result.path),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const NoticeBox(
            text:
                'Gửi file ZIP và mật khẩu qua hai kênh khác nhau. Mật khẩu chỉ '
                'còn trong cửa sổ này; đóng lại là không xem lại được.',
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => widget.io.reveal(result.path),
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: Text(
                  Platform.isMacOS ? 'Hiện trong Finder' : 'Mở thư mục chứa',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _copyPassword,
                icon: const Icon(Icons.key_rounded, size: 18),
                label: const Text('Sao chép mật khẩu'),
              ),
              FilledButton.tonalIcon(
                key: const Key('safe-pack-copy-message'),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: safePackMessage(result)),
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Đã sao chép lời nhắn gửi kèm (không có mật khẩu).',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.message_outlined, size: 18),
                label: const Text('Sao chép lời nhắn gửi kèm'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(result),
            child: const Text('Xong'),
          ),
        ],
      ),
    );
  }
}

/// One way to lock the zip, as a card that reads clearly when chosen.
class _EncryptionCard extends StatelessWidget {
  const _EncryptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected ? accent.withValues(alpha: 0.08) : null,
            border: Border.all(
              color: selected ? accent : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? accent : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? accent : theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
