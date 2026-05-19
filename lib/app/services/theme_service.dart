import 'package:app_release_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends GetxService {
  static const _themeKey = 'theme_choice';

  late final SharedPreferences _preferences;

  final choice = AppThemeChoice.cyber.obs;

  Future<ThemeService> init() async {
    _preferences = await SharedPreferences.getInstance();
    choice.value = _choiceFromKey(_preferences.getString(_themeKey));
    AppCyberTheme.activate(choice.value);
    return this;
  }

  ThemeData get themeData => AppCyberTheme.themeData(choice.value);

  Future<void> setChoice(AppThemeChoice nextChoice) async {
    if (choice.value == nextChoice) return;

    final nextTheme = AppCyberTheme.themeData(nextChoice);
    choice.value = nextChoice;
    Get.changeTheme(nextTheme);
    await _preferences.setString(_themeKey, nextChoice.name);
  }

  AppThemeChoice _choiceFromKey(String? key) {
    for (final option in AppThemeChoice.values) {
      if (option.name == key) return option;
    }
    return AppThemeChoice.cyber;
  }
}
