import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../shared/module_widgets.dart';
import '../controllers/safe_controller.dart';
import '../models/safe_item.dart';
import '../services/safe_password_tools.dart';
import '../widgets/safe_look.dart';
import 'safe_dialogs.dart';

/// Largest file a deposit box takes. The whole safe is decrypted into memory
/// and rewritten on every save, so it is meant for keys and keystores, not
/// for archives.
const safeMaxFileBytes = 10 * 1024 * 1024;

/// Turns a file dropped or picked into a draft of the right kind: a `.env`
/// becomes an env item, a JSON document a JSON key, anything else a file.
Future<SafeItem> safeDraftFromFile(SafeController safe, String path) async {
  final file = File(path);
  final size = await file.length();
  if (size > safeMaxFileBytes) {
    throw SafeEditorException(
      '${p.basename(path)} nặng ${formatByteSize(size)}, '
      'quá giới hạn ${formatByteSize(safeMaxFileBytes)} của một ngăn.',
    );
  }
  final name = p.basename(path);
  final lower = name.toLowerCase();
  final bytes = await file.readAsBytes();
  String? text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    text = null;
  }

  final looksLikeEnv =
      lower == '.env' || lower.startsWith('.env.') || lower.endsWith('.env');
  if (text != null && looksLikeEnv) {
    return safe.draft(SafeItemKind.env).copyWith(title: name, secret: text);
  }
  if (text != null && lower.endsWith('.json')) {
    try {
      jsonDecode(text);
      return safe
          .draft(SafeItemKind.jsonKey)
          .copyWith(title: name, secret: text);
    } on FormatException {
      // Not JSON after all: kept byte for byte as a file.
    }
  }
  return safe
      .draft(SafeItemKind.file)
      .copyWith(title: name, fileName: name, secret: base64Encode(bytes));
}

class SafeEditorException implements Exception {
  const SafeEditorException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Opens the editor for [item]. Returns whether it was saved into the safe.
Future<bool> showSafeItemEditor(
  BuildContext context,
  SafeController safe,
  SafeItem item, {
  bool isNew = false,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SafeItemEditor(safe: safe, item: item, isNew: isNew),
  );
  return saved ?? false;
}

class _SafeItemEditor extends StatefulWidget {
  const _SafeItemEditor({
    required this.safe,
    required this.item,
    required this.isNew,
  });

  final SafeController safe;
  final SafeItem item;
  final bool isNew;

  @override
  State<_SafeItemEditor> createState() => _SafeItemEditorState();
}

class _SafeItemEditorState extends State<_SafeItemEditor> {
  late final _title = TextEditingController(text: widget.item.title);
  late final _username = TextEditingController(text: widget.item.username);
  late final _secret = TextEditingController(
    text: widget.item.kind == SafeItemKind.file ? '' : widget.item.secret,
  );
  late final _url = TextEditingController(text: widget.item.url);
  late final _notes = TextEditingController(text: widget.item.notes);
  late final _project = TextEditingController(text: widget.item.project);
  final _projectFocus = FocusNode();
  late String _fileName = widget.item.fileName;
  late String _fileData = widget.item.kind == SafeItemKind.file
      ? widget.item.secret
      : '';

  bool _showSecret = false;
  bool _saving = false;
  String _error = '';

  SafeItemKind get _kind => widget.item.kind;

  @override
  void initState() {
    super.initState();
    // A new secret starts visible: it is being typed, not shoulder-surfed.
    _showSecret = widget.isNew && _kind != SafeItemKind.password;
  }

