import 'dart:io';

import 'package:app_management_center/app/modules/shared/module_widgets.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../controllers/bundle_check_controller.dart';
import '../models/bundle_check_models.dart';
import '../services/bundle_check_service.dart';
import '../telegram/telegram_intake_service.dart';
import '../widgets/bundle_check_widgets.dart';
import 'device_run_card.dart';
import 'env_contract_dialog.dart';
import 'telegram_bot_dialog.dart';

/// Opens the AAB checker as a full page over the shell.
Future<void> showBundleCheck(BuildContext context) => Navigator.of(
  context,
).push<void>(MaterialPageRoute(builder: (_) => const BundleCheckView()));

/// Drop an AAB, get three answers: built right, env complete, runs.
class BundleCheckView extends StatefulWidget {
  const BundleCheckView({super.key, this.controller});

  /// Injected by the tests; left null the page builds its own.
  final BundleCheckController? controller;

  @override
  State<BundleCheckView> createState() => _BundleCheckViewState();
}

class _BundleCheckViewState extends State<BundleCheckView> {
  late final BundleCheckController _controller =
      widget.controller ?? BundleCheckController();
  late final bool _ownsController = widget.controller == null;

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Kiểm tra AAB'),
            actions: [
              if (Get.isRegistered<TelegramIntakeService>())
                _TelegramBotButton(service: Get.find<TelegramIntakeService>()),
              _BundletoolStatus(controller: _controller),
              const SizedBox(width: 12),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final side = _SidePanel(controller: _controller);
              final main = _MainPane(controller: _controller);
              if (constraints.maxWidth < 900) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [side, const SizedBox(height: 16), main],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 330,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                      child: side,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
                      child: main,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _TelegramBotButton extends StatelessWidget {
  const _TelegramBotButton({required this.service});

  final TelegramIntakeService service;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final busy = service.current != null;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton.icon(
            key: const Key('bundle-check-telegram-bot'),
            onPressed: () => showTelegramBotDialog(context),
            icon: Icon(
              service.lastError != null
                  ? Icons.error_outline
                  : busy
                  ? Icons.hourglass_top
                  : Icons.smart_toy_outlined,
              size: 18,
            ),
            label: Text(
              busy
                  ? 'Bot: đang kiểm'
                  : service.running
                  ? 'Bot Telegram: bật'
                  : 'Bot Telegram',
            ),
          ),
        );
      },
    );
  }
}

class _BundletoolStatus extends StatelessWidget {
  const _BundletoolStatus({required this.controller});

