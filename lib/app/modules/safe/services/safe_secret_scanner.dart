import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pointycastle/digests/sha256.dart';

import '../../bundle_check/services/env_file.dart';
import '../models/safe_item.dart';

/// What a finding is, and which kind of deposit box it goes into.
enum SecretFindingType {
  envFile('File env', SafeItemKind.env),
  properties('File properties', SafeItemKind.env),
  serviceAccount('Service account', SafeItemKind.jsonKey),
  firebaseConfig('Cấu hình Firebase', SafeItemKind.jsonKey),
  secretJson('JSON chứa khoá', SafeItemKind.jsonKey),
  keystore('Keystore / chứng chỉ', SafeItemKind.file),
  appleConfig('GoogleService-Info', SafeItemKind.file),
  privateKey('Khoá riêng', SafeItemKind.apiKey),
  inlineToken('Khoá trong mã nguồn', SafeItemKind.apiKey);

  const SecretFindingType(this.label, this.kind);

  final String label;
  final SafeItemKind kind;

  /// Kept byte for byte (base64) rather than as text.
  bool get isBinary => kind == SafeItemKind.file;
}

/// One possible secret found on disk. Carries no secret itself, except the
/// short [value] of a token found inside a source file.
class SecretFinding {
  const SecretFinding({
    required this.id,
    required this.type,
    required this.path,
    required this.relativePath,
    required this.size,
    required this.fingerprint,
    this.label = '',
    this.preview = '',
    this.value,
    this.line,
    this.otherPlaces = 0,
  });

  /// Stable within one scan: the path, plus the value's fingerprint for a
  /// token found inside a file.
  final String id;
  final SecretFindingType type;

  /// Absolute path of the file.
  final String path;

  /// Path inside its project, with `/` separators.
  final String relativePath;
  final int size;

  /// SHA-256 of the file's bytes, or of the token: how a secret already in
  /// the safe is recognised without comparing the secrets themselves.
  final String fingerprint;

  /// What kind of token, for [SecretFindingType.inlineToken].
  final String label;

  /// A masked hint of what is inside: key names, an account email, the
  /// first and last characters of a token. Never the secret.
  final String preview;

  /// The token itself, for [SecretFindingType.inlineToken] only.
  final String? value;
  final int? line;

  /// How many other files hold the same token.
  final int otherPlaces;

  String get fileName => p.basename(path);

  /// The name the box gets in the safe.
  String get title => type == SecretFindingType.inlineToken
      ? '$label · $relativePath'
      : relativePath;

  /// [path] with the line, for the box's source field.
  String get location => line == null ? path : '$path:$line';

  SecretFinding withOtherPlace() => SecretFinding(
    id: id,
    type: type,
    path: path,
    relativePath: relativePath,
    size: size,
    fingerprint: fingerprint,
    label: label,
    preview: preview,
    value: value,
    line: line,
    otherPlaces: otherPlaces + 1,
  );
}

/// What a project folder was recognised by.
enum SecretProjectKind {
  flutter('Flutter'),
  node('Node / JS'),
  android('Android'),
  ios('iOS / macOS'),
  go('Go'),
  rust('Rust'),
  python('Python'),
  php('PHP'),
  ruby('Ruby'),
  java('Java'),
  git('Git'),
  folder('Thư mục');

  const SecretProjectKind(this.label);

  final String label;
}

class SecretProject {
  SecretProject({
    required this.root,
    required this.name,
    required this.kind,
    List<SecretFinding>? findings,
  }) : findings = findings ?? [];

  /// Absolute path of the project folder.
  final String root;

  /// Shown in the safe; unique within one scan.
  String name;
  final SecretProjectKind kind;
  final List<SecretFinding> findings;
}

class SecretScanProgress {
  const SecretScanProgress({
    required this.directories,
    required this.files,
    required this.findings,
    required this.projects,
    required this.currentPath,
  });

  final int directories;
  final int files;
  final int findings;
  final int projects;
  final String currentPath;
}

class SecretScanResult {
  const SecretScanResult({
    required this.root,
    required this.projects,
    required this.directories,
    required this.files,
    required this.truncated,
    required this.tooLarge,
  });

  final String root;

