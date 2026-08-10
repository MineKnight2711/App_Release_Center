import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_release_center/app/models/google_drive_release_settings.dart';
import 'package:app_release_center/app/services/google_drive_credential_store_service.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:get/get.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

abstract class GoogleDriveOAuthFlow {
  Future<String> authorize({
    required String oauthClientId,
    String? oauthClientSecret,
  });
}

abstract class GoogleDriveUrlLauncher {
  Future<void> launch(Uri url);
}

class UrlLauncherGoogleDriveUrlLauncher implements GoogleDriveUrlLauncher {
  @override
  Future<void> launch(Uri url) async {
    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw const GoogleDriveReleaseUploadException(
        'Could not open the Google OAuth page.',
      );
    }
  }
}

class BrowserGoogleDriveOAuthFlow implements GoogleDriveOAuthFlow {
  BrowserGoogleDriveOAuthFlow({
    GoogleDriveUrlLauncher? launcher,
    Duration timeout = _oauthTimeout,
    Duration tokenExchangeTimeout = _driveRequestTimeout,
    Uri? authorizationEndpoint,
    Uri? tokenEndpoint,
  }) : _launcher = launcher ?? UrlLauncherGoogleDriveUrlLauncher(),
       _timeout = timeout,
       _tokenExchangeTimeout = tokenExchangeTimeout,
       _authorizationEndpoint =
           authorizationEndpoint ?? _googleAuthorizationEndpoint,
       _tokenEndpoint = tokenEndpoint ?? _googleTokenEndpoint;

  final GoogleDriveUrlLauncher _launcher;
  final Duration _timeout;
  final Duration _tokenExchangeTimeout;
  final Uri _authorizationEndpoint;
  final Uri _tokenEndpoint;

  @override
  Future<String> authorize({
    required String oauthClientId,
    String? oauthClientSecret,
  }) async {
    final clientId = oauthClientId.trim();
    final clientSecret = oauthClientSecret?.trim();
    if (clientId.isEmpty) {
      throw const GoogleDriveReleaseUploadException(
        'Google OAuth Client ID is required.',
      );
    }

    HttpServer? server;
    oauth2.Client? oauthClient;
    oauth2.AuthorizationCodeGrant? grant;
    HttpResponse? browserResponse;
    var browserResponseWritten = false;
    var waitingForTokenExchange = false;

    Future<void> writeBrowserResponse({
      required bool success,
      String? details,
    }) async {
      if (browserResponse == null || browserResponseWritten) return;
      browserResponseWritten = true;
      try {
        await _writeOAuthBrowserResponse(
          browserResponse,
          success: success,
          details: details,
        );
      } catch (_) {
        // The browser tab may already be closed. The desktop app status still
        // carries the actionable result.
      }
    }

    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirectUri = Uri.parse(
        'http://127.0.0.1:${server.port}/oauth2callback',
      );
      grant = oauth2.AuthorizationCodeGrant(
        clientId,
        _authorizationEndpoint,
        _tokenEndpoint,
        basicAuth: false,
        secret: clientSecret == null || clientSecret.isEmpty
            ? null
            : clientSecret,
        httpClient: _TimeoutHttpClient(http.Client(), _tokenExchangeTimeout),
      );
      final state = _randomState();
      final authorizationUrl = grant.getAuthorizationUrl(
        redirectUri,
        scopes: const [googleDriveReleaseScope],
        state: state,
      );
      final offlineAuthorizationUrl = authorizationUrl.replace(
        queryParameters: {
          ...authorizationUrl.queryParameters,
          'access_type': 'offline',
          'prompt': 'consent',
        },
      );

      await _launcher.launch(offlineAuthorizationUrl);
      final request = await server.first.timeout(_timeout);
      browserResponse = request.response;

      waitingForTokenExchange = true;
      oauthClient = await grant
          .handleAuthorizationResponse(request.uri.queryParameters)
          .timeout(_tokenExchangeTimeout);
      await writeBrowserResponse(success: true);
      return oauthClient.credentials.toJson();
    } on TimeoutException {
      final message = waitingForTokenExchange
          ? 'Google Drive token exchange timed out after authorization. '
                'Please try Connect Drive again.'
          : 'Google Drive authorization timed out.';
      await writeBrowserResponse(success: false, details: message);
      throw GoogleDriveReleaseUploadException(message);
    } on oauth2.AuthorizationException catch (error) {
      final message = _googleDriveAuthorizationMessage(error);
      await writeBrowserResponse(success: false, details: message);
      throw GoogleDriveReleaseUploadException(message);
    } on FormatException catch (error) {
      final message =
          'Google Drive authorization returned an invalid response: '
          '${error.message}';
      await writeBrowserResponse(success: false, details: message);
      throw GoogleDriveReleaseUploadException(message);
    } on SocketException catch (error) {
      final message =
          'Network error during Google Drive authorization: ${error.message}';
      await writeBrowserResponse(success: false, details: message);
      throw GoogleDriveReleaseUploadException(message);
    } on http.ClientException catch (error) {
      final message =
          'Google Drive authorization HTTP request failed: ${error.message}';
      await writeBrowserResponse(success: false, details: message);
      throw GoogleDriveReleaseUploadException(message);
    } finally {
      oauthClient?.close();
      if (oauthClient == null) {
        grant?.close();
      }
      await server?.close(force: true);
    }
  }

  Future<void> _writeOAuthBrowserResponse(
    HttpResponse response, {
    required bool success,
    String? details,
  }) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.html;
    final escapedDetails = const HtmlEscape().convert(details ?? '');
    response.write(
      success
          ? '<html><body><h3>Google Drive connected.</h3>'
                '<p>You can close this tab and return to App Release Center.</p>'
                '</body></html>'
          : '<html><body><h3>Google Drive authorization failed.</h3>'
                '${escapedDetails.isEmpty ? '' : '<p>$escapedDetails</p>'}'
                '<p>You can close this tab and return to App Release Center.</p>'
                '</body></html>',
    );
    await response.close();
  }

  String _randomState() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

