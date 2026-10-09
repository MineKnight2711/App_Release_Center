import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:app_management_center/app/controllers/app_shell_controller.dart';
import 'package:app_management_center/app/controllers/flowfin_controller.dart';
import 'package:app_management_center/app/controllers/home_controller.dart';
import 'package:app_management_center/app/modules/bundle_check/views/bundle_check_view.dart';
import 'package:app_management_center/app/modules/mail_cleaner/views/mail_cleaner_view.dart';
import 'package:app_management_center/app/modules/plan_studio/views/plan_studio_view.dart';
import 'package:app_management_center/app/modules/qa_desk/services/qa_desk_runtime.dart';
import 'package:app_management_center/app/modules/qa_desk/views/qa_desk_view.dart';
import 'package:app_management_center/app/modules/qa_desk/views/qa_shell_status.dart';
import 'package:app_management_center/app/models/api_tool.dart';
import 'package:app_management_center/app/models/app_store_credentials.dart';
import 'package:app_management_center/app/models/app_store_project.dart';
import 'package:app_management_center/app/models/app_store_version_snapshot.dart';
import 'package:app_management_center/app/models/ch_play_credentials.dart';
import 'package:app_management_center/app/models/ch_play_project.dart';
import 'package:app_management_center/app/models/ch_play_version_snapshot.dart';
import 'package:app_management_center/app/models/cicd_dependency.dart';
import 'package:app_management_center/app/models/flowfin_models.dart';
import 'package:app_management_center/app/models/flowfin_settings.dart';
import 'package:app_management_center/app/models/release_fastlane_lane.dart';
import 'package:app_management_center/app/models/release_notification.dart';
import 'package:app_management_center/app/models/release_project.dart';
import 'package:app_management_center/app/models/release_script.dart';
import 'package:app_management_center/app/models/release_workflow.dart';
import 'package:app_management_center/app/models/resource_catalog.dart';
import 'package:app_management_center/app/models/resource_collection.dart';
import 'package:app_management_center/app/services/android_cicd_clone_service.dart';
import 'package:app_management_center/app/services/android_keystore_generation_service.dart';
import 'package:app_management_center/app/services/api_monitor_service.dart';
import 'package:app_management_center/app/services/api_tool_postman_import_service.dart';
import 'package:app_management_center/app/services/api_tool_repository_service.dart';
import 'package:app_management_center/app/services/api_tool_service.dart';
import 'package:app_management_center/app/services/auth_service.dart';
import 'package:app_management_center/app/services/git_inspector_service.dart';
import 'package:app_management_center/app/services/machine_power_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:app_management_center/app/services/release_workflow_service.dart';
import 'package:app_management_center/app/services/remote_control_service.dart';
import 'package:app_management_center/app/services/theme_service.dart';
import 'package:app_management_center/app/services/windows_auto_start_service.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:app_management_center/app/views/team_management_dialog.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

part 'home_widgets/api_monitor_dialog.dart';
part 'home_widgets/command_palette.dart';
part 'home_widgets/flow_panel.dart';
part 'home_widgets/flowfin_dialog.dart';
part 'home_widgets/flowfin/flowfin_shared.dart';
part 'home_widgets/flowfin/flowfin_transactions_tab.dart';
part 'home_widgets/flowfin/flowfin_accounts_tab.dart';
part 'home_widgets/flowfin/flowfin_budgets_tab.dart';
part 'home_widgets/flowfin/flowfin_statistics_tab.dart';
part 'home_widgets/flowfin/flowfin_reconcile_tab.dart';
part 'home_widgets/flowfin/flowfin_imports_tab.dart';
part 'home_widgets/flowfin/flowfin_settings_tab.dart';
part 'home_widgets/api_tool_dialog.dart';
part 'home_widgets/api_tool/api_tool_components.dart';
part 'home_widgets/api_tool/api_tool_omnibar.dart';
part 'home_widgets/api_tool/api_tool_sidebar.dart';
part 'home_widgets/api_tool/api_tool_request_panel.dart';
part 'home_widgets/api_tool/api_tool_response_panel.dart';
part 'home_widgets/api_tool/api_tool_environment_dialog.dart';
part 'home_widgets/api_tool/api_tool_quick_request_dialog.dart';
part 'home_widgets/fastlane_panel.dart';
part 'home_widgets/ch_play_versions_panel.dart';
part 'home_widgets/log_panel.dart';
part 'home_widgets/main_panel.dart';
part 'home_widgets/options_panel.dart';
part 'home_widgets/project_panel.dart';
part 'home_widgets/release_workflow_dialog.dart';
part 'home_widgets/shared_widgets.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) => const _HomeScaffold();
}