  /// Only projects with at least one finding, by name.
  final List<SecretProject> projects;
  final int directories;
  final int files;

  /// The walk stopped at [SafeSecretScanner.maxFiles].
  final bool truncated;

  /// Secret-looking files over the safe's size limit, left out.
  final List<String> tooLarge;

  int get findingCount =>
      projects.fold(0, (sum, project) => sum + project.findings.length);
}

/// A scan running in a background isolate.
class SecretScanJob {
  SecretScanJob(this.result, this._cancel);

  /// Null when the scan was cancelled.
  final Future<SecretScanResult?> result;
  final void Function() _cancel;

  void cancel() => _cancel();
}

typedef SecretScanRunner =
    SecretScanJob Function(
      String root, {
      void Function(SecretScanProgress progress)? onProgress,
    });

/// Walks a folder of projects looking for anything that could be a secret:
/// env and properties files, service accounts and Firebase configs,
/// keystores, private keys, and tokens written straight into source files.
///
/// It only reads. A file it cannot open is skipped, not reported.
class SafeSecretScanner {
  const SafeSecretScanner._();

  /// Stops a scan of someone's whole home folder from running for ever.
  static const maxFiles = 400000;
  static const maxDepth = 24;

  /// Files larger than this are not read for tokens.
  static const maxTextBytes = 1024 * 1024;

  /// The largest secret file kept, the same as the safe's own limit.
  static const maxSecretBytes = 10 * 1024 * 1024;

  /// Runs [scan] in a background isolate, reporting progress a few times a
  /// second.
  static SecretScanJob start(
    String root, {
    void Function(SecretScanProgress progress)? onProgress,
  }) {
    final port = ReceivePort();
    final completer = Completer<SecretScanResult?>();
    Isolate? isolate;
    var finished = false;

    void finish(SecretScanResult? result, [Object? error]) {
      if (finished) return;
      finished = true;
      port.close();
      isolate?.kill(priority: Isolate.immediate);
      if (error != null) {
        completer.completeError(error);
      } else {
        completer.complete(result);
      }
    }

    port.listen((message) {
      if (message is SecretScanProgress) {
        onProgress?.call(message);
      } else if (message is SecretScanResult) {
        finish(message);
      } else if (message is List && message.firstOrNull == 'error') {
        finish(null, FileSystemException('${message[1]}', root));
      }
    });
    Isolate.spawn(_isolateEntry, (port.sendPort, root)).then((spawned) {
      isolate = spawned;
      if (finished) spawned.kill(priority: Isolate.immediate);
    }, onError: (Object error) => finish(null, error));
    return SecretScanJob(completer.future, () => finish(null));
  }

  static void _isolateEntry((SendPort, String) message) {
    final (port, root) = message;
    try {
      final stopwatch = Stopwatch()..start();
      var last = -1000;
      final result = scan(
        root,
        onProgress: (progress) {
          if (stopwatch.elapsedMilliseconds - last < 120) return;
          last = stopwatch.elapsedMilliseconds;
          port.send(progress);
        },
      );
      port.send(result);
    } catch (error) {
      port.send(['error', '$error']);
    }
  }

  /// The scan itself, synchronous: run it through [start] from the UI.
  static SecretScanResult scan(
    String root, {
    void Function(SecretScanProgress progress)? onProgress,
  }) {
    final rootDir = Directory(p.normalize(p.absolute(root)));
    if (!rootDir.existsSync()) {
      throw FileSystemException('Không tìm thấy thư mục.', rootDir.path);
    }
    final walk = _Walk(rootDir.path, onProgress);
    walk.run();
    return walk.result();
  }
}

class _Walk {
  _Walk(this.root, this.onProgress);

  final String root;
  final void Function(SecretScanProgress progress)? onProgress;

  final _projects = <String, SecretProject>{};
  final _tokens = <String, int>{}; // project root + fingerprint → index
  final _tooLarge = <String>[];
  var _directories = 0;
  var _files = 0;
  var _findings = 0;
  var _truncated = false;