String _googleDriveAuthorizationMessage(oauth2.AuthorizationException error) {
  final details = error.description ?? error.error;
  if (details.toLowerCase().contains('client_secret is missing')) {
    return 'Google Drive authorization failed: client_secret is missing. '
        'Enter the OAuth Client Secret for this Google client, or create a new '
        'OAuth Client ID with application type Desktop app.';
  }
  return 'Google Drive authorization failed: $details';
}

class _TimeoutHttpClient extends http.BaseClient {
  _TimeoutHttpClient(this._inner, this._timeout);

  final http.Client _inner;
  final Duration _timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request).timeout(_timeout);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

abstract class GoogleDriveApiClient {
  Future<GoogleDriveRemoteFile> createFolder({required String folderName});

  Future<GoogleDriveRemoteFile> uploadFile({
    required File file,
    required String fileName,
    required String folderId,
    required String contentType,
  });

  Future<void> makeAnyoneReadable(String fileId);

  String credentialsJson();

  void close();
}

abstract class GoogleDriveApiClientFactory {
  GoogleDriveApiClient create({
    required String oauthClientId,
    String? oauthClientSecret,
    required String credentialsJson,
  });
}

class GoogleDriveApiClientFactoryImpl implements GoogleDriveApiClientFactory {
  @override
  GoogleDriveApiClient create({
    required String oauthClientId,
    String? oauthClientSecret,
    required String credentialsJson,
  }) {
    final clientSecret = oauthClientSecret?.trim();
    final credentials = oauth2.Credentials.fromJson(credentialsJson);
    final oauthClient = oauth2.Client(
      credentials,
      identifier: oauthClientId,
      secret: clientSecret == null || clientSecret.isEmpty
          ? null
          : clientSecret,
      basicAuth: false,
      httpClient: http.Client(),
    );
    return GoogleDriveApiClientImpl(oauthClient);
  }
}

class GoogleDriveApiClientImpl implements GoogleDriveApiClient {
  GoogleDriveApiClientImpl(oauth2.Client oauthClient)
    : _oauthClient = oauthClient,
      _driveApi = drive.DriveApi(oauthClient);

  final oauth2.Client _oauthClient;
  final drive.DriveApi _driveApi;

