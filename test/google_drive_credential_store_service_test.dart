import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_release_center/app/services/google_drive_credential_store_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'saves, reads, detects, and deletes Drive credentials securely',
    () async {
      final secureStore = _MemorySecureKeyValueStore();
      final credentials = GoogleDriveCredentialStoreService(
        secureStore: secureStore,
      );

      expect(await credentials.hasCredentials(), isFalse);

      await credentials.saveCredentialsJson(' {"accessToken":"secret"} ');
      await credentials.saveOAuthClientSecret(' client-secret ');
      expect(await credentials.hasCredentials(), isTrue);
      expect(await credentials.hasOAuthClientSecret(), isTrue);
      expect(
        await credentials.readCredentialsJson(),
        '{"accessToken":"secret"}',
      );
      expect(await credentials.readOAuthClientSecret(), 'client-secret');

      await credentials.saveCredentialsJson('');
      await credentials.saveOAuthClientSecret('');
      expect(await credentials.readCredentialsJson(), isNull);
      expect(await credentials.readOAuthClientSecret(), isNull);
      expect(secureStore.values, isEmpty);
    },
  );
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
