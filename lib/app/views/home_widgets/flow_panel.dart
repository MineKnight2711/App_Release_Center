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

class _FlowPanel extends StatefulWidget {
  const _FlowPanel();

  @override
  State<_FlowPanel> createState() => _FlowPanelState();
}

class _FlowPanelState extends State<_FlowPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final Worker _shellTabWorker;

  AppShellController get shell => Get.find<AppShellController>();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: ShellFlowTab.values.length,
      vsync: this,
      initialIndex: shell.flowTab.value.index,
    );
    _tabs.addListener(_publishTabToShell);
    _shellTabWorker = ever<ShellFlowTab>(shell.flowTab, _adoptTabFromShell);
  }

  @override
  void dispose() {
    _shellTabWorker.dispose();
    _tabs.removeListener(_publishTabToShell);
    _tabs.dispose();
    super.dispose();
  }

  /// Keeps the shell in step when the user clicks the tab bar directly, so the
  /// palette's "Go to" entries and the tab bar never disagree.
  void _publishTabToShell() {
    if (_tabs.indexIsChanging) return;
    shell.showFlowTab(ShellFlowTab.values[_tabs.index]);
  }

  void _adoptTabFromShell(ShellFlowTab tab) {
    if (!mounted || _tabs.index == tab.index) return;
    _tabs.animateTo(tab.index);
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FlowPanelHeader(),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(icon: Icon(Icons.shop_two_outlined), text: 'Bản trên store'),
              Tab(icon: Icon(Icons.schema_outlined), text: 'Luồng Fastlane'),
              Tab(icon: Icon(Icons.alt_route_outlined), text: 'Lệnh Fastlane'),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _StoreVersionsPanel(),
                _CicdFlowGrid(),
                _FastlanePanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _runExtendedAction(
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
      await Get.find<HomeController>().generateAndroidKeystore(
        keyAlias: input.keyAlias,
        storePassword: input.storePassword,
        forceRecreate: input.forceRecreate,
      );
      break;
    case _ExtendedAction.pullRemoteBranch:
      final payload = await _showPullRemoteBranchDialog(context);
      if (payload == null) return;
      await Get.find<HomeController>().pullBranchFromRemote(
        remote: payload.remote,
        branch: payload.branch,
      );
      break;
    case _ExtendedAction.updateFastlaneWithGem:
      await Get.find<HomeController>().checkFastlaneVersionAndUpdate();
      break;
    case _ExtendedAction.flutterClean:
      await Get.find<HomeController>().runFlutterClean();
      break;
    case _ExtendedAction.flutterPubGet:
      await Get.find<HomeController>().runFlutterPubGet();
      break;
  }
}

Future<void> _runAndroidCicdClone(
  BuildContext context,
  AndroidCicdCloneMode mode,
) async {
  final preview = await Get.find<HomeController>().previewAndroidCicdClone(
    mode: mode,
  );
  if (preview == null || !context.mounted) return;
  final confirmed = await _showAndroidCicdCloneDialog(context, preview);
  if (confirmed != true) return;
  await Get.find<HomeController>().applyAndroidCicdClone(preview);
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
              title: 'Pull branch',
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
                      labelText: 'Tên remote',
                      hintText: 'origin',
                      prefixIcon: Icon(Icons.hub_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: branchController,
                    decoration: const InputDecoration(
                      labelText: 'Tên branch',
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
                      validationError = 'Phải nhập remote và branch.';
                    });
                    return;
                  }

                  Navigator.of(
                    dialogContext,
                  ).pop(_PullRemoteBranchInput(remote: remote, branch: branch));
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
      : 'Không flavor';
  final modeLabel = preview.isFallback ? 'Chế độ fallback' : 'Chế độ adaptive';

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
                    label: preview.applicationId ?? 'Chưa có app ID',
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
                    label: 'thêm ${preview.count(AndroidCicdFileAction.add)}',
                  ),
                  _MetaChip(
                    icon: Icons.edit_outlined,
                    label:
                        'ghi đè ${preview.count(AndroidCicdFileAction.overwrite)}',
                  ),
                  _MetaChip(
                    icon: Icons.remove_circle_outline,
                    label:
                        'bỏ qua ${preview.count(AndroidCicdFileAction.skip)}',
                  ),
                ],
              ),
              if (preview.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                _AndroidCicdWarningList(warnings: preview.warnings),
              ],
              const SizedBox(height: 12),
              Text(
                'Danh sách file',
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
        title: 'Tạo Android JKS',
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
                  labelText: 'Mật khẩu JKS',
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
                title: const Text('Tạo lại JKS dù đã có'),
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
          label: const Text('Tạo'),
        ),
      ],
    );
  }

  void _submit() {
    final alias = _aliasController.text.trim();
    final storePassword = _storePasswordController.text.trim();
    if (alias.isEmpty) {
      setState(() {
        _validationError = 'Phải nhập key alias.';
      });
      return;
    }
    if (storePassword.isNotEmpty && storePassword.length < 6) {
      setState(() {
        _validationError = 'Mật khẩu JKS phải từ 6 ký tự.';
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
  const _FlowPanelHeader();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Two thresholds, dropping the least load-bearing things first: the
        // panel title and the search bar's label (both icons still say what
        // they are), then the status pill, which the bottom progress dock
        // repeats anyway, and the release button's label.
        final compact = width < 700;
        final tight = width < 470;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (compact)
              const Icon(Icons.account_tree_outlined, size: 17)
            else
              const _PanelTitle(
                icon: Icons.account_tree_outlined,
                title: 'Tự động hoá',
              ),
            const SizedBox(width: 10),
            Expanded(child: _CommandPaletteBar(compact: compact)),
            const SizedBox(width: 8),
            _ReleaseWorkflowButton(compact: tight),
            const SizedBox(width: 8),
            if (!tight)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Obx(
                  () => _StatusPill(
                    label: controller.runner.status.value,
                    running: controller.runner.isBusy,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            _AutomationMenuButton(
              onSelected: (action) => _runAutomationMenuAction(context, action),
            ),
          ],
        );
      },
    );
  }
}

