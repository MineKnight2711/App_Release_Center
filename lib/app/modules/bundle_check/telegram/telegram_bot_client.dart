import 'dart:io';

import 'package:app_management_center/app/models/telegram_release_settings.dart';
import 'package:app_management_center/app/services/telegram_release_notification_service.dart';

class TelegramBotException implements Exception {
  const TelegramBotException(this.message, {this.code});

  final String message;

  /// Telegram's `error_code`, e.g. 409 while a webhook is set.
  final int? code;

  @override
  String toString() => message;
}

class TgDocument {
  const TgDocument({
    required this.fileId,
    required this.fileUniqueId,
    required this.fileName,
    this.fileSize,
  });

  static TgDocument? fromJson(Object? json) {
    if (json is! Map) return null;
    final fileId = json['file_id'];
    final unique = json['file_unique_id'];
    if (fileId is! String || unique is! String) return null;
    return TgDocument(
      fileId: fileId,
      fileUniqueId: unique,
      fileName: (json['file_name'] as String?) ?? '',
      fileSize: (json['file_size'] as num?)?.toInt(),
    );
  }

  final String fileId;
  final String fileUniqueId;
  final String fileName;
  final int? fileSize;

  bool get isAab => fileName.toLowerCase().endsWith('.aab');
}

class TgMessage {
  const TgMessage({
    required this.messageId,
    required this.chatId,
    required this.chatType,
    required this.date,
    this.chatTitle = '',
    this.fromId,
    this.fromName = '',
    this.text = '',
    this.document,
    this.replyTo,
  });

  static TgMessage? fromJson(Object? json) {
    if (json is! Map) return null;
    final chat = json['chat'];
    final id = json['message_id'];
    if (chat is! Map || id is! num || chat['id'] is! num) return null;
    final from = json['from'];
    final name = from is Map
        ? [
            from['first_name'],
            from['last_name'],
          ].whereType<String>().join(' ').trim()
        : '';
    return TgMessage(
      messageId: id.toInt(),
      chatId: (chat['id'] as num).toInt(),
      chatType: (chat['type'] as String?) ?? '',
      chatTitle: (chat['title'] as String?) ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(
        ((json['date'] as num?)?.toInt() ?? 0) * 1000,
      ),
      fromId: from is Map ? (from['id'] as num?)?.toInt() : null,
      fromName: name.isNotEmpty
          ? name
          : (from is Map ? (from['username'] as String?) ?? '' : ''),
      text: (json['text'] as String?) ?? (json['caption'] as String?) ?? '',
      document: TgDocument.fromJson(json['document']),
      replyTo: TgMessage.fromJson(json['reply_to_message']),
    );
  }

  final int messageId;
  final int chatId;

  /// `private`, `group`, `supergroup`, `channel`.
  final String chatType;
  final String chatTitle;
  final DateTime date;
  final int? fromId;
  final String fromName;
  final String text;
  final TgDocument? document;
  final TgMessage? replyTo;

  bool get isPrivate => chatType == 'private';
}

class TgCallbackQuery {
  const TgCallbackQuery({
    required this.id,
    required this.data,
    this.fromId,
    this.fromName = '',
    this.message,
  });

  static TgCallbackQuery? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    final from = json['from'];
    return TgCallbackQuery(
      id: json['id'] as String,
      data: (json['data'] as String?) ?? '',
      fromId: from is Map ? (from['id'] as num?)?.toInt() : null,
      fromName: from is Map ? (from['first_name'] as String?) ?? '' : '',
      message: TgMessage.fromJson(json['message']),
    );
  }

  final String id;
  final String data;
  final int? fromId;
  final String fromName;

  /// The bot message whose button was pressed.
  final TgMessage? message;
}

class TgUpdate {
  const TgUpdate({required this.updateId, this.message, this.callbackQuery});

  static TgUpdate? fromJson(Object? json) {
    if (json is! Map || json['update_id'] is! num) return null;
    return TgUpdate(
      updateId: (json['update_id'] as num).toInt(),
      message: TgMessage.fromJson(json['message'] ?? json['channel_post']),
      callbackQuery: TgCallbackQuery.fromJson(json['callback_query']),
    );
  }

  final int updateId;
  final TgMessage? message;
  final TgCallbackQuery? callbackQuery;
}

class TgInlineButton {
  const TgInlineButton(this.text, this.callbackData);

  final String text;

  /// At most 64 bytes, a Bot API limit.
  final String callbackData;

  Map<String, Object?> toJson() => {
    'text': text,
    'callback_data': callbackData,
  };
}

/// The Bot API calls the AAB bot makes, against the cloud or a local server.
///
/// Built on the release notifier's [TelegramHttpClient] so tests swap the
/// transport the same way. The token never appears in an error message.
class TelegramBotClient {
  const TelegramBotClient({
    required this.http,
    required this.token,
    this.apiBaseUrl = '',
  });

