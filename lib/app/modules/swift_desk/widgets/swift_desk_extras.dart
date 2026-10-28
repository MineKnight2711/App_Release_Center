import 'dart:io';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/app_background_service.dart';
import '../infrastructure/remote_settings.dart';
import '../infrastructure/remote_network.dart';
import '../services/swift_desk_cloud.dart';
import '../services/swift_desk_runtime.dart';

class SwiftDeskExtras extends StatefulWidget {
  const SwiftDeskExtras({super.key, required this.runtime});
  final SwiftDeskRuntime runtime;
  @override
  State<SwiftDeskExtras> createState() => _SwiftDeskExtrasState();
}

class _SwiftDeskExtrasState extends State<SwiftDeskExtras> {
  SwiftDeskCloud? cloud;
  final invitation = TextEditingController();
  final startup = DesktopAutoStartService();
  bool busy = false, autostart = false;
  String? error;
  SwiftDeskRuntime get runtime => widget.runtime;
  @override
  void initState() {
    super.initState();
    _readAutostart();
  }

  Future<void> _readAutostart() async {
    try {
      final enabled = await startup.isEnabled();
      if (mounted) setState(() => autostart = enabled);
    } catch (_) {}
  }

  @override
  void dispose() {
    cloud?.removeListener(_changed);
    invitation.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _work(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      error = e is StateError
          ? e.message.toString()
          : e is FormatException
          ? e.message.toString()
          : 'Không hoàn tất được thao tác. Kiểm tra cấu hình và thử lại.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<SwiftDeskCloud> _cloud() async {
    if (cloud != null) return cloud!;
    cloud = await SwiftDeskCloud.open(runtime);
    cloud!.addListener(_changed);
    return cloud!;
  }

  Future<void> _invite() async {
    final value = await cloud!.invitation();
    if (value == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mã Internet dùng một lần · 5 phút'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: SelectableText(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            child: const Text('Sao chép mã'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null || picked.files.single.path == null) return;
    final file = File(picked.files.single.path!);
    if (await file.length() > 1048576) {
      throw const FormatException('File import tối đa 1 MB.');
    }
    final preview = LegacyRemoteImport.preview(await file.readAsString());
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nhập ${preview.length} thiết bị cũ'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chỉ lấy tên/địa chỉ. Mọi máy cần ghép lại bằng mã AMC. File nguồn được giữ nguyên.',
                ),
                const SizedBox(height: 12),
                for (final item in preview)
                  Text('${item['name']} · ${item['address']}:${item['port']}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: preview.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Nhập metadata'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await LegacyRemoteImport.apply(runtime.settings, preview);
    }
  }

  Widget _toggle(
    String title,
    String subtitle,
    String key, {
    bool enabled = true,
  }) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle),
    value: runtime.settings.flag(key),
    onChanged: busy || !enabled
        ? null
        : (v) => _work(() async {
            if (key == 'background') {
              await runtime.backgroundService?.reason(
                'remoteHost',
                runtime.active || (runtime.hostEnabled && v),
              );
            }
            await runtime.settings.setFlag(key, v);
          }),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Internet · Tài khoản AMC',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                cloud?.status ??
                    'Chưa bật. Cần API AMC hỗ trợ desktop. Có thể dùng P2P IPv6/IPv4; TURN là đường dự phòng khi đã cấu hình.',
              ),
              if (cloud?.cloudId != null)
                SelectableText('ID AMC: ${cloud!.cloudId}'),
              if (cloud?.error != null)
                Text(
                  cloud!.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Đường kết nối Internet',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<RemoteConnectionMode>(
                    key: const Key('swift-desk-connection-mode'),
                    value: runtime.settings.connectionMode,
                    isExpanded: true,
                    items: RemoteConnectionMode.values
                        .map(
                          (mode) => DropdownMenuItem(
                            value: mode,
                            child: Text(mode.label),
                          ),
                        )
                        .toList(),
                    onChanged:
                        busy ||
                            cloud?.busy == true ||
                            runtime.active ||
                            runtime.busy ||
                            runtime.draining
                        ? null
                        : (mode) {
                            if (mode != null) {
                              _work(
                                () => runtime.settings.setConnectionMode(mode),
                              );
                            }
                          },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(runtime.settings.connectionMode.explanation),
              const Text(
                'Áp dụng cho phiên Internet mới. Hai máy vẫn cần duyệt yêu cầu và xác thực như trước.',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed:
                        busy || cloud?.busy == true || !runtime.hostEnabled
                        ? null
                        : () => _work(() async {
                            final controller = await _cloud();
                            if (controller.wanted) {
                              await controller.stop();
                            } else {
                              await controller.start();
                            }
                          }),
                    child: Text(
                      cloud?.wanted == true
                          ? 'Tắt nhận Internet'
                          : 'Bật nhận Internet',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: busy || cloud?.online != true
                        ? null
                        : () => _work(_invite),
                    child: const Text('Tạo mã Internet'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: invitation,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Dán mã Internet AMC',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed:
                    busy || runtime.active || runtime.busy || runtime.draining
                    ? null
                    : () => _work(() async {
                        await (await _cloud()).connectInvitation(
                          invitation.text.trim(),
                        );
                      }),
                child: const Text('Kết nối qua Internet'),
              ),
              if (cloud != null)
                for (final peer in cloud!.saved)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(peer.name),
                    subtitle: Text(
                      'ID ${peer.cloudId} · Cần máy đích chấp nhận',
                    ),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Kết nối',
                          onPressed: busy || runtime.active
                              ? null
                              : () => _work(() => cloud!.connectSaved(peer)),
                          icon: const Icon(Icons.link),
                        ),
                        IconButton(
                          tooltip: 'Quên trên máy này',
                          onPressed: busy
                              ? null
                              : () => _work(() => cloud!.forget(peer)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Chạy nền và khôi phục',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _toggle(
                'Giữ host khi đóng cửa sổ',
                'AMC tiếp tục chạy trong tray/menu bar. Thoát AMC sẽ ngắt mọi phiên.',
                'background',
              ),
              _toggle(
                'Khôi phục host khi mở AMC',
                'Tự bật lại nhận LAN trên cổng đã lưu; vẫn duyệt từng phiên.',
                'restoreHost',
              ),
              _toggle(
                'Khôi phục nhận Internet',
                'Chỉ hoạt động khi đã bật khôi phục host và đăng nhập AMC.',
                'restoreInternet',
                enabled: runtime.settings.flag('restoreHost'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mở AMC khi đăng nhập máy'),
                subtitle: const Text(
                  'Cài đặt chung cho AMC. Không chạy ở màn hình đăng nhập hệ điều hành.',
                ),
                value: autostart,
                onChanged: busy || !startup.supported
                    ? null
                    : (v) => _work(() async {
                        await startup.setEnabled(v);
                        autostart = await startup.isEnabled();
                      }),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _work(_import),
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Nhập thiết bị từ SwiftDesk cũ'),
              ),
              for (final item in runtime.settings.metadata('legacyDevices'))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['name'] as String),
                  subtitle: Text(
                    '${item['address']}:${item['port']} · Cần ghép lại bằng mã AMC',
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}
