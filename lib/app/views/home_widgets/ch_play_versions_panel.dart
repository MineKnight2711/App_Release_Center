part of '../home_view.dart';

class _StoreVersionsPanel extends GetView<HomeController> {
  const _StoreVersionsPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 140;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToolbar(compact: compact),
            SizedBox(height: compact ? 6 : 10),
            Expanded(
              child: Obx(() {
                final selectedProject = controller.project.value;
                if (selectedProject == null) {
                  return const _StoreVersionsEmptyState(
                    icon: Icons.folder_open_outlined,
                    message: 'Select a project to view store versions.',
                  );
                }

                final chPlayProjects = _selectedChPlayProjects(
                  selectedProject.path,
                );
                final appStoreProjects = _selectedAppStoreProjects(
                  selectedProject.path,
                );
                if (chPlayProjects.isEmpty && appStoreProjects.isEmpty) {
                  return _StoreVersionsSetupPrompt(
                    project: selectedProject,
                    compact: compact,
                  );
                }

                final cards = <Widget>[
                  for (final project in chPlayProjects)
                    _ChPlayProjectCard(project: project, compact: compact),
                  for (final project in appStoreProjects)
                    _AppStoreProjectCard(project: project, compact: compact),
                ];

                if (compact) {
                  final cardWidth = cards.length > 1
                      ? ((constraints.maxWidth - 8) / 2)
                            .clamp(238.0, 280.0)
                            .toDouble()
                      : constraints.maxWidth;
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    itemCount: cards.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      return SizedBox(width: cardWidth, child: cards[index]);
                    },
                  );
                }

                return ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final card in cards) ...[
                      card,
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              }),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar({required bool compact}) {
    return Row(
      children: [
        Expanded(child: _buildCurrentProjectLabel(compact: compact)),
        _buildRefreshButton(compact: compact),
      ],
    );
  }

  Widget _buildCurrentProjectLabel({required bool compact}) {
    return Obx(() {
      final selectedProject = controller.project.value;
      if (selectedProject == null) {
        return Text(
          'No project selected',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppCyberTheme.dataTextStyle(
            size: compact ? 10.8 : 11.5,
            color: AppCyberTheme.textMuted,
            weight: FontWeight.w600,
          ),
        );
      }

      final count =
          _selectedChPlayProjects(selectedProject.path).length +
          _selectedAppStoreProjects(selectedProject.path).length;
      return Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 16,
            color: AppCyberTheme.textMuted,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              count == 0
                  ? '${selectedProject.name} - not setup'
                  : '${selectedProject.name} - $count store(s)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppCyberTheme.dataTextStyle(
                size: compact ? 10.8 : 11.5,
                color: AppCyberTheme.textMuted,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildRefreshButton({required bool compact}) {
    return Obx(() {
      final refreshing =
          controller.isRefreshingChPlay.value ||
          controller.isRefreshingAppStore.value;
      final selectedProject = controller.project.value;
      final selectedCount = selectedProject == null
          ? 0
          : _selectedChPlayProjects(selectedProject.path).length +
                _selectedAppStoreProjects(selectedProject.path).length;
      final disabled =
          controller.runner.isBusy || refreshing || selectedCount == 0;
      final icon = refreshing
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_outlined);
      if (compact) {
        return IconButton(
          tooltip: 'Refresh selected project',
          visualDensity: VisualDensity.compact,
          onPressed: disabled ? null : _refreshSelectedStoreProjects,
          icon: icon,
        );
      }
      return OutlinedButton.icon(
        onPressed: disabled ? null : _refreshSelectedStoreProjects,
        icon: icon,
        label: const Text('Refresh'),
      );
    });
  }

  List<ChPlayProject> _selectedChPlayProjects(String selectedPath) {
    return controller.chPlayProjects
        .where((project) => _sameStoreProjectPath(project.path, selectedPath))
        .toList(growable: false);
  }

  List<AppStoreProject> _selectedAppStoreProjects(String selectedPath) {
    return controller.appStoreProjects
        .where((project) => _sameStoreProjectPath(project.path, selectedPath))
        .toList(growable: false);
  }

  Future<void> _refreshSelectedStoreProjects() async {
    final selectedProject = controller.project.value;
    if (selectedProject == null) return;

    for (final project in _selectedChPlayProjects(selectedProject.path)) {
      await controller.refreshChPlayProject(project);
    }
    for (final project in _selectedAppStoreProjects(selectedProject.path)) {
      await controller.refreshAppStoreProject(project);
    }
  }
}

class _StoreVersionsSetupPrompt extends StatelessWidget {
  const _StoreVersionsSetupPrompt({
    required this.project,
    required this.compact,
  });

  final ReleaseProject project;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _HudCardShell(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            const Icon(Icons.add_task_outlined, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${project.name}: no store setup',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppCyberTheme.dataTextStyle(
                  size: 11,
                  color: AppCyberTheme.textPrimary,
                  weight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const Key('store-versions-setup-current-project'),
              onPressed: () => _runProjectSetupWizard(context),
              icon: const Icon(Icons.add_task_outlined, size: 16),
              label: const Text('Setup'),
            ),
          ],
        ),
      );
    }

    return _HudCardShell(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.add_task_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No store setup for ${project.name}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 11.5,
                    color: AppCyberTheme.textPrimary,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Use project setup to add CH Play or App Store and run version check.',
            style: AppCyberTheme.dataTextStyle(
              size: 10.5,
              color: AppCyberTheme.textMuted,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('store-versions-setup-current-project'),
              onPressed: () => _runProjectSetupWizard(context),
              icon: const Icon(Icons.add_task_outlined),
              label: const Text('Setup stores'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreVersionsEmptyState extends StatelessWidget {
  const _StoreVersionsEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppCyberTheme.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppCyberTheme.dataTextStyle(
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

bool _sameStoreProjectPath(String first, String second) {
  final left = p.normalize(first);
  final right = p.normalize(second);
  if (Platform.isWindows) {
    return left.toLowerCase() == right.toLowerCase();
  }
  return left == right;
}

Future<void> _showStoreProjectError(
  BuildContext context, {
  required String title,
  required Object error,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: AppCyberTheme.panelBackgroundStrong,
        surfaceTintColor: Colors.transparent,
        title: Text(title),
        content: Text(error.toString()),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

class _StoreVersionMetric extends StatelessWidget {
  const _StoreVersionMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final borderColor = highlighted
        ? (AppCyberTheme.isCyber
              ? AppCyberTheme.electricBlue.withValues(alpha: 0.75)
              : const Color(0xFF1570EF))
        : (AppCyberTheme.isCyber
              ? AppCyberTheme.electricBlue.withValues(alpha: 0.25)
              : AppCyberTheme.lineBlue);
    final backgroundColor = highlighted
        ? (AppCyberTheme.isCyber
              ? AppCyberTheme.electricBlue.withValues(alpha: 0.12)
              : const Color(0xFFEFF8FF))
        : AppCyberTheme.panelBackgroundStrong.withValues(alpha: 0.62);
    final iconColor = highlighted
        ? (AppCyberTheme.isCyber
              ? AppCyberTheme.neonGreen
              : const Color(0xFF1570EF))
        : AppCyberTheme.textMuted;

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 9.8,
                    color: AppCyberTheme.textMuted,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 11.5,
                    color: AppCyberTheme.textPrimary,
                    weight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreVersionInlinePair extends StatelessWidget {
  const _StoreVersionInlinePair({
    required this.localValue,
    required this.remoteLabel,
    required this.remoteValue,
  });

  final String localValue;
  final String remoteLabel;
  final String remoteValue;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'L $localValue',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppCyberTheme.dataTextStyle(
              size: 9.5,
              color: AppCyberTheme.textPrimary,
              weight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$remoteLabel $remoteValue',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppCyberTheme.dataTextStyle(
              size: 9.5,
              color: AppCyberTheme.textMuted,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChPlayProjectCard extends GetView<HomeController> {
  const _ChPlayProjectCard({required this.project, this.compact = false});

  final ChPlayProject project;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final currentSnapshot =
          controller.chPlaySnapshots[project.id] ??
          const ChPlayVersionSnapshot();
      final isRefreshing = currentSnapshot.isRefreshing;

      if (compact) {
        return _buildCompact(context, currentSnapshot, isRefreshing);
      }

      return KeyedSubtree(
        key: Key('store-version-chplay-${project.id}'),
        child: _HudCardShell(
          padding: const EdgeInsets.all(8),
          active: isRefreshing,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppCyberTheme.isCyber
                          ? AppCyberTheme.neonGreen.withValues(alpha: 0.12)
                          : const Color(0xFFEFF8F0),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppCyberTheme.isCyber
                            ? AppCyberTheme.neonGreen.withValues(alpha: 0.55)
                            : const Color(0xFFB7D7C2),
                      ),
                    ),
                    child: Icon(
                      Icons.android_outlined,
                      size: 17,
                      color: AppCyberTheme.isCyber
                          ? AppCyberTheme.neonGreen
                          : AppCyberTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name == p.basename(project.path)
                              ? 'CH Play'
                              : 'CH Play - ${project.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppCyberTheme.dataTextStyle(
                            size: 12,
                            color: AppCyberTheme.textPrimary,
                            weight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          project.applicationId.isEmpty
                              ? 'No app ID'
                              : project.applicationId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppCyberTheme.dataTextStyle(
                            size: 10.5,
                            color: AppCyberTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ChPlayProjectActions(project: project),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _StoreVersionMetric(
                      icon: Icons.sell_outlined,
                      label: 'Local',
                      value: currentSnapshot.localDisplay,
                      highlighted: true,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _StoreVersionMetric(
                      icon: Icons.storefront_outlined,
                      label: 'Store',
                      value: currentSnapshot.storeDisplay,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _MetaChip(icon: Icons.flag_outlined, label: project.track),
                  _MetaChip(
                    icon: _chPlayStatusIcon(currentSnapshot.status),
                    label: _chPlayStatusLabel(currentSnapshot.status),
                    highlighted:
                        currentSnapshot.status ==
                        ChPlayComparisonStatus.upToDate,
                  ),
                  _MetaChip(
                    icon: Icons.schedule_outlined,
                    label: _formatCheckedAt(currentSnapshot.lastCheckedAt),
                  ),
                  _MetaChip(
                    icon: project.hasSavedGooglePlayJson
                        ? Icons.lock_outlined
                        : Icons.lock_open_outlined,
                    label: project.hasSavedGooglePlayJson
                        ? 'Secure JSON'
                        : 'No saved JSON',
                  ),
                  if (project.hasSavedSigningCredentials)
                    const _MetaChip(
                      icon: Icons.vpn_key_outlined,
                      label: 'Signing key',
                    ),
                ],
              ),
              if (currentSnapshot.message.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  currentSnapshot.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 10.8,
                    color: AppCyberTheme.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }

  Widget _buildCompact(
    BuildContext context,
    ChPlayVersionSnapshot snapshot,
    bool isRefreshing,
  ) {
    return KeyedSubtree(
      key: Key('store-version-chplay-${project.id}'),
      child: _HudCardShell(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        active: isRefreshing,
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppCyberTheme.isCyber
                    ? AppCyberTheme.neonGreen.withValues(alpha: 0.12)
                    : const Color(0xFFEFF8F0),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppCyberTheme.isCyber
                      ? AppCyberTheme.neonGreen.withValues(alpha: 0.55)
                      : const Color(0xFFB7D7C2),
                ),
              ),
              child: Icon(
                Icons.android_outlined,
                size: 16,
                color: AppCyberTheme.isCyber
                    ? AppCyberTheme.neonGreen
                    : AppCyberTheme.textMuted,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CH Play',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 11.2,
                      color: AppCyberTheme.textPrimary,
                      weight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    project.applicationId.isEmpty
                        ? _chPlayStatusLabel(snapshot.status)
                        : project.applicationId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 9.8,
                      color: AppCyberTheme.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            _StoreVersionInlinePair(
              localValue: snapshot.localDisplay,
              remoteLabel: 'S',
              remoteValue: snapshot.storeDisplay,
            ),
            _ChPlayProjectActions(project: project, compact: true),
          ],
        ),
      ),
    );
  }
}

class _ChPlayProjectActions extends GetView<HomeController> {
  const _ChPlayProjectActions({required this.project, this.compact = false});

  final ChPlayProject project;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isRunning = controller.runner.isBusy;
      final isRefreshing =
          controller.chPlaySnapshots[project.id]?.isRefreshing ?? false;
      if (compact) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Refresh',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              onPressed: isRunning || isRefreshing
                  ? null
                  : () => controller.refreshChPlayProject(project),
              icon: isRefreshing
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_outlined, size: 18),
            ),
            IconButton(
              tooltip: 'Credentials',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              onPressed: () => _showChPlayCredentialsDialog(context, project),
              icon: const Icon(Icons.vpn_key_outlined, size: 18),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_horiz, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              onSelected: (value) {
                if (value == 'edit') {
                  unawaited(_editChPlayProject(context, project));
                } else if (value == 'delete' && !isRunning) {
                  unawaited(_confirmDeleteChPlayProject(context, project));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit project')),
                PopupMenuItem(
                  value: 'delete',
                  enabled: !isRunning,
                  child: const Text('Delete project'),
                ),
              ],
            ),
          ],
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Refresh',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: isRunning || isRefreshing
                ? null
                : () => controller.refreshChPlayProject(project),
            icon: isRefreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_outlined),
          ),
          IconButton(
            tooltip: 'Edit project',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: () => _editChPlayProject(context, project),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Credentials',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: () => _showChPlayCredentialsDialog(context, project),
            icon: const Icon(Icons.vpn_key_outlined),
          ),
          IconButton(
            tooltip: 'Delete project',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: isRunning
                ? null
                : () => _confirmDeleteChPlayProject(context, project),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      );
    });
  }

  Future<void> _editChPlayProject(
    BuildContext context,
    ChPlayProject project,
  ) async {
    final updated = await _showChPlayProjectDialog(context, project: project);
    if (updated == null) return;

    await controller.saveChPlayProject(updated);
  }

  Future<void> _confirmDeleteChPlayProject(
    BuildContext context,
    ChPlayProject project,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppCyberTheme.panelBackgroundStrong,
          surfaceTintColor: Colors.transparent,
          title: const Text('Delete project'),
          content: Text('Remove ${project.name} from CH Play management?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await controller.deleteChPlayProject(project);
    }
  }
}

class _AppStoreProjectCard extends GetView<HomeController> {
  const _AppStoreProjectCard({required this.project, this.compact = false});

  final AppStoreProject project;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final currentSnapshot =
          controller.appStoreSnapshots[project.id] ??
          const AppStoreVersionSnapshot();
      final isRefreshing = currentSnapshot.isRefreshing;

      if (compact) {
        return _buildCompact(context, currentSnapshot, isRefreshing);
      }

      return KeyedSubtree(
        key: Key('store-version-appstore-${project.id}'),
        child: _HudCardShell(
          padding: const EdgeInsets.all(8),
          active: isRefreshing,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppCyberTheme.isCyber
                          ? AppCyberTheme.electricBlue.withValues(alpha: 0.12)
                          : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppCyberTheme.isCyber
                            ? AppCyberTheme.electricBlue.withValues(alpha: 0.55)
                            : const Color(0xFFBFD7F5),
                      ),
                    ),
                    child: Icon(
                      Icons.phone_iphone_outlined,
                      size: 17,
                      color: AppCyberTheme.isCyber
                          ? AppCyberTheme.electricBlue
                          : AppCyberTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name == p.basename(project.path)
                              ? 'App Store'
                              : 'App Store - ${project.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppCyberTheme.dataTextStyle(
                            size: 12,
                            color: AppCyberTheme.textPrimary,
                            weight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          project.bundleId.isEmpty
                              ? 'No bundle ID'
                              : project.bundleId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppCyberTheme.dataTextStyle(
                            size: 10.5,
                            color: AppCyberTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _AppStoreProjectActions(project: project),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _StoreVersionMetric(
                      icon: Icons.sell_outlined,
                      label: 'Local',
                      value: currentSnapshot.localDisplay,
                      highlighted: true,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _StoreVersionMetric(
                      icon: Icons.flight_takeoff_outlined,
                      label: 'TestFlight',
                      value: currentSnapshot.testFlightDisplay,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _MetaChip(
                    icon: Icons.phone_iphone_outlined,
                    label: project.platform,
                  ),
                  _MetaChip(
                    icon: _appStoreStatusIcon(currentSnapshot.status),
                    label: _appStoreStatusLabel(currentSnapshot.status),
                    highlighted:
                        currentSnapshot.status ==
                        AppStoreComparisonStatus.upToDate,
                  ),
                  _MetaChip(
                    icon: Icons.schedule_outlined,
                    label: _formatCheckedAt(currentSnapshot.lastCheckedAt),
                  ),
                  _MetaChip(
                    icon: project.hasSavedRequiredCredentials
                        ? Icons.lock_outlined
                        : Icons.lock_open_outlined,
                    label: project.hasSavedRequiredCredentials
                        ? 'Secure API key'
                        : 'No saved key',
                  ),
                  if (project.hasSavedTeamId)
                    const _MetaChip(
                      icon: Icons.groups_2_outlined,
                      label: 'Team ID',
                    ),
                  if (project.inHouse)
                    const _MetaChip(
                      icon: Icons.business_outlined,
                      label: 'In-house',
                    ),
                ],
              ),
              if (currentSnapshot.message.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  currentSnapshot.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 10.8,
                    color: AppCyberTheme.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }

  Widget _buildCompact(
    BuildContext context,
    AppStoreVersionSnapshot snapshot,
    bool isRefreshing,
  ) {
    return KeyedSubtree(
      key: Key('store-version-appstore-${project.id}'),
      child: _HudCardShell(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        active: isRefreshing,
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppCyberTheme.isCyber
                    ? AppCyberTheme.electricBlue.withValues(alpha: 0.12)
                    : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppCyberTheme.isCyber
                      ? AppCyberTheme.electricBlue.withValues(alpha: 0.55)
                      : const Color(0xFFBFD7F5),
                ),
              ),
              child: Icon(
                Icons.phone_iphone_outlined,
                size: 16,
                color: AppCyberTheme.isCyber
                    ? AppCyberTheme.electricBlue
                    : AppCyberTheme.textMuted,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App Store',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 11.2,
                      color: AppCyberTheme.textPrimary,
                      weight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    project.bundleId.isEmpty
                        ? _appStoreStatusLabel(snapshot.status)
                        : project.bundleId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 9.8,
                      color: AppCyberTheme.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            _StoreVersionInlinePair(
              localValue: snapshot.localDisplay,
              remoteLabel: 'TF',
              remoteValue: snapshot.testFlightDisplay,
            ),
            _AppStoreProjectActions(project: project, compact: true),
          ],
        ),
      ),
    );
  }
}

class _AppStoreProjectActions extends GetView<HomeController> {
  const _AppStoreProjectActions({required this.project, this.compact = false});

  final AppStoreProject project;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isRunning = controller.runner.isBusy;
      final isRefreshing =
          controller.appStoreSnapshots[project.id]?.isRefreshing ?? false;
      if (compact) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Refresh',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              onPressed: isRunning || isRefreshing
                  ? null
                  : () => controller.refreshAppStoreProject(project),
              icon: isRefreshing
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_outlined, size: 18),
            ),
            IconButton(
              tooltip: 'Credentials',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              onPressed: () => _showAppStoreCredentialsDialog(context, project),
              icon: const Icon(Icons.vpn_key_outlined, size: 18),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_horiz, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              onSelected: (value) {
                if (value == 'edit') {
                  unawaited(_editAppStoreProject(context, project));
                } else if (value == 'delete' && !isRunning) {
                  unawaited(_confirmDeleteAppStoreProject(context, project));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit project')),
                PopupMenuItem(
                  value: 'delete',
                  enabled: !isRunning,
                  child: const Text('Delete project'),
                ),
              ],
            ),
          ],
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Refresh',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: isRunning || isRefreshing
                ? null
                : () => controller.refreshAppStoreProject(project),
            icon: isRefreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_outlined),
          ),
          IconButton(
            tooltip: 'Edit project',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: () => _editAppStoreProject(context, project),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Credentials',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: () => _showAppStoreCredentialsDialog(context, project),
            icon: const Icon(Icons.vpn_key_outlined),
          ),
          IconButton(
            tooltip: 'Delete project',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: isRunning
                ? null
                : () => _confirmDeleteAppStoreProject(context, project),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      );
    });
  }

  Future<void> _editAppStoreProject(
    BuildContext context,
    AppStoreProject project,
  ) async {
    final updated = await _showAppStoreProjectDialog(context, project: project);
    if (updated == null) return;

    await controller.saveAppStoreProject(updated);
  }

  Future<void> _confirmDeleteAppStoreProject(
    BuildContext context,
    AppStoreProject project,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppCyberTheme.panelBackgroundStrong,
          surfaceTintColor: Colors.transparent,
          title: const Text('Delete project'),
          content: Text('Remove ${project.name} from App Store management?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await controller.deleteAppStoreProject(project);
    }
  }
}

