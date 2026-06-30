import 'dart:io';

import 'package:app_release_center/app/models/release_fastlane_lane.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/models/release_script.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

class ScriptCatalogService extends GetxService {
  Future<ReleaseProject> inspect(String projectPath) async {
    final root = Directory(p.normalize(projectPath));
    if (!root.existsSync()) {
      throw FileSystemException('Project directory does not exist.', root.path);
    }

    final autoDirectory = Directory(p.join(root.path, 'auto'));
    final scripts = autoDirectory.existsSync()
        ? autoDirectory
              .listSync()
              .whereType<File>()
              .where((file) {
                final extension = p.extension(file.path).toLowerCase();
                return extension == '.sh' || extension == '.dart';
              })
              .map(
                (file) => ReleaseScript(
                  path: file.path,
                  kind: _scriptKind(file.path),
                ),
              )
              .toList()
        : <ReleaseScript>[];
    scripts.sort(_sortScripts);

    final deployScript = File(p.join(autoDirectory.path, 'deploy.sh'));
    final deployScriptSource = _readFile(deployScript);
    final executableDeployScript = _stripCommentOnlyLines(deployScriptSource);
    final hasFirebaseDeployTools =
        executableDeployScript.contains('deploy_firebase_dis') ||
        executableDeployScript.contains('firebase appdistribution');
    final hasPlayReleaseTools =
        executableDeployScript.contains('upload_to_chplay') ||
        File(p.join(autoDirectory.path, 'check_play_images.dart')).existsSync();

    return ReleaseProject(
      path: root.path,
      scripts: scripts,
      fastlaneLanes: _readFastlaneLanes(root.path),
      hasFirebaseDeployTools: hasFirebaseDeployTools,
      hasPlayReleaseTools: hasPlayReleaseTools,
      pubspecVersion: _readPubspecVersion(root.path),
    );
  }

  ReleaseScriptKind _scriptKind(String path) {
    return switch (p.basename(path)) {
      'release.sh' => ReleaseScriptKind.release,
      'control_ver_code.sh' => ReleaseScriptKind.versionCode,
      'control_ver_name.sh' => ReleaseScriptKind.versionName,
      'commit.sh' => ReleaseScriptKind.commit,
      'merge.sh' => ReleaseScriptKind.merge,
      'deploy.sh' => ReleaseScriptKind.deploy,
      'check_play_images.dart' => ReleaseScriptKind.imageValidation,
      _ when p.extension(path).toLowerCase() == '.dart' =>
        ReleaseScriptKind.dartTool,
      _ => ReleaseScriptKind.shell,
    };
  }

  int _sortScripts(ReleaseScript a, ReleaseScript b) {
    final order = <ReleaseScriptKind, int>{
      ReleaseScriptKind.release: 0,
      ReleaseScriptKind.versionCode: 1,
      ReleaseScriptKind.versionName: 2,
      ReleaseScriptKind.commit: 3,
      ReleaseScriptKind.merge: 4,
      ReleaseScriptKind.deploy: 5,
      ReleaseScriptKind.imageValidation: 6,
      ReleaseScriptKind.shell: 7,
      ReleaseScriptKind.dartTool: 8,
    };

    final byKind = (order[a.kind] ?? 99).compareTo(order[b.kind] ?? 99);
    if (byKind != 0) return byKind;
    return a.fileName.compareTo(b.fileName);
  }

  String _readFile(File file) {
    if (!file.existsSync()) return '';
    return file.readAsStringSync();
  }

  String _stripCommentOnlyLines(String source) {
    return source
        .split('\n')
        .map((line) => line.trimLeft())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .join('\n');
  }

  List<ReleaseFastlaneLane> _readFastlaneLanes(String projectPath) {
    final fastfile = File(
      p.join(projectPath, 'android', 'fastlane', 'Fastfile'),
    );
    if (!fastfile.existsSync()) return const [];

    final lanes = <ReleaseFastlaneLane>[];
    final seen = <String>{};
    final lanePattern = RegExp(r'^\s*lane\s+:([A-Za-z0-9_]+)\s+do\b');
    final descPattern = RegExp(r'''^\s*desc\s+["'](.+)["']\s*$''');
    final platformPattern = RegExp(r'^\s*platform\s+:([A-Za-z0-9_]+)\s+do\b');
    final defaultPlatformPattern = RegExp(
      r'^\s*default_platform\(\s*:([A-Za-z0-9_]+)\s*\)',
    );

    String? currentPlatform;
    String? defaultPlatform;
    String? pendingDescription;

    for (final line in fastfile.readAsLinesSync()) {
      final defaultMatch = defaultPlatformPattern.firstMatch(line);
      if (defaultMatch != null) {
        defaultPlatform = defaultMatch.group(1);
        continue;
      }

      final platformMatch = platformPattern.firstMatch(line);
      if (platformMatch != null) {
        currentPlatform = platformMatch.group(1);
        continue;
      }

      final descMatch = descPattern.firstMatch(line);
      if (descMatch != null) {
        pendingDescription = descMatch.group(1);
        continue;
      }

      final laneMatch = lanePattern.firstMatch(line);
      if (laneMatch == null) continue;

      final name = laneMatch.group(1)!;
      final platform = currentPlatform ?? defaultPlatform;
      final key = '${platform ?? 'default'}:$name';
      if (!seen.add(key)) {
        pendingDescription = null;
        continue;
      }

      lanes.add(
        ReleaseFastlaneLane(
          name: name,
          platform: platform,
          description: pendingDescription,
        ),
      );
      pendingDescription = null;
    }

    lanes.sort((a, b) => a.name.compareTo(b.name));
    return lanes;
  }

  String? _readPubspecVersion(String projectPath) {
    final pubspec = File(p.join(projectPath, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;

    for (final line in pubspec.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.startsWith('version:')) {
        return trimmed.substring('version:'.length).trim();
      }
    }

    return null;
  }
}