class _HomeScaffold extends StatefulWidget {
  const _HomeScaffold();

  @override
  State<_HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<_HomeScaffold> {
  static const double _outerPadding = 16;
  static const double _desktopBreakpoint = 1180;
  static const double _minSidePanelWidth = 280;
  static const double _maxSidePanelWidth = 460;
  static const double _minMainPanelWidth = 540;
  static const double _defaultSidePanelWidth = 340;
  static const double _splitterThickness = 14;

  double _leftPanelWidth = _defaultSidePanelWidth;
  double _rightPanelWidth = _defaultSidePanelWidth;

  HomeController get controller => Get.find<HomeController>();

  @override
  Widget build(BuildContext context) {
    final themeService = Get.find<ThemeService>();

    return Obx(() {
      final themeChoice = themeService.choice.value;

      final shell = Get.find<AppShellController>();

      return CallbackShortcuts(
        bindings: {
          for (final activator in _paletteActivators)
            activator: shell.togglePalette,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            key: ValueKey(themeChoice),
            bottomNavigationBar: GlobalCommandProgress(
              runner: controller.runner,
            ),
            body: Stack(
              children: [
                Positioned.fill(child: _HudBackdrop()),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final usableWidth =
                          constraints.maxWidth - (_outerPadding * 2);
                      final isWide = usableWidth >= _desktopBreakpoint;
                      final mobileOptionsHeight =
                          (constraints.maxHeight - (_outerPadding * 2))
                              .clamp(580.0, 760.0)
                              .toDouble();
                      final content = isWide
                          ? _WideHomeLayout(
                              leftPanelWidth: _leftPanelWidth,
                              rightPanelWidth: _rightPanelWidth,
                              splitterThickness: _splitterThickness,
                              onLeftResize: (delta) =>
                                  _resizeLeft(delta, usableWidth),
                              onRightResize: (delta) =>
                                  _resizeRight(delta, usableWidth),
                            )
                          : SingleChildScrollView(
                              child: Column(
                                children: [
                                  const _ProjectPanel(),
                                  const SizedBox(height: 16),
                                  const SizedBox(
                                    height: 520,
                                    child: _MainPanel(),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    height: mobileOptionsHeight,
                                    child: const _OptionsPanel(),
                                  ),
                                ],
                              ),
                            );

                      return Padding(
                        padding: const EdgeInsets.all(_outerPadding),
                        child: content,
                      );
                    },
                  ),
                ),
                if (Get.isRegistered<AuthService>())
                  const Positioned(top: 24, right: 24, child: _AccountHud()),
                Obx(
                  () => shell.isPaletteOpen.value
                      ? const _CommandPalette()
                      : const SizedBox.shrink(),
                ),
                // Last in the stack so nothing can cover the cancel button:
                // whoever is at the machine outranks whoever holds the phone.
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _PendingPowerBanner(),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  void _resizeLeft(double delta, double usableWidth) {
    final clamped = (_leftPanelWidth + delta).clamp(
      _minSidePanelWidth,
      _maxSidePanelWidth,
    );
    final nextLeft = _enforceMainWidth(
      usableWidth: usableWidth,
      nextLeft: clamped.toDouble(),
      nextRight: _rightPanelWidth,
      fallbackCurrent: _leftPanelWidth,
    );
    if (nextLeft == _leftPanelWidth) return;
    setState(() {
      _leftPanelWidth = nextLeft;
    });
  }

  void _resizeRight(double delta, double usableWidth) {
    final clamped = (_rightPanelWidth - delta).clamp(
      _minSidePanelWidth,
      _maxSidePanelWidth,
    );
    final nextRight = _enforceMainWidth(
      usableWidth: usableWidth,
      nextLeft: _leftPanelWidth,
      nextRight: clamped.toDouble(),
      fallbackCurrent: _rightPanelWidth,
      resizingRight: true,
    );
    if (nextRight == _rightPanelWidth) return;
    setState(() {
      _rightPanelWidth = nextRight;
    });
  }

  double _enforceMainWidth({
    required double usableWidth,
    required double nextLeft,
    required double nextRight,
    required double fallbackCurrent,
    bool resizingRight = false,
  }) {
    final reserved = nextLeft + nextRight + (_splitterThickness * 2);
    final minNeeded = reserved + _minMainPanelWidth;
    if (usableWidth >= minNeeded) {
      return resizingRight ? nextRight : nextLeft;
    }

    final maxSide =
        usableWidth -
        _minMainPanelWidth -
        _splitterThickness * 2 -
        (resizingRight ? nextLeft : nextRight);
    final adjusted = maxSide.clamp(_minSidePanelWidth, _maxSidePanelWidth);
    if (adjusted.isNaN || adjusted.isInfinite) {
      return fallbackCurrent;
    }
    return adjusted.toDouble();
  }
}

/// Ctrl+K is the primary binding; Ctrl+P matches the muscle memory of editors
/// the user already lives in.
const _paletteActivators = <SingleActivator>[
  SingleActivator(LogicalKeyboardKey.keyK, control: true),
  SingleActivator(LogicalKeyboardKey.keyK, meta: true),
  SingleActivator(LogicalKeyboardKey.keyP, control: true),
  SingleActivator(LogicalKeyboardKey.keyP, meta: true),
];

/// Shows a shutdown or restart a phone has queued, with a way out.
///
/// The phone can also cancel, but someone sitting at the machine should never
/// have to find their phone to stop it losing their work.
class _PendingPowerBanner extends StatefulWidget {
  const _PendingPowerBanner();

  @override
  State<_PendingPowerBanner> createState() => _PendingPowerBannerState();
}

class _PendingPowerBannerState extends State<_PendingPowerBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<RemoteControlService>()) {
      return const SizedBox.shrink();
    }
    final remote = Get.find<RemoteControlService>();

    return Obx(() {
      final pending = remote.pendingPowerCommand.value;
      if (pending == null) return const SizedBox.shrink();

      final remaining = pending.remaining();
      final label = pending.action == MachinePowerAction.restart
          ? 'Khởi động lại'
          : 'Tắt máy';

      return Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppCyberTheme.palette.danger,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.power_settings_new_outlined,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Điện thoại yêu cầu $label. Còn ${remaining.inSeconds} giây.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => unawaited(remote.cancelPendingPowerCommand()),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppCyberTheme.palette.danger,
                ),
                icon: const Icon(Icons.undo_outlined),
                label: const Text('Huỷ ngay'),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _AccountHud extends StatelessWidget {
  const _AccountHud();

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthService>();
    return Obx(() {
      final profile = auth.profile.value;
      if (profile == null) return const SizedBox.shrink();
      return Material(
        color: Colors.transparent,
        child: PopupMenuButton<String>(
          tooltip: 'Tài khoản',
          onSelected: (value) {
            if (value == 'team') {
              unawaited(showTeamManagementDialog(context));
            } else if (value == 'logout') {
              unawaited(auth.signOut());
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Text(profile.email, overflow: TextOverflow.ellipsis),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'team',
              child: ListTile(
                leading: Icon(Icons.groups_outlined),
                title: Text('Nhóm'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'logout',
              child: ListTile(
                leading: Icon(Icons.logout_outlined),
                title: Text('Đăng xuất'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppCyberTheme.panelBackgroundStrong.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppCyberTheme.electricBlue.withValues(alpha: 0.42),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_circle_outlined, size: 18),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    profile.teamName.isEmpty ? profile.email : profile.teamName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 10.8,
                      color: AppCyberTheme.textPrimary,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _WideHomeLayout extends StatelessWidget {
  const _WideHomeLayout({
    required this.leftPanelWidth,
    required this.rightPanelWidth,
    required this.splitterThickness,
    required this.onLeftResize,
    required this.onRightResize,
  });

  final double leftPanelWidth;
  final double rightPanelWidth;
  final double splitterThickness;
  final ValueChanged<double> onLeftResize;
  final ValueChanged<double> onRightResize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: leftPanelWidth, child: const _ProjectPanel()),
        SizedBox(
          width: splitterThickness,
          child: _PanelSplitter(axis: Axis.horizontal, onDelta: onLeftResize),
        ),
        const Expanded(child: _MainPanel()),
        SizedBox(
          width: splitterThickness,
          child: _PanelSplitter(axis: Axis.horizontal, onDelta: onRightResize),
        ),
        SizedBox(width: rightPanelWidth, child: const _OptionsPanel()),
      ],
    );
  }
}
