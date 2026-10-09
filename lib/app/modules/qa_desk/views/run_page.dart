import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../shared/module_widgets.dart';
import '../controllers/qa_workspace_controller.dart';
import '../models/preflight.dart';
import '../models/qa_models.dart';
import '../models/scenario_models.dart';
import '../services/account_vault.dart';
import '../services/appium_server_service.dart';
import '../services/qa_desk_host.dart';
import '../services/weak_network_proxy.dart';
import '../theme/qa_tokens.dart';
import '../widgets/add_source_button.dart';
import '../widgets/log_console.dart';
import '../widgets/qa_widgets.dart';
import '../widgets/suite_tree.dart';
import 'automation_dialogs.dart';
import 'devices_sheet.dart';
import 'issue_report_dialog.dart';
import 'network_sheet.dart';
import 'secrets_dialog.dart';
import 'vault_sheet.dart';

/// The batch whose result card the user closed; kept for the session so the
/// card does not come back every time the page is reopened.
String? _dismissedResultBatch;

/// Everything one run needs, on one screen: what to run, with which
/// environment, device and network, and what happened.
class QaRunPage extends StatefulWidget {
  const QaRunPage({
    super.key,
    required this.controller,
    required this.onOpenResults,
    required this.onOpenScenarios,
    this.host = const StandaloneQaDeskHost(),
    this.projectPath,
  });

  final QaWorkspaceController controller;
  final ValueChanged<String> onOpenResults;
  final ValueChanged<String> onOpenScenarios;
  final QaDeskHost host;

  /// The AMC project QA Desk was opened from; offered as a source when it is
  /// not one yet.
  final String? projectPath;

  @override
  State<QaRunPage> createState() => _QaRunPageState();
}

class _QaRunPageState extends State<QaRunPage> {
  static const _wideBreakpoint = 1050.0;

  String? _selectedRunId;
  int _narrowTab = 0;
  bool _suggestionDismissed = false;

  QaWorkspaceController get _controller => widget.controller;

  /// The project QA Desk was opened from, while it is not a source yet.
  String? get _suggestedProject {
    final path = widget.projectPath;
    if (path == null || _suggestionDismissed) return null;
    if (_controller.sources.any((source) => p.equals(source.path, path))) {
      return null;
    }
    return path;
  }

  void _enterSecrets(QaSource source, EnvironmentProfile environment) =>
      showSecretsDialog(
        context,
        controller: _controller,
        source: source,
        environment: environment,
      );

  void _enterSecretsFor(PreflightIssue issue) {
    final catalog = _controller.catalogFor(issue.sourceId ?? '');
    QaSource? source;
    for (final item in _controller.sources) {
      if (item.id == issue.sourceId) source = item;
    }
    if (catalog == null || source == null) return;
    for (final environment in catalog.environments) {
      if (environment.id == issue.environmentId) {
        _enterSecrets(source, environment);
      }
    }
  }

  void _dismissResult() {
    if (_controller.runs.isEmpty) return;
    setState(() => _dismissedResultBatch = _controller.runs.first.batchId);
  }

  Future<void> _run() async {
    if (!await confirmProductionRun(context, _controller)) return;
    if (!mounted) return;
    setState(() {
      _selectedRunId = null;
      _narrowTab = 1;
    });
    await _controller.runSelected();
  }

  void _openVault() => showVaultSheet(context, _controller);

  Future<void> _rerunFailed(String batchId) async {
    setState(() => _selectedRunId = null);
    final message = await _controller.rerunFailures(batchId);
    if (message != null && mounted) showQaMessage(context, message);
  }

