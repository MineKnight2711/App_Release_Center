import 'dart:convert';

import 'package:app_release_center/app/models/app_store_project.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class ProjectStoreService extends GetxService {
  static const _lastProjectKey = 'last_project_path';
  static const _recentProjectsKey = 'recent_project_paths';
  static const _chPlayProjectsKey = 'ch_play_projects';
  static const _appStoreProjectsKey = 'app_store_projects';

  late final SharedPreferences _preferences;

  Future<ProjectStoreService> init() async {
    _preferences = await SharedPreferences.getInstance();
    return this;
  }

  String? get lastProjectPath => _preferences.getString(_lastProjectKey);

  List<String> get recentProjectPaths {
    return _preferences.getStringList(_recentProjectsKey) ?? const [];
  }

  List<ChPlayProject> get chPlayProjects {
    final entries = _preferences.getStringList(_chPlayProjectsKey) ?? const [];
    final projects = <ChPlayProject>[];

    for (final entry in entries) {
      try {
        final json = jsonDecode(entry);
        if (json is Map<String, Object?>) {
          final project = ChPlayProject.fromJson(json);
          if (project.id.isNotEmpty && project.path.isNotEmpty) {
            projects.add(project);
          }
        }
      } catch (_) {
        // Ignore invalid legacy entries and keep loading the rest.
      }
    }

    return projects;
  }

  List<AppStoreProject> get appStoreProjects {
    final entries =
        _preferences.getStringList(_appStoreProjectsKey) ?? const [];
    final projects = <AppStoreProject>[];

    for (final entry in entries) {
      try {
        final json = jsonDecode(entry);
        if (json is Map<String, Object?>) {
          final project = AppStoreProject.fromJson(json);
          if (project.id.isNotEmpty && project.path.isNotEmpty) {
            projects.add(project);
          }
        }
      } catch (_) {
        // Ignore invalid entries and keep loading the rest.
      }
    }

    return projects;
  }

  Future<void> saveProjectPath(String path) async {
    final normalizedPath = p.normalize(path);
    final lowerPath = normalizedPath.toLowerCase();
    final paths = <String>[
      normalizedPath,
      ...recentProjectPaths.where(
        (existingPath) => existingPath.toLowerCase() != lowerPath,
      ),
    ].take(8).toList();

    await _preferences.setString(_lastProjectKey, normalizedPath);
    await _preferences.setStringList(_recentProjectsKey, paths);
  }

  Future<void> saveChPlayProjects(List<ChPlayProject> projects) async {
    final entries = projects
        .map((project) => jsonEncode(project.toJson()))
        .toList();
    await _preferences.setStringList(_chPlayProjectsKey, entries);
  }

  Future<void> saveAppStoreProjects(List<AppStoreProject> projects) async {
    final entries = projects
        .map((project) => jsonEncode(project.toJson()))
        .toList();
    await _preferences.setStringList(_appStoreProjectsKey, entries);
  }
}
