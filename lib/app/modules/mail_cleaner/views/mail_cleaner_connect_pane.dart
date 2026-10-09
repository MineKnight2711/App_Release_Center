import 'package:flutter/material.dart';

import '../controllers/mail_cleaner_controller.dart';
import '../../shared/module_widgets.dart';

/// The servers worth one click, plus the escape hatch for anything else.
enum _ServerPreset {
  emailPro('Email Pro GTEL', 'pro216.emailserver.vn', 993),
  gmail('Google Gmail', 'imap.gmail.com', 993),
  custom('Tùy chỉnh', null, null);

  const _ServerPreset(this.label, this.host, this.port);

  final String label;
  final String? host;
  final int? port;
}

/// Asks for the mailbox to clean and opens the IMAP connection.
class MailCleanerConnectPane extends StatefulWidget {
  const MailCleanerConnectPane({super.key, required this.controller});

  final MailCleanerController controller;

  @override
  State<MailCleanerConnectPane> createState() => _MailCleanerConnectPaneState();
}

class _MailCleanerConnectPaneState extends State<MailCleanerConnectPane> {
  final _form = GlobalKey<FormState>();
  late final _host = TextEditingController(text: widget.controller.host);
  late final _port = TextEditingController(text: '${widget.controller.port}');
  late final _account = TextEditingController(text: widget.controller.account);
  late final _password = TextEditingController(
    text: widget.controller.savedPassword ?? '',
  );
  bool _showPassword = false;
  late _ServerPreset _preset = _presetForHost(_host.text);

  MailCleanerController get controller => widget.controller;

  static _ServerPreset _presetForHost(String host) {
    final lower = host.toLowerCase();
    if (lower.contains('gmail')) return _ServerPreset.gmail;
    if (lower.contains('emailserver') || lower.contains('gtel')) {
      return _ServerPreset.emailPro;
    }
    return _ServerPreset.custom;
  }

  bool get _isGmail =>
      _preset == _ServerPreset.gmail ||
      _host.text.toLowerCase().contains('gmail');

  void _choosePreset(_ServerPreset preset) {
    setState(() {
      _preset = preset;
      if (preset.host != null) _host.text = preset.host!;
      if (preset.port != null) _port.text = '${preset.port}';
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_form.currentState!.validate()) return;
    await controller.connect(
      host: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      account: _account.text.trim(),
      password: _password.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connecting = controller.stage == MailCleanerStage.connecting;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Kết nối máy chủ', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Chọn cấu hình máy chủ sẵn có hoặc tự nhập thông số IMAP. '
                'App chỉ đọc tiêu đề và dung lượng thư để gom nhóm.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in _ServerPreset.values)
                    // Styled explicitly: the shell's theme leaves chips alone,
                    // and the default selected colours read as disabled on the
                    // Cyber palette.
                    ChoiceChip(
                      label: Text(preset.label),
                      selected: _preset == preset,
                      showCheckmark: false,
                      selectedColor: theme.colorScheme.primary.withValues(
                        alpha: 0.16,
                      ),
                      side: BorderSide(
                        color: _preset == preset
                            ? theme.colorScheme.primary.withValues(alpha: 0.6)
                            : theme.colorScheme.outlineVariant,
                      ),
                      labelStyle: theme.textTheme.labelLarge?.copyWith(
                        color: _preset == preset
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                      onSelected: connecting
                          ? null
                          : (_) => _choosePreset(preset),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ModuleCard(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _field(
                              controller: _host,
                              label: 'Máy chủ IMAP',
                              icon: Icons.dns_outlined,
                              emptyError: 'Chưa nhập host',
                              onChanged: (value) => setState(
                                () => _preset = _presetForHost(value),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              controller: _port,
                              label: 'Cổng',
                              icon: Icons.numbers,
                              validator: (value) {
                                final port = int.tryParse(value ?? '');
                                if (port == null || port < 1 || port > 65535) {
                                  return 'Sai';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _field(
                        controller: _account,
                        label: 'Địa chỉ email',
                        hint: 'user@gtelcts.vn',
                        icon: Icons.person_outline,
                        emptyError: 'Chưa nhập tài khoản email',
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: !_showPassword,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _connect(),
                        validator: (value) => (value == null || value.isEmpty)
                            ? 'Chưa nhập mật khẩu hoặc App Password'
                            : null,
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _showPassword ? 'Ẩn' : 'Hiện',
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      CheckboxListTile(
                        value: controller.rememberPassword,
                        onChanged: connecting
                            ? null
                            : (value) => controller.setRememberPassword(
                                value ?? false,
                              ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Nhớ mật khẩu trên máy này'),
                        subtitle: Text(
                          controller.rememberPassword
                              ? 'Mật khẩu được lưu trong kho bảo mật của '
                                    'Windows, chỉ trên máy này.'
                              : 'Đang tắt: mật khẩu chỉ dùng cho phiên này, '
                                    'không lưu xuống đĩa.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (_isGmail) ...[
                        const SizedBox(height: 14),
                        const NoticeBox(
                          icon: Icons.key_outlined,
                          text:
                              'Gmail yêu cầu "Mật khẩu ứng dụng" 16 ký tự. '
                              'Vào Tài khoản Google → Bảo mật → Xác minh 2 '
                              'bước → Mật khẩu ứng dụng, tạo mã rồi dán vào '
                              'ô trên.',
                        ),
                      ],
                      if (controller.error != null) ...[
                        const SizedBox(height: 14),
                        NoticeBox(
                          text: controller.error!,
                          tone: NoticeTone.danger,
                          icon: Icons.error_outline,
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: connecting ? null : _connect,
                        icon: connecting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login_rounded, size: 18),
                        label: Text(
                          connecting
                              ? 'Đang kết nối tới máy chủ…'
                              : 'Bắt đầu kết nối',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_isGmail)
                const NoticeBox(
                  icon: Icons.restore_from_trash_outlined,
                  text:
                      'Gmail: thư được chuyển vào Thùng rác nên còn 30 ngày để '
                      'lấy lại. Muốn giải phóng dung lượng ngay thì dọn Thùng '
                      'rác trong Gmail.',
                )
              else
                const NoticeBox(
                  tone: NoticeTone.warning,
                  text:
                      'Máy chủ Email Pro không đưa thư vào Thùng rác. App tách '
                      'làm hai bước: gắn cờ (hoàn tác được) rồi mới xoá thật. '
                      'Hãy luôn xem kỹ trước khi sang bước hai.',
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? emptyError,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      validator:
          validator ??
          (emptyError == null
              ? null
              : (value) => (value == null || value.trim().isEmpty)
                    ? emptyError
                    : null),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }
}
