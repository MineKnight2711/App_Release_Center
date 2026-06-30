import 'package:app_release_center/app/models/ch_play_credentials.dart';
import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saves, reads, and deletes secure CH Play credentials', () async {
    final secureStore = _MemorySecureKeyValueStore();
    final service = ChPlayCredentialStoreService(secureStore: secureStore);

    await service.save(
      'project-1',
      const ChPlayCredentials(
        googlePlayJson: '{"type":"service_account"}',
        jksPath: r'C:\keys\release.jks',
        keyAlias: 'release',
        storePassword: 'store-password',
        keyPassword: 'key-password',
      ),
    );

    final credentials = await service.read('project-1');
    expect(credentials.googlePlayJson, '{"type":"service_account"}');
    expect(credentials.jksPath, r'C:\keys\release.jks');
    expect(credentials.keyAlias, 'release');
    expect(credentials.storePassword, 'store-password');
    expect(credentials.keyPassword, 'key-password');

    final metadata = await service.metadata('project-1');
    expect(metadata.hasGooglePlayJson, isTrue);
    expect(metadata.hasAnySigningCredential, isTrue);

    await service.delete('project-1');
    final deleted = await service.read('project-1');
    expect(deleted.hasGooglePlayJson, isFalse);
    expect(deleted.hasJksPath, isFalse);
    expect(secureStore.values, isEmpty);
  });
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
