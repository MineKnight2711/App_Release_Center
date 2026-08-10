import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:app_release_center/app/controllers/home_controller.dart';
import 'package:app_release_center/app/models/api_tool.dart';
import 'package:app_release_center/app/models/app_store_credentials.dart';
import 'package:app_release_center/app/models/app_store_project.dart';
import 'package:app_release_center/app/models/app_store_version_snapshot.dart';
import 'package:app_release_center/app/models/ch_play_credentials.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/models/ch_play_version_snapshot.dart';
import 'package:app_release_center/app/models/cicd_dependency.dart';
import 'package:app_release_center/app/models/release_fastlane_lane.dart';
import 'package:app_release_center/app/models/release_notification.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/models/release_script.dart';
import 'package:app_release_center/app/models/release_workflow.dart';
import 'package:app_release_center/app/models/resource_catalog.dart';
import 'package:app_release_center/app/models/resource_collection.dart';
import 'package:app_release_center/app/services/android_cicd_clone_service.dart';
import 'package:app_release_center/app/services/android_keystore_generation_service.dart';
import 'package:app_release_center/app/services/api_tool_postman_import_service.dart';
import 'package:app_release_center/app/services/api_tool_repository_service.dart';
import 'package:app_release_center/app/services/api_tool_service.dart';
import 'package:app_release_center/app/services/auth_service.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:app_release_center/app/services/release_workflow_service.dart';
import 'package:app_release_center/app/services/remote_control_service.dart';
import 'package:app_release_center/app/services/theme_service.dart';
import 'package:app_release_center/app/theme/cyber_theme.dart';
import 'package:app_release_center/app/views/team_management_dialog.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';

part 'home_widgets/flow_panel.dart';
part 'home_widgets/api_tool_dialog.dart';
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

      return Scaffold(
        key: ValueKey(themeChoice),
        bottomNavigationBar: GlobalCommandProgress(runner: controller.runner),
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
                              const SizedBox(height: 520, child: _MainPanel()),
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
          ],
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
          tooltip: 'Account',
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
                title: Text('Team'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'logout',
              child: ListTile(
                leading: Icon(Icons.logout_outlined),
                title: Text('Logout'),
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
