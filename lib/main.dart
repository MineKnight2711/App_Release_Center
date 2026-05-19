import 'package:app_release_center/app/bindings/app_binding.dart';
import 'package:app_release_center/app/services/theme_service.dart';
import 'package:app_release_center/app/views/home_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppBinding.initServices();
  runApp(const AppReleaseCenterApp());
}

class AppReleaseCenterApp extends StatelessWidget {
  const AppReleaseCenterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = Get.find<ThemeService>();

    return GetMaterialApp(
      title: 'App Release Center',
      debugShowCheckedModeBanner: false,
      initialBinding: AppBinding(),
      theme: themeService.themeData,
      home: const HomeView(),
    );
  }
}
