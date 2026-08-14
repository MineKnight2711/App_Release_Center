part of '../home_view.dart';

class _ProjectPanel extends GetView<HomeController> {
  const _ProjectPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;

        return _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelTitle(
                icon: Icons.folder_open_outlined,
                title: 'Project',
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _chooseProjectAndSetup(context),
                  icon: const Icon(Icons.drive_folder_upload_outlined),
                  label: const Text('Choose directory'),
                ),
              ),
              const SizedBox(height: 16),
              Obx(() {
                final project = controller.project.value;
                final error = controller.projectError.value;

                if (controller.isLoadingProject.value) {
                  return const LinearProgressIndicator();
                }

                if (project == null) {
                  return Text(
                    error.isEmpty ? 'No project selected' : error,
                    style: TextStyle(
                      color: error.isEmpty
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.error,
                    ),
                  );
                }

                return _ProjectSummary(project: project);
              }),
              const SizedBox(height: 20),
              const _PanelTitle(icon: Icons.history_outlined, title: 'Recent'),
              const SizedBox(height: 8),
              if (hasBoundedHeight)
                const Expanded(child: _RecentProjectsList())
              else
                const SizedBox(height: 420, child: _RecentProjectsList()),
            ],
          ),
        );
      },
    );
  }

  Future<void> _chooseProjectAndSetup(BuildContext context) async {
    final loaded = await controller.pickProjectDirectory();
    if (!loaded || !context.mounted) return;
    await _runProjectSetupWizard(context);
  }
}

class _RecentProjectsList extends StatefulWidget {
  const _RecentProjectsList();

  @override
  State<_RecentProjectsList> createState() => _RecentProjectsListState();
}

class _RecentProjectsListState extends State<_RecentProjectsList> {
  final _scrollController = ScrollController();

  HomeController get controller => Get.find<HomeController>();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.recentPaths.isEmpty) {
        return const Center(child: Text('No saved projects'));
      }

      return Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.only(right: 10, bottom: 4),
          itemCount: controller.recentPaths.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final path = controller.recentPaths[index];
            return _RecentProjectTile(path: path);
          },
        ),
      );
    });
  }
}

enum _RecentProjectAction { remove }

