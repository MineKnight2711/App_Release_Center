import 'dart:async';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/swift_desk_runtime.dart';
import '../infrastructure/webrtc_desktop_engine.dart';
import '../infrastructure/lan_host.dart';
import '../infrastructure/remote_network.dart';
import '../widgets/remote_surface.dart';
import '../widgets/saved_remote_devices.dart';
import '../widgets/swift_desk_extras.dart';
import 'swift_desk_probe_view.dart';

Future<void> showSwiftDesk(BuildContext context) async {
  try {
    final runtime = await SwiftDeskRuntime.open();
    if (context.mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => SwiftDeskView(runtime: runtime)),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Không mở được SwiftDesk. Kiểm tra kho credential và dữ liệu thiết bị.',
          ),
        ),
      );
    }
  }
}

class SwiftDeskLanApp extends StatelessWidget {
  const SwiftDeskLanApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AMC · SwiftDesk LAN',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff167d89),
      useMaterial3: true,
    ),
    home: FutureBuilder<SwiftDeskRuntime>(
      future: SwiftDeskRuntime.open(),
      builder: (context, result) {
        if (result.hasData) return SwiftDeskView(runtime: result.data!);
        return Scaffold(
          body: Center(
            child: result.hasError
                ? const Text(
                    'Không mở được kho dữ liệu SwiftDesk. Kiểm tra credential/chứng chỉ.',
                  )
                : const CircularProgressIndicator(),
          ),
        );
      },
    ),
  );
}

class SwiftDeskView extends StatefulWidget {
  const SwiftDeskView({super.key, required this.runtime});
  final SwiftDeskRuntime runtime;
  @override
  State<SwiftDeskView> createState() => _SwiftDeskViewState();
}

class _SwiftDeskViewState extends State<SwiftDeskView> {
  SwiftDeskRuntime get runtime => widget.runtime;
  final _invitation = TextEditingController(),
      _text = TextEditingController(),
      _port = TextEditingController(text: '9877');
  bool _remember = true,
      _input = false,
      _clipboard = false,
      _nativeScale = false,
      _full = false,
      _mapCtrl = true,
      _leaving = false;
  String? _requestId;
  @override
  void dispose() {
    unawaited(runtime.releaseViewerInput());
    _invitation.dispose();
    _text.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (runtime.viewing) await runtime.disconnect();
    if (!mounted) return;
    setState(() => _leaving = true);
    Navigator.of(context).pop();
  }

