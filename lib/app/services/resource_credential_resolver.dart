import 'dart:convert';
import 'dart:io';

import 'package:app_release_center/app/models/ch_play_credentials.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/models/resource_collection.dart';
import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

class ResourceCredentialResolver extends GetxService {
  ResourceCredentialResolver({required ChPlayCredentialStoreService store})
    : _store = store;

  final ChPlayCredentialStoreService _store;

  Future<Map<String, SigningCredentialBundleEntry>> resolve({
    required String sourceRoot,
    required List<ResourceFinding> findings,
    required List<ChPlayProject> chPlayProjects,
    Map<String, SigningCredentialBundleEntry> manualCredentials = const {},
  }) async {
    final root = p.normalize(sourceRoot);
    final signingFindings = findings
        .where((finding) => finding.kind == ResourceTargetKind.signingKey)
        .toList();
    final resolved = <String, SigningCredentialBundleEntry>{
      for (final finding in signingFindings)
        finding.id: SigningCredentialBundleEntry(
          relativePath: finding.relativePath,
          source: SigningCredentialSource.projectFile,
        ),
    };

    if (signingFindings.isEmpty) return resolved;

    final managedProject = _matchingChPlayProject(root, chPlayProjects);
    if (managedProject != null) {
      final credentials = await _store.read(managedProject.id);
      final candidate = _candidateFromSecureStore(credentials, root);
      if (candidate != null) {
        _mergeCandidate(
          resolved: resolved,
          findings: signingFindings,
          candidate: candidate,
          sourceRoot: root,
          overwrite: false,
        );
      }
    }

    for (final candidate in await _projectFileCandidates(root)) {
      _mergeCandidate(
        resolved: resolved,
        findings: signingFindings,
        candidate: candidate,
        sourceRoot: root,
        overwrite: false,
      );
    }

    for (final finding in signingFindings) {
      final manual = manualCredentials[finding.id];
      if (manual == null || !manual.hasAnyCredential) continue;
      resolved[finding.id] = _mergeEntries(
        base: resolved[finding.id],
        incoming: SigningCredentialBundleEntry(
          relativePath: finding.relativePath,
          source: SigningCredentialSource.manual,
          keyAlias: manual.keyAlias,
          storePassword: manual.storePassword,
          keyPassword: _effectiveKeyPassword(
            manual.keyPassword,
            manual.storePassword,
          ),
        ),
        overwrite: true,
      );
    }

    return {
      for (final entry in resolved.entries)
        entry.key: _withMaskedPreview(entry.value),
    };
  }

  ChPlayProject? _matchingChPlayProject(
    String sourceRoot,
    List<ChPlayProject> projects,
  ) {
    final lowerSource = p.normalize(sourceRoot).toLowerCase();
    for (final project in projects) {
      if (p.normalize(project.path).toLowerCase() == lowerSource) {
        return project;
      }
    }
    return null;
  }

  _CredentialCandidate? _candidateFromSecureStore(
    ChPlayCredentials credentials,
    String sourceRoot,
  ) {
    if (!credentials.metadata.hasAnySigningCredential) return null;
    return _CredentialCandidate(
      source: SigningCredentialSource.secureStore,
      sourcePathHint: credentials.jksPath,
      pathBases: [
        sourceRoot,
        p.join(sourceRoot, 'android'),
        p.join(sourceRoot, 'android', 'app'),
      ],
      keyAlias: credentials.keyAlias,
      storePassword: credentials.storePassword,
      keyPassword: _effectiveKeyPassword(
        credentials.keyPassword,
        credentials.storePassword,
      ),
    );
  }

