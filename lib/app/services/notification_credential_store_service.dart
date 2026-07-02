import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:get/get.dart';

class NotificationCredentialStoreService extends GetxService {
  NotificationCredentialStoreService({SecureKeyValueStore? secureStore})
    : _secureStore = secureStore ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _secureStore;

  Future<String?> readApiToken() {
    return _secureStore.read(key: _apiTokenKey);
  }

  Future<void> saveApiToken(String? token) async {
    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _secureStore.delete(key: _apiTokenKey);
      return;
    }

    await _secureStore.write(key: _apiTokenKey, value: trimmed);
  }
}

const _apiTokenKey = 'release_notifications.api_token';
