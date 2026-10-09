import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../shared/module_widgets.dart';
import '../controllers/qa_workspace_controller.dart';
import '../models/qa_models.dart';
import '../services/report_export_service.dart';
import '../theme/qa_tokens.dart';
import '../widgets/log_console.dart';
import '../widgets/qa_widgets.dart';
import 'automation_dialogs.dart';
import 'issue_report_dialog.dart';

enum _ResultTab { detail, compare, trend }

/// Every saved run: what each suite did, how it compares with an earlier run,
/// and the trend across runs. The standalone app split this over History and
/// Reports.
class QaResultsPage extends StatefulWidget {
  const QaResultsPage({
    super.key,
    required this.controller,
    required this.onRunStarted,
  });

  final QaWorkspaceController controller;
  final VoidCallback onRunStarted;

  @override
  State<QaResultsPage> createState() => _QaResultsPageState();
}

class _QaResultsPageState extends State<QaResultsPage> {
  _ResultTab _tab = _ResultTab.detail;

  /// The earlier run to compare against; null means the one just before.
  String? _compareWith;

  QaWorkspaceController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // Both notify listeners, which must not happen while this page builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.refreshReports();
      final batches = _controller.historyBatches;
      if (batches.isNotEmpty &&
          !batches.any((batch) => batch.id == _controller.selectedBatchId)) {
        _controller.selectHistoryBatch(batches.first.id);
      }
    });
  }

  Future<void> _export(RunBatchSummary batch, ReportFormat format) async {
    final extension = switch (format) {
      ReportFormat.html => 'html',
      ReportFormat.junit => 'xml',
      ReportFormat.json => 'json',
    };
    final location = await getSaveLocation(
      suggestedName: 'qa-report-${batch.id}.$extension',
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'Báo cáo ${extension.toUpperCase()}',
          extensions: [extension],
        ),
      ],
    );
    if (location == null) return;
    final error = await _controller.exportBatch(
      batch.id,
      format,
      location.path,
    );
    if (mounted) {
      showQaMessage(context, error ?? 'Đã xuất báo cáo ${location.path}.');
    }
  }

  Future<void> _rerunFailed(RunBatchSummary batch) async {
    widget.onRunStarted();
    final message = await _controller.rerunFailures(batch.id);
    if (message != null && mounted) showQaMessage(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final batches = _controller.historyBatches;
        if (batches.isEmpty) {
          return _controller.isLoadingHistory
              ? const Center(child: CircularProgressIndicator())
              : const QaEmptyState(
                  icon: Icons.history_toggle_off,
                  title: 'Chưa có lượt chạy nào',
                  message:
                      'Kết quả, log và báo cáo của từng lượt hiện ở đây sau '
                      'lượt chạy đầu tiên.',
                );
        }
        RunBatchSummary? batch;
        for (final item in batches) {
          if (item.id == _controller.selectedBatchId) batch = item;
        }
        final list = _BatchList(
          controller: _controller,
          onSelect: (id) {
            setState(() => _compareWith = null);
            _controller.selectHistoryBatch(id);
          },
        );
        final detail = batch == null
            ? const ModuleCard(
                child: QaEmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'Chọn một lượt',
                  message: 'Chọn lượt ở danh sách để xem từng suite.',
                ),
              )
            : _BatchDetail(
                controller: _controller,
                batch: batch,
                tab: _tab,
                onTab: (tab) => setState(() => _tab = tab),
                compareWith: _compareWith,
                onCompareWith: (id) => setState(() => _compareWith = id),
                onExport: (format) => _export(batch!, format),
                onRerunFailed: () => _rerunFailed(batch!),
              );

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 950) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 230, child: list),
                    const SizedBox(height: 12),
                    Expanded(child: detail),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 320, child: list),
                  const SizedBox(width: 12),
                  Expanded(child: detail),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _BatchList extends StatelessWidget {
  const _BatchList({required this.controller, required this.onSelect});

  final QaWorkspaceController controller;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final batches = controller.historyBatches;
    return ModuleCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaPanelHeader(
            title: 'Các lượt',
            subtitle: '${batches.length} lượt gần nhất',
            trailing: [
              IconButton(
                tooltip: 'Làm mới',
                onPressed: controller.isLoadingHistory
                    ? null
                    : () {
                        controller.refreshHistory();
                        controller.refreshReports();
                      },
                icon: const Icon(Icons.refresh, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: batches.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final batch = batches[index];
                return QaSelectableRow(
                  key: Key('qa-batch-${batch.id}'),
                  selected: batch.id == controller.selectedBatchId,
                  onTap: () => onSelect(batch.id),
                  child: Row(
                    children: [
                      QaStatusIcon(status: batch.status),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullDateTime(batch.startedAt),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontFeatures: QaTokens.tabular,
                              ),
                            ),
                            Text(
                              [
                                '${batch.passed}/${batch.total} qua',
                                if (batch.failed > 0) '${batch.failed} lỗi',
                                if (batch.cancelled > 0)
                                  '${batch.cancelled} đã dừng',
                              ].join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tokens.muted,
                                fontFeatures: QaTokens.tabular,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        shortDuration(batch.duration),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.muted,
                          fontFeatures: QaTokens.tabular,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchDetail extends StatelessWidget {
  const _BatchDetail({
    required this.controller,
    required this.batch,
    required this.tab,
    required this.onTab,
    required this.compareWith,
    required this.onCompareWith,
    required this.onExport,
    required this.onRerunFailed,
  });

  final QaWorkspaceController controller;
  final RunBatchSummary batch;
  final _ResultTab tab;
  final ValueChanged<_ResultTab> onTab;
  final String? compareWith;
  final ValueChanged<String> onCompareWith;
  final ValueChanged<ReportFormat> onExport;
  final VoidCallback onRerunFailed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    return ModuleCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QaStatusIcon(status: batch.status, size: 24),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Lượt ${fullDateTime(batch.startedAt)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: QaTokens.tabular,
                        ),
                      ),
                      Text(
                        [
                          '${batch.total} suite',
                          '${batch.passed} qua',
                          if (batch.failed > 0) '${batch.failed} lỗi',
                          if (batch.cancelled > 0) '${batch.cancelled} đã dừng',
                          if (batch.duration != null)
                            longDuration(batch.duration),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.muted,
                          fontFeatures: QaTokens.tabular,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (batch.failed > 0)
                    OutlinedButton.icon(
                      key: const Key('qa-batch-rerun'),
                      onPressed: controller.isRunning ? null : onRerunFailed,
                      icon: const Icon(Icons.replay, size: 17),
                      label: const Text('Chạy lại suite lỗi'),
                    ),
                  FilledButton.tonalIcon(
                    key: const Key('qa-batch-report'),
                    onPressed: () => showIssueReport(
                      context,
                      controller.batchIssueReport(batch.id),
                    ),
                    icon: const Icon(Icons.assignment_outlined, size: 17),
                    label: const Text('Báo cáo issue'),
                  ),
                  MenuAnchor(
                    menuChildren: [
                      MenuItemButton(
                        onPressed: () => onExport(ReportFormat.html),
                        child: const Text('HTML'),
                      ),
                      MenuItemButton(
                        onPressed: () => onExport(ReportFormat.junit),
                        child: const Text('JUnit XML (kèm log, cho CI)'),
                      ),
                      MenuItemButton(
                        onPressed: () => onExport(ReportFormat.json),
                        child: const Text('JSON'),
                      ),
                    ],
                    builder: (context, menu, _) => OutlinedButton.icon(
                      key: const Key('qa-batch-export'),
                      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                      icon: const Icon(Icons.ios_share, size: 17),
                      label: const Text('Xuất'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_ResultTab>(
              style: qaSegmentedStyle(context),
              segments: const [
                ButtonSegment(
                  value: _ResultTab.detail,
                  icon: Icon(Icons.list_alt, size: 17),
                  label: Text('Chi tiết'),
                ),
                ButtonSegment(
                  value: _ResultTab.compare,
                  icon: Icon(Icons.compare_arrows, size: 17),
                  label: Text('So sánh'),
                ),
                ButtonSegment(
                  value: _ResultTab.trend,
                  icon: Icon(Icons.insights, size: 17),
                  label: Text('Xu hướng'),
                ),
              ],
              selected: {tab},
              onSelectionChanged: (value) => onTab(value.first),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: switch (tab) {
              _ResultTab.detail => _RunDetails(controller: controller),
              _ResultTab.compare => _Comparison(
                controller: controller,
                batch: batch,
                compareWith: compareWith,
                onCompareWith: onCompareWith,
              ),
              _ResultTab.trend => _Trend(controller: controller),
            },
          ),
        ],
      ),
    );
  }
}

class _RunDetails extends StatelessWidget {
  const _RunDetails({required this.controller});

  final QaWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    if (controller.isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }
    final runs = controller.historyRuns;
    if (runs.isEmpty) {
      return const QaEmptyState(
        icon: Icons.hourglass_empty,
        title: 'Lượt này chưa lưu suite nào',
        message: 'Lượt bị dừng trước khi suite đầu tiên chạy xong.',
      );
    }
    return ListView.separated(
      itemCount: runs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final run = runs[index];
        return Container(
          key: Key('qa-history-run-${run.suiteId}'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.well,
            borderRadius: BorderRadius.circular(QaTokens.radius),
            border: Border.all(
              color: run.status == RunStatus.failed
                  ? tokens.status(RunStatus.failed).withValues(alpha: 0.5)
                  : tokens.line,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  QaStatusIcon(status: run.status),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: run.suiteName,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          TextSpan(
                            text: '  ${run.sourceName}',
                            style: TextStyle(color: tokens.muted),
                          ),
                        ],
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  QaStatusPill(status: run.status),
                  const SizedBox(width: 10),
                  Text(
                    shortDuration(run.duration),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.muted,
                      fontFeatures: QaTokens.tabular,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (run.detailsPath != null)
                    TextButton.icon(
                      key: Key('qa-open-steps-${run.suiteId}'),
                      onPressed: () => showAutomationSteps(
                        context,
                        title: '${run.sourceName} · ${run.suiteName}',
                        detailsPath: run.detailsPath!,
                        screenshotPath: run.screenshotPath,
                      ),
                      icon: const Icon(Icons.format_list_numbered, size: 17),
                      label: const Text('Các bước'),
                    ),
                  TextButton.icon(
                    key: Key('qa-open-log-${run.suiteId}'),
                    onPressed: run.logPath == null
                        ? null
                        : () => showRunDebug(context, controller, run),
                    icon: const Icon(Icons.bug_report_outlined, size: 17),
                    label: Text(
                      run.screenshotPath == null ? 'Xem log' : 'Xem log & ảnh',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              QaMetaLine(label: 'Lệnh', value: run.command),
              QaMetaLine(
                label: 'Git',
                value: run.gitCommit == null
                    ? 'không có thông tin'
                    : '${run.gitBranch ?? 'detached'} @ ${run.gitCommit}'
                          '${run.gitDirty ? ' · có thay đổi chưa commit' : ''}',
              ),
              QaMetaLine(
                label: 'Exit code',
                value: run.exitCode?.toString() ?? '--',
              ),
              if (run.environmentName != null)
                QaMetaLine(label: 'Môi trường', value: run.environmentName!),
              if (run.deviceId != null)
                QaMetaLine(
                  label: 'Thiết bị',
                  value: '${run.deviceName ?? 'không rõ'} (${run.deviceId})',
                ),
              if (run.appiumPort != null)
                QaMetaLine(label: 'Appium', value: 'cổng ${run.appiumPort}'),
              QaMetaLine(
                label: 'Log',
                value: run.logPath ?? 'không có',
                selectable: true,
              ),
              if (run.screenshotPath != null)
                QaMetaLine(
                  label: 'Ảnh chụp',
                  value: run.screenshotPath!,
                  selectable: true,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The saved log of one suite, beside its failure screenshot when there is
/// one.
Future<void> showRunDebug(
  BuildContext context,
  QaWorkspaceController controller,
  HistoricalSuiteRun run,
) {
  final log = controller.readHistoricalLog(run);
  final screenshot = run.screenshotPath == null
      ? null
      : File(run.screenshotPath!);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final tokens = QaTokens.of(dialogContext);
      final console = FutureBuilder<String>(
        future: log,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return NoticeBox(
              text: 'Không đọc được log: ${snapshot.error}',
              tone: NoticeTone.danger,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return QaLogConsole(
            title: run.logPath ?? 'Log',
            lines: snapshot.data!.split(RegExp(r'\r?\n')),
            expandable: false,
          );
        },
      );
      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 1200,
          height: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                QaPanelHeader(
                  title: '${run.sourceName} · ${run.suiteName}',
                  subtitle:
                      '${statusLabel(run.status)} · '
                      '${fullDateTime(run.startedAt)}',
                  trailing: [
                    IconButton(
                      tooltip: 'Đóng',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: screenshot != null && screenshot.existsSync()
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 300,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: tokens.well,
                                  borderRadius: BorderRadius.circular(
                                    QaTokens.radius,
                                  ),
                                ),
                                padding: const EdgeInsets.all(8),
                                child: Image.file(
                                  screenshot,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: console),
                          ],
                        )
                      : console,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _Comparison extends StatelessWidget {
  const _Comparison({
    required this.controller,
    required this.batch,
    required this.compareWith,
    required this.onCompareWith,
  });

  final QaWorkspaceController controller;
  final RunBatchSummary batch;
  final String? compareWith;
  final ValueChanged<String> onCompareWith;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final batches = controller.historyBatches;
    final index = batches.indexWhere((item) => item.id == batch.id);
    final others = [
      for (final item in batches)
        if (item.id != batch.id) item,
    ];
    if (others.isEmpty) {
      return const QaEmptyState(
        icon: Icons.compare_arrows,
        title: 'Chưa có lượt khác để so sánh',
        message: 'So sánh cần ít nhất hai lượt chạy.',
      );
    }
    // Default: the run just before this one, or the newest other one when
    // this is the oldest.
    final fallback = index >= 0 && index + 1 < batches.length
        ? batches[index + 1].id
        : others.first.id;
    final before = others.any((item) => item.id == compareWith)
        ? compareWith!
        : fallback;
    final comparisons = controller.compareBatches(before, batch.id);
    final changed = comparisons.where((item) => item.changed).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'So với lượt',
              style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
            ),
            const SizedBox(width: 10),
            DropdownButton<String>(
              key: const Key('qa-compare-with'),
              value: before,
              isDense: true,
              items: [
                for (final item in others)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(
                      '${fullDateTime(item.startedAt)} · '
                      '${item.passed}/${item.total} qua',
                      style: const TextStyle(fontFeatures: QaTokens.tabular),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onCompareWith(value);
              },
            ),
            const Spacer(),
            Text(
              changed == 0
                  ? 'Không suite nào đổi trạng thái'
                  : '$changed suite đổi trạng thái',
              style: theme.textTheme.bodySmall?.copyWith(
                color: changed == 0 ? tokens.muted : tokens.palette.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            itemCount: comparisons.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: tokens.line),
            itemBuilder: (context, index) {
              final item = comparisons[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: item.suiteName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text: '  ${item.sourceName}',
                              style: TextStyle(color: tokens.muted),
                            ),
                          ],
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    QaStatusPill(status: item.before),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward, size: 16),
                    ),
                    QaStatusPill(status: item.after),
                    SizedBox(
                      width: 30,
                      child: item.changed
                          ? Icon(
                              Icons.change_circle_outlined,
                              size: 18,
                              color: tokens.palette.warning,
                            )
                          : null,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({required this.controller});

  final QaWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final palette = tokens.palette;
    final snapshot = controller.reportSnapshot;
    final batches = controller.historyBatches.take(12).toList();

    Widget metric(String label, String value, Color color, IconData icon) =>
        Container(
          width: 160,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.well,
            borderRadius: BorderRadius.circular(QaTokens.radius),
            border: Border.all(color: tokens.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: tokens.muted,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFeatures: QaTokens.tabular,
                ),
              ),
            ],
          ),
        );

    return ListView(
      children: [
        Text(
          'Tính trên ${snapshot.totalRuns} suite run gần nhất của mọi lượt.',
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            metric(
              'Tỷ lệ qua',
              '${(snapshot.passRate * 100).toStringAsFixed(1).replaceAll('.', ',')}%',
              palette.success,
              Icons.verified_outlined,
            ),
            metric(
              'Qua',
              '${snapshot.passed}',
              palette.success,
              Icons.check_circle_outline,
            ),
            metric(
              'Lỗi',
              '${snapshot.failed}',
              palette.danger,
              Icons.error_outline,
            ),
            metric(
              'Thời gian TB',
              shortDuration(snapshot.averageDuration),
              palette.info,
              Icons.timer_outlined,
            ),
            metric(
              'Suite chập chờn',
              '${snapshot.flakySuites.length}',
              palette.warning,
              Icons.warning_amber,
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SectionLabel('Tỷ lệ qua theo lượt'),
        const SizedBox(height: 8),
        for (final batch in batches)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    shortDateTime(batch.startedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFeatures: QaTokens.tabular,
                    ),
                  ),
                ),
                Expanded(
                  child: LinearProgressIndicator(
                    value: batch.total == 0 ? 0 : batch.passed / batch.total,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(6),
                    backgroundColor: palette.dangerSoft,
                    color: palette.success,
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    batch.total == 0
                        ? '--'
                        : '${(batch.passed / batch.total * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: QaTokens.tabular,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        const SectionLabel('Suite chập chờn'),
        const SizedBox(height: 4),
        if (snapshot.flakySuites.isEmpty)
          Text(
            'Chưa có suite lúc qua lúc lỗi.',
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
          ),
        for (final item in snapshot.flakySuites)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.warning_amber, color: palette.warning),
            title: Text(item.suiteName),
            subtitle: Text(item.sourceName),
            trailing: Text(
              '${item.failed} lỗi / ${item.total} lượt',
              style: const TextStyle(fontFeatures: QaTokens.tabular),
            ),
          ),
        const SizedBox(height: 14),
        const SectionLabel('Chậm nhất'),
        const SizedBox(height: 4),
        for (final run in snapshot.slowestSuites.take(5))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.timer_outlined, color: tokens.muted),
            title: Text(run.suiteName),
            subtitle: Text(run.sourceName),
            trailing: Text(
              shortDuration(run.duration ?? Duration.zero),
              style: const TextStyle(fontFeatures: QaTokens.tabular),
            ),
          ),
      ],
    );
  }
}
