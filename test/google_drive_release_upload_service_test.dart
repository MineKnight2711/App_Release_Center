import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_release_center/app/models/google_drive_release_settings.dart';
import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_release_center/app/services/google_drive_credential_store_service.dart';
import 'package:app_release_center/app/services/google_drive_release_upload_service.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('connect stores OAuth credentials and client ID', () async {
    final harness = await _DriveHarness.create();

    await harness.service.connect(
      oauthClientId: ' client-id ',
      oauthClientSecret: ' client-secret ',
    );

    expect(await harness.credentials.readCredentialsJson(), 'oauth-json');
    expect(await harness.credentials.readOAuthClientSecret(), 'client-secret');
    expect(harness.oauthFlow.clientSecret, 'client-secret');
    expect(harness.store.googleDriveReleaseSettings.oauthClientId, 'client-id');
  });

  test(
    'test connection creates and persists the Drive upload folder',
    () async {
      final harness = await _DriveHarness.create();
      await harness.saveConnectedSettings();

      final folder = await harness.service.testConnection();

      expect(folder.id, 'folder-id');
      expect(harness.client.folderCreateCount, 1);
      expect(harness.store.googleDriveReleaseSettings.folderId, 'folder-id');
    },
  );

  test('upload reuses folder, uploads APK, and shares it by link', () async {
    final harness = await _DriveHarness.create();
    await harness.saveConnectedSettings(folderId: 'folder-id');
    final temp = await Directory.systemTemp.createTemp('arc_drive_upload_');
    addTearDown(() => temp.delete(recursive: true));
    final apk = await File(
      p.join(temp.path, 'FizaHUB_v2.0.1_21_07_2026.apk'),
    ).writeAsBytes([1, 2, 3]);

    final result = await harness.service.uploadReleaseApk(
      apkFile: apk,
      appDisplayName: 'FizaHUB',
      version: '2.0.1+45',
      buildDate: DateTime(2026, 7, 21),
    );

    expect(harness.client.folderCreateCount, 0);
    expect(harness.client.uploads.single.folderId, 'folder-id');
    expect(
      harness.client.uploads.single.fileName,
      'FizaHUB_v2.0.1_21_07_2026.apk',
    );
    expect(harness.client.sharedFileIds, ['file-id']);
    expect(result.downloadUrl, 'https://drive.google.com/file/d/file-id/view');
    expect(result.fileSizeBytes, 3);
    expect(await harness.credentials.readCredentialsJson(), 'updated-json');
  });

  test('requires Drive credentials before upload', () async {
    final harness = await _DriveHarness.create();
    await harness.store.saveGoogleDriveReleaseSettings(
      const GoogleDriveReleaseSettings(oauthClientId: 'client-id'),
    );
    final temp = await Directory.systemTemp.createTemp('arc_drive_upload_');
    addTearDown(() => temp.delete(recursive: true));
    final apk = await File(p.join(temp.path, 'app.apk')).writeAsBytes([1]);

    await expectLater(
      harness.service.uploadReleaseApk(
        apkFile: apk,
        appDisplayName: 'Demo',
        version: '1.0.0+1',
        buildDate: DateTime(2026, 7, 21),
      ),
      throwsA(
        isA<GoogleDriveReleaseUploadException>().having(
          (error) => error.message,
          'message',
          contains('not connected'),
        ),
      ),
    );
  });

  test('sanitizes OAuth tokens from Drive API errors', () async {
    final harness = await _DriveHarness.create();
    await harness.saveConnectedSettings();
    harness.client.error = drive.ApiRequestError(
      'Unauthorized ya29.access-token refresh-token',
    );
    final temp = await Directory.systemTemp.createTemp('arc_drive_upload_');
    addTearDown(() => temp.delete(recursive: true));
    final apk = await File(p.join(temp.path, 'app.apk')).writeAsBytes([1]);

    await expectLater(
      harness.service.uploadReleaseApk(
        apkFile: apk,
        appDisplayName: 'Demo',
        version: '1.0.0+1',
        buildDate: DateTime(2026, 7, 21),
      ),
      throwsA(
        isA<GoogleDriveReleaseUploadException>()
            .having(
              (error) => error.message,
              'message',
              isNot(contains('ya29.access-token')),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('refresh-token')),
            )
            .having(
              (error) => error.message,
              'message',
              contains('[redacted]'),
            ),
      ),
    );
  });

  test('OAuth URL requests Drive scope, offline access, and PKCE', () async {
    final launcher = _CapturingDriveLauncher();
    final flow = BrowserGoogleDriveOAuthFlow(
      launcher: launcher,
      timeout: const Duration(milliseconds: 30),
    );

    await expectLater(
      flow.authorize(oauthClientId: 'client-id.apps.googleusercontent.com'),
      throwsA(isA<GoogleDriveReleaseUploadException>()),
    );

    final url = launcher.launchedUrl!;
    expect(url.host, 'accounts.google.com');
    expect(url.queryParameters['scope'], googleDriveReleaseScope);
    expect(url.queryParameters['access_type'], 'offline');
    expect(url.queryParameters['prompt'], 'consent');
    expect(url.queryParameters['code_challenge_method'], 'S256');
    expect(url.queryParameters['code_challenge'], isNotEmpty);
    expect(url.queryParameters['state'], isNotEmpty);
    expect(
      url.queryParameters['redirect_uri'],
      startsWith('http://127.0.0.1:'),
    );
  });

  test('OAuth access denied is surfaced clearly', () async {
    final launcher = _CallbackDriveLauncher((url) {
      final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
      return redirect.replace(
        queryParameters: {
          'error': 'access_denied',
          'error_description': 'Denied by user',
          'state': url.queryParameters['state']!,
        },
      );
    });
    final flow = BrowserGoogleDriveOAuthFlow(
      launcher: launcher,
      timeout: const Duration(seconds: 1),
    );

    await expectLater(
      flow.authorize(oauthClientId: 'client-id'),
      throwsA(
        isA<GoogleDriveReleaseUploadException>().having(
          (error) => error.message,
          'message',
          contains('Denied by user'),
        ),
      ),
    );
  });

  test('OAuth state mismatch is rejected', () async {
    final launcher = _CallbackDriveLauncher((url) {
      final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
      return redirect.replace(
        queryParameters: {'code': 'auth-code', 'state': 'wrong-state'},
      );
    });
    final flow = BrowserGoogleDriveOAuthFlow(
      launcher: launcher,
      timeout: const Duration(seconds: 1),
    );

    await expectLater(
      flow.authorize(oauthClientId: 'client-id'),
      throwsA(
        isA<GoogleDriveReleaseUploadException>().having(
          (error) => error.message,
          'message',
          contains('invalid response'),
        ),
      ),
    );
  });

  test('OAuth token exchange timeout is surfaced after callback', () async {
    final tokenServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => tokenServer.close(force: true));
    final tokenRequestReceived = Completer<void>();
    final tokenSubscription = tokenServer.listen((request) {
      if (!tokenRequestReceived.isCompleted) {
        tokenRequestReceived.complete();
      }
      // Keep the request open so the OAuth flow must rely on its timeout.
    });
    addTearDown(tokenSubscription.cancel);

    final launcher = _CallbackDriveLauncher((url) {
      final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
      return redirect.replace(
        queryParameters: {
          'code': 'auth-code',
          'state': url.queryParameters['state']!,
        },
      );
    });
    final flow = BrowserGoogleDriveOAuthFlow(
      launcher: launcher,
      timeout: const Duration(seconds: 1),
      tokenExchangeTimeout: const Duration(milliseconds: 30),
      tokenEndpoint: Uri.parse('http://127.0.0.1:${tokenServer.port}/token'),
    );

    await expectLater(
      flow.authorize(oauthClientId: 'client-id'),
      throwsA(
        isA<GoogleDriveReleaseUploadException>().having(
          (error) => error.message,
          'message',
          contains('token exchange timed out'),
        ),
      ),
    );
    await tokenRequestReceived.future.timeout(const Duration(seconds: 1));
  });

  test('OAuth token exchange sends client secret when provided', () async {
    final tokenServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => tokenServer.close(force: true));
    final tokenBody = Completer<String>();
    final tokenSubscription = tokenServer.listen((request) async {
      final bytes = await request.fold<List<int>>(<int>[], (buffer, chunk) {
        buffer.addAll(chunk);
        return buffer;
      });
      final body = utf8.decode(bytes);
      tokenBody.complete(body);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        '{"access_token":"access-token",'
        '"refresh_token":"refresh-token",'
        '"expires_in":3600,'
        '"token_type":"Bearer"}',
      );
      await request.response.close();
    });
    addTearDown(tokenSubscription.cancel);

    final launcher = _CallbackDriveLauncher((url) {
      final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
      return redirect.replace(
        queryParameters: {
          'code': 'auth-code',
          'state': url.queryParameters['state']!,
        },
      );
    });
    final flow = BrowserGoogleDriveOAuthFlow(
      launcher: launcher,
      timeout: const Duration(seconds: 1),
      tokenExchangeTimeout: const Duration(seconds: 1),
      tokenEndpoint: Uri.parse('http://127.0.0.1:${tokenServer.port}/token'),
    );

    final credentialsJson = await flow.authorize(
      oauthClientId: 'client-id',
      oauthClientSecret: 'client-secret',
    );

    final body = await tokenBody.future.timeout(const Duration(seconds: 1));
    expect(body, contains('client_id=client-id'));
    expect(body, contains('client_secret=client-secret'));
    expect(body, contains('code_verifier='));
    expect(credentialsJson, contains('access-token'));
  });

  test(
    'OAuth client secret missing error explains the required config',
    () async {
      final tokenServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => tokenServer.close(force: true));
      final tokenSubscription = tokenServer.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '{"error":"invalid_request",'
          '"error_description":"client_secret is missing."}',
        );
        await request.response.close();
      });
      addTearDown(tokenSubscription.cancel);

      final launcher = _CallbackDriveLauncher((url) {
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        return redirect.replace(
          queryParameters: {
            'code': 'auth-code',
            'state': url.queryParameters['state']!,
          },
        );
      });
      final flow = BrowserGoogleDriveOAuthFlow(
        launcher: launcher,
        timeout: const Duration(seconds: 1),
        tokenExchangeTimeout: const Duration(seconds: 1),
        tokenEndpoint: Uri.parse('http://127.0.0.1:${tokenServer.port}/token'),
      );

      await expectLater(
        flow.authorize(oauthClientId: 'client-id'),
        throwsA(
          isA<GoogleDriveReleaseUploadException>()
              .having(
                (error) => error.message,
                'message',
                contains('client_secret is missing'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('OAuth Client Secret'),
              ),
        ),
      );
    },
  );
}

