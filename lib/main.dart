import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:app_management_center/app/modules/plan_studio/services/plan_studio_runtime.dart';
import 'package:app_management_center/app/modules/plan_studio/views/reminder_popup_view.dart';
import 'package:app_management_center/app/modules/plan_studio/views/plan_studio_view.dart';
import 'package:app_management_center/app/modules/plan_studio/views/today_view.dart';

import 'package:app_management_center/app/bindings/app_binding.dart';
import 'package:app_management_center/app/config/backend_config.dart';
import 'package:app_management_center/app/services/legacy_storage_migration_service.dart';
import 'package:app_management_center/app/services/theme_service.dart';
import 'package:app_management_center/app/services/app_settings_service.dart';
import 'package:app_management_center/app/views/app_display_scale.dart';
import 'package:app_management_center/app/views/app_lock_gate.dart';
import 'package:app_management_center/app/views/auth_gate.dart';
import 'package:app_management_center/app/views/frame_pacing.dart';
import 'package:app_management_center/app/views/mobile_control_view.dart';
import 'package:app_management_center/app/views/pause_motion_when_inactive.dart';
import 'package:app_management_center/app/modules/swift_desk/views/swift_desk_probe_view.dart';
import 'package:app_management_center/app/modules/swift_desk/views/swift_desk_view.dart';
import 'package:app_management_center/app/modules/swift_desk/services/swift_desk_runtime.dart';
import 'package:app_management_center/app/modules/swift_desk/widgets/swift_desk_status.dart';
import 'package:app_management_center/app/modules/swift_desk/services/swift_desk_lan_smoke.dart';
import 'package:app_management_center/app/modules/swift_desk/services/swift_desk_cloud.dart';
import 'package:app_management_center/app/modules/swift_desk/services/swift_desk_cloud_smoke.dart';
import 'package:app_management_center/app/services/app_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<void> main(List<String> args) async {
  if (Platform.isAndroid || Platform.isIOS) {
    WidgetsFlutterBinding.ensureInitialized();
  } else {
    PacedFramesBinding.ensureInitialized();
  }
  final backgroundSmoke = args
      .where((a) => a.startsWith('--swiftdesk-background-smoke-report='))
      .firstOrNull;
  if (backgroundSmoke != null) {
    final path = backgroundSmoke.substring(
      '--swiftdesk-background-smoke-report='.length,
    );
    final service = AppBackgroundService.shared;
    service.register(
      'remoteHost',
      shutdown: () async {
        await File(path).writeAsString(
          jsonEncode({
            'outcome': 'passed',
            'shutdownCallbackRan': true,
            'backgroundReasonRetained': service.enabled,
            'checkedAt': DateTime.now().toUtc().toIso8601String(),
            'noNetworkListener': true,
          }),
        );
      },
    );
    await service.reason('remoteHost', true);
    final nativeState = await service.channel.invokeMapMethod<String, dynamic>(
      'state',
    );
    await File('$path.started').writeAsString(jsonEncode(nativeState));
    // The computer-use surface cannot bind an app without a visible window.
    // Restore only this disposable diagnostic window after its close check.
    Timer(const Duration(seconds: 12), () => unawaited(service.restore()));
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'AMC · Kiểm tra chạy nền\nĐóng cửa sổ để thử menu bar, rồi Thoát AMC.',
            ),
          ),
        ),
      ),
    );
    return;
  }
  final cloudSmoke = args
      .where((a) => a.startsWith('--swiftdesk-cloud-smoke-api='))
      .firstOrNull;
  if (cloudSmoke != null) {
    final report = args
        .where((a) => a.startsWith('--swiftdesk-cloud-smoke-report='))
        .first;
    final mode = args
        .where((a) => a.startsWith('--swiftdesk-cloud-smoke-mode='))
        .firstOrNull;
    runApp(
      SwiftDeskCloudSmokeApp(
        api: Uri.parse(
          cloudSmoke.substring('--swiftdesk-cloud-smoke-api='.length),
        ),
        reportPath: report.substring('--swiftdesk-cloud-smoke-report='.length),
        mode: parseRemoteConnectionMode(
          mode?.substring('--swiftdesk-cloud-smoke-mode='.length),
        ),
      ),
    );
    return;
  }
  final lanSmoke = args
      .where((a) => a.startsWith('--swiftdesk-lan-smoke-report='))
      .firstOrNull;
  if (lanSmoke != null) {
    runApp(
      SwiftDeskLanSmokeApp(
        reportPath: lanSmoke.substring('--swiftdesk-lan-smoke-report='.length),
      ),
    );
    return;
  }
  if (args.contains('--swiftdesk-lan')) {
    runApp(const SwiftDeskLanApp());
    return;
  }
  if (args.contains('--swiftdesk-spike')) {
    final reportArg = args
        .where((arg) => arg.startsWith('--swiftdesk-smoke-report='))
        .firstOrNull;
    runApp(
      SwiftDeskProbeApp(
        smokeReportPath: reportArg?.substring(
          '--swiftdesk-smoke-report='.length,
        ),
      ),
    );
    return;
  }
  if (args.contains('--plan-reminder-window')) {
    runApp(const ReminderPopupApp());
    return;
  }
  if (runWebViewTitleBarWidget(args)) {
    return;
  }
  // Must run before any service reads preferences or secure storage.
  await const LegacyStorageMigrationService().migrateIfNeeded();
  BackendConfig? backendConfig;
  String? backendConfigurationError;
  try {
    backendConfig = await BackendConfig.load();
  } on FormatException catch (error) {
    backendConfigurationError = error.message;
  }
  await AppBinding.initServices(backendConfig: backendConfig);
  runApp(
    AppManagementCenterApp(
      backendConfigured: backendConfig != null,
      backendConfigurationError: backendConfigurationError,
    ),
  );
  if (Platform.isWindows || Platform.isMacOS) {
    AppBackgroundService.shared.register(
      'remoteHost',
      open: () => unawaited(_openSwiftDesk()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Platform.isWindows) unawaited(_startPlanStudio());
      unawaited(_restoreSwiftDesk());
    });
  }
}

