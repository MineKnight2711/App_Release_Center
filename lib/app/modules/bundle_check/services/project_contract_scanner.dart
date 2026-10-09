import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/bundle_check_models.dart';
import 'env_file.dart';

/// Derives an [EnvContract] from a project's own sources: which env keys the
/// code reads, which env file it loads, which Firebase projects it knows.
///
/// Retains key names and in-memory fingerprints for comparison. Raw env
/// values are never included in the contract or diagnostic messages.
class ProjectContractScanner {
  const ProjectContractScanner();

  static const _maxDartFiles = 6000;
  static const _maxDartFileBytes = 2 * 1024 * 1024;

  Future<EnvContract> scan(String projectPath) async {
    final sources = <String>[];
    final pubspec = await _read(p.join(projectPath, 'pubspec.yaml'));
    final usesDotenv = _hasDependency(pubspec, 'flutter_dotenv');
    final usesFirebase = _hasDependency(pubspec, 'firebase_core');

    final code = await _scanDartSources(p.join(projectPath, 'lib'));
    if (code.required.isNotEmpty || code.optional.isNotEmpty) {
      sources.add(
        'Code trong lib/ đọc ${code.required.length + code.optional.length} '
        'key env (${code.required.length} bắt buộc).',
      );
    }

    // The project's own .env says which keys the machine that builds it has
    // today. A bundle missing one was likely built
    // from an older .env — worth a warning, not proof of a crash.
    final localKeys = <String>{};
    final fingerprints = <String, String>{};
    var hasActualEnv = false;
    if (usesDotenv) {
      for (final name
          in code.envFiles.isEmpty ? const ['.env'] : code.envFiles) {
        final text = await _read(p.join(projectPath, name));
        if (text == null) continue;
        hasActualEnv = true;
        final values = parseEnvFile(text);
        final keys = values.keys;
        localKeys.addAll(keys);
        fingerprints.addAll(
          values.map((key, value) => MapEntry(key, envValueFingerprint(value))),
        );
        sources.add(
          '$name của project có ${keys.length} key (đối chiếu giá trị đã băm).',
        );
      }
    }

    // Sample files can lag behind production. Only code that requires a key
    // may make it mandatory; compare other keys against the actual env file.
    final required = {...code.required};
    // If production deliberately omits a nullable/fallback key, the bundle
    // may omit it too. Without a local env, keep code-derived suggestions.
    final optional = {
      if (!hasActualEnv) ...code.optional,
      ...localKeys,
    }.difference(required);
    final keySources = <String, String>{
      for (final key in localKeys) key: '.env của project',
      for (final key in code.optional) key: 'code đọc, có xử lý khi thiếu',
      for (final key in code.required)
        key: 'code bắt buộc (dotenv.get / env[...]!)',
    };

    final firebase = await _firebaseCandidates(projectPath);
    final expected = await _expectedFirebaseProject(projectPath, firebase);
    if (firebase.isNotEmpty) {
      sources.add(
        'Firebase: ${firebase.entries.map((e) => '${e.key} (${e.value})').join('; ')}.',
      );
    }

    return EnvContract(
      projectLinked: true,
      usesDotenv: usesDotenv,
      envFileNames: code.envFiles.toList()..sort(),
      requiredKeys: required.toList()..sort(),
      optionalKeys: optional.toList()..sort(),
      keySources: keySources,
      envValueFingerprints: fingerprints,
      usesFirebase: usesFirebase || firebase.isNotEmpty,
      firebaseCandidates: firebase,
      expectedFirebaseProjectId: expected,
      sources: sources,
    );
  }

  static bool _hasDependency(String? pubspec, String package) {
    if (pubspec == null) return false;
    return RegExp(
      '^\\s+${RegExp.escape(package)}\\s*:',
      multiLine: true,
    ).hasMatch(pubspec);
  }

  Future<_CodeScan> _scanDartSources(String libPath) async {
    final scan = _CodeScan();
    final directory = Directory(libPath);
    if (!directory.existsSync()) return scan;

    var count = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (++count > _maxDartFiles) break;
      try {
        if (await entity.length() > _maxDartFileBytes) continue;
        scanDotenvUsage(await entity.readAsString(), scan);
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }
    return scan;
  }

  Future<Map<String, String>> _firebaseCandidates(String projectPath) async {
    final found = <String, List<String>>{};
    void add(String id, String source) {
      final list = found.putIfAbsent(id, () => []);
      if (!list.contains(source)) list.add(source);
    }

    final lib = Directory(p.join(projectPath, 'lib'));
    if (lib.existsSync()) {
      await for (final entity in lib.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('firebase_options') || !name.endsWith('.dart')) {
          continue;
        }
        final text = await _read(entity.path);
        if (text == null) continue;
        for (final id in parseFirebaseOptionsProjectIds(text)) {
          add(id, name);
        }
      }
    }

    for (final (file, label) in _googleServicesFiles(projectPath)) {
      final id = await _googleServicesProjectId(file);
      if (id != null) add(id, label);
    }

