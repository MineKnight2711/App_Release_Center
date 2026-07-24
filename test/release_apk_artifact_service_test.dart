import 'dart:io';

import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/services/release_apk_artifact_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'builds and renames APK with app, version name, and build date',
    () async {
      final root = await Directory.systemTemp.createTemp('arc_apk_artifact_');
      addTearDown(() => root.delete(recursive: true));
      final executor = _FakeReleaseApkBuildExecutor();
      final service = ReleaseApkArtifactService(
        buildExecutor: executor,
        now: () => DateTime(2026, 7, 21),
      );

      final artifact = await service.buildAndRename(
        project: _project(root, version: '2.0.1+45'),
        appDisplayName: 'FizaHUB',
      );

      expect(executor.callCount, 1);
      expect(p.basename(artifact.file.path), 'FizaHUB_v2.0.1_21_07_2026.apk');
      expect(artifact.versionName, '2.0.1');
      expect(artifact.fullVersion, '2.0.1+45');
      expect(await artifact.file.readAsString(), 'apk-bytes');
      expect(
        File(
          p.join(
            root.path,
            'build',
            'app',
            'outputs',
            'flutter-apk',
            'app-release.apk',
          ),
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('sanitizes filename segments', () async {
    final root = await Directory.systemTemp.createTemp('arc_apk_artifact_');
    addTearDown(() => root.delete(recursive: true));
    final service = ReleaseApkArtifactService(
      buildExecutor: _FakeReleaseApkBuildExecutor(),
      now: () => DateTime(2026, 7, 21),
    );

    final artifact = await service.buildAndRename(
      project: _project(root, version: '2.0.1-beta+45'),
      appDisplayName: 'Fiza HUB: Mobile',
    );

    expect(
      p.basename(artifact.file.path),
      'Fiza_HUB_Mobile_v2.0.1-beta_21_07_2026.apk',
    );
  });

  test(
    'finds and renames an existing standard release APK without building',
    () async {
      final root = await Directory.systemTemp.createTemp('arc_apk_artifact_');
      addTearDown(() => root.delete(recursive: true));
      final executor = _FakeReleaseApkBuildExecutor();
      final service = ReleaseApkArtifactService(
        buildExecutor: executor,
        now: () => DateTime(2026, 7, 21),
      );
      final output = await Directory(
        p.join(root.path, 'build', 'app', 'outputs', 'flutter-apk'),
      ).create(recursive: true);
      await File(
        p.join(output.path, 'app-release.apk'),
      ).writeAsString('existing-apk');

      final artifact = await service.findExistingAndRename(
        project: _project(root, version: '2.0.1+45'),
        appDisplayName: 'FizaHUB',
      );

      expect(executor.callCount, 0);
      expect(artifact, isNotNull);
      expect(p.basename(artifact!.file.path), 'FizaHUB_v2.0.1_21_07_2026.apk');
      expect(await artifact.file.readAsString(), 'existing-apk');
    },
  );

  test('reuses an existing renamed APK without building', () async {
    final root = await Directory.systemTemp.createTemp('arc_apk_artifact_');
    addTearDown(() => root.delete(recursive: true));
    final executor = _FakeReleaseApkBuildExecutor();
    final service = ReleaseApkArtifactService(
      buildExecutor: executor,
      now: () => DateTime(2026, 7, 21),
    );
    final output = await Directory(
      p.join(root.path, 'build', 'app', 'outputs', 'flutter-apk'),
    ).create(recursive: true);
    final existing = File(p.join(output.path, 'FizaHUB_v2.0.1_21_07_2026.apk'));
    await existing.writeAsString('renamed-apk');

    final artifact = await service.findExistingAndRename(
      project: _project(root, version: '2.0.1+45'),
      appDisplayName: 'FizaHUB',
    );

    expect(executor.callCount, 0);
    expect(artifact, isNotNull);
    expect(artifact!.file.path, existing.path);
    expect(await artifact.file.readAsString(), 'renamed-apk');
  });

  test('returns null when no existing release APK is available', () async {
    final root = await Directory.systemTemp.createTemp('arc_apk_artifact_');
    addTearDown(() => root.delete(recursive: true));
    final executor = _FakeReleaseApkBuildExecutor();
    final service = ReleaseApkArtifactService(buildExecutor: executor);

    final artifact = await service.findExistingAndRename(
      project: _project(root, version: '2.0.1+45'),
      appDisplayName: 'FizaHUB',
    );

    expect(artifact, isNull);
    expect(executor.callCount, 0);
  });

  test('does not rename an APK when the build command fails', () async {
    final root = await Directory.systemTemp.createTemp('arc_apk_artifact_');
    addTearDown(() => root.delete(recursive: true));
    final service = ReleaseApkArtifactService(
      buildExecutor: _FakeReleaseApkBuildExecutor(exitCode: 1),
    );

    await expectLater(
      service.buildAndRename(
        project: _project(root, version: '2.0.1+45'),
        appDisplayName: 'FizaHUB',
      ),
      throwsA(
        isA<ReleaseApkArtifactException>().having(
          (error) => error.message,
          'message',
          contains('exit code 1'),
        ),
      ),
    );
  });

  test('requires a pubspec version before starting the build', () async {
    final root = await Directory.systemTemp.createTemp('arc_apk_artifact_');
    addTearDown(() => root.delete(recursive: true));
    final executor = _FakeReleaseApkBuildExecutor();
    final service = ReleaseApkArtifactService(buildExecutor: executor);

    await expectLater(
      service.buildAndRename(
        project: _project(root, version: null),
        appDisplayName: 'FizaHUB',
      ),
      throwsA(isA<ReleaseApkArtifactException>()),
    );
    expect(executor.callCount, 0);
  });
}

ReleaseProject _project(Directory root, {required String? version}) {
  return ReleaseProject(
    path: root.path,
    scripts: const [],
    fastlaneLanes: const [],
    hasFirebaseDeployTools: false,
    hasPlayReleaseTools: true,
    pubspecVersion: version,
  );
}

class _FakeReleaseApkBuildExecutor implements ReleaseApkBuildExecutor {
  _FakeReleaseApkBuildExecutor({this.exitCode = 0});

  final int exitCode;
  int callCount = 0;

  @override
  Future<int> buildReleaseApk(ReleaseProject project) async {
    callCount++;
    if (exitCode != 0) return exitCode;

    final output = await Directory(
      p.join(project.path, 'build', 'app', 'outputs', 'flutter-apk'),
    ).create(recursive: true);
    await File(
      p.join(output.path, 'app-release.apk'),
    ).writeAsString('apk-bytes');
    return 0;
  }
}
