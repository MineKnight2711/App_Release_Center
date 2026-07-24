import 'dart:io';

import 'package:app_release_center/app/models/ch_play_version_snapshot.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

class ChPlayProjectInspection {
  const ChPlayProjectInspection({
    required this.path,
    required this.displayName,
    this.applicationId,
    this.localVersion,
  });

  final String path;
  final String displayName;
  final String? applicationId;
  final ChPlayLocalVersion? localVersion;
}

class ChPlayProjectInspectorService extends GetxService {
  Future<ChPlayProjectInspection> inspect(String projectPath) async {
    final normalizedPath = p.normalize(projectPath);
    return ChPlayProjectInspection(
      path: normalizedPath,
      displayName: p.basename(normalizedPath),
      applicationId: await detectApplicationId(normalizedPath),
      localVersion: await readLocalVersion(normalizedPath),
    );
  }

  Future<ChPlayLocalVersion?> readLocalVersion(String projectPath) async {
    final pubspec = File(p.join(projectPath, 'pubspec.yaml'));
    try {
      if (!pubspec.existsSync()) return null;

      return parsePubspecVersion(await pubspec.readAsString());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<String?> detectApplicationId(String projectPath) async {
    final candidates = [
      File(p.join(projectPath, 'android', 'app', 'build.gradle')),
      File(p.join(projectPath, 'android', 'app', 'build.gradle.kts')),
    ];

    for (final file in candidates) {
      try {
        if (!file.existsSync()) continue;
        final parsed = parseApplicationId(await file.readAsString());
        if (parsed != null) return parsed;
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }

    return null;
  }

  static ChPlayLocalVersion? parsePubspecVersion(String source) {
    final match = RegExp(
      r'^\s*version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(source);
    if (match == null) return null;

    return ChPlayLocalVersion.parse(match.group(1)!);
  }

  static String? parseApplicationId(String source) {
    final defaultConfig = _extractBlock(source, 'defaultConfig');
    final fromDefaultConfig = _parseApplicationIdFromSource(defaultConfig);
    if (fromDefaultConfig != null) return fromDefaultConfig;

    return _parseApplicationIdFromSource(source) ??
        _parseNamespaceFromSource(source);
  }

  static String? _parseApplicationIdFromSource(String source) {
    final patterns = [
      RegExp(r'''^\s*applicationId\s*=\s*["']([^"']+)["']''', multiLine: true),
      RegExp(r'''^\s*applicationId\s+["']([^"']+)["']''', multiLine: true),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(source);
      if (match != null) return match.group(1)?.trim();
    }

    return null;
  }

  static String? _parseNamespaceFromSource(String source) {
    final match = RegExp(
      r'''^\s*namespace\s*=\s*["']([^"']+)["']''',
      multiLine: true,
    ).firstMatch(source);
    return match?.group(1)?.trim();
  }

  static String _extractBlock(String source, String blockName) {
    final blockMatch = RegExp('\\b$blockName\\s*\\{').firstMatch(source);
    if (blockMatch == null) return source;

    final openBraceIndex = source.indexOf('{', blockMatch.start);
    if (openBraceIndex < 0) return source;

    var depth = 0;
    for (var i = openBraceIndex; i < source.length; i++) {
      final char = source[i];
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return source.substring(openBraceIndex + 1, i);
        }
      }
    }

    return source.substring(openBraceIndex + 1);
  }
}