  final BundleCheckController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (controller.bundletool) {
      BundletoolState.unknown => const SizedBox.shrink(),
      BundletoolState.ready => StatusChip(
        label: 'bundletool sẵn sàng',
        icon: Icons.build_circle_outlined,
        color: AppCyberTheme.success,
        tooltip: 'bundletool-all-1.18.3.jar, đã kiểm SHA-256.',
      ),
      BundletoolState.downloading => StatusChip(
        label:
            'Đang tải bundletool ${(controller.downloadProgress * 100).round()}%',
        icon: Icons.downloading_outlined,
        color: theme.colorScheme.primary,
      ),
      BundletoolState.missing => Tooltip(
        message:
            controller.bundletoolError ??
            'Cần cho bundletool validate và xuất APK universal. '
                'Tải từ GitHub của Google (31 MB), kiểm SHA-256 trước khi dùng.',
        child: TextButton.icon(
          key: const Key('bundle-check-download-bundletool'),
          onPressed: controller.downloadBundletool,
          icon: Icon(
            controller.bundletoolError == null
                ? Icons.download_outlined
                : Icons.error_outline,
            size: 18,
          ),
          label: const Text('Tải bundletool'),
        ),
      ),
    };
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.controller});

  final BundleCheckController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DropZone(controller: controller),
        const SizedBox(height: 16),
        ModuleCard(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Lịch sử'),
              const SizedBox(height: 8),
              if (controller.history.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Chưa kiểm file nào.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              for (final item in controller.history)
                _HistoryTile(
                  report: item,
                  selected: controller.report?.id == item.id,
                  onTap: () => controller.showReport(item),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DropZone extends StatefulWidget {
  const _DropZone({required this.controller});

  final BundleCheckController controller;

  @override
  State<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> {
  bool _hovering = false;

  Future<void> _accept(String path) async {
    if (p.extension(path).toLowerCase() != '.aab') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bản này chỉ nhận file .aab.')),
      );
      return;
    }
    await widget.controller.checkFile(path);
  }

  Future<void> _pick() async {
    final file = await file_selector.openFile(
      acceptedTypeGroups: const [
        file_selector.XTypeGroup(
          label: 'Android App Bundle',
          extensions: ['aab'],
        ),
      ],
      confirmButtonText: 'Kiểm tra',
    );
    if (file != null) await _accept(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = widget.controller.busy;
    final accent = _hovering
        ? theme.colorScheme.primary
        : AppCyberTheme.lineBlue;
    return DropTarget(
      enable: !busy,
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: (details) {
        setState(() => _hovering = false);
        final path = details.files.firstOrNull?.path;
        if (path != null) _accept(path);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(20),
        decoration: AppCyberTheme.panelDecoration(active: _hovering).copyWith(
          border: Border.all(color: accent, width: _hovering ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(
              _hovering
                  ? Icons.file_download_outlined
                  : Icons.inventory_2_outlined,
              size: 36,
              color: accent,
            ),
            const SizedBox(height: 10),
            Text(
              _hovering ? 'Thả để kiểm tra' : 'Kéo file .aab vào đây',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Đọc tại chỗ, không giải nén ra đĩa, không gửi đi đâu.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const Key('bundle-check-pick-file'),
              onPressed: busy ? null : _pick,
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: const Text('Chọn file…'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.report,
    required this.selected,
    required this.onTap,
  });

  final BundleCheckReport report;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = report.overall;
    final time = report.createdAt;
    final stamp =
        '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return ListTile(
      dense: true,
      selected: selected,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(
        checkStatusIcon(status),
        color: checkStatusColor(context, status),
        size: 20,
      ),
      title: Text(
        report.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${report.versionLabel} · $stamp',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}

class _MainPane extends StatelessWidget {
  const _MainPane({required this.controller});

  final BundleCheckController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (controller.stage == BundleCheckStage.checking) {
      return ModuleCard(
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Đang kiểm: ${controller.progress}…',
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
      );
    }

    final report = controller.report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.error != null) ...[
          NoticeBox(text: controller.error!, tone: NoticeTone.danger),
          const SizedBox(height: 12),
        ],
        if (report == null)
          const _EmptyState()
        else
          _ReportView(controller: controller, report: report),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget line(IconData icon, String title, String body) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(body, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ModuleCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Thả một AAB bên trái để bắt đầu',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          line(
            Icons.verified_outlined,
            'Build đúng không',
            'Package, version so với pubspec và CH Play, chữ ký (có phải debug '
                'key không), bản release, ABI, căn trang 16 KB, targetSdk.',
          ),
          line(
            Icons.key_outlined,
            'Đủ env không',
            'File .env trong bundle so với key code đọc, host máy dev, Firebase '
                'project, meta-data, bí mật lộ trong assets.',
          ),
          line(
            Icons.play_circle_outline,
            'Chạy được không',
            'Cài lên máy ảo hoặc máy thật, mở app, theo dõi crash, ANR và lỗi '
                'Flutter trong logcat, chụp màn hình.',
          ),
        ],
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({required this.controller, required this.report});

  final BundleCheckController controller;
  final BundleCheckReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportHeader(controller: controller, report: report),
        const SizedBox(height: 12),
        for (final group in CheckGroup.values) ...[
          if (group == CheckGroup.run)
            DeviceRunCard(controller: controller, report: report)
          else
            _GroupCard(group: group, results: report.inGroup(group).toList()),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({required this.controller, required this.report});

  final BundleCheckController controller;
  final BundleCheckReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final run = controller.run?.report.id == report.id ? controller.run : null;
    final signer = report.signer;
    final pinnable =
        signer != null &&
        !signer.isAndroidDebug &&
        report.results.any(
          (r) =>
              r.id == 'B04' &&
              r.status == CheckStatus.pass &&
              r.hint.isNotEmpty,
        );
    final sourceExists = File(report.sourcePath).existsSync();

    return ModuleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                checkStatusIcon(report.overall),
                size: 28,
                color: checkStatusColor(context, report.overall),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      report.fileName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      '${report.packageName} · ${report.versionLabel} · '
                      '${formatBytes(report.fileSize)} · '
                      'targetSdk ${report.targetSdk ?? '?'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (signer != null)
                      SelectableText(
                        'Ký bởi ${signer.subjectLine}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final status in const [
                CheckStatus.fail,
                CheckStatus.warn,
                CheckStatus.pass,
                CheckStatus.skip,
              ])
                StatusCount(status: status, count: report.count(status)),
              Text(
                '${(report.durationMs / 1000).toStringAsFixed(1)} giây',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ProjectPicker(controller: controller, report: report, run: run),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('bundle-check-recheck'),
                onPressed: sourceExists && !controller.busy
                    ? () => controller.recheck()
                    : null,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Kiểm lại'),
              ),
              OutlinedButton.icon(
                key: const Key('bundle-check-contract'),
                onPressed: controller.busy
                    ? null
                    : () => showEnvContractDialog(context, controller),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Contract env'),
              ),
              if (pinnable)
                OutlinedButton.icon(
                  key: const Key('bundle-check-pin-signer'),
                  onPressed: controller.busy ? null : controller.pinSigner,
                  icon: const Icon(Icons.push_pin_outlined, size: 18),
                  label: const Text('Ghim chữ ký'),
                ),
              OutlinedButton.icon(
                key: const Key('bundle-check-universal-apk'),
                onPressed:
                    run != null &&
                        !controller.busy &&
                        controller.bundletool == BundletoolState.ready
                    ? controller.exportUniversalApk
                    : null,
                icon: controller.exporting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.android, size: 18),
                label: const Text('Xuất APK universal'),
              ),
              TextButton.icon(
                onPressed: () async => revealPath(
                  controller.exportedApk?.path ??
                      await controller.jobDirectory(),
                ),
                icon: const Icon(Icons.folder_outlined, size: 18),
                label: const Text('Mở thư mục'),
              ),
            ],
          ),
          if (controller.bundletool != BundletoolState.ready &&
              run != null) ...[
            const SizedBox(height: 8),
            Text(
              'Xuất APK universal cần bundletool — bấm "Tải bundletool" ở góc trên.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (controller.exportedApk != null) ...[
            const SizedBox(height: 10),
            NoticeBox(
              text:
                  'Đã xuất ${p.basename(controller.exportedApk!.path)} '
                  '(${formatBytes(controller.exportedApk!.lengthSync())}). '
                  '${run?.keystore == null ? 'Ký bằng debug key của bundletool.' : 'Ký bằng ${run!.keystore!.source}.'}',
            ),
          ],
          if (controller.exportError != null) ...[
            const SizedBox(height: 10),
            NoticeBox(text: controller.exportError!, tone: NoticeTone.danger),
          ],
        ],
      ),
    );
  }
}

class _ProjectPicker extends StatelessWidget {
  const _ProjectPicker({
    required this.controller,
    required this.report,
    required this.run,
  });

  final BundleCheckController controller;
  final BundleCheckReport report;
  final BundleCheckRun? run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidates = run?.candidates ?? const <BundleProjectCandidate>[];
    final label = report.projectName == null
        ? 'Không gắn project'
        : 'Project: ${report.projectName}';
    if (run == null || candidates.isEmpty) {
      return Text(
        run == null
            ? '$label (mở từ lịch sử — bấm Kiểm lại để chạy với dữ liệu mới).'
            : '$label — không có project nào trong AMC có applicationId '
                  '${report.packageName}. Mở project đó một lần để AMC nhận ra.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Row(
      children: [
        Text('So với project', style: theme.textTheme.bodySmall),
        const SizedBox(width: 10),
        Flexible(
          child: DropdownButton<String>(
            key: const Key('bundle-check-project-picker'),
            isDense: true,
            value: report.projectPath ?? '',
            onChanged: controller.busy
                ? null
                : (value) {
                    if (value == null || value == (report.projectPath ?? '')) {
                      return;
                    }
                    if (value.isEmpty) {
                      controller.recheck(detachProject: true);
                    } else {
                      controller.recheck(
                        project: candidates.firstWhere((c) => c.path == value),
                      );
                    }
                  },
            items: [
              for (final candidate in candidates)
                DropdownMenuItem(
                  value: candidate.path,
                  child: Text(
                    '${candidate.name} (${candidate.applicationId})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const DropdownMenuItem(
                value: '',
                child: Text('Không gắn project'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.results});

  final CheckGroup group;
  final List<CheckResult> results;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ModuleCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SectionLabel(group.label),
          ),
          const SizedBox(height: 4),
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Không có kiểm tra nào.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final result in results) CheckResultTile(result: result),
        ],
      ),
    );
  }
}

/// Shows [path] in Explorer, selected when it is a file.
Future<void> revealPath(String path) async {
  if (path.isEmpty) return;
  if (Platform.isWindows) {
    final isFile = FileSystemEntity.isFileSync(path);
    await Process.start('explorer.exe', [if (isFile) '/select,', path]);
    return;
  }
  final directory = FileSystemEntity.isFileSync(path) ? p.dirname(path) : path;
  await launchUrl(Uri.file(directory));
}
