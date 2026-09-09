part of '../home_view.dart';

class _OptionsPanel extends StatefulWidget {
  const _OptionsPanel();

  @override
  State<_OptionsPanel> createState() => _OptionsPanelState();
}

class _OptionsPanelState extends State<_OptionsPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final Worker _shellTabWorker;

  AppShellController get shell => Get.find<AppShellController>();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: ShellOptionsTab.values.length,
      vsync: this,
      initialIndex: shell.optionsTab.value.index,
    );
    _tabs.addListener(_publishTabToShell);
    _shellTabWorker = ever<ShellOptionsTab>(
      shell.optionsTab,
      _adoptTabFromShell,
    );
  }

  @override
  void dispose() {
    _shellTabWorker.dispose();
    _tabs.removeListener(_publishTabToShell);
    _tabs.dispose();
    super.dispose();
  }

  /// Keeps the shell in step when the user clicks a tab button directly, so the
  /// palette's "Go to" entries and the tab strip never disagree.
  void _publishTabToShell() {
    if (_tabs.indexIsChanging) return;
    shell.showOptionsTab(ShellOptionsTab.values[_tabs.index]);
  }

  void _adoptTabFromShell(ShellOptionsTab tab) {
    if (!mounted || _tabs.index == tab.index) return;
    _tabs.animateTo(tab.index);
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(icon: Icons.tune_outlined, title: 'Tuỳ chọn'),
          const SizedBox(height: 10),
          _OptionsTabSelector(controller: _tabs),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _OptionsTabShell(child: _ReleaseOptions()),
                _OptionsTabShell(child: _CiCdSetupOptions()),
                _OptionsTabShell(child: _ResourceOptions()),
                _OptionsTabShell(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TelegramReleaseOptions(),
                      SizedBox(height: 10),
                      _InstallerTelegramOptions(),
                    ],
                  ),
                ),
                _OptionsTabShell(child: _NotificationOptions()),
                _OptionsTabShell(child: _RemoteControlOptions()),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _CommandInputDock(),
        ],
      ),
    );
  }
}

extension _OptionsTabMeta on ShellOptionsTab {
  IconData get icon {
    return switch (this) {
      ShellOptionsTab.release => Icons.rocket_launch_outlined,
      ShellOptionsTab.setup => Icons.construction_outlined,
      ShellOptionsTab.resources => Icons.inventory_2_outlined,
      ShellOptionsTab.telegram => Icons.send_outlined,
      ShellOptionsTab.push => Icons.notifications_active_outlined,
      ShellOptionsTab.remote => Icons.settings_remote_outlined,
    };
  }

  String get label {
    return switch (this) {
      ShellOptionsTab.release => 'Release',
      ShellOptionsTab.setup => 'Thiết lập',
      ShellOptionsTab.resources => 'Tài nguyên',
      ShellOptionsTab.telegram => 'Telegram',
      ShellOptionsTab.push => 'Thông báo',
      ShellOptionsTab.remote => 'Điều khiển',
    };
  }
}

class _OptionsTabSelector extends StatefulWidget {
  const _OptionsTabSelector({required this.controller});

  final TabController controller;

  @override
  State<_OptionsTabSelector> createState() => _OptionsTabSelectorState();
}

class _OptionsTabSelectorState extends State<_OptionsTabSelector> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTabChange);
  }

  @override
  void didUpdateWidget(covariant _OptionsTabSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleTabChange);
    widget.controller.addListener(_handleTabChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTabChange);
    super.dispose();
  }

  void _handleTabChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = widget.controller.index;
    const spacing = 8.0;
    final rows = <Widget>[];
    final tabs = ShellOptionsTab.values;

    for (var index = 0; index < tabs.length; index += 2) {
      final first = tabs[index];
      final second = index + 1 < tabs.length ? tabs[index + 1] : null;
      rows.add(
        Row(
          children: [
            Expanded(
              child: _OptionsTabButton(
                tab: first,
                selected: selectedIndex == first.index,
                onTap: _select,
              ),
            ),
            if (second != null) ...[
              const SizedBox(width: spacing),
              Expanded(
                child: _OptionsTabButton(
                  tab: second,
                  selected: selectedIndex == second.index,
                  onTap: _select,
                ),
              ),
            ] else ...[
              const SizedBox(width: spacing),
              const Expanded(child: SizedBox.shrink()),
            ],
          ],
        ),
      );
      if (index + 2 < tabs.length) {
        rows.add(const SizedBox(height: spacing));
      }
    }

    return Column(children: rows);
  }

  void _select(ShellOptionsTab tab) => widget.controller.animateTo(tab.index);
}

class _OptionsTabButton extends StatelessWidget {
  const _OptionsTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final ShellOptionsTab tab;
  final bool selected;
  final ValueChanged<ShellOptionsTab> onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? AppCyberTheme.electricBlue.withValues(alpha: 0.72)
        : AppCyberTheme.lineBlue.withValues(alpha: 0.25);
    final backgroundColor = selected
        ? AppCyberTheme.electricBlue.withValues(alpha: 0.14)
        : AppCyberTheme.panelBackgroundStrong.withValues(
            alpha: AppCyberTheme.isCyber ? 0.34 : 0.82,
          );
    final foregroundColor = selected
        ? AppCyberTheme.electricBlue
        : AppCyberTheme.textMuted;

