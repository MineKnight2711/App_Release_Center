import 'dart:io';

import 'package:app_management_center/app/services/legacy_storage_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LegacyStorageMigrationService', () {
    const service = LegacyStorageMigrationService();
    late Directory root;
    late Directory current;
    late Directory legacy;

    setUp(() {
      root = Directory.systemTemp.createTempSync(
        'app_management_center_migration_',
      );
      current = Directory(p.join(root.path, 'App Management Center'));
      legacy = Directory(
        p.join(root.path, LegacyStorageMigrationService.legacyDirectoryNames.first),
      );
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    void writeLegacy(String relativePath, String contents) {
      final file = File(p.join(legacy.path, relativePath));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    test('copies preferences and secure storage out of the old directory', () {
      writeLegacy('shared_preferences.json', '{"last_project_path":"C:/repo"}');
      writeLegacy('flutter_secure_storage.dat', 'encrypted-bytes');
      writeLegacy(p.join('api_monitor_webview', 'cache.bin'), 'webview');

      final result = service.migrateInto(current);

      expect(result.outcome, LegacyStorageMigrationOutcome.migrated);
      expect(result.copiedFiles, 3);
      expect(
        File(p.join(current.path, 'shared_preferences.json')).readAsStringSync(),
        '{"last_project_path":"C:/repo"}',
      );
      expect(
        File(p.join(current.path, 'flutter_secure_storage.dat'))
            .readAsStringSync(),
        'encrypted-bytes',
      );
      expect(
        File(
          p.join(current.path, 'api_monitor_webview', 'cache.bin'),
        ).readAsStringSync(),
        'webview',
      );
    });

    test('leaves the legacy directory in place', () {
      writeLegacy('shared_preferences.json', '{}');

      service.migrateInto(current);

      expect(File(p.join(legacy.path, 'shared_preferences.json')).existsSync(),
          isTrue);
    });

    test('skips once the current directory already holds data', () {
      writeLegacy('shared_preferences.json', '{"stale":true}');
      current.createSync(recursive: true);
      File(
        p.join(current.path, 'shared_preferences.json'),
      ).writeAsStringSync('{"fresh":true}');

      final result = service.migrateInto(current);

      expect(result.outcome, LegacyStorageMigrationOutcome.skipped);
      expect(
        File(p.join(current.path, 'shared_preferences.json')).readAsStringSync(),
        '{"fresh":true}',
      );
    });

    test('skips when no legacy directory exists', () {
      final result = service.migrateInto(current);

      expect(result.outcome, LegacyStorageMigrationOutcome.skipped);
      expect(current.existsSync(), isFalse);
    });

    test('ignores a legacy directory that holds no recognised data', () {
      writeLegacy('unrelated.log', 'noise');

      final result = service.migrateInto(current);

      expect(result.outcome, LegacyStorageMigrationOutcome.skipped);
    });

    test('running twice copies nothing the second time', () {
      writeLegacy('shared_preferences.json', '{"a":1}');

      final first = service.migrateInto(current);
      final second = service.migrateInto(current);

      expect(first.outcome, LegacyStorageMigrationOutcome.migrated);
      expect(second.outcome, LegacyStorageMigrationOutcome.skipped);
    });
  });
}
