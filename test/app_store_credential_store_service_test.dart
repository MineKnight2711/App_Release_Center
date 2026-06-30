import 'package:app_release_center/app/models/app_store_credentials.dart';
import 'package:app_release_center/app/services/app_store_credential_store_service.dart';
import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'saves, reads metadata, and deletes secure App Store credentials',
    () async {
      final secureStore = _MemorySecureKeyValueStore();
      final service = AppStoreCredentialStoreService(secureStore: secureStore);

      await service.save(
        'project-1',
        const AppStoreCredentials(
          p8PrivateKey: '''
-----BEGIN PRIVATE KEY-----
abc
-----END PRIVATE KEY-----
''',
          keyId: 'KEY1234567',
          issuerId: 'issuer-id',
          teamId: 'TEAM123456',
          inHouse: true,
        ),
      );

      final credentials = await service.read('project-1');
      expect(credentials.p8PrivateKey, contains('BEGIN PRIVATE KEY'));
      expect(credentials.keyId, 'KEY1234567');
      expect(credentials.issuerId, 'issuer-id');
      expect(credentials.teamId, 'TEAM123456');
      expect(credentials.inHouse, isTrue);

      final metadata = await service.metadata('project-1');
      expect(metadata.hasP8PrivateKey, isTrue);
      expect(metadata.hasKeyId, isTrue);
      expect(metadata.hasIssuerId, isTrue);
      expect(metadata.hasTeamId, isTrue);
      expect(metadata.hasRequiredCredentials, isTrue);
      expect(metadata.inHouse, isTrue);

      await service.delete('project-1');
      final deleted = await service.read('project-1');
      expect(deleted.hasRequiredCredentials, isFalse);
      expect(deleted.inHouse, isFalse);
      expect(secureStore.values, isEmpty);
    },
  );
}

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async {
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}