Future<void> _openSwiftDesk() async {
  final context = Get.key.currentContext;
  if (context != null) await showSwiftDesk(context);
}

Future<void> _restoreSwiftDesk() async {
  final preferences = await SharedPreferences.getInstance();
  if (preferences.getBool('swift_desk.restoreHost') != true) return;
  try {
    final runtime = await SwiftDeskRuntime.open();
    if (runtime.hostEnabled && runtime.settings.flag('restoreInternet')) {
      await (await SwiftDeskCloud.open(runtime)).start();
    }
  } catch (e) {
    debugPrint('SwiftDesk could not restore: ${e.runtimeType}');
  }
}

Future<void> _startPlanStudio() async {
  try {
    final runtime = await PlanStudioRuntime.open();
    await runtime.start(
      theme: () => Get.find<ThemeService>().choice.value.name,
      onOpen: (id) {
        final context = Get.key.currentContext;
        if (context == null) return;
        if (id == null) {
          Get.key.currentState?.push(
            MaterialPageRoute<void>(
              builder: (_) => TodayView(repository: runtime.repository),
            ),
          );
        } else {
          showPlanStudio(context, initialItemId: id);
        }
      },
    );
  } catch (e) {
    PlanStudioRuntime.startupError.value = 'Không khởi động được nhắc hẹn: $e';
    debugPrint('Plan Studio reminders could not start: $e');
  }
}

class AppManagementCenterApp extends StatelessWidget {
  const AppManagementCenterApp({
    super.key,
    required this.backendConfigured,
    this.backendConfigurationError,
  });

  final bool backendConfigured;
  final String? backendConfigurationError;

  @override
  Widget build(BuildContext context) {
    final themeService = Get.find<ThemeService>();

    return GetMaterialApp(
      title: 'App Management Center',
      debugShowCheckedModeBanner: false,
      initialBinding: AppBinding(),
      theme: themeService.themeData,
      builder: (context, child) => PauseMotionWhenInactive(
        child: AppDisplayScale(
          settings: Get.find<AppSettingsService>(),
          child: Column(
            children: [
              Expanded(child: child ?? const SizedBox.shrink()),
              SwiftDeskGlobalStatus(
                onOpen: () {
                  final runtime = SwiftDeskRuntime.current.value;
                  if (runtime != null) {
                    Get.key.currentState?.push(
                      MaterialPageRoute<void>(
                        builder: (_) => SwiftDeskView(runtime: runtime),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
      home: Platform.isAndroid || Platform.isIOS
          ? const AppLockGate(child: MobileControlView())
          : AuthGate(
              backendConfigured: backendConfigured,
              backendConfigurationError: backendConfigurationError,
            ),
    );
  }
}
