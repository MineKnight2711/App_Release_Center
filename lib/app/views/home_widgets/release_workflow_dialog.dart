part of '../home_view.dart';

bool _releaseWorkflowDialogVisible = false;

enum _ReleaseLogView { step, all }

Future<void> showReleaseWorkflowDialog(BuildContext context) async {
  if (_releaseWorkflowDialogVisible) return;
  _releaseWorkflowDialogVisible = true;
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Release workflow monitor',
      barrierColor: Colors.black.withValues(alpha: 0.66),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => const _ReleaseWorkflowDialog(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final reduceMotion =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  } finally {
    _releaseWorkflowDialogVisible = false;
  }
}

class _ReleaseWorkflowButton extends GetView<HomeController> {
  const _ReleaseWorkflowButton();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final workflow = controller.releaseWorkflow;
      final hasRun = workflow.currentRun.value != null;
      final enabled =
          hasRun ||
          (controller.project.value != null &&
              !controller.runner.isBusy &&
              !workflow.isPreparing.value);
      final running = workflow.isRunning || workflow.isPreparing.value;
      final reduceMotion = MediaQuery.of(context).disableAnimations;
      return FilledButton.icon(
        key: const Key('run-release-workflow'),
        onPressed: enabled ? () => showReleaseWorkflowDialog(context) : null,
        icon: running && !reduceMotion
            ? const SizedBox.square(
                dimension: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(hasRun ? Icons.monitor_heart_outlined : Icons.rocket_launch),
        label: Text(hasRun ? 'Monitor Release' : 'Run Release'),
      );
    });
  }
}

class _ReleaseWorkflowDialog extends StatefulWidget {
  const _ReleaseWorkflowDialog();

  @override
  State<_ReleaseWorkflowDialog> createState() => _ReleaseWorkflowDialogState();
}

class _ReleaseWorkflowDialogState extends State<_ReleaseWorkflowDialog> {
  static const _tracks = ['internal', 'alpha', 'beta', 'production'];

  final _logScrollController = ScrollController();
  String _track = 'internal';
  bool _productionConfirmed = false;
  bool _newRelease = false;
  int? _selectedStep;
  _ReleaseLogView _logView = _ReleaseLogView.step;
  String? _localError;

  HomeController get controller => Get.find<HomeController>();
  ReleaseWorkflowService get workflow => controller.releaseWorkflow;

