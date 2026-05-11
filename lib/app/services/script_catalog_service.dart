import 'dart:io';

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
    if (!autoDirectory.existsSync()) {
      throw FileSystemException(
        'Project does not contain an auto folder.',
        root.path,
      );
    }

    final scripts =
        autoDirectory
            .listSync()
            .whereType<File>()
            .where((file) {
              final extension = p.extension(file.path).toLowerCase();
              return extension == '.sh' || extension == '.dart';
            })
            .map(
              (file) =>
                  ReleaseScript(path: file.path, kind: _scriptKind(file.path)),
            )
            .toList()
          ..sort(_sortScripts);

    final deployScript = File(p.join(autoDirectory.path, 'deploy.sh'));
    final hasPlayReleaseTools =
        _fileContains(deployScript, 'upload_to_chplay') ||
        File(p.join(autoDirectory.path, 'check_play_images.dart')).existsSync();

    return ReleaseProject(
      path: root.path,
      scripts: scripts,
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

  bool _fileContains(File file, String text) {
    if (!file.existsSync()) return false;
    return file.readAsStringSync().contains(text);
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