    return Tooltip(
      message: tab.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('options-tab-${tab.name}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => onTap(tab),
          child: AnimatedContainer(
            height: 42,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
              boxShadow: selected && AppCyberTheme.isCyber
                  ? [
                      BoxShadow(
                        color: AppCyberTheme.electricBlue.withValues(
                          alpha: 0.18,
                        ),
                        blurRadius: 12,
                        spreadRadius: -4,
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(tab.icon, size: 17, color: foregroundColor),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 11.5,
                      color: foregroundColor,
                      weight: selected ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionsTabShell extends StatelessWidget {
  const _OptionsTabShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.only(right: 2, bottom: 2),
      child: child,
    );
  }
}

class _ReleaseOptions extends GetView<HomeController> {
  const _ReleaseOptions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final project = controller.project.value;
      final hasFirebaseTools = project?.hasFirebaseDeployTools ?? false;
      final hasPlayTools = project?.hasPlayReleaseTools ?? false;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasFirebaseTools) ...[
            CheckboxListTile(
              value: controller.includeFirebaseDeploy.value,
              onChanged: (value) {
                controller.includeFirebaseDeploy.value = value ?? true;
              },
              contentPadding: EdgeInsets.zero,
              title: const Text('Firebase App Distribution'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Divider(height: 24),
          ],
          if (hasPlayTools) ...[
            const _PlayUploadOptions(),
            const SizedBox(height: 10),
            const _AiReleaseNotesOptions(),
            const SizedBox(height: 10),
            _PlayImageOptions(project: project!),
            const SizedBox(height: 10),
            const _GoogleDriveFallbackOptions(),
            const Divider(height: 24),
          ],
          if (!hasFirebaseTools && !hasPlayTools) ...[
            _HudCardShell(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chọn dự án có sẵn bộ công cụ release để hiện tuỳ chọn deploy.',
                      style: AppCyberTheme.dataTextStyle(
                        size: 10.8,
                        color: AppCyberTheme.textMuted,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const _CustomScriptArguments(),
        ],
      );
    });
  }
}

class _CiCdSetupOptions extends GetView<HomeController> {
  const _CiCdSetupOptions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final snapshot = controller.cicdDependencySnapshot.value;
      final isChecking = controller.isCheckingCiCdDependencies.value;
      final isRunning = controller.isRunningCiCdInstallStep.value;
      final setupBusy = isChecking || isRunning;
      final steps = controller.cicdInstallSteps.toList(growable: false);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HudCardShell(
            active: setupBusy,
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: _PanelTitle(
                        icon: Icons.health_and_safety_outlined,
                        title: 'Doctor',
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const Key('cicd-doctor-check'),
                      onPressed: setupBusy
                          ? null
                          : controller.checkCiCdDependencies,
                      icon: isChecking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.manage_search_outlined),
                      label: Text(isChecking ? 'Đang kiểm tra' : 'Chạy Doctor'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaChip(
                      icon: Icons.desktop_windows_outlined,
                      label: snapshot?.platform.label ?? 'Chưa kiểm tra',
                      highlighted: snapshot != null,
                    ),
                    if (snapshot != null)
                      _MetaChip(
                        icon: Icons.schedule_outlined,
                        label: _ciCdCheckedAtLabel(snapshot.checkedAt),
                      ),
                  ],
                ),
                if (controller.cicdSetupStatus.value.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    controller.cicdSetupStatus.value,
                    style: AppCyberTheme.dataTextStyle(
                      size: 10.8,
                      color: AppCyberTheme.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (snapshot == null)
                  const _CiCdEmptyState(
                    icon: Icons.search_outlined,
                    message: 'Chạy Doctor để quét dependency CI/CD.',
                  )
                else
                  _CiCdDoctorList(snapshot: snapshot),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _HudCardShell(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _PanelTitle(
                  icon: Icons.playlist_add_check_outlined,
                  title: 'Hàng đợi cài đặt',
                ),
                const SizedBox(height: 10),
                _CiCdSetupOptionSelector(snapshot: snapshot),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hàng đợi',
                        style: AppCyberTheme.dataTextStyle(
                          size: 11.4,
                          color: AppCyberTheme.textPrimary,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _MetaChip(
                      icon: Icons.terminal_outlined,
                      label: '${steps.length} step(s)',
                      highlighted: steps.isNotEmpty,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (snapshot == null)
                  const _CiCdEmptyState(
                    icon: Icons.fact_check_outlined,
                    message: 'Hàng đợi hiện ra sau khi Doctor quét xong.',
                  )
                else if (steps.isEmpty)
                  const _CiCdEmptyState(
                    icon: Icons.verified_outlined,
                    message: 'Không có bước cài nào cho các công cụ đã chọn.',
                  )
                else
                  ...steps.map((step) => _CiCdInstallStepTile(step: step)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const _CiCdSetupLogs(),
        ],
      );
    });
  }
}

class _CiCdDoctorList extends StatelessWidget {
  const _CiCdDoctorList({required this.snapshot});

  final CiCdDependencySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final group in CiCdSetupGroup.values) {
      final checks = snapshot.checksForGroup(group);
      if (checks.isEmpty) continue;
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      children.add(
        Text(
          group.label,
          style: AppCyberTheme.dataTextStyle(
            size: 11.4,
            color: AppCyberTheme.textPrimary,
            weight: FontWeight.w800,
          ),
        ),
      );
      children.add(const SizedBox(height: 4));
      for (final check in checks) {
        children.add(_CiCdDependencyRow(check: check));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _CiCdDependencyRow extends StatelessWidget {
  const _CiCdDependencyRow({required this.check});

  final CiCdDependencyCheck check;

  @override
  Widget build(BuildContext context) {
    final color = _ciCdStatusColor(check.status);
    final detailParts = [
      if (check.version.trim().isNotEmpty) check.version.trim(),
      if (check.detail.trim().isNotEmpty) check.detail.trim(),
    ];

    return Container(
      key: Key('cicd-check-${check.id}'),
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppCyberTheme.lineBlue.withValues(alpha: 0.22),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_ciCdStatusIcon(check.status), size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        check.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppCyberTheme.dataTextStyle(
                          size: 11.4,
                          color: AppCyberTheme.textPrimary,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CiCdStatusChip(status: check.status),
                  ],
                ),
                if (detailParts.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    detailParts.join(' - '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 10.4,
                      color: AppCyberTheme.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CiCdSetupOptionSelector extends StatelessWidget {
  const _CiCdSetupOptionSelector({required this.snapshot});

  final CiCdDependencySnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final group in CiCdSetupGroup.values) {
      final options = CiCdSetupCatalog.optionsForGroup(group)
          .where((option) {
            if (snapshot == null) return true;
            return _ciCdChecksForOption(snapshot!, option).isNotEmpty;
          })
          .toList(growable: false);
      if (options.isEmpty) continue;
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      children.add(_CiCdSetupGroupHeader(group: group, options: options));
      children.add(const SizedBox(height: 4));
      for (final option in options) {
        children.add(_CiCdSetupOptionTile(option: option, snapshot: snapshot));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _CiCdSetupGroupHeader extends GetView<HomeController> {
  const _CiCdSetupGroupHeader({required this.group, required this.options});

  final CiCdSetupGroup group;
  final List<CiCdSetupOption> options;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selectedIds = controller.selectedCiCdSetupOptionIds;
      final selectedCount = options
          .where((option) => selectedIds.contains(option.id))
          .length;
      final selected = selectedCount == options.length
          ? true
          : selectedCount == 0
          ? false
          : null;
      return InkWell(
        key: Key('cicd-group-${group.name}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          controller.setCiCdSetupGroupSelected(group, selected != true);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Checkbox(
                tristate: true,
                value: selected,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onChanged: (value) {
                  controller.setCiCdSetupGroupSelected(group, value ?? true);
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  group.label,
                  style: AppCyberTheme.dataTextStyle(
                    size: 11.6,
                    color: AppCyberTheme.textPrimary,
                    weight: FontWeight.w900,
                  ),
                ),
              ),
              _MetaChip(
                icon: Icons.checklist_outlined,
                label: '$selectedCount/${options.length}',
                highlighted: selectedCount > 0,
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _CiCdSetupOptionTile extends GetView<HomeController> {
  const _CiCdSetupOptionTile({required this.option, required this.snapshot});

  final CiCdSetupOption option;
  final CiCdDependencySnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final checks = snapshot == null
        ? const <CiCdDependencyCheck>[]
        : _ciCdChecksForOption(snapshot!, option);
    final status = _ciCdOptionStatus(checks);
    final detail = _ciCdOptionDetail(option, checks);

    return Obx(() {
      final selected = controller.selectedCiCdSetupOptionIds.contains(
        option.id,
      );
      return InkWell(
        key: Key('cicd-option-${option.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => controller.toggleCiCdSetupOption(option.id, !selected),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: AppCyberTheme.lineBlue.withValues(alpha: 0.18),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onChanged: (value) {
                  controller.toggleCiCdSetupOption(option.id, value ?? true);
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            option.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppCyberTheme.dataTextStyle(
                              size: 11.2,
                              color: AppCyberTheme.textPrimary,
                              weight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (status != null) ...[
                          const SizedBox(width: 8),
                          _CiCdStatusChip(status: status),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppCyberTheme.dataTextStyle(
                        size: 10.2,
                        color: AppCyberTheme.textMuted,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _CiCdInstallStepTile extends GetView<HomeController> {
  const _CiCdInstallStepTile({required this.step});

  final CiCdInstallStep step;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isBusy =
          controller.runner.isBusy ||
          controller.isRunningCiCdInstallStep.value ||
          controller.isCheckingCiCdDependencies.value;

      return Container(
        key: Key('cicd-step-${step.id}'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AppCyberTheme.lineBlue.withValues(alpha: 0.22),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  step.isManual
                      ? Icons.open_in_new_outlined
                      : Icons.terminal_outlined,
                  size: 18,
                  color: AppCyberTheme.electricBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppCyberTheme.dataTextStyle(
                          size: 11.4,
                          color: AppCyberTheme.textPrimary,
                          weight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _CiCdCommandPreview(command: step.commandPreview),
                    ],
                  ),
                ),
              ],
            ),
            if (step.description.trim().isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                step.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppCyberTheme.dataTextStyle(
                  size: 10.2,
                  color: AppCyberTheme.textMuted,
                  weight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerRight,
              child: step.isManual
                  ? OutlinedButton.icon(
                      key: Key('cicd-open-${step.id}'),
                      onPressed: isBusy
                          ? null
                          : () => controller.openCiCdInstallFallback(step),
                      icon: const Icon(Icons.open_in_new_outlined),
                      label: const Text('Mở hướng dẫn'),
                    )
                  : FilledButton.tonalIcon(
                      key: Key('cicd-run-${step.id}'),
                      onPressed: isBusy
                          ? null
                          : () => _confirmCiCdInstallStep(context, step),
                      icon: const Icon(Icons.play_arrow_outlined),
                      label: const Text('Chạy'),
                    ),
            ),
          ],
        ),
      );
    });
  }
}

class _CiCdSetupLogs extends GetView<HomeController> {
  const _CiCdSetupLogs();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final logs = controller.runner.logLines.toList(growable: false);
      final visibleLogs = logs.length > 8
          ? logs.sublist(logs.length - 8)
          : logs;

      return _HudCardShell(
        active: controller.runner.isRunning.value,
        padding: const EdgeInsets.all(10),
        child: Column(
          key: const Key('cicd-setup-log-preview'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelTitle(icon: Icons.subject_outlined, title: 'Log'),
            const SizedBox(height: 8),
            if (visibleLogs.isEmpty)
              const _CiCdEmptyState(
                icon: Icons.notes_outlined,
                message: 'Log sẽ hiện ở đây khi các bước thiết lập chạy.',
              )
            else
              ...visibleLogs.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 10.2,
                      color: AppCyberTheme.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _CiCdStatusChip extends StatelessWidget {
  const _CiCdStatusChip({required this.status});

  final CiCdDependencyStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _ciCdStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppCyberTheme.isCyber ? 0.13 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.label,
        style: AppCyberTheme.dataTextStyle(
          size: 9.8,
          color: color,
          weight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CiCdCommandPreview extends StatelessWidget {
  const _CiCdCommandPreview({required this.command});

  final String command;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppCyberTheme.panelBackgroundStrong.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppCyberTheme.lineBlue.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        command,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppCyberTheme.dataTextStyle(
          size: 10.1,
          color: AppCyberTheme.textPrimary,
          weight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CiCdEmptyState extends StatelessWidget {
  const _CiCdEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppCyberTheme.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: AppCyberTheme.dataTextStyle(
              size: 10.8,
              color: AppCyberTheme.textMuted,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _confirmCiCdInstallStep(
  BuildContext context,
  CiCdInstallStep step,
) async {
  final controller = Get.find<HomeController>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(step.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Xem trước lệnh'),
            const SizedBox(height: 8),
            _CiCdCommandPreview(command: step.commandPreview),
            if (step.workingDirectory.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Thư mục làm việc: ${step.workingDirectory}'),
            ],
            if (step.requiresConfirmation) ...[
              const SizedBox(height: 10),
              const Text(
                'Việc này có thể cài công cụ, cập nhật package, hoặc mở prompt hỏi đáp.',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.play_arrow_outlined),
            label: const Text('Chạy'),
          ),
        ],
      );
    },
  );
  if (confirmed == true) {
    await controller.runCiCdInstallStep(step);
  }
}

List<CiCdDependencyCheck> _ciCdChecksForOption(
  CiCdDependencySnapshot snapshot,
  CiCdSetupOption option,
) {
  return snapshot.checks
      .where((check) => option.coversCheck(check.id))
      .toList(growable: false);
}

CiCdDependencyStatus? _ciCdOptionStatus(List<CiCdDependencyCheck> checks) {
  if (checks.isEmpty) return null;
  const priority = [
    CiCdDependencyStatus.error,
    CiCdDependencyStatus.outdated,
    CiCdDependencyStatus.missing,
    CiCdDependencyStatus.manual,
    CiCdDependencyStatus.unsupported,
    CiCdDependencyStatus.installed,
  ];
  for (final status in priority) {
    if (checks.any((check) => check.status == status)) return status;
  }
  return checks.first.status;
}

String _ciCdOptionDetail(
  CiCdSetupOption option,
  List<CiCdDependencyCheck> checks,
) {
  if (checks.isEmpty) return option.description;
  final primary = checks.firstWhere(
    (check) => check.isActionable,
    orElse: () => checks.first,
  );
  final detailParts = [
    option.description,
    if (primary.version.trim().isNotEmpty) primary.version.trim(),
    if (primary.detail.trim().isNotEmpty) primary.detail.trim(),
  ];
  return detailParts.join(' - ');
}

Color _ciCdStatusColor(CiCdDependencyStatus status) {
  return switch (status) {
    CiCdDependencyStatus.installed => AppCyberTheme.neonGreen,
    CiCdDependencyStatus.missing => Colors.orangeAccent,
    CiCdDependencyStatus.outdated => Colors.amberAccent,
    CiCdDependencyStatus.manual => AppCyberTheme.electricBlue,
    CiCdDependencyStatus.unsupported => AppCyberTheme.textMuted,
    CiCdDependencyStatus.error => Colors.redAccent,
  };
}

IconData _ciCdStatusIcon(CiCdDependencyStatus status) {
  return switch (status) {
    CiCdDependencyStatus.installed => Icons.check_circle_outline,
    CiCdDependencyStatus.missing => Icons.error_outline,
    CiCdDependencyStatus.outdated => Icons.update_outlined,
    CiCdDependencyStatus.manual => Icons.touch_app_outlined,
    CiCdDependencyStatus.unsupported => Icons.block_outlined,
    CiCdDependencyStatus.error => Icons.report_gmailerrorred_outlined,
  };
}

String _ciCdCheckedAtLabel(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

class _PlayUploadOptions extends GetView<HomeController> {
  const _PlayUploadOptions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isSkipped =
          controller.playUploadChoice.value == PlayUploadChoice.skip;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Upload CH Play', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<PlayUploadChoice>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: PlayUploadChoice.ask,
                  icon: Icon(Icons.help_outline),
                  label: Text('Hỏi'),
                ),
                ButtonSegment(
                  value: PlayUploadChoice.upload,
                  icon: Icon(Icons.cloud_upload_outlined),
                  label: Text('Upload'),
                ),
                ButtonSegment(
                  value: PlayUploadChoice.skip,
                  icon: Icon(Icons.block_outlined),
                  label: Text('Bỏ qua'),
                ),
              ],
              selected: {controller.playUploadChoice.value},
              onSelectionChanged: (selected) {
                controller.playUploadChoice.value = selected.first;
              },
            ),
          ),
          const SizedBox(height: 10),
          AnimatedOpacity(
            opacity: isSkipped ? 0.55 : 1,
            duration: const Duration(milliseconds: 160),
            child: TextField(
              controller: controller.releaseNotesController,
              enabled: !isSkipped,
              maxLines: 5,
              style: AppCyberTheme.dataTextStyle(
                size: 11.5,
                color: AppCyberTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Release note',
                alignLabelWithHint: true,
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _PlayImageOptions extends GetView<HomeController> {
  const _PlayImageOptions({required this.project});

  final ReleaseProject project;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            value: controller.uploadPlayListingImages.value,
            onChanged:
                controller.playUploadChoice.value != PlayUploadChoice.skip
                ? (value) {
                    controller.uploadPlayListingImages.value = value ?? true;
                  }
                : null,
            contentPadding: EdgeInsets.zero,
            title: const Text('Upload ảnh Play và icon app'),
            subtitle: const Text(
              'Gồm icon, feature graphic và ảnh chụp màn hình.',
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (project.imageValidator != null) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              value: controller.validatePlayImages.value,
              onChanged:
                  controller.playUploadChoice.value != PlayUploadChoice.skip &&
                      controller.uploadPlayListingImages.value
                  ? (value) {
                      controller.validatePlayImages.value = value ?? true;
                    }
                  : null,
              contentPadding: EdgeInsets.zero,
              title: const Text('Kiểm tra ảnh Play trước'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: controller.runner.isBusy
                    ? null
                    : controller.validateImages,
                icon: const Icon(Icons.image_search_outlined),
                label: const Text('Kiểm tra ảnh'),
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _CustomScriptArguments extends GetView<HomeController> {
  const _CustomScriptArguments();

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller.customArgsController,
      style: AppCyberTheme.dataTextStyle(
        size: 11.5,
        color: AppCyberTheme.textPrimary,
      ),
      decoration: const InputDecoration(
        labelText: 'Tham số script tuỳ chỉnh',
        prefixIcon: Icon(Icons.code_outlined),
      ),
    );
  }
}

class _CommandInputDock extends GetView<HomeController> {
  const _CommandInputDock();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isRunning = controller.runner.isRunning.value;
      final prompt = controller.runner.yesNoPrompt.value;

      return _HudCardShell(
        active: isRunning || prompt != null,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PanelTitle(icon: Icons.keyboard_outlined, title: 'Nhập'),
            const SizedBox(height: 10),
            if (prompt != null)
              _YesNoPromptActions(prompt: prompt)
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller.stdinController,
                      enabled: isRunning,
                      onSubmitted: (_) => controller.sendInput(),
                      style: AppCyberTheme.dataTextStyle(
                        size: 11.5,
                        color: AppCyberTheme.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Gửi cho script',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Gửi',
                    onPressed: isRunning ? controller.sendInput : null,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.clearLog,
                    icon: const Icon(Icons.clear_all_outlined),
                    label: const Text('Xoá log'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: isRunning ? controller.stopRun : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Dừng'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class _AiReleaseNotesOptions extends GetView<HomeController> {
  const _AiReleaseNotesOptions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isGenerating = controller.isGeneratingReleaseNotes.value;
      final isBusy =
          isGenerating ||
          controller.isSendingTelegram.value ||
          controller.isConnectingGoogleDrive.value ||
          controller.isTestingGoogleDrive.value ||
          controller.isUploadingGoogleDriveApk.value ||
          controller.runner.isBusy;
      final canSave = controller.hasGeminiApiKey.value && !isBusy;
      final canGenerate =
          controller.project.value != null &&
          controller.hasGeminiApiKey.value &&
          !controller.runner.isBusy &&
          !isBusy;

      return _HudCardShell(
        active: isBusy,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelTitle(
              icon: Icons.auto_awesome_outlined,
              title: 'Release note AI',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller.geminiApiKeyController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              style: AppCyberTheme.dataTextStyle(
                size: 11.5,
                color: AppCyberTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Gemini API key',
                prefixIcon: Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller.releaseNotePromptController,
              minLines: 3,
              maxLines: 5,
              style: AppCyberTheme.dataTextStyle(
                size: 11.3,
                color: AppCyberTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Prompt tuỳ chỉnh',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.edit_note_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: canSave ? controller.saveGeminiApiKey : null,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Lưu API key'),
                ),
                FilledButton.icon(
                  onPressed: canGenerate
                      ? controller.generateReleaseNotes
                      : null,
                  icon: isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Tạo'),
                ),
              ],
            ),
            if (controller.releaseNoteAiStatus.value.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                controller.releaseNoteAiStatus.value,
                style: AppCyberTheme.dataTextStyle(
                  size: 10.6,
                  color: AppCyberTheme.textMuted,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _GoogleDriveFallbackOptions extends GetView<HomeController> {
  const _GoogleDriveFallbackOptions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final settings = controller.googleDriveReleaseSettings.value;
      final isDriveBusy =
          controller.isConnectingGoogleDrive.value ||
          controller.isTestingGoogleDrive.value ||
          controller.isUploadingGoogleDriveApk.value;
      final isBusy =
          controller.isGeneratingReleaseNotes.value ||
          controller.isSendingTelegram.value ||
          isDriveBusy ||
          controller.runner.isBusy;
      final hasTelegramConfiguration =
          controller.hasTelegramBotToken.value &&
          controller.hasTelegramChatId.value;
      final hasDriveConfiguration =
          controller.hasGoogleDriveOAuthClientId.value &&
          controller.hasGoogleDriveCredentials.value;
      final canToggleDriveFallback =
          !isBusy &&
          (!settings.useDriveFallbackEnabled ||
              (hasTelegramConfiguration && hasDriveConfiguration));
      final canToggleDriveTelegramLink =
          !isBusy &&
          (!settings.sendApkLinkToTelegramEnabled ||
              (hasTelegramConfiguration && hasDriveConfiguration));
      final canUploadApkToDrive =
          controller.project.value != null && hasDriveConfiguration && !isBusy;

      return _HudCardShell(
        active: isDriveBusy,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_sync_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Gửi APK qua Google Drive',
                    style: AppCyberTheme.dataTextStyle(
                      size: 11.8,
                      color: AppCyberTheme.textPrimary,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
                _MetaChip(
                  icon: controller.hasGoogleDriveCredentials.value
                      ? Icons.check_circle_outline
                      : Icons.link_off_outlined,
                  label: controller.hasGoogleDriveCredentials.value
                      ? 'Đã kết nối'
                      : 'Chưa kết nối',
                  highlighted: controller.hasGoogleDriveCredentials.value,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller.googleDriveOAuthClientIdController,
              enabled: !isBusy,
              enableSuggestions: false,
              autocorrect: false,
              style: AppCyberTheme.dataTextStyle(
                size: 11.5,
                color: AppCyberTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Google OAuth Client ID',
                prefixIcon: Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller.googleDriveOAuthClientSecretController,
              obscureText: true,
              enabled: !isBusy,
              enableSuggestions: false,
              autocorrect: false,
              style: AppCyberTheme.dataTextStyle(
                size: 11.5,
                color: AppCyberTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Google OAuth Client Secret (không bắt buộc)',
                helperText:
                    'Chỉ cần khi Google từ chối đổi token với lỗi client_secret is missing.',
                prefixIcon: Icon(Icons.password_outlined),
              ),
            ),
            SwitchListTile.adaptive(
              value: settings.useDriveFallbackEnabled,
              onChanged: canToggleDriveFallback
                  ? controller.setGoogleDriveFallbackEnabled
                  : null,
              contentPadding: EdgeInsets.zero,
              title: const Text('Dùng Drive cho APK trên 50 MB'),
              subtitle: const Text(
                'APK quá lớn thì upload lên Drive rồi gửi link qua Telegram.',
              ),
            ),
            SwitchListTile.adaptive(
              value: settings.sendApkLinkToTelegramEnabled,
              onChanged: canToggleDriveTelegramLink
                  ? controller.setGoogleDriveApkLinkTelegramEnabled
                  : null,
              contentPadding: EdgeInsets.zero,
              title: const Text('Gửi link Drive qua Telegram'),
              subtitle: const Text(
                'Build/Upload APK và bước gửi sau deploy sẽ upload lên Drive rồi gửi link.',
              ),
            ),
            CheckboxListTile(
              value: settings.includeReleaseNotesInTelegramLink,
              onChanged: !isBusy && settings.sendApkLinkToTelegramEnabled
                  ? (value) => controller
                        .setGoogleDriveLinkReleaseNotesIncluded(value ?? false)
                  : null,
              contentPadding: EdgeInsets.zero,
              title: const Text('Kèm release note'),
              subtitle: const Text(
                'Thêm nội dung Release note hiện tại vào tin nhắn link trên Telegram.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Upload Drive thủ công dùng APK release mới nhất nếu có; không thì build APK release mới trước.',
                style: AppCyberTheme.dataTextStyle(
                  size: 10.2,
                  color: AppCyberTheme.textMuted,
                  weight: FontWeight.w500,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: !isBusy
                      ? controller.saveGoogleDriveConfiguration
                      : null,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Lưu Drive'),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      controller.hasGoogleDriveOAuthClientId.value && !isBusy
                      ? controller.connectGoogleDrive
                      : null,
                  icon: controller.isConnectingGoogleDrive.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_outlined),
                  label: const Text('Kết nối Drive'),
                ),
                OutlinedButton.icon(
                  onPressed: hasDriveConfiguration && !isBusy
                      ? controller.testGoogleDriveConnection
                      : null,
                  icon: controller.isTestingGoogleDrive.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_outlined),
                  label: const Text('Thử Drive'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      controller.hasGoogleDriveCredentials.value && !isBusy
                      ? controller.disconnectGoogleDrive
                      : null,
                  icon: const Icon(Icons.link_off_outlined),
                  label: const Text('Ngắt kết nối'),
                ),
                FilledButton.icon(
                  onPressed: canUploadApkToDrive
                      ? controller.buildOrUploadReleaseApkToGoogleDrive
                      : null,
                  icon: controller.isUploadingGoogleDriveApk.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Build/Upload APK'),
                ),
              ],
            ),
            if (controller.googleDriveReleaseStatus.value.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                controller.googleDriveReleaseStatus.value,
                style: AppCyberTheme.dataTextStyle(
                  size: 10.6,
                  color: AppCyberTheme.textMuted,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _ResourceOptions extends GetView<HomeController> {
  const _ResourceOptions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return Column(
        key: const Key('resource-options'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.inventory_2_outlined,
            title: 'Tài nguyên',
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<ResourcePanelMode>(
              key: const Key('resource-panel-mode'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ResourcePanelMode.catalog,
                  icon: Icon(Icons.view_list_outlined, size: 16),
                  label: Text('Danh mục'),
                ),
                ButtonSegment(
                  value: ResourcePanelMode.collector,
                  icon: Icon(Icons.archive_outlined, size: 16),
                  label: Text('Thu gom'),
                ),
              ],
              selected: {controller.resourcePanelMode.value},
              onSelectionChanged: (selected) =>
                  controller.setResourcePanelMode(selected.first),
            ),
          ),
          const SizedBox(height: 10),
          if (controller.resourcePanelMode.value == ResourcePanelMode.catalog)
            const _ResourceCatalogOptions()
          else
            const _ResourceCollectorOptions(),
        ],
      );
    });
  }
}

class _ResourceCollectorOptions extends GetView<HomeController> {
  const _ResourceCollectorOptions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final findings = controller.resourceFindings.toList();
      final selectedIds = controller.selectedResourceFindingIds.toSet();
      final isBusy =
          controller.isScanningResources.value ||
          controller.isExportingResources.value;
      final selectedCount = findings
          .where((finding) => selectedIds.contains(finding.id))
          .length;
      final hasSigningFindings = controller.resourceSigningFindings.isNotEmpty;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HudCardShell(
            active: controller.isScanningResources.value,
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ResourcePathField(
                  key: const Key('resource-source-path'),
                  controller: controller.resourceSourcePathController,
                  label: 'Thư mục nguồn',
                  icon: Icons.folder_open_outlined,
                  onPick: isBusy
                      ? null
                      : controller.pickResourceSourceDirectory,
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<ResourceCollectionPreset>(
                    key: const Key('resource-preset-selector'),
                    showSelectedIcon: false,
                    segments: [
                      for (final preset in ResourceCollectionPreset.values)
                        ButtonSegment(
                          value: preset,
                          icon: Icon(_resourcePresetIcon(preset), size: 16),
                          label: Text(preset.label),
                        ),
                    ],
                    selected: {controller.resourcePreset.value},
                    onSelectionChanged: isBusy
                        ? null
                        : (selected) =>
                              controller.setResourcePreset(selected.first),
                  ),
                ),
                if (controller.resourcePreset.value ==
                    ResourceCollectionPreset.custom) ...[
                  const SizedBox(height: 8),
                  for (final kind in ResourceTargetKind.values)
                    CheckboxListTile(
                      key: Key('resource-kind-${kind.name}'),
                      value: controller.resourceCustomKinds.contains(kind),
                      onChanged: isBusy
                          ? null
                          : (value) => controller.toggleResourceTargetKind(
                              kind,
                              value ?? false,
                            ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(kind.label),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('resource-scan'),
                        onPressed: isBusy ? null : controller.scanResources,
                        icon: controller.isScanningResources.value
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.manage_search_outlined),
                        label: const Text('Quét'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('resource-select-all'),
                        onPressed:
                            findings.isEmpty ||
                                isBusy ||
                                selectedCount == findings.length
                            ? null
                            : () => controller.setAllResourceFindingsSelected(
                                true,
                              ),
                        icon: const Icon(Icons.check_box_outlined),
                        label: const Text('Tất cả'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      key: const Key('resource-clear-selection'),
                      tooltip: 'Bỏ chọn tất cả',
                      onPressed:
                          findings.isEmpty || isBusy || selectedCount == 0
                          ? null
                          : () => controller.setAllResourceFindingsSelected(
                              false,
                            ),
                      icon: const Icon(Icons.check_box_outline_blank),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _HudCardShell(
            active: controller.isExportingResources.value,
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ResourcePathField(
                  key: const Key('resource-target-path'),
                  controller: controller.resourceTargetPathController,
                  label: 'Thư mục xuất',
                  icon: Icons.drive_folder_upload_outlined,
                  onPick: isBusy
                      ? null
                      : controller.pickResourceTargetDirectory,
                ),
                if (hasSigningFindings) ...[
                  const SizedBox(height: 10),
                  _ResourceSigningCredentialOptions(isBusy: isBusy),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('resource-export-bundle'),
                        onPressed: controller.canExportResourceBundle
                            ? _export
                            : null,
                        icon: controller.isExportingResources.value
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.archive_outlined),
                        label: Text(
                          selectedCount > 0 ? 'Zip $selectedCount' : 'Zip',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (controller.resourceStatus.value.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              controller.resourceStatus.value,
              style: AppCyberTheme.dataTextStyle(
                size: 10.6,
                color: AppCyberTheme.textMuted,
                weight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (findings.isEmpty)
            _HudCardShell(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  const Icon(Icons.search_off_outlined, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chưa quét được file tài nguyên nào',
                      style: AppCyberTheme.dataTextStyle(
                        size: 10.8,
                        color: AppCyberTheme.textMuted,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                for (final finding in findings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ResourceFindingTile(
                      finding: finding,
                      selected: selectedIds.contains(finding.id),
                      onChanged: isBusy
                          ? null
                          : (value) => controller.toggleResourceFinding(
                              finding,
                              value ?? false,
                            ),
                    ),
                  ),
              ],
            ),
        ],
      );
    });
  }

  Future<void> _export() async {
    await controller.exportResources();
  }
}

class _ResourceCatalogOptions extends GetView<HomeController> {
  const _ResourceCatalogOptions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final resources = controller.filteredResourceCatalogItems;
      final passwords = controller.filteredResourcePasswordEntries;
      final hasProject = controller.canUseResourceCatalog;
      final isBusy = controller.isResourceCatalogBusy;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HudCardShell(
            active: isBusy,
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                TextField(
                  key: const Key('resource-catalog-search'),
                  controller: controller.resourceCatalogSearchController,
                  enabled: hasProject,
                  style: AppCyberTheme.dataTextStyle(
                    size: 11.3,
                    color: AppCyberTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Tìm trong danh mục',
                    prefixIcon: Icon(Icons.search_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ResourceCatalogKind?>(
                  key: const Key('resource-catalog-kind-filter'),
                  initialValue: controller.selectedResourceCatalogKind.value,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Loại',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<ResourceCatalogKind?>(
                      value: null,
                      child: Text('Mọi loại'),
                    ),
                    for (final kind in ResourceCatalogKind.values)
                      DropdownMenuItem<ResourceCatalogKind?>(
                        value: kind,
                        child: Text(kind.label),
                      ),
                  ],
                  onChanged: hasProject
                      ? controller.setResourceCatalogKindFilter
                      : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('resource-catalog-add-resource'),
                        onPressed: hasProject && !isBusy
                            ? () => _editResource(context)
                            : null,
                        icon: const Icon(Icons.add_link_outlined),
                        label: const Text('Tài nguyên'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('resource-catalog-add-password'),
                        onPressed: hasProject && !isBusy
                            ? () => _editPassword(context)
                            : null,
                        icon: const Icon(Icons.password_outlined),
                        label: const Text('Mật khẩu'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('resource-catalog-import'),
                        onPressed: hasProject && !isBusy
                            ? controller.importResourceCatalogExcel
                            : null,
                        icon: controller.isImportingResourceCatalog.value
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file_outlined),
                        label: const Text('Nhập'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('resource-catalog-export'),
                        onPressed: hasProject && !isBusy
                            ? controller.exportResourceCatalogExcel
                            : null,
                        icon: controller.isExportingResourceCatalog.value
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_outlined),
                        label: const Text('Xuất'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (controller.resourceCatalogStatus.value.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              controller.resourceCatalogStatus.value,
              style: AppCyberTheme.dataTextStyle(
                size: 10.6,
                color: AppCyberTheme.textMuted,
                weight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (!hasProject)
            _ResourceEmptyState(
              icon: Icons.folder_open_outlined,
              label: 'Chọn một dự án để quản lý danh mục',
            )
          else ...[
            _ResourceCatalogSectionHeader(
              icon: Icons.link_outlined,
              label: 'Tài nguyên',
              count: resources.length,
            ),
            const SizedBox(height: 8),
            if (resources.isEmpty)
              const _ResourceEmptyState(
                icon: Icons.link_off_outlined,
                label: 'Danh mục chưa có tài nguyên nào',
              )
            else
              for (final item in resources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ResourceCatalogItemTile(
                    item: item,
                    onEdit: () => _editResource(context, item),
                  ),
                ),
            const SizedBox(height: 2),
            _ResourceCatalogSectionHeader(
              icon: Icons.password_outlined,
              label: 'Mật khẩu',
              count: passwords.length,
            ),
            const SizedBox(height: 8),
            if (passwords.isEmpty)
              const _ResourceEmptyState(
                icon: Icons.no_encryption_outlined,
                label: 'Chưa có mật khẩu nào',
              )
            else
              for (final entry in passwords)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ResourcePasswordEntryTile(
                    entry: entry,
                    onEdit: () => _editPassword(context, entry),
                  ),
                ),
          ],
        ],
      );
    });
  }

  Future<void> _editResource(
    BuildContext context, [
    ResourceCatalogItem? item,
  ]) async {
    final result = await showDialog<ResourceCatalogItem>(
      context: context,
      builder: (_) => _ResourceCatalogItemDialog(item: item),
    );
    if (result != null) {
      await controller.upsertResourceCatalogItem(result);
    }
  }

  Future<void> _editPassword(
    BuildContext context, [
    ResourcePasswordEntry? entry,
  ]) async {
    final result = await showDialog<_ResourcePasswordDialogResult>(
      context: context,
      builder: (_) => _ResourcePasswordEntryDialog(entry: entry),
    );
    if (result != null) {
      await controller.upsertResourcePasswordEntry(
        result.entry,
        password: result.password,
      );
    }
  }
}

class _ResourceCatalogSectionHeader extends StatelessWidget {
  const _ResourceCatalogSectionHeader({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppCyberTheme.textMuted),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppCyberTheme.dataTextStyle(
            size: 11.3,
            color: AppCyberTheme.textPrimary,
            weight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 6),
        _MetaChip(icon: Icons.tag_outlined, label: count.toString()),
      ],
    );
  }
}

class _ResourceEmptyState extends StatelessWidget {
  const _ResourceEmptyState({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return _HudCardShell(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppCyberTheme.dataTextStyle(
                size: 10.8,
                color: AppCyberTheme.textMuted,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResourceCatalogItemTile extends GetView<HomeController> {
  const _ResourceCatalogItemTile({required this.item, required this.onEdit});

  final ResourceCatalogItem item;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final location = item.hasUrl ? item.url : item.localPath;

    return _HudCardShell(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_resourceCatalogKindIcon(item.kind), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 11.1,
                    color: AppCyberTheme.textPrimary,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MetaChip(
                      icon: _resourceCatalogKindIcon(item.kind),
                      label: item.kind.label,
                      highlighted: true,
                    ),
                    if (item.environment.trim().isNotEmpty)
                      _MetaChip(
                        icon: Icons.public_outlined,
                        label: item.environment,
                      ),
                    if (item.owner.trim().isNotEmpty)
                      _MetaChip(icon: Icons.person_outline, label: item.owner),
                  ],
                ),
                if (location.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 10.4,
                      color: AppCyberTheme.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.tags.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 10.2,
                      color: AppCyberTheme.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            children: [
              IconButton(
                tooltip: 'Mở tài nguyên',
                onPressed: location.trim().isEmpty
                    ? null
                    : () => controller.openResourceCatalogItem(item),
                icon: const Icon(Icons.open_in_new_outlined),
              ),
              IconButton(
                tooltip: 'Sao chép tài nguyên',
                onPressed: location.trim().isEmpty
                    ? null
                    : () => controller.copyResourceCatalogValue(location),
                icon: const Icon(Icons.copy_outlined),
              ),
              IconButton(
                tooltip: 'Sửa tài nguyên',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Xoá tài nguyên',
                onPressed: () => controller.deleteResourceCatalogItem(item),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResourcePasswordEntryTile extends GetView<HomeController> {
  const _ResourcePasswordEntryTile({required this.entry, required this.onEdit});

  final ResourcePasswordEntry entry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final revealed = controller.revealedResourcePasswordIds.contains(
        entry.id,
      );
      final password = controller.revealedResourcePasswords[entry.id] ?? '';

      return _HudCardShell(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.password_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.site,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 11.1,
                      color: AppCyberTheme.textPrimary,
                      weight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Table(
                    columnWidths: const {
                      0: FixedColumnWidth(82),
                      1: FlexColumnWidth(),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      _passwordTableRow('URL', entry.loginUrl),
                      _passwordTableRow('Tài khoản', entry.username),
                      _passwordTableRow(
                        'Mật khẩu',
                        revealed ? password : '********',
                      ),
                      _passwordTableRow('Môi trường', entry.environment),
                      _passwordTableRow('Người phụ trách', entry.owner),
                      _passwordTableRow('2FA', entry.twoFactorLocation),
                    ],
                  ),
                  if (entry.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      entry.tags.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppCyberTheme.dataTextStyle(
                        size: 10.2,
                        color: AppCyberTheme.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              children: [
                IconButton(
                  tooltip: 'Mở trang đăng nhập',
                  onPressed: entry.hasLoginUrl
                      ? () => controller.openResourcePasswordLogin(entry)
                      : null,
                  icon: const Icon(Icons.open_in_new_outlined),
                ),
                IconButton(
                  tooltip: 'Sao chép mật khẩu',
                  onPressed: () => controller.copyResourcePassword(entry),
                  icon: const Icon(Icons.copy_outlined),
                ),
                IconButton(
                  tooltip: revealed ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                  onPressed: () => revealed
                      ? controller.hideResourcePassword(entry.id)
                      : controller.revealResourcePassword(entry),
                  icon: Icon(
                    revealed
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
                IconButton(
                  tooltip: 'Sửa mật khẩu',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Xoá mật khẩu',
                  onPressed: () =>
                      controller.deleteResourcePasswordEntry(entry),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  TableRow _passwordTableRow(String label, String value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            label,
            style: AppCyberTheme.dataTextStyle(
              size: 10,
              color: AppCyberTheme.textMuted,
              weight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            value.trim().isEmpty ? '-' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppCyberTheme.dataTextStyle(
              size: 10.4,
              color: AppCyberTheme.textPrimary,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ResourceCatalogItemDialog extends StatefulWidget {
  const _ResourceCatalogItemDialog({this.item});

  final ResourceCatalogItem? item;

  @override
  State<_ResourceCatalogItemDialog> createState() =>
      _ResourceCatalogItemDialogState();
}

class _ResourceCatalogItemDialogState
    extends State<_ResourceCatalogItemDialog> {
  late ResourceCatalogKind _kind;
  late final TextEditingController _titleController;
  late final TextEditingController _urlController;
  late final TextEditingController _pathController;
  late final TextEditingController _environmentController;
  late final TextEditingController _ownerController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagsController;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _kind = item?.kind ?? ResourceCatalogKind.summaryLink;
    _titleController = TextEditingController(text: item?.title ?? '');
    _urlController = TextEditingController(text: item?.url ?? '');
    _pathController = TextEditingController(text: item?.localPath ?? '');
    _environmentController = TextEditingController(
      text: item?.environment ?? '',
    );
    _ownerController = TextEditingController(text: item?.owner ?? '');
    _notesController = TextEditingController(text: item?.notes ?? '');
    _tagsController = TextEditingController(text: item?.tags.join(', ') ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _pathController.dispose();
    _environmentController.dispose();
    _ownerController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Tài nguyên mới' : 'Sửa tài nguyên'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<ResourceCatalogKind>(
                initialValue: _kind,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Loại',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: [
                  for (final kind in ResourceCatalogKind.values)
                    DropdownMenuItem<ResourceCatalogKind>(
                      value: kind,
                      child: Text(kind.label),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _kind = value);
                },
              ),
              const SizedBox(height: 8),
              _dialogField(_titleController, 'Tiêu đề', Icons.title_outlined),
              const SizedBox(height: 8),
              _dialogField(_urlController, 'URL', Icons.link_outlined),
              const SizedBox(height: 8),
              _dialogField(
                _pathController,
                'Đường dẫn máy',
                Icons.folder_outlined,
              ),
              const SizedBox(height: 8),
              _dialogField(
                _environmentController,
                'Môi trường',
                Icons.public_outlined,
              ),
              const SizedBox(height: 8),
              _dialogField(
                _ownerController,
                'Người phụ trách',
                Icons.person_outline,
              ),
              const SizedBox(height: 8),
              _dialogField(_notesController, 'Ghi chú', Icons.notes_outlined),
              const SizedBox(height: 8),
              _dialogField(_tagsController, 'Tag', Icons.tag_outlined),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(onPressed: _save, child: const Text('Lưu')),
      ],
    );
  }

  Widget _dialogField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }

  void _save() {
    Navigator.of(context).pop(
      ResourceCatalogItem(
        id: widget.item?.id ?? '',
        kind: _kind,
        title: _titleController.text,
        url: _urlController.text,
        localPath: _pathController.text,
        environment: _environmentController.text,
        owner: _ownerController.text,
        notes: _notesController.text,
        tags: _tagsController.text.split(','),
        updatedAt: widget.item?.updatedAt ?? DateTime.now().toUtc(),
      ),
    );
  }
}

class _ResourcePasswordEntryDialog extends StatefulWidget {
  const _ResourcePasswordEntryDialog({this.entry});

  final ResourcePasswordEntry? entry;

  @override
  State<_ResourcePasswordEntryDialog> createState() =>
      _ResourcePasswordEntryDialogState();
}

class _ResourcePasswordEntryDialogState
    extends State<_ResourcePasswordEntryDialog> {
  late final TextEditingController _siteController;
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _environmentController;
  late final TextEditingController _ownerController;
  late final TextEditingController _twoFactorController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagsController;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _siteController = TextEditingController(text: entry?.site ?? '');
    _urlController = TextEditingController(text: entry?.loginUrl ?? '');
    _usernameController = TextEditingController(text: entry?.username ?? '');
    _passwordController = TextEditingController();
    _environmentController = TextEditingController(
      text: entry?.environment ?? '',
    );
    _ownerController = TextEditingController(text: entry?.owner ?? '');
    _twoFactorController = TextEditingController(
      text: entry?.twoFactorLocation ?? '',
    );
    _notesController = TextEditingController(text: entry?.notes ?? '');
    _tagsController = TextEditingController(text: entry?.tags.join(', ') ?? '');
  }

  @override
  void dispose() {
    _siteController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _environmentController.dispose();
    _ownerController.dispose();
    _twoFactorController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.entry == null ? 'Mật khẩu mới' : 'Sửa mật khẩu'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(_siteController, 'Trang', Icons.language_outlined),
              const SizedBox(height: 8),
              _dialogField(
                _urlController,
                'URL đăng nhập',
                Icons.link_outlined,
              ),
              const SizedBox(height: 8),
              _dialogField(
                _usernameController,
                'Tài khoản/email',
                Icons.person_outline,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu',
                  prefixIcon: Icon(Icons.password_outlined),
                ),
              ),
              const SizedBox(height: 8),
              _dialogField(
                _environmentController,
                'Môi trường',
                Icons.public_outlined,
              ),
              const SizedBox(height: 8),
              _dialogField(
                _ownerController,
                'Người phụ trách',
                Icons.person_outline,
              ),
              const SizedBox(height: 8),
              _dialogField(
                _twoFactorController,
                'Nơi lấy mã 2FA',
                Icons.verified_user_outlined,
              ),
              const SizedBox(height: 8),
              _dialogField(_notesController, 'Ghi chú', Icons.notes_outlined),
              const SizedBox(height: 8),
              _dialogField(_tagsController, 'Tag', Icons.tag_outlined),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(onPressed: _save, child: const Text('Lưu')),
      ],
    );
  }

  Widget _dialogField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }

  void _save() {
    final existing = widget.entry;
    final rawPassword = _passwordController.text;
    Navigator.of(context).pop(
      _ResourcePasswordDialogResult(
        entry: ResourcePasswordEntry(
          id: existing?.id ?? '',
          secretKey: existing?.secretKey ?? '',
          site: _siteController.text,
          loginUrl: _urlController.text,
          username: _usernameController.text,
          environment: _environmentController.text,
          owner: _ownerController.text,
          twoFactorLocation: _twoFactorController.text,
          notes: _notesController.text,
          tags: _tagsController.text.split(','),
          updatedAt: existing?.updatedAt ?? DateTime.now().toUtc(),
        ),
        password: existing != null && rawPassword.isEmpty ? null : rawPassword,
      ),
    );
  }
}

class _ResourcePasswordDialogResult {
  const _ResourcePasswordDialogResult({
    required this.entry,
    required this.password,
  });

  final ResourcePasswordEntry entry;
  final String? password;
}

class _ResourceSigningCredentialOptions extends GetView<HomeController> {
  const _ResourceSigningCredentialOptions({required this.isBusy});

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final signingFindings = controller.resourceSigningFindings;
      final selectedSigningFindings =
          controller.selectedResourceSigningFindings;
      final activeId = controller.activeResourceSigningFindingId.value;
      final activeCredential = controller.activeResourceSigningCredential;
      final includeEnabled = controller.canIncludeResourceSigningCredentials;
      final includeValue =
          controller.resourceIncludeSigningCredentials.value &&
          selectedSigningFindings.isNotEmpty;
      final status =
          activeCredential?.status ?? SigningCredentialStatus.missing;
      final statusLabel = activeCredential == null
          ? SigningCredentialStatus.missing.label
          : '${status.label} - ${activeCredential.source.label}';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            key: const Key('resource-include-signing-credentials'),
            value: includeValue,
            onChanged: isBusy || !includeEnabled
                ? null
                : controller.setResourceIncludeSigningCredentials,
            contentPadding: EdgeInsets.zero,
            title: const Text('Kèm thông tin ký'),
            subtitle: const Text(
              'Thêm signing_credentials.txt vào file ZIP thường.',
            ),
          ),
          if (signingFindings.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              key: const Key('resource-signing-file-selector'),
              initialValue: activeId.isEmpty ? null : activeId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'File ký',
                prefixIcon: Icon(Icons.vpn_key_outlined),
              ),
              items: [
                for (final finding in signingFindings)
                  DropdownMenuItem(
                    value: finding.id,
                    child: Text(
                      finding.relativePath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: isBusy
                  ? null
                  : controller.setActiveResourceSigningFinding,
            ),
            const SizedBox(height: 8),
            _MetaChip(
              icon: _signingCredentialStatusIcon(status),
              label: statusLabel,
              highlighted: status == SigningCredentialStatus.resolved,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('resource-key-alias'),
              controller: controller.resourceKeyAliasController,
              enabled: !isBusy && activeId.isNotEmpty,
              style: AppCyberTheme.dataTextStyle(
                size: 11.5,
                color: AppCyberTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Key alias',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('resource-store-password'),
              controller: controller.resourceStorePasswordController,
              enabled: !isBusy && activeId.isNotEmpty,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              style: AppCyberTheme.dataTextStyle(
                size: 11.5,
                color: AppCyberTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Mật khẩu store',
                prefixIcon: Icon(Icons.password_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('resource-key-password'),
              controller: controller.resourceKeyPasswordController,
              enabled: !isBusy && activeId.isNotEmpty,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              style: AppCyberTheme.dataTextStyle(
                size: 11.5,
                color: AppCyberTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Mật khẩu key',
                prefixIcon: Icon(Icons.password_outlined),
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _ResourcePathField extends StatelessWidget {
  const _ResourcePathField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    required this.onPick,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            style: AppCyberTheme.dataTextStyle(
              size: 11.3,
              color: AppCyberTheme.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: Icon(icon),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Chọn $label',
          onPressed: onPick,
          icon: const Icon(Icons.folder_open_outlined),
        ),
      ],
    );
  }
}

class _ResourceFindingTile extends StatelessWidget {
  const _ResourceFindingTile({
    required this.finding,
    required this.selected,
    required this.onChanged,
  });

  final ResourceFinding finding;
  final bool selected;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final keyNames = finding.detectedKeyNames.take(4).join(', ');
    final preview = finding.maskedPreview.take(3).toList();
    final signingStatus = finding.signingCredentialStatus;
    final signingSource = finding.signingCredentialSource;
    final signingPreview = finding.signingCredentialMaskedPreview
        .take(3)
        .toList();

    return _HudCardShell(
      active: selected,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(value: selected, onChanged: onChanged),
          const SizedBox(width: 4),
          Icon(
            _resourceKindIcon(finding.kind),
            size: 18,
            color: selected ? AppCyberTheme.neonGreen : AppCyberTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  finding.relativePath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 11.1,
                    color: AppCyberTheme.textPrimary,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MetaChip(
                      icon: _resourceKindIcon(finding.kind),
                      label: finding.kind.label,
                      highlighted: selected,
                    ),
                    _MetaChip(
                      icon: Icons.data_object_outlined,
                      label: _formatResourceBytes(finding.sizeBytes),
                    ),
                    if (finding.isBinary)
                      const _MetaChip(
                        icon: Icons.lock_outline,
                        label: 'Nhị phân',
                      ),
                    if (signingStatus != null)
                      _MetaChip(
                        icon: _signingCredentialStatusIcon(signingStatus),
                        label: signingSource == null
                            ? signingStatus.label
                            : '${signingStatus.label} - ${signingSource.label}',
                        highlighted:
                            signingStatus == SigningCredentialStatus.resolved,
                      ),
                  ],
                ),
                if (keyNames.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    keyNames,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 10.4,
                      color: AppCyberTheme.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final line in preview)
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppCyberTheme.dataTextStyle(
                        size: 10.1,
                        color: AppCyberTheme.textMuted,
                      ),
                    ),
                ],
                if (signingPreview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final line in signingPreview)
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppCyberTheme.dataTextStyle(
                        size: 10.1,
                        color: AppCyberTheme.textMuted,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TelegramReleaseOptions extends GetView<HomeController> {
  const _TelegramReleaseOptions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isTelegramBusy = controller.isSendingTelegram.value;
      final isBusy =
          controller.isGeneratingReleaseNotes.value ||
          isTelegramBusy ||
          controller.isConnectingGoogleDrive.value ||
          controller.isTestingGoogleDrive.value ||
          controller.isUploadingGoogleDriveApk.value ||
          controller.runner.isBusy;
      final hasTelegramConfiguration =
          controller.hasTelegramBotToken.value &&
          controller.hasTelegramChatId.value;
      final canSendNow =
          hasTelegramConfiguration &&
          controller.hasTelegramReleaseContext.value &&
          controller.hasReleaseNoteText.value &&
          !isBusy;

      return _HudCardShell(
        active: isTelegramBusy,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelTitle(icon: Icons.send_outlined, title: 'Telegram'),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.forum_outlined, size: 18),
                const SizedBox(width: 8),
                Text(
                  hasTelegramConfiguration ? 'Đã cấu hình' : 'Chưa cấu hình',
                  style: AppCyberTheme.dataTextStyle(
                    size: 11,
                    color: hasTelegramConfiguration
                        ? AppCyberTheme.neonGreen
                        : AppCyberTheme.textMuted,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller.telegramBotTokenController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              enabled: !isBusy,
              style: AppCyberTheme.dataTextStyle(
                size: 11.5,
                color: AppCyberTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Telegram bot token',
                prefixIcon: Icon(Icons.smart_toy_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller.telegramChatIdController,
              enabled: !isBusy,
              enableSuggestions: false,
              autocorrect: false,
              style: AppCyberTheme.dataTextStyle(
                size: 11.5,
                color: AppCyberTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Telegram chat ID',
                hintText: '-1001234567890 or @group_username',
                prefixIcon: Icon(Icons.forum_outlined),
              ),
            ),
            SwitchListTile.adaptive(
              value: controller.telegramReleaseSettings.value.autoSendEnabled,
              onChanged: isBusy ? null : controller.setTelegramAutoSendEnabled,
              contentPadding: EdgeInsets.zero,
              title: const Text('Tự động gửi cập nhật release'),
              subtitle: const Text(
                'Tự gửi note vừa tạo và APK sau khi deploy.',
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: !isBusy
                      ? controller.saveTelegramConfiguration
                      : null,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Lưu'),
                ),
                OutlinedButton.icon(
                  onPressed: hasTelegramConfiguration && !isBusy
                      ? controller.testTelegramConfiguration
                      : null,
                  icon: const Icon(Icons.wifi_tethering_outlined),
                  label: const Text('Thử'),
                ),
                FilledButton.tonalIcon(
                  onPressed: canSendNow
                      ? controller.sendCurrentReleaseNoteToTelegram
                      : null,
                  icon: isTelegramBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: const Text('Gửi ngay'),
                ),
              ],
            ),
            if (controller.telegramReleaseStatus.value.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                controller.telegramReleaseStatus.value,
                style: AppCyberTheme.dataTextStyle(
                  size: 10.6,
                  color: AppCyberTheme.textMuted,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _InstallerTelegramOptions extends GetView<HomeController> {
  const _InstallerTelegramOptions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isInstallerBusy = controller.isBuildingInstaller.value;
      final isBusy =
          controller.isGeneratingReleaseNotes.value ||
          controller.isSendingTelegram.value ||
          isInstallerBusy ||
          controller.isConnectingGoogleDrive.value ||
          controller.isTestingGoogleDrive.value ||
          controller.isUploadingGoogleDriveApk.value ||
          controller.runner.isBusy;
      final hasTelegramConfiguration =
          controller.hasTelegramBotToken.value &&
          controller.hasTelegramChatId.value;
      final hasDriveConfiguration =
          controller.hasGoogleDriveOAuthClientId.value &&
          controller.hasGoogleDriveCredentials.value;
      final isWindowsSupported =
          controller.releaseInstallerArtifacts.isWindowsSupported;
      final hasInstallerProject =
          controller.hasSelectedAppManagementCenterProject;
      final canBuild =
          isWindowsSupported &&
          hasInstallerProject &&
          hasTelegramConfiguration &&
          !isBusy;

      return KeyedSubtree(
        key: const Key('installer-telegram-options'),
        child: _HudCardShell(
          active: isInstallerBusy,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.install_desktop_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bộ cài Windows',
                      style: AppCyberTheme.dataTextStyle(
                        size: 11.8,
                        color: AppCyberTheme.textPrimary,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _MetaChip(
                    icon: hasDriveConfiguration
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    label: hasDriveConfiguration
                        ? 'Drive sẵn sàng'
                        : 'Drive tắt',
                    highlighted: hasDriveConfiguration,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaChip(
                    icon: isWindowsSupported
                        ? Icons.check_circle_outline
                        : Icons.block_outlined,
                    label: isWindowsSupported ? 'Windows' : 'Chỉ trên Windows',
                    highlighted: isWindowsSupported,
                  ),
                  _MetaChip(
                    icon: hasInstallerProject
                        ? Icons.inventory_2_outlined
                        : Icons.folder_off_outlined,
                    label: hasInstallerProject ? 'ARC repo' : 'Chọn repo ARC',
                    highlighted: hasInstallerProject,
                  ),
                  _MetaChip(
                    icon: hasTelegramConfiguration
                        ? Icons.forum_outlined
                        : Icons.sms_failed_outlined,
                    label: hasTelegramConfiguration
                        ? 'Telegram sẵn sàng'
                        : 'Thiếu Telegram',
                    highlighted: hasTelegramConfiguration,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('build-send-installer'),
                onPressed: canBuild
                    ? controller.buildAndSendWindowsInstallerToTelegram
                    : null,
                icon: isInstallerBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_to_mobile_outlined),
                label: const Text('Build/Gửi bộ cài'),
              ),
              if (controller.installerDeliveryStatus.value.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  controller.installerDeliveryStatus.value,
                  style: AppCyberTheme.dataTextStyle(
                    size: 10.6,
                    color: AppCyberTheme.textMuted,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }
}

class _RemoteControlOptions extends GetView<HomeController> {
  const _RemoteControlOptions();

  RemoteControlService get remote => Get.find<RemoteControlService>();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final settings = remote.settings.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.settings_remote_outlined,
            title: 'Điều khiển từ xa',
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: settings.enabled,
            onChanged: remote.setEnabled,
            contentPadding: EdgeInsets.zero,
            title: const Text('Trung chuyển lệnh từ điện thoại'),
            subtitle: Text(remote.agentStatus.value),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _showControlPairingDialog(context),
                icon: const Icon(Icons.qr_code_2_outlined),
                label: const Text('Ghép app điều khiển'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showAllowedRootsDialog(context),
                icon: const Icon(Icons.folder_special_outlined),
                label: const Text('Thư mục cho phép'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _HudCardShell(
            active: settings.enabled,
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 17,
                  color: settings.enabled
                      ? AppCyberTheme.neonGreen
                      : AppCyberTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    settings.allowedRoots.isEmpty
                        ? 'Shell chỉ chạy trong các thư mục dự án gần đây.'
                        : 'Thư mục shell: ${settings.allowedRoots.length}',
                    style: AppCyberTheme.dataTextStyle(
                      size: 10.8,
                      color: AppCyberTheme.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Future<void> _showControlPairingDialog(BuildContext context) async {
    final session = await controller.createPhonePairing();
    if (session == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _PhonePairingDialog(session: session),
    );
  }

  Future<void> _showAllowedRootsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _AllowedRootsDialog(),
    );
  }
}

class _AllowedRootsDialog extends StatefulWidget {
  const _AllowedRootsDialog();

  @override
  State<_AllowedRootsDialog> createState() => _AllowedRootsDialogState();
}

class _AllowedRootsDialogState extends State<_AllowedRootsDialog> {
  late final TextEditingController _controller;

  RemoteControlService get remote => Get.find<RemoteControlService>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: remote.settings.value.allowedRoots.join('\n'),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppCyberTheme.panelBackgroundStrong,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: AppCyberTheme.isCyber
              ? AppCyberTheme.electricBlue.withValues(alpha: 0.4)
              : AppCyberTheme.lineBlue,
        ),
      ),
      title: const _PanelTitle(
        icon: Icons.folder_special_outlined,
        title: 'Thư mục cho phép',
      ),
      content: SizedBox(
        width: 460,
        child: TextField(
          controller: _controller,
          minLines: 6,
          maxLines: 10,
          style: AppCyberTheme.dataTextStyle(
            size: 11.5,
            color: AppCyberTheme.textPrimary,
          ),
          decoration: const InputDecoration(
            labelText: 'Mỗi dòng một thư mục',
            alignLabelWithHint: true,
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await remote.saveAllowedRoots(
              _controller.text.split(RegExp(r'\r?\n')),
            );
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Lưu'),
        ),
      ],
    );
  }
}

class _NotificationOptions extends GetView<HomeController> {
  const _NotificationOptions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final settings = controller.notificationSettings.value;
      final devices = controller.linkedNotificationDevices.toList();
      final selectedDeviceIds = settings.selectedDeviceIds.toSet();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.notifications_active_outlined,
            title: 'Thông báo',
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: settings.enabled,
            onChanged: controller.setNotificationsEnabled,
            contentPadding: EdgeInsets.zero,
            title: const Text('Thông báo trạng thái lệnh'),
            subtitle: const Text(
              'Gửi trạng thái lệnh tới các điện thoại đã chọn.',
            ),
          ),
          TextField(
            controller: controller.notificationEndpointController,
            style: AppCyberTheme.dataTextStyle(
              size: 11.5,
              color: AppCyberTheme.textPrimary,
            ),
            decoration: const InputDecoration(
              labelText: 'Serverless endpoint',
              hintText: 'https://your-site.web.app/api',
              prefixIcon: Icon(Icons.cloud_queue_outlined),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller.notificationTokenController,
            obscureText: true,
            style: AppCyberTheme.dataTextStyle(
              size: 11.5,
              color: AppCyberTheme.textPrimary,
            ),
            decoration: const InputDecoration(
              labelText: 'Desktop API token',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: controller.saveNotificationConfiguration,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Lưu'),
              ),
              FilledButton.icon(
                onPressed: () => _showPhonePairingDialog(context),
                icon: const Icon(Icons.qr_code_2_outlined),
                label: const Text('Liên kết điện thoại'),
              ),
              OutlinedButton.icon(
                onPressed: controller.isLoadingNotificationDevices.value
                    ? null
                    : controller.refreshLinkedNotificationDevices,
                icon: controller.isLoadingNotificationDevices.value
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined),
                label: const Text('Làm mới thiết bị'),
              ),
              OutlinedButton.icon(
                onPressed: settings.hasSelectedDevices
                    ? controller.sendTestNotification
                    : null,
                icon: const Icon(Icons.send_to_mobile_outlined),
                label: const Text('Thử'),
              ),
            ],
          ),
          if (controller.notificationStatus.value.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              controller.notificationStatus.value,
              style: AppCyberTheme.dataTextStyle(
                size: 10.8,
                color: AppCyberTheme.textMuted,
                weight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (devices.isEmpty)
            Text(
              'Chưa liên kết điện thoại nào',
              style: AppCyberTheme.dataTextStyle(
                size: 11,
                color: AppCyberTheme.textMuted,
              ),
            )
          else
            Column(
              children: devices.map((device) {
                final selected = selectedDeviceIds.contains(device.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _HudCardShell(
                    active: selected,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: selected,
                          onChanged: (value) =>
                              controller.toggleNotificationDevice(
                                device.id,
                                value ?? false,
                              ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.phone_iphone_outlined,
                          size: 18,
                          color: selected
                              ? AppCyberTheme.neonGreen
                              : AppCyberTheme.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppCyberTheme.dataTextStyle(
                                  size: 11.4,
                                  color: AppCyberTheme.textPrimary,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                device.detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppCyberTheme.dataTextStyle(
                                  size: 10.4,
                                  color: AppCyberTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Bỏ liên kết',
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              controller.unlinkNotificationDevice(device),
                          icon: const Icon(Icons.link_off_outlined),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      );
    });
  }

  Future<void> _showPhonePairingDialog(BuildContext context) async {
    final session = await controller.createPhonePairing();
    if (session == null || !context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => _PhonePairingDialog(session: session),
    );
  }
}

class _PhonePairingDialog extends StatefulWidget {
  const _PhonePairingDialog({required this.session});

  final NotificationPairingSession session;

  @override
  State<_PhonePairingDialog> createState() => _PhonePairingDialogState();
}

class _PhonePairingDialogState extends State<_PhonePairingDialog> {
  Timer? _pollTimer;
  Timer? _countdownTimer;
  bool _isPolling = false;
  NotificationPairingStatus _status = NotificationPairingStatus.pending;
  LinkedNotificationDevice? _device;
  Duration _initialRemaining = Duration.zero;
  Duration _remaining = Duration.zero;

  HomeController get controller => Get.find<HomeController>();

  @override
  void initState() {
    super.initState();
    _remaining = _remainingUntilExpiry();
    _initialRemaining = _remaining;
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _syncRemaining(),
    );
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    unawaited(_poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (_status) {
      NotificationPairingStatus.pending => 'Đang chờ điện thoại',
      NotificationPairingStatus.linked => 'Linked ${_device?.label ?? ''}',
      NotificationPairingStatus.expired => 'Mã ghép đã hết hạn',
    };
    final countdownLabel = _status == NotificationPairingStatus.linked
        ? 'Đã liên kết'
        : _status == NotificationPairingStatus.expired
        ? 'Hết hạn'
        : 'Hết hạn sau ${_formatRemaining(_remaining)}';
    final countdownColor = _status == NotificationPairingStatus.linked
        ? AppCyberTheme.neonGreen
        : _status == NotificationPairingStatus.expired
        ? Theme.of(context).colorScheme.error
        : _isExpiringSoon
        ? const Color(0xFFF79009)
        : AppCyberTheme.electricBlue;

    return AlertDialog(
      backgroundColor: AppCyberTheme.panelBackgroundStrong,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: AppCyberTheme.isCyber
              ? AppCyberTheme.electricBlue.withValues(alpha: 0.4)
              : AppCyberTheme.lineBlue,
        ),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: const _PanelTitle(
        icon: Icons.qr_code_2_outlined,
        title: 'Liên kết điện thoại',
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: widget.session.pairingUrl,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(color: Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SelectableText(
              widget.session.pairingCode,
              style: AppCyberTheme.dataTextStyle(
                size: 26,
                color: AppCyberTheme.textPrimary,
                weight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            _MetaChip(
              icon: _status == NotificationPairingStatus.linked
                  ? Icons.check_circle_outline
                  : _status == NotificationPairingStatus.expired
                  ? Icons.error_outline
                  : Icons.hourglass_top_outlined,
              label: statusLabel,
              highlighted: _status == NotificationPairingStatus.linked,
            ),
            const SizedBox(height: 10),
            _PairingCountdown(
              label: countdownLabel,
              progress: _countdownProgress,
              color: countdownColor,
            ),
            const SizedBox(height: 10),
            SelectableText(
              widget.session.pairingUrl,
              maxLines: 2,
              style: AppCyberTheme.dataTextStyle(
                size: 10.8,
                color: AppCyberTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: widget.session.pairingUrl));
          },
          icon: const Icon(Icons.content_copy_outlined),
          label: const Text('Sao chép link'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_outlined),
          label: const Text('Đóng'),
        ),
      ],
    );
  }

  bool get _isExpiringSoon =>
      _status == NotificationPairingStatus.pending &&
      _remaining <= const Duration(seconds: 60);

  double get _countdownProgress {
    if (_status == NotificationPairingStatus.linked) return 1;
    final totalMillis = _initialRemaining.inMilliseconds;
    if (totalMillis <= 0) return 0;
    return (_remaining.inMilliseconds / totalMillis).clamp(0.0, 1.0).toDouble();
  }

  void _syncRemaining({bool expireWhenElapsed = true}) {
    final clamped = _remainingUntilExpiry();
    if (!mounted) {
      _remaining = clamped;
      return;
    }

    setState(() {
      _remaining = clamped;
      if (expireWhenElapsed &&
          clamped == Duration.zero &&
          _status == NotificationPairingStatus.pending) {
        _status = NotificationPairingStatus.expired;
      }
    });

    if (_status == NotificationPairingStatus.expired) {
      _pollTimer?.cancel();
      _countdownTimer?.cancel();
    }
  }

  Duration _remainingUntilExpiry() {
    final nextRemaining = widget.session.expiresAt.difference(DateTime.now());
    return nextRemaining.isNegative ? Duration.zero : nextRemaining;
  }

  Future<void> _poll() async {
    if (_isPolling || _status != NotificationPairingStatus.pending) return;
    _isPolling = true;
    try {
      final result = await controller.pollPhonePairing(
        widget.session.pairingId,
      );
      if (!mounted || result == null) return;
      if (_status == NotificationPairingStatus.expired &&
          result.status == NotificationPairingStatus.pending) {
        return;
      }

      setState(() {
        _status = result.status;
        _device = result.device;
      });

      if (result.status != NotificationPairingStatus.pending) {
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
      }
      if (result.status == NotificationPairingStatus.linked && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.of(context).pop();
      }
    } finally {
      _isPolling = false;
    }
  }
}

class _PairingCountdown extends StatelessWidget {
  const _PairingCountdown({
    required this.label,
    required this.progress,
    required this.color,
  });

  final String label;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _HudCardShell(
      active: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 15, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 11,
                    color: AppCyberTheme.textPrimary,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: progress,
              color: color,
              backgroundColor: color.withValues(alpha: 0.16),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatRemaining(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (duration.inHours > 0) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

IconData _resourcePresetIcon(ResourceCollectionPreset preset) {
  return switch (preset) {
    ResourceCollectionPreset.allRecommended =>
      Icons.auto_awesome_motion_outlined,
    ResourceCollectionPreset.envOnly => Icons.tune_outlined,
    ResourceCollectionPreset.custom => Icons.checklist_outlined,
  };
}

IconData _resourceKindIcon(ResourceTargetKind kind) {
  return switch (kind) {
    ResourceTargetKind.envFile => Icons.tune_outlined,
    ResourceTargetKind.properties => Icons.article_outlined,
    ResourceTargetKind.fastlaneServiceAccount =>
      Icons.admin_panel_settings_outlined,
    ResourceTargetKind.firebaseConfig => Icons.local_fire_department_outlined,
    ResourceTargetKind.signingKey => Icons.vpn_key_outlined,
    ResourceTargetKind.appStoreKey => Icons.key_outlined,
  };
}

IconData _resourceCatalogKindIcon(ResourceCatalogKind kind) {
  return switch (kind) {
    ResourceCatalogKind.summaryLink => Icons.dashboard_customize_outlined,
    ResourceCatalogKind.googleSheet => Icons.table_chart_outlined,
    ResourceCatalogKind.driveFolder => Icons.drive_folder_upload_outlined,
    ResourceCatalogKind.driveFile => Icons.insert_drive_file_outlined,
    ResourceCatalogKind.resourceDocument => Icons.inventory_2_outlined,
    ResourceCatalogKind.figma => Icons.design_services_outlined,
    ResourceCatalogKind.playConsole => Icons.shop_2_outlined,
    ResourceCatalogKind.appStoreConnect => Icons.app_shortcut_outlined,
    ResourceCatalogKind.firebase => Icons.local_fire_department_outlined,
    ResourceCatalogKind.cicd => Icons.account_tree_outlined,
    ResourceCatalogKind.repository => Icons.source_outlined,
    ResourceCatalogKind.backendAdmin => Icons.admin_panel_settings_outlined,
    ResourceCatalogKind.apiDocs => Icons.integration_instructions_outlined,
    ResourceCatalogKind.analyticsCrash => Icons.monitor_heart_outlined,
    ResourceCatalogKind.authProvider => Icons.verified_user_outlined,
    ResourceCatalogKind.payment => Icons.payments_outlined,
    ResourceCatalogKind.deepLinkDomain => Icons.link_outlined,
    ResourceCatalogKind.signingCertificate => Icons.workspace_premium_outlined,
    ResourceCatalogKind.qaDevice => Icons.devices_outlined,
    ResourceCatalogKind.testAccount => Icons.manage_accounts_outlined,
    ResourceCatalogKind.legal => Icons.policy_outlined,
    ResourceCatalogKind.releaseRunbook => Icons.fact_check_outlined,
    ResourceCatalogKind.other => Icons.bookmark_border_outlined,
  };
}

IconData _signingCredentialStatusIcon(SigningCredentialStatus status) {
  return switch (status) {
    SigningCredentialStatus.resolved => Icons.verified_user_outlined,
    SigningCredentialStatus.partial => Icons.report_gmailerrorred_outlined,
    SigningCredentialStatus.missing => Icons.lock_open_outlined,
  };
}

String _formatResourceBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(kib >= 10 ? 0 : 1)} KB';
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib >= 10 ? 0 : 1)} MB';
}

class _YesNoPromptActions extends GetView<HomeController> {
  const _YesNoPromptActions({required this.prompt});

  final String prompt;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prompt,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppCyberTheme.dataTextStyle(
              size: 11.2,
              color: AppCyberTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => controller.sendYesNoInput(false),
                  icon: const Icon(Icons.close_outlined),
                  label: const Text('Không'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => controller.sendYesNoInput(true),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Có'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
