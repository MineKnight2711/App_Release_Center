import 'dart:io';

import 'package:app_release_center/app/bindings/app_binding.dart';
import 'package:app_release_center/app/services/theme_service.dart';
import 'package:app_release_center/app/views/auth_gate.dart';
import 'package:app_release_center/app/views/mobile_control_view.dart';
import 'package:app_release_center/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseOptions = await DefaultFirebaseOptions.load();
  if (firebaseOptions != null) {
    await Firebase.initializeApp(options: firebaseOptions);
  }
  await AppBinding.initServices(firebaseEnabled: firebaseOptions != null);
  runApp(AppReleaseCenterApp(firebaseConfigured: firebaseOptions != null));
}

class AppReleaseCenterApp extends StatelessWidget {
  const AppReleaseCenterApp({super.key, required this.firebaseConfigured});

  final bool firebaseConfigured;

  @override
  Widget build(BuildContext context) {
    final themeService = Get.find<ThemeService>();

    return GetMaterialApp(
      title: 'App Release Center',
      debugShowCheckedModeBanner: false,
      initialBinding: AppBinding(),
      theme: themeService.themeData,
      home: Platform.isAndroid || Platform.isIOS
          ? const MobileControlView()
          : AuthGate(firebaseConfigured: firebaseConfigured),
    );
  }
}
