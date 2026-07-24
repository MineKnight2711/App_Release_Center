import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:get/get.dart';

class GoogleDriveCredentialStoreService extends GetxService {
  GoogleDriveCredentialStoreService({SecureKeyValueStore? secureStore})
    : _secureStore = secureStore ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _secureStore;

  Future<String?> readCredentialsJson() {
    return _secureStore.read(key: _credentialsJsonKey);
  }

  Future<bool> hasCredentials() async {
    final credentials = await readCredentialsJson();
    return credentials != null && credentials.trim().isNotEmpty;
  }

  Future<String?> readOAuthClientSecret() {
    return _secureStore.read(key: _oauthClientSecretKey);
  }

  Future<bool> hasOAuthClientSecret() async {
    final secret = await readOAuthClientSecret();
    return secret != null && secret.trim().isNotEmpty;
  }

  Future<void> saveCredentialsJson(String? credentialsJson) async {
    final trimmed = credentialsJson?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await deleteCredentials();
      return;
    }

    await _secureStore.write(key: _credentialsJsonKey, value: trimmed);
  }

  Future<void> saveOAuthClientSecret(String? oauthClientSecret) async {
    final trimmed = oauthClientSecret?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await deleteOAuthClientSecret();
      return;
    }

    await _secureStore.write(key: _oauthClientSecretKey, value: trimmed);
  }

  Future<void> deleteCredentials() {
    return _secureStore.delete(key: _credentialsJsonKey);
  }

  Future<void> deleteOAuthClientSecret() {
    return _secureStore.delete(key: _oauthClientSecretKey);
  }
}

const _credentialsJsonKey = 'google_drive_release.oauth_credentials_json';
const _oauthClientSecretKey = 'google_drive_release.oauth_client_secret';
