import 'dart:io';

import 'package:app_release_center/app/models/app_store_version_snapshot.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

class AppStoreProjectInspection {
  const AppStoreProjectInspection({
    required this.path,
    required this.displayName,
    this.bundleId,
    this.localVersion,
  });

  final String path;
  final String displayName;
  final String? bundleId;
  final AppStoreLocalVersion? localVersion;
}

class AppStoreProjectInspectorService extends GetxService {
  Future<AppStoreProjectInspection> inspect(String projectPath) async {
    final normalizedPath = p.normalize(projectPath);
    return AppStoreProjectInspection(
      path: normalizedPath,
      displayName: p.basename(normalizedPath),
      bundleId: await detectBundleId(normalizedPath),
      localVersion: await readLocalVersion(normalizedPath),
    );
  }

  Future<AppStoreLocalVersion?> readLocalVersion(String projectPath) async {
    final pubspec = File(p.join(projectPath, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;

    return parsePubspecVersion(await pubspec.readAsString());
  }

  Future<String?> detectBundleId(String projectPath) async {
    final pbxproj = File(
      p.join(projectPath, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
    );
    if (!pbxproj.existsSync()) return null;

    return parseBundleId(await pbxproj.readAsString());
  }

  static AppStoreLocalVersion? parsePubspecVersion(String source) {
    final match = RegExp(
      r'^\s*version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(source);
    if (match == null) return null;

    return AppStoreLocalVersion.parse(match.group(1)!);
  }

  static String? parseBundleId(String source) {
    final bundleIds = parseBundleIds(source);
    return bundleIds.isEmpty ? null : bundleIds.first;
  }

  static List<String> parseBundleIds(
    String source, {
    bool ignoreTestBundleIds = true,
  }) {
    final runnerBundleIds = _parseRunnerBundleIds(
      source,
      ignoreTestBundleIds: ignoreTestBundleIds,
    );
    if (runnerBundleIds.isNotEmpty) return runnerBundleIds;

    return _parseBundleIdsFromSource(
      source,
      ignoreTestBundleIds: ignoreTestBundleIds,
    );
  }

  static List<String> _parseRunnerBundleIds(
    String source, {
    required bool ignoreTestBundleIds,
  }) {
    final configIds = <String>[];
    final configListPattern = RegExp(
      r'([A-Za-z0-9]+)\s*/\*\s*Build configuration list for PBXNativeTarget "Runner"\s*\*/\s*=\s*\{(.*?)\n\s*\};',
      multiLine: true,
      dotAll: true,
    );

    for (final listMatch in configListPattern.allMatches(source)) {
      final listBlock = listMatch.group(2) ?? '';
      final idPattern = RegExp(r'([A-Za-z0-9]+)\s*/\*[^*]+\*/');
      for (final idMatch in idPattern.allMatches(listBlock)) {
        final id = idMatch.group(1);
        if (id != null) configIds.add(id);
      }
    }

    final seen = <String>{};
    final bundleIds = <String>[];
    for (final id in configIds) {
      final configBlock = _extractPbxObjectBlock(source, id);
      if (configBlock == null) continue;
      for (final bundleId in _parseBundleIdsFromSource(
        configBlock,
        ignoreTestBundleIds: ignoreTestBundleIds,
      )) {
        if (seen.add(bundleId)) bundleIds.add(bundleId);
      }
    }

    return bundleIds;
  }

  static List<String> _parseBundleIdsFromSource(
    String source, {
    required bool ignoreTestBundleIds,
  }) {
    final pattern = RegExp(
      r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);',
      multiLine: true,
    );
    final seen = <String>{};
    final bundleIds = <String>[];

    for (final match in pattern.allMatches(source)) {
      final value = _normalizeBundleId(match.group(1) ?? '');
      if (value.isEmpty) continue;
      if (ignoreTestBundleIds && _looksLikeTestBundleId(value)) continue;
      if (seen.add(value)) bundleIds.add(value);
    }

    return bundleIds;
  }

  static String? _extractPbxObjectBlock(String source, String objectId) {
    final objectMatch = RegExp(
      '^\\s*${RegExp.escape(objectId)}\\s*/\\*[^*]*\\*/\\s*=\\s*\\{',
      multiLine: true,
    ).firstMatch(source);
    if (objectMatch == null) return null;

    final openBraceIndex = source.indexOf('{', objectMatch.start);
    if (openBraceIndex < 0) return null;

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

  static String _normalizeBundleId(String value) {
    return value
        .trim()
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll(r'\', '')
        .trim();
  }

  static bool _looksLikeTestBundleId(String bundleId) {
    final lower = bundleId.toLowerCase();
    if (lower == r'$(product_bundle_identifier)') return true;

    final segments = lower.split('.');
    final lastSegment = segments.isEmpty ? lower : segments.last;
    return lastSegment == 'test' ||
        lastSegment == 'tests' ||
        lastSegment.endsWith('test') ||
        lastSegment.endsWith('tests') ||
        lastSegment.contains('uitest');
  }
}