  @override
  Future<GoogleDriveRemoteFile> createFolder({
    required String folderName,
  }) async {
    final folder = drive.File()
      ..name = folderName
      ..mimeType = _driveFolderMimeType;
    final created = await _driveApi.files
        .create(folder, $fields: _driveFileFields)
        .timeout(_driveRequestTimeout);
    return GoogleDriveRemoteFile.fromDriveFile(created);
  }

  @override
  Future<GoogleDriveRemoteFile> uploadFile({
    required File file,
    required String fileName,
    required String folderId,
    required String contentType,
  }) async {
    final metadata = drive.File()
      ..name = fileName
      ..parents = [folderId];
    final media = drive.Media(
      file.openRead(),
      await file.length(),
      contentType: contentType,
    );
    final uploaded = await _driveApi.files
        .create(
          metadata,
          uploadMedia: media,
          uploadOptions: drive.UploadOptions.resumable,
          supportsAllDrives: true,
          $fields: _driveFileFields,
        )
        .timeout(_driveUploadTimeout);
    return GoogleDriveRemoteFile.fromDriveFile(uploaded);
  }

  @override
  Future<void> makeAnyoneReadable(String fileId) async {
    final permission = drive.Permission()
      ..type = 'anyone'
      ..role = 'reader';
    await _driveApi.permissions
        .create(
          permission,
          fileId,
          sendNotificationEmail: false,
          supportsAllDrives: true,
          $fields: 'id',
        )
        .timeout(_driveRequestTimeout);
  }

  @override
  String credentialsJson() => _oauthClient.credentials.toJson();

  @override
  void close() {
    _oauthClient.close();
  }
}

class GoogleDriveReleaseUploadService extends GetxService {
  GoogleDriveReleaseUploadService({
    required ProjectStoreService store,
    required GoogleDriveCredentialStoreService credentialStore,
    GoogleDriveOAuthFlow? oauthFlow,
    GoogleDriveApiClientFactory? apiClientFactory,
  }) : _store = store,
       _credentialStore = credentialStore,
       _oauthFlow = oauthFlow ?? BrowserGoogleDriveOAuthFlow(),
       _apiClientFactory =
           apiClientFactory ?? GoogleDriveApiClientFactoryImpl();

  final ProjectStoreService _store;
  final GoogleDriveCredentialStoreService _credentialStore;
  final GoogleDriveOAuthFlow _oauthFlow;
  final GoogleDriveApiClientFactory _apiClientFactory;

  GoogleDriveReleaseSettings get settings => _store.googleDriveReleaseSettings;

  Future<bool> hasCredentials() {
    return _credentialStore.hasCredentials();
  }

  Future<String?> readOAuthClientSecret() {
    return _credentialStore.readOAuthClientSecret();
  }

  Future<bool> hasOAuthClientSecret() {
    return _credentialStore.hasOAuthClientSecret();
  }

  Future<void> saveOAuthClientSecret(String? oauthClientSecret) {
    return _credentialStore.saveOAuthClientSecret(oauthClientSecret);
  }

  Future<void> saveSettings(GoogleDriveReleaseSettings settings) {
    return _store.saveGoogleDriveReleaseSettings(settings);
  }

  Future<void> connect({
    required String oauthClientId,
    String? oauthClientSecret,
  }) async {
    final clientId = oauthClientId.trim();
    final clientSecret = oauthClientSecret?.trim();
    if (clientId.isEmpty) {
      throw const GoogleDriveReleaseUploadException(
        'Google OAuth Client ID is required.',
      );
    }

    final credentialsJson = await _oauthFlow.authorize(
      oauthClientId: clientId,
      oauthClientSecret: clientSecret,
    );
    await _credentialStore.saveCredentialsJson(credentialsJson);
    await _credentialStore.saveOAuthClientSecret(clientSecret);
    final currentSettings = settings;
    final keepFolderId = currentSettings.oauthClientId.trim() == clientId
        ? currentSettings.folderId
        : '';
    await saveSettings(
      currentSettings.copyWith(oauthClientId: clientId, folderId: keepFolderId),
    );
  }

  Future<void> disconnect() async {
    await _credentialStore.deleteCredentials();
    await saveSettings(
      settings.copyWith(
        useDriveFallbackEnabled: false,
        sendApkLinkToTelegramEnabled: false,
      ),
    );
  }

