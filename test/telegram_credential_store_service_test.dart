import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_release_center/app/services/telegram_credential_store_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saves, reads, and deletes Telegram bot token securely', () async {
    final secureStore = _MemorySecureKeyValueStore();
    final credentials = TelegramCredentialStoreService(
      secureStore: secureStore,
    );

    await credentials.saveBotToken(' secret-token ');
    expect(await credentials.readBotToken(), 'secret-token');

    await credentials.saveBotToken('');
    expect(await credentials.readBotToken(), isNull);
    expect(secureStore.values, isEmpty);
  });
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
