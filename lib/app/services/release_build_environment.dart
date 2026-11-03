import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Only Ký Số CCCD uses compiled JSON configuration. Other projects keep
/// loading their root .env through their existing dotenv integration.
abstract final class ReleaseBuildEnvironment {
  static String? jsonFileFor(String projectPath) {
    final pubspec = File(p.join(projectPath, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    final config = loadYaml(pubspec.readAsStringSync());
    if (config is! YamlMap || config['name'] != 'kysocccd') return null;

    // Support the requested env/env.json and the app's existing prod.json.
    if (File(p.join(projectPath, 'env', 'env.json')).existsSync()) {
      return 'env/env.json';
    }
    return 'env/prod.json';
  }

  static List<String> flutterArguments(String projectPath) {
    final file = jsonFileFor(projectPath);
    if (file == null) return const [];
    if (!File(p.join(projectPath, file)).existsSync()) {
      throw FileSystemException('Thiếu file cấu hình ký số CCCD.', file);
    }
    return ['--dart-define-from-file=$file'];
  }
}