    return {
      for (final entry in found.entries) entry.key: entry.value.join(', '),
    };
  }

  Future<String?> _expectedFirebaseProject(
    String projectPath,
    Map<String, String> candidates,
  ) async {
    final files = {
      for (final (file, label) in _googleServicesFiles(projectPath))
        label: file,
    };
    final flavor = await readAndroidFlavor(projectPath);
    final ordered = [
      if (flavor != null) 'google-services.json ($flavor)',
      for (final name in const ['prod', 'production', 'release', 'live'])
        'google-services.json ($name)',
      'google-services.json (main)',
    ];
    for (final label in ordered) {
      final file = files[label];
      if (file == null) continue;
      final id = await _googleServicesProjectId(file);
      if (id != null) return id;
    }
    return candidates.length == 1 ? candidates.keys.single : null;
  }

  static List<(File, String)> _googleServicesFiles(String projectPath) {
    final app = p.join(projectPath, 'android', 'app');
    final result = <(File, String)>[];
    final main = File(p.join(app, 'google-services.json'));
    if (main.existsSync()) result.add((main, 'google-services.json (main)'));
    final src = Directory(p.join(app, 'src'));
    if (src.existsSync()) {
      for (final entity in src.listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final file = File(p.join(entity.path, 'google-services.json'));
        if (file.existsSync()) {
          result.add((
            file,
            'google-services.json (${p.basename(entity.path)})',
          ));
        }
      }
    }
    return result;
  }

  static Future<String?> _googleServicesProjectId(File file) async {
    try {
      final json = jsonDecode(await file.readAsString());
      final info = json is Map ? json['project_info'] : null;
      final id = info is Map ? info['project_id'] : null;
      return id is String && id.trim().isNotEmpty ? id.trim() : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Future<String?> _read(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return await file.readAsString();
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }
}

/// `ANDROID_FLAVOR` from `android/env.properties`, as the release workflow
/// reads it.
Future<String?> readAndroidFlavor(String projectPath) async {
  final file = File(p.join(projectPath, 'android', 'env.properties'));
  if (!file.existsSync()) return null;
  try {
    for (final line in await file.readAsLines()) {
      final match = RegExp(
        r'^\s*ANDROID_FLAVOR\s*=\s*(.*?)\s*$',
      ).firstMatch(line);
      final flavor = match?.group(1)?.trim();
      if (flavor != null && flavor.isNotEmpty) return flavor;
    }
  } on FileSystemException {
    return null;
  }
  return null;
}

class _CodeScan implements DotenvUsageSink {
  final Set<String> required = {};
  final Set<String> optional = {};
  final Set<String> envFiles = {};

  @override
  void requiredKey(String key) {
    required.add(key);
    optional.remove(key);
  }

  @override
  void optionalKey(String key) {
    if (!required.contains(key)) optional.add(key);
  }

  @override
  void envFile(String name) => envFiles.add(name);
}

abstract class DotenvUsageSink {
  void requiredKey(String key);
  void optionalKey(String key);
  void envFile(String name);
}

final _loadPattern = RegExp(r'(?:dotenv|DotEnv\(\))\s*\.\s*load\s*\(([^)]*)\)');
final _fileNamePattern = RegExp(r'''fileName\s*:\s*['"]([^'"]+)['"]''');
final _keyPattern = RegExp(
  r'''(?:dotenv|DotEnv\(\))\s*\.\s*(env\s*\[|get\s*\(|maybeGet\s*\(|getInt\s*\(|getDouble\s*\(|getBool\s*\()\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]''',
);

/// Records how [source] uses flutter_dotenv.
///
/// A key is required when reading it throws or is force-unwrapped
/// (`dotenv.get('X')`, `dotenv.env['X']!`), optional when the code copes with
/// its absence (`dotenv.env['X']`, `maybeGet`, a `fallback:`).
void scanDotenvUsage(String source, DotenvUsageSink sink) {
  for (final match in _loadPattern.allMatches(source)) {
    final name = _fileNamePattern.firstMatch(match.group(1) ?? '')?.group(1);
    sink.envFile(name ?? '.env');
  }
  for (final match in _keyPattern.allMatches(source)) {
    final accessor = match.group(1)!.replaceAll(RegExp(r'\s'), '');
    final key = match.group(2)!;
    final rest = source.substring(
      match.end,
      (match.end + 160).clamp(0, source.length),
    );
    final bool required;
    if (accessor.startsWith('env[')) {
      required = RegExp(r'^\s*\]\s*!').hasMatch(rest);
    } else if (accessor.startsWith('maybeGet')) {
      required = false;
    } else {
      final close = rest.indexOf(')');
      final args = close < 0 ? rest : rest.substring(0, close);
      required = !args.contains('fallback');
    }
    required ? sink.requiredKey(key) : sink.optionalKey(key);
  }
}

/// Project ids from a FlutterFire `firebase_options.dart`, taking the
/// `android` options when the file has them.
List<String> parseFirebaseOptionsProjectIds(String source) {
  final projectId = RegExp(r'''projectId\s*:\s*['"]([^'"]+)['"]''');
  final android = RegExp(
    r'FirebaseOptions\s+android\s*=\s*(?:const\s+)?FirebaseOptions\s*\(([^;]*)\)\s*;',
  ).firstMatch(source);
  final scope = android?.group(1) ?? source;
  return {
    for (final match in projectId.allMatches(scope)) match.group(1)!,
  }.toList();
}
