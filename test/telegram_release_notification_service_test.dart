import 'dart:io';

import 'package:app_release_center/app/models/telegram_release_settings.dart';
import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:app_release_center/app/services/telegram_credential_store_service.dart';
import 'package:app_release_center/app/services/telegram_release_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('sends exact release metadata and notes to a numeric group', () async {
    final harness = await _TelegramHarness.create(chatId: '-1001234567890');
    harness.client.responses.add(
      const TelegramHttpResponse(statusCode: 200, body: {'ok': true}),
    );

    await harness.service.sendReleaseNote(
      appDisplayName: 'VNeTrip',
      version: '1.2.3+45',
      releaseNotes: 'Cải thiện độ ổn định.',
    );

    final request = harness.client.requests.single;
    expect(request.url.host, 'api.telegram.org');
    expect(request.url.path, '/botsecret-token/sendMessage');
    expect(request.body['chat_id'], '-1001234567890');
    expect(
      request.body['text'],
      '🚀 RELEASE NOTE MỚI\n'
      '📱 Ứng dụng: VNeTrip\n'
      '🏷 Phiên bản: 1.2.3+45\n\n'
      '📝 Release note:\n'
      'Cải thiện độ ổn định.',
    );
  });

  test('accepts a group username and labels a missing version', () async {
    final harness = await _TelegramHarness.create(chatId: '@release_team');
    harness.client.responses.add(
      const TelegramHttpResponse(statusCode: 200, body: {'ok': true}),
    );

    await harness.service.sendReleaseNote(
      appDisplayName: 'Demo App',
      version: null,
      releaseNotes: 'Sửa lỗi nhỏ.',
    );

    final request = harness.client.requests.single;
    expect(request.body['chat_id'], '@release_team');
    expect(request.body['text'], contains('Phiên bản: không xác định'));
  });

  test(
    'rejects messages over Telegram limit before making a request',
    () async {
      final harness = await _TelegramHarness.create(chatId: '-1001');

      expect(
        () => harness.service.sendReleaseNote(
          appDisplayName: 'Demo',
          version: '1.0.0+1',
          releaseNotes: List.filled(telegramMessageCharacterLimit, 'x').join(),
        ),
        throwsA(
          isA<TelegramReleaseNotificationException>().having(
            (error) => error.message,
            'message',
            contains('4096-character'),
          ),
        ),
      );
      expect(harness.client.requests, isEmpty);
    },
  );

  test('surfaces Telegram API description without leaking token', () async {
    final harness = await _TelegramHarness.create(chatId: '-1001');
    harness.client.responses.add(
      const TelegramHttpResponse(
        statusCode: 401,
        body: {'ok': false, 'description': 'Unauthorized secret-token'},
      ),
    );

    await expectLater(
      harness.service.sendTestMessage(),
      throwsA(
        isA<TelegramReleaseNotificationException>()
            .having((error) => error.message, 'message', contains('[redacted]'))
            .having(
              (error) => error.message,
              'message',
              isNot(contains('secret-token')),
            ),
      ),
    );
  });

  test('rejects an invalid successful response', () async {
    final harness = await _TelegramHarness.create(chatId: '-1001');
    harness.client.responses.add(
      const TelegramHttpResponse(statusCode: 200, body: 'not-json'),
    );

    await expectLater(
      harness.service.sendTestMessage(),
      throwsA(
        isA<TelegramReleaseNotificationException>().having(
          (error) => error.message,
          'message',
          contains('invalid response'),
        ),
      ),
    );
  });

  test('propagates sanitized timeout errors from the HTTP client', () async {
    final harness = await _TelegramHarness.create(chatId: '-1001');
    harness.client.error = const TelegramReleaseNotificationException(
      'Telegram request timed out.',
    );

    await expectLater(
      harness.service.sendTestMessage(),
      throwsA(
        isA<TelegramReleaseNotificationException>().having(
          (error) => error.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });

  test('uploads an APK with sendDocument multipart fields', () async {
    final harness = await _TelegramHarness.create(chatId: '-1001234567890');
    final temp = await Directory.systemTemp.createTemp('arc_telegram_apk_');
    addTearDown(() => temp.delete(recursive: true));
    final apk = await File(
      '${temp.path}${Platform.pathSeparator}FizaHUB_v2.0.1_21_07_2026.apk',
    ).writeAsBytes([1, 2, 3]);
    harness.client.responses.add(
      const TelegramHttpResponse(statusCode: 200, body: {'ok': true}),
    );

    await harness.service.sendReleaseApk(
      apkFile: apk,
      appDisplayName: 'FizaHUB',
      version: '2.0.1+45',
      buildDate: DateTime(2026, 7, 21),
    );

    final upload = harness.client.uploads.single;
    expect(upload.url.path, '/botsecret-token/sendDocument');
    expect(upload.fields['chat_id'], '-1001234567890');
    expect(upload.fields['caption'], contains('FizaHUB'));
    expect(upload.fields['caption'], contains('2.0.1+45'));
    expect(upload.fileField, 'document');
    expect(upload.fileName, 'FizaHUB_v2.0.1_21_07_2026.apk');
    expect(upload.contentType, 'application/vnd.android.package-archive');
  });

  test(
    'uploads a Windows installer with sendDocument multipart fields',
    () async {
      final harness = await _TelegramHarness.create(chatId: '-1001234567890');
      final temp = await Directory.systemTemp.createTemp(
        'arc_telegram_installer_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final installer = await File(
        p.join(temp.path, 'AppReleaseCenter_Setup_v0.1.0.exe'),
      ).writeAsBytes([1, 2, 3]);
      harness.client.responses.add(
        const TelegramHttpResponse(statusCode: 200, body: {'ok': true}),
      );

      await harness.service.sendReleaseInstaller(
        installerFile: installer,
        appDisplayName: 'App Release Center',
        version: '0.1.0+1',
        buildDate: DateTime(2026, 8, 3),
      );

      final upload = harness.client.uploads.single;
      expect(upload.url.path, '/botsecret-token/sendDocument');
      expect(upload.fields['chat_id'], '-1001234567890');
      expect(upload.fields['caption'], contains('App Release Center'));
      expect(upload.fields['caption'], contains('0.1.0+1'));
      expect(upload.fileField, 'document');
      expect(upload.fileName, 'AppReleaseCenter_Setup_v0.1.0.exe');
      expect(upload.contentType, windowsInstallerContentType);
    },
  );

  test('rejects APKs over the Bot API document size limit', () async {
    final harness = await _TelegramHarness.create(chatId: '-1001');
    final temp = await Directory.systemTemp.createTemp('arc_telegram_apk_');
    addTearDown(() => temp.delete(recursive: true));
    final apk = File('${temp.path}${Platform.pathSeparator}oversize.apk');
    final handle = await apk.open(mode: FileMode.write);
    await handle.truncate(telegramDocumentMaxBytes + 1);
    await handle.close();

    await expectLater(
      harness.service.sendReleaseApk(
        apkFile: apk,
        appDisplayName: 'FizaHUB',
        version: '2.0.1+45',
        buildDate: DateTime(2026, 7, 21),
      ),
      throwsA(
        isA<TelegramReleaseNotificationException>().having(
          (error) => error.message,
          'message',
          contains('50 MB'),
        ),
      ),
    );
    expect(harness.client.uploads, isEmpty);
  });

  test('rejects installers over the Bot API document size limit', () async {
    final harness = await _TelegramHarness.create(chatId: '-1001');
    final temp = await Directory.systemTemp.createTemp(
      'arc_telegram_installer_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final installer = File(p.join(temp.path, 'installer.exe'));
    final handle = await installer.open(mode: FileMode.write);
    await handle.truncate(telegramDocumentMaxBytes + 1);
    await handle.close();

    await expectLater(
      harness.service.sendReleaseInstaller(
        installerFile: installer,
        appDisplayName: 'App Release Center',
        version: '0.1.0+1',
        buildDate: DateTime(2026, 8, 3),
      ),
      throwsA(
        isA<TelegramReleaseNotificationException>().having(
          (error) => error.message,
          'message',
          contains('50 MB'),
        ),
      ),
    );
    expect(harness.client.uploads, isEmpty);
  });

  test('sends a Drive APK link with optional release notes', () async {
    final harness = await _TelegramHarness.create(chatId: '-1001234567890');
    harness.client.responses.add(
      const TelegramHttpResponse(statusCode: 200, body: {'ok': true}),
    );

    await harness.service.sendReleaseApkLink(
      appDisplayName: 'FizaHUB',
      version: '2.0.1+45',
      fileName: 'FizaHUB_v2.0.1_21_07_2026.apk',
      fileSizeBytes: 3 * 1024 * 1024,
      downloadUrl: 'https://drive.google.com/file/d/drive-file-id/view',
      releaseNotes: 'Fixed checkout crash.',
      oversized: false,
    );

    final request = harness.client.requests.single;
    expect(request.url.path, '/botsecret-token/sendMessage');
    expect(request.body['chat_id'], '-1001234567890');
    final message = request.body['text'] as String;
    expect(message, contains('Release APK uploaded to Google Drive.'));
    expect(message, contains('FizaHUB'));
    expect(message, contains('2.0.1+45'));
    expect(message, contains('FizaHUB_v2.0.1_21_07_2026.apk'));
    expect(
      message,
      contains('https://drive.google.com/file/d/drive-file-id/view'),
    );
    expect(message, contains('Release notes:'));
    expect(message, contains('Fixed checkout crash.'));
  });

  test('sends a Drive installer link', () async {
    final harness = await _TelegramHarness.create(chatId: '-1001234567890');
    harness.client.responses.add(
      const TelegramHttpResponse(statusCode: 200, body: {'ok': true}),
    );

    await harness.service.sendReleaseInstallerLink(
      appDisplayName: 'App Release Center',
      version: '0.1.0+1',
      fileName: 'AppReleaseCenter_Setup_v0.1.0.exe',
      fileSizeBytes: 151 * 1024 * 1024,
      downloadUrl: 'https://drive.google.com/file/d/drive-file-id/view',
      oversized: true,
    );

    final request = harness.client.requests.single;
    expect(request.url.path, '/botsecret-token/sendMessage');
    expect(request.body['chat_id'], '-1001234567890');
    final message = request.body['text'] as String;
    expect(message, contains('Installer is over Telegram 50 MB limit'));
    expect(message, contains('App Release Center'));
    expect(message, contains('0.1.0+1'));
    expect(message, contains('AppReleaseCenter_Setup_v0.1.0.exe'));
    expect(message, contains('151.0 MB'));
    expect(
      message,
      contains('https://drive.google.com/file/d/drive-file-id/view'),
    );
  });
}

class _TelegramHarness {
  const _TelegramHarness({required this.client, required this.service});

  final _FakeTelegramHttpClient client;
  final TelegramReleaseNotificationService service;

  static Future<_TelegramHarness> create({required String chatId}) async {
    SharedPreferences.setMockInitialValues({});
    final store = await ProjectStoreService().init();
    await store.saveTelegramReleaseSettings(
      TelegramReleaseSettings(chatId: chatId),
    );
    final credentials = TelegramCredentialStoreService(
      secureStore: _MemorySecureKeyValueStore(),
    );
    await credentials.saveBotToken('secret-token');
    final client = _FakeTelegramHttpClient();
    return _TelegramHarness(
      client: client,
      service: TelegramReleaseNotificationService(
        store: store,
        credentialStore: credentials,
        httpClient: client,
      ),
    );
  }
}

class _TelegramRequest {
  const _TelegramRequest({required this.url, required this.body});

  final Uri url;
  final Map<String, Object?> body;
}

class _TelegramUploadRequest {
  const _TelegramUploadRequest({
    required this.url,
    required this.fields,
    required this.fileField,
    required this.file,
    required this.fileName,
    required this.contentType,
  });

  final Uri url;
  final Map<String, String> fields;
  final String fileField;
  final File file;
  final String fileName;
  final String contentType;
}

class _FakeTelegramHttpClient implements TelegramHttpClient {
  final requests = <_TelegramRequest>[];
  final uploads = <_TelegramUploadRequest>[];
  final responses = <TelegramHttpResponse>[];
  Object? error;

  @override
  Future<TelegramHttpResponse> postJson(
    Uri url,
    Map<String, Object?> body,
  ) async {
    requests.add(_TelegramRequest(url: url, body: body));
    final currentError = error;
    if (currentError != null) throw currentError;
    return responses.removeAt(0);
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
    uploads.add(
      _TelegramUploadRequest(
        url: url,
        fields: fields,
        fileField: fileField,
        file: file,
        fileName: fileName,
        contentType: contentType,
      ),
    );
    final currentError = error;
    if (currentError != null) throw currentError;
    return responses.removeAt(0);
  }
}

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}
