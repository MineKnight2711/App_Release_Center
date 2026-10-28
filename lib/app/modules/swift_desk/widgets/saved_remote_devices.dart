import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/swift_desk_runtime.dart';

class SavedRemoteDevices extends StatelessWidget {
  const SavedRemoteDevices({super.key, required this.runtime});
  final SwiftDeskRuntime runtime;
  Future<void> _edit(BuildContext context, RemoteDevice device) async {
    final address = TextEditingController(text: device.endpoint.address);
    final port = TextEditingController(text: '${device.endpoint.port}');
    final alias = TextEditingController(text: device.endpoint.name);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Địa chỉ thiết bị đã ghép'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Chỉ đổi địa chỉ LAN hoặc tên hiển thị. Chứng chỉ máy đích vẫn phải khớp với lần ghép trước.',
              ),
              TextField(
                controller: alias,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Tên hiển thị'),
              ),
              TextField(
                controller: address,
                decoration: const InputDecoration(labelText: 'IPv4 LAN'),
              ),
              TextField(
                controller: port,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                decoration: const InputDecoration(labelText: 'Cổng'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (save == true) {
      await runtime.updateDeviceAddress(
        device,
        address.text,
        int.tryParse(port.text) ?? 0,
        alias.text,
      );
    }
    // Let the reverse route animation detach its fields before disposing.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    address.dispose();
    port.dispose();
    alias.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Thiết bị đã lưu',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Chứng chỉ được ghim theo máy. Kết nối lại vẫn cần máy đích chấp nhận.',
          ),
          TextButton.icon(
            onPressed:
                runtime.busy || runtime.draining || runtime.devices.isEmpty
                ? null
                : () => runtime.probeDevices(),
            icon: const Icon(Icons.refresh),
            label: const Text('Kiểm tra trạng thái LAN'),
          ),
          if (runtime.devices.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Chưa có thiết bị.'),
            ),
          for (final device in runtime.devices)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.computer),
              title: Text(device.endpoint.name),
              subtitle: Text(
                '${device.endpoint.address}:${device.endpoint.port} · ${device.platform} · ${runtime.deviceOnline[device.endpoint.deviceId] == null
                    ? "Chưa kiểm tra"
                    : runtime.deviceOnline[device.endpoint.deviceId] == true
                    ? "Đang nhận LAN"
                    : "Không phản hồi hoặc sai danh tính"}',
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  OutlinedButton(
                    onPressed:
                        runtime.active || runtime.busy || runtime.draining
                        ? null
                        : () => runtime.connectSaved(device),
                    child: const Text('Kết nối'),
                  ),
                  IconButton(
                    tooltip: 'Đổi IP, cổng hoặc tên',
                    onPressed: runtime.busy
                        ? null
                        : () => _edit(context, device),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Quên thiết bị trên máy này',
                    onPressed: runtime.busy
                        ? null
                        : () => runtime.forgetDevice(device),
                    icon: const Icon(Icons.link_off),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