  Future<List<_CredentialCandidate>> _projectFileCandidates(
    String sourceRoot,
  ) async {
    final candidates = <_CredentialCandidate>[];
    final androidRoot = p.join(sourceRoot, 'android');
    final files = [
      _ProjectCredentialFile(
        file: File(p.join(androidRoot, 'key.properties')),
        pathBases: [androidRoot, p.join(androidRoot, 'app'), sourceRoot],
      ),
      _ProjectCredentialFile(
        file: File(p.join(androidRoot, 'env.properties')),
        pathBases: [androidRoot, sourceRoot, p.join(androidRoot, 'app')],
      ),
    ];

    for (final entry in files) {
      if (!entry.file.existsSync()) continue;
      final properties = await _readProperties(entry.file);
      final keyAlias = _firstValue(properties, const ['keyalias', 'alias']);
      final storePassword = _firstValue(properties, const [
        'storepassword',
        'androidstorepassword',
        'releaseStorePassword',
      ]);
      final keyPassword = _effectiveKeyPassword(
        _firstValue(properties, const ['keypassword', 'androidkeypassword']),
        storePassword,
      );
      final sourcePathHint = _firstValue(properties, const [
        'storefile',
        'androidjkspath',
        'jkspath',
        'keystorepath',
      ]);

      if (_hasText(keyAlias) ||
          _hasText(storePassword) ||
          _hasText(keyPassword) ||
          _hasText(sourcePathHint)) {
        candidates.add(
          _CredentialCandidate(
            source: SigningCredentialSource.projectFile,
            sourcePathHint: sourcePathHint,
            pathBases: entry.pathBases,
            keyAlias: keyAlias,
            storePassword: storePassword,
            keyPassword: keyPassword,
          ),
        );
      }
    }

    return candidates;
  }

  Future<Map<String, String>> _readProperties(File file) async {
    final result = <String, String>{};
    final source = await file.readAsString();
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
      final key = _canonicalKey(match.group(1)!);
      final value = _stripQuotes(_stripInlineComment(match.group(2) ?? ''));
      if (key.isNotEmpty && value.trim().isNotEmpty) {
        result.putIfAbsent(key, () => value.trim());
      }
    }

