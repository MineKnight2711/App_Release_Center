import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;

const defaultAndroidKeyAlias = 'release';

class AndroidKeystoreGenerationService extends GetxService {
  AndroidKeystoreGenerationService({
    AndroidKeystoreCommandRunner? commandRunner,
    String Function()? passwordGenerator,
  }) : _commandRunner = commandRunner ?? ProcessAndroidKeystoreCommandRunner(),
       _passwordGenerator = passwordGenerator ?? _securePassword;

  final AndroidKeystoreCommandRunner _commandRunner;
  final String Function() _passwordGenerator;

  Future<AndroidKeystoreGenerationResult> generate({
    required String projectPath,
    String keyAlias = defaultAndroidKeyAlias,
    String? storePassword,
    bool forceRecreate = false,
    String? distinguishedName,
  }) async {
    final root = Directory(p.normalize(projectPath));
    if (!root.existsSync()) {
      throw FileSystemException('Project directory does not exist.', root.path);
    }

    final androidDirectory = Directory(p.join(root.path, 'android'));
    if (!androidDirectory.existsSync()) {
      throw FileSystemException(
        'Project does not contain an android folder.',
        androidDirectory.path,
      );
    }

    final alias = _normalizeAlias(keyAlias);
    final fileName = '${_safeFileSegment(alias)}.jks';
    final keystoreFile = File(
      p.join(androidDirectory.path, 'fastlane', 'keys', fileName),
    );
    final envPropertiesFile = File(
      p.join(androidDirectory.path, 'env.properties'),
    );
    final keyPropertiesFile = File(
      p.join(androidDirectory.path, 'key.properties'),
    );
    final envKeystorePath = _normalizeRelativePath(
      p.join('fastlane', 'keys', fileName),
    );
    final keyPropertiesStoreFile = _normalizeRelativePath(
      p.join('..', 'fastlane', 'keys', fileName),
    );

    if (keystoreFile.existsSync()) {
      if (!forceRecreate) {
        throw AndroidKeystoreGenerationException(
          '${_normalizeRelativePath(p.relative(keystoreFile.path, from: root.path))} already exists. Enable force recreate to replace it.',
        );
      }
      await keystoreFile.delete();
    }

    final password = _resolvePassword(storePassword);

    keystoreFile.parent.createSync(recursive: true);
    final result = await _commandRunner.run(
      executable: 'keytool',
      arguments: [
        '-genkeypair',
        '-v',
        '-keystore',
        keystoreFile.path,
        '-storetype',
        'JKS',
        '-keyalg',
        'RSA',
        '-keysize',
        '2048',
        '-validity',
        '10000',
        '-alias',
        alias,
        '-storepass',
        password,
        '-keypass',
        password,
        '-dname',
        distinguishedName ?? _defaultDistinguishedName(root),
      ],
      workingDirectory: root.path,
    );

    if (result.exitCode != 0) {
      throw AndroidKeystoreGenerationException(
        'keytool failed with exit code ${result.exitCode}.${_failureOutput(result, password)}',
      );
    }

    await _writeProperties(envPropertiesFile, {
      'KEY_ALIAS': alias,
      'ANDROID_JKS_PATH': envKeystorePath,
      'STORE_PASSWORD': password,
      'KEY_PASSWORD': password,
    });
    await _writeProperties(keyPropertiesFile, {
      'keyAlias': alias,
      'storeFile': keyPropertiesStoreFile,
      'storePassword': password,
      'keyPassword': password,
    });
    await _ensureGitignoreEntries(
      File(p.join(androidDirectory.path, '.gitignore')),
      const ['/env.properties', '/key.properties'],
    );
    await _ensureGitignoreEntries(
      File(p.join(keystoreFile.parent.path, '.gitignore')),
      const ['*.jks', '*.keystore', '!.gitkeep'],
    );

    return AndroidKeystoreGenerationResult(
      keystorePath: keystoreFile.path,
      envPropertiesPath: envPropertiesFile.path,
      keyPropertiesPath: keyPropertiesFile.path,
      keyAlias: alias,
      storePassword: password,
      keyPassword: password,
      envKeystorePath: envKeystorePath,
      keyPropertiesStoreFile: keyPropertiesStoreFile,
    );
  }

  Future<void> _writeProperties(
    File file,
    Map<String, String> properties,
  ) async {
    file.parent.createSync(recursive: true);
    final existing = file.existsSync() ? await file.readAsString() : '';
    final lines = existing.isEmpty
        ? <String>[]
        : existing.split(RegExp(r'\r?\n'));
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }

    final updatedKeys = <String>{};
    final updatedLines = <String>[];
    for (final line in lines) {
      final key = _propertyKey(line);
      if (key == null || !properties.containsKey(key)) {
        updatedLines.add(line);
        continue;
      }

      final value = properties[key]!;
      updatedLines.add('$key=$value');
      updatedKeys.add(key);
    }

