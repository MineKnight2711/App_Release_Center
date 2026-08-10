import 'dart:convert';
import 'dart:io';

import 'package:app_release_center/app/models/resource_collection.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

class ResourceDiscoveryService extends GetxService {
  Future<ResourceDiscoveryResult> scan({
    required String sourceRoot,
    required ResourceCollectionPreset preset,
    required Set<ResourceTargetKind> customKinds,
  }) async {
    final root = Directory(p.normalize(sourceRoot));
    if (!root.existsSync()) {
      throw FileSystemException(
        'Resource source directory does not exist.',
        root.path,
      );
    }

    final activeKinds = _activeKinds(preset, customKinds);
    final findings = <ResourceFinding>[];
    final excludedPaths = <String>[];

    for (final file in _walkFiles(root, excludedPaths)) {
      final relativePath = _safeRelativePath(file.path, root.path);
      if (relativePath == null) continue;

      final kind = _classify(relativePath);
      if (kind == null || !activeKinds.contains(kind)) continue;

      final stat = await file.stat();
      final probe = await _probeFile(file, kind);
      findings.add(
        ResourceFinding(
          sourcePath: p.normalize(file.path),
          relativePath: relativePath,
          kind: kind,
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
          detectedKeyNames: probe.keyNames,
          maskedPreview: probe.maskedPreview,
          isBinary: probe.isBinary,
        ),
      );
    }

    findings.sort((a, b) {
      final byKind = a.kind.index.compareTo(b.kind.index);
      if (byKind != 0) return byKind;
      return a.relativePath.compareTo(b.relativePath);
    });

    return ResourceDiscoveryResult(
      sourceRoot: root.path,
      findings: findings,
      excludedPaths: excludedPaths..sort(),
    );
  }

  Iterable<File> _walkFiles(Directory root, List<String> excludedPaths) sync* {
    final pending = <Directory>[root];
    while (pending.isNotEmpty) {
      final directory = pending.removeLast();
      List<FileSystemEntity> children;
      try {
        children = directory.listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }

      for (final child in children) {
        if (child is Directory) {
          if (_isExcludedDirectory(child)) {
            excludedPaths.add(_relativeOrName(child.path, root.path));
            continue;
          }
          pending.add(child);
        } else if (child is File) {
          yield child;
        }
      }
    }
  }

  bool _isExcludedDirectory(Directory directory) {
    return _excludedDirectoryNames.contains(
      p.basename(directory.path).toLowerCase(),
    );
  }

  Set<ResourceTargetKind> _activeKinds(
    ResourceCollectionPreset preset,
    Set<ResourceTargetKind> customKinds,
  ) {
    return switch (preset) {
      ResourceCollectionPreset.allRecommended => resourceRecommendedTargetKinds,
      ResourceCollectionPreset.envOnly => {ResourceTargetKind.envFile},
      ResourceCollectionPreset.custom => customKinds,
    };
  }

  ResourceTargetKind? _classify(String relativePath) {
    final normalized = _toPosix(relativePath);
    final lower = normalized.toLowerCase();
    final basename = p.posix.basename(lower);

    if (_isIgnoredCandidateName(basename)) return null;

    if (lower == 'android/app/google-services.json' ||
        basename == 'googleservice-info.plist'.toLowerCase() ||
        basename == 'firebase_app_id_file.json') {
      return ResourceTargetKind.firebaseConfig;
    }

    if (_isPropertiesPath(lower, basename)) {
      return ResourceTargetKind.properties;
    }

    if (_isEnvName(basename)) {
      return ResourceTargetKind.envFile;
    }

    if (_isServiceAccountPath(lower, basename)) {
      return ResourceTargetKind.fastlaneServiceAccount;
    }

    if (basename.endsWith('.jks') || basename.endsWith('.keystore')) {
      return ResourceTargetKind.signingKey;
    }

    if (basename.endsWith('.p8') || basename.endsWith('.pem')) {
      return ResourceTargetKind.appStoreKey;
    }

    return null;
  }

  bool _isEnvName(String basename) {
    return basename == '.env' ||
        basename.startsWith('.env.') ||
        basename == 'env' ||
        basename.startsWith('env.');
  }

  bool _isPropertiesPath(String lowerPath, String basename) {
    if (basename == 'gradle-wrapper.properties' ||
        basename == 'local.properties') {
      return false;
    }
    return lowerPath == 'android/env.properties' ||
        lowerPath == 'android/key.properties' ||
        (lowerPath.startsWith('android/fastlane/') &&
            lowerPath.endsWith('.properties'));
  }

  bool _isServiceAccountPath(String lowerPath, String basename) {
    return basename == 'fastlane-service-account.json' ||
        basename == 'google-play-key.json' ||
        (basename.startsWith('service-account') &&
            basename.endsWith('.json')) ||
        (lowerPath.startsWith('android/fastlane/') &&
            lowerPath.endsWith('.json'));
  }

  bool _isIgnoredCandidateName(String basename) {
    return basename == '.env.example' ||
        basename == '.env.sample' ||
        basename == '.env.template' ||
        basename == 'env.example' ||
        basename == 'env.sample' ||
        basename == 'env.template';
  }

  Future<_ResourceProbe> _probeFile(File file, ResourceTargetKind kind) async {
    final bytes = await _readProbeBytes(file);
    final binary = _isBinaryKind(kind) || bytes.contains(0);
    if (binary) {
      return const _ResourceProbe(isBinary: true);
    }

    final source = _decodeText(bytes);
    if (source == null || source.trim().isEmpty) {
      return const _ResourceProbe();
    }

    return switch (kind) {
      ResourceTargetKind.envFile ||
      ResourceTargetKind.properties => _probeKeyValueSource(source),
      ResourceTargetKind.fastlaneServiceAccount ||
      ResourceTargetKind.firebaseConfig => _probeStructuredSource(source),
      ResourceTargetKind.signingKey ||
      ResourceTargetKind.appStoreKey => _probeKeyValueSource(source),
    };
  }

