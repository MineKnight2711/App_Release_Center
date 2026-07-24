import 'dart:io';

import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

abstract class ReleaseApkBuildExecutor {
  Future<int> buildReleaseApk(ReleaseProject project);
}

class RunnerReleaseApkBuildExecutor implements ReleaseApkBuildExecutor {
  RunnerReleaseApkBuildExecutor(this.runner);

  final ReleaseRunnerService runner;

  @override
  Future<int> buildReleaseApk(ReleaseProject project) {
    return runner.runCommand(
      workingDirectory: project.path,
      statusLabel: 'flutter build apk --release',
      activePath: 'deploy:build-release-apk',
      executable: runner.resolveFlutterExecutable(),
      arguments: const ['build', 'apk', '--release'],
      clearLog: false,
      projectName: project.name,
      allowDuringWorkflow: true,
    );
  }
}

class ReleaseApkArtifactService extends GetxService {
  ReleaseApkArtifactService({
    required ReleaseApkBuildExecutor buildExecutor,
    DateTime Function()? now,
  }) : _buildExecutor = buildExecutor,
       _now = now ?? DateTime.now;

  final ReleaseApkBuildExecutor _buildExecutor;
  final DateTime Function() _now;

  Future<ReleaseApkArtifact> buildAndRename({
    required ReleaseProject project,
    required String appDisplayName,
  }) async {
    _requiredPubspecVersion(project);

    final exitCode = await _buildExecutor.buildReleaseApk(project);
    if (exitCode != 0) {
      throw ReleaseApkArtifactException(
        'Release APK build failed with exit code $exitCode.',
      );
    }

    final outputDirectory = Directory(
      p.join(project.path, 'build', 'app', 'outputs', 'flutter-apk'),
    );
    final source = _findReleaseApk(outputDirectory);
    if (source == null) {
      throw ReleaseApkArtifactException(
        'Release APK was not found in ${outputDirectory.path}.',
      );
    }

    return _renameExistingApk(
      project: project,
      appDisplayName: appDisplayName,
      source: source,
      outputDirectory: outputDirectory,
    );
  }

  Future<ReleaseApkArtifact?> findExistingAndRename({
    required ReleaseProject project,
    required String appDisplayName,
  }) async {
    final outputDirectory = _releaseApkOutputDirectory(project);
    final source = _findReleaseApk(outputDirectory);
    if (source == null) return null;

    return _renameExistingApk(
      project: project,
      appDisplayName: appDisplayName,
      source: source,
      outputDirectory: outputDirectory,
    );
  }

  Directory _releaseApkOutputDirectory(ReleaseProject project) {
    return Directory(
      p.join(project.path, 'build', 'app', 'outputs', 'flutter-apk'),
    );
  }

  Future<ReleaseApkArtifact> _renameExistingApk({
    required ReleaseProject project,
    required String appDisplayName,
    required File source,
    required Directory outputDirectory,
  }) async {
    final version = _requiredPubspecVersion(project);

    final versionName = version.split('+').first.trim();
    final buildDate = _now();
    final fileName =
        '${_safeFileSegment(appDisplayName)}_v'
        '${_safeFileSegment(versionName)}_${_dateLabel(buildDate)}.apk';
    final target = File(p.join(outputDirectory.path, fileName));
    if (!p.equals(source.path, target.path)) {
      if (target.existsSync()) {
        await target.delete();
      }
      await source.rename(target.path);
    }

    return ReleaseApkArtifact(
      file: target,
      appDisplayName: appDisplayName.trim(),
      fullVersion: version,
      versionName: versionName,
      buildDate: buildDate,
    );
  }

  String _requiredPubspecVersion(ReleaseProject project) {
    final version = project.pubspecVersion?.trim();
    if (version == null || version.isEmpty) {
      throw const ReleaseApkArtifactException(
        'Project pubspec version is required to name the APK.',
      );
    }
    return version;
  }

  File? _findReleaseApk(Directory outputDirectory) {
    final standard = File(p.join(outputDirectory.path, 'app-release.apk'));
    if (standard.existsSync()) return standard;
    if (!outputDirectory.existsSync()) return null;

    final candidates =
        outputDirectory.listSync().whereType<File>().where((file) {
          final name = p.basename(file.path).toLowerCase();
          return name.endsWith('.apk') &&
              !name.contains('debug') &&
              !name.contains('profile');
        }).toList()..sort((a, b) {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        });
    return candidates.isEmpty ? null : candidates.first;
  }

  String _safeFileSegment(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^[._]+|[._]+$'), '');
    if (sanitized.isEmpty) {
      throw const ReleaseApkArtifactException(
        'App name and version must contain valid filename characters.',
      );
    }
    return sanitized;
  }

  String _dateLabel(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '${day}_${month}_${value.year}';
  }
}

class ReleaseApkArtifact {
  const ReleaseApkArtifact({
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

class ReleaseApkArtifactException implements Exception {
  const ReleaseApkArtifactException(this.message);

  final String message;

  @override
  String toString() => message;
}
