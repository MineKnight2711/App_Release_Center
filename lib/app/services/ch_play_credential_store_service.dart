import 'package:app_release_center/app/models/ch_play_credentials.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

abstract class SecureKeyValueStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }
}

class ChPlayCredentialStoreService extends GetxService {
  ChPlayCredentialStoreService({SecureKeyValueStore? secureStore})
    : _secureStore = secureStore ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _secureStore;

  Future<ChPlayCredentials> read(String projectId) async {
    return ChPlayCredentials(
      googlePlayJson: await _secureStore.read(
        key: _key(projectId, _googlePlayJsonKey),
      ),
      jksPath: await _secureStore.read(key: _key(projectId, _jksPathKey)),
      keyAlias: await _secureStore.read(key: _key(projectId, _keyAliasKey)),
      storePassword: await _secureStore.read(
        key: _key(projectId, _storePasswordKey),
      ),
      keyPassword: await _secureStore.read(
        key: _key(projectId, _keyPasswordKey),
      ),
    );
  }

  Future<ChPlayCredentialMetadata> metadata(String projectId) async {
    return (await read(projectId)).metadata;
  }

  Future<void> save(String projectId, ChPlayCredentials credentials) async {
    await _writeOrDelete(
      projectId,
      _googlePlayJsonKey,
      credentials.googlePlayJson,
    );
    await _writeOrDelete(projectId, _jksPathKey, credentials.jksPath);
    await _writeOrDelete(projectId, _keyAliasKey, credentials.keyAlias);
    await _writeOrDelete(
      projectId,
      _storePasswordKey,
      credentials.storePassword,
    );
    await _writeOrDelete(projectId, _keyPasswordKey, credentials.keyPassword);
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
    return 'ch_play_project.$projectId.$name';
  }
}

const _googlePlayJsonKey = 'google_play_json';
const _jksPathKey = 'jks_path';
const _keyAliasKey = 'key_alias';
const _storePasswordKey = 'store_password';
const _keyPasswordKey = 'key_password';
const _credentialKeys = [
  _googlePlayJsonKey,
  _jksPathKey,
  _keyAliasKey,
  _storePasswordKey,
  _keyPasswordKey,
];
