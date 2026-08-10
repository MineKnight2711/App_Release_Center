import 'dart:convert';
import 'dart:math';

import 'package:app_release_center/app/services/gemini_env_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:get/get.dart';

class ResourceCatalogCryptoService extends GetxService {
  ResourceCatalogCryptoService({required GeminiEnvService env}) : _env = env;

  final GeminiEnvService _env;
  final AesGcm _algorithm = AesGcm.with256bits();

  Future<String> readOrCreateExportKey() async {
    final existing = (await _env.readValue(_exportKeyName))?.trim();
    if (existing != null && _validKey(existing)) {
      return existing;
    }

    final generated = _randomBase64UrlBytes(_keyLength);
    await _env.writeValue(_exportKeyName, generated);
    return generated;
  }

  Future<String> encryptPassword(String password) async {
    if (password.isEmpty) return '';
    final key = await _secretKey();
    final nonce = _randomBytes(_nonceLength);
    final box = await _algorithm.encrypt(
      utf8.encode(password),
      secretKey: key,
      nonce: nonce,
    );

    return [
      _cipherPrefix,
      _cipherVersion,
      base64UrlEncode(nonce),
      base64UrlEncode(box.cipherText),
      base64UrlEncode(box.mac.bytes),
    ].join(':');
  }

  Future<String> decryptPassword(String payload) async {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) return '';
    final parts = trimmed.split(':');
    if (parts.length != 5 ||
        parts[0] != _cipherPrefix ||
        parts[1] != _cipherVersion) {
      throw const ResourceCatalogCryptoException(
        'Invalid encrypted password payload.',
      );
    }

    try {
      final clearBytes = await _algorithm.decrypt(
        SecretBox(
          _decodeBase64Url(parts[3]),
          nonce: _decodeBase64Url(parts[2]),
          mac: Mac(_decodeBase64Url(parts[4])),
        ),
        secretKey: await _secretKey(),
      );
      return utf8.decode(clearBytes);
    } catch (_) {
      throw const ResourceCatalogCryptoException(
        'Could not decrypt password with the current export key.',
      );
    }
  }

  bool isEncryptedPayload(String value) {
    return value.trim().startsWith('$_cipherPrefix:$_cipherVersion:');
  }

  Future<SecretKey> _secretKey() async {
    final encoded = await readOrCreateExportKey();
    final bytes = _decodeBase64Url(encoded);
    if (bytes.length != _keyLength) {
      throw const ResourceCatalogCryptoException(
        'Invalid ARC_RESOURCE_EXPORT_KEY length.',
      );
    }
    return SecretKey(bytes);
  }

  bool _validKey(String value) {
    try {
      return _decodeBase64Url(value).length == _keyLength;
    } catch (_) {
      return false;
    }
  }

  String _randomBase64UrlBytes(int length) {
    return base64UrlEncode(_randomBytes(length));
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  List<int> _decodeBase64Url(String value) {
    return base64Url.decode(base64Url.normalize(value.trim()));
  }
}

class ResourceCatalogCryptoException implements Exception {
  const ResourceCatalogCryptoException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _exportKeyName = 'ARC_RESOURCE_EXPORT_KEY';
const _cipherPrefix = 'arcenc';
const _cipherVersion = 'v1';
const _keyLength = 32;
const _nonceLength = 12;
