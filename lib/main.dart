import 'dart:io';
import 'dart:async';
import 'package:app_management_center/app/modules/plan_studio/services/plan_studio_runtime.dart';
import 'package:app_management_center/app/modules/plan_studio/views/reminder_popup_view.dart';
import 'package:app_management_center/app/modules/plan_studio/views/plan_studio_view.dart';
import 'package:app_management_center/app/modules/plan_studio/views/today_view.dart';

import 'package:app_management_center/app/bindings/app_binding.dart';
import 'package:app_management_center/app/services/legacy_storage_migration_service.dart';
import 'package:app_management_center/app/services/theme_service.dart';
import 'package:app_management_center/app/views/app_lock_gate.dart';
import 'package:app_management_center/app/views/auth_gate.dart';
import 'package:app_management_center/app/views/mobile_control_view.dart';
import 'package:app_management_center/firebase_options.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains('--plan-reminder-window')) {
    runApp(const ReminderPopupApp());
    return;
  }
  if (runWebViewTitleBarWidget(args)) {
    return;
  }
  // Must run before any service reads preferences or secure storage.
  await const LegacyStorageMigrationService().migrateIfNeeded();
  final firebaseOptions = await DefaultFirebaseOptions.load();
  if (firebaseOptions != null) {
    await Firebase.initializeApp(options: firebaseOptions);
  }
  await AppBinding.initServices(firebaseEnabled: firebaseOptions != null);
  runApp(AppManagementCenterApp(firebaseConfigured: firebaseOptions != null));
  if (Platform.isWindows) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_startPlanStudio()),
    );
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
  const AppManagementCenterApp({super.key, required this.firebaseConfigured});

  final bool firebaseConfigured;

  @override
  Widget build(BuildContext context) {
    final themeService = Get.find<ThemeService>();

    return GetMaterialApp(
      title: 'App Management Center',
      debugShowCheckedModeBanner: false,
      initialBinding: AppBinding(),
      theme: themeService.themeData,
      home: Platform.isAndroid || Platform.isIOS
          ? const AppLockGate(child: MobileControlView())
          : AuthGate(firebaseConfigured: firebaseConfigured),
    );
  }
}
