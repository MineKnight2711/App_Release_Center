import 'package:app_release_center/app/bindings/app_binding.dart';
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
    const seed = Color(0xFF0F766E);

    return GetMaterialApp(
      title: 'App Release Center',
      debugShowCheckedModeBanner: false,
      initialBinding: AppBinding(),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
          surface: const Color(0xFFF7F8FA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        fontFamily: 'Segoe UI',
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          isDense: true,
        ),
      ),
      home: const HomeView(),
    );
  }
}