    return result;
  }

  void _mergeCandidate({
    required Map<String, SigningCredentialBundleEntry> resolved,
    required List<ResourceFinding> findings,
    required _CredentialCandidate candidate,
    required String sourceRoot,
    required bool overwrite,
  }) {
    final matches = _matchingFindings(candidate, findings, sourceRoot);
    for (final finding in matches) {
      resolved[finding.id] = _mergeEntries(
        base: resolved[finding.id],
        incoming: SigningCredentialBundleEntry(
          relativePath: finding.relativePath,
          source: candidate.source,
          keyAlias: candidate.keyAlias,
          storePassword: candidate.storePassword,
          keyPassword: candidate.keyPassword,
        ),
        overwrite: overwrite,
      );
    }
  }

  List<ResourceFinding> _matchingFindings(
    _CredentialCandidate candidate,
    List<ResourceFinding> findings,
    String sourceRoot,
  ) {
    final hintedPath = candidate.sourcePathHint?.trim();
    if (hintedPath == null || hintedPath.isEmpty) {
      return findings.length == 1 ? [findings.single] : const [];
    }

    final paths = _candidateAbsolutePaths(
      hintedPath: hintedPath,
      pathBases: candidate.pathBases,
      sourceRoot: sourceRoot,
    );
    final matches = findings.where((finding) {
      final findingPath = p.normalize(p.absolute(finding.sourcePath));
      return paths.any((path) => p.equals(path, findingPath));
    }).toList();
    if (matches.isNotEmpty) return matches;
    return findings.length == 1 ? [findings.single] : const [];
  }

  Set<String> _candidateAbsolutePaths({
    required String hintedPath,
    required List<String> pathBases,
    required String sourceRoot,
  }) {
    final normalizedHint = hintedPath.replaceAll('/', p.separator);
    if (p.isAbsolute(normalizedHint)) {
      return {p.normalize(p.absolute(normalizedHint))};
    }

    return {
      for (final base in pathBases)
        p.normalize(p.absolute(p.join(base, normalizedHint))),
      p.normalize(p.absolute(p.join(sourceRoot, normalizedHint))),
    };
  }

  SigningCredentialBundleEntry _mergeEntries({
    required SigningCredentialBundleEntry? base,
    required SigningCredentialBundleEntry incoming,
    required bool overwrite,
  }) {
    if (base == null) return _withMaskedPreview(incoming);
    final keyAlias = overwrite
        ? _nonEmptyOrFallback(incoming.keyAlias, base.keyAlias)
        : _nonEmptyOrFallback(base.keyAlias, incoming.keyAlias);
    final storePassword = overwrite
        ? _nonEmptyOrFallback(incoming.storePassword, base.storePassword)
        : _nonEmptyOrFallback(base.storePassword, incoming.storePassword);
    final keyPassword = _effectiveKeyPassword(
      overwrite
          ? _nonEmptyOrFallback(incoming.keyPassword, base.keyPassword)
          : _nonEmptyOrFallback(base.keyPassword, incoming.keyPassword),
      storePassword,
    );

    return _withMaskedPreview(
      SigningCredentialBundleEntry(
        relativePath: base.relativePath,
        source: overwrite || !base.hasAnyCredential
            ? incoming.source
            : base.source,
        keyAlias: keyAlias,
        storePassword: storePassword,
        keyPassword: keyPassword,
      ),
    );
  }

  SigningCredentialBundleEntry _withMaskedPreview(
    SigningCredentialBundleEntry entry,
  ) {
    final preview = <String>[
      if (_hasText(entry.keyAlias)) 'alias=${entry.keyAlias!.trim()}',
      if (_hasText(entry.storePassword))
        'storePassword=${_maskValue(entry.storePassword!)}',
      if (_hasText(entry.keyPassword))
        'keyPassword=${_maskValue(entry.keyPassword!)}',
    ];
    return SigningCredentialBundleEntry(
      relativePath: entry.relativePath,
      source: entry.source,
      keyAlias: _trimmedOrNull(entry.keyAlias),
      storePassword: _trimmedOrNull(entry.storePassword),
      keyPassword: _effectiveKeyPassword(
        entry.keyPassword,
        entry.storePassword,
      ),
      maskedPreview: preview,
    );
  }

  String _canonicalKey(String key) {
    return key.replaceAll(RegExp(r'[_\-.]'), '').toLowerCase();
  }

  String? _firstValue(Map<String, String> properties, List<String> keys) {
    for (final key in keys.map(_canonicalKey)) {
      final value = properties[key];
      if (_hasText(value)) return value!.trim();
    }
    return null;
  }

  String? _effectiveKeyPassword(String? keyPassword, String? storePassword) {
    return _trimmedOrNull(keyPassword) ?? _trimmedOrNull(storePassword);
  }

  String? _nonEmptyOrFallback(String? preferred, String? fallback) {
    return _trimmedOrNull(preferred) ?? _trimmedOrNull(fallback);
  }

  String _stripInlineComment(String value) {
    final comment = value.indexOf(' #');
    return comment < 0 ? value.trim() : value.substring(0, comment).trimRight();
  }

  String _stripQuotes(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 2) return trimmed;
    final quote = trimmed[0];
    if ((quote == '"' || quote == "'") && trimmed.endsWith(quote)) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  String _maskValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '********';
    if (trimmed.length <= 4) return '****';
    if (trimmed.length <= 8) {
      return '${trimmed.substring(0, 1)}***${trimmed.substring(trimmed.length - 1)}';
    }
    return '${trimmed.substring(0, 3)}***${trimmed.substring(trimmed.length - 3)}';
  }

  bool _hasText(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  String? _trimmedOrNull(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class _CredentialCandidate {
  const _CredentialCandidate({
    required this.source,
    required this.pathBases,
    this.sourcePathHint,
    this.keyAlias,
    this.storePassword,
    this.keyPassword,
  });

  final SigningCredentialSource source;
  final List<String> pathBases;
  final String? sourcePathHint;
  final String? keyAlias;
  final String? storePassword;
  final String? keyPassword;
}

class _ProjectCredentialFile {
  const _ProjectCredentialFile({required this.file, required this.pathBases});

  final File file;
  final List<String> pathBases;
}
