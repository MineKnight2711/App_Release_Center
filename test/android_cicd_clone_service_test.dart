import 'dart:io';

import 'package:app_release_center/app/services/android_cicd_clone_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AndroidCicdCloneService', () {
    late Directory tempDir;
    late AndroidCicdCloneService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('arc_android_cicd_');
      service = AndroidCicdCloneService();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('detects non-flavored Android projects', () async {
      final project = _createProject(tempDir, _groovyGradle());

      final preview = await service.preview(project.path);

      expect(preview.applicationId, 'com.example.demo');
      expect(preview.flavors, isEmpty);
      expect(preview.selectedFlavor, isNull);
      expect(
        _draft(preview, 'android/env.properties.example').content,
        contains('ANDROID_FLAVOR=\n'),
      );
      expect(
        _draft(preview, 'android/fastlane/Fastfile').content,
        contains('flavor.empty? ? nil : flavor'),
      );
    });

    test('uses the only detected flavor as the default flavor', () async {
      final project = _createProject(
        tempDir,
        _groovyGradle(
          flavors: '''
    flavorDimensions "app"
    productFlavors {
        staging {
            dimension "app"
        }
    }
''',
        ),
      );

      final preview = await service.preview(project.path);

      expect(preview.flavors, ['staging']);
      expect(preview.selectedFlavor, 'staging');
      expect(
        _draft(preview, 'android/env.properties.example').content,
        contains('ANDROID_FLAVOR=staging'),
      );
    });

    test(
      'prefers production when multiple flavors include production',
      () async {
        final project = _createProject(
          tempDir,
          _groovyGradle(
            flavors: '''
    flavorDimensions "app"
    productFlavors {
        dev {
            dimension "app"
        }
        production {
            dimension "app"
        }
    }
''',
          ),
        );

        final preview = await service.preview(project.path);

        expect(preview.flavors, ['dev', 'production']);
        expect(preview.selectedFlavor, 'production');
        expect(
          _draft(preview, 'android/fastlane/Fastfile').content,
          contains('flavor.empty? ? "production" : flavor'),
        );
      },
    );

    test('uses the first detected flavor when production is absent', () async {
      final project = _createProject(
        tempDir,
        _groovyGradle(
          flavors: '''
    flavorDimensions "app"
    productFlavors {
        qa {
            dimension "app"
        }
        beta {
            dimension "app"
        }
    }
''',
        ),
      );

      final preview = await service.preview(project.path);

      expect(preview.flavors, ['qa', 'beta']);
      expect(preview.selectedFlavor, 'qa');
    });

    test('overwrites existing files after confirmation', () async {
      final project = _createProject(tempDir, _groovyGradle());
      final releaseScript = File(p.join(project.path, 'auto', 'release.sh'))
        ..createSync(recursive: true)
        ..writeAsStringSync('old release script');

      final preview = await service.preview(project.path);

      expect(
        preview.changeFor('auto/release.sh')?.action,
        AndroidCicdFileAction.overwrite,
      );

      await service.apply(preview);

      expect(
        releaseScript.readAsStringSync(),
        contains('Starting the release process'),
      );
      expect(
        releaseScript.readAsStringSync(),
        isNot(contains('old release script')),
      );
    });

    test('creates release pull requests against main by default', () async {
      final project = _createProject(tempDir, _groovyGradle());

      final preview = await service.preview(project.path);

      expect(
        _draft(preview, 'auto/release.sh').content,
        contains('Creating pull request to main'),
      );
      expect(
        _draft(preview, 'auto/merge.sh').content,
        contains('TARGET_BRANCH="\${TARGET_BRANCH:-main}"'),
      );
    });

    test('skips existing files when overwrite is disabled', () async {
      final project = _createProject(tempDir, _groovyGradle());
      final releaseScript = File(p.join(project.path, 'auto', 'release.sh'))
        ..createSync(recursive: true)
        ..writeAsStringSync('old release script');

      final preview = await service.preview(
        project.path,
        overwriteExisting: false,
      );

      expect(
        preview.changeFor('auto/release.sh')?.action,
        AndroidCicdFileAction.skip,
      );

      await service.apply(preview);

      expect(releaseScript.readAsStringSync(), 'old release script');
    });

    test('fallback mode creates a generic scaffold without Gradle', () async {
      final project = _createProjectWithoutGradle(tempDir);

      final preview = await service.preview(
        project.path,
        mode: AndroidCicdCloneMode.fallback,
      );

      expect(preview.isFallback, isTrue);
      expect(preview.gradleFilePath, 'Not found');
      expect(preview.applicationId, isNull);
      expect(preview.flavors, isEmpty);
      expect(preview.selectedFlavor, isNull);
      expect(
        _draft(preview, 'android/fastlane/Fastfile').content,
        contains('flavor.empty? ? nil : flavor'),
      );
      expect(
        preview.warnings,
        contains(
          'Gradle app build file was not found. Update ANDROID_PACKAGE_NAME before uploading.',
        ),
      );
    });

    test(
      'fallback mode ignores detected flavors and skips Gradle patch',
      () async {
        final project = _createProject(
          tempDir,
          _groovyGradle(
            flavors: '''
    flavorDimensions "app"
    productFlavors {
        dev {
            dimension "app"
        }
        production {
            dimension "app"
        }
    }
''',
          ),
        );

        final preview = await service.preview(
          project.path,
          mode: AndroidCicdCloneMode.fallback,
        );

        expect(preview.isFallback, isTrue);
        expect(preview.applicationId, 'com.example.demo');
        expect(preview.flavors, isEmpty);
        expect(preview.selectedFlavor, isNull);
        expect(_draftOrNull(preview, 'android/app/build.gradle'), isNull);
        expect(
          _draft(preview, 'android/env.properties.example').content,
          contains('ANDROID_FLAVOR=\n'),
        );
        expect(
          preview.warnings,
          contains(
            'Detected flavors were ignored: dev, production. Set ANDROID_FLAVOR manually if this app requires one.',
          ),
        );
      },
    );
  });
}

Directory _createProject(Directory parent, String gradleSource) {
  final project = _createProjectWithoutGradle(parent);
  File(p.join(project.path, 'android', 'app', 'build.gradle'))
    ..createSync(recursive: true)
    ..writeAsStringSync(gradleSource);
  return project;
}

Directory _createProjectWithoutGradle(Directory parent) {
  final project = Directory(p.join(parent.path, 'demo'))..createSync();
  File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: demo
version: 1.0.0+1
''');
  File(p.join(project.path, 'android', '.gitignore'))
    ..createSync(recursive: true)
    ..writeAsStringSync('/local.properties\n');
  return project;
}

AndroidCicdFileDraft _draft(
  AndroidCicdClonePreview preview,
  String relativePath,
) {
  return preview.drafts.singleWhere(
    (draft) => draft.relativePath == relativePath,
  );
}

AndroidCicdFileDraft? _draftOrNull(
  AndroidCicdClonePreview preview,
  String relativePath,
) {
  for (final draft in preview.drafts) {
    if (draft.relativePath == relativePath) return draft;
  }
  return null;
}

String _groovyGradle({String flavors = ''}) {
  return '''
plugins {
    id "com.android.application"
}

android {
    namespace = "com.example.demo"
    defaultConfig {
        applicationId "com.example.demo"
        versionCode flutter.versionCode
        versionName flutter.versionName
    }
$flavors
    buildTypes {
        release {
            signingConfig signingConfigs.debug
        }
    }
}
''';
}
