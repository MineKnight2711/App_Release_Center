import 'dart:io';

import 'package:app_management_center/app/models/telegram_release_settings.dart';
import 'package:app_management_center/app/modules/bundle_check/services/android_toolchain.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_check_service.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_check_store.dart';
import 'package:app_management_center/app/modules/bundle_check/telegram/telegram_intake_service.dart';
import 'package:app_management_center/app/modules/bundle_check/telegram/telegram_intake_store.dart';
import 'package:app_management_center/app/modules/bundle_check/views/telegram_bot_dialog.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/telegram_credential_store_service.dart';
import 'package:app_management_center/app/services/telegram_release_notification_service.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Memory implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async =>
      values[key] = value;

  @override
  Future<void> delete({required String key}) async => values.remove(key);
}

/// Fails the test on any network call: a widget test must never reach
/// api.telegram.org.
class _NoNetwork implements TelegramHttpClient {
  @override
  Future<TelegramHttpResponse> postJson(Uri url, Map<String, Object?> body) =>
      throw StateError('Unexpected Telegram call: ${url.pathSegments.last}');

  @override
  Future<TelegramHttpResponse> postMultipartFile(
    Uri url, {
    required Map<String, String> fields,
    required String fileField,
    required File file,
    required String fileName,
    required String contentType,
  }) => throw StateError('Unexpected Telegram upload');
}

class _NoProjects implements BundleProjectSource {
  @override
  Future<List<BundleProjectCandidate>> candidates() async => const [];

  @override
  Future<KeystoreRef?> savedKeystore(BundleProjectCandidate candidate) async =>
      null;
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('bundle_tg_dialog'));
  tearDown(() => temp.deleteSync(recursive: true));

  testWidgets('cài đặt bot: cảnh báo cloud, lưu câu báo và api_id/hash', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final memory = _Memory();
    final credentials = TelegramCredentialStoreService(secureStore: memory);
    final service = TelegramIntakeService(
      store: TelegramIntakeStore(root: Directory(p.join(temp.path, 'tg'))),
      checker: BundleCheckService(
        store: BundleCheckStore(root: Directory(p.join(temp.path, 'store'))),
        projects: _NoProjects(),
        tools: const JavaTools(java: 'java', keytool: 'keytool'),
      ),
      readToken: () async => '1:t',
      releaseSettings: () => const TelegramReleaseSettings(chatId: '-100'),
      saveReleaseSettings: (_) async {},
      readServerCredentials: credentials.readLocalServerCredentials,
      http: _NoNetwork(),
      slowHttp: _NoNetwork(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppCyberTheme.themeData(AppThemeChoice.cyber),
        home: Scaffold(
          body: TelegramBotDialog(service: service, credentials: credentials),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(find.text('Bot Telegram kiểm tra AAB'), findsOneWidget);
    expect(find.textContaining('chỉ tải được file ≤ 20 MB'), findsOneWidget);
    expect(find.text('Chuyển bot sang server local'), findsOneWidget);
    expect(
      find.text(TelegramIntakeSettings.defaultDownloadingMessage),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Câu bot nói trước khi tải file'),
      'Đang tải và kiểm tra aab',
    );
    await tester.enterText(find.widgetWithText(TextField, 'api_id'), '12345');
    await tester.enterText(
      find.widgetWithText(TextField, 'api_hash'),
      'abcdef',
    );

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('telegram-bot-save')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    final saved = await tester.runAsync(() => service.store.readSettings());
    expect(saved!.downloadingMessage, 'Đang tải và kiểm tra aab');
    // Saving without switching the bot on must not start polling.
    expect(saved.enabled, isFalse);
    expect(service.running, isFalse);
    expect(await credentials.readLocalServerCredentials(), ('12345', 'abcdef'));
    expect(tester.takeException(), isNull);
  });
}
