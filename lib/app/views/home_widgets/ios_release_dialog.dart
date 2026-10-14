part of '../home_view.dart';

bool _iosReleaseDialogVisible = false;

Future<void> showIosReleaseDialog(
  BuildContext context,
  HomeController controller,
  AppStoreProject project,
) async {
  if (_iosReleaseDialogVisible) return;
  _iosReleaseDialogVisible = true;
  try {
    await _showReleaseDialogRoute(
      context,
      barrierLabel: 'Bảng release TestFlight / App Store',
      child: _IosReleaseDialog(controller: controller, project: project),
    );
  } finally {
    _iosReleaseDialogVisible = false;
  }
}

/// Something the footer offers to do next with a run.
class _IosAction {
  const _IosAction(this.id, this.label, this.icon, this.onPressed);

  /// Stable name used in widget keys and to avoid offering an action twice.
  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

class _IosReleaseDialog extends StatefulWidget {
  const _IosReleaseDialog({required this.controller, required this.project});

  final HomeController controller;
  final AppStoreProject project;

  @override
  State<_IosReleaseDialog> createState() => _IosReleaseDialogState();
}

class _IosReleaseDialogState extends State<_IosReleaseDialog> {
  final _version = TextEditingController();
  final _notes = TextEditingController();
  IosReleaseSettings _settings = const IosReleaseSettings();
  AppStoreLocalVersion? _local;
  bool _loading = true;
  bool _preparing = false;
  bool _newRelease = false;
  bool _reuseBuild = false;
  bool _loadingBuilds = false;
  List<IosStoreBuild>? _builds;
  IosStoreBuild? _selectedBuild;
  IosReleaseRun? _run;
  IosReleaseStage? _selectedStage;
  String? _error;
  ({String key, Future<List<String>> lines})? _savedLog;

  HomeController get controller => widget.controller;
  IosReleaseWorkflowService get service => controller.iosRelease;

  List<IosReleaseRun> get _history => service.history
      .where((run) => run.project.id == widget.project.id)
      .toList();

  /// Saved settings with the release notes being edited.
  IosReleaseSettings get _draftSettings => IosReleaseSettings.fromJson({
    ..._settings.toJson(),
    'notes': _notes.text,
  });

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await service.load();
      final settings = await service.readSettings(widget.project);
      final local = await controller.appStoreInspector.readLocalVersion(
        widget.project.path,
      );
      if (!mounted) return;
      _settings = settings;
      _local = local;
      _version.text = local?.name ?? '';
      _notes.text = settings.notes;
      // A run still working in the background wins over the newest one.
      final active = service.current.value;
      _run = service.busy.value && active?.project.id == widget.project.id
          ? active
          : _history.firstOrNull;
    } catch (error) {
      _error = error.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _version.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ReleaseDialogFrame(
      key: const Key('ios-release-dialog'),
      child: Obx(() {
        final iosBusy = service.busy.value;
        final blocked = iosBusy || controller.runner.isBusy;
        // Runs are saved in place; this rebuilds when a step updates one.
        service.current.value;
        final history = _history;
        final run = _run;
        final showPreparation = _loading || _newRelease || run == null;
        return Column(
          children: [
            _buildHeader(run, iosBusy, showPreparation, history),
            Expanded(
              child: _ReleaseViewSwitcher(
                viewKey: showPreparation ? 'prepare' : 'monitor',
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : showPreparation
                    ? _buildPreparation(blocked)
                    : _buildMonitor(run, iosBusy),
              ),
            ),
            _buildFooter(run, iosBusy, blocked, showPreparation),
          ],
        );
      }),
    );
  }

