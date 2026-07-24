class GoogleDriveReleaseSettings {
  const GoogleDriveReleaseSettings({
    this.useDriveFallbackEnabled = false,
    this.sendApkLinkToTelegramEnabled = false,
    this.includeReleaseNotesInTelegramLink = false,
    this.oauthClientId = '',
    this.folderId = '',
  });

  final bool useDriveFallbackEnabled;
  final bool sendApkLinkToTelegramEnabled;
  final bool includeReleaseNotesInTelegramLink;
  final String oauthClientId;
  final String folderId;

  bool get hasOAuthClientId => oauthClientId.trim().isNotEmpty;
  bool get hasFolderId => folderId.trim().isNotEmpty;

  GoogleDriveReleaseSettings copyWith({
    bool? useDriveFallbackEnabled,
    bool? sendApkLinkToTelegramEnabled,
    bool? includeReleaseNotesInTelegramLink,
    String? oauthClientId,
    String? folderId,
  }) {
    return GoogleDriveReleaseSettings(
      useDriveFallbackEnabled:
          useDriveFallbackEnabled ?? this.useDriveFallbackEnabled,
      sendApkLinkToTelegramEnabled:
          sendApkLinkToTelegramEnabled ?? this.sendApkLinkToTelegramEnabled,
      includeReleaseNotesInTelegramLink:
          includeReleaseNotesInTelegramLink ??
          this.includeReleaseNotesInTelegramLink,
      oauthClientId: oauthClientId ?? this.oauthClientId,
      folderId: folderId ?? this.folderId,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'useDriveFallbackEnabled': useDriveFallbackEnabled,
      'sendApkLinkToTelegramEnabled': sendApkLinkToTelegramEnabled,
      'includeReleaseNotesInTelegramLink': includeReleaseNotesInTelegramLink,
      'oauthClientId': oauthClientId,
      'folderId': folderId,
    };
  }

  factory GoogleDriveReleaseSettings.fromJson(Map<String, Object?> json) {
    return GoogleDriveReleaseSettings(
      useDriveFallbackEnabled:
          (json['useDriveFallbackEnabled'] as bool?) ?? false,
      sendApkLinkToTelegramEnabled:
          (json['sendApkLinkToTelegramEnabled'] as bool?) ?? false,
      includeReleaseNotesInTelegramLink:
          (json['includeReleaseNotesInTelegramLink'] as bool?) ?? false,
      oauthClientId: (json['oauthClientId'] as String?) ?? '',
      folderId: (json['folderId'] as String?) ?? '',
    );
  }
}