  Future<GoogleDriveRemoteFile> testConnection() async {
    return _withApiClient((client) => _ensureFolder(client));
  }

  Future<GoogleDriveReleaseUploadResult> uploadReleaseApk({
    required File apkFile,
    required String appDisplayName,
    required String version,
    required DateTime buildDate,
  }) async {
    return uploadReleaseArtifact(
      file: apkFile,
      contentType: 'application/vnd.android.package-archive',
      appDisplayName: appDisplayName,
      version: version,
      buildDate: buildDate,
      missingFileMessage: 'Release APK file does not exist.',
    );
  }

  Future<GoogleDriveReleaseUploadResult> uploadReleaseArtifact({
    required File file,
    required String contentType,
    required String appDisplayName,
    required String version,
    required DateTime buildDate,
    String? fileName,
    String missingFileMessage = 'Release file does not exist.',
  }) async {
    if (!file.existsSync()) {
      throw GoogleDriveReleaseUploadException(missingFileMessage);
    }

    final trimmedContentType = contentType.trim();
    if (trimmedContentType.isEmpty) {
      throw const GoogleDriveReleaseUploadException(
        'Google Drive upload content type is required.',
      );
    }

    return _withApiClient((client) async {
      final folder = await _ensureFolder(client);
      final fileSize = await file.length();
      final uploadName = (fileName?.trim().isNotEmpty ?? false)
          ? fileName!.trim()
          : p.basename(file.path);
      final uploaded = await client.uploadFile(
        file: file,
        fileName: uploadName,
        folderId: folder.id,
        contentType: trimmedContentType,
      );
      await client.makeAnyoneReadable(uploaded.id);

      return GoogleDriveReleaseUploadResult(
        fileId: uploaded.id,
        fileName: uploadName,
        downloadUrl: uploaded.link,
        fileSizeBytes: fileSize,
        appDisplayName: appDisplayName.trim(),
        version: version.trim(),
        buildDate: buildDate,
      );
    });
  }

  Future<T> _withApiClient<T>(
    Future<T> Function(GoogleDriveApiClient client) callback,
  ) async {
    final currentSettings = settings;
    final clientId = currentSettings.oauthClientId.trim();
    if (clientId.isEmpty) {
      throw const GoogleDriveReleaseUploadException(
        'Google OAuth Client ID is required.',
      );
    }

    final storedCredentials = (await _credentialStore.readCredentialsJson())
        ?.trim();
    if (storedCredentials == null || storedCredentials.isEmpty) {
      throw const GoogleDriveReleaseUploadException(
        'Google Drive is not connected.',
      );
    }

    GoogleDriveApiClient? client;
    try {
      final clientSecret = await _credentialStore.readOAuthClientSecret();
      client = _apiClientFactory.create(
        oauthClientId: clientId,
        oauthClientSecret: clientSecret,
        credentialsJson: storedCredentials,
      );
      return await callback(client);
    } on oauth2.AuthorizationException catch (error) {
      await _credentialStore.deleteCredentials();
      throw GoogleDriveReleaseUploadException(
        _googleDriveAuthorizationMessage(error).replaceFirst(
          'Google Drive authorization failed:',
          'Google Drive authorization expired:',
        ),
      );
    } on drive.ApiRequestError catch (error) {
      final status = error is drive.DetailedApiRequestError
          ? error.status
          : null;
      throw GoogleDriveReleaseUploadException(
        _sanitizeDriveMessage(
          'Google Drive API failed'
          '${status == null ? '' : ' ($status)'}'
          '${error.message == null ? '' : ': ${error.message}'}',
          storedCredentials,
        ),
      );
    } on TimeoutException {
      throw const GoogleDriveReleaseUploadException(
        'Google Drive request timed out.',
      );
    } on FileSystemException catch (error) {
      throw GoogleDriveReleaseUploadException(
        'Failed to read file for Google Drive upload: ${error.message}',
      );
    } finally {
      if (client != null) {
        await _credentialStore.saveCredentialsJson(client.credentialsJson());
        client.close();
      }
    }
  }

