import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class ProjectStoreService extends GetxService {
  static const _lastProjectKey = 'last_project_path';
  static const _recentProjectsKey = 'recent_project_paths';

  late final SharedPreferences _preferences;

  Future<ProjectStoreService> init() async {
    _preferences = await SharedPreferences.getInstance();
    return this;
  }

  String? get lastProjectPath => _preferences.getString(_lastProjectKey);

  List<String> get recentProjectPaths {
    return _preferences.getStringList(_recentProjectsKey) ?? const [];
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
}