class _RecentProjectTile extends GetView<HomeController> {
  const _RecentProjectTile({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected =
          controller.project.value?.path.toLowerCase() == path.toLowerCase();

      return GestureDetector(
        onSecondaryTapDown: (details) => _showContextMenu(context, details),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => controller.loadProject(path),
            child: _HudCardShell(
              active: selected,
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.check_circle : Icons.folder,
                    size: 20,
                    color: selected
                        ? AppCyberTheme.neonGreen
                        : AppCyberTheme.electricBlue.withValues(alpha: 0.82),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.basename(path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppCyberTheme.dataTextStyle(
                            size: 10.8,
                            color: AppCyberTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.more_vert,
                    size: 16,
                    color: AppCyberTheme.textMuted.withValues(alpha: 0.72),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Future<void> _showContextMenu(
    BuildContext context,
    TapDownDetails details,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<_RecentProjectAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(details.globalPosition, details.globalPosition),
        Offset.zero & overlay.size,
      ),
      color: AppCyberTheme.panelBackgroundStrong.withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: AppCyberTheme.isCyber
              ? AppCyberTheme.electricBlue.withValues(alpha: 0.42)
              : AppCyberTheme.lineBlue,
        ),
      ),
      items: const [
        PopupMenuItem(
          value: _RecentProjectAction.remove,
          child: Row(
            children: [
              Icon(Icons.remove_circle_outline, size: 18),
              SizedBox(width: 10),
              Text('Remove from recent'),
            ],
          ),
        ),
      ],
    );

    if (action == _RecentProjectAction.remove) {
      await controller.removeRecentProject(path);
    }
  }
}

class _ProjectSummary extends GetView<HomeController> {
  const _ProjectSummary({required this.project});

  final ReleaseProject project;

  @override
  Widget build(BuildContext context) {
    return _HudCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            project.path,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppCyberTheme.dataTextStyle(
              size: 11.2,
              color: AppCyberTheme.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                icon: Icons.terminal_outlined,
                label: '${project.scripts.length} auto tools',
              ),
              if (project.fastlaneLanes.isNotEmpty)
                _MetaChip(
                  icon: Icons.alt_route_outlined,
                  label: '${project.fastlaneLanes.length} fastlane lanes',
                ),
              if (project.pubspecVersion != null)
                _MetaChip(
                  icon: Icons.sell_outlined,
                  label: project.pubspecVersion!,
                ),
              if (project.hasPlayReleaseTools)
                const _MetaChip(icon: Icons.android_outlined, label: 'CH Play'),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('project-setup-stores'),
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

class _ProjectStoreSetupSelection {
  const _ProjectStoreSetupSelection({
    required this.cloneAndroidCicd,
    required this.chPlay,
    required this.appStore,
  });

  final bool cloneAndroidCicd;
  final bool chPlay;
  final bool appStore;

  bool get hasAny => cloneAndroidCicd || chPlay || appStore;
}

Future<void> _runProjectSetupWizard(BuildContext context) async {
  final controller = Get.find<HomeController>();
  final currentProject = controller.project.value;
  if (currentProject == null) return;

  final selection = await _showProjectSetupSelectionDialog(
    context,
    project: currentProject,
  );
  if (selection == null || !selection.hasAny || !context.mounted) return;

  try {
    if (selection.cloneAndroidCicd && context.mounted) {
      await _cloneAndroidCicdForCurrentProject(context);
    }
    if (selection.chPlay && context.mounted) {
      await _setupChPlayForCurrentProject(context);
    }
    if (selection.appStore && context.mounted) {
      await _setupAppStoreForCurrentProject(context);
    }
  } catch (error) {
    controller.runner.appendSystemLog('Project setup failed: $error');
    if (context.mounted) {
      await _showStoreProjectError(
        context,
        title: 'Project setup failed',
        error: error,
      );
    }
  }
}

Future<_ProjectStoreSetupSelection?> _showProjectSetupSelectionDialog(
  BuildContext context, {
  required ReleaseProject project,
}) async {
  final hasAndroid = Directory(p.join(project.path, 'android')).existsSync();
  final hasIos = Directory(p.join(project.path, 'ios')).existsSync();
  final hasAndroidReleaseTools =
      project.hasPlayReleaseTools ||
      project.scripts.isNotEmpty ||
      project.fastlaneLanes.isNotEmpty;
  var cloneAndroidCicd = hasAndroid && !hasAndroidReleaseTools;
  var includeChPlay = hasAndroid || project.hasPlayReleaseTools;
  var includeAppStore = hasIos;
  if (!includeChPlay && !includeAppStore) {
    includeChPlay = true;
  }

  return showDialog<_ProjectStoreSetupSelection>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final canContinue = includeChPlay || includeAppStore;
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
              icon: Icons.add_task_outlined,
              title: 'Setup project',
            ),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    project.path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 10.8,
                      color: AppCyberTheme.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    key: const Key('project-setup-clone-android-cicd'),
                    value: cloneAndroidCicd,
                    onChanged: hasAndroid
                        ? (value) {
                            setState(() => cloneAndroidCicd = value ?? true);
                          }
                        : null,
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.account_tree_outlined),
                    title: const Text('Clone Android CI/CD'),
                    subtitle: Text(
                      hasAndroid
                          ? hasAndroidReleaseTools
                                ? 'Existing release files detected'
                                : 'Recommended for a new Android project'
                          : 'Needs an android folder',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    key: const Key('project-setup-chplay'),
                    value: includeChPlay,
                    onChanged: (value) {
                      setState(() => includeChPlay = value ?? true);
                    },
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.android_outlined),
                    title: const Text('CH Play'),
                    subtitle: Text(
                      hasAndroid ? 'Android folder detected' : 'Manual setup',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    key: const Key('project-setup-appstore'),
                    value: includeAppStore,
                    onChanged: (value) {
                      setState(() => includeAppStore = value ?? true);
                    },
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.phone_iphone_outlined),
                    title: const Text('App Store'),
                    subtitle: Text(
                      hasIos ? 'iOS folder detected' : 'Manual setup',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Skip'),
              ),
              FilledButton.icon(
                key: const Key('project-setup-start'),
                onPressed: canContinue
                    ? () {
                        Navigator.of(dialogContext).pop(
                          _ProjectStoreSetupSelection(
                            cloneAndroidCicd: cloneAndroidCicd,
                            chPlay: includeChPlay,
                            appStore: includeAppStore,
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('Continue'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _cloneAndroidCicdForCurrentProject(BuildContext context) async {
  final controller = Get.find<HomeController>();
  final preview = await controller.previewAndroidCicdClone(
    overwriteExisting: false,
  );
  if (preview == null) return;

  await controller.applyAndroidCicdClone(preview);
}

Future<void> _setupChPlayForCurrentProject(BuildContext context) async {
  final controller = Get.find<HomeController>();
  final draft = await controller.createChPlayProjectDraftForCurrentProject();
  if (draft == null || !context.mounted) return;

  final isNew = controller.findChPlayProjectById(draft.id) == null;
  var project = draft;
  if (project.applicationId.trim().isEmpty) {
    final edited = await _showChPlayProjectDialog(
      context,
      project: project,
      isNew: isNew,
    );
    if (edited == null || !context.mounted) return;
    project = edited;
  }

  await controller.saveChPlayProject(project);
  project = controller.findChPlayProjectById(project.id) ?? project;
  final credentials = await _resolveChPlayWizardCredentials(project);

  if ((!credentials.hasGooglePlayJson || !credentials.hasJksPath) &&
      context.mounted) {
    await _showChPlayCredentialsDialog(context, project);
    project = controller.findChPlayProjectById(project.id) ?? project;
  }

  await controller.refreshChPlayProject(project);
}

Future<ChPlayCredentials> _resolveChPlayWizardCredentials(
  ChPlayProject project,
) async {
  final controller = Get.find<HomeController>();
  final stored = await controller.readChPlayCredentials(project.id);
  final discovered = _discoverChPlayCredentials(project.path);
  final merged = ChPlayCredentials(
    googlePlayJson: stored.googlePlayJson ?? discovered.googlePlayJson,
    jksPath: stored.jksPath ?? discovered.jksPath,
    keyAlias: stored.keyAlias ?? discovered.keyAlias,
    storePassword: stored.storePassword ?? discovered.storePassword,
    keyPassword: stored.keyPassword ?? discovered.keyPassword,
  );
  if (merged.hasGooglePlayJson ||
      merged.hasJksPath ||
      merged.hasKeyAlias ||
      merged.hasStorePassword ||
      merged.hasKeyPassword) {
    controller.cacheChPlayCredentialsForSession(
      projectId: project.id,
      credentials: merged,
    );
  }
  return merged;
}

ChPlayCredentials _discoverChPlayCredentials(String projectPath) {
  final androidPath = p.join(projectPath, 'android');
  final keyProperties = _readPropertiesFile(
    File(p.join(androidPath, 'key.properties')),
  );
  final envProperties = _readPropertiesFile(
    File(p.join(androidPath, 'env.properties')),
  );

  final googlePlayJsonFile = _firstExistingFile([
    _fileFromProperty(androidPath, envProperties['FASTLANE_KEY_PATH']),
    File(p.join(androidPath, 'fastlane', 'keys', 'google-play-key.json')),
    File(
      p.join(
        androidPath,
        'fastlane',
        'keys',
        'google-play-service-account.json',
      ),
    ),
    File(p.join(androidPath, 'fastlane', 'google-play-service-account.json')),
    File(p.join(androidPath, 'fastlane-service-account.json')),
    File(p.join(androidPath, 'google-play-service-account.json')),
  ]);
  final jksFile =
      _fileFromProperty(
        p.join(androidPath, 'app'),
        keyProperties['storeFile'],
      ) ??
      _firstExistingFile([
        File(p.join(androidPath, 'fastlane', 'keys', 'release.jks')),
        File(p.join(androidPath, 'app', 'upload-keystore.jks')),
        File(p.join(androidPath, 'upload-keystore.jks')),
      ]) ??
      _firstJksInDirectory(Directory(p.join(androidPath, 'fastlane', 'keys')));

  return ChPlayCredentials(
    googlePlayJson: _readFileContent(googlePlayJsonFile),
    jksPath: jksFile?.path,
    keyAlias: keyProperties['keyAlias'],
    storePassword: keyProperties['storePassword'],
    keyPassword: keyProperties['keyPassword'],
  );
}

Map<String, String> _readPropertiesFile(File file) {
  if (!file.existsSync()) return const {};
  final values = <String, String>{};
  try {
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          !trimmed.contains('=')) {
        continue;
      }
      final separator = trimmed.indexOf('=');
      final key = trimmed.substring(0, separator).trim();
      final value = trimmed.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        values[key] = value.replaceAll('"', '').replaceAll("'", '');
      }
    }
  } on FileSystemException {
    return const {};
  }
  return values;
}

File? _fileFromProperty(String basePath, String? rawValue) {
  final value = rawValue?.trim();
  if (value == null || value.isEmpty) return null;
  final resolved = p.isAbsolute(value)
      ? File(value)
      : File(p.normalize(p.join(basePath, value)));
  return resolved.existsSync() ? resolved : null;
}

File? _firstExistingFile(List<File?> files) {
  for (final file in files) {
    if (file != null && file.existsSync()) return file;
  }
  return null;
}

File? _firstJksInDirectory(Directory directory) {
  if (!directory.existsSync()) return null;
  try {
    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      final extension = p.extension(entity.path).toLowerCase();
      if (extension == '.jks' || extension == '.keystore') return entity;
    }
  } on FileSystemException {
    return null;
  }
  return null;
}

String? _readFileContent(File? file) {
  if (file == null || !file.existsSync()) return null;
  try {
    return file.readAsStringSync();
  } on FileSystemException {
    return null;
  }
}

Future<void> _setupAppStoreForCurrentProject(BuildContext context) async {
  final controller = Get.find<HomeController>();
  final draft = await controller.createAppStoreProjectDraftForCurrentProject();
  if (draft == null || !context.mounted) return;

  final isNew = controller.findAppStoreProjectById(draft.id) == null;
  var project = draft;
  if (project.bundleId.trim().isEmpty) {
    final edited = await _showAppStoreProjectDialog(
      context,
      project: project,
      isNew: isNew,
    );
    if (edited == null || !context.mounted) return;
    project = edited;
  }

  await controller.saveAppStoreProject(project);
  project = controller.findAppStoreProjectById(project.id) ?? project;

  if (!project.hasSavedRequiredCredentials && context.mounted) {
    await _showAppStoreCredentialsDialog(context, project);
    project = controller.findAppStoreProjectById(project.id) ?? project;
  }

  await controller.refreshAppStoreProject(project);
}
