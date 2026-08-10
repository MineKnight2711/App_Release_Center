import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:get/get.dart';

class ResourceCatalogPasswordStoreService extends GetxService {
  ResourceCatalogPasswordStoreService({SecureKeyValueStore? secureStore})
    : _secureStore = secureStore ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _secureStore;

  Future<String?> read(String secretKey) {
    return _secureStore.read(key: _key(secretKey));
  }

  Future<void> save(String secretKey, String? password) async {
    final value = password ?? '';
    if (value.isEmpty) {
      await delete(secretKey);
      return;
    }

    await _secureStore.write(key: _key(secretKey), value: value);
  }

  Future<void> delete(String secretKey) {
    return _secureStore.delete(key: _key(secretKey));
  }

  String _key(String secretKey) {
    return 'resource_catalog_password.$secretKey';
  }
}
