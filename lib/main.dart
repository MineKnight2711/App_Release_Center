import 'dart:io';

import 'package:app_management_center/app/bindings/app_binding.dart';
import 'package:app_management_center/app/services/legacy_storage_migration_service.dart';
import 'package:app_management_center/app/services/theme_service.dart';
import 'package:app_management_center/app/views/auth_gate.dart';
import 'package:app_management_center/app/views/mobile_control_view.dart';
import 'package:app_management_center/firebase_options.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
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
          ? const MobileControlView()
          : AuthGate(firebaseConfigured: firebaseConfigured),
    );
  }
}
