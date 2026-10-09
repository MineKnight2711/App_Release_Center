import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:get/get.dart';

/// Keeps the App Management Center session token in the OS secure store.
class AuthTokenStoreService extends GetxService {
  AuthTokenStoreService({SecureKeyValueStore? secureStore})
    : _secureStore = secureStore ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _secureStore;
  String? _cachedToken;
  var _loaded = false;

  Future<String?> readToken() async {
    if (!_loaded) {
      _cachedToken = await _secureStore.read(key: _sessionTokenKey);
      _loaded = true;
    }
    return _cachedToken;
  }

  Future<void> saveToken(String? token) async {
    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _secureStore.delete(key: _sessionTokenKey);
      _cachedToken = null;
    } else {
      await _secureStore.write(key: _sessionTokenKey, value: trimmed);
      _cachedToken = trimmed;
    }
    _loaded = true;
  }
}

const _sessionTokenKey = 'auth.session_token';
