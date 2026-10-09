import 'package:app_management_center/app/modules/shared/module_widgets.dart';
import 'package:app_management_center/app/services/telegram_credential_store_service.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../telegram/local_bot_server.dart';
import '../telegram/telegram_bot_client.dart';
import '../telegram/telegram_intake_service.dart';
import '../telegram/telegram_intake_store.dart';

Future<void> showTelegramBotDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => TelegramBotDialog(
      service: Get.find<TelegramIntakeService>(),
      credentials: Get.find<TelegramCredentialStoreService>(),
    ),
  );
}

/// Settings and live state of the AAB bot.
class TelegramBotDialog extends StatefulWidget {
  const TelegramBotDialog({
    super.key,
    required this.service,
    required this.credentials,
  });

  final TelegramIntakeService service;
  final TelegramCredentialStoreService credentials;

  @override
  State<TelegramBotDialog> createState() => _TelegramBotDialogState();
}

class _TelegramBotDialogState extends State<TelegramBotDialog> {
  late TelegramIntakeSettings _draft = widget.service.settings;
  late final _sentence = TextEditingController(text: _draft.downloadingMessage);
  late final _chats = TextEditingController(
    text: _draft.allowedChatIds.join(', '),
  );
  late final _users = TextEditingController(
    text: _draft.allowedUserIds.join(', '),
  );
  late final _executable = TextEditingController(text: _draft.serverExecutable);
  late final _port = TextEditingController(text: '${_draft.serverPort}');
  late final _mapFrom = TextEditingController(text: _draft.serverFilesFrom);
  late final _mapTo = TextEditingController(text: _draft.serverFilesTo);
  final _apiId = TextEditingController();
  final _apiHash = TextEditingController();
  bool _hasServerCredentials = false;
  bool _working = false;
  String? _notice;
  bool _noticeIsError = false;

  @override
  void initState() {
    super.initState();
    if (_executable.text.trim().isEmpty) {
      _executable.text = findBuiltServerExecutable() ?? '';
    }
    widget.credentials.readLocalServerCredentials().then((value) {
      if (mounted) setState(() => _hasServerCredentials = value != null);
    });
  }