Future<ChPlayProject?> _showChPlayProjectDialog(
  BuildContext context, {
  required ChPlayProject project,
  bool isNew = false,
}) async {
  final nameController = TextEditingController(text: project.displayName);
  final appIdController = TextEditingController(text: project.applicationId);
  final pathController = TextEditingController(text: project.path);
  final knownTracks = ['production', 'internal', 'alpha', 'beta'];
  var selectedTrack = knownTracks.contains(project.track)
      ? project.track
      : 'production';
  String? validationError;

  final result = await showDialog<ChPlayProject>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
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
            title: _PanelTitle(
              icon: Icons.shop_two_outlined,
              title: isNew ? 'Add CH Play' : 'Edit CH Play',
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pathController,
                    readOnly: true,
                    maxLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Project path',
                      prefixIcon: Icon(Icons.folder_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: appIdController,
                    decoration: const InputDecoration(
                      labelText: 'Application ID',
                      hintText: 'com.company.app',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTrack,
                    decoration: const InputDecoration(
                      labelText: 'Play track',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    items: knownTracks
                        .map(
                          (track) => DropdownMenuItem(
                            value: track,
                            child: Text(track),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => selectedTrack = value);
                    },
                  ),
                  if (validationError != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        validationError!,
                        style: AppCyberTheme.dataTextStyle(
                          size: 11,
                          color: Theme.of(context).colorScheme.error,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  final appId = appIdController.text.trim();
                  if (appId.isEmpty) {
                    setState(() {
                      validationError = 'Application ID is required.';
                    });
                    return;
                  }

                  Navigator.of(dialogContext).pop(
                    project.copyWith(
                      displayName: nameController.text.trim(),
                      applicationId: appId,
                      track: selectedTrack,
                    ),
                  );
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  nameController.dispose();
  appIdController.dispose();
  pathController.dispose();
  return result;
}

Future<AppStoreProject?> _showAppStoreProjectDialog(
  BuildContext context, {
  required AppStoreProject project,
  bool isNew = false,
}) async {
  final nameController = TextEditingController(text: project.displayName);
  final bundleIdController = TextEditingController(text: project.bundleId);
  final pathController = TextEditingController(text: project.path);

  final result = await showDialog<AppStoreProject>(
    context: context,
    builder: (dialogContext) {
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
        title: _PanelTitle(
          icon: Icons.phone_iphone_outlined,
          title: isNew ? 'Add App Store' : 'Edit App Store',
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pathController,
                readOnly: true,
                maxLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Project path',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bundleIdController,
                decoration: const InputDecoration(
                  labelText: 'Bundle ID',
                  hintText: 'com.company.app',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop(
                project.copyWith(
                  displayName: nameController.text.trim(),
                  bundleId: bundleIdController.text.trim(),
                  platform: 'ios',
                ),
              );
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
        ],
      );
    },
  );

  nameController.dispose();
  bundleIdController.dispose();
  pathController.dispose();
  return result;
}

Future<void> _showChPlayCredentialsDialog(
  BuildContext context,
  ChPlayProject project,
) async {
  final controller = Get.find<HomeController>();
  final credentials = await controller.readChPlayCredentials(project.id);
  if (!context.mounted) return;

  final jksController = TextEditingController(text: credentials.jksPath ?? '');
  final jksPasswordController = TextEditingController();
  final aliasController = TextEditingController(
    text: credentials.keyAlias ?? '',
  );
  final storePasswordController = TextEditingController(
    text: credentials.storePassword ?? '',
  );
  final keyPasswordController = TextEditingController(
    text: credentials.keyPassword ?? '',
  );
  var googlePlayJson = credentials.googlePlayJson;
  var jsonLabel = credentials.hasGooglePlayJson
      ? 'Saved service-account JSON'
      : '';
  final jsonController = TextEditingController(text: jsonLabel);
  var keyPasswordSameAsStore =
      credentials.keyPassword == null ||
      credentials.keyPassword == credentials.storePassword;
  var saveSecurely =
      project.hasSavedGooglePlayJson ||
      project.hasSavedSigningCredentials ||
      !credentials.hasGooglePlayJson;
  var forceRecreateJks = false;
  var isGeneratingJks = false;
  String? validationError;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
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
              icon: Icons.vpn_key_outlined,
              title: 'Credentials',
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      readOnly: true,
                      controller: jsonController,
                      decoration: InputDecoration(
                        labelText: 'Google Play JSON',
                        prefixIcon: const Icon(Icons.description_outlined),
                        suffixIcon: IconButton(
                          tooltip: 'Import JSON',
                          onPressed: () async {
                            final content = await controller
                                .pickGooglePlayJsonContent();
                            if (content == null) return;
                            setState(() {
                              googlePlayJson = content;
                              jsonLabel = 'Imported service-account JSON';
                              jsonController.text = jsonLabel;
                              validationError = null;
                            });
                          },
                          icon: const Icon(Icons.file_upload_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: jksController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'JKS keystore',
                        prefixIcon: const Icon(Icons.inventory_2_outlined),
                        suffixIcon: IconButton(
                          tooltip: 'Import JKS',
                          onPressed: () async {
                            final path = await controller.pickJksPath();
                            if (path == null) return;
                            setState(() => jksController.text = path);
                          },
                          icon: const Icon(Icons.file_upload_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: jksPasswordController,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'JKS password',
                        prefixIcon: Icon(Icons.password_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            value: forceRecreateJks,
                            onChanged: isGeneratingJks
                                ? null
                                : (value) {
                                    setState(() {
                                      forceRecreateJks = value ?? false;
                                    });
                                  },
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Force recreate JKS'),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed:
                              isGeneratingJks ||
                                  controller.runner.isBusy ||
                                  controller.isGeneratingAndroidKeystore.value
                              ? null
                              : () async {
                                  final manualPassword = jksPasswordController
                                      .text
                                      .trim();
                                  if (manualPassword.isNotEmpty &&
                                      manualPassword.length < 6) {
                                    setState(() {
                                      validationError =
                                          'JKS password must be at least 6 characters.';
                                    });
                                    return;
                                  }

                                  setState(() {
                                    isGeneratingJks = true;
                                    validationError = null;
                                  });
                                  final result = await controller
                                      .generateAndroidKeystore(
                                        projectPath: project.path,
                                        keyAlias: aliasController.text.trim(),
                                        storePassword: manualPassword,
                                        forceRecreate: forceRecreateJks,
                                      );
                                  if (!dialogContext.mounted) return;
                                  if (result != null) {
                                    setState(() {
                                      jksController.text = result.keystorePath;
                                      aliasController.text = result.keyAlias;
                                      jksPasswordController.text =
                                          result.storePassword;
                                      storePasswordController.text =
                                          result.storePassword;
                                      keyPasswordController.text =
                                          result.keyPassword;
                                      keyPasswordSameAsStore =
                                          result.keyPassword ==
                                          result.storePassword;
                                    });
                                  }
                                  setState(() {
                                    isGeneratingJks = false;
                                  });
                                },
                          icon: isGeneratingJks
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.vpn_key_outlined),
                          label: const Text('Generate'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: aliasController,
                      decoration: const InputDecoration(
                        labelText: 'Key alias',
                        prefixIcon: Icon(Icons.alternate_email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: storePasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Store password',
                        prefixIcon: Icon(Icons.password_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: keyPasswordSameAsStore,
                      onChanged: (value) {
                        setState(() {
                          keyPasswordSameAsStore = value ?? true;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Key password matches store password'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (!keyPasswordSameAsStore) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: keyPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Key password',
                          prefixIcon: Icon(Icons.password_outlined),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: saveSecurely,
                      onChanged: (value) {
                        setState(() => saveSecurely = value ?? true);
                      },
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Save securely for next run'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          validationError!,
                          style: AppCyberTheme.dataTextStyle(
                            size: 11,
                            color: Theme.of(context).colorScheme.error,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (googlePlayJson == null ||
                      googlePlayJson!.trim().isEmpty) {
                    setState(() {
                      validationError =
                          'Google Play service-account JSON is required.';
                    });
                    return;
                  }

                  final storePassword = storePasswordController.text.trim();
                  await controller.saveChPlayCredentials(
                    project: project,
                    credentials: ChPlayCredentials(
                      googlePlayJson: googlePlayJson,
                      jksPath: jksController.text.trim(),
                      keyAlias: aliasController.text.trim(),
                      storePassword: storePassword,
                      keyPassword: keyPasswordSameAsStore
                          ? storePassword
                          : keyPasswordController.text.trim(),
                    ),
                    saveSecurely: saveSecurely,
                  );
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  jsonController.dispose();
  jksController.dispose();
  jksPasswordController.dispose();
  aliasController.dispose();
  storePasswordController.dispose();
  keyPasswordController.dispose();
}

Future<void> _showAppStoreCredentialsDialog(
  BuildContext context,
  AppStoreProject project,
) async {
  final controller = Get.find<HomeController>();
  final credentials = await controller.readAppStoreCredentials(project.id);
  if (!context.mounted) return;

  final keyIdController = TextEditingController(text: credentials.keyId ?? '');
  final issuerIdController = TextEditingController(
    text: credentials.issuerId ?? '',
  );
  final teamIdController = TextEditingController(
    text: credentials.teamId ?? '',
  );
  var p8PrivateKey = credentials.p8PrivateKey;
  var p8Label = credentials.hasP8PrivateKey ? 'Saved .p8 private key' : '';
  final p8Controller = TextEditingController(text: p8Label);
  var inHouse = credentials.inHouse;
  var saveSecurely =
      project.hasSavedRequiredCredentials ||
      !credentials.hasRequiredCredentials;
  String? validationError;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
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
              icon: Icons.vpn_key_outlined,
              title: 'App Store Credentials',
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      readOnly: true,
                      controller: p8Controller,
                      decoration: InputDecoration(
                        labelText: '.p8 private key',
                        prefixIcon: const Icon(Icons.key_outlined),
                        suffixIcon: IconButton(
                          tooltip: 'Import .p8',
                          onPressed: () async {
                            final content = await controller
                                .pickAppStoreP8Content();
                            if (content == null) return;
                            setState(() {
                              p8PrivateKey = content;
                              p8Label = 'Imported .p8 private key';
                              p8Controller.text = p8Label;
                              validationError = null;
                            });
                          },
                          icon: const Icon(Icons.file_upload_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keyIdController,
                      decoration: const InputDecoration(
                        labelText: 'Key ID',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: issuerIdController,
                      decoration: const InputDecoration(
                        labelText: 'Issuer ID',
                        prefixIcon: Icon(Icons.account_tree_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: teamIdController,
                      decoration: const InputDecoration(
                        labelText: 'Team ID',
                        hintText: 'Optional',
                        prefixIcon: Icon(Icons.groups_2_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: inHouse,
                      onChanged: (value) {
                        setState(() => inHouse = value ?? false);
                      },
                      contentPadding: EdgeInsets.zero,
                      title: const Text('In-house API key'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: saveSecurely,
                      onChanged: (value) {
                        setState(() => saveSecurely = value ?? true);
                      },
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Save securely for next run'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          validationError!,
                          style: AppCyberTheme.dataTextStyle(
                            size: 11,
                            color: Theme.of(context).colorScheme.error,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (p8PrivateKey == null || p8PrivateKey!.trim().isEmpty) {
                    setState(() {
                      validationError = '.p8 private key is required.';
                    });
                    return;
                  }
                  if (keyIdController.text.trim().isEmpty ||
                      issuerIdController.text.trim().isEmpty) {
                    setState(() {
                      validationError = 'Key ID and Issuer ID are required.';
                    });
                    return;
                  }

                  await controller.saveAppStoreCredentials(
                    project: project,
                    credentials: AppStoreCredentials(
                      p8PrivateKey: p8PrivateKey,
                      keyId: keyIdController.text.trim(),
                      issuerId: issuerIdController.text.trim(),
                      teamId: teamIdController.text.trim(),
                      inHouse: inHouse,
                    ),
                    saveSecurely: saveSecurely,
                  );
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  p8Controller.dispose();
  keyIdController.dispose();
  issuerIdController.dispose();
  teamIdController.dispose();
}

IconData _chPlayStatusIcon(ChPlayComparisonStatus status) {
  return switch (status) {
    ChPlayComparisonStatus.notChecked => Icons.hourglass_empty_outlined,
    ChPlayComparisonStatus.missingCredentials => Icons.key_off_outlined,
    ChPlayComparisonStatus.missingLocalVersion => Icons.error_outline,
    ChPlayComparisonStatus.upToDate => Icons.check_circle_outline,
    ChPlayComparisonStatus.localBehind => Icons.arrow_downward_outlined,
    ChPlayComparisonStatus.localAhead => Icons.arrow_upward_outlined,
    ChPlayComparisonStatus.failed => Icons.error_outline,
  };
}

String _chPlayStatusLabel(ChPlayComparisonStatus status) {
  return switch (status) {
    ChPlayComparisonStatus.notChecked => 'Not checked',
    ChPlayComparisonStatus.missingCredentials => 'Missing JSON',
    ChPlayComparisonStatus.missingLocalVersion => 'Bad local version',
    ChPlayComparisonStatus.upToDate => 'Up to date',
    ChPlayComparisonStatus.localBehind => 'Behind store',
    ChPlayComparisonStatus.localAhead => 'Ahead store',
    ChPlayComparisonStatus.failed => 'Failed',
  };
}

IconData _appStoreStatusIcon(AppStoreComparisonStatus status) {
  return switch (status) {
    AppStoreComparisonStatus.notChecked => Icons.hourglass_empty_outlined,
    AppStoreComparisonStatus.missingCredentials => Icons.key_off_outlined,
    AppStoreComparisonStatus.missingBundleId => Icons.badge_outlined,
    AppStoreComparisonStatus.missingLocalVersion => Icons.error_outline,
    AppStoreComparisonStatus.upToDate => Icons.check_circle_outline,
    AppStoreComparisonStatus.localBehind => Icons.arrow_downward_outlined,
    AppStoreComparisonStatus.localAhead => Icons.arrow_upward_outlined,
    AppStoreComparisonStatus.failed => Icons.error_outline,
  };
}

String _appStoreStatusLabel(AppStoreComparisonStatus status) {
  return switch (status) {
    AppStoreComparisonStatus.notChecked => 'Not checked',
    AppStoreComparisonStatus.missingCredentials => 'Missing key',
    AppStoreComparisonStatus.missingBundleId => 'Missing bundle ID',
    AppStoreComparisonStatus.missingLocalVersion => 'Bad local version',
    AppStoreComparisonStatus.upToDate => 'Up to date',
    AppStoreComparisonStatus.localBehind => 'Behind TestFlight',
    AppStoreComparisonStatus.localAhead => 'Ahead TestFlight',
    AppStoreComparisonStatus.failed => 'Failed',
  };
}

String _formatCheckedAt(DateTime? value) {
  if (value == null) return 'Never checked';

  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
