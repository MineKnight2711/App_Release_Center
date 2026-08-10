import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

abstract class ReleaseInstallerBuildExecutor {
  Future<int> buildWindowsRelease(ReleaseProject project);

  Future<int> packageWindowsInstaller({
    required ReleaseProject project,
    required String versionName,
  });
}

class RunnerReleaseInstallerBuildExecutor
    implements ReleaseInstallerBuildExecutor {
  RunnerReleaseInstallerBuildExecutor(this.runner);

  final ReleaseRunnerService runner;

  @override
  Future<int> buildWindowsRelease(ReleaseProject project) {
    return runner.runCommand(
      workingDirectory: project.path,
      statusLabel: 'flutter build windows --release',
      activePath: 'installer:build-windows-release',
      executable: runner.resolveFlutterExecutable(),
      arguments: const ['build', 'windows', '--release'],
      clearLog: false,
      projectName: project.name,
      allowDuringWorkflow: true,
    );
  }

  @override
  Future<int> packageWindowsInstaller({
    required ReleaseProject project,
    required String versionName,
  }) {
    return runner.runCommand(
      workingDirectory: project.path,
      statusLabel: 'Build Windows installer',
      activePath: 'installer:package-windows-installer',
      executable: 'powershell.exe',
      arguments: [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        p.join(project.path, 'installer', 'windows', 'build_installer.ps1'),
        '-Version',
        versionName,
      ],
      displayArguments: [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        p.join('installer', 'windows', 'build_installer.ps1'),
        '-Version',
        versionName,
      ],
      clearLog: false,
      projectName: project.name,
      allowDuringWorkflow: true,
    );
  }
}

class ReleaseInstallerArtifactService extends GetxService {
  ReleaseInstallerArtifactService({
    required ReleaseInstallerBuildExecutor buildExecutor,
    DateTime Function()? now,
    bool Function()? isWindows,
  }) : _buildExecutor = buildExecutor,
       _now = now ?? DateTime.now,
       _isWindows = isWindows ?? (() => Platform.isWindows);

  final ReleaseInstallerBuildExecutor _buildExecutor;
  final DateTime Function() _now;
  final bool Function() _isWindows;

  bool get isWindowsSupported => _isWindows();

  bool isAppReleaseCenterProject(ReleaseProject project) {
    try {
      return _readPubspecMetadata(project).name == appReleaseCenterPubspecName;
    } catch (_) {
      return false;
    }
  }

  Future<ReleaseInstallerArtifact> build({
    required ReleaseProject project,
  }) async {
    final metadata = _validate(project);
    final versionName = _versionName(metadata.version);
    final outputFile = _installerOutputFile(project, versionName);

    final buildExitCode = await _buildExecutor.buildWindowsRelease(project);
    if (buildExitCode != 0) {
      throw ReleaseInstallerArtifactException(
        'Windows release build failed with exit code $buildExitCode.',
      );
    }

    final packageExitCode = await _buildExecutor.packageWindowsInstaller(
      project: project,
      versionName: versionName,
    );
    if (packageExitCode != 0) {
      throw ReleaseInstallerArtifactException(
        'Windows installer packaging failed with exit code $packageExitCode.',
      );
    }

    if (!outputFile.existsSync()) {
      throw ReleaseInstallerArtifactException(
        'Windows installer was not found at ${outputFile.path}.',
      );
    }
    _validateInstallerPayload(project);

    return ReleaseInstallerArtifact(
      file: outputFile,
      appDisplayName: appReleaseCenterDisplayName,
      fullVersion: metadata.version,
      versionName: versionName,
      buildDate: _now(),
    );
  }

  _PubspecMetadata _validate(ReleaseProject project) {
    if (!_isWindows()) {
      throw const ReleaseInstallerArtifactException(
        'Windows installer builds are only supported on Windows.',
      );
    }

    final metadata = _readPubspecMetadata(project);
    if (metadata.name != appReleaseCenterPubspecName) {
      throw ReleaseInstallerArtifactException(
        'Selected project must be the App Release Center repo '
        '($appReleaseCenterPubspecName).',
      );
    }

    final script = _installerScript(project);
    if (!script.existsSync()) {
      throw ReleaseInstallerArtifactException(
        'Windows installer script was not found at ${script.path}.',
      );
    }

    _versionName(metadata.version);
    return metadata;
  }

