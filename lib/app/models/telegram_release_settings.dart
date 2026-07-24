class TelegramReleaseSettings {
  const TelegramReleaseSettings({
    this.autoSendEnabled = false,
    this.chatId = '',
  });

  final bool autoSendEnabled;
  final String chatId;

  bool get hasChatId => chatId.trim().isNotEmpty;

  TelegramReleaseSettings copyWith({bool? autoSendEnabled, String? chatId}) {
    return TelegramReleaseSettings(
      autoSendEnabled: autoSendEnabled ?? this.autoSendEnabled,
      chatId: chatId ?? this.chatId,
    );
  }

  Map<String, Object?> toJson() {
    return {'autoSendEnabled': autoSendEnabled, 'chatId': chatId};
  }

  factory TelegramReleaseSettings.fromJson(Map<String, Object?> json) {
    return TelegramReleaseSettings(
      autoSendEnabled: (json['autoSendEnabled'] as bool?) ?? false,
      chatId: (json['chatId'] as String?) ?? '',
    );
  }
}