class _DriveHarness {
  const _DriveHarness({
    required this.store,
    required this.credentials,
    required this.client,
    required this.oauthFlow,
    required this.service,
  });

  final ProjectStoreService store;
  final GoogleDriveCredentialStoreService credentials;
  final _FakeGoogleDriveApiClient client;
  final _FakeGoogleDriveOAuthFlow oauthFlow;
  final GoogleDriveReleaseUploadService service;

  static Future<_DriveHarness> create() async {
    SharedPreferences.setMockInitialValues({});
    final store = await ProjectStoreService().init();
    final credentials = GoogleDriveCredentialStoreService(
      secureStore: _MemorySecureKeyValueStore(),
    );
    final client = _FakeGoogleDriveApiClient();
    final oauthFlow = _FakeGoogleDriveOAuthFlow();
    return _DriveHarness(
      store: store,
      credentials: credentials,
      client: client,
      oauthFlow: oauthFlow,
      service: GoogleDriveReleaseUploadService(
        store: store,
        credentialStore: credentials,
        oauthFlow: oauthFlow,
        apiClientFactory: _FakeGoogleDriveApiClientFactory(client),
      ),
    );
  }

  Future<void> saveConnectedSettings({String folderId = ''}) async {
    await credentials.saveCredentialsJson(_credentialsJson);
    await credentials.saveOAuthClientSecret('client-secret');
    await store.saveGoogleDriveReleaseSettings(
      GoogleDriveReleaseSettings(
        oauthClientId: 'client-id',
        folderId: folderId,
      ),
    );
  }
}

