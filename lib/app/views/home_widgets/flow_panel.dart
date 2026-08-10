part of '../home_view.dart';

enum _ExtendedAction {
  cloneAndroidCicd,
  cloneAndroidCicdFallback,
  generateAndroidJks,
  pullRemoteBranch,
  updateFastlaneWithGem,
  flutterClean,
  flutterPubGet,
}

class _AndroidKeystoreGenerationInput {
  const _AndroidKeystoreGenerationInput({
    required this.keyAlias,
    required this.storePassword,
    required this.forceRecreate,
  });

  final String keyAlias;
  final String storePassword;
  final bool forceRecreate;
}

class _PullRemoteBranchInput {
  const _PullRemoteBranchInput({required this.remote, required this.branch});

  final String remote;
  final String branch;
}

class _FlowPanel extends GetView<HomeController> {
  const _FlowPanel();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FlowPanelHeader(
              onExtendedActionSelected: _onExtendedActionSelected,
            ),
            const SizedBox(height: 8),
            const TabBar(
              tabs: [
                Tab(
                  icon: Icon(Icons.shop_two_outlined),
                  text: 'Store Versions',
                ),
                Tab(icon: Icon(Icons.schema_outlined), text: 'Fastlane Flow'),
                Tab(
                  icon: Icon(Icons.alt_route_outlined),
                  text: 'Fastlane Command',
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Expanded(
              child: TabBarView(
                children: [
                  _StoreVersionsPanel(),
                  _CicdFlowGrid(),
                  _FastlanePanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onExtendedActionSelected(
    BuildContext context,
    _ExtendedAction action,
  ) async {
    switch (action) {
      case _ExtendedAction.cloneAndroidCicd:
        await _runAndroidCicdClone(context, AndroidCicdCloneMode.adaptive);
        break;
      case _ExtendedAction.cloneAndroidCicdFallback:
        await _runAndroidCicdClone(context, AndroidCicdCloneMode.fallback);
        break;
      case _ExtendedAction.generateAndroidJks:
        final input = await _showAndroidKeystoreGenerationDialog(context);
        if (input == null) return;
        await controller.generateAndroidKeystore(
          keyAlias: input.keyAlias,
          storePassword: input.storePassword,
          forceRecreate: input.forceRecreate,
        );
        break;
      case _ExtendedAction.pullRemoteBranch:
        final payload = await _showPullRemoteBranchDialog(context);
        if (payload == null) return;
        await controller.pullBranchFromRemote(
          remote: payload.remote,
          branch: payload.branch,
        );
        break;
      case _ExtendedAction.updateFastlaneWithGem:
        await controller.checkFastlaneVersionAndUpdate();
        break;
      case _ExtendedAction.flutterClean:
        await controller.runFlutterClean();
        break;
      case _ExtendedAction.flutterPubGet:
        await controller.runFlutterPubGet();
        break;
    }
  }

  Future<void> _runAndroidCicdClone(
    BuildContext context,
    AndroidCicdCloneMode mode,
  ) async {
    final preview = await controller.previewAndroidCicdClone(mode: mode);
    if (preview == null || !context.mounted) return;
    final confirmed = await _showAndroidCicdCloneDialog(context, preview);
    if (confirmed != true) return;
    await controller.applyAndroidCicdClone(preview);
  }

  Future<_AndroidKeystoreGenerationInput?> _showAndroidKeystoreGenerationDialog(
    BuildContext context,
  ) {
    return showDialog<_AndroidKeystoreGenerationInput>(
      context: context,
      builder: (_) => const _AndroidKeystoreGenerationDialog(),
    );
  }

  Future<_PullRemoteBranchInput?> _showPullRemoteBranchDialog(
    BuildContext context,
  ) async {
    final remoteController = TextEditingController(text: 'origin');
    final branchController = TextEditingController();
    String? validationError;

    final result = await showDialog<_PullRemoteBranchInput>(
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
              titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: const _PanelTitle(
                icon: Icons.call_received_outlined,
                title: 'Pull Branch',
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: remoteController,
                      decoration: const InputDecoration(
                        labelText: 'Remote name',
                        hintText: 'origin',
                        prefixIcon: Icon(Icons.hub_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: branchController,
                      decoration: const InputDecoration(
                        labelText: 'Branch name',
                        hintText: 'develop',
                        prefixIcon: Icon(Icons.alt_route_outlined),
                      ),
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        validationError!,
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
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final remote = remoteController.text.trim();
                    final branch = branchController.text.trim();
                    if (remote.isEmpty || branch.isEmpty) {
                      setState(() {
                        validationError = 'Remote and branch are required.';
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop(
                      _PullRemoteBranchInput(remote: remote, branch: branch),
                    );
                  },
                  icon: const Icon(Icons.sync_alt_outlined),
                  label: const Text('Pull'),
                ),
              ],
            );
          },
        );
      },
    );

    remoteController.dispose();
    branchController.dispose();
    return result;
  }

  Future<bool?> _showAndroidCicdCloneDialog(
    BuildContext context,
    AndroidCicdClonePreview preview,
  ) {
    final flavorLabel = preview.hasFlavors
        ? 'Flavor ${preview.selectedFlavor ?? '-'}'
        : 'No flavor';
    final modeLabel = preview.isFallback ? 'Fallback mode' : 'Adaptive mode';

    return showDialog<bool>(
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
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: const _PanelTitle(
            icon: Icons.android_outlined,
            title: 'Clone Android CI/CD',
          ),
          content: SizedBox(
            width: 620,
            height: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaChip(
                      icon: Icons.badge_outlined,
                      label: preview.applicationId ?? 'No app ID',
                      highlighted: preview.applicationId != null,
                    ),
                    _MetaChip(
                      icon: preview.isFallback
                          ? Icons.low_priority_outlined
                          : Icons.auto_awesome_motion_outlined,
                      label: modeLabel,
                      highlighted: preview.isFallback,
                    ),
                    _MetaChip(icon: Icons.layers_outlined, label: flavorLabel),
                    _MetaChip(
                      icon: Icons.description_outlined,
                      label: preview.gradleFilePath,
                    ),
                    _MetaChip(
                      icon: Icons.add_circle_outline,
                      label: '${preview.count(AndroidCicdFileAction.add)} add',
                    ),
                    _MetaChip(
                      icon: Icons.edit_outlined,
                      label:
                          '${preview.count(AndroidCicdFileAction.overwrite)} overwrite',
                    ),
                    _MetaChip(
                      icon: Icons.remove_circle_outline,
                      label:
                          '${preview.count(AndroidCicdFileAction.skip)} skip',
                    ),
                  ],
                ),
                if (preview.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _AndroidCicdWarningList(warnings: preview.warnings),
                ],
                const SizedBox(height: 12),
                Text(
                  'Files',
                  style: AppCyberTheme.dataTextStyle(
                    size: 11.8,
                    color: AppCyberTheme.textPrimary,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppCyberTheme.isCyber
                          ? AppCyberTheme.panelBackgroundStrong.withValues(
                              alpha: 0.7,
                            )
                          : const Color(0xFFFAFBFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppCyberTheme.isCyber
                            ? AppCyberTheme.electricBlue.withValues(alpha: 0.28)
                            : AppCyberTheme.lineBlue,
                      ),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: preview.changes.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 10),
                      itemBuilder: (context, index) {
                        return _AndroidCicdChangeRow(
                          change: preview.changes[index],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.content_copy_outlined),
              label: const Text('Clone'),
            ),
          ],
        );
      },
    );
  }
}

class _AndroidKeystoreGenerationDialog extends StatefulWidget {
  const _AndroidKeystoreGenerationDialog();

  @override
  State<_AndroidKeystoreGenerationDialog> createState() =>
      _AndroidKeystoreGenerationDialogState();
}

class _AndroidKeystoreGenerationDialogState
    extends State<_AndroidKeystoreGenerationDialog> {
  final _aliasController = TextEditingController(text: defaultAndroidKeyAlias);
  final _storePasswordController = TextEditingController();

  var _forceRecreate = false;
  String? _validationError;

  @override
  void dispose() {
    _aliasController.dispose();
    _storePasswordController.dispose();
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
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: const _PanelTitle(
        icon: Icons.vpn_key_outlined,
        title: 'Generate Android JKS',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _aliasController,
                decoration: const InputDecoration(
                  labelText: 'Key alias',
                  prefixIcon: Icon(Icons.alternate_email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _storePasswordController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'JKS password',
                  prefixIcon: Icon(Icons.password_outlined),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _forceRecreate,
                onChanged: (value) {
                  setState(() => _forceRecreate = value ?? false);
                },
                contentPadding: EdgeInsets.zero,
                title: const Text('Force recreate existing JKS'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_validationError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _validationError!,
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
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.vpn_key_outlined),
          label: const Text('Generate'),
        ),
      ],
    );
  }

  void _submit() {
    final alias = _aliasController.text.trim();
    final storePassword = _storePasswordController.text.trim();
    if (alias.isEmpty) {
      setState(() {
        _validationError = 'Key alias is required.';
      });
      return;
    }
    if (storePassword.isNotEmpty && storePassword.length < 6) {
      setState(() {
        _validationError = 'JKS password must be at least 6 characters.';
      });
      return;
    }

    Navigator.of(context).pop(
      _AndroidKeystoreGenerationInput(
        keyAlias: alias,
        storePassword: storePassword,
        forceRecreate: _forceRecreate,
      ),
    );
  }
}

class _FlowPanelHeader extends GetView<HomeController> {
  const _FlowPanelHeader({required this.onExtendedActionSelected});

  final Future<void> Function(BuildContext context, _ExtendedAction action)
  onExtendedActionSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(
          child: _PanelTitle(
            icon: Icons.account_tree_outlined,
            title: 'Automation',
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 2,
          child: Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const _ApiToolButton(),
                const _ReleaseWorkflowButton(),
                const _ThemeSwitchMenu(),
                Obx(
                  () => _StatusPill(
                    label: controller.runner.status.value,
                    running: controller.runner.isBusy,
                  ),
                ),
                _ExtendedActionsButton(
                  onSelected: (action) =>
                      onExtendedActionSelected(context, action),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ExtendedActionsButton extends GetView<HomeController> {
  const _ExtendedActionsButton({required this.onSelected});

  final ValueChanged<_ExtendedAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEnabled =
          controller.project.value != null &&
          !controller.runner.isBusy &&
          !controller.isGeneratingAndroidKeystore.value;

      return PopupMenuButton<_ExtendedAction>(
        enabled: isEnabled,
        tooltip: isEnabled ? 'Extended actions' : 'Choose a project first',
        onSelected: onSelected,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 8),
        color: AppCyberTheme.panelBackgroundStrong.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 340),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: AppCyberTheme.isCyber
                ? AppCyberTheme.electricBlue.withValues(alpha: 0.42)
                : AppCyberTheme.lineBlue,
          ),
        ),
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _ExtendedAction.cloneAndroidCicd,
            child: _ExtendedMenuItem(
              icon: Icons.android_outlined,
              title: 'Clone Android CI/CD',
              subtitle: 'Preview and scaffold Fastlane plus auto tools.',
            ),
          ),
          PopupMenuItem(
            value: _ExtendedAction.cloneAndroidCicdFallback,
            child: _ExtendedMenuItem(
              icon: Icons.low_priority_outlined,
              title: 'Clone Android CI/CD fallback',
              subtitle: 'Use generic no-flavor CI/CD without Gradle patching.',
            ),
          ),
          PopupMenuItem(
            value: _ExtendedAction.generateAndroidJks,
            child: _ExtendedMenuItem(
              icon: Icons.vpn_key_outlined,
              title: 'Generate Android JKS',
              subtitle: 'Create local upload keystore and signing configs.',
            ),
          ),
          PopupMenuItem(
            value: _ExtendedAction.pullRemoteBranch,
            child: _ExtendedMenuItem(
              icon: Icons.call_received_outlined,
              title: 'Pull branch from remote',
              subtitle: 'Input remote and branch, then run git pull.',
            ),
          ),
          PopupMenuItem(
            value: _ExtendedAction.updateFastlaneWithGem,
            child: _ExtendedMenuItem(
              icon: Icons.system_update_alt_outlined,
              title: 'Check and update Fastlane',
              subtitle: 'Run fastlane --version then a user-scoped gem update.',
            ),
          ),
          PopupMenuItem(
            value: _ExtendedAction.flutterClean,
            child: _ExtendedMenuItem(
              icon: Icons.cleaning_services_outlined,
              title: 'Flutter clean',
              subtitle: 'Clear Flutter build artifacts in this project.',
            ),
          ),
          PopupMenuItem(
            value: _ExtendedAction.flutterPubGet,
            child: _ExtendedMenuItem(
              icon: Icons.download_for_offline_outlined,
              title: 'Flutter pub get',
              subtitle: 'Fetch Dart and Flutter dependencies.',
            ),
          ),
        ],
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: isEnabled ? 1 : 0.55,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppCyberTheme.isCyber
                    ? AppCyberTheme.electricBlue.withValues(alpha: 0.44)
                    : AppCyberTheme.lineBlue,
              ),
              gradient: LinearGradient(
                colors: AppCyberTheme.isCyber
                    ? [
                        AppCyberTheme.electricBlue.withValues(alpha: 0.2),
                        AppCyberTheme.electricBlue.withValues(alpha: 0.08),
                      ]
                    : const [Colors.white, Color(0xFFFAFBFC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.extension_outlined,
                    size: 16,
                    color: AppCyberTheme.isCyber
                        ? AppCyberTheme.electricBlue.withValues(alpha: 0.95)
                        : AppCyberTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Extend',
                    style: AppCyberTheme.dataTextStyle(
                      size: 11.5,
                      color: AppCyberTheme.textPrimary,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.expand_more_outlined,
                    size: 15,
                    color: AppCyberTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _AndroidCicdWarningList extends StatelessWidget {
  const _AndroidCicdWarningList({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: warnings.map((warning) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_outlined,
                size: 15,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  warning,
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
      }).toList(),
    );
  }
}

class _AndroidCicdChangeRow extends StatelessWidget {
  const _AndroidCicdChangeRow({required this.change});

  final AndroidCicdFileChange change;

  @override
  Widget build(BuildContext context) {
    final color = _actionColor(context, change.action);

    return Row(
      children: [
        Icon(_actionIcon(change.action), size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            change.relativePath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppCyberTheme.dataTextStyle(
              size: 11,
              color: AppCyberTheme.textPrimary,
              weight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _actionLabel(change.action),
          style: AppCyberTheme.dataTextStyle(
            size: 10.5,
            color: color,
            weight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  IconData _actionIcon(AndroidCicdFileAction action) {
    return switch (action) {
      AndroidCicdFileAction.add => Icons.add_circle_outline,
      AndroidCicdFileAction.overwrite => Icons.edit_outlined,
      AndroidCicdFileAction.skip => Icons.remove_circle_outline,
    };
  }

  String _actionLabel(AndroidCicdFileAction action) {
    return switch (action) {
      AndroidCicdFileAction.add => 'ADD',
      AndroidCicdFileAction.overwrite => 'OVERWRITE',
      AndroidCicdFileAction.skip => 'SKIP',
    };
  }

  Color _actionColor(BuildContext context, AndroidCicdFileAction action) {
    return switch (action) {
      AndroidCicdFileAction.add =>
        AppCyberTheme.isCyber
            ? AppCyberTheme.neonGreen
            : const Color(0xFF039855),
      AndroidCicdFileAction.overwrite =>
        AppCyberTheme.isCyber
            ? AppCyberTheme.electricBlue
            : const Color(0xFF1570EF),
      AndroidCicdFileAction.skip => Theme.of(context).colorScheme.error,
    };
  }
}

class _ExtendedMenuItem extends StatelessWidget {
  const _ExtendedMenuItem({
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
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: AppCyberTheme.dataTextStyle(
                  size: 11.8,
                  color: AppCyberTheme.textPrimary,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppCyberTheme.dataTextStyle(
                  size: 10.5,
                  color: AppCyberTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CicdFlowGrid extends GetView<HomeController> {
  const _CicdFlowGrid();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final project = controller.project.value;
      if (project == null) {
        return const Center(child: Text('Choose a project'));
      }

      if (project.scripts.isEmpty) {
        return const Center(child: Text('No auto tools found'));
      }

      return GridView.builder(
        padding: EdgeInsets.zero,
        itemCount: project.scripts.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 148,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemBuilder: (context, index) {
          return _ScriptCard(script: project.scripts[index]);
        },
      );
    });
  }
}

class _ScriptCard extends GetView<HomeController> {
  const _ScriptCard({required this.script});

  final ReleaseScript script;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isRunning = controller.runner.isBusy;
      final isActive = controller.runner.activeScriptPath.value == script.path;

      return _HudCardShell(
        active: isActive,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(script.kind), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    script.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              script.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    script.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 10.8,
                      color: AppCyberTheme.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Run ${script.label}',
                  visualDensity: VisualDensity.compact,
                  onPressed: isRunning
                      ? null
                      : () {
                          if (script.kind == ReleaseScriptKind.release) {
                            showReleaseWorkflowDialog(context);
                          } else {
                            controller.runScript(script);
                          }
                        },
                  icon: isActive
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  IconData _iconFor(ReleaseScriptKind kind) {
    return switch (kind) {
      ReleaseScriptKind.release => Icons.rocket_launch_outlined,
      ReleaseScriptKind.versionCode => Icons.pin_outlined,
      ReleaseScriptKind.versionName => Icons.sell_outlined,
      ReleaseScriptKind.commit => Icons.commit_outlined,
      ReleaseScriptKind.merge => Icons.call_merge_outlined,
      ReleaseScriptKind.deploy => Icons.cloud_upload_outlined,
      ReleaseScriptKind.imageValidation => Icons.image_search_outlined,
      ReleaseScriptKind.shell => Icons.terminal_outlined,
      ReleaseScriptKind.dartTool => Icons.data_object_outlined,
    };
  }
}
