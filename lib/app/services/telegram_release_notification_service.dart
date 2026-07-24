import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_release_center/app/models/telegram_release_settings.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:app_release_center/app/services/telegram_credential_store_service.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

abstract class TelegramHttpClient {
  Future<TelegramHttpResponse> postJson(Uri url, Map<String, Object?> body);

  Future<TelegramHttpResponse> postMultipartFile(
    Uri url, {
    required Map<String, String> fields,
    required String fileField,
    required File file,
    required String fileName,
    required String contentType,
  });
}

class TelegramHttpResponse {
  const TelegramHttpResponse({required this.statusCode, this.body});

  final int statusCode;
  final Object? body;

  bool get isOk => statusCode >= 200 && statusCode < 300;
}

class DartTelegramHttpClient implements TelegramHttpClient {
  @override
  Future<TelegramHttpResponse> postJson(
    Uri url,
    Map<String, Object?> body,
  ) async {
    final client = HttpClient()..connectionTimeout = _connectionTimeout;

    try {
      final request = await client.postUrl(url);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      final payload = utf8.encode(jsonEncode(body));
      request.contentLength = payload.length;
      request.add(payload);

      final response = await request.close().timeout(_requestTimeout);
      final rawBody = await response.transform(utf8.decoder).join();
      Object? decodedBody;
      if (rawBody.trim().isNotEmpty) {
        try {
          decodedBody = jsonDecode(rawBody);
        } on FormatException {
          decodedBody = rawBody;
        }
      }

      return TelegramHttpResponse(
        statusCode: response.statusCode,
        body: decodedBody,
      );
    } on TimeoutException {
      throw const TelegramReleaseNotificationException(
        'Telegram request timed out.',
      );
    } on SocketException catch (error) {
      throw TelegramReleaseNotificationException(
        'Network error while calling Telegram: ${error.message}',
      );
    } on HandshakeException {
      throw const TelegramReleaseNotificationException(
        'Secure connection to Telegram failed.',
      );
    } on HttpException {
      throw const TelegramReleaseNotificationException(
        'Telegram HTTP request could not be completed.',
      );
    } catch (_) {
      throw const TelegramReleaseNotificationException(
        'Unexpected error while calling Telegram.',
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<TelegramHttpResponse> postMultipartFile(
    Uri url, {
    required Map<String, String> fields,
    required String fileField,
    required File file,
    required String fileName,
    required String contentType,
  }) async {
    final client = HttpClient()..connectionTimeout = _connectionTimeout;
    final boundary =
        'app-release-center-${DateTime.now().microsecondsSinceEpoch}';

    try {
      final request = await client.postUrl(url);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );

      for (final entry in fields.entries) {
        request.add(
          utf8.encode(
            '--$boundary\r\n'
            'Content-Disposition: form-data; name="${entry.key}"\r\n\r\n'
            '${entry.value}\r\n',
          ),
        );
      }

      final safeFileName = fileName.replaceAll(RegExp(r'["\r\n]'), '_');
      request.add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="$fileField"; '
          'filename="$safeFileName"\r\n'
          'Content-Type: $contentType\r\n\r\n',
        ),
      );
      await for (final chunk in file.openRead()) {
        request.add(chunk);
      }
      request.add(utf8.encode('\r\n--$boundary--\r\n'));

      final response = await request.close().timeout(_uploadRequestTimeout);
      return _readResponse(response);
    } on TimeoutException {
      throw const TelegramReleaseNotificationException(
        'Telegram file upload timed out.',
      );
    } on SocketException catch (error) {
      throw TelegramReleaseNotificationException(
        'Network error while uploading to Telegram: ${error.message}',
      );
    } on HandshakeException {
      throw const TelegramReleaseNotificationException(
        'Secure connection to Telegram failed.',
      );
    } on FileSystemException catch (error) {
      throw TelegramReleaseNotificationException(
        'Failed to read APK for Telegram upload: ${error.message}',
      );
    } on HttpException {
      throw const TelegramReleaseNotificationException(
        'Telegram file upload could not be completed.',
      );
    } catch (_) {
      throw const TelegramReleaseNotificationException(
        'Unexpected error while uploading file to Telegram.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<TelegramHttpResponse> _readResponse(
    HttpClientResponse response,
  ) async {
    final rawBody = await response.transform(utf8.decoder).join();
    Object? decodedBody;
    if (rawBody.trim().isNotEmpty) {
      try {
        decodedBody = jsonDecode(rawBody);
      } on FormatException {
        decodedBody = rawBody;
      }
    }
    return TelegramHttpResponse(
      statusCode: response.statusCode,
      body: decodedBody,
    );
  }
}

class TelegramReleaseNotificationService extends GetxService {
  TelegramReleaseNotificationService({
    required ProjectStoreService store,
    required TelegramCredentialStoreService credentialStore,
    required TelegramHttpClient httpClient,
  }) : _store = store,
       _credentialStore = credentialStore,
       _httpClient = httpClient;

  final ProjectStoreService _store;
  final TelegramCredentialStoreService _credentialStore;
  final TelegramHttpClient _httpClient;

  TelegramReleaseSettings get settings => _store.telegramReleaseSettings;

  Future<void> saveSettings(TelegramReleaseSettings settings) {
    return _store.saveTelegramReleaseSettings(settings);
  }

  Future<String?> readBotToken() {
    return _credentialStore.readBotToken();
  }

  Future<void> saveBotToken(String? token) {
    return _credentialStore.saveBotToken(token);
  }

  Future<void> sendTestMessage() {
    return _sendText('✅ App Release Center kết nối Telegram thành công.');
  }

  Future<void> sendReleaseNote({
    required String appDisplayName,
    required String? version,
    required String releaseNotes,
  }) {
    final trimmedAppName = appDisplayName.trim();
    final trimmedNotes = releaseNotes.trim();
    if (trimmedAppName.isEmpty) {
      throw const TelegramReleaseNotificationException(
        'App display name is required.',
      );
    }
    if (trimmedNotes.isEmpty) {
      throw const TelegramReleaseNotificationException(
        'Release notes are required.',
      );
    }

    final normalizedVersion = version?.trim();
    final versionLabel = normalizedVersion == null || normalizedVersion.isEmpty
        ? 'không xác định'
        : normalizedVersion;
    final message =
        '🚀 RELEASE NOTE MỚI\n'
        '📱 Ứng dụng: $trimmedAppName\n'
        '🏷 Phiên bản: $versionLabel\n\n'
        '📝 Release note:\n'
        '$trimmedNotes';
    return _sendText(message);
  }

  Future<void> sendReleaseApk({
    required File apkFile,
    required String appDisplayName,
    required String version,
    required DateTime buildDate,
  }) async {
    if (!apkFile.existsSync()) {
      throw const TelegramReleaseNotificationException(
        'Release APK file does not exist.',
      );
    }
    final fileSize = await apkFile.length();
    if (fileSize > telegramDocumentMaxBytes) {
      throw TelegramReleaseNotificationException(
        'APK is ${_formatMegabytes(fileSize)} MB; Telegram Bot API allows '
        'documents up to 50 MB.',
      );
    }

    final currentSettings = settings;
    final chatId = currentSettings.chatId.trim();
    if (chatId.isEmpty) {
      throw const TelegramReleaseNotificationException(
        'Telegram chat ID is required.',
      );
    }
    final token = (await readBotToken())?.trim() ?? '';
    if (token.isEmpty) {
      throw const TelegramReleaseNotificationException(
        'Telegram bot token is required.',
      );
    }

    final day = buildDate.day.toString().padLeft(2, '0');
    final month = buildDate.month.toString().padLeft(2, '0');
    final caption =
        '📦 APK ${appDisplayName.trim()}\n'
        '🏷 Phiên bản: ${version.trim()}\n'
        '📅 Ngày build: $day/$month/${buildDate.year}';
    final response = await _httpClient.postMultipartFile(
      Uri.https('api.telegram.org', '/bot$token/sendDocument'),
      fields: {'chat_id': chatId, 'caption': caption},
      fileField: 'document',
      file: apkFile,
      fileName: p.basename(apkFile.path),
      contentType: 'application/vnd.android.package-archive',
    );
    _ensureTelegramSuccess(response, token);
  }

  Future<void> sendReleaseApkLink({
    required String appDisplayName,
    required String version,
    required String fileName,
    required int fileSizeBytes,
    required String downloadUrl,
    String? releaseNotes,
    bool oversized = false,
  }) {
    final trimmedAppName = appDisplayName.trim();
    final trimmedVersion = version.trim();
    final trimmedFileName = fileName.trim();
    final trimmedUrl = downloadUrl.trim();
    if (trimmedAppName.isEmpty) {
      throw const TelegramReleaseNotificationException(
        'App display name is required.',
      );
    }
    if (trimmedVersion.isEmpty) {
      throw const TelegramReleaseNotificationException(
        'Release APK version is required.',
      );
    }
    if (trimmedFileName.isEmpty) {
      throw const TelegramReleaseNotificationException(
        'Release APK file name is required.',
      );
    }
    if (trimmedUrl.isEmpty) {
      throw const TelegramReleaseNotificationException(
        'Google Drive download link is required.',
      );
    }

    final trimmedReleaseNotes = releaseNotes?.trim() ?? '';
    final intro = oversized
        ? 'APK is over Telegram 50 MB limit, so it was uploaded to Google Drive.'
        : 'Release APK uploaded to Google Drive.';
    final message =
        '$intro\n\n'
        'App: $trimmedAppName\n'
        'Version: $trimmedVersion\n'
        'File: $trimmedFileName\n'
        'Size: ${_formatMegabytes(fileSizeBytes)} MB\n\n'
        'Download link:\n'
        '$trimmedUrl'
        '${trimmedReleaseNotes.isEmpty ? '' : '\n\nRelease notes:\n$trimmedReleaseNotes'}';
    return _sendText(message);
  }

  Future<void> _sendText(String text) async {
    final currentSettings = settings;
    final chatId = currentSettings.chatId.trim();
    if (chatId.isEmpty) {
      throw const TelegramReleaseNotificationException(
        'Telegram chat ID is required.',
      );
    }

    final token = (await readBotToken())?.trim() ?? '';
    if (token.isEmpty) {
      throw const TelegramReleaseNotificationException(
        'Telegram bot token is required.',
      );
    }

    if (text.runes.length > telegramMessageCharacterLimit) {
      throw const TelegramReleaseNotificationException(
        'Telegram message exceeds the 4096-character limit.',
      );
    }

    final response = await _httpClient.postJson(
      Uri.https('api.telegram.org', '/bot$token/sendMessage'),
      {'chat_id': chatId, 'text': text},
    );
    _ensureTelegramSuccess(response, token);
  }

  void _ensureTelegramSuccess(TelegramHttpResponse response, String token) {
    final body = response.body;
    final bodyMap = body is Map ? body : null;
    final telegramOk = bodyMap?['ok'] == true;
    if (response.isOk && telegramOk) return;

    final rawDescription = bodyMap?['description'];
    final description = rawDescription is String
        ? _sanitize(rawDescription, token)
        : '';
    if (!response.isOk) {
      final suffix = description.isEmpty ? '' : ': $description';
      throw TelegramReleaseNotificationException(
        'Telegram request failed (${response.statusCode})$suffix',
      );
    }
    if (bodyMap == null) {
      throw const TelegramReleaseNotificationException(
        'Telegram returned an invalid response.',
      );
    }

    throw TelegramReleaseNotificationException(
      description.isEmpty ? 'Telegram rejected the message.' : description,
    );
  }

  String _sanitize(String value, String token) {
    if (token.isEmpty) return value;
    return value.replaceAll(token, '[redacted]');
  }

  String _formatMegabytes(int bytes) {
    return (bytes / (1024 * 1024)).toStringAsFixed(1);
  }
}

class TelegramReleaseNotificationException implements Exception {
  const TelegramReleaseNotificationException(this.message);

  final String message;

  @override
  String toString() => message;
}

const telegramMessageCharacterLimit = 4096;
const telegramDocumentMaxBytes = 50 * 1024 * 1024;
const _connectionTimeout = Duration(seconds: 20);
const _requestTimeout = Duration(seconds: 30);
const _uploadRequestTimeout = Duration(minutes: 5);
