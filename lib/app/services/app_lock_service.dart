import 'dart:async';

import 'package:app_management_center/app/models/app_lock.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';

/// The platform biometric prompt, behind a seam.
///
/// `local_auth` needs a real Android activity, so nothing that touches it can
/// run under `flutter test`. Every rule about when to prompt lives in
/// [AppLockService] and is exercised against a fake of this.
abstract class BiometricAuthenticator {
  Future<BiometricAvailability> availability();

  /// Returns whether the person proved who they are. A cancelled prompt is a
  /// `false`, not an error: backing out is an ordinary thing to do.
  Future<bool> authenticate(String reason);
}

class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<BiometricAvailability> availability() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return const BiometricAvailability.none();
      // canCheckBiometrics alone is false on a phone that has only a PIN, and
      // a PIN is still a fine way to prove who is holding it.
      final enrolled =
          await _auth.canCheckBiometrics ||
          (await _auth.getAvailableBiometrics()).isNotEmpty;
      return BiometricAvailability(supported: true, enrolled: enrolled);
    } on PlatformException {
      return const BiometricAvailability.none();
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // The prompt survives the app being backgrounded, which on Android it
        // technically is while the system dialog is up.
        persistAcrossBackgrounding: true,
        // A device PIN or pattern stays allowed. Refusing it would lock out
        // anyone whose fingerprint reader is wet, dirty or simply failing,
        // and their fallback is the same credential that guards the phone.
        biometricOnly: false,
      );
    } on PlatformException {
      return false;
    }
  }
}

/// Holds the phone app shut until the person at the phone proves who they are.
///
/// Two separate guards, because they answer different questions: [isLocked]
/// covers the console as a whole, and [confirmSensitiveAction] stands in front
/// of the individual commands that cannot be undone.
class AppLockService extends GetxService with WidgetsBindingObserver {
  AppLockService({
    required ProjectStoreService store,
    required BiometricAuthenticator authenticator,
    DateTime Function()? now,
  }) : _store = store,
       _authenticator = authenticator,
       _now = now ?? DateTime.now;

  final ProjectStoreService _store;
  final BiometricAuthenticator _authenticator;
  final DateTime Function() _now;

  final settings = const AppLockSettings().obs;
  final availability = const BiometricAvailability.none().obs;
  final isLocked = false.obs;
  final isPrompting = false.obs;
  final status = ''.obs;

  DateTime? _backgroundedAt;

  Future<AppLockService> init() async {
    settings.value = _store.appLockSettings;
    availability.value = await _authenticator.availability();
    // A lock that cannot be opened is worse than no lock, so a device that
    // lost its enrolment (factory reset, biometrics removed) starts unlocked
    // rather than trapping the person behind a prompt that always fails.
    isLocked.value = settings.value.enabled && availability.value.usable;
    WidgetsBinding.instance.addObserver(this);
    return this;
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  bool get isEnabled => settings.value.enabled && availability.value.usable;

  /// Turns the lock on, but only after one successful prompt.
  ///
  /// Enabling it on an unverified promise that biometrics work would let
  /// someone lock themselves out of a paired phone with no way back in short
  /// of clearing app data and re-pairing.
  Future<bool> setEnabled(bool enabled) async {
    if (!enabled) {
      await _save(settings.value.copyWith(enabled: false));
      isLocked.value = false;
      status.value = 'Đã tắt khóa ứng dụng.';
      return true;
    }

    availability.value = await _authenticator.availability();
    if (!availability.value.supported) {
      status.value = 'Máy này không hỗ trợ khóa bằng sinh trắc học.';
      return false;
    }
    if (!availability.value.enrolled) {
      status.value =
          'Chưa đăng ký khuôn mặt, vân tay hay mã PIN nào trên máy. '
          'Thiết lập trong phần cài đặt bảo mật của Android rồi bật lại.';
      return false;
    }
    if (!await _prompt(AppLockReason.open)) {
      status.value = 'Chưa xác thực được nên khóa ứng dụng vẫn tắt.';
      return false;
    }

    await _save(settings.value.copyWith(enabled: true));
    isLocked.value = false;
    status.value = 'Đã bật khóa ứng dụng.';
    return true;
  }

  Future<void> setProtectSensitiveActions(bool value) async {
    await _save(settings.value.copyWith(protectSensitiveActions: value));
  }

  Future<void> setGraceSeconds(int seconds) async {
    await _save(settings.value.copyWith(graceSeconds: seconds));
  }

  /// Opens the console. Returns whether it is now unlocked.
  Future<bool> unlock() async {
    if (!isLocked.value) return true;
    if (!await _prompt(AppLockReason.open)) {
      status.value = 'Xác thực không thành công.';
      return false;
    }
    isLocked.value = false;
    status.value = '';
    return true;
  }

  /// The gate in front of one irreversible command.
  ///
  /// Answers `true` when the lock is off or the action is not covered, so
  /// callers can treat it as "may I proceed" and not branch on settings.
  Future<bool> confirmSensitiveAction(AppLockReason reason) async {
    if (!isEnabled) return true;
    if (!settings.value.protectSensitiveActions) return true;
    return _prompt(reason);
  }

  /// Prompts whatever the app-lock settings say.
  ///
  /// [confirmSensitiveAction] is a policy the person can turn off; this is not.
  /// It guards the saved Windows password, which is the only thing standing
  /// between a phone in someone else's hand and a signed-in desktop, so it
  /// cannot be a preference.
  Future<bool> confirmUnconditionally(AppLockReason reason) async {
    if (!availability.value.usable) return false;
    return _prompt(reason);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isEnabled) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Only the first of these matters: Android sends several on the way
        // out, and taking the later ones would keep pushing the deadline.
        _backgroundedAt ??= _now();
      case AppLifecycleState.resumed:
        final left = _backgroundedAt;
        _backgroundedAt = null;
        if (left == null) return;
        if (_now().difference(left) >= settings.value.grace) {
          isLocked.value = true;
        }
      case AppLifecycleState.inactive:
        // Raised by a passing notification shade or by the biometric prompt
        // itself. Treating it as leaving would lock the app behind its own
        // dialog.
        break;
    }
  }

  Future<bool> _prompt(AppLockReason reason) async {
    if (isPrompting.value) return false;
    isPrompting.value = true;
    try {
      return await _authenticator.authenticate(reason.prompt);
    } finally {
      isPrompting.value = false;
    }
  }

  Future<void> _save(AppLockSettings updated) async {
    await _store.saveAppLockSettings(updated);
    settings.value = updated;
  }
}
