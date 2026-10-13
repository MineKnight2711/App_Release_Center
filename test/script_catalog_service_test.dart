import 'dart:io';

import 'package:app_management_center/app/services/script_catalog_service.dart';
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

    test('keeps iOS and Android lanes with the same name distinct', () async {
      for (final platform in ['android', 'ios']) {
        final directory = Directory(p.join(tempDir.path, platform, 'fastlane'))
          ..createSync(recursive: true);
        File(p.join(directory.path, 'Fastfile')).writeAsStringSync(
          'default_platform(:$platform)\nplatform :$platform do\n  lane :release do\n  end\nend\n',
        );
      }
      final project = await ScriptCatalogService().inspect(tempDir.path);
      expect(project.fastlaneLanes.length, 2);
      expect(project.fastlaneLanes.map((lane) => lane.key).toSet().length, 2);
      final ios = project.fastlaneLanes.singleWhere(
        (lane) => lane.platform == 'ios',
      );
      expect(ios.workingDirectory, p.join(tempDir.path, 'ios'));
      expect(ios.command, 'fastlane ios release');
      expect(
        project.fastlaneLanes
            .singleWhere((lane) => lane.platform == 'android')
            .workingDirectory,
        isNull,
      );
    });
  });
}