/// Everything the header used to spell out as its own button.
///
/// They all stayed one click away, but they no longer each cost a slot in a
/// header that had run out of room; the palette reaches every one of them by
/// name.
enum _AutomationMenuAction {
  apiTool,
  apiMonitor,
  flowFin,
  themeDefault,
  themeCyber,
  cloneAndroidCicd,
  cloneAndroidCicdFallback,
  generateAndroidJks,
  pullRemoteBranch,
  updateFastlaneWithGem,
  flutterClean,
  flutterPubGet,
}

Future<void> _runAutomationMenuAction(
  BuildContext context,
  _AutomationMenuAction action,
) async {
  switch (action) {
    case _AutomationMenuAction.apiTool:
      await showApiToolDialog(context);
    case _AutomationMenuAction.apiMonitor:
      await showApiMonitorDialog(context);
    case _AutomationMenuAction.flowFin:
      await showFlowFinDialog(context);
    case _AutomationMenuAction.themeDefault:
      Get.find<ThemeService>().setChoice(AppThemeChoice.defaultTheme);
    case _AutomationMenuAction.themeCyber:
      Get.find<ThemeService>().setChoice(AppThemeChoice.cyber);
    case _AutomationMenuAction.cloneAndroidCicd:
      await _runExtendedAction(context, _ExtendedAction.cloneAndroidCicd);
    case _AutomationMenuAction.cloneAndroidCicdFallback:
      await _runExtendedAction(
        context,
        _ExtendedAction.cloneAndroidCicdFallback,
      );
    case _AutomationMenuAction.generateAndroidJks:
      await _runExtendedAction(context, _ExtendedAction.generateAndroidJks);
    case _AutomationMenuAction.pullRemoteBranch:
      await _runExtendedAction(context, _ExtendedAction.pullRemoteBranch);
    case _AutomationMenuAction.updateFastlaneWithGem:
      await _runExtendedAction(context, _ExtendedAction.updateFastlaneWithGem);
    case _AutomationMenuAction.flutterClean:
      await _runExtendedAction(context, _ExtendedAction.flutterClean);
    case _AutomationMenuAction.flutterPubGet:
      await _runExtendedAction(context, _ExtendedAction.flutterPubGet);
  }
}

/// The header's single overflow menu: tools, theme, and the project actions
/// that need a project open.
class _AutomationMenuButton extends GetView<HomeController> {
  const _AutomationMenuButton({required this.onSelected});

  final ValueChanged<_AutomationMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final themeService = Get.find<ThemeService>();