class _FakeGoogleDriveOAuthFlow implements GoogleDriveOAuthFlow {
  String? clientSecret;

  @override
  Future<String> authorize({
    required String oauthClientId,
    String? oauthClientSecret,
  }) async {
    clientSecret = oauthClientSecret;
    return 'oauth-json';
  }
}

class _FakeGoogleDriveApiClientFactory implements GoogleDriveApiClientFactory {
  const _FakeGoogleDriveApiClientFactory(this.client);

  final _FakeGoogleDriveApiClient client;

  @override
  GoogleDriveApiClient create({
    required String oauthClientId,
    String? oauthClientSecret,
    required String credentialsJson,
  }) {
    return client;
  }
}

class _FakeGoogleDriveUpload {
  const _FakeGoogleDriveUpload({
    required this.fileName,
    required this.folderId,
  });

  final String fileName;
  final String folderId;
}

class _FakeGoogleDriveApiClient implements GoogleDriveApiClient {
  final uploads = <_FakeGoogleDriveUpload>[];
  final sharedFileIds = <String>[];
  int folderCreateCount = 0;
  Object? error;

  @override
  Future<GoogleDriveRemoteFile> createFolder({
    required String folderName,
  }) async {
    final currentError = error;
    if (currentError != null) throw currentError;
    folderCreateCount++;
    return const GoogleDriveRemoteFile(
      id: 'folder-id',
      name: googleDriveReleaseFolderName,
    );
  }

