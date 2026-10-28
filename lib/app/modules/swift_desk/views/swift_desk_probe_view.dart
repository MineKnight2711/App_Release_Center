import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:amc_remote_platform/amc_remote_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/swift_desk_probe.dart';

Future<void> showSwiftDeskProbe(BuildContext context) => Navigator.of(
  context,
).push<void>(MaterialPageRoute(builder: (_) => const SwiftDeskProbeView()));

/// Separate entry point keeps experimentation away from the live AMC command
/// relay, release jobs, Telegram intake and reminder runtime.
class SwiftDeskProbeApp extends StatelessWidget {
  const SwiftDeskProbeApp({super.key, this.smokeReportPath});
  final String? smokeReportPath;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AMC · SwiftDesk',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff157a79),
      useMaterial3: true,
    ),
    home: SwiftDeskProbeView(smokeReportPath: smokeReportPath),
  );
}

class SwiftDeskProbeView extends StatefulWidget {
  const SwiftDeskProbeView({super.key, this.probe, this.smokeReportPath});
  final SwiftDeskProbe? probe;
  final String? smokeReportPath;

  @override
  State<SwiftDeskProbeView> createState() => _SwiftDeskProbeViewState();
}

class _SwiftDeskProbeViewState extends State<SwiftDeskProbeView> {
  late final probe = widget.probe ?? SwiftDeskProbe();
  final _signal = TextEditingController();
  final _turnUrl = TextEditingController();
  final _turnUser = TextEditingController();
  final _turnPassword = TextEditingController();
  final _testOutput = TextEditingController();
  final _testFocus = FocusNode();
  bool _relayOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_initialize()),
    );
  }

  Future<void> _initialize() async {
    await probe.initialize();
    if (widget.smokeReportPath == null) return;
    var outcome = 'blocked';
    final cycles = <Map<String, Object?>>[];
    var inputWithoutGrantRejected = false;
    try {
      try {
        await const AmcRemotePlatform().sendInput('ungranted-probe', {
          'type': 'unsupported-probe',
        });
      } on PlatformException catch (e) {
        inputWithoutGrantRejected = e.code == 'session';
      }
      if (probe.permissions?.screen == true &&
          probe.sourceId != null &&
          probe.error == null) {
        outcome = 'passed';
        for (var cycle = 0; cycle < 3; cycle++) {
          await probe.startLoopback();
          final frame = probe.error == null && await probe.waitForFrame();
          await Future<void>.delayed(const Duration(seconds: 3));
          await probe.sampleStats();
          final passed =
              frame && probe.framesDecoded > 0 && probe.dataRoundTripMs != null;
          final result = {...probe.report(), 'passed': passed};
          await probe.stop();
          result['sessionReleased'] = !probe.hasSession && !probe.inputEnabled;
          cycles.add(result);
          if (!passed || result['sessionReleased'] != true) {
            outcome = 'failed';
            break;
          }
        }
      }
      if (!inputWithoutGrantRejected) outcome = 'failed';
      final report = {
        ...probe.report(),
        'outcome': outcome,
        'cycles': cycles,
        'inputWithoutGrantRejected': inputWithoutGrantRejected,
        'note':
            'Local loopback only; no OS input was injected. Two-machine and TURN tests remain.',
      };
      await File(
        widget.smokeReportPath!,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    } finally {
      await probe.close();
    }
    exit(outcome == 'failed' ? 1 : 0);
  }

  @override
  void dispose() {
    unawaited(probe.close());
    for (final controller in [
      _signal,
      _turnUrl,
      _turnUser,
      _turnPassword,
      _testOutput,
    ]) {
      controller.dispose();
    }
    _testFocus.dispose();
    super.dispose();
  }

  void _start({required bool host}) {
    final action = host ? probe.createHostOffer : probe.startLoopback;
    unawaited(
      action(
        relayOnly: _relayOnly,
        turnUrl: _turnUrl.text.trim(),
        turnUser: _turnUser.text.trim(),
        turnPassword: _turnPassword.text,
      ),
    );
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã sao chép')));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: probe,
    builder: (context, _) {
      final canStart = probe.initialized && !probe.busy;
      final canCapture =
          canStart && probe.sourceId != null && !probe.hasSession;
      return Scaffold(
        appBar: AppBar(
          title: const Text('SwiftDesk · Thử kết nối'),
          actions: [
            TextButton.icon(
              onPressed: probe.hasSession || probe.busy
                  ? () => unawaited(probe.stop())
                  : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Dừng phiên'),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Bản thử engine trong AMC',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Thử truyền màn hình ngay trên máy này, hoặc nối hai máy bằng mã phiên. '
                    'Phiên chỉ tồn tại khi trang này mở. Chưa có kết nối bằng ID hay chạy nền.',
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 20,
                            runSpacing: 8,
                            children: [
                              _permission(
                                'Ghi màn hình',
                                probe.permissions?.screen,
                              ),
                              _permission(
                                'Chuột/phím',
                                probe.permissions?.input,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: canStart
                                    ? () => unawaited(
                                        probe.refreshPermissions(request: true),
                                      )
                                    : null,
                                child: const Text('Cấp quyền trên máy này'),
                              ),
                              TextButton(
                                onPressed: canStart
                                    ? () =>
                                          unawaited(probe.refreshPermissions())
                                    : null,
                                child: const Text('Kiểm tra lại quyền'),
                              ),
                            ],
                          ),
                          const Text(
                            'macOS: bật Screen Recording và Accessibility cho AMC trong Cài đặt hệ thống. '
                            'Sau khi cấp quyền có thể cần mở lại ứng dụng. Viewer không cần quyền ghi màn hình.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'source-${probe.sourceId}-${probe.sources.length}',
                    ),
                    initialValue: probe.sourceId,
                    decoration: const InputDecoration(
                      labelText: 'Màn hình chia sẻ',
                      border: OutlineInputBorder(),
                    ),
                    items: probe.sources
                        .map(
                          (source) => DropdownMenuItem(
                            value: source.id,
                            child: Text(source.name),
                          ),
                        )
                        .toList(),
                    onChanged: canStart && !probe.hasSession
                        ? (id) => setState(() => probe.sourceId = id)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const Key('swift-desk-loopback'),
                        onPressed: canCapture
                            ? () => _start(host: false)
                            : null,
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('Thử trên máy này'),
                      ),
                      OutlinedButton.icon(
                        onPressed: canCapture ? () => _start(host: true) : null,
                        icon: const Icon(Icons.screen_share_outlined),
                        label: const Text('Tạo phiên chia sẻ cho máy khác'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (probe.busy) const LinearProgressIndicator(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(probe.status),
                  ),
                  if (probe.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        probe.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(
                      color: const Color(0xff142323),
                      child:
                          probe.initialized &&
                              probe.firstFrame &&
                              probe.hasSession
                          ? RTCVideoView(
                              probe.renderer,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitContain,
                            )
                          : const Center(
                              child: Text(
                                'Hình nhận qua WebRTC sẽ xuất hiện tại đây',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    children: [
                      Text('Frame giải mã: ${probe.framesDecoded}'),
                      Text(
                        'FPS nhận: ${probe.framesPerSecond.toStringAsFixed(1)}',
                      ),
                      Text(
                        'Dữ liệu: ${(probe.receivedBytes / 1024).toStringAsFixed(0)} KB',
                      ),
                      Text(
                        'Kênh dữ liệu: ${probe.dataRoundTripMs == null ? "đang chờ" : "${probe.dataRoundTripMs} ms"}',
                      ),
                      if (probe.candidateType.isNotEmpty)
                        Text('ICE: ${probe.candidateType}'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ExpansionTile(
                    title: const Text('Kết nối hai máy bằng mã phiên'),
                    childrenPadding: const EdgeInsets.all(12),
                    children: [
                      const Text(
                        'Host tạo phiên và sao chép mã mời sang viewer. Viewer dán mã, chọn Nhận mã mời, '
                        'rồi gửi mã trả lời về host. Host dán mã trả lời và chọn Hoàn tất. '
                        'Chỉ chuyển mã cho máy bạn tin cậy; mã có thông tin kết nối và hết hạn sau 10 phút. '
                        'Mặc định thử LAN; khác mạng cần cấu hình TURN ở cả hai máy.',
                      ),
                      if (probe.localSignal != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: FilledButton.tonalIcon(
                            onPressed: () => _copy(probe.localSignal!),
                            icon: const Icon(Icons.copy),
                            label: Text(
                              probe.mode == ProbeMode.host
                                  ? 'Sao chép mã mời'
                                  : 'Sao chép mã trả lời',
                            ),
                          ),
                        ),
                      TextField(
                        controller: _signal,
                        maxLines: 3,
                        maxLength: 300000,
                        decoration: const InputDecoration(
                          labelText: 'Dán mã từ máy kia',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: canStart && !probe.hasSession
                                ? () {
                                    unawaited(
                                      probe.joinOffer(
                                        _signal.text,
                                        relayOnly: _relayOnly,
                                        turnUrl: _turnUrl.text.trim(),
                                        turnUser: _turnUser.text.trim(),
                                        turnPassword: _turnPassword.text,
                                      ),
                                    );
                                    _signal.clear();
                                  }
                                : null,
                            child: const Text('Nhận mã mời (viewer)'),
                          ),
                          OutlinedButton(
                            onPressed:
                                canStart &&
                                    probe.mode == ProbeMode.host &&
                                    probe.localSignal != null
                                ? () {
                                    unawaited(probe.applyAnswer(_signal.text));
                                    _signal.clear();
                                  }
                                : null,
                            child: const Text('Hoàn tất trên host'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('Thử chuột và nhập tiếng Việt'),
                    childrenPadding: const EdgeInsets.all(12),
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Cho phép phiên này gửi input vào máy này',
                        ),
                        subtitle: const Text(
                          'Chỉ host bật khi đã kết nối. Tắt hoặc dừng phiên sẽ thu hồi ngay.',
                        ),
                        value: probe.inputEnabled,
                        onChanged: canStart && probe.canReceiveInput
                            ? (value) => unawaited(probe.setInputEnabled(value))
                            : null,
                      ),
                      TextField(
                        controller: _testOutput,
                        focusNode: _testFocus,
                        decoration: const InputDecoration(
                          labelText:
                              'Đặt con trỏ ở đây trên host để nhận chữ thử',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: probe.dataReady && !probe.busy
                                ? () async {
                                    _testFocus.requestFocus();
                                    await Future<void>.delayed(
                                      const Duration(milliseconds: 250),
                                    );
                                    if (!mounted) return;
                                    await probe.sendTestInput(
                                      RemoteText(
                                        'AMC SwiftDesk · Tiếng Việt ✓',
                                      ),
                                    );
                                  }
                                : null,
                            child: const Text('Gửi chữ thử tới host'),
                          ),
                          OutlinedButton(
                            onPressed: probe.dataReady && !probe.busy
                                ? () => unawaited(
                                    probe.sendTestInput(
                                      RemotePointer(0.5, 0.5),
                                    ),
                                  )
                                : null,
                            child: const Text(
                              'Đưa chuột tới giữa màn hình host',
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Sự kiện native đã áp dụng trên máy này: ${probe.appliedInputs}',
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('TURN · thử kết nối relay'),
                    childrenPadding: const EdgeInsets.all(12),
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Bắt buộc đi qua TURN'),
                        subtitle: const Text(
                          'Nhập credential thử nghiệm. Chỉ giữ trong phiên ứng dụng này.',
                        ),
                        value: _relayOnly,
                        onChanged: !probe.hasSession && !probe.busy
                            ? (value) => setState(() => _relayOnly = value)
                            : null,
                      ),
                      TextField(
                        controller: _turnUrl,
                        enabled: !probe.hasSession,
                        decoration: const InputDecoration(
                          labelText: 'TURN URL (turn: hoặc turns:)',
                        ),
                      ),
                      TextField(
                        controller: _turnUser,
                        enabled: !probe.hasSession,
                        decoration: const InputDecoration(
                          labelText: 'Tài khoản TURN',
                        ),
                      ),
                      TextField(
                        controller: _turnPassword,
                        enabled: !probe.hasSession,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Credential TURN',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _copy(
                        const JsonEncoder.withIndent(
                          '  ',
                        ).convert(probe.report()),
                      ),
                      icon: const Icon(Icons.copy_all),
                      label: const Text('Sao chép kết quả thử'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _permission(String title, bool? granted) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        granted == true ? Icons.check_circle_outline : Icons.info_outline,
        size: 18,
      ),
      const SizedBox(width: 6),
      Text(
        '$title: ${granted == null
            ? "chưa kiểm tra"
            : granted
            ? "đã có"
            : "chưa có quyền"}',
      ),
    ],
  );
}