  Future<void> _showInvite() async {
    if (runtime.addresses.isEmpty) return;
    var address = runtime.addresses.first;
    var invitation = runtime.invitation(address);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Ghép máy qua LAN'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Gửi mã này cho máy bạn muốn kết nối. Mã dùng một lần, hết hạn sau 5 phút. Máy này vẫn hỏi chấp nhận từng phiên.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: address,
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ IP của máy này',
                    ),
                    items: runtime.addresses
                        .map(
                          (a) => DropdownMenuItem(
                            value: a,
                            child: Text('$a:${runtime.listenPort}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        update(() {
                          address = value;
                          invitation = runtime.invitation(address);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  QrImageView(
                    data: invitation.encode(),
                    size: 230,
                    backgroundColor: Colors.white,
                  ),
                  SelectableText(
                    '${invitation.endpoint.address}:${invitation.endpoint.port}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: invitation.encode()),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Đã sao chép mã ghép nối'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Sao chép mã ghép nối'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: runtime,
    builder: (context, _) {
      final request = runtime.pendingRequest;
      if (_requestId != request?.sessionId) {
        _requestId = request?.sessionId;
        _input = _clipboard = false;
      }
      return PopScope(
        canPop: _leaving || !runtime.viewing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_leave());
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('SwiftDesk · Điều khiển máy tính'),
            actions: [
              if (runtime.active)
                TextButton.icon(
                  onPressed: () => unawaited(runtime.disconnect()),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Ngắt phiên'),
                ),
              IconButton(
                tooltip: 'Bản thử engine Phase 0',
                onPressed: runtime.active
                    ? null
                    : () => showSwiftDeskProbe(context),
                icon: const Icon(Icons.science_outlined),
              ),
            ],
          ),
          body: _full && runtime.viewing
              ? _viewer()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1220),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            runtime.status,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (runtime.busy)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: LinearProgressIndicator(),
                            ),
                          if (runtime.error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                runtime.error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          const SizedBox(height: 14),
                          if (request != null) _request(request),
                          if (runtime.viewing)
                            SizedBox(height: 700, child: _viewer()),
                          if (runtime.hosting && runtime.pendingRequest == null)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${runtime.session!.peerName} đang truy cập máy này',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(
                                      'Quyền: ${runtime.session!.scopes.map(_scopeName).join(" · ")}',
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        if (runtime.allows(RemoteScope.input))
                                          OutlinedButton(
                                            onPressed: () => runtime
                                                .revokeScope(RemoteScope.input),
                                            child: const Text(
                                              'Dừng quyền chuột/phím',
                                            ),
                                          ),
                                        if (runtime.allows(
                                          RemoteScope.clipboard,
                                        ))
                                          OutlinedButton(
                                            onPressed: () =>
                                                runtime.revokeScope(
                                                  RemoteScope.clipboard,
                                                ),
                                            child: const Text('Tắt clipboard'),
                                          ),
                                        FilledButton.tonal(
                                          onPressed: () => runtime.disconnect(),
                                          child: const Text('Ngắt ngay'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          _hostCard(),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Kết nối máy khác',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Dán mã ghép nối do máy đích tạo. Hai máy phải cùng LAN; máy đích cần mở AMC và bật nhận kết nối.',
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    key: const Key('swift-desk-invitation'),
                                    controller: _invitation,
                                    maxLines: 2,
                                    maxLength: 4096,
                                    decoration: const InputDecoration(
                                      labelText: 'Mã ghép nối AMC LAN',
                                      border: OutlineInputBorder(),
                                      counterText: '',
                                    ),
                                  ),
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      'Lưu thiết bị trên máy này',
                                    ),
                                    value: _remember,
                                    onChanged: runtime.active
                                        ? null
                                        : (value) => setState(
                                            () => _remember = value ?? false,
                                          ),
                                  ),
                                  FilledButton.icon(
                                    key: const Key('swift-desk-connect'),
                                    onPressed: runtime.active || runtime.busy
                                        ? null
                                        : () {
                                            unawaited(
                                              runtime.connectInvitation(
                                                _invitation.text,
                                                remember: _remember,
                                              ),
                                            );
                                            _invitation.clear();
                                          },
                                    icon: const Icon(Icons.link),
                                    label: const Text('Gửi yêu cầu kết nối'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SavedRemoteDevices(runtime: runtime),
                          if (runtime.controllers.isNotEmpty)
                            ExpansionTile(
                              title: const Text(
                                'Thiết bị đã được máy này ghép',
                              ),
                              children: [
                                for (final controller in runtime.controllers)
                                  ListTile(
                                    title: Text(controller.name),
                                    subtitle: Text(
                                      controller.scopes
                                          .map(_scopeName)
                                          .join(' · '),
                                    ),
                                    trailing: TextButton(
                                      onPressed: () => runtime.revokeController(
                                        controller.id,
                                      ),
                                      child: const Text('Thu hồi quyền'),
                                    ),
                                  ),
                              ],
                            ),
                          if (runtime.history.isNotEmpty)
                            ExpansionTile(
                              title: const Text('Lịch sử phiên trên máy này'),
                              children: [
                                for (final record in runtime.history.take(10))
                                  ListTile(
                                    leading: Icon(
                                      record.failed
                                          ? Icons.error_outline
                                          : Icons.check_circle_outline,
                                    ),
                                    title: Text(record.peerName),
                                    subtitle: Text(
                                      '${record.role == RemoteRole.host ? "Chia sẻ máy này" : "Xem máy khác"} · ${record.endedAt.toLocal().toString().substring(0, 16)} · ${record.frames} frame',
                                    ),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 20),
                          SwiftDeskExtras(runtime: runtime),
                          const Text(
                            'LAN dùng TLS và ghim chứng chỉ. Internet dùng tài khoản AMC và signaling mã hóa tới máy đích. Mỗi phiên cần chấp nhận; chưa hỗ trợ unattended, UAC hay màn hình đăng nhập. Thoát AMC sẽ ngắt mọi phiên.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      );
    },
  );

  Widget _hostCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Máy tính này · ${runtime.name}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Ghi màn hình: ${runtime.permissions?.screen == true ? "đã có quyền" : "chưa có quyền"} · Chuột/phím: ${runtime.permissions?.input == true ? "đã có quyền" : "chưa có quyền"}',
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: runtime.busy
                    ? null
                    : () => runtime.refreshPermissions(request: true),
                child: const Text('Cấp quyền trên máy này'),
              ),
              TextButton(
                onPressed: runtime.busy
                    ? null
                    : () => runtime.refreshPermissions(),
                child: const Text('Kiểm tra lại quyền'),
              ),
            ],
          ),
          if (runtime.displays.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey(runtime.displayId),
              initialValue: runtime.displayId,
              decoration: const InputDecoration(labelText: 'Màn hình chia sẻ'),
              items: runtime.displays
                  .map(
                    (d) => DropdownMenuItem(
                      value: d.id,
                      child: Text(
                        '${d.name}${d.width > 0 ? " · ${d.width}×${d.height}" : ""}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: runtime.busy
                  ? null
                  : (id) {
                      if (id != null) unawaited(runtime.chooseHostDisplay(id));
                    },
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('swift-desk-host'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Nhận kết nối trên LAN'),
            subtitle: Text(
              runtime.hostEnabled
                  ? 'Cổng ${runtime.listenPort} · Mỗi phiên đều cần chấp nhận'
                  : 'Mặc định tắt. Chỉ bật khi muốn chia sẻ máy.',
            ),
            value: runtime.hostEnabled,
            onChanged: runtime.busy || runtime.permissions?.screen != true
                ? null
                : (enabled) {
                    if (enabled) {
                      unawaited(
                        runtime.enableHost(
                          port: int.tryParse(_port.text) ?? 9877,
                        ),
                      );
                    } else {
                      unawaited(runtime.disableHost());
                    }
                  },
          ),
          if (!runtime.hostEnabled)
            SizedBox(
              width: 160,
              child: TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                decoration: const InputDecoration(labelText: 'Cổng LAN (9877)'),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed:
                runtime.hostEnabled &&
                    !runtime.active &&
                    runtime.addresses.isNotEmpty
                ? _showInvite
                : null,
            icon: const Icon(Icons.qr_code),
            label: const Text('Tạo mã ghép nối'),
          ),
          if (runtime.addresses.isEmpty)
            const Text('Chưa tìm thấy IPv4 LAN. Kiểm tra Wi-Fi hoặc Ethernet.'),
        ],
      ),
    ),
  );

  Widget _request(RemotePairRequest request) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${request.name} muốn truy cập máy này',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            '${request.address} · ${request.knownDevice ? "Thiết bị đã ghép" : "Ghép lần đầu"}${request.remember ? " · Có yêu cầu lưu thiết bị" : ""}',
          ),
          if (request.internet)
            Text('Đường viewer yêu cầu: ${request.connectionMode.label}'),
          const Text(
            'Chỉ chọn những quyền bạn muốn cấp cho phiên này. Yêu cầu tự hết hạn sau 60 giây.',
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _input,
            title: const Text('Cho phép chuột/phím'),
            subtitle: runtime.permissions?.input == true
                ? null
                : const Text('Cần cấp Accessibility trên macOS trước.'),
            onChanged:
                runtime.permissions?.input == true &&
                    request.availableScopes.contains(RemoteScope.input)
                ? (value) => setState(() => _input = value ?? false)
                : null,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _clipboard,
            title: const Text('Cho phép clipboard văn bản'),
            onChanged: request.availableScopes.contains(RemoteScope.clipboard)
                ? (value) => setState(() => _clipboard = value ?? false)
                : null,
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: const Key('swift-desk-accept'),
                onPressed: () =>
                    runtime.accept(input: _input, clipboard: _clipboard),
                child: const Text('Chấp nhận'),
              ),
              OutlinedButton(
                onPressed: runtime.reject,
                child: const Text('Từ chối'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _viewer() {
    final engine = runtime.engine;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  runtime.session?.peerName ?? '',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (runtime.remoteDisplays.isNotEmpty)
                  DropdownButton<String>(
                    value: runtime.remoteDisplayId,
                    items: runtime.remoteDisplays
                        .map(
                          (d) => DropdownMenuItem(
                            value: d.id,
                            child: Text(d.name),
                          ),
                        )
                        .toList(),
                    onChanged: runtime.allows(RemoteScope.view)
                        ? (id) {
                            if (id != null) {
                              unawaited(
                                runtime.changeDisplay(id, runtime.quality),
                              );
                            }
                          }
                        : null,
                  ),
                DropdownButton<RemoteQuality>(
                  value: runtime.quality,
                  items: RemoteQuality.values
                      .map(
                        (q) => DropdownMenuItem(
                          value: q,
                          child: Text(switch (q) {
                            RemoteQuality.low => 'Tiết kiệm',
                            RemoteQuality.balanced => 'Cân bằng',
                            RemoteQuality.high => 'Rõ nét',
                          }),
                        ),
                      )
                      .toList(),
                  onChanged:
                      runtime.allows(RemoteScope.view) &&
                          runtime.remoteDisplayId != null
                      ? (q) {
                          if (q != null) {
                            unawaited(
                              runtime.changeDisplay(
                                runtime.remoteDisplayId!,
                                q,
                              ),
                            );
                          }
                        }
                      : null,
                ),
                FilterChip(
                  label: const Text('1:1'),
                  selected: _nativeScale,
                  onSelected: (v) => setState(() => _nativeScale = v),
                ),
                IconButton(
                  tooltip: _full ? 'Thu nhỏ màn hình' : 'Mở rộng màn hình',
                  onPressed: () => setState(() => _full = !_full),
                  icon: Icon(_full ? Icons.fullscreen_exit : Icons.fullscreen),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: engine is WebRtcDesktopEngine
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        RemoteSurface(
                          runtime: runtime,
                          renderer: engine.renderer,
                          nativeScale: _nativeScale,
                          mapCtrlToCmd: _mapCtrl,
                        ),
                        if (!runtime.firstFrame)
                          const ColoredBox(
                            color: Color(0xff10191d),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text('Đang chờ hình thật từ máy đích…'),
                                ],
                              ),
                            ),
                          ),
                      ],
                    )
                  : const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Đang chờ hình thật từ máy đích…'),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              '${runtime.frames} frame · ${runtime.fps.toStringAsFixed(1)} FPS · ${runtime.kbps.toStringAsFixed(0)} kb/s · ${remoteNetworkPathLabel(runtime.networkPath)}',
            ),
            if (runtime.remotePlatform == 'macos')
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Ctrl trái trên Windows tương ứng ⌘; Ctrl phải giữ nguyên',
                ),
                value: _mapCtrl,
                onChanged: (v) => setState(() => _mapCtrl = v ?? true),
              ),
            if (runtime.clipboardEnabled)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Gửi clipboard mới nhất trước khi dán (Ctrl/⌘+V)',
                ),
                value: runtime.settings.flag('clipboardBeforePaste'),
                onChanged: (v) async {
                  await runtime.settings.setFlag(
                    'clipboardBeforePaste',
                    v == true,
                  );
                  if (mounted) setState(() {});
                },
              ),
            if (runtime.allows(RemoteScope.input))
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      maxLength: 1024,
                      decoration: const InputDecoration(
                        labelText: 'Nhập tiếng Việt / văn bản gửi tới máy đích',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Gửi văn bản',
                    onPressed: _sendText,
                    icon: const Icon(Icons.send_outlined),
                  ),
                ],
              ),
            if (runtime.allows(RemoteScope.clipboard))
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: const Text('Clipboard văn bản (tối đa 16 KB)'),
                    selected: runtime.clipboardEnabled,
                    onSelected: (value) =>
                        setState(() => runtime.clipboardEnabled = value),
                  ),
                  TextButton(
                    onPressed: runtime.clipboardEnabled
                        ? () => runtime.clipboard(pull: false)
                        : null,
                    child: const Text('Gửi clipboard'),
                  ),
                  TextButton(
                    onPressed: runtime.clipboardEnabled
                        ? () => runtime.clipboard(pull: true)
                        : null,
                    child: const Text('Lấy clipboard'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _sendText() {
    unawaited(runtime.sendText(_text.text));
    _text.clear();
  }

  String _scopeName(RemoteScope scope) => switch (scope) {
    RemoteScope.view => 'Xem',
    RemoteScope.input => 'Chuột/phím',
    RemoteScope.clipboard => 'Clipboard',
  };
}
