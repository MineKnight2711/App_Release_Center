import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/safe_controller.dart';
import '../models/safe_item.dart';
import '../services/safe_password_tools.dart';
import '../widgets/safe_look.dart';
import '../widgets/safe_metal.dart';
import 'safe_dialogs.dart';
import 'safe_item_editor.dart';
import 'safe_share_dialog.dart';

const _mono = TextStyle(
  fontFamily: 'JetBrains Mono',
  fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New'],
  fontSize: 13,
  height: 1.4,
);

/// JSON fields whose value is itself a secret and stays hidden with the
/// document, even in the summary.
bool _isSecretJsonKey(String key) => RegExp(
  r'private|secret|password|passwd|token|credential|api_?key',
  caseSensitive: false,
).hasMatch(key);

/// One opened deposit box: every field of [item], each hidden until asked.
class SafeItemDetail extends StatefulWidget {
  const SafeItemDetail({
    super.key,
    required this.safe,
    required this.item,
    this.onClose,
  });

  final SafeController safe;
  final SafeItem item;

  /// Shown as a close button when the detail sits in a dialog.
  final VoidCallback? onClose;

  @override
  State<SafeItemDetail> createState() => _SafeItemDetailState();
}

class _SafeItemDetailState extends State<SafeItemDetail> {
  final _revealed = <String>{};
  String _notice = '';

  SafeItem get _item => widget.item;

  @override
  void didUpdateWidget(SafeItemDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Opening another box starts with everything hidden again.
    if (oldWidget.item.id != widget.item.id) {
      _revealed.clear();
      _notice = '';
    }
  }

  bool _isShown(String field) => _revealed.contains(field);

  void _toggle(String field) => setState(() {
    if (!_revealed.remove(field)) _revealed.add(field);
    widget.safe.touch();
  });