  @override
  void initState() {
    super.initState();
    final existing = workflow.currentRun.value;
    if (existing != null) {
      _track = existing.track;
      _productionConfirmed = true;
    } else {
      final selectedPath = controller.project.value?.path.toLowerCase();
      for (final project in controller.chPlayProjects) {
        if (project.path.toLowerCase() == selectedPath &&
            _tracks.contains(project.track.toLowerCase())) {
          _track = project.track.toLowerCase();
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width < 760
        ? (size.width * 0.96).toDouble()
        : (size.width * 0.92).clamp(680.0, 1180.0).toDouble();
    final height = size.height < 640
        ? (size.height * 0.94).toDouble()
        : (size.height * 0.9).clamp(560.0, 820.0).toDouble();

    return SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            key: const Key('release-workflow-dialog'),
            width: width,
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppCyberTheme.panelBackgroundStrong,
                  AppCyberTheme.panelBackgroundStrong.withValues(alpha: 0.92),
                  AppCyberTheme.panelBackgroundStrong,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppCyberTheme.isCyber
                    ? AppCyberTheme.electricBlue.withValues(alpha: 0.58)
                    : AppCyberTheme.lineBlue,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppCyberTheme.electricBlue.withValues(
                    alpha: AppCyberTheme.isCyber ? 0.22 : 0.08,
                  ),
                  blurRadius: 38,
                  spreadRadius: -8,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Obx(() {
              final run = workflow.currentRun.value;
              final showPreparation = _newRelease || run == null;
              return Column(
                children: [
                  _buildHeader(run),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: _motionDuration(
                        context,
                        const Duration(milliseconds: 260),
                      ),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.985,
                              end: 1,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(showPreparation ? 'prepare' : 'monitor'),
                        child: showPreparation
                            ? _buildPreparation(context)
                            : _buildMonitor(context, run),
                      ),
                    ),
                  ),
                  _buildActions(context, run, showPreparation),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ReleaseWorkflowRun? run) {
    final status = _runStatus(run);
    final statusColor = _runStatusColor(context, run);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppCyberTheme.baseBackground.withValues(alpha: 0.22),
        border: Border(
          bottom: BorderSide(
            color: AppCyberTheme.electricBlue.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          _ReleaseHeaderMark(
            color: statusColor,
            running: run?.isRunning ?? workflow.isPreparing.value,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  run == null ? 'Android Release Pipeline' : run.projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: run == null
                      ? const [
                          _HeaderPill(
                            icon: Icons.auto_awesome_motion_outlined,
                            label:
                                'Version -> Commit -> Build -> Deploy -> Release',
                          ),
                        ]
                      : [
                          _HeaderPill(
                            icon: Icons.sell_outlined,
                            label:
                                '${run.currentVersion} -> ${run.proposedVersion}',
                            highlighted: true,
                          ),
                          _HeaderPill(
                            icon: Icons.alt_route_outlined,
                            label: run.track.toUpperCase(),
                            highlighted: run.track == 'production',
                          ),
                          _HeaderPill(
                            icon: Icons.timer_outlined,
                            label: _durationLabel(run.duration),
                          ),
                        ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _ReleaseStatusBadge(label: status, color: statusColor),
          const SizedBox(width: 4),
          IconButton(
            key: const Key('hide-release-workflow'),
            tooltip: workflow.isRunning ? 'Hide monitor' : 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildPreparation(BuildContext context) {
    final isPreparing = workflow.isPreparing.value;
    final project = controller.project.value;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _WorkflowSectionTitle(
                icon: Icons.fact_check_outlined,
                title: 'Prepare release',
                subtitle:
                    'Choose the destination once. Every following step runs without terminal prompts.',
              ),
              const SizedBox(height: 22),
              _WorkflowInfoCard(
                children: [
                  _WorkflowInfoRow(
                    label: 'Project',
                    value: project?.name ?? 'No project selected',
                  ),
                  _WorkflowInfoRow(
                    label: 'Current version',
                    value: project?.pubspecVersion ?? '-',
                  ),
                  const _WorkflowInfoRow(
                    label: 'Version strategy',
                    value: 'max(local, store) + 1 / auto patch bump',
                  ),
                  const _WorkflowInfoRow(
                    label: 'Git strategy',
                    value: 'Commit and push current branch - no PR',
                  ),
                  const _WorkflowInfoRow(
                    label: 'Post upload',
                    value: 'Verify CH Play, then run configured artifact sends',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _TrackSelector(
                track: _track,
                tracks: _tracks,
                enabled: !isPreparing,
                onChanged: (value) => setState(() {
                  _track = value;
                  _productionConfirmed = false;
                  _localError = null;
                }),
              ),
              if (_track == 'production') ...[
                const SizedBox(height: 12),
                _WorkflowCallout(
                  icon: Icons.security_update_warning_outlined,
                  color: const Color(0xFFF79009),
                  child: Material(
                    color: Colors.transparent,
                    child: CheckboxListTile(
                      key: const Key('production-release-confirmation'),
                      value: _productionConfirmed,
                      onChanged: isPreparing
                          ? null
                          : (value) => setState(
                              () => _productionConfirmed = value ?? false,
                            ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'I understand this publishes to the production track.',
                      ),
                      subtitle: const Text(
                        'The workflow will commit, push, build and upload without another confirmation.',
                      ),
                    ),
                  ),
                ),
              ],
              if (_localError != null) ...[
                const SizedBox(height: 14),
                _WorkflowMessage(
                  icon: Icons.error_outline,
                  message: _localError!,
                  color: Theme.of(context).colorScheme.error,
                ),
              ],
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('review-release-workflow'),
                  onPressed:
                      isPreparing ||
                          project == null ||
                          (_track == 'production' && !_productionConfirmed)
                      ? null
                      : _prepare,
                  icon: isPreparing
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.manage_search_outlined),
                  label: Text(
                    isPreparing ? 'Running preflight...' : 'Review Release',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonitor(BuildContext context, ReleaseWorkflowRun run) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    final selectedIndex = _resolvedSelectedStep(run);
    final selectedStep = run.steps[selectedIndex];
    final activeIndex = run.steps.indexWhere(
      (step) => step.status == ReleaseStepStatus.running,
    );
    if ((selectedStep.status == ReleaseStepStatus.running || run.isRunning) &&
        !MediaQuery.of(context).disableAnimations) {
      _scheduleLogScroll();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        children: [
          _buildRunSummary(run),
          const SizedBox(height: 14),
          _ReleaseProgressBar(progress: run.progress, running: run.isRunning),
          const SizedBox(height: 16),
          SizedBox(
            height: compact ? 210 : 126,
            child: _WorkflowTimeline(
              steps: run.steps,
              selectedIndex: selectedIndex,
              activeIndex: activeIndex,
              compact: compact,
              onSelected: (index) => setState(() => _selectedStep = index),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: compact
                ? Column(
                    children: [
                      SizedBox(
                        height: 168,
                        child: _buildStepDetails(run, selectedStep),
                      ),
                      const SizedBox(height: 10),
                      Expanded(child: _buildLog(run, selectedStep)),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 322,
                        child: _buildStepDetails(run, selectedStep),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _buildLog(run, selectedStep)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunSummary(ReleaseWorkflowRun run) {
    return _HudCardShell(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      active: run.isRunning,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _MetaChip(icon: Icons.source_outlined, label: run.currentBranch),
          _MetaChip(
            icon: Icons.sell_outlined,
            label: '${run.currentVersion} -> ${run.proposedVersion}',
            highlighted: true,
          ),
          _MetaChip(
            icon: Icons.alt_route_outlined,
            label: run.track.toUpperCase(),
            highlighted: run.track == 'production',
          ),
          _MetaChip(
            icon: run.supportsSplitBuildDeploy
                ? Icons.call_split_outlined
                : Icons.merge_type_outlined,
            label: run.supportsSplitBuildDeploy
                ? 'Split build/deploy'
                : 'Legacy compatibility',
          ),
          if (run.artifactPath != null)
            _MetaChip(
              icon: Icons.inventory_2_outlined,
              label: run.artifactPath!,
            ),
          _MetaChip(
            icon: Icons.timer_outlined,
            label: _durationLabel(run.duration),
          ),
        ],
      ),
    );
  }

  Widget _buildStepDetails(
    ReleaseWorkflowRun run,
    ReleaseWorkflowStepRun step,
  ) {
    final color = _statusColor(context, step.status);
    return _HudCardShell(
      active: step.status == ReleaseStepStatus.running,
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_stepIcon(step.kind), color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  step.status.name.toUpperCase(),
                  style: AppCyberTheme.dataTextStyle(
                    size: 10,
                    color: color,
                    weight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _stepDescription(step.kind),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DetailMetric(
                  icon: Icons.timer_outlined,
                  label: 'Duration',
                  value: _durationLabel(step.duration),
                ),
                if (step.exitCode != null)
                  _DetailMetric(
                    icon: Icons.numbers_outlined,
                    label: 'Exit',
                    value: '${step.exitCode}',
                  ),
                if (step.artifactPath != null)
                  _DetailMetric(
                    icon: Icons.inventory_2_outlined,
                    label: 'Artifact',
                    value: step.artifactPath!,
                  ),
              ],
            ),
            if (step.kind == ReleaseWorkflowStepKind.legacyBuildDeploy) ...[
              const SizedBox(height: 10),
              _WorkflowCallout(
                icon: Icons.merge_type_outlined,
                color: const Color(0xFFF79009),
                child: Text(
                  'Compatibility mode: this project does not expose separate build_aab and upload_to_chplay lanes, so build and upload run as one legacy step.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            if (step.error != null) ...[
              const SizedBox(height: 10),
              _WorkflowCallout(
                icon: step.status == ReleaseStepStatus.warning
                    ? Icons.warning_amber_outlined
                    : Icons.error_outline,
                color: color,
                child: SelectableText(
                  step.error!,
                  style: AppCyberTheme.dataTextStyle(
                    size: 10.6,
                    color: color,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            if (step.kind == ReleaseWorkflowStepKind.preflight &&
                run.changedFiles.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ChangedFilesPreview(files: run.changedFiles),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLog(ReleaseWorkflowRun run, ReleaseWorkflowStepRun step) {
    final stepLines = _stepLogLines(step);
    final allLines = _allLogLines(run);
    final lines = _logView == _ReleaseLogView.all ? allLines : stepLines;
    final title = _logView == _ReleaseLogView.all ? 'All logs' : 'Step log';
    return _HudCardShell(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
            child: Row(
              children: [
                const Icon(Icons.terminal_outlined, size: 16),
                const SizedBox(width: 7),
                Expanded(child: Text(title)),
                SegmentedButton<_ReleaseLogView>(
                  key: const Key('release-log-view-toggle'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: _ReleaseLogView.step,
                      label: Text('Step'),
                    ),
                    ButtonSegment(
                      value: _ReleaseLogView.all,
                      label: Text('All'),
                    ),
                  ],
                  selected: {_logView},
                  onSelectionChanged: (selection) {
                    setState(() => _logView = selection.first);
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const Key('copy-release-workflow-log'),
                  tooltip: 'Copy log',
                  visualDensity: VisualDensity.compact,
                  onPressed: lines.isEmpty
                      ? null
                      : () => Clipboard.setData(
                          ClipboardData(text: lines.join('\n')),
                        ),
                  icon: const Icon(Icons.copy_all_outlined, size: 17),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: _logScrollController,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: SelectableText(
                  lines.isEmpty ? 'No output yet.' : lines.join('\n'),
                  style: AppCyberTheme.dataTextStyle(
                    size: 11.2,
                    color: AppCyberTheme.textPrimary,
                  ).copyWith(height: 1.38),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _stepLogLines(ReleaseWorkflowStepRun step) {
    if (step.status == ReleaseStepStatus.running || step.logLines.isEmpty) {
      return controller.runner.logLines.toList();
    }
    return step.logLines;
  }

  List<String> _allLogLines(ReleaseWorkflowRun run) {
    final output = <String>[];
    for (final step in run.steps) {
      output.add('[${step.status.name.toUpperCase()}] ${step.label}');
      final lines =
          step.status == ReleaseStepStatus.running || step.logLines.isEmpty
          ? controller.runner.logLines.toList()
          : step.logLines;
      if (lines.isEmpty) {
        output.add('No output recorded.');
      } else {
        output.addAll(lines);
      }
      output.add('');
    }
    if (output.isNotEmpty && output.last.isEmpty) output.removeLast();
    return output;
  }

  Widget _buildActions(
    BuildContext context,
    ReleaseWorkflowRun? run,
    bool showPreparation,
  ) {
    final prepared =
        run != null &&
        run.steps.length > 1 &&
        run.steps.first.status == ReleaseStepStatus.succeeded &&
        run.startedAt == null;
    final artifactPath = run?.artifactPath;
    final leading = TextButton.icon(
      onPressed: () => Navigator.of(context).pop(),
      icon: const Icon(Icons.visibility_off_outlined),
      label: Text(workflow.isRunning ? 'Hide' : 'Close'),
    );
    final trailing = <Widget>[
      if (!showPreparation && artifactPath != null)
        OutlinedButton.icon(
          key: const Key('open-release-artifact'),
          onPressed: () => controller.openReleaseArtifact(artifactPath),
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Open Artifact'),
        ),
      if (workflow.isRunning)
        OutlinedButton.icon(
          key: const Key('stop-release-workflow'),
          onPressed: _confirmStop,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Stop'),
        )
      else if (!showPreparation && workflow.canRetry)
        FilledButton.icon(
          key: const Key('retry-release-workflow'),
          onPressed: _retry,
          icon: const Icon(Icons.replay_outlined),
          label: const Text('Retry Failed Step'),
        )
      else if (!showPreparation && prepared)
        FilledButton.icon(
          key: const Key('start-release-workflow'),
          onPressed: run.track == 'production' && !_productionConfirmed
              ? null
              : _start,
          icon: const Icon(Icons.rocket_launch),
          label: const Text('Start Release'),
        )
      else if (!showPreparation && run != null && run.isCompleted)
        OutlinedButton.icon(
          key: const Key('new-release-workflow'),
          onPressed: () => setState(() {
            _newRelease = true;
            _productionConfirmed = false;
            _localError = null;
          }),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New Release'),
        ),
    ];
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppCyberTheme.electricBlue.withValues(alpha: 0.22),
          ),
        ),
      ),
      child: compact
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [leading, ...trailing],
            )
          : Row(
              children: [
                leading,
                const Spacer(),
                for (var index = 0; index < trailing.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  trailing[index],
                ],
              ],
            ),
    );
  }

  String _runStatus(ReleaseWorkflowRun? run) {
    if (workflow.isPreparing.value) return 'PREFLIGHT';
    if (run == null) return 'READY';
    if (run.isRunning) return 'RUNNING';
    final retryable = run.retryableStep;
    if (retryable != null) return retryable.status.name.toUpperCase();
    if (run.isCompleted && run.hasWarning) return 'WARNING';
    if (run.isCompleted) return 'COMPLETE';
    if (run.startedAt == null) return 'REVIEWED';
    return 'WAITING';
  }

  Color _runStatusColor(BuildContext context, ReleaseWorkflowRun? run) {
    if (workflow.isPreparing.value || run?.isRunning == true) {
      return AppCyberTheme.electricBlue;
    }
    if (run == null || run.startedAt == null) return AppCyberTheme.textMuted;
    final retryable = run.retryableStep;
    if (retryable != null) return _statusColor(context, retryable.status);
    if (run.isCompleted && run.hasWarning) return const Color(0xFFF79009);
    if (run.isCompleted) return AppCyberTheme.neonGreen;
    return AppCyberTheme.textMuted;
  }

  Future<void> _prepare() async {
    setState(() => _localError = null);
    try {
      await controller.prepareAutomatedRelease(_track);
      if (!mounted) return;
      setState(() {
        _newRelease = false;
        _selectedStep = 0;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _localError = error.toString());
    }
  }

  Future<void> _start() async {
    setState(() {
      _localError = null;
      _selectedStep = null;
    });
    try {
      await controller.startAutomatedRelease();
    } catch (error) {
      if (!mounted) return;
      setState(() => _localError = error.toString());
    }
  }

  Future<void> _retry() async {
    setState(() => _selectedStep = null);
    try {
      await controller.retryAutomatedRelease();
    } catch (error) {
      if (!mounted) return;
      setState(() => _localError = error.toString());
    }
  }

  Future<void> _confirmStop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop release workflow?'),
        content: const Text(
          'The active process will stop. Completed version, Git or upload side effects will not be rolled back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep Running'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.cancelAutomatedRelease();
  }

  int _resolvedSelectedStep(ReleaseWorkflowRun run) {
    final selected = _selectedStep;
    if (selected != null && selected >= 0 && selected < run.steps.length) {
      return selected;
    }
    final active = run.steps.indexWhere(
      (step) => step.status == ReleaseStepStatus.running,
    );
    if (active >= 0) return active;
    for (var index = run.steps.length - 1; index >= 0; index--) {
      if (run.steps[index].isTerminal) return index;
    }
    return 0;
  }

  void _scheduleLogScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_logScrollController.hasClients) return;
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _logScrollController.jumpTo(
          _logScrollController.position.maxScrollExtent,
        );
        return;
      }
      _logScrollController.animateTo(
        _logScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      );
    });
  }
}

class _WorkflowTimeline extends StatelessWidget {
  const _WorkflowTimeline({
    required this.steps,
    required this.selectedIndex,
    required this.activeIndex,
    required this.compact,
    required this.onSelected,
  });

  final List<ReleaseWorkflowStepRun> steps;
  final int selectedIndex;
  final int activeIndex;
  final bool compact;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return ListView.separated(
        key: const Key('release-workflow-timeline-vertical'),
        itemCount: steps.length,
        separatorBuilder: (_, index) => _WorkflowConnector(
          completed: _stepCompleted(steps[index]),
          active: activeIndex == index + 1 || activeIndex == index,
          compact: true,
        ),
        itemBuilder: (_, index) => _WorkflowStepIndicator(
          step: steps[index],
          selected: index == selectedIndex,
          compact: true,
          onTap: () => onSelected(index),
        ),
      );
    }
    return Row(
      key: const Key('release-workflow-timeline-horizontal'),
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          Expanded(
            child: _WorkflowStepIndicator(
              step: steps[index],
              selected: index == selectedIndex,
              compact: false,
              onTap: () => onSelected(index),
            ),
          ),
          if (index < steps.length - 1)
            _WorkflowConnector(
              completed: _stepCompleted(steps[index]),
              active: activeIndex == index || activeIndex == index + 1,
              compact: false,
            ),
        ],
      ],
    );
  }
}

class _WorkflowStepIndicator extends StatefulWidget {
  const _WorkflowStepIndicator({
    required this.step,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final ReleaseWorkflowStepRun step;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_WorkflowStepIndicator> createState() => _WorkflowStepIndicatorState();
}

class _WorkflowStepIndicatorState extends State<_WorkflowStepIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _failureAnimated = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _WorkflowStepIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final failure =
        widget.step.status == ReleaseStepStatus.failed ||
        widget.step.status == ReleaseStepStatus.canceled;
    if (failure) {
      if (reduceMotion) {
        _pulse.stop();
        _pulse.value = 0;
      } else if (!_failureAnimated) {
        _failureAnimated = true;
        _pulse.duration = const Duration(milliseconds: 420);
        _pulse.forward(from: 0);
      }
      return;
    }
    _failureAnimated = false;
    final shouldRun =
        widget.step.status == ReleaseStepStatus.running && !reduceMotion;
    if (shouldRun && !_pulse.isAnimating) {
      _pulse.duration = const Duration(milliseconds: 950);
      _pulse.repeat(reverse: true);
    } else if (!shouldRun && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, widget.step.status);
    final statusLabel = widget.step.status.name.toUpperCase();
    final motionIcon = AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) {
        final failure =
            widget.step.status == ReleaseStepStatus.failed ||
            widget.step.status == ReleaseStepStatus.canceled;
        final shake = failure ? _failureShake(_pulse.value) : 0.0;
        final scale = widget.step.status == ReleaseStepStatus.running
            ? 1 + (_pulse.value * 0.1)
            : 1.0;
        return Transform.translate(
          offset: Offset(shake, 0),
          child: Transform.scale(
            key: ValueKey(
              'release-workflow-step-motion-${widget.step.kind.name}',
            ),
            scale: scale,
            child: Container(
              width: widget.compact ? 38 : 36,
              height: widget.compact ? 38 : 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.74)),
                boxShadow: widget.step.status == ReleaseStepStatus.running
                    ? [
                        BoxShadow(
                          color: color.withValues(
                            alpha: 0.16 + _pulse.value * 0.16,
                          ),
                          blurRadius: 10 + _pulse.value * 8,
                        ),
                      ]
                    : const [],
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: _motionDuration(
                    context,
                    const Duration(milliseconds: 220),
                  ),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: Icon(
                    _statusIcon(widget.step),
                    key: ValueKey(widget.step.status),
                    size: 18,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: _motionDuration(context, const Duration(milliseconds: 240)),
        padding: widget.compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 9)
            : const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        decoration: BoxDecoration(
          color: widget.selected ? color.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.selected
                ? color.withValues(alpha: 0.55)
                : Colors.transparent,
          ),
        ),
        child: widget.compact
            ? Row(
                children: [
                  motionIcon,
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.step.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppCyberTheme.dataTextStyle(
                            size: 11,
                            color: widget.selected
                                ? AppCyberTheme.textPrimary
                                : AppCyberTheme.textMuted,
                            weight: widget.selected
                                ? FontWeight.w800
                                : FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          statusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppCyberTheme.dataTextStyle(
                            size: 9.6,
                            color: color,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _durationLabel(widget.step.duration),
                    style: AppCyberTheme.dataTextStyle(
                      size: 9.6,
                      color: AppCyberTheme.textMuted,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  motionIcon,
                  const SizedBox(height: 7),
                  Text(
                    widget.step.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 9.7,
                      color: widget.selected
                          ? AppCyberTheme.textPrimary
                          : AppCyberTheme.textMuted,
                      weight: widget.selected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _WorkflowConnector extends StatefulWidget {
  const _WorkflowConnector({
    required this.completed,
    required this.active,
    required this.compact,
  });

  final bool completed;
  final bool active;
  final bool compact;

  @override
  State<_WorkflowConnector> createState() => _WorkflowConnectorState();
}

class _WorkflowConnectorState extends State<_WorkflowConnector>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scan;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncScan();
  }

  @override
  void didUpdateWidget(covariant _WorkflowConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncScan();
  }

  void _syncScan() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shouldScan = widget.active && !widget.completed && !reduceMotion;
    if (shouldScan && !_scan.isAnimating) {
      _scan.repeat();
    } else if (!shouldScan && _scan.isAnimating) {
      _scan
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.completed ? 1 : 0),
      duration: _motionDuration(context, const Duration(milliseconds: 360)),
      builder: (_, value, _) {
        final baseColor = Color.lerp(
          AppCyberTheme.textMuted.withValues(alpha: widget.active ? 0.42 : 0.2),
          AppCyberTheme.neonGreen.withValues(alpha: 0.78),
          value,
        )!;
        return AnimatedBuilder(
          animation: _scan,
          builder: (_, _) {
            final scanAlpha = widget.active && !widget.completed
                ? 0.18 + (1 - (_scan.value * 2 - 1).abs()) * 0.34
                : 0.0;
            return Container(
              width: widget.compact ? 2 : 22,
              height: widget.compact ? 18 : 2,
              margin: widget.compact
                  ? const EdgeInsets.only(left: 28)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: baseColor,
                boxShadow: scanAlpha <= 0
                    ? const []
                    : [
                        BoxShadow(
                          color: AppCyberTheme.electricBlue.withValues(
                            alpha: scanAlpha,
                          ),
                          blurRadius: 10,
                        ),
                      ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ReleaseProgressBar extends StatelessWidget {
  const _ReleaseProgressBar({required this.progress, required this.running});

  final double progress;
  final bool running;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress),
      duration: _motionDuration(context, const Duration(milliseconds: 440)),
      curve: Curves.easeOutCubic,
      builder: (_, value, _) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          boxShadow: running && AppCyberTheme.isCyber
              ? [
                  BoxShadow(
                    color: AppCyberTheme.electricBlue.withValues(alpha: 0.22),
                    blurRadius: 18,
                    spreadRadius: -5,
                  ),
                ]
              : const [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            key: const Key('release-workflow-progress'),
            value: value,
            minHeight: 8,
            backgroundColor: AppCyberTheme.electricBlue.withValues(alpha: 0.11),
            valueColor: AlwaysStoppedAnimation<Color>(
              running ? AppCyberTheme.electricBlue : AppCyberTheme.neonGreen,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReleaseHeaderMark extends StatelessWidget {
  const _ReleaseHeaderMark({required this.color, required this.running});

  final Color color;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return SizedBox.square(
      dimension: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: color.withValues(alpha: 0.48)),
              boxShadow: AppCyberTheme.isCyber && running
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.18),
                        blurRadius: 18,
                        spreadRadius: -4,
                      ),
                    ]
                  : const [],
            ),
            child: SizedBox.square(
              dimension: 40,
              child: Icon(Icons.rocket_launch_outlined, color: color),
            ),
          ),
          if (running && !reduceMotion)
            SizedBox.square(
              dimension: 44,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: color,
                backgroundColor: color.withValues(alpha: 0.08),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted
        ? AppCyberTheme.electricBlue
        : AppCyberTheme.textMuted;
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: highlighted ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppCyberTheme.dataTextStyle(
                size: 10.5,
                color: highlighted
                    ? AppCyberTheme.textPrimary
                    : AppCyberTheme.textMuted,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseStatusBadge extends StatelessWidget {
  const _ReleaseStatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.48)),
      ),
      child: Text(
        label,
        style: AppCyberTheme.dataTextStyle(
          size: 10,
          color: color,
          weight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TrackSelector extends StatelessWidget {
  const _TrackSelector({
    required this.track,
    required this.tracks,
    required this.enabled,
    required this.onChanged,
  });

  final String track;
  final List<String> tracks;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return _HudCardShell(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.alt_route_outlined,
                size: 17,
                color: AppCyberTheme.electricBlue,
              ),
              const SizedBox(width: 8),
              Text(
                'CH Play track',
                style: AppCyberTheme.dataTextStyle(
                  size: 11,
                  color: AppCyberTheme.textMuted,
                  weight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              key: const Key('release-track-selector'),
              showSelectedIcon: false,
              segments: [
                for (final item in tracks)
                  ButtonSegment(
                    value: item,
                    icon: Icon(_trackIcon(item), size: 16),
                    label: Text(item.toUpperCase()),
                  ),
              ],
              selected: {track},
              onSelectionChanged: enabled
                  ? (selection) => onChanged(selection.first)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowCallout extends StatelessWidget {
  const _WorkflowCallout({
    required this.icon,
    required this.color,
    required this.child,
  });

  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppCyberTheme.baseBackground.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: AppCyberTheme.electricBlue.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppCyberTheme.electricBlue),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: AppCyberTheme.dataTextStyle(
              size: 10,
              color: AppCyberTheme.textMuted,
              weight: FontWeight.w700,
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppCyberTheme.dataTextStyle(
                size: 10.2,
                color: AppCyberTheme.textPrimary,
                weight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangedFilesPreview extends StatelessWidget {
  const _ChangedFilesPreview({required this.files});

  final List<String> files;

  @override
  Widget build(BuildContext context) {
    return _WorkflowCallout(
      icon: Icons.change_circle_outlined,
      color: AppCyberTheme.electricBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${files.length} pre-existing change(s) included in commit.',
            style: AppCyberTheme.dataTextStyle(
              size: 10.4,
              color: AppCyberTheme.textPrimary,
              weight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 112),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final file in files)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: SelectableText(
                        '- $file',
                        style: AppCyberTheme.dataTextStyle(
                          size: 10.2,
                          color: AppCyberTheme.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowSectionTitle extends StatelessWidget {
  const _WorkflowSectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 28, color: AppCyberTheme.electricBlue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkflowInfoCard extends StatelessWidget {
  const _WorkflowInfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _HudCardShell(
      padding: const EdgeInsets.all(14),
      child: Column(children: children),
    );
  }
}

class _WorkflowInfoRow extends StatelessWidget {
  const _WorkflowInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: AppCyberTheme.dataTextStyle(
                size: 10.8,
                color: AppCyberTheme.textMuted,
                weight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppCyberTheme.dataTextStyle(
                size: 11.2,
                color: AppCyberTheme.textPrimary,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowMessage extends StatelessWidget {
  const _WorkflowMessage({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

Color _statusColor(BuildContext context, ReleaseStepStatus status) {
  return switch (status) {
    ReleaseStepStatus.running => AppCyberTheme.electricBlue,
    ReleaseStepStatus.succeeded => AppCyberTheme.neonGreen,
    ReleaseStepStatus.failed ||
    ReleaseStepStatus.canceled => Theme.of(context).colorScheme.error,
    ReleaseStepStatus.warning => const Color(0xFFF79009),
    ReleaseStepStatus.skipped => AppCyberTheme.textMuted,
    ReleaseStepStatus.pending => AppCyberTheme.textMuted,
  };
}

IconData _statusIcon(ReleaseWorkflowStepRun step) {
  return switch (step.status) {
    ReleaseStepStatus.running => Icons.bolt_rounded,
    ReleaseStepStatus.succeeded => Icons.check_rounded,
    ReleaseStepStatus.failed => Icons.close_rounded,
    ReleaseStepStatus.canceled => Icons.stop_rounded,
    ReleaseStepStatus.warning => Icons.priority_high_rounded,
    ReleaseStepStatus.skipped => Icons.skip_next_rounded,
    ReleaseStepStatus.pending => _stepIcon(step.kind),
  };
}

IconData _stepIcon(ReleaseWorkflowStepKind kind) {
  return switch (kind) {
    ReleaseWorkflowStepKind.preflight => Icons.fact_check_outlined,
    ReleaseWorkflowStepKind.versionCode => Icons.pin_outlined,
    ReleaseWorkflowStepKind.versionName => Icons.sell_outlined,
    ReleaseWorkflowStepKind.releaseNotes => Icons.notes_outlined,
    ReleaseWorkflowStepKind.commit => Icons.commit_outlined,
    ReleaseWorkflowStepKind.build => Icons.build_circle_outlined,
    ReleaseWorkflowStepKind.deploy => Icons.cloud_upload_outlined,
    ReleaseWorkflowStepKind.legacyBuildDeploy => Icons.merge_type_outlined,
    ReleaseWorkflowStepKind.release => Icons.rocket_launch_outlined,
  };
}

IconData _trackIcon(String track) {
  return switch (track) {
    'internal' => Icons.lock_outline,
    'alpha' => Icons.science_outlined,
    'beta' => Icons.groups_2_outlined,
    'production' => Icons.public_outlined,
    _ => Icons.alt_route_outlined,
  };
}

String _stepDescription(ReleaseWorkflowStepKind kind) {
  return switch (kind) {
    ReleaseWorkflowStepKind.preflight =>
      'Checks Git, credentials, version state and Fastlane capabilities.',
    ReleaseWorkflowStepKind.versionCode =>
      'Sets the next monotonic code from local and store state.',
    ReleaseWorkflowStepKind.versionName =>
      'Increments the final numeric segment of the version name.',
    ReleaseWorkflowStepKind.releaseNotes =>
      'Generates notes with Gemini or Git fallback and writes Play changelogs.',
    ReleaseWorkflowStepKind.commit =>
      'Commits all release changes and pushes the current branch.',
    ReleaseWorkflowStepKind.build =>
      'Builds the signed release AAB as a reusable artifact.',
    ReleaseWorkflowStepKind.deploy =>
      'Uploads the existing AAB to the selected CH Play track.',
    ReleaseWorkflowStepKind.legacyBuildDeploy =>
      'Runs the legacy combined build/upload command for compatibility.',
    ReleaseWorkflowStepKind.release =>
      'Verifies the store version and runs APK/notification post-processing.',
  };
}

bool _stepCompleted(ReleaseWorkflowStepRun step) {
  return step.status == ReleaseStepStatus.succeeded ||
      step.status == ReleaseStepStatus.warning ||
      step.status == ReleaseStepStatus.skipped;
}

Duration _motionDuration(BuildContext context, Duration duration) {
  return (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
      ? Duration.zero
      : duration;
}

double _failureShake(double value) {
  if (value <= 0 || value >= 1) return 0;
  final segment = (value * 8).floor();
  final direction = segment.isEven ? 1.0 : -1.0;
  return direction * 4 * (1 - value);
}

String _durationLabel(Duration? duration) {
  if (duration == null) return '—';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  if (minutes > 0) return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  return '${seconds}s';
}
