import 'dart:io';
import 'dart:typed_data';

import 'package:app_management_center/app/modules/shared/module_widgets.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../controllers/bundle_check_controller.dart';
import '../models/bundle_check_models.dart';
import '../widgets/bundle_check_widgets.dart';
import 'bundle_check_view.dart';

/// "Chạy được không": pick a device, install, open, watch — then the results,
/// the screenshots and the log.
class DeviceRunCard extends StatelessWidget {
  const DeviceRunCard({
    super.key,
    required this.controller,
    required this.report,
  });

  final BundleCheckController controller;
  final BundleCheckReport report;

  Future<void> _confirmUninstall(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Gỡ bản đang cài?'),
        content: Text(
          'Máy ${controller.target?.label ?? ''} đang có '
          '${report.packageName} ký bằng key khác hoặc version cao hơn. '
          'Gỡ nó sẽ xoá dữ liệu của app trên máy này (đăng nhập, cache, file '
          'đã lưu).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Thôi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gỡ và cài lại'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.runOnDevice(allowUninstall: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = report.inGroup(CheckGroup.run).toList();
    final live = controller.run?.report.id == report.id;
    final summary = report.deviceRun;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return ModuleCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SectionLabel(CheckGroup.run.label),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: live
                ? _Controls(controller: controller)
                : Text(
                    'Mở từ lịch sử — bấm Kiểm lại để chạy thử bản này.',
                    style: muted,
                  ),
          ),
          if (controller.deviceRunning) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${controller.progress}…',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (controller.deviceError != null && live) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: NoticeBox(
                text: controller.deviceError!,
                tone: NoticeTone.danger,
              ),
            ),
          ],
          if (controller.needsUninstallConfirm && live) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: NoticeBox(
                      text:
                          'Máy thật đang có bản khác chữ ký hoặc version cao '
                          'hơn. AMC không tự gỡ trên máy thật.',
                      tone: NoticeTone.warning,
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonal(
                    key: const Key('bundle-check-confirm-uninstall'),
                    onPressed: controller.busy
                        ? null
                        : () => _confirmUninstall(context),
                    child: const Text('Gỡ và cài lại…'),
                  ),
                ],
              ),
            ),
          ],
          if (results.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final result in results) CheckResultTile(result: result),
          ],
          if (summary != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    'Chạy trên ${summary.deviceLabel} lúc '
                    '${_time(summary.startedAt)}, '
                    '${(summary.durationMs / 1000).round()} giây, '
                    'ký bằng ${summary.signedWith}.',
                    style: muted,
                  ),
                  if (summary.logcatFile != null)
                    TextButton.icon(
                      onPressed: () async {
                        final dir = await controller.jobDirectory();
                        await revealPath(p.join(dir, summary.logcatFile!));
                      },
                      icon: const Icon(Icons.article_outlined, size: 16),
                      label: const Text('Mở logcat'),
                    ),
                ],
              ),
            ),
            if (summary.screenshots.isNotEmpty) ...[
              const SizedBox(height: 8),
              FutureBuilder<String>(
                future: controller.jobDirectory(),
                builder: (context, snapshot) {
                  final dir = snapshot.data;
                  if (dir == null) return const SizedBox(height: 280);
                  return SizedBox(
                    height: 280,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: summary.screenshots.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final name = summary.screenshots[index];
                        return _Screenshot(
                          file: File(p.join(dir, name)),
                          version: summary.startedAt,
                          caption: index == 0 && summary.screenshots.length > 1
                              ? 'Sau 3 giây'
                              : 'Lúc kết thúc',
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _time(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)} ${two(time.day)}/${two(time.month)}';
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final BundleCheckController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final target = controller.target;
    final ready = controller.bundletool == BundletoolState.ready;
    final prefs = controller.devicePreferences;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: DropdownButton<String>(
                key: const Key('bundle-check-device-picker'),
                isExpanded: true,
                isDense: true,
                hint: Text(
                  controller.loadingTargets
                      ? 'Đang tìm thiết bị…'
                      : 'Không có thiết bị',
                ),
                value: target?.key,
                onChanged: controller.busy
                    ? null
                    : (key) {
                        final picked = controller.targets
                            .where((t) => t.key == key)
                            .firstOrNull;
                        if (picked != null) controller.selectTarget(picked);
                      },
                items: [
                  for (final item in controller.targets)
                    DropdownMenuItem(
                      value: item.key,
                      child: Row(
                        children: [
                          Icon(
                            item.isEmulator
                                ? Icons.tablet_android_outlined
                                : Icons.smartphone,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Tìm lại thiết bị',
              onPressed: controller.busy || controller.loadingTargets
                  ? null
                  : controller.loadTargets,
              icon: controller.loadingTargets
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Theo dõi', style: theme.textTheme.bodySmall),
                const SizedBox(width: 6),
                DropdownButton<int>(
                  isDense: true,
                  value: const [10, 20, 30, 60].contains(prefs.watchSeconds)
                      ? prefs.watchSeconds
                      : 20,
                  onChanged: controller.busy
                      ? null
                      : (value) {
                          if (value != null) controller.setWatchSeconds(value);
                        },
                  items: [
                    for (final seconds in const [10, 20, 30, 60])
                      DropdownMenuItem(
                        value: seconds,
                        child: Text('$seconds giây'),
                      ),
                  ],
                ),
              ],
            ),
            if (target?.isEmulator ?? true)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: prefs.uninstallAfter,
                    onChanged: controller.busy
                        ? null
                        : (value) =>
                              controller.setUninstallAfter(value ?? false),
                  ),
                  Text('Gỡ app sau khi kiểm', style: theme.textTheme.bodySmall),
                ],
              ),
            FilledButton.icon(
              key: const Key('bundle-check-run-device'),
              onPressed: ready && target != null && !controller.busy
                  ? () => controller.runOnDevice()
                  : null,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(
                target?.avdName != null ? 'Bật máy ảo và chạy thử' : 'Chạy thử',
              ),
            ),
          ],
        ),
        if (!ready)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Chạy thử cần bundletool để sinh APK cho thiết bị — bấm "Tải '
              'bundletool" ở góc trên.',
              style: muted,
            ),
          ),
        if (controller.targetsError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: NoticeBox(
              text: controller.targetsError!,
              tone: NoticeTone.danger,
            ),
          )
        else if (!controller.loadingTargets && controller.targets.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Không thấy thiết bị hay máy ảo nào. Cắm điện thoại (bật USB '
              'debugging) hoặc tạo AVD trong Android Studio, rồi bấm tìm lại.',
              style: muted,
            ),
          )
        else if (target != null && !target.isEmulator)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: NoticeBox(
              text:
                  'Máy thật: app được cài đè lên bản đang có nếu cùng chữ ký, '
                  'dữ liệu giữ nguyên. AMC không gỡ gì trên máy thật khi chưa '
                  'hỏi bạn.',
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Máy ảo: bản đang cài (nếu có) được gỡ trước để cài sạch như '
              'người dùng mới.',
              style: muted,
            ),
          ),
      ],
    );
  }
}

/// A screenshot, read once per run so a newer run's file under the same name
/// is never hidden behind Flutter's image cache.
class _Screenshot extends StatefulWidget {
  const _Screenshot({
    required this.file,
    required this.version,
    required this.caption,
  });

  final File file;
  final DateTime version;
  final String caption;

  @override
  State<_Screenshot> createState() => _ScreenshotState();
}

class _ScreenshotState extends State<_Screenshot> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_Screenshot old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path || old.version != widget.version) {
      setState(_load);
    }
  }

  // Synchronous on purpose: a screencap PNG is a few hundred KB, and reading
  // it inline means the image appears in the same frame as the results.
  void _load() {
    try {
      _bytes = widget.file.readAsBytesSync();
    } on FileSystemException {
      _bytes = null;
    }
  }

  void _open() {
    final bytes = _bytes;
    if (bytes == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Stack(
          children: [
            InteractiveViewer(child: Image.memory(bytes)),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = _bytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InkWell(
            onTap: _open,
            borderRadius: BorderRadius.circular(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: bytes == null
                  ? const SizedBox(
                      width: 130,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    )
                  : Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(widget.caption, style: theme.textTheme.labelSmall),
      ],
    );
  }
}
