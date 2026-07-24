import 'dart:io';

import 'package:app_release_center/app/services/ch_play_project_inspector_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChPlayProjectInspectorService', () {
    test('parses pubspec version name and code', () {
      final version = ChPlayProjectInspectorService.parsePubspecVersion('''
name: sample
version: 1.2.3+45
''');

      expect(version?.name, '1.2.3');
      expect(version?.code, 45);
      expect(version?.display, '1.2.3+45');
    });

    test('rejects pubspec versions without a build number', () {
      final version = ChPlayProjectInspectorService.parsePubspecVersion('''
name: sample
version: 1.2.3
''');

      expect(version, isNull);
    });

    test('parses Groovy applicationId from defaultConfig first', () {
      final applicationId = ChPlayProjectInspectorService.parseApplicationId('''
android {
  defaultConfig {
    applicationId "com.example.main"
  }
  productFlavors {
    demo {
      applicationId "com.example.demo"
    }
  }
}
''');

      expect(applicationId, 'com.example.main');
    });

    test('parses Kotlin applicationId assignment', () {
      final applicationId = ChPlayProjectInspectorService.parseApplicationId('''
android {
  defaultConfig {
    applicationId = "com.example.kotlin"
  }
}
''');

      expect(applicationId, 'com.example.kotlin');
    });

    test('falls back to namespace when applicationId is absent', () {
      final applicationId = ChPlayProjectInspectorService.parseApplicationId('''
android {
  namespace = "com.example.namespace"
}
''');

      expect(applicationId, 'com.example.namespace');
    });

    test('inspect tolerates malformed project metadata files', () async {
      final directory = await Directory.systemTemp.createTemp(
        'app_release_center_ch_play_inspector_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });

      await File(
        '${directory.path}${Platform.pathSeparator}pubspec.yaml',
      ).writeAsBytes([0xFF, 0xFE, 0xFD]);
      await File(
        '${directory.path}${Platform.pathSeparator}android'
        '${Platform.pathSeparator}app${Platform.pathSeparator}build.gradle',
      ).create(recursive: true);
      await File(
        '${directory.path}${Platform.pathSeparator}android'
        '${Platform.pathSeparator}app${Platform.pathSeparator}build.gradle',
      ).writeAsBytes([0xFF, 0xFE, 0xFD]);

      final inspection = await ChPlayProjectInspectorService().inspect(
        directory.path,
      );

      expect(inspection.applicationId, isNull);
      expect(inspection.localVersion, isNull);
    });

    test('detectApplicationId skips malformed Gradle candidates', () async {
      final directory = await Directory.systemTemp.createTemp(
        'app_release_center_ch_play_inspector_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });

      final groovyGradle = File(
        '${directory.path}${Platform.pathSeparator}android'
        '${Platform.pathSeparator}app${Platform.pathSeparator}build.gradle',
      );
      final kotlinGradle = File(
        '${directory.path}${Platform.pathSeparator}android'
        '${Platform.pathSeparator}app${Platform.pathSeparator}build.gradle.kts',
      );
      await groovyGradle.create(recursive: true);
      await groovyGradle.writeAsBytes([0xFF, 0xFE, 0xFD]);
      await kotlinGradle.writeAsString('''
android {
  defaultConfig {
    applicationId = "com.example.kotlin"
  }
}
''');

      final applicationId = await ChPlayProjectInspectorService()
          .detectApplicationId(directory.path);

      expect(applicationId, 'com.example.kotlin');
    });
  });
}
