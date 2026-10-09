import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_management_center/app/models/remote_unlock.dart';
import 'package:app_management_center/app/services/remote_unlock_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

void main() {
  test('encrypts a short-lived password envelope with RSA OAEP SHA-256', () {
    final pair = _keyPair();
    final publicKey = pair.publicKey as RSAPublicKey;
    final privateKey = pair.privateKey as RSAPrivateKey;
    final challenge = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final state = RemoteUnlockState(
      installed: true,
      enabled: true,
      keyId: 'test-key',
      modulus: _base64BigInt(publicKey.modulus!),
      exponent: _base64BigInt(publicKey.exponent!),
      challenge: _base64(challenge),
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      accountName: r'WORKSTATION\miste',
    );

    final encoded = RemoteUnlockService.encryptPassword(
      state: state,
      password: 'correct horse battery staple',
    );

    expect(encoded, isNot(contains('correct')));
    final cipher = OAEPEncoding.withSHA256(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final plain = cipher.process(
      Uint8List.fromList(base64Url.decode(base64Url.normalize(encoded))),
    );
    expect(ascii.decode(plain.sublist(0, 4)), 'AMC1');
    expect(plain[4], 1);
    expect(plain.sublist(13, 45), challenge);
    final userLength = _u16(plain, 45);
    final passwordLength = _u16(plain, 47);
    expect(
      utf8.decode(plain.sublist(49, 49 + userLength)),
      r'WORKSTATION\miste',
    );
    expect(
      utf8.decode(
        plain.sublist(49 + userLength, 49 + userLength + passwordLength),
      ),
      'correct horse battery staple',
    );
  });

  test('refuses an expired or incomplete challenge', () {
    expect(
      () => RemoteUnlockService.encryptPassword(
        state: RemoteUnlockState(
          installed: true,
          enabled: true,
          expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
        password: 'secret',
      ),
      throwsA(isA<RemoteUnlockException>()),
    );
  });

  test(
    'hands only decoded ciphertext to the credential provider',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'amc-remote-unlock-',
      );
      addTearDown(() => directory.delete(recursive: true));
      await File(
        '${directory.path}${Platform.pathSeparator}challenge.bin',
      ).writeAsBytes([1]);
      final ciphertext = Uint8List.fromList(
        List<int>.generate(384, (index) => index % 251),
      );
      final service = RemoteUnlockService(dataDirectory: directory);

      await service.acceptEncryptedEnvelope(_base64(ciphertext));

      final pending = File(
        '${directory.path}${Platform.pathSeparator}pending.bin',
      );
      expect(await pending.readAsBytes(), ciphertext);
      expect(await File('${pending.path}.tmp').exists(), isFalse);
    },
    skip: !Platform.isWindows,
  );

  test(
    'throttles the fourth encrypted unlock request in ten minutes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'amc-remote-unlock-',
      );
      addTearDown(() => directory.delete(recursive: true));
      await File(
        '${directory.path}${Platform.pathSeparator}challenge.bin',
      ).writeAsBytes([1]);
      final envelope = _base64(Uint8List(384));
      final service = RemoteUnlockService(dataDirectory: directory);

      await service.acceptEncryptedEnvelope(envelope);
      await service.acceptEncryptedEnvelope(envelope);
      await service.acceptEncryptedEnvelope(envelope);

      expect(
        () => service.acceptEncryptedEnvelope(envelope),
        throwsA(isA<RemoteUnlockException>()),
      );
    },
    skip: !Platform.isWindows,
  );
}

AsymmetricKeyPair<PublicKey, PrivateKey> _keyPair() {
  final secure = FortunaRandom();
  secure.seed(
    KeyParameter(Uint8List.fromList(List<int>.generate(32, (i) => i + 1))),
  );
  final generator = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
        secure,
      ),
    );
  return generator.generateKeyPair();
}

String _base64BigInt(BigInt value) {
  final bytes = <int>[];
  var current = value;
  while (current > BigInt.zero) {
    bytes.add((current & BigInt.from(255)).toInt());
    current >>= 8;
  }
  return _base64(Uint8List.fromList(bytes.reversed.toList()));
}

String _base64(Uint8List value) => base64Url.encode(value).replaceAll('=', '');

int _u16(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint16(offset, Endian.little);