    return Obx(() {
      final theme = themeService.choice.value;
      // Project actions run commands in the checked-out repo; the tools above
      // them do not, so only the lower half is gated.
      final projectActionsEnabled =
          controller.project.value != null &&
          !controller.runner.isBusy &&
          !controller.isGeneratingAndroidKeystore.value;

      return PopupMenuButton<_AutomationMenuAction>(
        key: const Key('automation-menu'),
        tooltip: 'Thêm thao tác',
        onSelected: onSelected,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 8),
        color: AppCyberTheme.panelBackgroundStrong.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: AppCyberTheme.isCyber
                ? AppCyberTheme.electricBlue.withValues(alpha: 0.42)
                : AppCyberTheme.lineBlue,
          ),
        ),
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: _AutomationMenuAction.apiTool,
            child: _ExtendedMenuItem(
              icon: Icons.api_outlined,
              title: 'API Tool',
              subtitle: 'Gửi và lưu request HTTP.',
            ),
          ),
          const PopupMenuItem(
            value: _AutomationMenuAction.apiMonitor,
            child: _ExtendedMenuItem(
              icon: Icons.query_stats_outlined,
              title: 'API Monitor',
              subtitle: 'Mở dashboard giám sát.',
            ),
          ),
          const PopupMenuItem(
            value: _AutomationMenuAction.flowFin,
            child: _ExtendedMenuItem(
              icon: Icons.account_balance_wallet_outlined,
              title: 'FlowFin',
              subtitle: 'Ví, ngân sách và giao dịch.',
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: theme == AppThemeChoice.cyber
                ? _AutomationMenuAction.themeDefault
                : _AutomationMenuAction.themeCyber,
            child: _ExtendedMenuItem(
              icon: theme == AppThemeChoice.cyber
                  ? AppThemeChoice.defaultTheme.icon
                  : AppThemeChoice.cyber.icon,
              title: theme == AppThemeChoice.cyber
                  ? 'Đổi sang giao diện Default'
                  : 'Đổi sang giao diện Cyber',
              subtitle: 'Đang dùng ${theme.label}.',
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: _AutomationMenuAction.cloneAndroidCicd,
            enabled: projectActionsEnabled,
            child: const _ExtendedMenuItem(
              icon: Icons.android_outlined,
              title: 'Clone Android CI/CD',
              subtitle: 'Xem trước rồi dựng Fastlane và bộ auto tool.',
            ),
          ),
          PopupMenuItem(
            value: _AutomationMenuAction.cloneAndroidCicdFallback,
            enabled: projectActionsEnabled,
            child: const _ExtendedMenuItem(
              icon: Icons.low_priority_outlined,
              title: 'Clone Android CI/CD fallback',
              subtitle: 'Dùng CI/CD không flavor, không vá Gradle.',
            ),
          ),
          PopupMenuItem(
            value: _AutomationMenuAction.generateAndroidJks,
            enabled: projectActionsEnabled,
            child: const _ExtendedMenuItem(
              icon: Icons.vpn_key_outlined,
              title: 'Tạo Android JKS',
              subtitle: 'Tạo upload keystore và cấu hình ký ngay tại máy.',
            ),
          ),
          PopupMenuItem(
            value: _AutomationMenuAction.pullRemoteBranch,
            enabled: projectActionsEnabled,
            child: const _ExtendedMenuItem(
              icon: Icons.call_received_outlined,
              title: 'Pull branch từ remote',
              subtitle: 'Chọn remote và branch rồi chạy git pull.',
            ),
          ),
          PopupMenuItem(
            value: _AutomationMenuAction.updateFastlaneWithGem,
            enabled: projectActionsEnabled,
            child: const _ExtendedMenuItem(
              icon: Icons.system_update_alt_outlined,
              title: 'Kiểm tra và cập nhật Fastlane',
              subtitle: 'Chạy fastlane --version rồi gem update cho user.',
            ),
          ),
          PopupMenuItem(
            value: _AutomationMenuAction.flutterClean,
            enabled: projectActionsEnabled,
            child: const _ExtendedMenuItem(
              icon: Icons.cleaning_services_outlined,
              title: 'Flutter clean',
              subtitle: 'Xoá artifact build của Flutter trong dự án này.',
            ),
          ),
          PopupMenuItem(
            value: _AutomationMenuAction.flutterPubGet,
            enabled: projectActionsEnabled,
            child: const _ExtendedMenuItem(
              icon: Icons.download_for_offline_outlined,
              title: 'Flutter pub get',
              subtitle: 'Tải dependency của Dart và Flutter.',
            ),
          ),
        ],
        child: Container(
          height: 36,
          width: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppCyberTheme.lineBlue.withValues(alpha: 0.5),
            ),
          ),
          child: const Icon(Icons.more_horiz, size: 18),
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
        return const Center(child: Text('Chọn một dự án'));
      }

      if (project.scripts.isEmpty) {
        return const Center(child: Text('Không tìm thấy auto tool nào'));
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
                  tooltip: 'Chạy ${script.label}',
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
