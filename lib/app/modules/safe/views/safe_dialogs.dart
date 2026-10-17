import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';

import '../../shared/module_widgets.dart';
import '../controllers/safe_controller.dart';
import '../models/safe_item.dart';
import '../services/safe_password_tools.dart';

const _vaultTypes = [
  file_selector.XTypeGroup(label: 'Két AMC', extensions: ['vault']),
  file_selector.XTypeGroup(label: 'Mọi tệp'),
];

Future<bool> confirmSafeAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
  IconData icon = Icons.help_outline_rounded,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(icon, color: danger ? scheme.error : null),
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(message),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for a safe code in a dialog. Null when cancelled.
Future<String?> askSafeCode(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Mở',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _CodeDialog(title: title, message: message, confirmLabel: confirmLabel),
  );
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final String title;
  final String? message;
  final String confirmLabel;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();
  bool _show = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    if (_code.text.isEmpty) return;
    Navigator.pop(context, _code.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.lock_outline_rounded),
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[
              Text(widget.message!),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _code,
              autofocus: true,
              obscureText: !_show,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Mã két',
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _show = !_show),
                  icon: Icon(
                    _show
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// Picks a backup, asks its code and makes it this machine's safe. Returns
/// what to tell the person, or null when they backed out.
Future<String?> restoreSafeBackup(
  BuildContext context,
  SafeController safe,
) async {
  if (safe.isOpen) {
    final proceed = await confirmSafeAction(
      context,
      title: 'Khôi phục từ bản sao lưu?',
      message:
          'Két hiện tại sẽ được thay bằng nội dung của bản sao lưu. Bản hiện '
          'tại không bị xoá: nó được giữ lại cạnh file két với đuôi '
          '.before-restore.',
      confirmLabel: 'Chọn bản sao lưu',
      icon: Icons.settings_backup_restore_rounded,
    );
    if (!proceed) return null;
  }
  final file = await file_selector.openFile(acceptedTypeGroups: _vaultTypes);
  if (file == null || !context.mounted) return null;
  final code = await askSafeCode(
    context,
    title: 'Mã của bản sao lưu',
    message: 'Nhập mã két lúc tạo bản sao lưu này.',
    confirmLabel: 'Khôi phục',
  );
  if (code == null) return null;
  final error = await safe.restoreBackup(file.path, code);
  return error ?? 'Đã khôi phục két từ bản sao lưu.';
}

Future<String?> exportSafeBackup(SafeController safe) async {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final location = await file_selector.getSaveLocation(
    suggestedName: 'amc-safe-${now.year}${two(now.month)}${two(now.day)}.vault',
    acceptedTypeGroups: _vaultTypes,
  );
  if (location == null) return null;
  final error = await safe.exportBackup(location.path);
  return error ??
      'Đã xuất bản sao lưu. Tệp vẫn được mã hoá, mở bằng mã két hiện tại.';
}

Future<void> showSafeSettings(BuildContext context, SafeController safe) {
  return showDialog<void>(
    context: context,
    builder: (context) => _SafeSettingsDialog(safe: safe),
  );
}

class _SafeSettingsDialog extends StatefulWidget {
  const _SafeSettingsDialog({required this.safe});

  final SafeController safe;

  @override
  State<_SafeSettingsDialog> createState() => _SafeSettingsDialogState();
}

class _SafeSettingsDialogState extends State<_SafeSettingsDialog> {
  String _message = '';
  String _path = '';

  SafeController get _safe => widget.safe;

  @override
  void initState() {
    super.initState();
    _safe.filePath.then((path) {
      if (mounted) setState(() => _path = path);
    });
  }

  Future<void> _update(SafeSettings settings) async {
    final saved = await _safe.updateSettings(settings);
    if (mounted) setState(() => _message = saved ? '' : _safe.error);
  }

  void _say(String? message) {
    if (message != null && mounted) setState(() => _message = message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _safe,
      builder: (context, _) {
        if (!_safe.isOpen) {
          // The safe locked itself while this was open: nothing here may
          // stay on screen.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).maybePop();
          });
          return const SizedBox.shrink();
        }
        final settings = _safe.settings;
        return AlertDialog(
          icon: const Icon(Icons.settings_outlined),
          title: const Text('Cài đặt két'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Tự khoá'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(child: Text('Khoá khi không dùng sau')),
                      DropdownButton<int>(
                        value:
                            SafeSettings.autoLockChoices.contains(
                              settings.autoLockMinutes,
                            )
                            ? settings.autoLockMinutes
                            : null,
                        hint: Text('${settings.autoLockMinutes} phút'),
                        items: [
                          for (final minutes in SafeSettings.autoLockChoices)
                            DropdownMenuItem(
                              value: minutes,
                              child: Text('$minutes phút'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _update(settings.copyWith(autoLockMinutes: value));
                          }
                        },
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.lockOnClose,
                    onChanged: (value) =>
                        _update(settings.copyWith(lockOnClose: value)),
                    title: const Text('Khoá ngay khi đóng màn hình két'),
                    subtitle: const Text(
                      'Tắt thì két vẫn mở trong lúc bạn đi dán mật khẩu ở chỗ khác, '
                      'đến khi hết thời gian tự khoá.',
                    ),
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Xoá clipboard sau khi sao chép'),
                      ),
                      DropdownButton<int>(
                        value:
                            SafeSettings.clipboardChoices.contains(
                              settings.clipboardSeconds,
                            )
                            ? settings.clipboardSeconds
                            : null,
                        hint: Text('${settings.clipboardSeconds} giây'),
                        items: [
                          for (final seconds in SafeSettings.clipboardChoices)
                            DropdownMenuItem(
                              value: seconds,
                              child: Text('$seconds giây'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _update(settings.copyWith(clipboardSeconds: value));
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const SectionLabel('Mã két'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _safe.isSaving
                        ? null
                        : () async {
                            final changed = await showDialog<bool>(
                              context: context,
                              builder: (_) => _ChangeCodeDialog(safe: _safe),
                            );
                            if (changed == true) _say('Đã đổi mã két.');
                          },
                    icon: const Icon(Icons.password_rounded, size: 18),
                    label: const Text('Đổi mã két'),
                  ),
                  const SizedBox(height: 18),
                  const SectionLabel('Sao lưu'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async =>
                            _say(await exportSafeBackup(_safe)),
                        icon: const Icon(Icons.save_alt_rounded, size: 18),
                        label: const Text('Xuất bản sao lưu'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async =>
                            _say(await restoreSafeBackup(context, _safe)),
                        icon: const Icon(
                          Icons.settings_backup_restore_rounded,
                          size: 18,
                        ),
                        label: const Text('Khôi phục…'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const NoticeBox(
                    text:
                        'Bản sao lưu là chính file két đã mã hoá, an toàn để cất '
                        'lên Drive hay USB. Muốn mở nó vẫn cần mã két lúc xuất.',
                  ),
                  if (_path.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'File két trên máy này',
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _path,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'JetBrains Mono',
                        fontFamilyFallback: const ['Menlo', 'Consolas'],
                      ),
                    ),
                  ],
                  if (_message.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    NoticeBox(text: _message),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Xong'),
            ),
          ],
        );
      },
    );
  }
}

class _ChangeCodeDialog extends StatefulWidget {
  const _ChangeCodeDialog({required this.safe});

  final SafeController safe;

  @override
  State<_ChangeCodeDialog> createState() => _ChangeCodeDialogState();
}

class _ChangeCodeDialogState extends State<_ChangeCodeDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    final error = await widget.safe.changeCode(
      _current.text,
      _next.text,
      _confirm.text,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String label) => InputDecoration(labelText: label);
    return AlertDialog(
      icon: const Icon(Icons.password_rounded),
      title: const Text('Đổi mã két'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _current,
              autofocus: true,
              obscureText: true,
              decoration: field('Mã hiện tại'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _next,
              obscureText: true,
              decoration: field(
                'Mã mới (ít nhất ${SafeController.minimumCodeLength} ký tự)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirm,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: field('Nhập lại mã mới'),
            ),
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: _next,
              builder: (context, _) =>
                  PasswordStrengthBar(strength: ratePassword(_next.text)),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              NoticeBox(text: _error, tone: NoticeTone.danger),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Đổi mã'),
        ),
      ],
    );
  }
}

/// A bar of four segments, filled as far as [strength] goes.
class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({super.key, required this.strength});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (strength.level) {
      0 => theme.colorScheme.outlineVariant,
      1 => theme.colorScheme.error,
      2 => const Color(0xFFE0A526),
      3 => const Color(0xFF7BC67E),
      _ => const Color(0xFF3DBE7A),
    };
    return Row(
      children: [
        for (var i = 1; i <= 4; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i <= strength.level
                    ? color
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          if (i < 4) const SizedBox(width: 4),
        ],
        const SizedBox(width: 10),
        SizedBox(
          width: 64,
          child: Text(
            strength.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// The password generator. Returns the chosen password, or null.
Future<String?> showPasswordGenerator(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _GeneratorDialog(),
  );
}

class _GeneratorDialog extends StatefulWidget {
  const _GeneratorDialog();

  @override
  State<_GeneratorDialog> createState() => _GeneratorDialogState();
}

class _GeneratorDialogState extends State<_GeneratorDialog> {
  PasswordRecipe _recipe = const PasswordRecipe();
  late String _value = generatePassword(_recipe);

  void _change(PasswordRecipe recipe) {
    if (recipe.groups.isEmpty) return;
    setState(() {
      _recipe = recipe;
      _value = generatePassword(recipe);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget toggle(
      String label,
      bool value,
      PasswordRecipe Function(bool) apply,
    ) => FilterChip(
      label: Text(label),
      selected: value,
      onSelected: (selected) => _change(apply(selected)),
    );

    return AlertDialog(
      icon: const Icon(Icons.casino_outlined),
      title: const Text('Tạo mật khẩu'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _value,
                      key: const Key('safe-generated-password'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        fontFamily: 'JetBrains Mono',
                        fontFamilyFallback: [
                          'Menlo',
                          'Consolas',
                          'Courier New',
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tạo lại',
                    onPressed: () => _change(_recipe),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            PasswordStrengthBar(strength: ratePassword(_value)),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Độ dài ${_recipe.length}',
                  style: theme.textTheme.labelLarge,
                ),
                Expanded(
                  child: Slider(
                    min: 8,
                    max: 64,
                    divisions: 56,
                    value: _recipe.length.toDouble(),
                    label: '${_recipe.length}',
                    onChanged: (value) =>
                        _change(_recipe.copyWith(length: value.round())),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                toggle('A–Z', _recipe.upper, (v) => _recipe.copyWith(upper: v)),
                toggle('a–z', _recipe.lower, (v) => _recipe.copyWith(lower: v)),
                toggle(
                  '0–9',
                  _recipe.digits,
                  (v) => _recipe.copyWith(digits: v),
                ),
                toggle(
                  '!@#',
                  _recipe.symbols,
                  (v) => _recipe.copyWith(symbols: v),
                ),
                toggle(
                  'Bỏ ký tự dễ nhầm',
                  _recipe.avoidLookalikes,
                  (v) => _recipe.copyWith(avoidLookalikes: v),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _value),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Dùng mật khẩu này'),
        ),
      ],
    );
  }
}
