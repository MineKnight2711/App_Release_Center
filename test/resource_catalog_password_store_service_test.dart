import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_release_center/app/services/resource_catalog_password_store_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saves, reads, and deletes resource catalog passwords', () async {
    final secureStore = _MemorySecureKeyValueStore();
    final service = ResourceCatalogPasswordStoreService(
      secureStore: secureStore,
    );

    await service.save('secret-key-1', 'super-secret-password');
    expect(await service.read('secret-key-1'), 'super-secret-password');

    await service.save('secret-key-1', '');
    expect(await service.read('secret-key-1'), isNull);

    await service.save('secret-key-1', 'new-password');
    await service.delete('secret-key-1');
    expect(await service.read('secret-key-1'), isNull);
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