  void run() {
    final stack = <(Directory, String?, int)>[(Directory(root), null, 0)];
    while (stack.isNotEmpty) {
      if (_files >= SafeSecretScanner.maxFiles) {
        _truncated = true;
        break;
      }
      final (directory, inherited, depth) = stack.removeLast();
      final List<FileSystemEntity> children;
      try {
        children = directory.listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      _directories++;

      // The outermost project wins: a Flutter app's android/ and ios/
      // folders have markers of their own but belong to the app.
      var projectRoot = inherited;
      if (projectRoot == null) {
        final kind = _projectKind(children);
        if (kind != null) {
          projectRoot = directory.path;
          _projects[projectRoot] = SecretProject(
            root: projectRoot,
            name: p.basename(projectRoot),
            kind: kind,
          );
        }
      }

      for (final child in children) {
        final name = p.basename(child.path);
        if (child is Directory) {
          if (depth + 1 > SafeSecretScanner.maxDepth || _skipDirectory(name)) {
            continue;
          }
          stack.add((child, projectRoot, depth + 1));
        } else if (child is File) {
          _files++;
          _inspect(child, projectRoot ?? _looseProject(directory.path));
          if (_files % 200 == 0) _report(directory.path);
        }
      }
      if (_directories % 50 == 0) _report(directory.path);
    }
    _report(root);
  }

  void _report(String current) => onProgress?.call(
    SecretScanProgress(
      directories: _directories,
      files: _files,
      findings: _findings,
      projects: _projects.values.where((x) => x.findings.isNotEmpty).length,
      currentPath: current,
    ),
  );

  /// Files outside any project are grouped by the top folder they sit in
  /// under the scanned root, or under the root itself.
  String _looseProject(String directory) {
    final relative = p.relative(directory, from: root);
    final top = relative == '.' ? root : p.join(root, p.split(relative).first);
    return _projects
        .putIfAbsent(
          top,
          () => SecretProject(
            root: top,
            name: p.basename(top),
            kind: SecretProjectKind.folder,
          ),
        )
        .root;
  }

  SecretScanResult result() {
    final projects = _projects.values
        .where((project) => project.findings.isNotEmpty)
        .toList();
    // Two projects with the same folder name get their parent's name too.
    final byName = <String, List<SecretProject>>{};
    for (final project in projects) {
      byName.putIfAbsent(project.name, () => []).add(project);
    }
    for (final same in byName.values.where((list) => list.length > 1)) {
      for (final project in same) {
        final parent = p.basename(p.dirname(project.root));
        project.name = '${project.name} ($parent)';
      }
    }
    for (final project in projects) {
      project.findings.sort((a, b) {
        final byType = a.type.index.compareTo(b.type.index);
        if (byType != 0) return byType;
        return a.relativePath.compareTo(b.relativePath);
      });
    }
    projects.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return SecretScanResult(
      root: root,
      projects: projects,
      directories: _directories,
      files: _files,
      truncated: _truncated,
      tooLarge: _tooLarge,
    );
  }

  // ---- files --------------------------------------------------------------

  void _inspect(File file, String projectRoot) {
    final name = p.basename(file.path);
    final lower = name.toLowerCase();
    if (_isTemplateName(lower)) return;
    final extension = p.extension(lower);

    final candidate = _candidateType(lower, extension);
    final textual =
        _textExtensions.contains(extension) ||
        _textNames.contains(lower) ||
        candidate != null;
    if (candidate == null && !textual) return;

    final int size;
    try {
      size = file.lengthSync();
    } on FileSystemException {
      return;
    }
    if (size == 0) return;

    if (candidate != null && candidate.isBinary) {
      if (size > SafeSecretScanner.maxSecretBytes) {
        _tooLarge.add(file.path);
        return;
      }
      final bytes = _read(file);
      if (bytes == null) return;
      _add(projectRoot, file, candidate, bytes, preview: formatByteSize(size));
      return;
    }

    if (size > SafeSecretScanner.maxTextBytes) {
      // Only names that are secrets by themselves are worth a warning; a big
      // JSON is far more often translations than a key.
      if (candidate == SecretFindingType.envFile ||
          candidate == SecretFindingType.privateKey) {
        _tooLarge.add(file.path);
      }
      return;
    }
    final bytes = _read(file);
    if (bytes == null || _looksBinary(bytes)) return;
    final text = utf8.decode(bytes, allowMalformed: true);

    final classified = _classifyText(lower, extension, text, candidate);
    if (classified != null) {
      final (type, preview) = classified;
      _add(projectRoot, file, type, bytes, preview: preview);
      // A whole env or JSON key is already kept; its tokens would be twice.
      return;
    }
    _scanTokens(projectRoot, file, text);
  }

  Uint8List? _read(File file) {
    try {
      return file.readAsBytesSync();
    } on FileSystemException {
      return null;
    }
  }

  void _add(
    String projectRoot,
    File file,
    SecretFindingType type,
    List<int> bytes, {
    String preview = '',
  }) {
    final project = _projects[projectRoot]!;
    project.findings.add(
      SecretFinding(
        id: file.path,
        type: type,
        path: file.path,
        relativePath: _relative(file.path, projectRoot),
        size: bytes.length,
        fingerprint: fingerprintBytes(bytes),
        preview: preview,
      ),
    );
    _findings++;
  }

  String _relative(String path, String projectRoot) {
    final relative = p.relative(path, from: projectRoot);
    return p.split(relative).join('/');
  }

  /// Which secret file the name alone says this is, for files whose
  /// content still has to confirm it (text) or that cannot be read as text.
  SecretFindingType? _candidateType(String lower, String extension) {
    if (_keystoreExtensions.contains(extension)) {
      return SecretFindingType.keystore;
    }
    if (lower == 'googleservice-info.plist') {
      return SecretFindingType.appleConfig;
    }
    if (_isEnvName(lower)) return SecretFindingType.envFile;
    if (extension == '.properties') return SecretFindingType.properties;
    if (extension == '.json') return SecretFindingType.secretJson;
    if (_privateKeyExtensions.contains(extension) ||
        _sshKeyNames.contains(lower)) {
      return SecretFindingType.privateKey;
    }
    return null;
  }

  (SecretFindingType, String)? _classifyText(
    String lower,
    String extension,
    String text,
    SecretFindingType? candidate,
  ) {
    switch (candidate) {
      case SecretFindingType.envFile:
        final keys = parseEnvFile(text).keys.toList();
        if (keys.isEmpty) return null;
        return (SecretFindingType.envFile, _keyList(keys));
      case SecretFindingType.properties:
        final entries = parseEnvFile(text);
        final named = _namedPropertyFiles.contains(lower);
        // Other properties files only count when they hold a secret, as
        // gradle.properties does when signing passwords are kept there.
        final secretKeys = entries.entries
            .where(
              (e) =>
                  looksLikeSecretKeyName(e.key) ||
                  _secretKeyName.hasMatch(e.key),
            )
            .where(
              (e) => e.value.trim().isNotEmpty && !isPlaceholderValue(e.value),
            )
            .map((e) => e.key)
            .toList();
        if (!named && secretKeys.isEmpty) return null;
        if (entries.isEmpty) return null;
        return (SecretFindingType.properties, _keyList(entries.keys.toList()));
      case SecretFindingType.secretJson:
        return _classifyJson(text);
      case SecretFindingType.privateKey:
        final match = _privateKeyBlock.firstMatch(text);
        if (match == null && !text.startsWith('PuTTY-User-Key-File')) {
          return null;
        }
        final kind = match?.group(1)?.trim() ?? 'PuTTY';
        return (
          SecretFindingType.privateKey,
          kind.isEmpty ? 'PRIVATE KEY' : '$kind PRIVATE KEY',
        );
      default:
        return null;
    }
  }

  (SecretFindingType, String)? _classifyJson(String text) {
    final Object? value;
    try {
      value = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (value is! Map) return null;
    if (value['type'] == 'service_account' || value['private_key'] is String) {
      final email = value['client_email'];
      return (
        SecretFindingType.serviceAccount,
        email is String ? email : 'service account',
      );
    }
    if (value['project_info'] is Map && value['client'] is List) {
      final projectId = (value['project_info'] as Map)['project_id'];
      return (
        SecretFindingType.firebaseConfig,
        projectId is String ? 'Firebase · $projectId' : 'Firebase',
      );
    }
    // OAuth client secrets ({"installed": {"client_secret": ...}}) and other
    // documents carrying a key one level down.
    final keys = <String>[];
    void collect(Map<dynamic, dynamic> map, int depth) {
      for (final entry in map.entries) {
        final key = '${entry.key}';
        final child = entry.value;
        // The value has to look like a key too: translation files are full
        // of "password" keys whose values are sentences.
        if (child is String &&
            _secretKeyName.hasMatch(key) &&
            _looksLikeSecretValue(child)) {
          keys.add(key);
        } else if (child is Map && depth < 2) {
          collect(child, depth + 1);
        }
      }
    }

    collect(value, 0);
    if (keys.isEmpty) return null;
    return (SecretFindingType.secretJson, _keyList(keys));
  }

  void _scanTokens(String projectRoot, File file, String text) {
    final project = _projects[projectRoot]!;
    for (final pattern in _tokenPatterns) {
      for (final match in pattern.regex.allMatches(text)) {
        final value =
            (match.groupCount >= 1 && pattern.valueGroup > 0
                    ? match.group(pattern.valueGroup)
                    : match.group(0))!
                .trim();
        if (pattern.generic && !_looksRandom(value)) continue;
        final fingerprint = fingerprintBytes(utf8.encode(value));
        final key = '$projectRoot\u0000$fingerprint';
        final existing = _tokens[key];
        if (existing != null) {
          final previous = project.findings[existing];
          if (previous.path != file.path) {
            project.findings[existing] = previous.withOtherPlace();
          }
          continue;
        }
        final line = '\n'.allMatches(text.substring(0, match.start)).length + 1;
        _tokens[key] = project.findings.length;
        project.findings.add(
          SecretFinding(
            id: '${file.path}#$fingerprint',
            type: SecretFindingType.inlineToken,
            path: file.path,
            relativePath: _relative(file.path, projectRoot),
            size: value.length,
            fingerprint: fingerprint,
            label: pattern.label,
            preview: maskSecret(value),
            value: value,
            line: line,
          ),
        );
        _findings++;
      }
    }
  }

  // ---- rules --------------------------------------------------------------

  static SecretProjectKind? _projectKind(List<FileSystemEntity> children) {
    final names = {for (final child in children) p.basename(child.path)};
    if (names.contains('pubspec.yaml')) return SecretProjectKind.flutter;
    if (names.contains('package.json')) return SecretProjectKind.node;
    if (names.contains('settings.gradle') ||
        names.contains('settings.gradle.kts') ||
        names.contains('build.gradle') ||
        names.contains('build.gradle.kts')) {
      return SecretProjectKind.android;
    }
    if (names.contains('Podfile') ||
        names.contains('Package.swift') ||
        names.any(
          (name) =>
              name.endsWith('.xcodeproj') || name.endsWith('.xcworkspace'),
        )) {
      return SecretProjectKind.ios;
    }
    if (names.contains('go.mod')) return SecretProjectKind.go;
    if (names.contains('Cargo.toml')) return SecretProjectKind.rust;
    if (names.contains('pyproject.toml') ||
        names.contains('requirements.txt') ||
        names.contains('setup.py')) {
      return SecretProjectKind.python;
    }
    if (names.contains('composer.json')) return SecretProjectKind.php;
    if (names.contains('Gemfile')) return SecretProjectKind.ruby;
    if (names.contains('pom.xml')) return SecretProjectKind.java;
    if (names.contains('.git')) return SecretProjectKind.git;
    return null;
  }

  static bool _skipDirectory(String name) {
    // System folders, matched by exact case so an Android module named
    // "library" is still read.
    if (_systemDirectories.contains(name)) return true;
    final lower = name.toLowerCase();
    if (_skippedDirectories.contains(lower)) return true;
    return _skippedDirectorySuffixes.any(lower.endsWith);
  }

  static bool _isEnvName(String lower) =>
      lower == '.env' ||
      lower.startsWith('.env.') ||
      lower.endsWith('.env') ||
      lower == 'env' ||
      // env.production yes; env.dart or env.json are code and config.
      (lower.startsWith('env.') &&
          !_textExtensions.contains(p.extension(lower)));

  static bool _isTemplateName(String lower) => _templateMarkers.any(
    (marker) => lower.endsWith(marker) || lower.contains('$marker.'),
  );

  static bool _looksBinary(List<int> bytes) {
    final limit = math.min(bytes.length, 4096);
    for (var i = 0; i < limit; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  static String _keyList(List<String> keys) {
    if (keys.isEmpty) return '';
    final shown = keys.take(4).join(', ');
    return keys.length > 4 ? '$shown +${keys.length - 4}' : shown;
  }

  /// A value under a secret-sounding key: one unbroken word that is not a
  /// path, an address or a placeholder.
  static bool _looksLikeSecretValue(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 8 || isPlaceholderValue(trimmed)) return false;
    if (RegExp(r'\s').hasMatch(trimmed)) return false;
    if (trimmed.startsWith('/') || trimmed.contains('://')) return false;
    return shannonEntropy(trimmed) >= 3;
  }

  /// A generic `password = "…"` match only counts when the value looks
  /// generated: long, mixed, and not a placeholder, path or address.
  static bool _looksRandom(String value) {
    if (value.length < 16 || !_looksLikeSecretValue(value)) return false;
    if (!RegExp('[0-9]').hasMatch(value) ||
        !RegExp('[A-Za-z]').hasMatch(value)) {
      return false;
    }
    return shannonEntropy(value) >= 3.5;
  }
}

String fingerprintBytes(List<int> bytes) => SHA256Digest()
    .process(bytes is Uint8List ? bytes : Uint8List.fromList(bytes))
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

/// The first four and last two characters, for recognising a token without
/// showing it.
String maskSecret(String value) {
  if (value.length <= 8) return '•' * value.length;
  final head = value.substring(0, 4);
  final tail = value.substring(value.length - 2);
  return '$head${'•' * math.min(12, value.length - 6)}$tail';
}

double shannonEntropy(String value) {
  if (value.isEmpty) return 0;
  final counts = <int, int>{};
  for (final unit in value.codeUnits) {
    counts[unit] = (counts[unit] ?? 0) + 1;
  }
  var entropy = 0.0;
  for (final count in counts.values) {
    final share = count / value.length;
    entropy -= share * math.log(share) / math.ln2;
  }
  return entropy;
}

class _TokenPattern {
  const _TokenPattern(
    this.label,
    this.regex, {
    this.valueGroup = 0,
    this.generic = false,
  });

  final String label;
  final RegExp regex;
  final int valueGroup;

  /// A keyword match, whose value must also look random to count.
  final bool generic;
}

/// High-signal token shapes. Each is specific enough that a match in source
/// is almost always a real credential rather than ordinary code.
final _tokenPatterns = <_TokenPattern>[
  _TokenPattern(
    'Private key',
    RegExp(
      r'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----[\s\S]{20,8000}?-----END (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----',
    ),
  ),
  _TokenPattern('AWS access key', RegExp(r'\b(?:AKIA|ASIA)[0-9A-Z]{16}\b')),
  _TokenPattern('Google API key', RegExp(r'\bAIza[0-9A-Za-z_\-]{35}\b')),
  _TokenPattern(
    'GitHub token',
    RegExp(r'\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})\b'),
  ),
  _TokenPattern('GitLab token', RegExp(r'\bglpat-[A-Za-z0-9_\-]{20,}\b')),
  _TokenPattern('Slack token', RegExp(r'\bxox[abposr]-[A-Za-z0-9-]{10,}\b')),
  _TokenPattern(
    'Slack webhook',
    RegExp(
      r'https://hooks\.slack\.com/services/T[A-Za-z0-9]+/B[A-Za-z0-9]+/[A-Za-z0-9]+',
    ),
  ),
  _TokenPattern(
    'Stripe secret key',
    RegExp(r'\b(?:sk|rk)_live_[0-9A-Za-z]{20,}\b'),
  ),
  _TokenPattern('Anthropic API key', RegExp(r'\bsk-ant-[A-Za-z0-9_\-]{30,}')),
  _TokenPattern(
    'OpenAI API key',
    RegExp(r'\bsk-(?:proj-|svcacct-|admin-)?[A-Za-z0-9_\-]{32,}'),
  ),
  _TokenPattern(
    'SendGrid API key',
    RegExp(r'\bSG\.[A-Za-z0-9_\-]{22}\.[A-Za-z0-9_\-]{43}\b'),
  ),
  _TokenPattern(
    'Telegram bot token',
    RegExp(r'\b\d{8,10}:AA[A-Za-z0-9_\-]{33}\b'),
  ),
  _TokenPattern(
    'FCM server key',
    RegExp(r'\bAAAA[A-Za-z0-9_\-]{7}:[A-Za-z0-9_\-]{140}\b'),
  ),
  _TokenPattern(
    'Chuỗi bí mật',
    RegExp(
      r'''(?:password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|private[_-]?key)["']?\s*[:=]\s*["']([^"'\s]{16,200})["']''',
      caseSensitive: false,
    ),
    valueGroup: 1,
    generic: true,
  ),
];

final _privateKeyBlock = RegExp(
  r'-----BEGIN ((?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?)PRIVATE KEY-----',
);

final _secretKeyName = RegExp(
  r'password|passwd|secret|token|api[_-]?key|private[_-]?key|client[_-]?secret|credential',
  caseSensitive: false,
);

const _namedPropertyFiles = {
  'key.properties',
  'keystore.properties',
  'signing.properties',
  'secrets.properties',
  'secret.properties',
  'env.properties',
  'release.properties',
  'upload.properties',
};

const _keystoreExtensions = {'.jks', '.keystore', '.p12', '.pfx', '.bks'};
const _privateKeyExtensions = {'.p8', '.pem', '.key', '.ppk'};
const _sshKeyNames = {'id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519'};

const _templateMarkers = [
  '.example',
  '.sample',
  '.template',
  '.tmpl',
  '.dist',
  '.defaults',
];

/// Source and config files worth reading for tokens.
const _textExtensions = {
  '.dart',
  '.kt',
  '.kts',
  '.java',
  '.swift',
  '.m',
  '.mm',
  '.h',
  '.c',
  '.cc',
  '.cpp',
  '.cs',
  '.go',
  '.rs',
  '.py',
  '.rb',
  '.php',
  '.js',
  '.jsx',
  '.ts',
  '.tsx',
  '.mjs',
  '.cjs',
  '.vue',
  '.svelte',
  '.gradle',
  '.xml',
  '.plist',
  '.yaml',
  '.yml',
  '.toml',
  '.ini',
  '.cfg',
  '.conf',
  '.json',
  '.properties',
  '.sh',
  '.zsh',
  '.bash',
  '.ps1',
  '.bat',
  '.cmd',
  '.tf',
  '.tfvars',
  '.txt',
  '.md',
  '.xcconfig',
  '.entitlements',
  '.sql',
  '.graphql',
  '.html',
};

const _textNames = {
  'dockerfile',
  'makefile',
  'fastfile',
  'appfile',
  'matchfile',
  'gemfile',
  'podfile',
  '.npmrc',
  '.netrc',
  '.pypirc',
  'credentials',
};

/// Folders that hold tools, caches and build output, never a project's own
/// secrets, and that would make a scan crawl.
const _skippedDirectories = {
  '.git',
  '.hg',
  '.svn',
  '.dart_tool',
  '.pub-cache',
  '.pub',
  'build',
  '.gradle',
  '.cxx',
  '.externalnativebuild',
  'pods',
  'deriveddata',
  '.symlinks',
  'ephemeral',
  'node_modules',
  'bower_components',
  '.next',
  '.nuxt',
  '.turbo',
  '.expo',
  'dist',
  'out',
  'target',
  'vendor',
  'venv',
  '.venv',
  '__pycache__',
  '.mypy_cache',
  '.pytest_cache',
  '.idea',
  '.vscode',
  '.fvm',
  '.cache',
  '.terraform',
  'coverage',
  '.trash',
  '\$recycle.bin',
};

/// What a scan of a home folder or a whole drive would otherwise wade into.
const _systemDirectories = {
  'Library',
  'Applications',
  'System',
  'AppData',
  'Windows',
  'Program Files',
  'Program Files (x86)',
  'ProgramData',
  'System Volume Information',
};

const _skippedDirectorySuffixes = [
  '.xcassets',
  '.framework',
  '.xcframework',
  '.app',
  '.dsym',
  '.bundle',
  '.xcodeproj',
  '.xcworkspace',
  '.lproj',
];
