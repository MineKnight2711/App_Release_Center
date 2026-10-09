import 'package:flutter/material.dart';

import '../../shared/module_widgets.dart';
import '../controllers/qa_workspace_controller.dart';
import '../models/qa_models.dart';
import '../services/appium_server_service.dart';
import '../theme/qa_tokens.dart';
import '../widgets/log_console.dart';
import '../widgets/qa_widgets.dart';

/// Picks the device mobile suites run on, and runs the Appium server.
Future<void> showDevicesSheet(
  BuildContext context,
  QaWorkspaceController controller,
) {
  if (controller.devices.isEmpty && !controller.isDiscoveringDevices) {
    controller.refreshDevices();
  }
  return showQaSideSheet<void>(
    context,
    key: const Key('qa-devices-sheet'),
    title: 'Thiết bị & Appium',
    subtitle: 'Cho suite mobile và suite cần Appium',
    builder: (_) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _DevicesSheetBody(controller: controller),
    ),
  );
}

class _DevicesSheetBody extends StatelessWidget {
  const _DevicesSheetBody({required this.controller});

  final QaWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final discovering = controller.isDiscoveringDevices;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionLabel(
          'Thiết bị',
          action: TextButton.icon(
            key: const Key('qa-refresh-devices'),
            onPressed: discovering ? null : controller.refreshDevices,
            icon: discovering
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 17),
            label: Text(discovering ? 'Đang quét…' : 'Quét lại'),
          ),
        ),
        const SizedBox(height: 8),
        if (controller.deviceError != null) ...[
          NoticeBox(text: controller.deviceError!, tone: NoticeTone.warning),
          const SizedBox(height: 8),
        ],
        if (controller.devices.isEmpty)
          SizedBox(
            height: 180,
            child: QaEmptyState(
              icon: Icons.phone_android_outlined,
              title: discovering ? 'Đang quét thiết bị' : 'Không có thiết bị',
              message: discovering
                  ? 'Flutter đang kiểm tra máy ảo và điện thoại đang cắm.'
                  : 'Bật máy ảo hoặc cắm điện thoại (bật USB debugging), rồi '
                        'quét lại.',
            ),
          )
        else
          for (final device in controller.devices) ...[
            _DeviceRow(
              device: device,
              selected: device.id == controller.selectedDeviceId,
              onSelect: controller.isRunning
                  ? null
                  : () => controller.selectDevice(device.id),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 16),
        const SectionLabel('Appium'),
        const SizedBox(height: 8),
        _AppiumBox(controller: controller),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.selected,
    required this.onSelect,
  });

  final DeviceInfo device;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    return QaSelectableRow(
      key: Key('qa-device-${device.id}'),
      selected: selected,
      onTap: onSelect,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18,
            color: selected ? tokens.accent : tokens.faint,
          ),
          const SizedBox(width: 10),
          Icon(
            device.isEmulator ? Icons.phone_android : Icons.smartphone,
            size: 20,
            color: tokens.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    device.platform,
                    device.isEmulator ? 'máy ảo' : 'máy thật',
                    if (device.platformVersion != null) device.platformVersion!,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.muted,
                  ),
                ),
                Text(
                  device.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.mono(size: 10.5, color: tokens.faint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppiumBox extends StatelessWidget {
  const _AppiumBox({required this.controller});

  final QaWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final palette = tokens.palette;
    final status = controller.appiumStatus;
    final (label, color) = switch (status) {
      AppiumStatus.unavailable => ('không có trong PATH', palette.danger),
      AppiumStatus.stopped => ('đang tắt', palette.idle),
      AppiumStatus.starting => ('đang khởi động', palette.warning),
      AppiumStatus.running => ('đang chạy', palette.success),
      AppiumStatus.error => ('lỗi', palette.danger),
    };
    final busy = status == AppiumStatus.starting;
    final running = status == AppiumStatus.running;
    final logs = controller.appiumLogs;
    final detail =
        controller.appiumError ??
        (status == AppiumStatus.unavailable
            ? 'Cài bằng: npm install -g appium'
            : logs.isEmpty
            ? 'Chỉ cần cho suite có requiresAppium; tự bật khi chạy suite đó.'
            : logs.last);

    return ModuleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Appium · $label · cổng ${controller.appiumPort}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (running)
                OutlinedButton.icon(
                  key: const Key('qa-appium-stop'),
                  onPressed: controller.stopAppium,
                  icon: const Icon(Icons.stop_circle_outlined, size: 17),
                  label: const Text('Dừng'),
                )
              else
                FilledButton.tonalIcon(
                  key: const Key('qa-appium-start'),
                  onPressed: busy || status == AppiumStatus.unavailable
                      ? null
                      : controller.startAppium,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Khởi động'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
          ),
          if (logs.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 220,
              child: QaLogConsole(
                title: 'Log Appium · ${logs.length} dòng',
                lines: logs,
                expandable: false,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
