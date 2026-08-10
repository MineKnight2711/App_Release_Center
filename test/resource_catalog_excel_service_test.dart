import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:app_release_center/app/models/resource_catalog.dart';
import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_release_center/app/services/gemini_env_service.dart';
import 'package:app_release_center/app/services/resource_catalog_crypto_service.dart';
import 'package:app_release_center/app/services/resource_catalog_excel_service.dart';
import 'package:app_release_center/app/services/resource_catalog_password_store_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late ResourceCatalogCryptoService crypto;
  late ResourceCatalogPasswordStoreService passwordStore;
  late ResourceCatalogExcelService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('arc_resource_excel_');
    crypto = ResourceCatalogCryptoService(
      env: GeminiEnvService(rootDirectory: root),
    );
    passwordStore = ResourceCatalogPasswordStoreService(
      secureStore: _MemorySecureKeyValueStore(),
    );
    service = ResourceCatalogExcelService(
      crypto: crypto,
      passwordStore: passwordStore,
    );
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  test(
    'exports encrypted passwords and imports them into secure store',
    () async {
      await passwordStore.save('secret-key-1', 'super-secret-password');
      final outputPath = p.join(root.path, 'catalog.xlsx');

      final exportResult = await service.exportCatalog(
        outputPath: outputPath,
        resources: [
          ResourceCatalogItem(
            id: 'resource-1',
            kind: ResourceCatalogKind.figma,
            title: 'Design handoff',
            url: 'https://figma.example.com/file/app',
            tags: const ['design'],
            updatedAt: DateTime.utc(2026, 8, 3),
          ),
        ],
        passwords: [
          ResourcePasswordEntry(
            id: 'password-1',
            secretKey: 'secret-key-1',
            site: 'Admin',
            loginUrl: 'https://admin.example.com',
            username: 'release@example.com',
            updatedAt: DateTime.utc(2026, 8, 3),
          ),
        ],
      );

      expect(exportResult.resourceCount, 1);
      expect(exportResult.passwordCount, 1);
      final archive = ZipDecoder().decodeBytes(
        File(outputPath).readAsBytesSync(),
      );
      expect(archive.findFile('xl/worksheets/sheet1.xml'), isNotNull);
      expect(archive.findFile('xl/worksheets/sheet2.xml'), isNotNull);
      final passwordSheet = utf8.decode(
        archive.findFile('xl/worksheets/sheet2.xml')!.readBytes()!,
      );
      expect(passwordSheet, contains('arcenc:v1:'));
      expect(passwordSheet, isNot(contains('super-secret-password')));

      final importedPasswordStore = ResourceCatalogPasswordStoreService(
        secureStore: _MemorySecureKeyValueStore(),
      );
      final importedService = ResourceCatalogExcelService(
        crypto: crypto,
        passwordStore: importedPasswordStore,
      );
      final importResult = await importedService.importCatalog(
        projectPath: r'C:\apps\demo',
        inputPath: outputPath,
      );

      expect(importResult.resourceCount, 1);
      expect(importResult.passwordCount, 1);
      expect(
        importResult.bundle.resources.single.kind,
        ResourceCatalogKind.figma,
      );
      expect(
        await importedPasswordStore.read('secret-key-1'),
        'super-secret-password',
      );
    },
  );
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
