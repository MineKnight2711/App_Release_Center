import 'dart:convert';
import 'dart:io';

import 'package:app_release_center/app/services/gemini_env_service.dart';
import 'package:app_release_center/app/services/resource_catalog_crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late GeminiEnvService env;
  late ResourceCatalogCryptoService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('arc_resource_crypto_');
    env = GeminiEnvService(rootDirectory: root);
    service = ResourceCatalogCryptoService(env: env);
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  test('generates export key and encrypts without plaintext', () async {
    final payload = await service.encryptPassword('super-secret-password');

    expect(payload, startsWith('arcenc:v1:'));
    expect(payload, isNot(contains('super-secret-password')));
    expect(await service.decryptPassword(payload), 'super-secret-password');
    expect(await env.readValue('ARC_RESOURCE_EXPORT_KEY'), isNotEmpty);
  });

  test('fails to decrypt with a different export key', () async {
    final payload = await service.encryptPassword('super-secret-password');
    await env.writeValue(
      'ARC_RESOURCE_EXPORT_KEY',
      base64UrlEncode(List.filled(32, 7)),
    );

    expect(
      () => service.decryptPassword(payload),
      throwsA(isA<ResourceCatalogCryptoException>()),
    );
  });
}
