import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/module_widgets.dart';
import '../controllers/network_test_controller.dart';
import '../controllers/qa_workspace_controller.dart';
import '../services/weak_network_proxy.dart';
import '../theme/qa_tokens.dart';
import '../widgets/qa_widgets.dart';

String networkPresetLabel(NetworkProfile profile) =>
    '${profile.name} · ${kilobytes(profile.bytesPerSecond)} KB/s';

/// Slows the suites' traffic through the local proxy, and probes an API
/// through it.
Future<void> showNetworkSheet(
  BuildContext context,
  QaWorkspaceController controller,
) {
  return showQaSideSheet<void>(
    context,
    key: const Key('qa-network-sheet'),
    title: 'Mạng yếu',
    subtitle: 'Giới hạn băng thông qua proxy cục bộ',
    width: 540,
    builder: (_) => ListenableBuilder(
      listenable: Listenable.merge([controller, controller.network]),
      builder: (context, _) => NetworkPanel(
        network: controller.network,
        suitesRunning: controller.isRunning,
      ),
    ),
  );
}

/// The sheet's content, on its own so it can be tested without a page.
class NetworkPanel extends StatefulWidget {
  const NetworkPanel({
    super.key,
    required this.network,
    required this.suitesRunning,
  });

  final NetworkTestController network;
  final bool suitesRunning;

  @override
  State<NetworkPanel> createState() => _NetworkPanelState();
}

class _NetworkPanelState extends State<NetworkPanel> {
  late final _url = TextEditingController(text: widget.network.apiUrl);

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, String done) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) showQaMessage(context, done);
    } on Object {
      if (mounted) {
        showQaMessage(context, 'Không copy được. Hãy chọn và copy trực tiếp.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final model = widget.network;
    final locked = model.busy || model.probing || widget.suitesRunning;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionLabel('Mức mạng'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in NetworkProfile.presets)
              QaChoiceChip(
                label: networkPresetLabel(preset),
                selected: model.profile == preset,
                onSelected: locked || model.enabled
                    ? null
                    : (_) => model.selectProfile(preset),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          model.profile.description,
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              key: const Key('qa-network-toggle'),
              onPressed: locked ? null : model.toggle,
              style: model.enabled
                  ? FilledButton.styleFrom(
                      backgroundColor: tokens.palette.warning,
                      foregroundColor: tokens.palette.base,
                    )
                  : null,
              icon: Icon(
                model.enabled
                    ? Icons.stop_circle_outlined
                    : Icons.network_check,
                size: 18,
              ),
              label: Text(
                model.busy
                    ? 'Đang xử lý…'
                    : model.enabled
                    ? 'Tắt giả lập'
                    : 'Bật giả lập',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                model.enabled
                    ? 'Đang bật · ${model.connections} kết nối đã đi qua proxy'
                    : widget.suitesRunning
                    ? 'Đang có lượt chạy: bật/tắt sau khi chạy xong.'
                    : 'Đang tắt',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: model.enabled ? tokens.palette.warning : tokens.muted,
                  fontWeight: model.enabled ? FontWeight.w700 : null,
                ),
              ),
            ),
          ],
        ),
        if (model.enabled && model.proxyUrl != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  'Proxy: ${model.proxyUrl}',
                  style: tokens.mono(size: 12),
                ),
              ),
              IconButton(
                tooltip: 'Copy địa chỉ proxy',
                onPressed: () =>
                    _copy(model.proxyUrl!, 'Đã copy địa chỉ proxy.'),
                icon: const Icon(Icons.copy, size: 16),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        const NoticeBox(
          text:
              'Suite nhận proxy qua FIZA_QA_PROXY, HTTP_PROXY và HTTPS_PROXY; '
              'client phải dùng proxy thì mới bị giới hạn. Giới hạn tính riêng '
              'từng kết nối, từng chiều, kể cả header và TLS. Không đổi mạng '
              'Windows. Nhớ tắt giả lập khi xong.',
        ),
        const SizedBox(height: 22),
        const SectionLabel('Thử API qua mạng giả lập'),
        const SizedBox(height: 10),
        TextField(
          key: const Key('qa-api-url'),
          controller: _url,
          enabled: !model.probing,
          onChanged: (value) => model.apiUrl = value,
          decoration: const InputDecoration(
            labelText: 'URL API (GET)',
            hintText: 'https://api.example.com/health',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<int>(
                initialValue: model.timeoutSeconds,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Timeout',
                  isDense: true,
                ),
                items: [
                  for (final seconds in const [10, 30, 60, 120])
                    DropdownMenuItem(
                      value: seconds,
                      child: Text('$seconds giây'),
                    ),
                ],
                onChanged: model.probing
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => model.timeoutSeconds = value);
                        }
                      },
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              key: const Key('qa-api-test'),
              onPressed: model.enabled && !model.probing && !model.busy
                  ? model.testApi
                  : null,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Kiểm tra API'),
            ),
            if (model.probing) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: model.cancelProbe,
                child: const Text('Dừng'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          model.enabled
              ? 'GET không kèm token hay header riêng, không theo redirect. '
                    'API cần xác thực, POST hoặc kiểm tra nghiệp vụ thì dùng suite.'
              : 'Bật giả lập trước để thử API.',
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
        ),
        if (model.probing)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        if (model.error != null) ...[
          const SizedBox(height: 10),
          NoticeBox(text: model.error!, tone: NoticeTone.danger),
        ],
        if (model.result != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.well,
              borderRadius: BorderRadius.circular(QaTokens.radius),
              border: Border.all(color: tokens.line),
            ),
            child: SelectableText(
              model.result!,
              style: tokens.mono(size: 11.5),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _copy(model.result!, 'Đã copy báo cáo API.'),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy báo cáo API'),
            ),
          ),
        ],
        const SizedBox(height: 14),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Cách nối suite vào proxy'),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dart (HttpClient dùng gọi API):',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            _Snippet(
              "final proxy = Platform.environment['FIZA_QA_PROXY'];\n"
              'if (proxy != null) {\n'
              '  final address = Uri.parse(proxy);\n'
              "  client.findProxy = (_) => 'PROXY \${address.host}:\${address.port}';\n"
              '}',
            ),
            const SizedBox(height: 10),
            Text(
              'Playwright (trong use của cấu hình):',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            const _Snippet(
              'proxy: process.env.FIZA_QA_PROXY\n'
              '  ? { server: process.env.FIZA_QA_PROXY }\n'
              '  : undefined,',
            ),
            const SizedBox(height: 10),
            Text(
              'App Android không nhận biến môi trường của runner: nối '
              '`adb reverse tcp:<port> tcp:<port>` theo cổng proxy ở trên, cho '
              'bản test dùng 127.0.0.1:<port>, và gỡ đường nối khi xong.',
              style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
            ),
          ],
        ),
      ],
    );
  }
}

class _Snippet extends StatelessWidget {
  const _Snippet(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    final tokens = QaTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.consoleBackground,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectableText(
        code,
        style: tokens.mono(size: 11, color: tokens.consoleText),
      ),
    );
  }
}