  final TelegramHttpClient http;
  final String token;
  final String apiBaseUrl;

  Future<Object?> call(String method, Map<String, Object?> body) async {
    final TelegramHttpResponse response;
    try {
      response = await http.postJson(
        telegramMethodUri(apiBaseUrl, token, method),
        body,
      );
    } on TelegramReleaseNotificationException catch (error) {
      throw TelegramBotException(_redact(error.message));
    }
    final json = response.body;
    if (json is Map && json['ok'] == true) return json['result'];
    final description = json is Map ? json['description'] : null;
    throw TelegramBotException(
      description is String
          ? _redact(description)
          : 'Telegram trả lỗi HTTP ${response.statusCode}.',
      code: json is Map ? (json['error_code'] as num?)?.toInt() : null,
    );
  }

  Future<String> getMeUsername() async {
    final result = await call('getMe', const {});
    return result is Map ? (result['username'] as String?) ?? '' : '';
  }

  /// Long-polls for updates after [offset]. [timeoutSeconds] stays under the
  /// HTTP client's own request timeout.
  Future<List<TgUpdate>> getUpdates({
    int? offset,
    int timeoutSeconds = 20,
  }) async {
    final result = await call('getUpdates', {
      'offset': ?offset,
      'timeout': timeoutSeconds,
      'allowed_updates': const ['message', 'channel_post', 'callback_query'],
    });
    if (result is! List) return const [];
    return [for (final item in result) ?TgUpdate.fromJson(item)];
  }

  Future<int?> sendMessage(
    int chatId,
    String text, {
    int? replyTo,
    List<List<TgInlineButton>>? keyboard,
  }) async {
    final result = await call('sendMessage', {
      'chat_id': chatId,
      'text': _clip(text),
      if (replyTo != null)
        'reply_parameters': {
          'message_id': replyTo,
          'allow_sending_without_reply': true,
        },
      if (keyboard != null)
        'reply_markup': {
          'inline_keyboard': [
            for (final row in keyboard) [for (final b in row) b.toJson()],
          ],
        },
      'link_preview_options': const {'is_disabled': true},
    });
    return result is Map ? (result['message_id'] as num?)?.toInt() : null;
  }

  Future<void> editMessageText(int chatId, int messageId, String text) async {
    await call('editMessageText', {
      'chat_id': chatId,
      'message_id': messageId,
      'text': _clip(text),
      'link_preview_options': const {'is_disabled': true},
    });
  }

  Future<void> answerCallbackQuery(String id, {String text = ''}) async {
    await call('answerCallbackQuery', {
      'callback_query_id': id,
      if (text.isNotEmpty) 'text': text,
    });
  }

  /// `file_path` of a file: relative on the cloud, absolute on a local
  /// server started with `--local`.
  Future<String> getFilePath(String fileId) async {
    final result = await call('getFile', {'file_id': fileId});
    final path = result is Map ? result['file_path'] : null;
    if (path is! String || path.isEmpty) {
      throw const TelegramBotException(
        'Telegram không trả đường dẫn file. Trên cloud, bot chỉ tải được '
        'file tới 20 MB.',
      );
    }
    return path;
  }

  Future<void> sendPhoto(
    int chatId,
    File photo, {
    String caption = '',
    int? replyTo,
  }) async {
    final TelegramHttpResponse response;
    try {
      response = await http.postMultipartFile(
        telegramMethodUri(apiBaseUrl, token, 'sendPhoto'),
        fields: {
          'chat_id': '$chatId',
          if (caption.isNotEmpty) 'caption': _clip(caption, 1024),
          if (replyTo != null) 'reply_to_message_id': '$replyTo',
        },
        fileField: 'photo',
        file: photo,
        fileName: 'screen.png',
        contentType: 'image/png',
      );
    } on TelegramReleaseNotificationException catch (error) {
      throw TelegramBotException(_redact(error.message));
    }
    final json = response.body;
    if (json is Map && json['ok'] == true) return;
    throw TelegramBotException(
      json is Map && json['description'] is String
          ? _redact(json['description'] as String)
          : 'Gửi ảnh lỗi HTTP ${response.statusCode}.',
    );
  }

  /// Moves the bot off the server it is logged into. Called against the
  /// cloud once before using a local server; the cloud refuses it back for
  /// 10 minutes afterwards.
  Future<void> logOut() async {
    await call('logOut', const {});
  }

  String _redact(String text) =>
      token.isEmpty ? text : text.replaceAll(token, '[token]');

  static String _clip(
    String text, [
    int limit = telegramMessageCharacterLimit,
  ]) {
    if (text.runes.length <= limit) return text;
    return '${String.fromCharCodes(text.runes.take(limit - 1))}…';
  }
}