  _PubspecMetadata _readPubspecMetadata(ReleaseProject project) {
    final pubspec = File(p.join(project.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw ReleaseInstallerArtifactException(
        'Selected project does not contain pubspec.yaml.',
      );
    }

    String? name;
    String? version;
    for (final line in pubspec.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.startsWith('name:')) {
        name = trimmed.substring('name:'.length).trim();
      } else if (trimmed.startsWith('version:')) {
        version = trimmed.substring('version:'.length).trim();
      }
    }

    final normalizedName = name?.trim() ?? '';
    if (normalizedName.isEmpty) {
      throw const ReleaseInstallerArtifactException(
        'Project pubspec name is required.',
      );
    }

    final normalizedVersion = version?.trim() ?? '';
    if (normalizedVersion.isEmpty) {
      throw const ReleaseInstallerArtifactException(
        'Project pubspec version is required to name the installer.',
      );
    }

    return _PubspecMetadata(name: normalizedName, version: normalizedVersion);
  }

  File _installerScript(ReleaseProject project) {
    return File(
      p.join(project.path, 'installer', 'windows', 'build_installer.ps1'),
    );
  }

  File _installerOutputFile(ReleaseProject project, String versionName) {
    return File(
      p.join(
        project.path,
        'build',
        'installer',
        'AppReleaseCenter_Setup_v${_safeVersion(versionName)}.exe',
      ),
    );
  }

  void _validateInstallerPayload(ReleaseProject project) {
    final payloadDirectory = Directory(
      p.join(project.path, 'build', 'installer', 'payload'),
    );
    final missingFiles = <String>[];
    for (final path in _requiredInstallerPayloadFiles) {
      final file = File(p.joinAll([payloadDirectory.path, ...path.split('/')]));
      if (!file.existsSync()) {
        missingFiles.add(path);
      }
    }

    final payloadArchive = File(
      p.join(project.path, 'build', 'installer', 'stage', 'payload.zip'),
    );
    if (!payloadArchive.existsSync()) {
      missingFiles.add('stage/payload.zip');
    } else {
      try {
        final archive = ZipDecoder().decodeBytes(
          payloadArchive.readAsBytesSync(),
        );
        final archiveFiles = archive.files
            .map((file) => file.name.replaceAll(r'\', '/'))
            .toSet();
        for (final path in _requiredInstallerPayloadFiles) {
          if (!archiveFiles.contains(path)) {
            missingFiles.add('payload.zip:$path');
          }
        }
      } catch (error) {
        throw ReleaseInstallerArtifactException(
          'Windows installer payload.zip could not be inspected: $error',
        );
      }
    }

    if (missingFiles.isNotEmpty) {
      throw ReleaseInstallerArtifactException(
        'Windows installer payload is missing Flutter runtime files: '
        '${missingFiles.join(', ')}.',
      );
    }
  }

  String _versionName(String fullVersion) {
    final versionName = fullVersion.split('+').first.trim();
    if (versionName.isEmpty) {
      throw const ReleaseInstallerArtifactException(
        'Project pubspec version name is required to name the installer.',
      );
    }
    return versionName;
  }

  String _safeVersion(String value) {
    return value.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
  }
}

class ReleaseInstallerArtifact {
  const ReleaseInstallerArtifact({
    required this.file,
    required this.appDisplayName,
    required this.fullVersion,
    required this.versionName,
    required this.buildDate,
  });

  final File file;
  final String appDisplayName;
  final String fullVersion;
  final String versionName;
  final DateTime buildDate;
}

class ReleaseInstallerArtifactException implements Exception {
  const ReleaseInstallerArtifactException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _PubspecMetadata {
  const _PubspecMetadata({required this.name, required this.version});

  final String name;
  final String version;
}

const appReleaseCenterPubspecName = 'app_release_center';
const appReleaseCenterDisplayName = 'App Release Center';
const _requiredInstallerPayloadFiles = [
  'app_release_center.exe',
  'flutter_windows.dll',
  'data/app.so',
  'data/icudtl.dat',
  'data/flutter_assets/AssetManifest.bin',
  'data/flutter_assets/FontManifest.json',
  'data/flutter_assets/NativeAssetsManifest.json',
];
