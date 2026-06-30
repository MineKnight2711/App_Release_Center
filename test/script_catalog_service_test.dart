import 'dart:io';

import 'package:app_release_center/app/services/script_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ScriptCatalogService', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('arc_catalog_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('loads projects that do not have an auto folder yet', () async {
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: demo
version: 1.0.0+1
''');

      final project = await ScriptCatalogService().inspect(tempDir.path);

      expect(project.path, tempDir.path);
      expect(project.scripts, isEmpty);
      expect(project.fastlaneLanes, isEmpty);
      expect(project.hasPlayReleaseTools, isFalse);
    });
  });
}
