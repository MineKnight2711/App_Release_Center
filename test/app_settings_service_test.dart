import 'package:app_management_center/app/services/app_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'display sizes persist independently and reset without changing theme',
    () async {
      final settings = await AppSettingsService().init();
      expect(settings.fontScale.value, 1);
      expect(settings.interfaceScale.value, 1);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_choice', 'cyber');
      await settings.setFontScale(1.3);
      await settings.setInterfaceScale(0.9);
      final restored = await AppSettingsService().init();
      expect(restored.fontScale.value, 1.3);
      expect(restored.interfaceScale.value, 0.9);
      await restored.resetDisplay();
      final reset = await AppSettingsService().init();
      expect(reset.fontScale.value, 1);
      expect(reset.interfaceScale.value, 1);
      expect(prefs.getString('theme_choice'), 'cyber');
    },
  );

  test(
    'invalid preferences fall back and values stay within supported range',
    () async {
      SharedPreferences.setMockInitialValues({
        AppSettingsService.fontScaleKey: 'bad',
        AppSettingsService.interfaceScaleKey: double.nan,
      });
      final settings = await AppSettingsService().init();
      expect(settings.fontScale.value, 1);
      expect(settings.interfaceScale.value, 1);
      await settings.setFontScale(10);
      await settings.setInterfaceScale(-2);
      expect(settings.fontScale.value, AppSettingsService.maxFontScale);
      expect(
        settings.interfaceScale.value,
        AppSettingsService.minInterfaceScale,
      );
      await settings.setFontScale(double.infinity);
      expect(settings.fontScale.value, 1);
    },
  );

  test('rapid slider updates save the final value', () async {
    final settings = await AppSettingsService().init();
    await Future.wait([
      settings.setFontScale(1.1),
      settings.setFontScale(1.2),
      settings.setFontScale(1.4),
      settings.setInterfaceScale(1.3),
      settings.resetDisplay(),
    ]);
    final restored = await AppSettingsService().init();
    expect(restored.fontScale.value, 1);
    expect(restored.interfaceScale.value, 1);
  });
}
