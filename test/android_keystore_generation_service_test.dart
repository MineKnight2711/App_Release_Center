import 'dart:io';

import 'package:app_release_center/app/services/android_keystore_generation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AndroidKeystoreGenerationService', () {
    late Directory tempDir;
    late Directory project;
    late _RecordingKeytoolRunner runner;
    late AndroidKeystoreGenerationService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('arc_jks_');
      project = _createFlutterAndroidProject(tempDir);
      runner = _RecordingKeytoolRunner();
      service = AndroidKeystoreGenerationService(
        commandRunner: runner,
        passwordGenerator: () => 'fixed-secret-password',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('generates a release JKS and writes signing config files', () async {
      final result = await service.generate(
        projectPath: project.path,
        distinguishedName: 'CN=Demo',
      );

      expect(runner.calls, hasLength(1));
      final call = runner.calls.single;
      expect(call.executable, 'keytool');
      expect(
        call.arguments,
        containsAllInOrder([
          '-genkeypair',
          '-v',
          '-keystore',
          result.keystorePath,
          '-storetype',
          'JKS',
          '-keyalg',
          'RSA',
          '-keysize',
          '2048',
          '-validity',
          '10000',
          '-alias',
          'release',
        ]),
      );
      expect(
        _argumentAfter(call.arguments, '-storepass'),
        result.storePassword,
      );
      expect(_argumentAfter(call.arguments, '-keypass'), result.keyPassword);
      expect(_argumentAfter(call.arguments, '-dname'), 'CN=Demo');

      expect(File(result.keystorePath).existsSync(), isTrue);
      expect(result.keyAlias, 'release');
      expect(result.storePassword, isNotEmpty);
      expect(result.keyPassword, result.storePassword);

      final envProperties = File(result.envPropertiesPath).readAsStringSync();
      expect(envProperties, contains('KEY_ALIAS=release'));
      expect(
        envProperties,
        contains('ANDROID_JKS_PATH=fastlane/keys/release.jks'),
      );
      expect(envProperties, contains('STORE_PASSWORD=fixed-secret-password'));
      expect(envProperties, contains('KEY_PASSWORD=fixed-secret-password'));

      final keyProperties = File(result.keyPropertiesPath).readAsStringSync();
      expect(keyProperties, contains('keyAlias=release'));
      expect(keyProperties, contains('storeFile=../fastlane/keys/release.jks'));
      expect(keyProperties, contains('storePassword=fixed-secret-password'));
      expect(keyProperties, contains('keyPassword=fixed-secret-password'));
    });

    test(
      'does not overwrite an existing JKS unless force is enabled',
      () async {
        final existing =
            File(
                p.join(
                  project.path,
                  'android',
                  'fastlane',
                  'keys',
                  'release.jks',
                ),
              )
              ..createSync(recursive: true)
              ..writeAsStringSync('existing');

        await expectLater(
          service.generate(projectPath: project.path),
          throwsA(
            isA<AndroidKeystoreGenerationException>().having(
              (error) => error.message,
              'message',
              contains('already exists'),
            ),
          ),
        );

        expect(existing.readAsStringSync(), 'existing');
        expect(runner.calls, isEmpty);
      },
    );

    test(
      'preserves unrelated properties while updating signing keys',
      () async {
        File(p.join(project.path, 'android', 'env.properties'))
          ..createSync(recursive: true)
          ..writeAsStringSync('PLAY_TRACK=internal\nKEY_ALIAS=old\n');
        File(p.join(project.path, 'android', 'key.properties'))
          ..createSync(recursive: true)
          ..writeAsStringSync('custom=value\nstoreFile=old.jks\n');

        await service.generate(projectPath: project.path);

        final envProperties = File(
          p.join(project.path, 'android', 'env.properties'),
        ).readAsStringSync();
        expect(envProperties, contains('PLAY_TRACK=internal'));
        expect(envProperties, contains('KEY_ALIAS=release'));
        expect(envProperties, contains('STORE_PASSWORD=fixed-secret-password'));

        final keyProperties = File(
          p.join(project.path, 'android', 'key.properties'),
        ).readAsStringSync();
        expect(keyProperties, contains('custom=value'));
        expect(
          keyProperties,
          contains('storeFile=../fastlane/keys/release.jks'),
        );
        expect(keyProperties, contains('keyPassword=fixed-secret-password'));
      },
    );

    test('force recreate replaces the existing JKS', () async {
      final existing =
          File(
              p.join(
                project.path,
                'android',
                'fastlane',
                'keys',
                'release.jks',
              ),
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('existing');

      await service.generate(projectPath: project.path, forceRecreate: true);

      expect(existing.readAsStringSync(), 'generated');
      expect(runner.calls, hasLength(1));
    });
  });
}

Directory _createFlutterAndroidProject(Directory parent) {
  final project = Directory(p.join(parent.path, 'demo'))..createSync();
  File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('name: demo\n');
  Directory(p.join(project.path, 'android')).createSync();
  return project;
}

String _argumentAfter(List<String> arguments, String key) {
  final index = arguments.indexOf(key);
  expect(index, greaterThanOrEqualTo(0));
  expect(index + 1, lessThan(arguments.length));
  return arguments[index + 1];
}

class _RecordingKeytoolRunner implements AndroidKeystoreCommandRunner {
  final calls = <_CommandCall>[];

  @override
  Future<AndroidKeystoreCommandResult> run({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    calls.add(
      _CommandCall(
        executable: executable,
        arguments: List.unmodifiable(arguments),
        workingDirectory: workingDirectory,
      ),
    );

    final keystorePath = _argumentAfter(arguments, '-keystore');
    File(keystorePath)
      ..createSync(recursive: true)
      ..writeAsStringSync('generated');
    return const AndroidKeystoreCommandResult(exitCode: 0);
  }
}

class _CommandCall {
  const _CommandCall({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
}
