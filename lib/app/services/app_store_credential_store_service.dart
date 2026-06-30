import 'package:app_release_center/app/models/app_store_credentials.dart';
import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:get/get.dart';

class AppStoreCredentialStoreService extends GetxService {
  AppStoreCredentialStoreService({SecureKeyValueStore? secureStore})
    : _secureStore = secureStore ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _secureStore;

  Future<AppStoreCredentials> read(String projectId) async {
    return AppStoreCredentials(
      p8PrivateKey: await _secureStore.read(
        key: _key(projectId, _p8PrivateKeyKey),
      ),
      keyId: await _secureStore.read(key: _key(projectId, _keyIdKey)),
      issuerId: await _secureStore.read(key: _key(projectId, _issuerIdKey)),
      teamId: await _secureStore.read(key: _key(projectId, _teamIdKey)),
      inHouse:
          _parseBool(
            await _secureStore.read(key: _key(projectId, _inHouseKey)),
          ) ??
          false,
    );
  }

  Future<AppStoreCredentialMetadata> metadata(String projectId) async {
    return (await read(projectId)).metadata;
  }

  Future<void> save(String projectId, AppStoreCredentials credentials) async {
    await _writeOrDelete(projectId, _p8PrivateKeyKey, credentials.p8PrivateKey);
    await _writeOrDelete(projectId, _keyIdKey, credentials.keyId);
    await _writeOrDelete(projectId, _issuerIdKey, credentials.issuerId);
    await _writeOrDelete(projectId, _teamIdKey, credentials.teamId);
    await _writeOrDelete(
      projectId,
      _inHouseKey,
      credentials.inHouse ? 'true' : null,
    );
  }

  Future<void> delete(String projectId) async {
    for (final name in _credentialKeys) {
      await _secureStore.delete(key: _key(projectId, name));
    }
  }

  Future<void> _writeOrDelete(
    String projectId,
    String name,
    String? value,
  ) async {
    final trimmed = value?.trim();
    final key = _key(projectId, name);
    if (trimmed == null || trimmed.isEmpty) {
      await _secureStore.delete(key: key);
      return;
    }

    await _secureStore.write(key: key, value: trimmed);
  }

  String _key(String projectId, String name) {
    return 'app_store_project.$projectId.$name';
  }

  bool? _parseBool(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return null;
  }
}

const _p8PrivateKeyKey = 'p8_private_key';
const _keyIdKey = 'key_id';
const _issuerIdKey = 'issuer_id';
const _teamIdKey = 'team_id';
const _inHouseKey = 'in_house';
const _credentialKeys = [
  _p8PrivateKeyKey,
  _keyIdKey,
  _issuerIdKey,
  _teamIdKey,
  _inHouseKey,
];
