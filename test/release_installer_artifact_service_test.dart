import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/services/release_installer_artifact_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('builds Windows release and packages installer in order', () async {
    final root = await _createInstallerProject(version: '0.1.0+1');
    addTearDown(() => root.delete(recursive: true));
    final executor = _FakeReleaseInstallerBuildExecutor();
    final service = ReleaseInstallerArtifactService(
      buildExecutor: executor,
      now: () => DateTime(2026, 8, 3),
      isWindows: () => true,
    );

    final artifact = await service.build(project: _project(root));

    expect(executor.calls, ['build', 'package:0.1.0']);
    expect(p.basename(artifact.file.path), 'AppReleaseCenter_Setup_v0.1.0.exe');
    expect(artifact.appDisplayName, appReleaseCenterDisplayName);
    expect(artifact.fullVersion, '0.1.0+1');
    expect(artifact.versionName, '0.1.0');
    expect(artifact.buildDate, DateTime(2026, 8, 3));
  });

  test('rejects non-Windows hosts before running commands', () async {
    final root = await _createInstallerProject(version: '0.1.0+1');
    addTearDown(() => root.delete(recursive: true));
    final executor = _FakeReleaseInstallerBuildExecutor();
    final service = ReleaseInstallerArtifactService(
      buildExecutor: executor,
      isWindows: () => false,
    );

    await expectLater(
      service.build(project: _project(root)),
      throwsA(
        isA<ReleaseInstallerArtifactException>().having(
          (error) => error.message,
          'message',
          contains('only supported on Windows'),
        ),
      ),
    );
    expect(executor.calls, isEmpty);
  });

  test('requires the selected project to be App Release Center', () async {
    final root = await _createInstallerProject(
      name: 'other_app',
      version: '0.1.0+1',
    );
    addTearDown(() => root.delete(recursive: true));
    final executor = _FakeReleaseInstallerBuildExecutor();
    final service = ReleaseInstallerArtifactService(
      buildExecutor: executor,
      isWindows: () => true,
    );

    await expectLater(
      service.build(project: _project(root)),
      throwsA(
        isA<ReleaseInstallerArtifactException>().having(
          (error) => error.message,
          'message',
          contains('App Release Center repo'),
        ),
      ),
    );
    expect(executor.calls, isEmpty);
  });

  test('requires installer script before running commands', () async {
    final root = await _createInstallerProject(
      version: '0.1.0+1',
      createScript: false,
    );
    addTearDown(() => root.delete(recursive: true));
    final executor = _FakeReleaseInstallerBuildExecutor();
    final service = ReleaseInstallerArtifactService(
      buildExecutor: executor,
      isWindows: () => true,
    );

    await expectLater(
      service.build(project: _project(root)),
      throwsA(
        isA<ReleaseInstallerArtifactException>().having(
          (error) => error.message,
          'message',
          contains('installer script'),
        ),
      ),
    );
    expect(executor.calls, isEmpty);
  });

  test('stops when Windows release build fails', () async {
    final root = await _createInstallerProject(version: '0.1.0+1');
    addTearDown(() => root.delete(recursive: true));
    final executor = _FakeReleaseInstallerBuildExecutor(buildExitCode: 1);
    final service = ReleaseInstallerArtifactService(
      buildExecutor: executor,
      isWindows: () => true,
    );

    await expectLater(
      service.build(project: _project(root)),
      throwsA(
        isA<ReleaseInstallerArtifactException>().having(
          (error) => error.message,
          'message',
          contains('exit code 1'),
        ),
      ),
    );
    expect(executor.calls, ['build']);
  });

  test('reports failed installer packaging command', () async {
    final root = await _createInstallerProject(version: '0.1.0+1');
    addTearDown(() => root.delete(recursive: true));
    final executor = _FakeReleaseInstallerBuildExecutor(packageExitCode: 2);
    final service = ReleaseInstallerArtifactService(
      buildExecutor: executor,
      isWindows: () => true,
    );

    await expectLater(
      service.build(project: _project(root)),
      throwsA(
        isA<ReleaseInstallerArtifactException>().having(
          (error) => error.message,
          'message',
          contains('exit code 2'),
        ),
      ),
    );
    expect(executor.calls, ['build', 'package:0.1.0']);
  });

  test('reports missing installer after successful package command', () async {
    final root = await _createInstallerProject(version: '0.1.0+1');
    addTearDown(() => root.delete(recursive: true));
    final executor = _FakeReleaseInstallerBuildExecutor(createOutput: false);
    final service = ReleaseInstallerArtifactService(
      buildExecutor: executor,
      isWindows: () => true,
    );

    await expectLater(
      service.build(project: _project(root)),
      throwsA(
        isA<ReleaseInstallerArtifactException>().having(
          (error) => error.message,
          'message',
          contains('was not found'),
        ),
      ),
    );
    expect(executor.calls, ['build', 'package:0.1.0']);
  });

  test('reports installer payload zip missing Flutter runtime files', () async {
    final root = await _createInstallerProject(version: '0.1.0+1');
    addTearDown(() => root.delete(recursive: true));
    final executor = _FakeReleaseInstallerBuildExecutor(
      missingArchiveFiles: {'data/flutter_assets/AssetManifest.bin'},
    );
    final service = ReleaseInstallerArtifactService(
      buildExecutor: executor,
      isWindows: () => true,
    );

    await expectLater(
      service.build(project: _project(root)),
      throwsA(
        isA<ReleaseInstallerArtifactException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('payload is missing Flutter runtime files'),
            contains('payload.zip:data/flutter_assets/AssetManifest.bin'),
          ),
        ),
      ),
    );
    expect(executor.calls, ['build', 'package:0.1.0']);
  });
}