  /// The run the log shows: the one picked, else the one running, else the
  /// first failure, else the first.
  SuiteRun? _shownRun(List<SuiteRun> runs) {
    if (runs.isEmpty) return null;
    for (final run in runs) {
      if (run.runId == _selectedRunId) return run;
    }
    for (final status in const [RunStatus.running, RunStatus.failed]) {
      for (final run in runs) {
        if (run.status == status) return run;
      }
    }
    return runs.first;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // The host fires when a release starts or stops, which changes whether
      // the run warns about sharing the project with it.
      listenable: Listenable.merge([_controller, widget.host.changes]),
      builder: (context, _) {
        if (_controller.sources.isEmpty) {
          return _Onboarding(controller: _controller, host: widget.host);
        }
        final suggested = _suggestedProject;
        final tree = QaSuiteTree(
          controller: _controller,
          addSourceButton: QaAddSourceButton(
            controller: _controller,
            host: widget.host,
          ),
          onOpenScenarios: widget.onOpenScenarios,
          onEnterSecrets: _enterSecrets,
          onSelectionChanged: _dismissResult,
        );
        final runs = _RunsColumn(
          controller: _controller,
          shownRun: _shownRun(_controller.runs),
          onSelectRun: (id) => setState(() => _selectedRunId = id),
          onOpenDevices: () => showDevicesSheet(context, _controller),
          onOpenNetwork: () => showNetworkSheet(context, _controller),
          onOpenVault: _openVault,
          onDismissResult: _dismissResult,
          onRerunFailed: _rerunFailed,
          onOpenResults: widget.onOpenResults,
        );
        final actionBar = _RunActionBar(
          controller: _controller,
          onRun: _run,
          onOpenDevices: () => showDevicesSheet(context, _controller),
          onOpenVault: _openVault,
          onEnterSecrets: _enterSecretsFor,
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= _wideBreakpoint;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (suggested != null) ...[
                    _ProjectSuggestion(
                      path: suggested,
                      onAdd: () => addQaSource(context, _controller, suggested),
                      onDismiss: () =>
                          setState(() => _suggestionDismissed = true),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (wide)
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: (constraints.maxWidth * 0.36).clamp(
                              340.0,
                              460.0,
                            ),
                            child: tree,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: runs),
                        ],
                      ),
                    )
                  else ...[
                    SegmentedButton<int>(
                      style: qaSegmentedStyle(context),
                      segments: [
                        const ButtonSegment(
                          value: 0,
                          icon: Icon(Icons.checklist, size: 17),
                          label: Text('Chọn suite'),
                        ),
                        ButtonSegment(
                          value: 1,
                          icon: const Icon(Icons.terminal, size: 17),
                          label: Text(
                            _controller.runs.isEmpty
                                ? 'Lượt chạy'
                                : 'Lượt chạy (${_controller.runs.length})',
                          ),
                        ),
                      ],
                      selected: {_narrowTab},
                      onSelectionChanged: (value) =>
                          setState(() => _narrowTab = value.first),
                    ),
                    const SizedBox(height: 10),
                    Expanded(child: _narrowTab == 0 ? tree : runs),
                  ],
                  const SizedBox(height: 12),
                  actionBar,
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Offers the AMC project QA Desk was opened from as a source.
class _ProjectSuggestion extends StatelessWidget {
  const _ProjectSuggestion({
    required this.path,
    required this.onAdd,
    required this.onDismiss,
  });

  final String path;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    return Container(
      key: const Key('qa-project-suggestion'),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: tokens.palette.infoSoft,
        borderRadius: BorderRadius.circular(QaTokens.radius),
        border: Border.all(color: tokens.palette.infoBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_special_outlined, color: tokens.palette.info),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: p.basename(path),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const TextSpan(
                    text: ' đang mở trong AMC nhưng chưa là nguồn của QA Desk.',
                  ),
                ],
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
          FilledButton.tonalIcon(
            key: const Key('qa-add-suggested'),
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 17),
            label: const Text('Thêm dự án này'),
          ),
          IconButton(
            tooltip: 'Bỏ qua',
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

/// The first screen of an empty workspace: the three steps, the first one as
/// a button, and AMC's own projects ready to add.
class _Onboarding extends StatelessWidget {
  const _Onboarding({required this.controller, required this.host});

  final QaWorkspaceController controller;
  final QaDeskHost host;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    Widget step(int number, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: tokens.selectedFill,
            child: Text(
              '$number',
              style: theme.textTheme.labelMedium?.copyWith(
                color: tokens.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ModuleCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.science_outlined, size: 36, color: tokens.accent),
                const SizedBox(height: 10),
                Text(
                  'Chạy test của nhiều dự án ở một chỗ',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                step(
                  1,
                  'Thêm nguồn',
                  'Chọn thư mục dự án Flutter, Node/Web hoặc Playwright đã cài '
                      'dependency. Suite lấy từ .fiza-qa/project.yaml, hoặc '
                      'được đoán sẵn nếu chưa có file đó.',
                ),
                step(
                  2,
                  'Chọn suite',
                  'Tick suite cần chạy, chọn môi trường ngay trên dòng nguồn; '
                      'thiết bị và mạng yếu nằm trên thanh phía trên lượt chạy.',
                ),
                step(
                  3,
                  'Chạy và đọc kết quả',
                  'Log chạy trực tiếp. Xong là có thẻ kết quả, báo cáo issue để '
                      'copy thành task, và lịch sử trong Kết quả.',
                ),
                const SizedBox(height: 6),
                QaAddSourceButton(
                  controller: controller,
                  host: host,
                  prominent: true,
                ),
                for (final path in qaSourceCandidates(
                  controller,
                  host,
                  limit: 4,
                )) ...[
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    key: ValueKey('qa-quick-add:$path'),
                    onPressed: () => addQaSource(context, controller, path),
                    icon: const Icon(Icons.add, size: 17),
                    label: Text(
                      'Thêm ${p.basename(path)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The right-hand column: run context, the result of the last run, and the
/// runs with their log.
class _RunsColumn extends StatelessWidget {
  const _RunsColumn({
    required this.controller,
    required this.shownRun,
    required this.onSelectRun,
    required this.onOpenDevices,
    required this.onOpenNetwork,
    required this.onOpenVault,
    required this.onDismissResult,
    required this.onRerunFailed,
    required this.onOpenResults,
  });

  final QaWorkspaceController controller;
  final SuiteRun? shownRun;
  final ValueChanged<String> onSelectRun;
  final VoidCallback onOpenDevices;
  final VoidCallback onOpenNetwork;
  final VoidCallback onOpenVault;
  final VoidCallback onDismissResult;
  final ValueChanged<String> onRerunFailed;
  final ValueChanged<String> onOpenResults;

  @override
  Widget build(BuildContext context) {
    final runs = controller.runs;
    final showResult =
        !controller.isRunning &&
        runs.isNotEmpty &&
        runs.first.batchId != _dismissedResultBatch;
    final run = shownRun;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RunConfigBar(
          controller: controller,
          onOpenDevices: onOpenDevices,
          onOpenNetwork: onOpenNetwork,
          onOpenVault: onOpenVault,
        ),
        if (showResult) ...[
          const SizedBox(height: 10),
          _ResultCard(
            controller: controller,
            onDismiss: onDismissResult,
            onRerunFailed: onRerunFailed,
            onOpenResults: onOpenResults,
          ),
        ],
        const SizedBox(height: 10),
        Expanded(
          child: ModuleCard(
            padding: const EdgeInsets.all(12),
            child: runs.isEmpty
                ? const QaEmptyState(
                    icon: Icons.terminal_outlined,
                    title: 'Chưa có lượt chạy',
                    message:
                        'Tick suite hoặc kịch bản tự thao tác ở cây bên trái '
                        'rồi bấm Chạy. Log của từng mục hiện ở đây trong lúc '
                        'chạy.',
                  )
                : QaVerticalSplit(
                    top: _RunList(
                      controller: controller,
                      shownRunId: run?.runId,
                      onSelectRun: onSelectRun,
                    ),
                    bottom: QaLogConsole(
                      key: ValueKey(run?.runId),
                      title: run == null
                          ? 'Log'
                          : '${run.sourceName} · ${run.suiteName}',
                      lines: run?.logs ?? const [],
                      liveUpdates: controller,
                      emptyMessage: 'Suite chưa bắt đầu.',
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// What the run will use besides the suites: device, network, Appium, and
/// for automated scenarios the app environment and demo accounts. Each chip
/// opens what changes it.
class _RunConfigBar extends StatelessWidget {
  const _RunConfigBar({
    required this.controller,
    required this.onOpenDevices,
    required this.onOpenNetwork,
    required this.onOpenVault,
  });

  final QaWorkspaceController controller;
  final VoidCallback onOpenDevices;
  final VoidCallback onOpenNetwork;
  final VoidCallback onOpenVault;

  @override
  Widget build(BuildContext context) {
    final tokens = QaTokens.of(context);
    final palette = tokens.palette;
    final selected = [
      for (final source in controller.sources)
        for (final suite in source.suites)
          if (controller.isSuiteSelected(source, suite)) suite,
    ];
    final automated = controller.selectedAutomationCount > 0;
    final needsDevice =
        automated ||
        selected.any(
          (suite) => suite.requiresDevice || suite.requiresPhysicalDevice,
        );
    final needsAppium = selected.any((suite) => suite.requiresAppium);
    final kinds = {for (final issue in controller.preflight()) issue.kind};
    final device = controller.selectedDevice;
    final deviceProblem =
        kinds.contains(PreflightKind.deviceMissing) ||
        kinds.contains(PreflightKind.physicalDeviceRequired);
    final network = controller.network;
    final appium = controller.appiumStatus;
    final showAppium =
        needsAppium ||
        appium == AppiumStatus.running ||
        appium == AppiumStatus.starting ||
        appium == AppiumStatus.error;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ConfigChip(
          key: const Key('qa-device-chip'),
          icon: device == null || device.isEmulator
              ? Icons.phone_android
              : Icons.smartphone,
          label: 'Thiết bị',
          value: device == null
              ? 'chưa chọn'
              : '${device.name} · ${device.isEmulator ? 'máy ảo' : 'máy thật'}',
          tone: deviceProblem
              ? palette.danger
              : needsDevice
              ? palette.success
              : null,
          tooltip: needsDevice
              ? 'Suite đang chọn chạy trên thiết bị này.'
              : 'Chưa suite nào đang chọn cần thiết bị.',
          onTap: onOpenDevices,
        ),
        _ConfigChip(
          key: const Key('qa-network-chip'),
          icon: network.enabled ? Icons.network_check : Icons.wifi,
          label: 'Mạng',
          value: network.enabled
              ? '${network.profile.name} · '
                    '${kilobytes(network.profile.bytesPerSecond)} KB/s'
              : 'bình thường',
          tone: network.enabled ? palette.warning : null,
          tooltip: network.enabled
              ? 'Đang giả lập mạng yếu cho suite đi qua proxy.'
              : 'Giả lập mạng yếu qua proxy cục bộ.',
          onTap: onOpenNetwork,
        ),
        if (automated || controller.appEnvironments.isNotEmpty) ...[
          _AppEnvironmentChip(controller: controller, active: automated),
          _AccountsChip(
            controller: controller,
            active: automated,
            onTap: onOpenVault,
          ),
        ],
        if (showAppium)
          _ConfigChip(
            key: const Key('qa-appium-chip'),
            icon: Icons.hub_outlined,
            label: 'Appium',
            value: switch (appium) {
              AppiumStatus.unavailable => 'không có',
              AppiumStatus.stopped => 'tắt · tự bật khi chạy',
              AppiumStatus.starting => 'đang bật',
              AppiumStatus.running => 'cổng ${controller.appiumPort}',
              AppiumStatus.error => 'lỗi',
            },
            tone: switch (appium) {
              AppiumStatus.unavailable || AppiumStatus.error =>
                needsAppium ? palette.danger : palette.warning,
              AppiumStatus.running => palette.success,
              _ => null,
            },
            onTap: onOpenDevices,
          ),
      ],
    );
  }
}

/// The environment automated scenarios log in to, picked for the whole run.
class _AppEnvironmentChip extends StatelessWidget {
  const _AppEnvironmentChip({required this.controller, required this.active});

  final QaWorkspaceController controller;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = QaTokens.of(context).palette;
    final current = controller.appEnvironment;
    final production = controller.isProductionEnvironment(current);
    final names = controller.appEnvironments;
    return MenuAnchor(
      menuChildren: [
        for (final name in names)
          MenuItemButton(
            key: Key('qa-app-env-$name'),
            leadingIcon: Icon(
              name == current ? Icons.check : Icons.circle_outlined,
              size: 16,
            ),
            onPressed: controller.isRunning
                ? null
                : () => controller.selectAppEnvironment(name),
            child: Text(
              controller.isProductionEnvironment(name)
                  ? '$name · production'
                  : name,
            ),
          ),
      ],
      builder: (context, menu, _) => _ConfigChip(
        key: const Key('qa-app-env-chip'),
        icon: production ? Icons.warning_amber_rounded : Icons.cloud_outlined,
        label: 'Môi trường app',
        value: production ? '$current · production' : current,
        tone: production
            ? palette.danger
            : active
            ? palette.success
            : null,
        tooltip: production
            ? 'Kịch bản tự thao tác sẽ chạy trên dữ liệu thật: chỉ kịch bản '
                  'chỉ đọc được chạy.'
            : 'Môi trường kịch bản tự thao tác đăng nhập vào.',
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}

/// Whether the demo accounts and Maestro are ready to log in with.
class _AccountsChip extends StatelessWidget {
  const _AccountsChip({
    required this.controller,
    required this.active,
    required this.onTap,
  });

  final QaWorkspaceController controller;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = QaTokens.of(context).palette;
    final runner = controller.automation;
    final vault = runner?.vault;
    final maestroMissing = runner?.status?.ready == false;
    final (value, ready) = switch (vault?.state) {
      null => ('chưa dùng được', false),
      _ when maestroMissing => ('cần cài Maestro', false),
      VaultState.loading => ('đang mở kho', false),
      VaultState.needsSetup => ('chưa có kho', false),
      VaultState.locked => ('kho đang khoá', false),
      VaultState.failed => ('lỗi kho', false),
      VaultState.ready => ('${vault!.accounts.length} tài khoản', true),
    };
    return _ConfigChip(
      key: const Key('qa-accounts-chip'),
      icon: Icons.badge_outlined,
      label: 'Tài khoản demo',
      value: value,
      tone: ready
          ? (active ? palette.success : null)
          : (active ? palette.danger : palette.warning),
      tooltip: 'Kho tài khoản demo và Maestro.',
      onTap: onTap,
    );
  }
}

class _ConfigChip extends StatelessWidget {
  const _ConfigChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.tone,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Color? tone;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final tint = tone ?? tokens.muted;
    final chip = Material(
      color: tint.withValues(alpha: tone == null ? 0.06 : 0.12),
      shape: StadiumBorder(
        side: BorderSide(color: tint.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: tone ?? tokens.muted),
              const SizedBox(width: 7),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$label: ',
                      style: TextStyle(color: tokens.muted),
                    ),
                    TextSpan(
                      text: value,
                      style: TextStyle(
                        color: tone ?? tokens.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more, size: 16, color: tokens.muted),
            ],
          ),
        ),
      ),
    );
    final message = tooltip;
    return message == null ? chip : Tooltip(message: message, child: chip);
  }
}

/// The outcome of the run that just finished, with what to do next. It does
/// not block anything, and goes away once the selection changes.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.controller,
    required this.onDismiss,
    required this.onRerunFailed,
    required this.onOpenResults,
  });

  final QaWorkspaceController controller;
  final VoidCallback onDismiss;
  final ValueChanged<String> onRerunFailed;
  final ValueChanged<String> onOpenResults;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final runs = controller.runs;
    final batchId = runs.first.batchId;
    int count(RunStatus status) =>
        runs.where((run) => run.status == status).length;
    final passed = count(RunStatus.passed);
    final failed = count(RunStatus.failed);
    final cancelled = count(RunStatus.cancelled);
    final overall = failed > 0
        ? RunStatus.failed
        : cancelled > 0
        ? RunStatus.cancelled
        : RunStatus.passed;
    DateTime? start;
    DateTime? end;
    for (final run in runs) {
      final started = run.startedAt;
      final finished = run.finishedAt;
      if (started != null && (start == null || started.isBefore(start))) {
        start = started;
      }
      if (finished != null && (end == null || finished.isAfter(end))) {
        end = finished;
      }
    }
    final duration = start == null || end == null
        ? null
        : end.difference(start);
    final title = switch (overall) {
      RunStatus.failed => 'Có $failed suite lỗi',
      RunStatus.cancelled => 'Lượt chạy đã dừng giữa chừng',
      _ => 'Tất cả suite đều qua',
    };
    final summary = [
      '${runs.length} suite',
      '$passed qua',
      if (failed > 0) '$failed lỗi',
      if (cancelled > 0) '$cancelled đã dừng',
      if (duration != null) longDuration(duration),
    ].join(' · ');

    return Container(
      key: const Key('qa-result-card'),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: tokens.status(overall).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(QaTokens.radius),
        border: Border.all(
          color: tokens.status(overall).withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          QaStatusIcon(status: overall, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      summary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.muted,
                        fontFeatures: QaTokens.tabular,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilledButton.tonalIcon(
                      key: const Key('qa-result-report'),
                      onPressed: () => showIssueReport(
                        context,
                        controller.currentIssueReport(),
                      ),
                      icon: const Icon(Icons.assignment_outlined, size: 17),
                      label: const Text('Báo cáo issue'),
                    ),
                    if (failed > 0)
                      OutlinedButton.icon(
                        key: const Key('qa-result-rerun'),
                        onPressed: () => onRerunFailed(batchId),
                        icon: const Icon(Icons.replay, size: 17),
                        label: const Text('Chạy lại suite lỗi'),
                      ),
                    TextButton(
                      key: const Key('qa-result-open'),
                      onPressed: () => onOpenResults(batchId),
                      child: const Text('Mở trong Kết quả'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Đóng',
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _RunList extends StatelessWidget {
  const _RunList({
    required this.controller,
    required this.shownRunId,
    required this.onSelectRun,
  });

  final QaWorkspaceController controller;
  final String? shownRunId;
  final ValueChanged<String> onSelectRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final runs = controller.runs;
    final done = runs
        .where(
          (run) =>
              run.status != RunStatus.queued && run.status != RunStatus.running,
        )
        .length;
    final failed = runs.where((run) => run.status == RunStatus.failed).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QaPanelHeader(
          title: 'Lượt chạy',
          subtitle: [
            '$done/${runs.length} xong',
            if (failed > 0) '$failed lỗi',
          ].join(' · '),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: runs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final run = runs[index];
              return QaSelectableRow(
                key: Key('qa-run-${run.suiteId}'),
                selected: run.runId == shownRunId,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                onTap: () => onSelectRun(run.runId),
                child: Row(
                  children: [
                    if (run.status == RunStatus.running)
                      SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tokens.status(RunStatus.running),
                        ),
                      )
                    else
                      QaStatusIcon(status: run.status, size: 17),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: run.suiteName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text: '  ${run.sourceName}',
                              style: TextStyle(color: tokens.muted),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      run.status == RunStatus.queued
                          ? 'chờ'
                          : shortDuration(run.duration),
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
    );
  }
}

/// The summary of the selection, what blocks it, and the button. Always at
/// the bottom of the page, so starting or stopping is never a scroll away.
class _RunActionBar extends StatelessWidget {
  const _RunActionBar({
    required this.controller,
    required this.onRun,
    required this.onOpenDevices,
    required this.onOpenVault,
    required this.onEnterSecrets,
  });

  final QaWorkspaceController controller;
  final VoidCallback onRun;
  final VoidCallback onOpenDevices;
  final VoidCallback onOpenVault;
  final ValueChanged<PreflightIssue> onEnterSecrets;

  String _summary() {
    final sources = controller.sources
        .where(
          (source) =>
              source.suites.any(
                (suite) => controller.isSuiteSelected(source, suite),
              ) ||
              controller
                  .automatedScenarios(source)
                  .any(
                    (scenario) =>
                        scenario.enabled &&
                        controller.isAutomationSelected(source, scenario),
                  ),
        )
        .toList();
    final automated = controller.selectedAutomationCount;
    final environments = <String>{};
    for (final source in sources) {
      final id = controller.selectedEnvironmentId(source.id);
      for (final item
          in controller.catalogFor(source.id)?.environments ??
              const <EnvironmentProfile>[]) {
        if (item.id == id) environments.add(item.name);
      }
    }
    final network = controller.network;
    return [
      '${sources.length} nguồn',
      if (controller.selectedSuiteCount > 0)
        '${controller.selectedSuiteCount} suite',
      if (automated > 0) '$automated tự thao tác',
      if (environments.isNotEmpty) 'môi trường ${environments.join(', ')}',
      if (automated > 0) 'app ${controller.appEnvironment}',
      network.enabled ? 'mạng ${network.profile.name}' : 'mạng bình thường',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final palette = tokens.palette;
    final running = controller.isRunning;
    final issues = controller.preflight();
    final blocking = issues.where((issue) => issue.blocking).toList();
    final nothingSelected = issues.any(
      (issue) => issue.kind == PreflightKind.noSuites,
    );
    final runs = controller.runs;
    final done = runs
        .where(
          (run) =>
              run.status != RunStatus.queued && run.status != RunStatus.running,
        )
        .length;
    final failed = runs.where((run) => run.status == RunStatus.failed).length;

    Widget issueLine(PreflightIssue issue) {
      final color = issue.blocking ? palette.danger : palette.warning;
      final action = switch (issue.kind) {
        PreflightKind.deviceMissing ||
        PreflightKind.physicalDeviceRequired => TextButton(
          onPressed: onOpenDevices,
          child: const Text('Chọn thiết bị'),
        ),
        PreflightKind.appiumMissing => TextButton(
          onPressed: onOpenDevices,
          child: const Text('Xem Appium'),
        ),
        PreflightKind.secretsMissing => TextButton(
          onPressed: () => onEnterSecrets(issue),
          child: const Text('Nhập secret'),
        ),
        PreflightKind.automationSetup ||
        PreflightKind.vaultNotReady ||
        PreflightKind.accountMissing => TextButton(
          onPressed: onOpenVault,
          child: const Text('Mở kho tài khoản'),
        ),
        _ => null,
      };
      return Padding(
        key: Key('qa-preflight-${issue.kind.name}'),
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Icon(
              issue.blocking ? Icons.error_outline : Icons.warning_amber,
              size: 15,
              color: color,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                issue.message,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
            ?action,
          ],
        ),
      );
    }

    return ModuleCard(
      key: const Key('qa-action-bar'),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (running) ...[
                  Text(
                    'Đang chạy $done/${runs.length}'
                    '${failed > 0 ? ' · $failed lỗi' : ''}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: QaTokens.tabular,
                    ),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: runs.isEmpty ? null : done / runs.length,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ] else if (nothingSelected)
                  Text(
                    'Chưa chọn gì. Tick suite hoặc kịch bản ở cây bên trái.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.muted,
                    ),
                  )
                else ...[
                  Text(
                    _summary(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  for (final issue in issues) issueLine(issue),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (running)
            FilledButton.tonalIcon(
              key: const Key('qa-stop-button'),
              onPressed: controller.cancelAll,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Dừng'),
            )
          else
            FilledButton.icon(
              key: const Key('qa-run-button'),
              onPressed: blocking.isEmpty ? onRun : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(switch ((
                controller.selectedSuiteCount,
                controller.selectedAutomationCount,
              )) {
                _ when nothingSelected => 'Chạy',
                (final suites, 0) => 'Chạy $suites suite',
                (0, final automated) => 'Chạy $automated kịch bản',
                (final suites, final automated) =>
                  'Chạy ${suites + automated} mục',
              }),
            ),
        ],
      ),
    );
  }
}