  Future<void> _copy(String value, String what) async {
    await widget.safe.copySecret(value);
    if (!mounted) return;
    final seconds = widget.safe.settings.clipboardSeconds;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            'Đã sao chép $what · tự xoá khỏi clipboard sau $seconds giây.',
          ),
        ),
      );
  }

  Future<void> _export(List<int> bytes) async {
    final location = await file_selector.getSaveLocation(
      suggestedName: suggestedExportName(_item),
    );
    if (location == null) return;
    try {
      await File(location.path).writeAsBytes(bytes, flush: true);
      setState(
        () =>
            _notice = 'Đã xuất ra ${location.path}. Tệp này KHÔNG được mã hoá.',
      );
    } catch (error) {
      setState(() => _notice = 'Không xuất được: $error');
    }
  }

  Future<void> _edit() async {
    await showSafeItemEditor(context, widget.safe, _item);
  }

  Future<void> _delete() async {
    final confirmed = await confirmSafeAction(
      context,
      title: 'Xoá khỏi két?',
      message: '"${_item.title}" sẽ bị xoá hẳn khỏi két. Không hoàn tác được.',
      confirmLabel: 'Xoá',
      danger: true,
      icon: Icons.delete_forever_outlined,
    );
    if (!confirmed) return;
    final removed = await widget.safe.remove(_item.id);
    if (removed) widget.onClose?.call();
  }

  Future<void> _share() async {
    await showSafeShareDialog(context, widget.safe, _item);
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    if (uri != null) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steel = SafeSteel.of(context);
    final kind = _item.kind;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: steel.boxFace,
        ),
        border: Border.all(color: steel.boxEdge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: steel.dark ? 0.45 : 0.15),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The box's lid: a coloured strip with the kind.
          Container(height: 4, color: kind.tint),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kind.tint.withValues(alpha: 0.16),
                    border: Border.all(color: kind.tint.withValues(alpha: 0.4)),
                  ),
                  child: Icon(kind.icon, color: kind.tint, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _item.title,
                        key: const Key('safe-detail-title'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(kind.label, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _item.favorite ? 'Bỏ ghim' : 'Ghim lên đầu',
                  onPressed: () => widget.safe.toggleFavorite(_item.id),
                  icon: Icon(
                    _item.favorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: _item.favorite ? const Color(0xFFE0A526) : null,
                  ),
                ),
                IconButton(
                  key: const Key('safe-detail-share'),
                  tooltip: 'Chia sẻ qua link',
                  onPressed: _share,
                  icon: const Icon(Icons.link_rounded),
                ),
                IconButton(
                  key: const Key('safe-detail-edit'),
                  tooltip: 'Sửa',
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Xoá',
                  onPressed: _delete,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: theme.colorScheme.error,
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: steel.boxEdge),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ..._fields(context),
                if (_item.notes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _Label('Ghi chú'),
                  const SizedBox(height: 6),
                  SelectableText(
                    _item.notes,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                if (_item.project.isNotEmpty || _item.source.isNotEmpty)
                  const SizedBox(height: 14),
                if (_item.project.isNotEmpty)
                  _FieldRow(label: 'Dự án', value: _item.project),
                if (_item.source.isNotEmpty)
                  _FieldRow(
                    label: 'Nguồn',
                    value: _item.source,
                    onCopy: () => _copy(_item.source, 'đường dẫn nguồn'),
                  ),
                if (_notice.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    _notice,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  'Cất lúc ${formatSafeTimestamp(_item.createdAt)} · '
                  'sửa lúc ${formatSafeTimestamp(_item.updatedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _fields(BuildContext context) {
    switch (_item.kind) {
      case SafeItemKind.password:
        return [
          if (_item.username.isNotEmpty)
            _FieldRow(
              label: 'Tài khoản',
              value: _item.username,
              onCopy: () => _copy(_item.username, 'tài khoản'),
            ),
          if (_item.secret.isNotEmpty) ...[
            _FieldRow(
              key: const Key('safe-detail-secret'),
              label: 'Mật khẩu',
              value: _item.secret,
              hidden: !_isShown('secret'),
              onToggle: () => _toggle('secret'),
              onCopy: () => _copy(_item.secret, 'mật khẩu'),
              trailing: _StrengthChip(strength: ratePassword(_item.secret)),
            ),
          ],
          if (_item.url.isNotEmpty)
            _FieldRow(
              label: 'Trang web',
              value: _item.url,
              onCopy: () => _copy(_item.url, 'địa chỉ'),
              onOpen: () => _open(_item.url),
            ),
        ];
      case SafeItemKind.apiKey:
        return [
          _FieldRow(
            key: const Key('safe-detail-secret'),
            label: 'Key',
            value: _item.secret,
            hidden: !_isShown('secret'),
            onToggle: () => _toggle('secret'),
            onCopy: () => _copy(_item.secret, 'key'),
          ),
          if (_item.url.isNotEmpty)
            _FieldRow(
              label: 'Dashboard',
              value: _item.url,
              onCopy: () => _copy(_item.url, 'địa chỉ'),
              onOpen: () => _open(_item.url),
            ),
        ];
      case SafeItemKind.env:
        return _envFields(context);
      case SafeItemKind.jsonKey:
        return _jsonFields(context);
      case SafeItemKind.note:
        return [
          _BlockField(
            label: 'Nội dung',
            text: _item.secret,
            hidden: !_isShown('secret'),
            onToggle: () => _toggle('secret'),
            onCopy: () => _copy(_item.secret, 'ghi chú'),
          ),
        ];
      case SafeItemKind.file:
        return _fileFields(context);
    }
  }

  List<Widget> _envFields(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _item.envEntries;
    final showValues = _isShown('values');
    return [
      Row(
        children: [
          _Label('${entries.length} biến'),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _toggle('values'),
            icon: Icon(
              showValues
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 16,
            ),
            label: Text(showValues ? 'Ẩn giá trị' : 'Hiện giá trị'),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            for (final (index, entry) in entries.entries.indexed)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                decoration: BoxDecoration(
                  border: index == 0
                      ? null
                      : Border(
                          top: BorderSide(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: SelectableText(
                        entry.key,
                        style: _mono.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 6,
                      child: showValues
                          ? SelectableText(
                              entry.value,
                              style: _mono.copyWith(fontSize: 12.5),
                            )
                          : Text(
                              _dots(entry.value),
                              style: _mono.copyWith(
                                fontSize: 12.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.clip,
                              maxLines: 1,
                            ),
                    ),
                    IconButton(
                      tooltip: 'Sao chép giá trị',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: () => _copy(entry.value, entry.key),
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
              ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Không đọc được dòng KEY=VALUE nào.'),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => _copy(_item.secret, 'cả file env'),
            icon: const Icon(Icons.copy_all_rounded, size: 18),
            label: const Text('Sao chép cả file'),
          ),
          OutlinedButton.icon(
            onPressed: () => _export(utf8.encode(_item.secret)),
            icon: const Icon(Icons.save_alt_rounded, size: 18),
            label: const Text('Xuất .env'),
          ),
          TextButton.icon(
            onPressed: () => _toggle('raw'),
            icon: const Icon(Icons.code_rounded, size: 18),
            label: Text(_isShown('raw') ? 'Ẩn bản gốc' : 'Xem bản gốc'),
          ),
        ],
      ),
      if (_isShown('raw')) ...[
        const SizedBox(height: 10),
        _CodeBox(text: _item.secret),
      ],
    ];
  }

  List<Widget> _jsonFields(BuildContext context) {
    final value = _item.jsonValue;
    final summary = <MapEntry<String, String>>[
      if (value is Map)
        for (final entry in value.entries)
          if (entry.value is String ||
              entry.value is num ||
              entry.value is bool)
            if (!_isSecretJsonKey('${entry.key}'))
              MapEntry('${entry.key}', '${entry.value}'),
    ];
    final hiddenKeys = value is Map
        ? [
            for (final key in value.keys)
              if (_isSecretJsonKey('$key')) '$key',
          ]
        : const <String>[];
    final pretty = value == null
        ? _item.secret
        : const JsonEncoder.withIndent('  ').convert(value);

    return [
      if (value == null)
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text('Nội dung không còn là JSON hợp lệ.'),
        ),
      for (final entry in summary.take(8))
        _FieldRow(
          label: entry.key,
          value: entry.value,
          onCopy: () => _copy(entry.value, entry.key),
        ),
      if (hiddenKeys.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Trường bí mật luôn ẩn ở trên: ${hiddenKeys.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      _BlockField(
        label: 'Toàn bộ JSON',
        text: pretty,
        hidden: !_isShown('secret'),
        onToggle: () => _toggle('secret'),
        onCopy: () => _copy(_item.secret, 'JSON'),
        extra: OutlinedButton.icon(
          onPressed: () => _export(utf8.encode(_item.secret)),
          icon: const Icon(Icons.save_alt_rounded, size: 18),
          label: const Text('Xuất .json'),
        ),
      ),
    ];
  }

  /// Decoding and hashing a 10 MB keystore on every rebuild would stall the
  /// panel, so both are kept until the box or its file changes.
  (String, DateTime, Uint8List, String)? _fileCache;

  (Uint8List, String) _fileFacts() {
    final cached = _fileCache;
    if (cached != null &&
        cached.$1 == _item.id &&
        cached.$2 == _item.updatedAt) {
      return (cached.$3, cached.$4);
    }
    final bytes = _item.fileBytes;
    final fingerprint = SHA256Digest()
        .process(bytes)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    _fileCache = (_item.id, _item.updatedAt, bytes, fingerprint);
    return (bytes, fingerprint);
  }

  List<Widget> _fileFields(BuildContext context) {
    final theme = Theme.of(context);
    final (bytes, fingerprint) = _fileFacts();
    return [
      _FieldRow(
        label: 'Tên tệp',
        value: _item.fileName.isEmpty ? '(không tên)' : _item.fileName,
      ),
      _FieldRow(label: 'Kích thước', value: formatByteSize(bytes.length)),
      _FieldRow(
        label: 'SHA-256',
        value: fingerprint,
        onCopy: () => _copy(fingerprint, 'SHA-256'),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: bytes.isEmpty ? null : () => _export(bytes),
            icon: const Icon(Icons.save_alt_rounded, size: 18),
            label: const Text('Xuất tệp…'),
          ),
          OutlinedButton.icon(
            onPressed: bytes.isEmpty
                ? null
                : () => _copy(_item.secret, 'base64 của tệp'),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Sao chép base64'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        'Base64 tiện dán vào secret của CI (GitHub Actions, Codemagic…).',
        style: theme.textTheme.bodySmall,
      ),
    ];
  }
}

String _dots(String value) =>
    value.isEmpty ? '(trống)' : '•' * value.length.clamp(6, 18);

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.9,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

/// A labelled one-line value with reveal, copy and open controls.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.label,
    required this.value,
    this.hidden = false,
    this.onToggle,
    this.onCopy,
    this.onOpen,
    this.trailing,
  });

  final String label;
  final String value;
  final bool hidden;
  final VoidCallback? onToggle;
  final VoidCallback? onCopy;
  final VoidCallback? onOpen;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: _Label(label)),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.only(left: 12, right: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.55,
              ),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: hidden
                        ? Text(
                            _dots(value),
                            style: _mono,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                          )
                        : SelectableText(value, style: _mono),
                  ),
                ),
                if (onToggle != null)
                  IconButton(
                    tooltip: hidden ? 'Hiện' : 'Ẩn',
                    visualDensity: VisualDensity.compact,
                    onPressed: onToggle,
                    icon: Icon(
                      hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                    ),
                  ),
                if (onOpen != null)
                  IconButton(
                    tooltip: 'Mở',
                    visualDensity: VisualDensity.compact,
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  ),
                if (onCopy != null)
                  IconButton(
                    tooltip: 'Sao chép',
                    visualDensity: VisualDensity.compact,
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A multi-line secret: hidden as a placeholder until revealed.
class _BlockField extends StatelessWidget {
  const _BlockField({
    required this.label,
    required this.text,
    required this.hidden,
    required this.onToggle,
    required this.onCopy,
    this.extra,
  });

  final String label;
  final String text;
  final bool hidden;
  final VoidCallback onToggle;
  final VoidCallback onCopy;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(label),
        const SizedBox(height: 6),
        if (hidden)
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 96,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.55,
                ),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.visibility_off_outlined),
                  const SizedBox(height: 6),
                  Text(
                    'Đang ẩn ${text.length} ký tự · bấm để hiện',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          )
        else
          _CodeBox(text: text),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Sao chép'),
            ),
            OutlinedButton.icon(
              onPressed: onToggle,
              icon: Icon(
                hidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
              ),
              label: Text(hidden ? 'Hiện' : 'Ẩn'),
            ),
            ?extra,
          ],
        ),
      ],
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText(text, style: _mono.copyWith(fontSize: 12.5)),
      ),
    );
  }
}

class _StrengthChip extends StatelessWidget {
  const _StrengthChip({required this.strength});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final color = switch (strength.level) {
      1 => Theme.of(context).colorScheme.error,
      2 => const Color(0xFFE0A526),
      _ => const Color(0xFF3DBE7A),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        strength.label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
