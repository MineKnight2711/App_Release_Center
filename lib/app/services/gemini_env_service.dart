import 'dart:io';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;

class GeminiEnvService extends GetxService {
  GeminiEnvService({Directory? rootDirectory})
    : _rootDirectory = rootDirectory ?? Directory.current;

  final Directory _rootDirectory;

  File get envFile => File(p.join(_rootDirectory.path, '.env'));

  Future<String?> readApiKey() async {
    final fromFile = await readValue(_geminiApiKeyName);
    if (fromFile != null && fromFile.trim().isNotEmpty) {
      return fromFile.trim();
    }

    final fromGeminiEnv = Platform.environment[_geminiApiKeyName]?.trim();
    if (fromGeminiEnv != null && fromGeminiEnv.isNotEmpty) {
      return fromGeminiEnv;
    }

    final fromGoogleEnv = Platform.environment['GOOGLE_API_KEY']?.trim();
    if (fromGoogleEnv != null && fromGoogleEnv.isNotEmpty) {
      return fromGoogleEnv;
    }

    return null;
  }

  Future<void> saveApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      throw const GeminiEnvException('Gemini API key is required.');
    }

    await writeValue(_geminiApiKeyName, trimmed);
  }

  Future<String?> readValue(String key) async {
    if (!envFile.existsSync()) return null;

    final keyPattern = _keyPattern(key);
    for (final line in await envFile.readAsLines()) {
      final match = keyPattern.firstMatch(line);
      if (match == null) continue;
      return _decodeEnvValue(match.group(1) ?? '');
    }

    return null;
  }

  Future<void> writeValue(String key, String value) async {
    final encodedLine = '$key=${_encodeEnvValue(value)}';
    final newline = await _preferredNewline();
    final lines = envFile.existsSync()
        ? await envFile.readAsLines()
        : <String>[];
    final keyPattern = _keyPattern(key);
    var replaced = false;

    final nextLines = lines.map((line) {
      if (keyPattern.hasMatch(line)) {
        replaced = true;
        return encodedLine;
      }
      return line;
    }).toList();

    if (!replaced) {
      nextLines.add(encodedLine);
    }

    await envFile.writeAsString('${nextLines.join(newline)}$newline');
  }

  Future<String> _preferredNewline() async {
    if (!envFile.existsSync()) return Platform.lineTerminator;
    final source = await envFile.readAsString();
    return source.contains('\r\n') ? '\r\n' : '\n';
  }

  RegExp _keyPattern(String key) {
    return RegExp('^\\s*${RegExp.escape(key)}\\s*=\\s*(.*)\\s*\$');
  }

  String _decodeEnvValue(String rawValue) {
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
    if (commentStart >= 0) {
      return trimmed.substring(0, commentStart).trimRight();
    }
    return trimmed;
  }

  String _encodeEnvValue(String value) {
    if (!value.contains(RegExp(r'''[\s#"\\']'''))) return value;
    final escaped = value
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }
}

class GeminiEnvException implements Exception {
  const GeminiEnvException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _geminiApiKeyName = 'GEMINI_API_KEY';
