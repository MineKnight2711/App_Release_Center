import 'dart:async';
import '../modules/analytics/feature_analytics_service.dart';
import '../modules/analytics/analytics_view.dart';

import 'package:app_management_center/app/services/app_lock_service.dart';
import 'package:app_management_center/app/services/app_settings_service.dart';
import 'package:app_management_center/app/services/theme_service.dart';
import 'package:app_management_center/app/services/windows_auto_start_service.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<void> showAppSettings(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const AppSettingsDialog(),
);

class AppSettingsButton extends StatelessWidget {
  const AppSettingsButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('open-app-settings'),
    tooltip: 'Cài đặt',
    onPressed: () => unawaited(showAppSettings(context)),
    icon: const Icon(Icons.settings_outlined),
  );
}

class AppSettingsDialog extends StatelessWidget {
  const AppSettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<AppSettingsService>();
    final theme = Get.find<ThemeService>();
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.settings_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cài đặt',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (Get.isRegistered<FeatureAnalyticsService>()) ...[
                      const _SettingsHeading('Thống kê sử dụng'),
                      Obx(
                        () => SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Chia sẻ thống kê sử dụng'),
                          subtitle: const Text(
                            'Gửi số lượt dùng và kết quả thao tác để cải tiến AMC. Không gửi nội dung file, token hay dữ liệu dự án. Tắt sẽ xóa hàng đợi chưa gửi trên máy này.',
                          ),
                          value: settings.analyticsEnabled.value,
                          onChanged: settings.setAnalyticsEnabled,
                        ),
                      ),
                      if (!Get.find<FeatureAnalyticsService>().production)
                        const Text(
                          'Bản debug/test không gửi thống kê production.',
                        ),
                      Obx(() {
                        final analytics = Get.find<FeatureAnalyticsService>();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (analytics.canView.value)
                              OutlinedButton.icon(
                                onPressed: () => showFeatureAnalytics(context),
                                icon: const Icon(Icons.insights_outlined),
                                label: const Text('Mở thống kê sử dụng'),
                              ),
                            TextButton(
                              onPressed: analytics.refreshAccess,
                              child: const Text('Kiểm tra quyền dashboard'),
                            ),
                            if (analytics.status.value.isNotEmpty)
                              Text(analytics.status.value),
                            if (analytics.dropped.value +
                                    analytics.rejected.value >
                                0)
                              Text(
                                'Sự kiện bỏ qua trên máy: ${analytics.dropped.value}; server từ chối: ${analytics.rejected.value}',
                              ),
                          ],
                        );
                      }),
                      const SizedBox(height: 24),
                    ],
                    const _SettingsHeading('Giao diện'),
                    const Text('Theme'),
                    const SizedBox(height: 8),
                    Obx(
                      () => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final choice in AppThemeChoice.values)
                            ChoiceChip(
                              key: Key('settings-theme-${choice.name}'),
                              avatar: Icon(choice.icon, size: 18),
                              label: Text(choice.label),
                              selected: theme.choice.value == choice,
                              onSelected: (_) =>
                                  unawaited(theme.setChoice(choice)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Obx(
                      () => _ScaleControl(
                        id: 'font',
                        title: 'Cỡ chữ',
                        description: 'Điều chỉnh chữ trong toàn bộ ứng dụng.',
                        value: settings.fontScale.value,
                        min: AppSettingsService.minFontScale,
                        max: AppSettingsService.maxFontScale,
                        onChanged: settings.setFontScale,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Obx(
                      () => _ScaleControl(
                        id: 'interface',
                        title: 'Kích thước giao diện',
                        description:
                            'Phóng to hoặc thu nhỏ widget, nút, biểu tượng và khoảng cách. Chữ cũng thay đổi theo.',
                        value: settings.interfaceScale.value,
                        min: AppSettingsService.minInterfaceScale,
                        max: AppSettingsService.maxInterfaceScale,
                        onChanged: settings.setInterfaceScale,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Xem trước',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'App Management Center — chữ và widget thay đổi ngay khi điều chỉnh.',
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Nút mẫu'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('reset-display-settings'),
                      onPressed: () => unawaited(settings.resetDisplay()),
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Đặt lại kích thước về 100%'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Thay đổi được áp dụng ngay và tự lưu trên thiết bị này.',
                    ),
                    Obx(
                      () => settings.saveError.value.isEmpty
                          ? const SizedBox.shrink()
                          : Text(
                              settings.saveError.value,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                    ),
                    if (WindowsAutoStartService().isSupported) ...[
                      const SizedBox(height: 24),
                      const _SettingsHeading('Cài đặt chung'),
                      const _AutoStartSetting(),
                    ],
                    if (Get.isRegistered<AppLockService>()) ...[
                      const SizedBox(height: 24),
                      const _SettingsHeading('Khóa ứng dụng'),
                      const _AppLockSettings(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeading extends StatelessWidget {
  const _SettingsHeading(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _ScaleControl extends StatelessWidget {
  const _ScaleControl({
    required this.id,
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String id, title, description;
  final double value, min, max;
  final Future<void> Function(double) onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$title · ${(value * 100).round()}%',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 4),
      Text(description, style: Theme.of(context).textTheme.bodySmall),
      Row(
        children: [
          IconButton(
            key: Key('$id-scale-decrease'),
            tooltip: 'Thu nhỏ $title',
            onPressed: value <= min
                ? null
                : () => unawaited(
                    onChanged(((value - 0.05) * 100).round() / 100),
                  ),
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Slider(
              key: Key('$id-scale-slider'),
              label: '${(value * 100).round()}%',
              min: min,
              max: max,
              divisions: ((max - min) / 0.05).round(),
              value: value,
              onChanged: (next) => unawaited(onChanged(next)),
            ),
          ),
          IconButton(
            key: Key('$id-scale-increase'),
            tooltip: 'Phóng to $title',
            onPressed: value >= max
                ? null
                : () => unawaited(
                    onChanged(((value + 0.05) * 100).round() / 100),
                  ),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    ],
  );
}

class _AutoStartSetting extends StatefulWidget {
  const _AutoStartSetting();
  @override
  State<_AutoStartSetting> createState() => _AutoStartSettingState();
}

class _AutoStartSettingState extends State<_AutoStartSetting> {
  final _service = WindowsAutoStartService();
  late bool _enabled = _service.isEnabled();
  bool _busy = false;
  String _error = '';

  Future<void> _apply(bool value) async {
    setState(() => _busy = true);
    try {
      await _service.setEnabled(value);
      _error = '';
    } catch (error) {
      _error = 'Không đổi được: $error';
    }
    if (!mounted) return;
    setState(() {
      _enabled = _service.isEnabled();
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('Tự khởi động cùng Windows'),
    subtitle: Text(
      _error.isNotEmpty
          ? _error
          : 'Giúp điện thoại kết nối lại sau khi máy tính khởi động lại.',
    ),
    value: _enabled,
    onChanged: _busy ? null : (value) => unawaited(_apply(value)),
  );
}

class _AppLockSettings extends StatelessWidget {
  const _AppLockSettings();
  @override
  Widget build(BuildContext context) {
    final service = Get.find<AppLockService>();
    return Obx(() {
      final usable = service.availability.value.usable;
      return Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hỏi sinh trắc học khi mở app'),
            subtitle: Text(
              usable
                  ? 'Khóa lại sau ${service.settings.value.graceSeconds} giây kể từ khi thoát ra nền.'
                  : 'Máy chưa đăng ký khuôn mặt, vân tay hay mã PIN.',
            ),
            value: service.settings.value.enabled && usable,
            onChanged: usable && !service.isPrompting.value
                ? (value) => unawaited(service.setEnabled(value))
                : null,
          ),
          if (service.settings.value.enabled && usable)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hỏi lại khi tắt hoặc khởi động lại máy'),
              subtitle: const Text('Mở khóa Windows luôn hỏi, không tắt được.'),
              value: service.settings.value.protectSensitiveActions,
              onChanged: service.isPrompting.value
                  ? null
                  : (value) =>
                        unawaited(service.setProtectSensitiveActions(value)),
            ),
          if (service.status.value.isNotEmpty)
            Text(
              service.status.value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      );
    });
  }
}
