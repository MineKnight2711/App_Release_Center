import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:get/get.dart';

class TelegramCredentialStoreService extends GetxService {
  TelegramCredentialStoreService({SecureKeyValueStore? secureStore})
    : _secureStore = secureStore ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _secureStore;

  Future<String?> readBotToken() {
    return _secureStore.read(key: _botTokenKey);
  }

  Future<void> saveBotToken(String? token) async {
    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _secureStore.delete(key: _botTokenKey);
      return;
    }

    await _secureStore.write(key: _botTokenKey, value: trimmed);
  }

  /// api_id and api_hash from my.telegram.org, which a local Bot API server
  /// needs to log the bot in. Both or neither.
  Future<(String, String)?> readLocalServerCredentials() async {
    final id = (await _secureStore.read(key: _apiIdKey))?.trim() ?? '';
    final hash = (await _secureStore.read(key: _apiHashKey))?.trim() ?? '';
    return id.isEmpty || hash.isEmpty ? null : (id, hash);
  }

  Future<void> saveLocalServerCredentials(
    String? apiId,
    String? apiHash,
  ) async {
    final id = apiId?.trim() ?? '';
    final hash = apiHash?.trim() ?? '';
    if (id.isEmpty || hash.isEmpty) {
      await _secureStore.delete(key: _apiIdKey);
      await _secureStore.delete(key: _apiHashKey);
      return;
    }
    await _secureStore.write(key: _apiIdKey, value: id);
    await _secureStore.write(key: _apiHashKey, value: hash);
  }
}

const _botTokenKey = 'telegram_release.bot_token';
const _apiIdKey = 'telegram_local_server.api_id';
const _apiHashKey = 'telegram_local_server.api_hash';
