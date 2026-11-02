import 'dart:async';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../infrastructure/remote_network.dart';
import '../services/swift_desk_public.dart';
import '../services/swift_desk_runtime.dart';

class SwiftDeskPairing extends StatefulWidget {
  const SwiftDeskPairing({
    super.key,
    required this.runtime,
    required this.service,
  });
  final SwiftDeskRuntime runtime;
  final SwiftDeskPublic service;
  @override
  State<SwiftDeskPairing> createState() => _SwiftDeskPairingState();
}

class _SwiftDeskPairingState extends State<SwiftDeskPairing> {
  final _target = TextEditingController(), _password = TextEditingController();
  bool _remember = true, _showPassword = false;
  String? _error;
  SwiftDeskPublic get service => widget.service;
  SwiftDeskRuntime get runtime => widget.runtime;
  bool get blocked =>
      service.busy ||
      service.hasSession ||
      runtime.busy ||
      runtime.active ||
      runtime.draining;
  @override
  void dispose() {
    _target.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đã sao chép mã kết nối. Gửi riêng cho người bạn muốn ghép.',
          ),
        ),
      );
    }
  }

  Future<void> _mode(RemoteConnectionMode mode) async {
    try {
      await runtime.setConnectionMode(mode);
      _error = null;
    } catch (_) {
      _error = 'Không lưu được lựa chọn kết nối.';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Ghép bằng mã máy · Không cần tài khoản AMC hay máy chủ riêng',
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [_host(), _viewer()];
            if (constraints.maxWidth >= 900 &&
                MediaQuery.textScalerOf(context).scale(1) < 1.3) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[1]),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: cards,
            );
          },
        ),
        if (service.error != null || _error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              service.error ?? _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
  Widget _host() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mã máy này', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          SelectableText(
            service.formattedId,
            key: const Key('swift-desk-my-id'),
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(service.status),
          const SizedBox(height: 12),
          if (service.online) ...[
            const Text('Mật khẩu ghép tạm thời'),
            SelectableText(
              service.password,
              key: const Key('swift-desk-my-password'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Dùng một lần, tối đa 5 phút. Mỗi phiên vẫn cần bạn chấp nhận.',
            ),
            const SizedBox(height: 8),
          ] else
            const Text(
              'Bật nhận kết nối rồi gửi mã cho máy đối tác. Chỉ máy chia sẻ màn hình cần cấp quyền ghi màn hình.',
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('swift-desk-public-host'),
                onPressed:
                    service.busy ||
                        runtime.active ||
                        runtime.busy ||
                        runtime.draining
                    ? null
                    : () => unawaited(
                        service.wanted ? service.stop() : service.start(),
                      ),
                icon: Icon(
                  service.wanted
                      ? Icons.stop_circle_outlined
                      : Icons.wifi_tethering,
                ),
                label: Text(
                  service.wanted
                      ? 'Tắt nhận kết nối bằng mã'
                      : 'Cho phép kết nối bằng mã',
                ),
              ),
              OutlinedButton.icon(
                key: const Key('swift-desk-copy-code'),
                onPressed: service.online && !blocked
                    ? () => unawaited(_copy(service.code.encode()))
                    : null,
                icon: const Icon(Icons.copy),
                label: const Text('Sao chép mã kết nối'),
              ),
              if (service.online)
                IconButton(
                  tooltip: 'Đổi mật khẩu ghép',
                  onPressed: blocked ? null : service.renewPassword,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          if (runtime.permissions?.screen != true)
            TextButton(
              onPressed: runtime.busy
                  ? null
                  : () => unawaited(runtime.refreshPermissions(request: true)),
              child: const Text('Cấp quyền chia sẻ màn hình'),
            ),
        ],
      ),
    ),
  );
  Widget _viewer() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Kết nối máy đối tác',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('swift-desk-partner-id'),
            controller: _target,
            maxLength: 128,
            decoration: const InputDecoration(
              labelText: 'Mã máy đối tác hoặc mã kết nối',
              hintText: '123 456 789 hoặc dán mã đã sao chép',
              counterText: '',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('swift-desk-partner-password'),
            controller: _password,
            obscureText: !_showPassword,
            maxLength: 16,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Mật khẩu ghép',
              helperText:
                  'Bỏ trống khi dán toàn bộ mã hoặc kết nối máy đã nhớ.',
              counterText: '',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Đường kết nối',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<RemoteConnectionMode>(
                key: const Key('swift-desk-public-mode'),
                value: runtime.settings.connectionMode,
                isExpanded: true,
                items: RemoteConnectionMode.values
                    .map(
                      (mode) => DropdownMenuItem(
                        value: mode,
                        enabled: mode != RemoteConnectionMode.relay,
                        child: Text(
                          mode == RemoteConnectionMode.automatic
                              ? 'Tự động · P2P IPv6/IPv4'
                              : mode == RemoteConnectionMode.relay
                              ? 'TURN · Cấu hình trong nâng cao'
                              : mode.label,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: blocked
                    ? null
                    : (mode) {
                        if (mode != null) unawaited(_mode(mode));
                      },
              ),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Nhớ máy đối tác'),
            value: _remember,
            onChanged: blocked
                ? null
                : (v) => setState(() => _remember = v ?? true),
          ),
          FilledButton.icon(
            key: const Key('swift-desk-public-connect'),
            onPressed: blocked
                ? null
                : () async {
                    await service.connect(
                      _target.text,
                      password: _password.text.trim(),
                      remember: _remember,
                    );
                    if (mounted) {
                      _password.clear();
                      if (_target.text.startsWith('amc-id:')) _target.clear();
                    }
                  },
            icon: const Icon(Icons.link),
            label: Text(service.busy ? 'Đang kết nối…' : 'Kết nối bằng mã'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Máy đối tác cần mở AMC và bật nhận kết nối bằng mã. Hình ảnh và điều khiển đi qua P2P IPv6/IPv4.',
          ),
          for (final peer in service.saved)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(peer.name),
              subtitle: Text(
                'Mã ${formatPublicRemoteId(peer.codeId)} · Cần máy đích chấp nhận',
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Kết nối máy đã nhớ',
                    onPressed: blocked
                        ? null
                        : () => unawaited(service.connect(peer.codeId)),
                    icon: const Icon(Icons.link),
                  ),
                  IconButton(
                    tooltip: 'Quên máy đối tác',
                    onPressed: blocked
                        ? null
                        : () => unawaited(service.forget(peer)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
