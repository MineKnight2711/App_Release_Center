import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class VaultException implements Exception {
  const VaultException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Where a key or a local vault is kept on this machine.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Windows secure storage (DPAPI) or the macOS keychain, as AMC keeps its
/// other credentials.
class SecureSecretStore implements SecretStore {
  const SecureSecretStore([
    this._storage = const FlutterSecureStorage(
      // Legacy keychain: works in ad-hoc signed (team-less) macOS builds.
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Argon2id cost, stored with the vault so a later change of defaults still
/// derives the same key for an existing vault.
class VaultKdfParams {
  const VaultKdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// OWASP's minimum for Argon2id: 19 MiB, 2 passes, 1 lane.
  static const standard = VaultKdfParams(
    memoryKiB: 19456,
    iterations: 2,
    parallelism: 1,
  );

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Map<String, dynamic> toJson() => {
    'algorithm': 'argon2id',
    'memoryKiB': memoryKiB,
    'iterations': iterations,
    'parallelism': parallelism,
  };

  factory VaultKdfParams.fromJson(Map<String, dynamic> json) => VaultKdfParams(
    memoryKiB: (json['memoryKiB'] as num?)?.toInt() ?? standard.memoryKiB,
    iterations: (json['iterations'] as num?)?.toInt() ?? standard.iterations,
    parallelism: (json['parallelism'] as num?)?.toInt() ?? standard.parallelism,
  );
}

/// End-to-end encryption of the team vault: AES-GCM 256 with a key derived
/// from the team's passphrase. Firebase only ever stores what this produces.
class VaultCipher {
  VaultCipher._(this._key, this.keyBytes);

  static const _prefix = 'qav1';

  /// Encrypted with the key and stored beside the vault; decrypting it is how
  /// a passphrase is checked without storing anything derived from it.
  static const checkPlaintext = 'qa-desk-vault';

  static final _algorithm = AesGcm.with256bits();
  static final _random = Random.secure();

  final SecretKey _key;

  /// The raw key, cached in this machine's secure storage after unlocking so
  /// the passphrase is asked once per machine.
  final List<int> keyBytes;

  static List<int> randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));

  static Future<VaultCipher> derive(
    String passphrase,
    List<int> salt,
    VaultKdfParams params,
  ) async {
    final kdf = Argon2id(
      parallelism: params.parallelism,
      memory: params.memoryKiB,
      iterations: params.iterations,
      hashLength: 32,
    );
    final key = await kdf.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
    return VaultCipher._(key, await key.extractBytes());
  }

  static VaultCipher fromKeyBytes(List<int> bytes) =>
      VaultCipher._(SecretKey(bytes), List.unmodifiable(bytes));

  Future<String> encrypt(String plaintext) async {
    final box = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: _key,
      nonce: randomBytes(12),
    );
    return [
      _prefix,
      base64UrlEncode(box.nonce),
      base64UrlEncode(box.cipherText),
      base64UrlEncode(box.mac.bytes),
    ].join(':');
  }

  Future<String> decrypt(String payload) async {
    final parts = payload.split(':');
    if (parts.length != 4 || parts.first != _prefix) {
      throw const VaultException('Dữ liệu kho không đúng định dạng.');
    }
    try {
      final clear = await _algorithm.decrypt(
        SecretBox(
          base64Url.decode(parts[2]),
          nonce: base64Url.decode(parts[1]),
          mac: Mac(base64Url.decode(parts[3])),
        ),
        secretKey: _key,
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      throw const VaultException('Khoá kho không khớp.');
    } on FormatException {
      throw const VaultException('Dữ liệu kho không đúng định dạng.');
    }
  }

  /// Whether this key opens a vault whose check value is [check].
  Future<bool> opens(String check) async {
    try {
      return await decrypt(check) == checkPlaintext;
    } on VaultException {
      return false;
    }
  }
}