Future<Directory> _createInstallerProject({
  String name = appReleaseCenterPubspecName,
  required String version,
  bool createScript = true,
}) async {
  final root = await Directory.systemTemp.createTemp('arc_installer_service_');
  await File(p.join(root.path, 'pubspec.yaml')).writeAsString(
    'name: $name\n'
    'version: $version\n',
  );
  if (createScript) {
    final scriptDirectory = await Directory(
      p.join(root.path, 'installer', 'windows'),
    ).create(recursive: true);
    await File(
      p.join(scriptDirectory.path, 'build_installer.ps1'),
    ).writeAsString('# test script\n');
  }
  return root;
}

ReleaseProject _project(Directory root) {
  return ReleaseProject(
    path: root.path,
    scripts: const [],
    fastlaneLanes: const [],
    hasFirebaseDeployTools: false,
    hasPlayReleaseTools: false,
    pubspecVersion: '0.1.0+1',
  );
}

class _FakeReleaseInstallerBuildExecutor
    implements ReleaseInstallerBuildExecutor {
  _FakeReleaseInstallerBuildExecutor({
    this.buildExitCode = 0,
    this.packageExitCode = 0,
    this.createOutput = true,
    this.missingArchiveFiles = const {},
  });

  final int buildExitCode;
  final int packageExitCode;
  final bool createOutput;
  final Set<String> missingArchiveFiles;
  final calls = <String>[];

  @override
  Future<int> buildWindowsRelease(ReleaseProject project) async {
    calls.add('build');
    return buildExitCode;
  }

  @override
  Future<int> packageWindowsInstaller({
    required ReleaseProject project,
    required String versionName,
  }) async {
    calls.add('package:$versionName');
    if (packageExitCode == 0 && createOutput) {
      final output = await Directory(
        p.join(project.path, 'build', 'installer'),
      ).create(recursive: true);
      await File(
        p.join(output.path, 'AppReleaseCenter_Setup_v$versionName.exe'),
      ).writeAsBytes([1, 2, 3]);
      await _writeInstallerPayload(project);
    }
    return packageExitCode;
  }

  Future<void> _writeInstallerPayload(ReleaseProject project) async {
    final buildRoot = Directory(p.join(project.path, 'build', 'installer'));
    final payloadRoot = Directory(p.join(buildRoot.path, 'payload'));
    final stageRoot = Directory(p.join(buildRoot.path, 'stage'));
    await payloadRoot.create(recursive: true);
    await stageRoot.create(recursive: true);

    final archive = Archive();
    for (final path in _requiredTestPayloadFiles) {
      final bytes = [1, 2, 3];
      final file = File(p.joinAll([payloadRoot.path, ...path.split('/')]));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      if (!missingArchiveFiles.contains(path)) {
        archive.add(ArchiveFile(path, bytes.length, bytes));
      }
    }

    await File(
      p.join(stageRoot.path, 'payload.zip'),
    ).writeAsBytes(ZipEncoder().encode(archive));
  }
}

const _requiredTestPayloadFiles = [
  'app_release_center.exe',
  'flutter_windows.dll',
  'data/app.so',
  'data/icudtl.dat',
  'data/flutter_assets/AssetManifest.bin',
  'data/flutter_assets/FontManifest.json',
  'data/flutter_assets/NativeAssetsManifest.json',
];
