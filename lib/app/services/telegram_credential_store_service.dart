import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
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
}

const _botTokenKey = 'telegram_release.bot_token';
