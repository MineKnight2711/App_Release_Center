import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Seals what one remote iOS step needs for one build host.
///
/// The relay stores every command it carries, and a remote build has to carry
/// the App Store Connect private key and the gitignored files the project
/// cannot build without. Only the host can open an envelope: it is encrypted to
/// the host's X25519 key with a key agreement that is new for each envelope, so
/// the relay holds ciphertext alone.
///
/// The associated data binds the envelope to the host, the action, the run and
/// the project it was written for. The relay can route a command but cannot
/// lift a sealed "draft" onto a "submit", or point it at another run.
class IosBuildEnvelope {
  const IosBuildEnvelope._();

  static const _version = 1;
  static const _info = 'amc-ios-build-v1';
  static final _x25519 = X25519();
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static String associatedData({
    required String desktopId,
    required String action,
    required String runId,
    required String projectId,
  }) => ['amc-ios-v1', desktopId, action, runId, projectId].join('\n');

  /// Returns base64url without padding, the alphabet the relay accepts.
  static Future<String> seal({
    required List<int> hostPublicKey,
    required Map<String, Object?> body,
    required String associatedData,
  }) async {
    if (hostPublicKey.length != 32) {
      throw const FormatException('Khóa công khai của Mac không hợp lệ.');
    }
    final ephemeral = await _x25519.newKeyPair();
    final ephemeralPublic = (await ephemeral.extractPublicKey()).bytes;
    final key = await _derive(
      await _x25519.sharedSecretKey(
        keyPair: ephemeral,
        remotePublicKey: SimplePublicKey(
          hostPublicKey,
          type: KeyPairType.x25519,
        ),
      ),
      ephemeralPublic,
      hostPublicKey,
    );
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(body)),
      secretKey: key,
      nonce: _aes.newNonce(),
      aad: utf8.encode(associatedData),
    );
    final bytes = BytesBuilder(copy: false)
      ..addByte(_version)
      ..add(ephemeralPublic)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return base64Url.encode(bytes.takeBytes()).replaceAll('=', '');
  }

  /// Throws [FormatException] when the envelope was not sealed for
  /// [hostKeyPair] and [associatedData], or was altered on the way.
  static Future<Map<String, Object?>> open({
    required SimpleKeyPair hostKeyPair,
    required String envelope,
    required String associatedData,
  }) async {
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(envelope.trim()));
    } on FormatException {
      throw const FormatException('Envelope iOS không đọc được.');
    }
    const header = 1 + 32 + 12;
    if (bytes.length < header + 16 || bytes.first != _version) {
      throw const FormatException('Envelope iOS sai định dạng.');
    }
    final ephemeralPublic = bytes.sublist(1, 33);
    final hostPublic = (await hostKeyPair.extractPublicKey()).bytes;
    final key = await _derive(
      await _x25519.sharedSecretKey(
        keyPair: hostKeyPair,
        remotePublicKey: SimplePublicKey(
          ephemeralPublic,
          type: KeyPairType.x25519,
        ),
      ),
      ephemeralPublic,
      hostPublic,
    );
    final List<int> plain;
    try {
      plain = await _aes.decrypt(
        SecretBox(
          bytes.sublist(header, bytes.length - 16),
          nonce: bytes.sublist(33, header),
          mac: Mac(bytes.sublist(bytes.length - 16)),
        ),
        secretKey: key,
        aad: utf8.encode(associatedData),
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'Envelope iOS không dành cho máy này hoặc đã bị sửa.',
      );
    }
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! Map) {
      throw const FormatException('Envelope iOS sai định dạng.');
    }
    return Map<String, Object?>.from(decoded);
  }

  /// A short, readable digest of a host key, shown on both machines at pairing
  /// so a person can confirm the relay did not swap the key in between.
  static Future<String> fingerprint(List<int> publicKey) async {
    final digest = (await Sha256().hash(publicKey)).bytes.take(8);
    final hex = digest
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return [
      for (var index = 0; index < hex.length; index += 4)
        hex.substring(index, index + 4),
    ].join('-');
  }

  static String randomId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static Future<SecretKey> _derive(
    SecretKey shared,
    List<int> ephemeralPublic,
    List<int> hostPublic,
  ) => _hkdf.deriveKey(
    secretKey: shared,
    nonce: [...ephemeralPublic, ...hostPublic],
    info: utf8.encode(_info),
  );
}
