import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local display preferences, independent of a project or signed-in account.
class AppSettingsService extends GetxService {
  static const fontScaleKey = 'app_font_scale';
  static const interfaceScaleKey = 'app_interface_scale';
  static const minFontScale = 0.8;
  static const maxFontScale = 1.6;
  static const minInterfaceScale = 0.8;
  static const maxInterfaceScale = 1.4;

  final fontScale = 1.0.obs;
  final interfaceScale = 1.0.obs;
  final saveError = ''.obs;
  late final SharedPreferences _preferences;
  Future<void> _pendingSave = Future<void>.value();

  Future<AppSettingsService> init() async {
    _preferences = await SharedPreferences.getInstance();
    fontScale.value = _bounded(
      _preferences.get(fontScaleKey),
      minFontScale,
      maxFontScale,
    );
    interfaceScale.value = _bounded(
      _preferences.get(interfaceScaleKey),
      minInterfaceScale,
      maxInterfaceScale,
    );
    return this;
  }

  Future<void> setFontScale(double value) =>
      _set(fontScale, fontScaleKey, value, minFontScale, maxFontScale);

  Future<void> setInterfaceScale(double value) => _set(
    interfaceScale,
    interfaceScaleKey,
    value,
    minInterfaceScale,
    maxInterfaceScale,
  );

  Future<void> resetDisplay() async {
    await Future.wait([setFontScale(1), setInterfaceScale(1)]);
  }

  Future<void> _set(
    RxDouble target,
    String key,
    double value,
    double min,
    double max,
  ) {
    final next = _bounded(value, min, max);
    if (target.value == next && saveError.value.isEmpty) return _pendingSave;
    target.value = next;
    // Sliders can issue several writes before the first one completes.
    _pendingSave = _pendingSave.then((_) async {
      try {
        if (!await _preferences.setDouble(key, next)) {
          throw StateError('Không ghi được tùy chọn hiển thị.');
        }
        saveError.value = '';
      } catch (_) {
        saveError.value = 'Chưa lưu được thay đổi. Hãy thử lại.';
      }
    });
    return _pendingSave;
  }

  static double _bounded(Object? value, double min, double max) {
    if (value is! num || !value.isFinite) return 1;
    return value.toDouble().clamp(min, max);
  }
}
