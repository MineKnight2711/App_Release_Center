import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static Future<FirebaseOptions?> load() async {
    final dotenv = await _readDotEnvValues();
    final apiKey = _value('FIREBASE_API_KEY', dotenv);
    final appId = _value('FIREBASE_APP_ID', dotenv);
    final messagingSenderId = _value('FIREBASE_MESSAGING_SENDER_ID', dotenv);
    final projectId = _value('FIREBASE_PROJECT_ID', dotenv);

    if ([apiKey, appId, messagingSenderId, projectId].any((v) => v.isEmpty)) {
      return null;
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: _optionalValue('FIREBASE_AUTH_DOMAIN', dotenv),
      storageBucket: _optionalValue('FIREBASE_STORAGE_BUCKET', dotenv),
    );
  }

  static const Map<String, String> _dartDefineValues = {
    'FIREBASE_API_KEY': String.fromEnvironment('FIREBASE_API_KEY'),
    'FIREBASE_APP_ID': String.fromEnvironment('FIREBASE_APP_ID'),
    'FIREBASE_MESSAGING_SENDER_ID': String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
    ),
    'FIREBASE_PROJECT_ID': String.fromEnvironment('FIREBASE_PROJECT_ID'),
    'FIREBASE_AUTH_DOMAIN': String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    'FIREBASE_STORAGE_BUCKET': String.fromEnvironment(
      'FIREBASE_STORAGE_BUCKET',
    ),
  };

  static String _value(String key, Map<String, String> dotenv) {
    final fromDefine = _dartDefineValues[key]?.trim() ?? '';
    if (fromDefine.isNotEmpty) return fromDefine;

    final fromEnv = Platform.environment[key]?.trim() ?? '';
    if (fromEnv.isNotEmpty) return fromEnv;

    return dotenv[key]?.trim() ?? '';
  }

  static String? _optionalValue(String key, Map<String, String> dotenv) {
    final value = _value(key, dotenv);
    return value.isEmpty ? null : value;
  }

  static Future<Map<String, String>> _readDotEnvValues() async {
    final values = <String, String>{};
    for (final file in _envFiles()) {
      if (!file.existsSync()) continue;
      for (final line in await file.readAsLines()) {
        final match = RegExp(
          r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$',
        ).firstMatch(line);
        if (match == null) continue;
        values.putIfAbsent(
          match.group(1)!,
          () => _decodeEnvValue(match.group(2) ?? ''),
        );
      }
    }
    return values;
  }

  static List<File> _envFiles() {
    final files = <File>[File('.env'), File('firebase.env')];

    final executableDirectory = File(Platform.resolvedExecutable).parent;
    files.addAll([
      File('${executableDirectory.path}${Platform.pathSeparator}.env'),
      File('${executableDirectory.path}${Platform.pathSeparator}firebase.env'),
    ]);

    final appData = Platform.environment['APPDATA']?.trim();
    if (appData != null && appData.isNotEmpty) {
      final configDirectory =
          '$appData${Platform.pathSeparator}App Release Center';
      files.addAll([
        File('$configDirectory${Platform.pathSeparator}.env'),
        File('$configDirectory${Platform.pathSeparator}firebase.env'),
      ]);
    }

    final seen = <String>{};
    return files
        .where((file) => seen.add(file.absolute.path.toLowerCase()))
        .toList(growable: false);
  }

  static String _decodeEnvValue(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.length >= 2) {
      final quote = trimmed[0];
      if ((quote == '"' || quote == "'") && trimmed.endsWith(quote)) {
        final inner = trimmed.substring(1, trimmed.length - 1);
        if (quote == '"') {
          return inner
              .replaceAll(r'\"', '"')
              .replaceAll(r'\\', '\\')
              .replaceAll(r'\n', '\n');
        }
        return inner;
      }
    }

    final commentStart = trimmed.indexOf(' #');
    return commentStart >= 0
        ? trimmed.substring(0, commentStart).trimRight()
        : trimmed;
  }
}
