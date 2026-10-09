class TelegramReleaseSettings {
  const TelegramReleaseSettings({
    this.autoSendEnabled = false,
    this.chatId = '',
    this.apiBaseUrl = '',
  });

  final bool autoSendEnabled;
  final String chatId;

  /// Bot API server every call goes to. Empty means Telegram's cloud; a local
  /// `telegram-bot-api` server is e.g. `http://127.0.0.1:8081`.
  final String apiBaseUrl;

  bool get hasChatId => chatId.trim().isNotEmpty;

  bool get usesLocalServer => apiBaseUrl.trim().isNotEmpty;

  TelegramReleaseSettings copyWith({
    bool? autoSendEnabled,
    String? chatId,
    String? apiBaseUrl,
  }) {
    return TelegramReleaseSettings(
      autoSendEnabled: autoSendEnabled ?? this.autoSendEnabled,
      chatId: chatId ?? this.chatId,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'autoSendEnabled': autoSendEnabled,
      'chatId': chatId,
      'apiBaseUrl': apiBaseUrl,
    };
  }

  factory TelegramReleaseSettings.fromJson(Map<String, Object?> json) {
    return TelegramReleaseSettings(
      autoSendEnabled: (json['autoSendEnabled'] as bool?) ?? false,
      chatId: (json['chatId'] as String?) ?? '',
      apiBaseUrl: (json['apiBaseUrl'] as String?) ?? '',
    );
  }
}

const telegramCloudApi = 'https://api.telegram.org';

/// `<base>/bot<token>/<method>` on the cloud or on a local server.
Uri telegramMethodUri(String apiBaseUrl, String token, String method) {
  return _telegramUri(apiBaseUrl, '/bot$token/$method');
}

/// Download URL of a file, for servers that serve files over HTTP.
Uri telegramFileUri(String apiBaseUrl, String token, String filePath) {
  return _telegramUri(apiBaseUrl, '/file/bot$token/$filePath');
}

Uri _telegramUri(String apiBaseUrl, String path) {
  var base = apiBaseUrl.trim();
  if (base.isEmpty) base = telegramCloudApi;
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  final parsed = Uri.parse(base);
  return parsed.replace(path: '${parsed.path}$path');
}