    for (final entry in properties.entries) {
      if (updatedKeys.contains(entry.key)) continue;
      updatedLines.add('${entry.key}=${entry.value}');
    }

    await file.writeAsString('${updatedLines.join('\n')}\n');
  }

  Future<void> _ensureGitignoreEntries(File file, List<String> entries) async {
    final existing = file.existsSync() ? await file.readAsString() : '';
    final lines = existing.isEmpty
        ? <String>[]
        : existing.split(RegExp(r'\r?\n'));
    final existingEntries = lines.map((line) => line.trim()).toSet();
    final missing = entries
        .where((entry) => !existingEntries.contains(entry))
        .toList();
    if (missing.isEmpty) return;

    file.parent.createSync(recursive: true);
    final separator = existing.isEmpty || existing.endsWith('\n') ? '' : '\n';
    await file.writeAsString('$existing$separator${missing.join('\n')}\n');
  }

  String _failureOutput(AndroidKeystoreCommandResult result, String password) {
    final output = [result.stderr, result.stdout]
        .where((value) => value.trim().isNotEmpty)
        .join('\n')
        .replaceAll(password, '[redacted]')
        .trim();
    if (output.isEmpty) return '';
    return ' $output';
  }

  String _defaultDistinguishedName(Directory root) {
    final name = _sanitizeDistinguishedNameValue(p.basename(root.path));
    return 'CN=$name, OU=Mobile, O=$name, L=Ho Chi Minh City, ST=Ho Chi Minh, C=VN';
  }

  String _normalizeAlias(String value) {
    final alias = value.trim();
    return alias.isEmpty ? defaultAndroidKeyAlias : alias;
  }

  String _resolvePassword(String? manualPassword) {
    final manual = manualPassword?.trim() ?? '';
    if (manual.isNotEmpty) {
      if (manual.length < 6) {
        throw const AndroidKeystoreGenerationException(
          'Manual keystore password must be at least 6 characters.',
        );
      }
      return manual;
    }

    final generated = _passwordGenerator().trim();
    if (generated.isEmpty) {
      throw const AndroidKeystoreGenerationException(
        'Failed to generate a keystore password.',
      );
    }
    return generated;
  }

  String _safeFileSegment(String value) {
    final safe = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^[._]+|[._]+$'), '');
    if (safe.isEmpty) return defaultAndroidKeyAlias;
    return safe;
  }

  String _sanitizeDistinguishedNameValue(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[,=+]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sanitized.isEmpty ? 'Android App' : sanitized;
  }

  String? _propertyKey(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('!')) {
      return null;
    }

    final equalsIndex = line.indexOf('=');
    final colonIndex = line.indexOf(':');
    final indexes = [
      if (equalsIndex >= 0) equalsIndex,
      if (colonIndex >= 0) colonIndex,
    ]..sort();
    if (indexes.isEmpty) return null;

    final key = line.substring(0, indexes.first).trim();
    return key.isEmpty ? null : key;
  }
}

abstract class AndroidKeystoreCommandRunner {
  Future<AndroidKeystoreCommandResult> run({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  });
}

class ProcessAndroidKeystoreCommandRunner
    implements AndroidKeystoreCommandRunner {
  @override
  Future<AndroidKeystoreCommandResult> run({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        runInShell: false,
      );
      return AndroidKeystoreCommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout?.toString() ?? '',
        stderr: result.stderr?.toString() ?? '',
      );
    } on ProcessException catch (error) {
      return AndroidKeystoreCommandResult(exitCode: -1, stderr: error.message);
    }
  }
}

class AndroidKeystoreCommandResult {
  const AndroidKeystoreCommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class AndroidKeystoreGenerationResult {
  const AndroidKeystoreGenerationResult({
    required this.keystorePath,
    required this.envPropertiesPath,
    required this.keyPropertiesPath,
    required this.keyAlias,
    required this.storePassword,
    required this.keyPassword,
    required this.envKeystorePath,
    required this.keyPropertiesStoreFile,
  });

  final String keystorePath;
  final String envPropertiesPath;
  final String keyPropertiesPath;
  final String keyAlias;
  final String storePassword;
  final String keyPassword;
  final String envKeystorePath;
  final String keyPropertiesStoreFile;
}

class AndroidKeystoreGenerationException implements Exception {
  const AndroidKeystoreGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _securePassword() {
  final random = Random.secure();
  final bytes = Uint8List(48);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return base64Url.encode(bytes).replaceAll('=', '');
}

String _normalizeRelativePath(String path) {
  return path.replaceAll('\\', '/');
}