  Future<List<int>> _readProbeBytes(File file) async {
    final length = await file.length();
    final limit = length > _maxProbeBytes ? _maxProbeBytes : length;
    final handle = await file.open();
    try {
      return await handle.read(limit);
    } finally {
      await handle.close();
    }
  }

  bool _isBinaryKind(ResourceTargetKind kind) {
    return kind == ResourceTargetKind.signingKey;
  }

  String? _decodeText(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      try {
        return latin1.decode(bytes);
      } on FormatException {
        return null;
      }
    }
  }

  _ResourceProbe _probeKeyValueSource(String source) {
    final keyNames = <String>{};
    final maskedPreview = <String>[];
    final keyValuePattern = RegExp(
      r'''^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_.-]*)\s*[:=]\s*(.*)\s*$''',
    );

    for (final line in const LineSplitter().convert(source)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith('!') ||
          trimmed.startsWith('//')) {
        continue;
      }

      final match = keyValuePattern.firstMatch(line);
      if (match == null) continue;
      final key = match.group(1)!.trim();
      keyNames.add(key);
      if (maskedPreview.length < _maxPreviewLines) {
        maskedPreview.add('$key=${_maskValue(match.group(2) ?? '')}');
      }
    }

    return _ResourceProbe(
      keyNames: keyNames.take(_maxKeyNames).toList(),
      maskedPreview: maskedPreview,
    );
  }

  _ResourceProbe _probeStructuredSource(String source) {
    final keyNames = <String>{};
    final maskedPreview = <String>[];

    try {
      final decoded = jsonDecode(source);
      _collectJsonKeys(decoded, keyNames, maskedPreview);
    } on FormatException {
      final plistKeyPattern = RegExp(r'<key>([^<]+)</key>');
      for (final match in plistKeyPattern.allMatches(source)) {
        final key = match.group(1)?.trim();
        if (key == null || key.isEmpty) continue;
        keyNames.add(key);
      }
    }

    return _ResourceProbe(
      keyNames: keyNames.take(_maxKeyNames).toList(),
      maskedPreview: maskedPreview.take(_maxPreviewLines).toList(),
    );
  }

  void _collectJsonKeys(
    Object? value,
    Set<String> keyNames,
    List<String> maskedPreview, [
    String prefix = '',
  ]) {
    if (keyNames.length >= _maxKeyNames) return;
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (key.isEmpty) continue;
        final name = prefix.isEmpty ? key : '$prefix.$key';
        keyNames.add(name);
        final entryValue = entry.value;
        if (maskedPreview.length < _maxPreviewLines &&
            (entryValue is String || entryValue is num || entryValue is bool)) {
          maskedPreview.add('$name=${_maskValue(entryValue.toString())}');
        }
        if (entryValue is Map || entryValue is List) {
          _collectJsonKeys(entryValue, keyNames, maskedPreview, name);
        }
        if (keyNames.length >= _maxKeyNames) break;
      }
    } else if (value is List) {
      for (var index = 0; index < value.length && index < 8; index++) {
        _collectJsonKeys(value[index], keyNames, maskedPreview, prefix);
      }
    }
  }

  String? _safeRelativePath(String path, String rootPath) {
    final relative = p.relative(path, from: rootPath);
    if (p.isAbsolute(relative)) return null;
    final segments = p.split(relative);
    if (segments.any((segment) => segment == '..')) return null;
    return _toPosix(relative);
  }

  String _relativeOrName(String path, String rootPath) {
    return _safeRelativePath(path, rootPath) ?? p.basename(path);
  }

  String _toPosix(String path) {
    return p.split(path).join('/');
  }

  String _maskValue(String value) {
    final trimmed = _stripInlineComment(value.trim());
    if (trimmed.isEmpty) return '********';
    final unquoted = _stripQuotes(trimmed);
    if (unquoted.length <= 4) return '****';
    if (unquoted.length <= 8) {
      return '${unquoted.substring(0, 1)}***${unquoted.substring(unquoted.length - 1)}';
    }
    return '${unquoted.substring(0, 3)}***${unquoted.substring(unquoted.length - 3)}';
  }

  String _stripInlineComment(String value) {
    final comment = value.indexOf(' #');
    return comment < 0 ? value : value.substring(0, comment).trimRight();
  }

  String _stripQuotes(String value) {
    if (value.length < 2) return value;
    final quote = value[0];
    if ((quote == '"' || quote == "'") && value.endsWith(quote)) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }
}

class ResourceDiscoveryResult {
  const ResourceDiscoveryResult({
    required this.sourceRoot,
    required this.findings,
    required this.excludedPaths,
  });

  final String sourceRoot;
  final List<ResourceFinding> findings;
  final List<String> excludedPaths;
}

class _ResourceProbe {
  const _ResourceProbe({
    this.keyNames = const [],
    this.maskedPreview = const [],
    this.isBinary = false,
  });

  final List<String> keyNames;
  final List<String> maskedPreview;
  final bool isBinary;
}

const _excludedDirectoryNames = {
  '.git',
  '.dart_tool',
  'build',
  '.gradle',
  'pods',
  'node_modules',
  '.idea',
  '.vscode',
};
const _maxProbeBytes = 256 * 1024;
const _maxPreviewLines = 5;
const _maxKeyNames = 40;