  Future<GoogleDriveRemoteFile> _ensureFolder(
    GoogleDriveApiClient client,
  ) async {
    final currentSettings = settings;
    final folderId = currentSettings.folderId.trim();
    if (folderId.isNotEmpty) {
      return GoogleDriveRemoteFile(
        id: folderId,
        name: googleDriveReleaseFolderName,
        webViewLink: _driveFolderUrl(folderId),
      );
    }

    final folder = await client.createFolder(
      folderName: googleDriveReleaseFolderName,
    );
    await saveSettings(settings.copyWith(folderId: folder.id));
    return folder;
  }

  String _sanitizeDriveMessage(String message, String credentialsJson) {
    try {
      final credentials = oauth2.Credentials.fromJson(credentialsJson);
      var sanitized = message.replaceAll(credentials.accessToken, '[redacted]');
      final refreshToken = credentials.refreshToken;
      if (refreshToken != null && refreshToken.isNotEmpty) {
        sanitized = sanitized.replaceAll(refreshToken, '[redacted]');
      }
      return sanitized;
    } catch (_) {
      return _sanitizeDriveMessageFromRawJson(message, credentialsJson);
    }
  }

  String _sanitizeDriveMessageFromRawJson(
    String message,
    String credentialsJson,
  ) {
    try {
      final parsed = jsonDecode(credentialsJson);
      if (parsed is! Map) return message;

      var sanitized = message;
      for (final key in const ['accessToken', 'refreshToken']) {
        final value = parsed[key];
        if (value is String && value.isNotEmpty) {
          sanitized = sanitized.replaceAll(value, '[redacted]');
        }
      }
      return sanitized;
    } catch (_) {
      return message;
    }
  }
}

class GoogleDriveRemoteFile {
  const GoogleDriveRemoteFile({
    required this.id,
    required this.name,
    this.webViewLink,
    this.webContentLink,
  });

  final String id;
  final String name;
  final String? webViewLink;
  final String? webContentLink;

  String get link {
    final viewLink = webViewLink?.trim();
    if (viewLink != null && viewLink.isNotEmpty) return viewLink;

    final contentLink = webContentLink?.trim();
    if (contentLink != null && contentLink.isNotEmpty) return contentLink;

    return _driveFileUrl(id);
  }

  factory GoogleDriveRemoteFile.fromDriveFile(drive.File file) {
    final id = file.id?.trim();
    if (id == null || id.isEmpty) {
      throw const GoogleDriveReleaseUploadException(
        'Google Drive response did not include file ID.',
      );
    }
    return GoogleDriveRemoteFile(
      id: id,
      name: file.name ?? '',
      webViewLink: file.webViewLink,
      webContentLink: file.webContentLink,
    );
  }
}

class GoogleDriveReleaseUploadResult {
  const GoogleDriveReleaseUploadResult({
    required this.fileId,
    required this.fileName,
    required this.downloadUrl,
    required this.fileSizeBytes,
    required this.appDisplayName,
    required this.version,
    required this.buildDate,
  });

  final String fileId;
  final String fileName;
  final String downloadUrl;
  final int fileSizeBytes;
  final String appDisplayName;
  final String version;
  final DateTime buildDate;
}

class GoogleDriveReleaseUploadException implements Exception {
  const GoogleDriveReleaseUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

String formatGoogleDriveReleaseMegabytes(int bytes) {
  return (bytes / (1024 * 1024)).toStringAsFixed(1);
}

String _driveFileUrl(String fileId) {
  return 'https://drive.google.com/file/d/$fileId/view?usp=sharing';
}

String _driveFolderUrl(String folderId) {
  return 'https://drive.google.com/drive/folders/$folderId';
}

const googleDriveReleaseScope = 'https://www.googleapis.com/auth/drive.file';
const googleDriveReleaseFolderName = 'App Release Center APKs';
const _driveFolderMimeType = 'application/vnd.google-apps.folder';
const _driveFileFields = 'id,name,webViewLink,webContentLink';
const _oauthTimeout = Duration(minutes: 3);
const _driveRequestTimeout = Duration(seconds: 45);
const _driveUploadTimeout = Duration(minutes: 15);
final _googleAuthorizationEndpoint = Uri.parse(
  'https://accounts.google.com/o/oauth2/v2/auth',
);
final _googleTokenEndpoint = Uri.parse('https://oauth2.googleapis.com/token');
