import 'package:app_release_center/app/models/telegram_release_settings.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to disabled when no Telegram settings were saved', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await ProjectStoreService().init();

    expect(store.telegramReleaseSettings.autoSendEnabled, isFalse);
    expect(store.telegramReleaseSettings.chatId, isEmpty);
  });

  test('persists Telegram auto send and chat ID', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await ProjectStoreService().init();

    await store.saveTelegramReleaseSettings(
      const TelegramReleaseSettings(
        autoSendEnabled: true,
        chatId: '-1001234567890',
      ),
    );

    expect(store.telegramReleaseSettings.autoSendEnabled, isTrue);
    expect(store.telegramReleaseSettings.chatId, '-1001234567890');
  });

  test('invalid legacy Telegram settings fall back to safe defaults', () async {
    SharedPreferences.setMockInitialValues({
      'telegram_release_settings': 'not-json',
    });
    final store = await ProjectStoreService().init();

    expect(store.telegramReleaseSettings.autoSendEnabled, isFalse);
    expect(store.telegramReleaseSettings.chatId, isEmpty);
  });
}
