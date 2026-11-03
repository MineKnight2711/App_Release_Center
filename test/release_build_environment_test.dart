import 'dart:io';

import 'package:app_management_center/app/models/release_project.dart';
import 'package:app_management_center/app/services/release_apk_artifact_service.dart';
import 'package:app_management_center/app/services/release_build_environment.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('amc release env ');
  });
  tearDown(() => root.deleteSync(recursive: true));

  void write(String path, String content) {
    File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  test('other packages keep root .env even when JSON files exist', () {
    write('pubspec.yaml', 'name: another_app\n');
    write('.env', 'API_URL=https://example.com\n');
    write('env/env.json', '{}');
    write('env/prod.json', '{}');

    expect(ReleaseBuildEnvironment.jsonFileFor(root.path), isNull);
    expect(ReleaseBuildEnvironment.flutterArguments(root.path), isEmpty);
  });

  test('CCCD is identified by package even in a renamed checkout', () {
    write('pubspec.yaml', 'name: kysocccd\n');
    write('env/prod.json', '{}');

    expect(ReleaseBuildEnvironment.flutterArguments(root.path), [
      '--dart-define-from-file=env/prod.json',
    ]);
  });

  test('CCCD prefers env/env.json when present', () {
    write('pubspec.yaml', 'name: kysocccd\n');
    write('env/env.json', '{}');
    write('env/prod.json', '{}');
    write('.env', 'API_URL=https://example.com\n');

    expect(ReleaseBuildEnvironment.flutterArguments(root.path), [
      '--dart-define-from-file=env/env.json',
    ]);
  });

  test('CCCD never falls back to .env when its JSON is missing', () {
    write('pubspec.yaml', 'name: kysocccd\n');
    write('.env', 'API_URL=https://example.com\n');

    expect(
      () => ReleaseBuildEnvironment.flutterArguments(root.path),
      throwsA(isA<FileSystemException>()),
    );
  });

  for (final packageName in ['kysocccd', 'another_app']) {
    test('release APK command uses the environment for $packageName', () async {
      write('pubspec.yaml', 'name: $packageName\n');
      write('env/env.json', '{}');
      final runner = _RecordingRunner();
      final project = ReleaseProject(
        path: root.path,
        scripts: const [],
        fastlaneLanes: const [],
        hasLegacyDistributionPrompt: false,
        hasPlayReleaseTools: true,
      );

      await RunnerReleaseApkBuildExecutor(runner).buildReleaseApk(project);

      expect(runner.directory, root.path);
      expect(runner.arguments, [
        'build',
        'apk',
        '--release',
        if (packageName == 'kysocccd') '--dart-define-from-file=env/env.json',
      ]);
    });
  }
}

class _RecordingRunner extends ReleaseRunnerService {
  List<String>? arguments;
  String? directory;

  @override
  String resolveFlutterExecutable() => 'flutter';

  @override
  Future<int> runCommand({
    required String workingDirectory,
    required String statusLabel,
    required String activePath,
    required String executable,
    List<String> arguments = const [],
    List<String>? displayArguments,
    Map<String, String> environment = const {},
    bool clearLog = false,
    String? projectName,
    bool allowDuringWorkflow = false,
    bool trackWorkflowStep = true,
  }) async {
    directory = workingDirectory;
    this.arguments = arguments;
    return 0;
  }
}