  Widget _buildHeader(
    IosReleaseRun? run,
    bool iosBusy,
    bool showPreparation,
    List<IosReleaseRun> history,
  ) {
    final (status, color) = showPreparation
        ? (
            iosBusy ? (_preparing ? 'PREFLIGHT' : 'RUNNING') : 'READY',
            iosBusy ? AppCyberTheme.electricBlue : AppCyberTheme.textMuted,
          )
        : iosBusy
        ? ('RUNNING', AppCyberTheme.electricBlue)
        : (_runLabel(run!), _runColor(run));
    return _ReleaseDialogHeader(
      icon: Icons.apple,
      title: 'Release iOS — ${widget.project.name}',
      status: status,
      statusColor: color,
      running: iosBusy,
      closeKey: const Key('hide-ios-release'),
      closeTooltip: iosBusy ? 'Ẩn bảng theo dõi' : 'Đóng',
      pills: showPreparation
          ? const [
              _HeaderPill(
                icon: Icons.auto_awesome_motion_outlined,
                label: 'Preflight -> Build IPA -> TestFlight -> App Store',
              ),
            ]
          : [
              _HeaderPill(
                icon: Icons.sell_outlined,
                label: '${run!.version}+${run.buildNumber}',
                highlighted: true,
              ),
              _HeaderPill(
                icon: run.reusesBuild
                    ? Icons.history_outlined
                    : Icons.build_circle_outlined,
                label: run.reusesBuild
                    ? 'Build TestFlight có sẵn'
                    : 'Build mới',
              ),
              _HeaderPill(
                icon: Icons.schedule_outlined,
                label: _iosShortDate(run.createdAt),
              ),
            ],
      actions: [
        if (history.isNotEmpty)
          PopupMenuButton<IosReleaseRun>(
            key: const Key('ios-release-history'),
            tooltip: 'Lịch sử release',
            enabled: !iosBusy,
            icon: const Icon(Icons.history),
            onSelected: (selected) => setState(() {
              _run = selected;
              _newRelease = false;
              _selectedStage = null;
              _error = null;
            }),
            itemBuilder: (_) => [
              for (final item in history.take(20))
                CheckedPopupMenuItem(
                  value: item,
                  checked: !showPreparation && item.id == run?.id,
                  child: Text(
                    '${item.version}+${item.buildNumber}  ·  ${_runLabel(item)}  ·  ${_iosShortDate(item.createdAt)}',
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildPreparation(bool blocked) {
    final settings = _settings;
    final testFlight =
        controller.appStoreSnapshots[widget.project.id]?.testFlightBuildNumber;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: _WorkflowSectionTitle(
                      icon: Icons.fact_check_outlined,
                      title: 'Chuẩn bị release iOS',
                      subtitle:
                          'AMC kiểm tra signing, chốt version/build rồi build & upload TestFlight. Gửi review và phát hành luôn hỏi lại.',
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    key: const Key('ios-release-settings'),
                    onPressed: blocked ? null : _openSettings,
                    icon: const Icon(Icons.tune, size: 17),
                    label: const Text('Cấu hình build'),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _WorkflowInfoCard(
                children: [
                  _WorkflowInfoRow(
                    label: 'Bundle ID',
                    value: widget.project.bundleId,
                  ),
                  _WorkflowInfoRow(
                    label: 'Version hiện tại',
                    value:
                        '${_local?.display ?? '-'}${testFlight == null ? '' : '  ·  TestFlight build $testFlight'}',
                  ),
                  _WorkflowInfoRow(
                    label: 'Signing',
                    value:
                        'Team ${settings.teamId.isEmpty ? 'theo API key' : settings.teamId}  ·  ${settings.scheme} / ${settings.configuration}',
                  ),
                  _WorkflowInfoRow(
                    label: 'Phân phối',
                    value:
                        'TestFlight: ${settings.groups.isEmpty ? 'chưa chọn group' : settings.groups.join(', ')}${settings.externalTesting ? ' (external)' : ''}  ·  App Store: ${settings.automaticRelease ? 'tự phát hành sau duyệt' : 'phát hành thủ công'}',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _HudCardShell(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardLabel(Icons.alt_route_outlined, 'Nguồn build'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SegmentedButton<bool>(
                          key: const Key('ios-release-source'),
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: false,
                              icon: Icon(Icons.build_circle_outlined, size: 16),
                              label: Text('BUILD MỚI'),
                            ),
                            ButtonSegment(
                              value: true,
                              icon: Icon(Icons.history_outlined, size: 16),
                              label: Text('BUILD TESTFLIGHT CÓ SẴN'),
                            ),
                          ],
                          selected: {_reuseBuild},
                          onSelectionChanged: blocked
                              ? null
                              : (selection) => _selectSource(selection.first),
                        ),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            key: const Key('ios-release-version'),
                            controller: _version,
                            enabled: !blocked,
                            onChanged: (_) => setState(() {
                              // Builds are listed per version.
                              _builds = null;
                              _selectedBuild = null;
                            }),
                            decoration: const InputDecoration(
                              labelText: 'Marketing version',
                              prefixIcon: Icon(Icons.sell_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _reuseBuild
                          ? 'Chọn một build đã VALID của version này; AMC không build hay upload lại.'
                          : 'AMC đề xuất build number từ TestFlight khi xem lại release.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_reuseBuild) ...[
                      const SizedBox(height: 14),
                      _buildPicker(blocked),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _HudCardShell(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardLabel(
                      Icons.notes_outlined,
                      'Release notes',
                      trailing: settings.useAppStoreLocale
                          ? 'Ngôn ngữ chính App Store'
                          : settings.locale,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('ios-release-notes'),
                      controller: _notes,
                      enabled: !blocked,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText:
                            'What to Test trên TestFlight và What\'s New trên App Store',
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _WorkflowMessage(
                  icon: Icons.error_outline,
                  message: _error!,
                  color: Theme.of(context).colorScheme.error,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardLabel(IconData icon, String label, {String? trailing}) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppCyberTheme.electricBlue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: AppCyberTheme.dataTextStyle(
              size: 11,
              color: AppCyberTheme.textMuted,
              weight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null) _MetaChip(icon: Icons.translate, label: trailing),
      ],
    );
  }

  Widget _buildPicker(bool blocked) {
    if (_loadingBuilds) {
      return const Row(
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Đang lấy build từ App Store Connect...'),
        ],
      );
    }
    final builds = _builds;
    final reload = IconButton(
      tooltip: 'Lấy lại danh sách build',
      onPressed: blocked ? null : _loadBuilds,
      icon: const Icon(Icons.refresh),
    );
    if (builds == null || builds.isEmpty) {
      return Row(
        children: [
          Expanded(
            child: Text(
              builds == null
                  ? 'Chưa lấy danh sách build.'
                  : 'Không có build TestFlight cho version này.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          reload,
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const Key('ios-release-build-picker'),
            initialValue: _selectedBuild?.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Build TestFlight',
              prefixIcon: Icon(Icons.inventory_2_outlined),
            ),
            items: [
              for (final build in builds)
                DropdownMenuItem(
                  value: build.id,
                  enabled: build.isReady,
                  child: Text(
                    '${build.version}+${build.number}  ·  ${build.processingState}${build.expired ? ' · hết hạn' : ''}',
                  ),
                ),
            ],
            onChanged: blocked
                ? null
                : (id) => setState(
                    () => _selectedBuild = builds.firstWhere(
                      (build) => build.id == id,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 6),
        reload,
      ],
    );
  }

  Widget _buildMonitor(IosReleaseRun run, bool iosBusy) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    final live = iosBusy && service.current.value?.id == run.id;
    final statuses = run.stageStatuses(running: live ? run.lastAction : null);
    final steps = [
      for (final stage in IosReleaseStage.values)
        _TimelineStep(
          id: 'ios-${stage.name}',
          label: _iosStageLabel(stage, run),
          icon: _iosStageIcon(stage),
          status: statuses[stage]!,
        ),
    ];
    final current = _currentStage(statuses);
    final selected = _selectedStage ?? current;
    final finished = statuses.values
        .where(
          (status) =>
              status == ReleaseStepStatus.succeeded ||
              status == ReleaseStepStatus.skipped,
        )
        .length;

    final details = _buildStageDetails(
      run,
      selected,
      statuses[selected]!,
      isCurrent: selected == current,
    );
    final log = _buildLog(run, live);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        children: [
          _buildRunSummary(run, live),
          const SizedBox(height: 14),
          _ReleaseProgressBar(progress: finished / steps.length, running: live),
          const SizedBox(height: 16),
          SizedBox(
            height: compact
                ? math.min(210.0, MediaQuery.sizeOf(context).height * 0.25)
                : 126,
            child: _WorkflowTimeline(
              steps: steps,
              selectedIndex: selected.index,
              activeIndex: steps.indexWhere(
                (step) => step.status == ReleaseStepStatus.running,
              ),
              compact: compact,
              onSelected: (index) => setState(
                () => _selectedStage = IosReleaseStage.values[index],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: compact
                ? LayoutBuilder(
                    // Short windows shrink the details before the log.
                    builder: (context, box) => Column(
                      children: [
                        SizedBox(
                          height: math.min(168.0, box.maxHeight * 0.55),
                          child: details,
                        ),
                        const SizedBox(height: 10),
                        Expanded(child: log),
                      ],
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 322, child: details),
                      const SizedBox(width: 12),
                      Expanded(child: log),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// The stage that needs attention: running, then stuck, then next.
  IosReleaseStage _currentStage(Map<IosReleaseStage, ReleaseStepStatus> map) {
    for (final wanted in const [
      [ReleaseStepStatus.running],
      [
        ReleaseStepStatus.failed,
        ReleaseStepStatus.canceled,
        ReleaseStepStatus.warning,
      ],
      [ReleaseStepStatus.pending],
    ]) {
      for (final stage in IosReleaseStage.values) {
        if (wanted.contains(map[stage])) return stage;
      }
    }
    return IosReleaseStage.values.last;
  }

  Widget _buildRunSummary(IosReleaseRun run, bool live) {
    final commit = run.commit.length > 7
        ? run.commit.substring(0, 7)
        : run.commit;
    return _HudCardShell(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      active: live,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _MetaChip(icon: Icons.apps_outlined, label: run.project.bundleId),
          _MetaChip(
            icon: Icons.commit_outlined,
            label: run.dirty ? '$commit · có thay đổi chưa commit' : commit,
          ),
          _MetaChip(
            icon: Icons.verified_user_outlined,
            label: 'Team ${run.settings.teamId}',
          ),
        ],
      ),
    );
  }

  Widget _buildStageDetails(
    IosReleaseRun run,
    IosReleaseStage stage,
    ReleaseStepStatus status, {
    required bool isCurrent,
  }) {
    final color = _statusColor(context, status);
    final stageError =
        status == ReleaseStepStatus.failed ||
            status == ReleaseStepStatus.canceled
        ? run.lastError ?? run.message
        : null;
    final settings = run.settings;
    final metrics = <Widget>[
      if (stage == IosReleaseStage.prepare) ...[
        _DetailMetric(
          icon: Icons.layers_outlined,
          label: 'Scheme',
          value: '${settings.scheme} / ${settings.configuration}',
        ),
        _DetailMetric(
          icon: Icons.code,
          label: 'Entrypoint',
          value: settings.entrypoint,
        ),
      ] else if (stage.index <= IosReleaseStage.processing.index) ...[
        _DetailMetric(
          icon: Icons.sell_outlined,
          label: 'Build',
          value: '${run.version}+${run.buildNumber}',
        ),
        if (stage == IosReleaseStage.build && run.ipaPath != null)
          _DetailMetric(
            icon: Icons.inventory_2_outlined,
            label: 'IPA',
            value: run.ipaPath!,
          ),
      ] else ...[
        _DetailMetric(
          icon: Icons.translate,
          label: 'Ngôn ngữ',
          value: settings.useAppStoreLocale
              ? 'Mặc định App Store'
              : settings.locale,
        ),
        _DetailMetric(
          icon: Icons.public,
          label: 'Sau duyệt',
          value: settings.automaticRelease ? 'Tự phát hành' : 'Thủ công',
        ),
      ],
      if (stage == IosReleaseStage.processing && settings.groups.isNotEmpty)
        _DetailMetric(
          icon: Icons.group_outlined,
          label: 'Groups',
          value: settings.groups.join(', '),
        ),
    ];
    return _HudCardShell(
      active: status == ReleaseStepStatus.running,
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iosStageIcon(stage), color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _iosStageLabel(stage, run),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  status.name.toUpperCase(),
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
              _iosStageDescription(stage, run),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: metrics),
            if (_error != null && _error != stageError) ...[
              const SizedBox(height: 10),
              _WorkflowCallout(
                icon: Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                child: SelectableText(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            if (stageError != null) ...[
              const SizedBox(height: 10),
              _WorkflowCallout(
                icon: Icons.error_outline,
                color: color,
                child: SelectableText(
                  stageError,
                  style: AppCyberTheme.dataTextStyle(
                    size: 10.6,
                    color: color,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ] else if (isCurrent && run.message.isNotEmpty) ...[
              const SizedBox(height: 10),
              _WorkflowCallout(
                icon: status == ReleaseStepStatus.warning
                    ? Icons.warning_amber_outlined
                    : Icons.info_outline,
                color: status == ReleaseStepStatus.warning
                    ? color
                    : AppCyberTheme.electricBlue,
                child: Text(
                  run.message,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            if (stage.index >= IosReleaseStage.appStore.index &&
                settings.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              _WorkflowCallout(
                icon: Icons.notes_outlined,
                color: AppCyberTheme.textMuted,
                child: Text(
                  settings.notes,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLog(IosReleaseRun run, bool live) {
    if (live) {
      return _logPane(run, controller.runner.logLines.toList(), live: true);
    }
    return FutureBuilder<List<String>>(
      future: _savedLogFor(run),
      builder: (context, snapshot) =>
          _logPane(run, snapshot.data ?? const [], live: false),
    );
  }

  Widget _logPane(IosReleaseRun run, List<String> lines, {required bool live}) {
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
                Expanded(child: Text(live ? 'Log đang chạy' : 'Log của run')),
                IconButton(
                  key: const Key('copy-ios-release-log'),
                  tooltip: 'Sao chép log',
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
            child: _LogLines(
              lines: lines,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              style: AppCyberTheme.dataTextStyle(
                size: 11.2,
                color: AppCyberTheme.textPrimary,
              ).copyWith(height: 1.38),
            ),
          ),
        ],
      ),
    );
  }

  /// Tail of the run's command log, re-read when the run moves on.
  Future<List<String>> _savedLogFor(IosReleaseRun run) {
    final key = '${run.id}:${run.steps.length}:${run.status.name}';
    final cached = _savedLog;
    if (cached != null && cached.key == key) return cached.lines;
    final lines = () async {
      final file = File(p.join(run.directory, 'commands.log'));
      if (!await file.exists()) return const <String>[];
      final all = utf8
          .decode(await file.readAsBytes(), allowMalformed: true)
          .trimRight()
          .split('\n');
      return all.length > 600 ? all.sublist(all.length - 600) : all;
    }();
    _savedLog = (key: key, lines: lines);
    return lines;
  }

  Widget _buildFooter(
    IosReleaseRun? run,
    bool iosBusy,
    bool blocked,
    bool showPreparation,
  ) {
    final leading = TextButton.icon(
      onPressed: () => Navigator.of(context).pop(),
      icon: const Icon(Icons.visibility_off_outlined),
      label: Text(iosBusy ? 'Ẩn' : 'Đóng'),
    );
    final trailing = <Widget>[];
    if (iosBusy) {
      trailing.add(
        OutlinedButton.icon(
          key: const Key('stop-ios-release'),
          onPressed: _confirmStop,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Dừng'),
        ),
      );
    }
    if (showPreparation) {
      if (_newRelease && run != null && !_loading && !iosBusy) {
        trailing.add(
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _newRelease = false;
              _error = null;
            }),
            icon: const Icon(Icons.monitor_heart_outlined),
            label: const Text('Quay lại theo dõi'),
          ),
        );
      }
      final canReview =
          !blocked &&
          !_loading &&
          (_reuseBuild
              ? _selectedBuild != null
              : _version.text.trim().isNotEmpty);
      trailing.add(
        FilledButton.icon(
          key: const Key('ios-review-release'),
          onPressed: canReview ? _prepare : null,
          icon: _preparing
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.manage_search_outlined),
          label: Text(
            _preparing ? 'Đang chạy preflight...' : 'Xem lại release',
          ),
        ),
      );
    } else if (run != null && !iosBusy) {
      final primary = _primaryAction(run);
      final secondary = _secondaryAction(run, primary);
      final more = _moreActions(run, [primary.id, ?secondary?.id]);
      if (more.isNotEmpty) {
        trailing.add(
          PopupMenuButton<_IosAction>(
            key: const Key('ios-release-more'),
            tooltip: 'Thao tác khác',
            enabled: !blocked,
            icon: const Icon(Icons.more_horiz),
            onSelected: (action) => action.onPressed(),
            itemBuilder: (_) => [
              for (final action in more)
                PopupMenuItem(
                  value: action,
                  child: Row(
                    children: [
                      Icon(action.icon, size: 18),
                      const SizedBox(width: 10),
                      Flexible(child: Text(action.label)),
                    ],
                  ),
                ),
            ],
          ),
        );
      }
      if (secondary != null) {
        trailing.add(
          OutlinedButton.icon(
            key: Key('ios-action-${secondary.id}'),
            onPressed: blocked ? null : secondary.onPressed,
            icon: Icon(secondary.icon),
            label: Text(secondary.label),
          ),
        );
      }
      trailing.add(
        FilledButton.icon(
          key: Key('ios-action-${primary.id}'),
          onPressed: blocked ? null : primary.onPressed,
          icon: Icon(primary.icon),
          label: Text(primary.label),
        ),
      );
    }
    return _ReleaseDialogFooter(leading: leading, trailing: trailing);
  }

  _IosAction _primaryAction(IosReleaseRun run) => switch (run.status) {
    IosReleaseStatus.prepared || IosReleaseStatus.built => _testFlight(run),
    IosReleaseStatus.processing => _IosAction(
      'wait',
      'Theo dõi processing',
      Icons.hourglass_top_outlined,
      () => _perform(() => service.waitForProcessing(run)),
    ),
    IosReleaseStatus.verificationRequired ||
    IosReleaseStatus.building ||
    IosReleaseStatus.uploading => _refresh(run, 'Kiểm tra lại Apple'),
    IosReleaseStatus.ready => _store(run, 'draft'),
    IosReleaseStatus.draft => _store(run, 'submit'),
    IosReleaseStatus.submitted =>
      run.store.versions.any(
            (version) =>
                version['version'] == run.version &&
                version['state'] == 'PENDING_DEVELOPER_RELEASE',
          )
          ? _store(run, 'release')
          : _refresh(run, 'Làm mới trạng thái'),
    IosReleaseStatus.released => _newReleaseAction,
    IosReleaseStatus.failed ||
    IosReleaseStatus.canceled => switch (run.lastAction) {
      'build' || 'upload' => _testFlight(run, label: 'Chạy lại bước lỗi'),
      'query' => _refresh(run, 'Kiểm tra lại Apple'),
      'draft' ||
      'submit' ||
      'release' ||
      'distribute' => _store(run, run.lastAction, label: 'Chạy lại bước lỗi'),
      _ => _IosAction(
        'new',
        'Chuẩn bị lại',
        Icons.replay_outlined,
        _startNewRelease,
      ),
    },
  };

  _IosAction? _secondaryAction(IosReleaseRun run, _IosAction primary) {
    if (run.status == IosReleaseStatus.ready &&
        run.settings.groups.isNotEmpty) {
      return _store(run, 'distribute');
    }
    if ((run.status == IosReleaseStatus.failed ||
            run.status == IosReleaseStatus.canceled) &&
        primary.id != 'new') {
      return _newReleaseAction;
    }
    return null;
  }

  List<_IosAction> _moreActions(IosReleaseRun run, List<String> shown) {
    final actions = [
      if (run.status == IosReleaseStatus.prepared)
        _IosAction(
          'build',
          'Chỉ build IPA',
          Icons.build_circle_outlined,
          () => _perform(() => service.build(run)),
        ),
      if (run.uploadAttempted) _refresh(run, 'Làm mới trạng thái Apple'),
      if (run.status == IosReleaseStatus.verificationRequired &&
          run.ipaPath != null)
        _IosAction(
          'retry-upload',
          'Thử upload lại (đã kiểm tra Apple)',
          Icons.cloud_upload_outlined,
          () => _confirmRetryUpload(run),
        ),
      if ((run.status == IosReleaseStatus.draft ||
              run.status == IosReleaseStatus.submitted) &&
          run.settings.groups.isNotEmpty)
        _store(run, 'distribute'),
      if (run.status == IosReleaseStatus.submitted &&
          !run.settings.automaticRelease &&
          !run.succeeded('release'))
        _store(run, 'release', label: 'Phát hành bản đã duyệt'),
      if (run.ipaPath != null)
        _IosAction(
          'reveal',
          'Mở IPA trong Finder',
          Icons.folder_open_outlined,
          () => controller.openReleaseArtifact(run.ipaPath!),
        ),
      _newReleaseAction,
    ];
    return actions.where((action) => !shown.contains(action.id)).toList();
  }

  _IosAction _testFlight(IosReleaseRun run, {String? label}) => _IosAction(
    'testflight',
    label ??
        (run.ipaPath == null
            ? 'Build & upload TestFlight'
            : 'Upload TestFlight'),
    Icons.rocket_launch,
    () => _perform(() => service.continueToTestFlight(run)),
  );

  _IosAction _refresh(IosReleaseRun run, String label) => _IosAction(
    'refresh',
    label,
    Icons.refresh,
    () => _perform(() => service.refresh(run)),
  );

  _IosAction _store(IosReleaseRun run, String action, {String? label}) {
    final (title, icon) = switch (action) {
      'distribute' => ('Phân phối TestFlight', Icons.group_add_outlined),
      'draft' => ('Chuẩn bị App Store', Icons.storefront_outlined),
      'submit' => ('Gửi review', Icons.send_outlined),
      _ => ('Phát hành', Icons.public),
    };
    return _IosAction(
      action,
      label ?? title,
      icon,
      () => _confirmStoreAction(run, action, title),
    );
  }

  _IosAction get _newReleaseAction =>
      _IosAction('new', 'Release mới', Icons.add_rounded, _startNewRelease);

  void _startNewRelease() => setState(() {
    _newRelease = true;
    _selectedStage = null;
    _error = null;
  });

  void _selectSource(bool reuse) {
    setState(() {
      _reuseBuild = reuse;
      _error = null;
    });
    if (reuse && _builds == null) _loadBuilds();
  }

  Future<void> _loadBuilds() async {
    setState(() {
      _loadingBuilds = true;
      _error = null;
    });
    try {
      final state = await service.inspect(
        widget.project,
        _draftSettings,
        _version.text.trim(),
      );
      if (!mounted) return;
      // Never preselect: the newest build may come from another repo or run.
      setState(() {
        _builds = state.builds;
        _selectedBuild = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loadingBuilds = false);
    }
  }

  Future<void> _prepare() async {
    final settings = _draftSettings;
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final run = await service.prepare(
        project: widget.project,
        settings: settings,
        version: _version.text,
        existingBuild: _reuseBuild ? _selectedBuild : null,
      );
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _run = run;
        _newRelease = false;
        _selectedStage = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _perform(Future<void> Function() task) async {
    setState(() {
      _error = null;
      _selectedStage = null;
    });
    try {
      await task();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    final updated = await showDialog<IosReleaseSettings>(
      context: context,
      builder: (_) => _IosReleaseSettingsDialog(
        controller: controller,
        project: widget.project,
        settings: _draftSettings,
      ),
    );
    if (updated != null && mounted) setState(() => _settings = updated);
  }

  Future<void> _confirmStoreAction(
    IosReleaseRun run,
    String action,
    String title,
  ) async {
    final settings = run.settings;
    final rows = [
      ('App', '${run.project.name}  ·  ${run.project.bundleId}'),
      ('Build', '${run.version}+${run.buildNumber}'),
      if (action == 'distribute')
        (
          'Groups',
          '${settings.groups.join(', ')}${settings.externalTesting ? ' (external, cần beta review)' : ''}',
        ),
      if ((action == 'distribute' || action == 'draft') &&
          settings.notes.isNotEmpty)
        ('Release notes', settings.notes),
      if (action == 'submit')
        (
          'Sau khi duyệt',
          settings.automaticRelease
              ? 'Tự phát hành ngay'
              : 'Chờ bạn bấm phát hành',
        ),
    ];
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title?'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, value) in rows)
                _WorkflowInfoRow(label: label, value: value),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(title),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await _perform(() => service.storeAction(run, action));
    }
  }

  Future<void> _confirmRetryUpload(IosReleaseRun run) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thử upload lại?'),
        content: Text(
          'Apple chưa hiển thị ${run.version}+${run.buildNumber}. Chỉ tiếp tục nếu bạn đã kiểm tra lần upload trước thất bại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Chờ thêm'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đã kiểm tra, thử lại'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await _perform(() => service.upload(run, retryAfterVerification: true));
    }
  }

  Future<void> _confirmStop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dừng luồng iOS?'),
        content: const Text(
          'Lệnh đang chạy sẽ dừng. Bản đã upload lên Apple không bị hoàn tác; hãy kiểm tra lại Apple trước khi thử lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Chạy tiếp'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Dừng'),
          ),
        ],
      ),
    );
    if (confirmed == true) await service.cancel();
  }

  String _runLabel(IosReleaseRun run) => switch (run.status) {
    IosReleaseStatus.prepared => 'REVIEWED',
    IosReleaseStatus.building => 'BUILDING',
    IosReleaseStatus.built => 'BUILT',
    IosReleaseStatus.uploading => 'UPLOADING',
    IosReleaseStatus.processing => 'PROCESSING',
    IosReleaseStatus.verificationRequired => 'VERIFY',
    IosReleaseStatus.ready => 'TESTFLIGHT',
    IosReleaseStatus.draft => 'DRAFT',
    IosReleaseStatus.submitted =>
      run.succeeded('release') ? 'RELEASING' : 'IN REVIEW',
    IosReleaseStatus.released => 'RELEASED',
    IosReleaseStatus.failed => 'FAILED',
    IosReleaseStatus.canceled => 'CANCELED',
  };

  Color _runColor(IosReleaseRun run) => switch (run.status) {
    IosReleaseStatus.failed ||
    IosReleaseStatus.canceled => Theme.of(context).colorScheme.error,
    IosReleaseStatus.verificationRequired => const Color(0xFFF79009),
    IosReleaseStatus.ready ||
    IosReleaseStatus.released => AppCyberTheme.neonGreen,
    IosReleaseStatus.building ||
    IosReleaseStatus.uploading ||
    IosReleaseStatus.processing ||
    IosReleaseStatus.submitted => AppCyberTheme.electricBlue,
    IosReleaseStatus.prepared ||
    IosReleaseStatus.built ||
    IosReleaseStatus.draft => AppCyberTheme.textMuted,
  };
}

/// Build, signing and distribution choices that rarely change per release.
class _IosReleaseSettingsDialog extends StatefulWidget {
  const _IosReleaseSettingsDialog({
    required this.controller,
    required this.project,
    required this.settings,
  });

  final HomeController controller;
  final AppStoreProject project;
  final IosReleaseSettings settings;

  @override
  State<_IosReleaseSettingsDialog> createState() =>
      _IosReleaseSettingsDialogState();
}

class _IosReleaseSettingsDialogState extends State<_IosReleaseSettingsDialog> {
  late final _flavor = TextEditingController(text: widget.settings.flavor);
  late final _entrypoint = TextEditingController(
    text: widget.settings.entrypoint,
  );
  late final _teamId = TextEditingController(text: widget.settings.teamId);
  late final _exportOptions = TextEditingController(
    text: widget.settings.exportOptionsPath,
  );
  late final _arguments = TextEditingController(
    text: widget.settings.extraBuildArguments.join('\n'),
  );
  late final _flutter = TextEditingController(
    text: widget.settings.flutterExecutable,
  );
  late final _groups = TextEditingController(
    text: widget.settings.groups.join(', '),
  );
  late final _locale = TextEditingController(text: widget.settings.locale);
  late bool _external = widget.settings.externalTesting;
  late bool _useAppStoreLocale = widget.settings.useAppStoreLocale;
  late bool _automatic = widget.settings.automaticRelease;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final field in [
      _flavor,
      _entrypoint,
      _teamId,
      _exportOptions,
      _arguments,
      _flutter,
      _groups,
      _locale,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  /// Flutter IPA builds only accept Runner/Release or the flavor's scheme and
  /// `Release-<flavor>`, so both follow the flavor.
  IosReleaseSettings _read() {
    final flavor = _flavor.text.trim();
    return IosReleaseSettings(
      scheme: flavor.isEmpty ? 'Runner' : flavor,
      configuration: flavor.isEmpty ? 'Release' : 'Release-$flavor',
      entrypoint: _entrypoint.text.trim(),
      flavor: flavor,
      exportOptionsPath: _exportOptions.text.trim(),
      flutterExecutable: _flutter.text.trim(),
      teamId: _teamId.text.trim(),
      locale: _locale.text.trim(),
      useAppStoreLocale: _useAppStoreLocale,
      notes: widget.settings.notes,
      groups: _groups.text
          .split(',')
          .map((group) => group.trim())
          .where((group) => group.isNotEmpty)
          .toList(),
      externalTesting: _external,
      automaticRelease: _automatic,
      extraBuildArguments: _arguments.text
          .split('\n')
          .map((argument) => argument.trim())
          .where((argument) => argument.isNotEmpty)
          .toList(),
    );
  }

  String _message(Object error) =>
      error is FormatException ? error.message : error.toString();

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final settings = _read();
      await widget.controller.iosRelease.saveSettings(widget.project, settings);
      if (mounted) Navigator.of(context).pop(settings);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _message(error);
          _saving = false;
        });
      }
    }
  }

  Future<void> _exportScripts() async {
    setState(() => _error = null);
    try {
      final directory = await file_selector.getDirectoryPath(
        confirmButtonText: 'Xuất script',
      );
      if (directory == null) return;
      final output = await widget.controller.iosRelease.exportScripts(
        widget.project,
        _read(),
        directory,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Đã xuất script iOS: $output')));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? helper,
    int lines = 1,
  }) {
    return TextField(
      controller: controller,
      minLines: lines,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        prefixIcon: Icon(icon),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title.toUpperCase(),
      style: AppCyberTheme.dataTextStyle(
        size: 10.5,
        color: AppCyberTheme.textMuted,
        weight: FontWeight.w800,
      ),
    ),
  );

  Widget _option(
    String title,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
  }) {
    return CheckboxListTile(
      value: value,
      onChanged: (checked) => setState(() => onChanged(checked ?? false)),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('ios-release-settings-dialog'),
      backgroundColor: AppCyberTheme.panelBackgroundStrong,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppCyberTheme.palette.cardBorder),
      ),
      title: const _PanelTitle(icon: Icons.tune, title: 'Cấu hình release iOS'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section('Build & signing'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _field(
                      _flavor,
                      'Flavor',
                      Icons.layers_outlined,
                      helper: 'Trống: scheme Runner / Release',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(_entrypoint, 'Entrypoint', Icons.code),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _field(
                      _teamId,
                      'Team ID',
                      Icons.groups_2_outlined,
                      helper: 'Trống: dùng Team ID của API key',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      _exportOptions,
                      'ExportOptions plist',
                      Icons.description_outlined,
                      helper: 'Trống: signing Automatic',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _field(
                _arguments,
                'Build arguments bổ sung',
                Icons.terminal,
                helper: 'Mỗi dòng một flag, ví dụ --dart-define=ENV=production',
                lines: 2,
              ),
              const SizedBox(height: 12),
              _field(
                _flutter,
                'Flutter executable',
                Icons.flutter_dash,
                helper: 'Trống: dùng Flutter của AMC',
              ),
              const SizedBox(height: 20),
              _section('Phân phối'),
              _field(
                _groups,
                'TestFlight groups',
                Icons.group_outlined,
                helper: 'Phân cách bằng dấu phẩy',
              ),
              _option(
                'External testing (cần beta review)',
                _external,
                (value) => _external = value,
              ),
              _option(
                'Dùng ngôn ngữ mặc định của App Store',
                _useAppStoreLocale,
                (value) => _useAppStoreLocale = value,
                subtitle:
                    'Giữ ngôn ngữ chính đã cấu hình trên App Store Connect.',
              ),
              if (!_useAppStoreLocale) ...[
                const SizedBox(height: 4),
                _field(
                  _locale,
                  'Locale release notes',
                  Icons.translate,
                  helper: 'vi-VN → tiếng Việt (vi) trên App Store',
                ),
                const SizedBox(height: 4),
              ],
              _option(
                'Tự phát hành sau khi Apple duyệt',
                _automatic,
                (value) => _automatic = value,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: AppCyberTheme.dataTextStyle(
                    size: 11,
                    color: Theme.of(context).colorScheme.error,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _saving ? null : _exportScripts,
          icon: const Icon(Icons.ios_share_outlined),
          label: const Text('Xuất script iOS'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton.icon(
          key: const Key('save-ios-release-settings'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Lưu'),
        ),
      ],
    );
  }
}

String _iosShortDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}

String _iosStageLabel(IosReleaseStage stage, IosReleaseRun run) =>
    switch (stage) {
      IosReleaseStage.prepare => 'Preflight',
      IosReleaseStage.build => 'Build IPA',
      IosReleaseStage.upload => 'Upload',
      IosReleaseStage.processing => 'Apple xử lý',
      IosReleaseStage.appStore => 'App Store',
      IosReleaseStage.review => 'Review',
      IosReleaseStage.release =>
        run.settings.automaticRelease ? 'Tự phát hành' : 'Phát hành',
    };

IconData _iosStageIcon(IosReleaseStage stage) => switch (stage) {
  IosReleaseStage.prepare => Icons.fact_check_outlined,
  IosReleaseStage.build => Icons.build_circle_outlined,
  IosReleaseStage.upload => Icons.cloud_upload_outlined,
  IosReleaseStage.processing => Icons.hourglass_top_outlined,
  IosReleaseStage.appStore => Icons.storefront_outlined,
  IosReleaseStage.review => Icons.rate_review_outlined,
  IosReleaseStage.release => Icons.public,
};

String _iosStageDescription(
  IosReleaseStage stage,
  IosReleaseRun run,
) => switch (stage) {
  IosReleaseStage.prepare =>
    'Kiểm tra API key, certificate, scheme và Bundle ID; chốt build number từ TestFlight.',
  IosReleaseStage.build when run.reusesBuild =>
    'Bỏ qua: dùng build đã có trên TestFlight.',
  IosReleaseStage.build =>
    'flutter build ipa với version/build đã chốt, rồi kiểm tra Bundle ID và version trong IPA.',
  IosReleaseStage.upload when run.reusesBuild =>
    'Bỏ qua: build đã có trên App Store Connect.',
  IosReleaseStage.upload =>
    'Upload đúng IPA vừa build lên App Store Connect. Không tự upload lại khi chưa rõ kết quả.',
  IosReleaseStage.processing =>
    'Apple xử lý build. Khi VALID, build dùng được trên TestFlight và có thể phân phối tới groups.',
  IosReleaseStage.appStore =>
    'Tạo version App Store, gắn đúng build và cập nhật What\'s New. Chưa gửi review.',
  IosReleaseStage.review =>
    'Gửi Apple xét duyệt. AMC luôn hỏi xác nhận trước khi gửi.',
  IosReleaseStage.release =>
    run.settings.automaticRelease
        ? 'Apple tự phát hành ngay khi duyệt xong.'
        : 'Sau khi Apple duyệt, bấm phát hành để lên App Store.',
};
