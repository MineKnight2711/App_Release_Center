/// How the phone app guards the link it keeps to a desktop.
///
/// The link survives restarts on purpose — re-pairing by QR every morning
/// would make the app unusable — but that persistence is exactly what needs a
/// lock: the stored control token runs shell commands, powers the machine off
/// and unlocks Windows, so a phone handed to someone else hands all of that
/// over with it.
class AppLockSettings {
  const AppLockSettings({
    this.enabled = false,
    this.protectSensitiveActions = true,
    this.graceSeconds = defaultGraceSeconds,
  });

  /// Long enough to answer a notification or check a code in another app
  /// without re-authenticating, short enough that a phone left on a desk is
  /// not left open.
  static const defaultGraceSeconds = 60;

  /// Requires biometrics before the console is shown at all.
  final bool enabled;

  /// Asks again, per action, for the commands that cannot be taken back:
  /// unlocking Windows, and shutting down or restarting the machine.
  ///
  /// Kept separate from [enabled] because the two answer different questions.
  /// Opening the app proves who is holding the phone right now; a second
  /// prompt in front of a shutdown proves the press was meant.
  final bool protectSensitiveActions;

  /// How long the app may stay backgrounded before it locks again.
  final int graceSeconds;

  Duration get grace => Duration(seconds: graceSeconds);

  AppLockSettings copyWith({
    bool? enabled,
    bool? protectSensitiveActions,
    int? graceSeconds,
  }) {
    return AppLockSettings(
      enabled: enabled ?? this.enabled,
      protectSensitiveActions:
          protectSensitiveActions ?? this.protectSensitiveActions,
      graceSeconds: graceSeconds ?? this.graceSeconds,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'protectSensitiveActions': protectSensitiveActions,
      'graceSeconds': graceSeconds,
    };
  }

  factory AppLockSettings.fromJson(Map<String, Object?> json) {
    return AppLockSettings(
      enabled: json['enabled'] == true,
      // Absent means a settings blob written before this flag existed. It
      // defaults on: someone who turned the lock on wanted the protection.
      protectSensitiveActions: json['protectSensitiveActions'] != false,
      graceSeconds: _grace(json['graceSeconds']),
    );
  }

  static int _grace(Object? value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed < 0) return defaultGraceSeconds;
    // A grace longer than a few minutes stops being a grace period.
    return parsed > 600 ? 600 : parsed;
  }
}

/// Why the app is asking for a fingerprint or a face right now.
///
/// The system prompt shows this, and a person who is asked twice in a minute
/// deserves to know which press caused the second ask.
enum AppLockReason {
  open,
  unlockWindows,
  powerAction,
  saveUnlockSession;

  String get prompt => switch (this) {
    AppLockReason.open => 'Xác thực để mở Management Remote',
    AppLockReason.unlockWindows => 'Xác thực để mở khóa máy tính',
    AppLockReason.powerAction => 'Xác thực để gửi lệnh nguồn cho máy tính',
    AppLockReason.saveUnlockSession =>
      'Xác thực để lưu mật khẩu Windows trên máy này',
  };
}

/// What the device can actually do, as reported by the platform.
class BiometricAvailability {
  const BiometricAvailability({
    required this.supported,
    required this.enrolled,
  });

  const BiometricAvailability.none() : supported = false, enrolled = false;

  /// The hardware exists and the OS exposes it.
  final bool supported;

  /// Something is actually enrolled — a face, a fingerprint, or a device
  /// passcode. Hardware with nothing enrolled cannot authenticate anyone, so
  /// the lock must refuse to turn on rather than lock the person out.
  final bool enrolled;

  bool get usable => supported && enrolled;
}
