import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/module_widgets.dart';
import '../controllers/qa_workspace_controller.dart';
import '../models/qa_models.dart';
import '../services/qa_desk_host.dart';
import '../services/qa_desk_runtime.dart';
import '../services/qa_desk_storage.dart';
import '../theme/qa_tokens.dart';
import '../widgets/qa_widgets.dart';
import 'automation_dialogs.dart';
import 'help_sheet.dart';
import 'issue_report_dialog.dart';
import 'results_page.dart';
import 'run_page.dart';
import 'scenarios_page.dart';
import 'vault_sheet.dart';

enum QaSection { run, scenarios, results }

/// What to do once QA Desk is open, for the shell's commands that go
/// straight to a task.
enum QaDeskIntent {
  /// Just open it.
  open,

  /// Run the saved selection, unless something blocks it.
  run,

  /// Re-run the failed suites of the latest run.
  rerunFailed,

  /// Show the issue report of the latest run.
  lastReport,
}

/// The section shown last, so reopening QA Desk lands where the user left.
QaSection _rememberedSection = QaSection.run;

/// Opens QA Desk as a full page over the shell.
///
/// [projectPath] is the AMC project it is opened from, offered as a source
/// when it is not one yet.
Future<void> showQaDesk(
  BuildContext context, {
  String? projectPath,
  QaDeskIntent intent = QaDeskIntent.open,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => QaDeskPage(projectPath: projectPath, intent: intent),
  ),
);

/// Opens the app-wide QA runtime, then shows the workspace on it.
class QaDeskPage extends StatefulWidget {
  const QaDeskPage({
    super.key,
    this.projectPath,
    this.intent = QaDeskIntent.open,
  });

  final String? projectPath;
  final QaDeskIntent intent;

  @override
  State<QaDeskPage> createState() => _QaDeskPageState();
}

class _QaDeskPageState extends State<QaDeskPage> {
  late Future<QaDeskRuntime> _runtime = QaDeskRuntime.open();