  @override
  void dispose() {
    for (final controller in [
      _sentence,
      _chats,
      _users,
      _executable,
      _port,
      _mapFrom,
      _mapTo,
      _apiId,
      _apiHash,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  static List<int> _ids(String text) => [
    for (final part in text.split(RegExp(r'[\s,;]+')))
      ?int.tryParse(part.trim()),
  ];

  TelegramIntakeSettings _collect() {
    return _draft.copyWith(
      downloadingMessage: _sentence.text.trim().isEmpty
          ? TelegramIntakeSettings.defaultDownloadingMessage
          : _sentence.text.trim(),
      allowedChatIds: _ids(_chats.text),
      allowedUserIds: _ids(_users.text),
      serverExecutable: _executable.text.trim(),
      serverPort: int.tryParse(_port.text.trim()) ?? 8081,
      serverFilesFrom: _mapFrom.text.trim(),
      serverFilesTo: _mapTo.text.trim(),
    );
  }

  Future<void> _save() async {
    final apiId = _apiId.text.trim();
    final apiHash = _apiHash.text.trim();
    if (apiId.isNotEmpty || apiHash.isNotEmpty) {
      await widget.credentials.saveLocalServerCredentials(apiId, apiHash);
      _apiId.clear();
      _apiHash.clear();
      _hasServerCredentials = apiId.isNotEmpty && apiHash.isNotEmpty;
    }
    _draft = _collect();
    await widget.service.saveSettings(_draft);
  }

  Future<void> _run(String label, Future<String?> Function() action) async {
    setState(() {
      _working = true;
      _notice = null;
    });
    try {
      await _save();
      final message = await action();
      _notice = message ?? '$label: xong.';
      _noticeIsError = false;
    } on TelegramBotException catch (error) {
      _notice = '$label lỗi: ${error.message}';
      _noticeIsError = true;
    } on LocalBotServerException catch (error) {
      _notice = '$label lỗi: ${error.message}';
      _noticeIsError = true;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.swap_horiz),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Thôi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _pickExecutable() async {
    final file = await file_selector.openFile(
      acceptedTypeGroups: const [
        file_selector.XTypeGroup(
          label: 'telegram-bot-api',
          extensions: ['exe'],
        ),
      ],
    );
    if (file != null) setState(() => _executable.text = file.path);
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? helper,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: suffix,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        final service = widget.service;
        final local = service.usesLocalServer;
        final muted = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
        return AlertDialog(
          title: const Text('Bot Telegram kiểm tra AAB'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StatusChip(
                        label: service.running ? 'Đang chạy' : 'Đang tắt',
                        icon: service.running
                            ? Icons.play_circle_outline
                            : Icons.pause_circle_outline,
                        color: service.running
                            ? AppCyberTheme.success
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      if (service.botUsername != null)
                        StatusChip(label: '@${service.botUsername}'),
                      StatusChip(
                        label: local
                            ? 'Local server ${service.apiBaseUrl}'
                            : 'Telegram cloud (≤ 20 MB)',
                        icon: local ? Icons.dns_outlined : Icons.cloud_outlined,
                        color: local
                            ? AppCyberTheme.info
                            : AppCyberTheme.warning,
                      ),
                      if (service.current != null)
                        StatusChip(
                          label: 'Đang kiểm ${service.current!.fileName}',
                          icon: Icons.hourglass_top,
                        ),
                      if (service.queued > 0)
                        StatusChip(label: '${service.queued} đang chờ'),
                    ],
                  ),
                  if (service.lastError != null) ...[
                    const SizedBox(height: 10),
                    NoticeBox(
                      text: service.lastError!,
                      tone: NoticeTone.danger,
                    ),
                  ],
                  if (!local) ...[
                    const SizedBox(height: 10),
                    const NoticeBox(
                      tone: NoticeTone.warning,
                      text:
                          'Bot đang dùng Telegram cloud: chỉ tải được file ≤ 20 MB, '
                          'trong khi AAB thường 100–170 MB. Dựng local Bot API '
                          'server ở phần dưới rồi bấm "Chuyển bot sang server '
                          'local".',
                    ),
                  ],
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bật bot kiểm tra AAB'),
                    subtitle: const Text(
                      '/aab liệt kê file .aab trong nhóm để chọn; /check reply '
                      'vào tin có file để kiểm ngay.',
                    ),
                    value: _draft.enabled,
                    onChanged: _working
                        ? null
                        : (value) => setState(
                            () => _draft = _draft.copyWith(enabled: value),
                          ),
                  ),
                  const SizedBox(height: 4),
                  _field(
                    _sentence,
                    'Câu bot nói trước khi tải file',
                    helper: 'Gửi vào nhóm ngay khi có người chọn file.',
                  ),
                  _field(
                    _chats,
                    'Chat ID được phép',
                    helper:
                        'Cách nhau bằng dấu phẩy. Để trống: chỉ nhóm release '
                        'đã khai trong Options > Telegram.',
                  ),
                  _field(
                    _users,
                    'User ID được phép',
                    helper:
                        'Để trống: ai trong chat được phép cũng dùng được. Chat '
                        'riêng với bot chỉ mở cho user có trong danh sách này.',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Chạy thử trên máy ảo'),
                    subtitle: const Text(
                      'Cài, mở và theo dõi trên emulator, gửi ảnh màn hình vào '
                      'nhóm. Không bao giờ cài lên máy thật.',
                    ),
                    value: _draft.runOnEmulator,
                    onChanged: _working
                        ? null
                        : (value) => setState(
                            () =>
                                _draft = _draft.copyWith(runOnEmulator: value),
                          ),
                  ),
                  const Divider(height: 28),
                  const SectionLabel('Local Bot API server'),
                  const SizedBox(height: 10),
                  _field(
                    _executable,
                    'telegram-bot-api.exe',
                    helper:
                        'AMC tự khởi động server (--local, chỉ nghe 127.0.0.1) '
                        'khi cần. Để trống nếu server do nơi khác chạy.',
                    suffix: IconButton(
                      tooltip: 'Chọn file',
                      onPressed: _pickExecutable,
                      icon: const Icon(Icons.folder_open_outlined),
                    ),
                  ),
                  _field(_port, 'Cổng', helper: 'Mặc định 8081.'),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          _apiId,
                          _hasServerCredentials ? 'api_id (đã lưu)' : 'api_id',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          _apiHash,
                          _hasServerCredentials
                              ? 'api_hash (đã lưu)'
                              : 'api_hash',
                          obscure: true,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Lấy api_id / api_hash ở my.telegram.org → API development '
                    'tools. Lưu trong Windows secure storage, chỉ đưa cho '
                    'server qua biến môi trường.',
                    style: muted,
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Server chạy trong container'),
                    children: [
                      _field(
                        _mapFrom,
                        'Đường dẫn file phía server',
                        helper: 'Vd /var/lib/telegram-bot-api',
                      ),
                      _field(
                        _mapTo,
                        'Thư mục tương ứng trên máy này',
                        helper: r'Vd D:\telegram-bot-api-data',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _working
                            ? null
                            : () => _run('Kiểm tra kết nối', () async {
                                final name = await service.testConnection();
                                return 'Kết nối được @$name qua '
                                    '${local ? service.apiBaseUrl : 'Telegram cloud'}.';
                              }),
                        icon: const Icon(Icons.wifi_tethering, size: 18),
                        label: const Text('Kiểm tra kết nối'),
                      ),
                      if (!local)
                        FilledButton.tonalIcon(
                          onPressed: _working
                              ? null
                              : () async {
                                  final ok = await _confirm(
                                    'Chuyển bot sang server local?',
                                    'AMC sẽ khởi động server, gọi logOut để '
                                        'đưa bot ra khỏi Telegram cloud, rồi '
                                        'đăng nhập bot vào server local.\n\n'
                                        'Từ đó mọi thứ dùng bot này — kể cả '
                                        'thông báo release — phải đi qua server '
                                        'local; server tắt là bot im lặng. '
                                        'Telegram không cho bot quay lại cloud '
                                        'trong 10 phút sau khi chuyển.',
                                    'Chuyển',
                                  );
                                  if (!ok) return;
                                  await _run('Chuyển server', () async {
                                    final name = await service
                                        .moveToLocalServer();
                                    return 'Bot @$name đã chạy qua server '
                                        'local.';
                                  });
                                },
                          icon: const Icon(Icons.dns_outlined, size: 18),
                          label: const Text('Chuyển bot sang server local'),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _working
                              ? null
                              : () async {
                                  final ok = await _confirm(
                                    'Đưa bot về Telegram cloud?',
                                    'Bot rời server local và dùng lại cloud. '
                                        'Cloud chỉ tải được file ≤ 20 MB. Nếu '
                                        'bot vừa rời cloud chưa tới 10 phút, '
                                        'Telegram sẽ từ chối tới khi hết thời '
                                        'gian đó.',
                                    'Đưa về cloud',
                                  );
                                  if (!ok) return;
                                  await _run('Đưa về cloud', () async {
                                    await service.moveToCloud();
                                    return 'Bot đã dùng lại Telegram cloud.';
                                  });
                                },
                          icon: const Icon(Icons.cloud_outlined, size: 18),
                          label: const Text('Đưa bot về cloud'),
                        ),
                    ],
                  ),
                  if (_notice != null) ...[
                    const SizedBox(height: 10),
                    NoticeBox(
                      text: _notice!,
                      tone: _noticeIsError
                          ? NoticeTone.danger
                          : NoticeTone.info,
                    ),
                  ],
                  if (service.activity.isNotEmpty) ...[
                    const Divider(height: 28),
                    const SectionLabel('Hoạt động gần đây'),
                    const SizedBox(height: 6),
                    for (final line in service.activity.take(12))
                      Text(line, style: muted),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
            FilledButton(
              key: const Key('telegram-bot-save'),
              onPressed: _working
                  ? null
                  : () async {
                      setState(() => _working = true);
                      await _save();
                      if (context.mounted) Navigator.pop(context);
                    },
              child: const Text('Lưu'),
            ),
          ],
        );
      },
    );
  }
}
