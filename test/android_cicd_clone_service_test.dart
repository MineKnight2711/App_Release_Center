import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/services/android_cicd_clone_service.dart';
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
      final fastfile = _draft(preview, 'android/fastlane/Fastfile').content;
      expect(fastfile, contains('lane :build_aab do |options|'));
      expect(fastfile, contains('ARC_AAB_PATH:#{aab_path}'));
      expect(fastfile, contains('options[:skip_build]'));
      expect(fastfile, contains('ENV["SKIP_PLAY_BUILD"]'));
      expect(
        _draft(preview, 'android/.gitignore').content,
        contains('/key.properties'),
      );
    });

    test(
      'version templates read Fastlane markers and surface lane failures',
      () async {
        final project = _createProject(tempDir, _groovyGradle());
        final preview = await service.preview(project.path);
        final auto = Directory(p.join(project.path, 'auto'))..createSync();
        final bin = Directory(p.join(tempDir.path, 'mock bin'))..createSync();
        final mock = File(p.join(bin.path, 'fastlane'))
          ..writeAsStringSync(r'''#!/bin/bash
for argument in "$@"; do
  [[ "$argument" != --capture_output ]] || exit 42
done
if [[ "${FAIL_LANE:-}" == "$2" ]]; then
  echo 'simulated Fastlane failure' >&2
  exit 7
fi
case "$2" in
  fetch_version_code_from_play_store) echo STORE_CODE_ONLY:200;;
  get_local_version_code) echo LOCAL_CODE_ONLY:200;;
  get_version_name) echo VERSION_NAME_ONLY:3.5.24;;
  bump_version_code|update_version_name) echo "MOCK_UPDATE:$*";;
esac
''');
        expect((await Process.run('chmod', ['+x', mock.path])).exitCode, 0);

        for (final name in ['control_ver_code.sh', 'control_ver_name.sh']) {
          final script = File(p.join(auto.path, name))
            ..writeAsStringSync(_draft(preview, 'auto/$name').content);
          Future<ProcessResult> run({String failLane = ''}) async {
            final process = await Process.start(
              'bash',
              [script.path],
              workingDirectory: auto.path,
              environment: {
                'PATH': '${bin.path}:${Platform.environment['PATH']}',
                'USE_BUNDLER_FASTLANE': '0',
                'FAIL_LANE': failLane,
              },
            );
            final stdout = process.stdout.transform(utf8.decoder).join();
            final stderr = process.stderr.transform(utf8.decoder).join();
            process.stdin.write('y\n1\n');
            await process.stdin.close();
            return ProcessResult(
              process.pid,
              await process.exitCode,
              await stdout,
              await stderr,
            );
          }

          final result = await run();
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}${result.stderr}',
          );
          expect(
            result.stdout,
            contains(
              name == 'control_ver_code.sh'
                  ? 'MOCK_UPDATE:android bump_version_code'
                  : 'MOCK_UPDATE:android update_version_name version_name:3.5.25',
            ),
          );
          final failure = await run(
            failLane: name == 'control_ver_code.sh'
                ? 'get_local_version_code'
                : 'get_version_name',
          );
          expect(failure.exitCode, 1);
          expect(failure.stderr, contains('simulated Fastlane failure'));
          expect(failure.stdout, isNot(contains('MOCK_UPDATE')));
        }
      },
      skip: Platform.isWindows,
    );

    test('patches Kotlin Gradle signing with explicit File import', () async {
      final project = _createProject(
        tempDir,
        _kotlinGradle(),
        gradleFileName: 'build.gradle.kts',
      );

      final preview = await service.preview(project.path);

      final gradle = _draft(preview, 'android/app/build.gradle.kts').content;
      expect(gradle, contains('import java.io.File'));
      expect(gradle, contains('import java.util.Properties'));
      expect(
        gradle,
        contains('fun resolveKeystoreFile(rawPath: String?): File?'),
      );
      expect(gradle, contains('val candidate = File(path)'));
      expect(gradle, isNot(contains('java.io.File(path)')));
      expect(gradle, isNot(contains('rawPath: String?): java.io.File?')));
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

    test(
      'adds key.properties to android gitignore when env is already ignored',
      () async {
        final project = _createProject(tempDir, _groovyGradle());
        File(p.join(project.path, 'android', '.gitignore'))
          ..createSync(recursive: true)
          ..writeAsStringSync('/local.properties\n/env.properties\n');

        final preview = await service.preview(project.path);

        final gitignore = _draft(preview, 'android/.gitignore').content;
        expect(gitignore, contains('/env.properties\n/key.properties\n'));
      },
    );

    test('fallback mode creates a generic scaffold without Gradle', () async {
      final project = _createProjectWithoutGradle(tempDir);

      final preview = await service.preview(
        project.path,
        mode: AndroidCicdCloneMode.fallback,
      );

      expect(preview.isFallback, isTrue);
      expect(preview.gradleFilePath, 'Không thấy');
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
          'Không thấy file build Gradle của app. Sửa ANDROID_PACKAGE_NAME trước khi upload.',
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

Directory _createProject(
  Directory parent,
  String gradleSource, {
  String gradleFileName = 'build.gradle',
}) {
  final project = _createProjectWithoutGradle(parent);
  File(p.join(project.path, 'android', 'app', gradleFileName))
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

String _kotlinGradle({String flavors = ''}) {
  return '''
plugins {
    id("com.android.application")
}

android {
    namespace = "com.example.demo"
    defaultConfig {
        applicationId = "com.example.demo"
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
$flavors
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
''';
}
