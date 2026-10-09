/// What the phone remembers about a saved Windows unlock password.
///
/// Deliberately holds no secret. The password itself lives in secure storage
/// and only comes out behind a biometric prompt; this is the part the console
/// needs in order to draw itself — whether a password is saved at all, and who
/// it belongs to — and reading that must not require a prompt, or the screen
/// could not be painted without interrogating the person first.
class RemoteUnlockSession {
  const RemoteUnlockSession({
    required this.accountName,
    required this.desktopId,
    required this.savedAt,
  });

  const RemoteUnlockSession.none()
    : accountName = '',
      desktopId = '',
      savedAt = null;

  /// The Windows account the saved password signs in, as the desktop reports
  /// it (`MACHINE\user`).
  final String accountName;

  /// Which desktop it was saved for.
  final String desktopId;

  final DateTime? savedAt;

  bool get exists => accountName.isNotEmpty && desktopId.isNotEmpty;

  /// Whether the saved password may be sent to the machine now on screen.
  ///
  /// A password saved for one account is wrong for another, and sending it
  /// anyway would hand a Windows password to a machine it does not belong to
  /// and burn a failed sign-in attempt on the one it does.
  bool matches({required String accountName, required String desktopId}) {
    return exists &&
        this.desktopId == desktopId &&
        this.accountName.toLowerCase() == accountName.toLowerCase();
  }

  Map<String, Object?> toJson() {
    return {
      'accountName': accountName,
      'desktopId': desktopId,
      'savedAt': savedAt?.toUtc().toIso8601String(),
    };
  }

  factory RemoteUnlockSession.fromJson(Map<String, Object?> json) {
    final savedAt = json['savedAt']?.toString();
    return RemoteUnlockSession(
      accountName: json['accountName']?.toString().trim() ?? '',
      desktopId: json['desktopId']?.toString().trim() ?? '',
      savedAt: savedAt == null ? null : DateTime.tryParse(savedAt)?.toLocal(),
    );
  }
}