  @override
  void dispose() {
    // Whatever finished while the page was open has been seen; the shell's
    // chip only keeps a result the user has not looked at.
    QaDeskRuntime.current?.acknowledgeResult();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QaDeskRuntime>(
      future: _runtime,
      builder: (context, snapshot) {
        final runtime = snapshot.data;
        if (runtime != null) {
          return QaDeskView(
            controller: runtime.controller,
            importNotice: runtime.takeImportNotice(),
            projectPath: widget.projectPath,
            intent: widget.intent,
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('QA Desk · Kiểm thử')),
          body: snapshot.hasError
              ? QaEmptyState(
                  icon: Icons.error_outline,
                  title: 'Không mở được QA Desk',
                  message: '${snapshot.error}',
                  action: FilledButton.icon(
                    onPressed: () =>
                        setState(() => _runtime = QaDeskRuntime.open()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

/// QA Desk's three sections under one header that always shows whether a run
/// is going and how it is doing.
class QaDeskView extends StatefulWidget {
  const QaDeskView({
    super.key,
    required this.controller,
    this.importNotice,
    this.initialSection,
    this.projectPath,
    this.intent = QaDeskIntent.open,
    this.host,
  });

  final QaWorkspaceController controller;

  /// What happened to the standalone app's data, announced once.
  final QaDeskImportResult? importNotice;
  final QaSection? initialSection;
  final String? projectPath;
  final QaDeskIntent intent;

  /// Defaults to the one AMC registered on [QaDeskRuntime.host].
  final QaDeskHost? host;

  @override
  State<QaDeskView> createState() => _QaDeskViewState();
}

class _QaDeskViewState extends State<QaDeskView> {
  late QaSection _section = widget.initialSection ?? _rememberedSection;
  late QaDeskImportResult? _notice = widget.importNotice;
  String? _scenarioSourceId;
  late bool _wasRunning = widget.controller.isRunning;

  QaWorkspaceController get _controller => widget.controller;

  QaDeskHost get _host => widget.host ?? QaDeskRuntime.host;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    if (widget.intent != QaDeskIntent.open) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_carryOut(widget.intent)),
      );
    }
  }

  /// Does what the shell's command asked for, or says why it cannot.
  Future<void> _carryOut(QaDeskIntent intent) async {
    if (!mounted) return;
    final controller = _controller;
    final latest = controller.historyBatches.firstOrNull;
    String? message;
    switch (intent) {
      case QaDeskIntent.open:
        return;
      case QaDeskIntent.run:
        _show(QaSection.run);
        final blocking = controller
            .preflight()
            .where((issue) => issue.blocking)
            .toList();
        if (controller.isRunning) {
          message = 'Đang có lượt chạy.';
        } else if (blocking.isNotEmpty) {
          message = 'Chưa chạy được: ${blocking.first.message}';
        } else if (await confirmProductionRun(context, controller)) {
          unawaited(controller.runSelected());
        }
      case QaDeskIntent.rerunFailed:
        _show(QaSection.run);
        if (latest == null) {
          message = 'Chưa có lượt chạy nào.';
        } else if (controller.isRunning) {
          message = 'Đang có lượt chạy.';
        } else if (latest.failed == 0) {
          message = 'Lượt gần nhất không có suite lỗi.';
        } else {
          message = await controller.rerunFailures(latest.id);
        }
      case QaDeskIntent.lastReport:
        if (latest == null) {
          message = 'Chưa có lượt chạy nào.';
        } else {
          _openResults(latest.id);
          unawaited(
            showIssueReport(context, controller.batchIssueReport(latest.id)),
          );
        }
    }
    if (message != null && mounted) showQaMessage(context, message);
  }

  @override
  void didUpdateWidget(covariant QaDeskView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _wasRunning = widget.controller.isRunning;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// A run that finishes while another section is open is announced there,
  /// with the way back; on the run page the result card says it already.
  void _onControllerChanged() {
    final finished = _wasRunning && !_controller.isRunning;
    _wasRunning = _controller.isRunning;
    if (!finished || _controller.runs.isEmpty || !mounted) return;
    if (_section == QaSection.run) return;
    final runs = _controller.runs;
    final failed = runs.where((run) => run.status == RunStatus.failed).length;
    final passed = runs.where((run) => run.status == RunStatus.passed).length;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Lượt chạy xong: $passed qua'
            '${failed > 0 ? ' · $failed lỗi' : ''}.',
          ),
          action: SnackBarAction(
            label: 'Xem',
            onPressed: () => _show(QaSection.run),
          ),
        ),
      );
  }

  void _show(QaSection section) {
    if (!mounted) return;
    setState(() => _section = _rememberedSection = section);
  }

  void _openResults(String batchId) {
    _controller.selectHistoryBatch(batchId);
    _show(QaSection.results);
  }

  void _openScenarios(String sourceId) {
    setState(() => _scenarioSourceId = sourceId);
    _show(QaSection.scenarios);
  }

  @override
  Widget build(BuildContext context) {
    final notice = _notice;
    return Scaffold(
      appBar: AppBar(
        title: const Text('QA Desk · Kiểm thử'),
        actions: [
          _RunStatusChip(
            controller: _controller,
            onTap: () => _show(QaSection.run),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const Key('qa-open-vault'),
            tooltip: 'Tài khoản demo',
            onPressed: () => showVaultSheet(context, _controller),
            icon: const Icon(Icons.badge_outlined),
          ),
          IconButton(
            key: const Key('qa-help'),
            tooltip: 'Hướng dẫn',
            onPressed: () => showQaHelp(context),
            icon: const Icon(Icons.help_outline),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<QaSection>(
                key: const Key('qa-sections'),
                style: qaSegmentedStyle(context),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: QaSection.run,
                    icon: Icon(Icons.play_circle_outline, size: 18),
                    label: Text('Chạy test', key: Key('qa-section-run')),
                  ),
                  ButtonSegment(
                    value: QaSection.scenarios,
                    icon: Icon(Icons.account_tree_outlined, size: 18),
                    label: Text('Kịch bản', key: Key('qa-section-scenarios')),
                  ),
                  ButtonSegment(
                    value: QaSection.results,
                    icon: Icon(Icons.insights_outlined, size: 18),
                    label: Text('Kết quả', key: Key('qa-section-results')),
                  ),
                ],
                selected: {_section},
                onSelectionChanged: (value) => _show(value.first),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notice != null)
            _ImportNotice(
              result: notice,
              onClose: () => setState(() => _notice = null),
            ),
          Expanded(
            child: switch (_section) {
              QaSection.run => QaRunPage(
                controller: _controller,
                host: _host,
                projectPath: widget.projectPath,
                onOpenResults: _openResults,
                onOpenScenarios: _openScenarios,
              ),
              QaSection.scenarios => QaScenariosPage(
                controller: _controller,
                initialSourceId: _scenarioSourceId,
                onRunStarted: () => _show(QaSection.run),
              ),
              QaSection.results => QaResultsPage(
                controller: _controller,
                onRunStarted: () => _show(QaSection.run),
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// Whether a run is going and how it is doing, from any section.
class _RunStatusChip extends StatelessWidget {
  const _RunStatusChip({required this.controller, required this.onTap});

  final QaWorkspaceController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tokens = QaTokens.of(context);
        final runs = controller.runs;
        if (runs.isEmpty) return const SizedBox.shrink();
        final failed = runs
            .where((run) => run.status == RunStatus.failed)
            .length;
        final passed = runs
            .where((run) => run.status == RunStatus.passed)
            .length;
        final done = runs
            .where(
              (run) =>
                  run.status != RunStatus.queued &&
                  run.status != RunStatus.running,
            )
            .length;
        final running = controller.isRunning;
        final status = running
            ? RunStatus.running
            : failed > 0
            ? RunStatus.failed
            : done < runs.length || passed < runs.length
            ? RunStatus.cancelled
            : RunStatus.passed;
        final color = tokens.status(status);
        final label = running
            ? 'Đang chạy $done/${runs.length}'
                  '${failed > 0 ? ' · $failed lỗi' : ''}'
            : 'Lượt vừa xong: $passed/${runs.length} qua';

        return Tooltip(
          message: 'Về Chạy test',
          child: Material(
            key: const Key('qa-run-status'),
            color: color.withValues(alpha: 0.12),
            shape: StadiumBorder(
              side: BorderSide(color: color.withValues(alpha: 0.45)),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (running)
                      SizedBox.square(
                        dimension: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    else
                      QaStatusIcon(status: status, size: 15),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontFeatures: QaTokens.tabular,
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
  }
}

/// Says once what happened to the standalone app's data.
class _ImportNotice extends StatelessWidget {
  const _ImportNotice({required this.result, required this.onClose});

  final QaDeskImportResult result;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final failed = result.outcome == QaDeskImportOutcome.failed;
    return Padding(
      key: const Key('qa-desk-import-notice'),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: NoticeBox(
              tone: failed ? NoticeTone.danger : NoticeTone.info,
              icon: failed ? null : Icons.move_down_outlined,
              text: failed
                  ? 'Không chuyển được dữ liệu từ Fiza QA Desk: ${result.error}. '
                        'Dữ liệu cũ vẫn nguyên ở ${result.legacyPath}; QA Desk '
                        'bắt đầu với danh sách trống.'
                  : 'Đã chuyển dữ liệu từ Fiza QA Desk (${result.copiedFiles} '
                        'file). Từ giờ dùng QA Desk trong AMC: app cũ vẫn ghi '
                        'vào thư mục cũ, nên lượt chạy ở đó sẽ không hiện ở đây.',
            ),
          ),
          IconButton(
            tooltip: 'Đóng',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
