part of '../home_view.dart';

bool _releaseWorkflowDialogVisible = false;

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
    final width = (size.width * 0.92).clamp(680.0, 1180.0).toDouble();
    final height = (size.height * 0.9).clamp(560.0, 820.0).toDouble();

    return SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            key: const Key('release-workflow-dialog'),
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: AppCyberTheme.panelBackgroundStrong,
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
                    child: showPreparation
                        ? _buildPreparation(context)
                        : _buildMonitor(context, run),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 15, 12, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppCyberTheme.electricBlue.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppCyberTheme.electricBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppCyberTheme.electricBlue.withValues(alpha: 0.42),
              ),
            ),
            child: const SizedBox.square(
              dimension: 40,
              child: Icon(Icons.rocket_launch_outlined),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  run == null ? 'Android Release Pipeline' : run.projectName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  run == null
                      ? 'Version → Commit → Build → Deploy → Release'
                      : '${run.proposedVersion}  •  ${run.track.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 11.2,
                    color: AppCyberTheme.textMuted,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
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
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
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
                    value: 'Commit and push current branch — no PR',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                key: const Key('release-track-selector'),
                initialValue: _track,
                decoration: const InputDecoration(
                  labelText: 'CH Play track',
                  prefixIcon: Icon(Icons.alt_route_outlined),
                ),
                items: _tracks
                    .map(
                      (track) => DropdownMenuItem(
                        value: track,
                        child: Text(track.toUpperCase()),
                      ),
                    )
                    .toList(),
                onChanged: isPreparing
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _track = value;
                          _productionConfirmed = false;
                          _localError = null;
                        });
                      },
              ),
              if (_track == 'production') ...[
                const SizedBox(height: 12),
                Material(
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
              FilledButton.icon(
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
                  isPreparing ? 'Running preflight…' : 'Review Release',
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
    final lines =
        selectedStep.status == ReleaseStepStatus.running ||
            selectedStep.logLines.isEmpty
        ? controller.runner.logLines.toList()
        : selectedStep.logLines;
    if (selectedStep.status == ReleaseStepStatus.running &&
        !MediaQuery.of(context).disableAnimations) {
      _scheduleLogScroll();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        children: [
          _buildRunSummary(run),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween(end: run.progress),
            duration: _motionDuration(
              context,
              const Duration(milliseconds: 360),
            ),
            curve: Curves.easeOutCubic,
            builder: (_, value, _) => LinearProgressIndicator(
              key: const Key('release-workflow-progress'),
              value: value,
              minHeight: 7,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: compact ? 178 : 116,
            child: _WorkflowTimeline(
              steps: run.steps,
              selectedIndex: selectedIndex,
              vertical: compact,
              onSelected: (index) => setState(() => _selectedStep = index),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: compact
                ? Column(
                    children: [
                      SizedBox(
                        height: 126,
                        child: _buildStepDetails(run, selectedStep),
                      ),
                      const SizedBox(height: 10),
                      Expanded(child: _buildLog(lines)),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 292,
                        child: _buildStepDetails(run, selectedStep),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _buildLog(lines)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunSummary(ReleaseWorkflowRun run) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MetaChip(icon: Icons.source_outlined, label: run.currentBranch),
        _MetaChip(
          icon: Icons.sell_outlined,
          label: '${run.currentVersion} → ${run.proposedVersion}',
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
        _MetaChip(
          icon: Icons.timer_outlined,
          label: _durationLabel(run.duration),
        ),
      ],
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
                    size: 9.8,
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
            const SizedBox(height: 10),
            Text(
              'Duration: ${_durationLabel(step.duration)}',
              style: AppCyberTheme.dataTextStyle(
                size: 10.4,
                color: AppCyberTheme.textMuted,
              ),
            ),
            if (step.exitCode != null)
              Text(
                'Exit code: ${step.exitCode}',
                style: AppCyberTheme.dataTextStyle(
                  size: 10.4,
                  color: AppCyberTheme.textMuted,
                ),
              ),
            if (step.error != null) ...[
              const SizedBox(height: 10),
              Text(
                step.error!,
                style: AppCyberTheme.dataTextStyle(
                  size: 10.6,
                  color: color,
                  weight: FontWeight.w600,
                ),
              ),
            ],
            if (step.kind == ReleaseWorkflowStepKind.preflight &&
                run.changedFiles.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '${run.changedFiles.length} pre-existing change(s) included in commit.',
                style: AppCyberTheme.dataTextStyle(
                  size: 10.4,
                  color: AppCyberTheme.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              for (final file in run.changedFiles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      '• $file',
                      style: AppCyberTheme.dataTextStyle(
                        size: 10.2,
                        color: AppCyberTheme.textMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLog(List<String> lines) {
    return _HudCardShell(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 4),
            child: Row(
              children: [
                const Icon(Icons.terminal_outlined, size: 16),
                const SizedBox(width: 7),
                const Expanded(child: Text('Step log')),
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
              padding: const EdgeInsets.all(12),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppCyberTheme.electricBlue.withValues(alpha: 0.22),
          ),
        ),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.visibility_off_outlined),
            label: Text(workflow.isRunning ? 'Hide' : 'Close'),
          ),
          const Spacer(),
          if (!showPreparation && artifactPath != null) ...[
            OutlinedButton.icon(
              key: const Key('open-release-artifact'),
              onPressed: () => controller.openReleaseArtifact(artifactPath),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Open Artifact'),
            ),
            const SizedBox(width: 8),
          ],
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
        ],
      ),
    );
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
    required this.vertical,
    required this.onSelected,
  });

  final List<ReleaseWorkflowStepRun> steps;
  final int selectedIndex;
  final bool vertical;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (vertical) {
      return ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: steps.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => SizedBox(
          width: 126,
          child: _WorkflowStepIndicator(
            step: steps[index],
            selected: index == selectedIndex,
            onTap: () => onSelected(index),
          ),
        ),
      );
    }
    return Row(
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          Expanded(
            child: _WorkflowStepIndicator(
              step: steps[index],
              selected: index == selectedIndex,
              onTap: () => onSelected(index),
            ),
          ),
          if (index < steps.length - 1)
            _WorkflowConnector(completed: _stepCompleted(steps[index])),
        ],
      ],
    );
  }
}

class _WorkflowStepIndicator extends StatefulWidget {
  const _WorkflowStepIndicator({
    required this.step,
    required this.selected,
    required this.onTap,
  });

  final ReleaseWorkflowStepRun step;
  final bool selected;
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
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: _motionDuration(context, const Duration(milliseconds: 240)),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        decoration: BoxDecoration(
          color: widget.selected ? color.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.selected
                ? color.withValues(alpha: 0.55)
                : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
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
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.12),
                        border: Border.all(color: color.withValues(alpha: 0.7)),
                        boxShadow:
                            widget.step.status == ReleaseStepStatus.running
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
            ),
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
                weight: widget.selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowConnector extends StatelessWidget {
  const _WorkflowConnector({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: completed ? 1 : 0),
      duration: _motionDuration(context, const Duration(milliseconds: 360)),
      builder: (_, value, _) => Container(
        width: 18,
        height: 2,
        color: Color.lerp(
          AppCyberTheme.textMuted.withValues(alpha: 0.2),
          AppCyberTheme.neonGreen.withValues(alpha: 0.75),
          value,
        ),
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