  @override
  void dispose() {
    _title.dispose();
    _username.dispose();
    _secret.dispose();
    _url.dispose();
    _notes.dispose();
    _project.dispose();
    _projectFocus.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_title.text.trim().isEmpty) return 'Đặt tên cho mục này.';
    switch (_kind) {
      case SafeItemKind.file:
        if (_fileData.isEmpty) return 'Chọn tệp cần cất vào két.';
      case SafeItemKind.jsonKey:
        if (_secret.text.trim().isEmpty) return 'Dán nội dung JSON.';
        try {
          jsonDecode(_secret.text);
        } on FormatException catch (error) {
          return 'JSON không hợp lệ: ${error.message}';
        }
      case SafeItemKind.password:
        if (_secret.text.isEmpty && _username.text.trim().isEmpty) {
          return 'Nhập ít nhất tài khoản hoặc mật khẩu.';
        }
      default:
        if (_secret.text.trim().isEmpty) return 'Nội dung đang trống.';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    final item = widget.item.copyWith(
      title: _title.text.trim(),
      username: _kind == SafeItemKind.password ? _username.text.trim() : '',
      secret: _kind == SafeItemKind.file ? _fileData : _secret.text,
      url: _url.text.trim(),
      notes: _notes.text.trimRight(),
      project: _project.text.trim(),
      // A non-file secret keeps the name of the file it came from, if any.
      fileName: _kind == SafeItemKind.file ? _fileName : widget.item.fileName,
    );
    final saved = await widget.safe.put(item);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = widget.safe.error.isEmpty
            ? 'Không lưu được.'
            : widget.safe.error;
      });
    }
  }

  Future<void> _importText() async {
    final file = await file_selector.openFile();
    if (file == null) return;
    try {
      final size = await file.length();
      if (size > safeMaxFileBytes) {
        setState(() => _error = 'Tệp quá lớn (${formatByteSize(size)}).');
        return;
      }
      final text = await file.readAsString();
      setState(() {
        _secret.text = text;
        if (_title.text.trim().isEmpty) _title.text = file.name;
        _error = '';
      });
    } on FormatException {
      setState(() => _error = '${file.name} không phải tệp văn bản.');
    }
  }

  Future<void> _pickFile() async {
    final file = await file_selector.openFile();
    if (file == null) return;
    final size = await file.length();
    if (size > safeMaxFileBytes) {
      setState(
        () => _error =
            '${file.name} nặng ${formatByteSize(size)}, quá giới hạn '
            '${formatByteSize(safeMaxFileBytes)}.',
      );
      return;
    }
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = file.name;
      _fileData = base64Encode(bytes);
      if (_title.text.trim().isEmpty) _title.text = file.name;
      _error = '';
    });
  }

  void _formatJson() {
    try {
      final value = jsonDecode(_secret.text);
      setState(() {
        _secret.text = const JsonEncoder.withIndent('  ').convert(value);
        _error = '';
      });
    } on FormatException catch (error) {
      setState(() => _error = 'JSON không hợp lệ: ${error.message}');
    }
  }

  Future<void> _generate() async {
    final value = await showPasswordGenerator(context);
    if (value != null) {
      setState(() {
        _secret.text = value;
        _showSecret = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = const TextStyle(
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New'],
      fontSize: 13,
    );

    Widget revealButton() => IconButton(
      tooltip: _showSecret ? 'Ẩn' : 'Hiện',
      onPressed: () => setState(() => _showSecret = !_showSecret),
      icon: Icon(
        _showSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
    );

    final fields = <Widget>[
      TextField(
        key: const Key('safe-editor-title'),
        controller: _title,
        autofocus: widget.isNew && _title.text.isEmpty,
        decoration: InputDecoration(
          labelText: 'Tên',
          hintText: switch (_kind) {
            SafeItemKind.password => 'VD: GitHub công ty',
            SafeItemKind.apiKey => 'VD: OpenAI production',
            SafeItemKind.env => 'VD: .env.production app X',
            SafeItemKind.jsonKey => 'VD: Play Console service account',
            SafeItemKind.note => 'VD: Mã khôi phục 2FA',
            SafeItemKind.file => 'VD: upload-keystore app X',
          },
        ),
      ),
      const SizedBox(height: 12),
      ...switch (_kind) {
        SafeItemKind.password => [
          TextField(
            controller: _username,
            decoration: const InputDecoration(
              labelText: 'Tài khoản / email',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('safe-editor-secret'),
            controller: _secret,
            obscureText: !_showSecret,
            autocorrect: false,
            enableSuggestions: false,
            style: mono,
            decoration: InputDecoration(
              labelText: 'Mật khẩu',
              prefixIcon: const Icon(Icons.password_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  revealButton(),
                  IconButton(
                    tooltip: 'Tạo mật khẩu mạnh',
                    onPressed: _generate,
                    icon: const Icon(Icons.casino_outlined),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: _secret,
            builder: (context, _) =>
                PasswordStrengthBar(strength: ratePassword(_secret.text)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'Trang web (tuỳ chọn)',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          ),
        ],
        SafeItemKind.apiKey => [
          TextField(
            key: const Key('safe-editor-secret'),
            controller: _secret,
            obscureText: !_showSecret,
            autocorrect: false,
            enableSuggestions: false,
            style: mono,
            maxLines: _showSecret ? 4 : 1,
            minLines: 1,
            decoration: InputDecoration(
              labelText: 'Key / token / secret',
              prefixIcon: const Icon(Icons.vpn_key_outlined),
              suffixIcon: revealButton(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'Dashboard / tài liệu (tuỳ chọn)',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          ),
        ],
        SafeItemKind.env || SafeItemKind.jsonKey || SafeItemKind.note => [
          Row(
            children: [
              Text(switch (_kind) {
                SafeItemKind.env => 'Nội dung .env',
                SafeItemKind.jsonKey => 'Nội dung JSON',
                _ => 'Nội dung',
              }, style: theme.textTheme.labelLarge),
              const Spacer(),
              if (_kind != SafeItemKind.note)
                TextButton.icon(
                  onPressed: _importText,
                  icon: const Icon(Icons.file_open_outlined, size: 16),
                  label: const Text('Lấy từ tệp'),
                ),
              if (_kind == SafeItemKind.jsonKey)
                TextButton.icon(
                  onPressed: _formatJson,
                  icon: const Icon(Icons.format_align_left_rounded, size: 16),
                  label: const Text('Định dạng'),
                ),
              revealButton(),
            ],
          ),
          const SizedBox(height: 4),
          if (_showSecret)
            TextField(
              key: const Key('safe-editor-secret'),
              controller: _secret,
              minLines: 8,
              maxLines: 16,
              autocorrect: false,
              enableSuggestions: false,
              style: mono,
              decoration: InputDecoration(
                hintText: switch (_kind) {
                  SafeItemKind.env => 'API_URL=https://...\nAPI_KEY=...',
                  SafeItemKind.jsonKey =>
                    '{\n  "type": "service_account",\n  ...\n}',
                  _ => 'Văn bản cần giữ bí mật',
                },
                alignLabelWithHint: true,
              ),
            )
          else
            _HiddenBlock(
              length: _secret.text.length,
              onReveal: () => setState(() => _showSecret = true),
            ),
          const SizedBox(height: 6),
          ListenableBuilder(
            listenable: _secret,
            builder: (context, _) =>
                _ContentHint(kind: _kind, text: _secret.text),
          ),
        ],
        SafeItemKind.file => [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(
                  SafeItemKind.file.icon,
                  color: SafeItemKind.file.tint,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _fileData.isEmpty
                      ? const Text('Chưa chọn tệp')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_fileName, style: theme.textTheme.titleSmall),
                            Text(
                              formatByteSize(
                                widget.item
                                    .copyWith(secret: _fileData)
                                    .fileSize,
                              ),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                ),
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(_fileData.isEmpty ? 'Chọn tệp…' : 'Đổi tệp…'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Keystore (.jks), khoá App Store (.p8), chứng chỉ (.pem, .p12)… '
            'tối đa ${formatByteSize(safeMaxFileBytes)}.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      },
      const SizedBox(height: 12),
      _ProjectField(
        controller: _project,
        focusNode: _projectFocus,
        projects: widget.safe.projects,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _notes,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'Ghi chú (tuỳ chọn)',
          alignLabelWithHint: true,
        ),
      ),
      if (_error.isNotEmpty) ...[
        const SizedBox(height: 12),
        NoticeBox(text: _error, tone: NoticeTone.danger),
      ],
    ];

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kind.tint.withValues(alpha: 0.16),
            ),
            child: Icon(_kind.icon, color: _kind.tint, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isNew
                      ? 'Cất vào két · ${_kind.label}'
                      : 'Sửa · ${_kind.label}',
                ),
                Text(_kind.description, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: fields,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Huỷ'),
        ),
        FilledButton.icon(
          key: const Key('safe-editor-save'),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_rounded, size: 18),
          label: Text(widget.isNew ? 'Cất vào két' : 'Lưu'),
        ),
      ],
    );
  }
}

/// Stands in for a long secret while it is hidden.
class _HiddenBlock extends StatelessWidget {
  const _HiddenBlock({required this.length, required this.onReveal});

  final int length;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onReveal,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_off_outlined),
            const SizedBox(height: 6),
            Text(
              length == 0
                  ? 'Trống · bấm để nhập'
                  : 'Đang ẩn $length ký tự · bấm để hiện',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// A live read of what the pasted text turns into.
class _ContentHint extends StatelessWidget {
  const _ContentHint({required this.kind, required this.text});

  final SafeItemKind kind;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final (ok, message) = switch (kind) {
      SafeItemKind.env => () {
        final count = SafeItem(
          id: '',
          kind: SafeItemKind.env,
          title: '',
          secret: text,
          createdAt: DateTime(0),
          updatedAt: DateTime(0),
        ).envEntries.length;
        return (
          count > 0,
          count > 0 ? 'Đọc được $count biến.' : 'Chưa thấy dòng KEY=VALUE nào.',
        );
      }(),
      SafeItemKind.jsonKey => () {
        try {
          final value = jsonDecode(text);
          return (
            true,
            value is Map
                ? 'JSON hợp lệ · ${value.length} trường.'
                : 'JSON hợp lệ.',
          );
        } on FormatException catch (error) {
          return (false, 'JSON chưa hợp lệ: ${error.message}');
        }
      }(),
      _ => (true, '${text.length} ký tự.'),
    };
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
          size: 15,
          color: ok ? const Color(0xFF3DBE7A) : theme.colorScheme.error,
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}

/// The project a secret belongs to, suggesting the ones already in the safe.
class _ProjectField extends StatelessWidget {
  const _ProjectField({
    required this.controller,
    required this.focusNode,
    required this.projects,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> projects;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        return projects.where(
          (project) =>
              project.toLowerCase().contains(query) &&
              project.toLowerCase() != query,
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          TextField(
            key: const Key('safe-editor-project'),
            controller: controller,
            focusNode: focusNode,
            onSubmitted: (_) => onSubmitted(),
            decoration: const InputDecoration(
              labelText: 'Dự án (tuỳ chọn)',
              hintText: 'Gom khoá theo dự án, VD: Shop app',
              prefixIcon: Icon(Icons.folder_special_outlined),
            ),
          ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 420),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final option in options)
                  ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.folder_special_outlined,
                      size: 18,
                    ),
                    title: Text(option),
                    onTap: () => onSelected(option),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