  @override
  Future<GoogleDriveRemoteFile> uploadApk({
    required File file,
    required String fileName,
    required String folderId,
  }) async {
    final currentError = error;
    if (currentError != null) throw currentError;
    uploads.add(_FakeGoogleDriveUpload(fileName: fileName, folderId: folderId));
    return const GoogleDriveRemoteFile(
      id: 'file-id',
      name: 'FizaHUB_v2.0.1_21_07_2026.apk',
      webViewLink: 'https://drive.google.com/file/d/file-id/view',
    );
  }

  @override
  Future<void> makeAnyoneReadable(String fileId) async {
    final currentError = error;
    if (currentError != null) throw currentError;
    sharedFileIds.add(fileId);
  }

  @override
  String credentialsJson() => 'updated-json';

  @override
  void close() {}
}

class _CapturingDriveLauncher implements GoogleDriveUrlLauncher {
  Uri? launchedUrl;

  @override
  Future<void> launch(Uri url) async {
    launchedUrl = url;
  }
}

class _CallbackDriveLauncher implements GoogleDriveUrlLauncher {
  _CallbackDriveLauncher(this.callbackUrlBuilder);

  final Uri Function(Uri launchedUrl) callbackUrlBuilder;

  @override
  Future<void> launch(Uri url) async {
    unawaited(_sendCallback(callbackUrlBuilder(url)));
  }

  Future<void> _sendCallback(Uri url) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
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

const _credentialsJson = '''
{
  "accessToken": "ya29.access-token",
  "refreshToken": "refresh-token",
  "idToken": null,
  "tokenEndpoint": "https://oauth2.googleapis.com/token",
  "scopes": ["https://www.googleapis.com/auth/drive.file"],
  "expiration": "2099-01-01T00:00:00.000Z"
}
''';
