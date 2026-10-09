import 'package:flutter/material.dart';
import '../services/plan_studio_runtime.dart';

Future<void> showReminderSettings(
  BuildContext context,
  PlanStudioRuntime runtime,
) => showDialog<void>(
  context: context,
  builder: (_) => ReminderSettingsView(runtime: runtime),
);

class ReminderSettingsView extends StatefulWidget {
  const ReminderSettingsView({super.key, required this.runtime});
  final PlanStudioRuntime runtime;
  @override
  State<ReminderSettingsView> createState() => _ReminderSettingsViewState();
}

class _ReminderSettingsViewState extends State<ReminderSettingsView> {
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.runtime.refreshAutostart();
  }

  Future<void> _save(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.runtime;
    return AlertDialog(
      title: const Text('Nhắc hẹn Windows'),
      content: SizedBox(
        width: 520,
        child: ListenableBuilder(
          listenable: r,
          builder: (_, _) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy) const LinearProgressIndicator(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: r.background,
                  title: const Text('Tiếp tục nhắc khi đóng cửa sổ'),
                  subtitle: const Text(
                    'Nút X sẽ ẩn AMC xuống khay hệ thống. Chọn Thoát hoàn toàn trong menu khay để dừng ứng dụng.',
                  ),
                  onChanged: busy
                      ? null
                      : (v) => _save(() => r.settings(runInTray: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: r.autostart,
                  title: const Text('Khởi động cùng Windows'),
                  onChanged: busy
                      ? null
                      : (v) => _save(() => r.settings(startup: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: r.paused,
                  title: const Text('Tạm ngưng nhắc'),
                  subtitle: const Text(
                    'Giữ các lịch đến hạn, gom lại khi tiếp tục.',
                  ),
                  onChanged: busy
                      ? null
                      : (v) => _save(() => r.settings(pause: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: r.quiet,
                  title: const Text('Giờ yên lặng'),
                  onChanged: busy
                      ? null
                      : (v) => _save(() => r.settings(quietHours: v)),
                ),
                if (r.quiet)
                  Row(
                    children: [
                      const Text('Từ '),
                      DropdownButton<int>(
                        value: r.quietStart,
                        items: [
                          for (var h = 0; h < 24; h++)
                            DropdownMenuItem(value: h, child: Text('$h:00')),
                        ],
                        onChanged: busy
                            ? null
                            : (h) => _save(() => r.settings(from: h)),
                      ),
                      const Text(' đến '),
                      DropdownButton<int>(
                        value: r.quietEnd,
                        items: [
                          for (var h = 0; h < 24; h++)
                            DropdownMenuItem(value: h, child: Text('$h:00')),
                        ],
                        onChanged: busy
                            ? null
                            : (h) => _save(() => r.settings(until: h)),
                      ),
                    ],
                  ),
                const Text(
                  'Máy tắt, sleep hoặc đã thoát hoàn toàn: lịch bị lỡ sẽ xuất hiện khi AMC chạy lại. Nhắc hẹn lưu trên máy, không gửi qua mạng.',
                ),
                if (error ?? r.error ?? r.scheduler?.error
                    case final String message)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => _save(r.preview),
          child: const Text('Thử popup'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}
