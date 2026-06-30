part of '../home_view.dart';

class _StoreVersionsPanel extends GetView<HomeController> {
  const _StoreVersionsPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Obx(() {
                final chPlayCount = controller.chPlayProjects.length;
                final appStoreCount = controller.appStoreProjects.length;
                final count = chPlayCount + appStoreCount;
                final label = count == 0
                    ? 'No managed projects'
                    : '$count projects';
                return Text(
                  label,
                  style: AppCyberTheme.dataTextStyle(
                    size: 11.5,
                    color: AppCyberTheme.textMuted,
                    weight: FontWeight.w600,
                  ),
                );
              }),
            ),
            Obx(() {
              final disabled =
                  controller.runner.isRunning.value ||
                  controller.isRefreshingChPlay.value ||
                  controller.isRefreshingAppStore.value;
              return OutlinedButton.icon(
                onPressed: disabled ? null : controller.refreshAllStoreProjects,
                icon:
                    controller.isRefreshingChPlay.value ||
                        controller.isRefreshingAppStore.value
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined),
                label: const Text('Refresh all'),
              );
            }),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _addChPlayProject(context),
              icon: const Icon(Icons.android_outlined),
              label: const Text('Add CH Play'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _addAppStoreProject(context),
              icon: const Icon(Icons.apple),
              label: const Text('Add App Store'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Obx(() {
            final chPlayProjects = controller.chPlayProjects.toList();
            final appStoreProjects = controller.appStoreProjects.toList();
            final itemCount = chPlayProjects.length + appStoreProjects.length;
            if (itemCount == 0) {
              return Center(
                child: Text(
                  'No managed store projects',
                  style: AppCyberTheme.dataTextStyle(
                    color: AppCyberTheme.textMuted,
                  ),
                ),
              );
            }

            return ListView.separated(
              itemCount: itemCount,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index < chPlayProjects.length) {
                  final project = chPlayProjects[index];
                  return _ChPlayProjectCard(project: project);
                }

                final project = appStoreProjects[index - chPlayProjects.length];
                return _AppStoreProjectCard(project: project);
              },
            );
          }),
        ),
      ],
    );
  }

  Future<void> _addChPlayProject(BuildContext context) async {
    final draft = await controller.pickChPlayProjectDraft();
    if (draft == null || !context.mounted) return;

    final project = await _showChPlayProjectDialog(
      context,
      project: draft,
      isNew: true,
    );
    if (project == null) return;

    await controller.saveChPlayProject(project);
  }

  Future<void> _addAppStoreProject(BuildContext context) async {
    final draft = await controller.pickAppStoreProjectDraft();
    if (draft == null || !context.mounted) return;

    final project = await _showAppStoreProjectDialog(
      context,
      project: draft,
      isNew: true,
    );
    if (project == null) return;

    await controller.saveAppStoreProject(project);
  }
}

class _ChPlayProjectCard extends GetView<HomeController> {
  const _ChPlayProjectCard({required this.project});

  final ChPlayProject project;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final currentSnapshot =
          controller.chPlaySnapshots[project.id] ??
          const ChPlayVersionSnapshot();
      final isRefreshing = currentSnapshot.isRefreshing;

      return _HudCardShell(
        active: isRefreshing,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.android_outlined,
                    size: 20,
                    color: AppCyberTheme.isCyber
                        ? AppCyberTheme.neonGreen
                        : AppCyberTheme.textMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        project.path,
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(
                  icon: Icons.badge_outlined,
                  label: project.applicationId.isEmpty
                      ? 'No app ID'
                      : project.applicationId,
                ),
                _MetaChip(icon: Icons.flag_outlined, label: project.track),
                _MetaChip(
                  icon: Icons.sell_outlined,
                  label: 'Local ${currentSnapshot.localDisplay}',
                  highlighted: true,
                ),
                _MetaChip(
                  icon: Icons.storefront_outlined,
                  label: 'Store ${currentSnapshot.storeDisplay}',
                ),
                _MetaChip(
                  icon: _chPlayStatusIcon(currentSnapshot.status),
                  label: _chPlayStatusLabel(currentSnapshot.status),
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
      );
    });
  }
}

class _ChPlayProjectActions extends GetView<HomeController> {
  const _ChPlayProjectActions({required this.project});

  final ChPlayProject project;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isRunning = controller.runner.isRunning.value;
      final isRefreshing =
          controller.chPlaySnapshots[project.id]?.isRefreshing ?? false;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Refresh',
            visualDensity: VisualDensity.compact,
            onPressed: isRunning || isRefreshing
                ? null
                : () => controller.refreshChPlayProject(project),
            icon: isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_outlined),
          ),
          IconButton(
            tooltip: 'Edit project',
            visualDensity: VisualDensity.compact,
            onPressed: () => _editChPlayProject(context, project),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Credentials',
            visualDensity: VisualDensity.compact,
            onPressed: () => _showChPlayCredentialsDialog(context, project),
            icon: const Icon(Icons.vpn_key_outlined),
          ),
          IconButton(
            tooltip: 'Delete project',
            visualDensity: VisualDensity.compact,
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
  const _AppStoreProjectCard({required this.project});

  final AppStoreProject project;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final currentSnapshot =
          controller.appStoreSnapshots[project.id] ??
          const AppStoreVersionSnapshot();
      final isRefreshing = currentSnapshot.isRefreshing;

      return _HudCardShell(
        active: isRefreshing,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.phone_iphone_outlined,
                    size: 20,
                    color: AppCyberTheme.isCyber
                        ? AppCyberTheme.electricBlue
                        : AppCyberTheme.textMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        project.path,
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(
                  icon: Icons.badge_outlined,
                  label: project.bundleId.isEmpty
                      ? 'No bundle ID'
                      : project.bundleId,
                ),
                _MetaChip(
                  icon: Icons.phone_iphone_outlined,
                  label: project.platform,
                ),
                _MetaChip(
                  icon: Icons.sell_outlined,
                  label: 'Local ${currentSnapshot.localDisplay}',
                  highlighted: true,
                ),
                _MetaChip(
                  icon: Icons.flight_takeoff_outlined,
                  label: 'TestFlight ${currentSnapshot.testFlightDisplay}',
                ),
                _MetaChip(
                  icon: _appStoreStatusIcon(currentSnapshot.status),
                  label: _appStoreStatusLabel(currentSnapshot.status),
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
      );
    });
  }
}

class _AppStoreProjectActions extends GetView<HomeController> {
  const _AppStoreProjectActions({required this.project});

  final AppStoreProject project;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isRunning = controller.runner.isRunning.value;
      final isRefreshing =
          controller.appStoreSnapshots[project.id]?.isRefreshing ?? false;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Refresh',
            visualDensity: VisualDensity.compact,
            onPressed: isRunning || isRefreshing
                ? null
                : () => controller.refreshAppStoreProject(project),
            icon: isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_outlined),
          ),
          IconButton(
            tooltip: 'Edit project',
            visualDensity: VisualDensity.compact,
            onPressed: () => _editAppStoreProject(context, project),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Credentials',
            visualDensity: VisualDensity.compact,
            onPressed: () => _showAppStoreCredentialsDialog(context, project),
            icon: const Icon(Icons.vpn_key_outlined),
          ),
          IconButton(
            tooltip: 'Delete project',
            visualDensity: VisualDensity.compact,
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
