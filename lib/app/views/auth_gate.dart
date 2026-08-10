import 'package:app_release_center/app/models/auth_models.dart';
import 'package:app_release_center/app/services/auth_service.dart';
import 'package:app_release_center/app/services/theme_service.dart';
import 'package:app_release_center/app/theme/cyber_theme.dart';
import 'package:app_release_center/app/views/home_view.dart';
import 'package:app_release_center/app/views/login_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.firebaseConfigured});

  final bool firebaseConfigured;

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthService>();

    return Obx(() {
      return switch (auth.authStatus.value) {
        AuthStatus.authenticated => const HomeView(),
        AuthStatus.teamRequired => const TeamSetupView(),
        AuthStatus.unauthenticated => LoginView(
          firebaseConfigured: firebaseConfigured,
        ),
        AuthStatus.unavailable => LoginView(
          firebaseConfigured: firebaseConfigured,
        ),
        AuthStatus.initializing => const _AuthLoadingView(),
      };
    });
  }
}

class _AuthLoadingView extends StatelessWidget {
  const _AuthLoadingView();

  @override
  Widget build(BuildContext context) {
    final themeService = Get.find<ThemeService>();
    final _ = themeService.choice.value;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: AppCyberTheme.backdropGradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppCyberTheme.neonGreen,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Opening App Release Center',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
