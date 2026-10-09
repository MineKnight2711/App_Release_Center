import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

import 'bundle_zip.dart';

class BundleToolException implements Exception {
  const BundleToolException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BundleProcessResult {
  const BundleProcessResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.missingExecutable = false,
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool missingExecutable;
  final bool timedOut;

  String get output =>
      [stdout, stderr].where((s) => s.trim().isNotEmpty).join('\n').trim();
}

/// Runs the JDK and bundletool. An interface so tests never spawn Java.
abstract class BundleProcessRunner {
  Future<BundleProcessResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    Duration timeout = const Duration(minutes: 2),
  });

  /// Starts a process that outlives AMC, e.g. an emulator. False when the
  /// executable is missing.
  Future<bool> startDetached(String executable, List<String> arguments);
}

class IoBundleProcessRunner implements BundleProcessRunner {
  const IoBundleProcessRunner();

  @override
  Future<bool> startDetached(String executable, List<String> arguments) async {
    try {
      await Process.start(
        executable,
        arguments,
        mode: ProcessStartMode.detached,
      );
      return true;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<BundleProcessResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        environment: environment,
      );
    } on ProcessException catch (error) {
      return BundleProcessResult(
        exitCode: -1,
        stderr: error.message,
        missingExecutable: true,
      );
    }
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    try {
      final code = await process.exitCode.timeout(timeout);
      return BundleProcessResult(
        exitCode: code,
        stdout: await stdout,
        stderr: await stderr,
      );
    } on TimeoutException {
      process.kill();
      return BundleProcessResult(
        exitCode: -1,
        stdout: await stdout.timeout(
          const Duration(seconds: 2),
          onTimeout: () => '',
        ),
        stderr: 'Quá ${timeout.inSeconds} giây, đã dừng.',
        timedOut: true,
      );
    }
  }
}

/// Where the JDK lives. `java` runs bundletool, `keytool` reads keystores.
class JavaTools {
  const JavaTools({required this.java, required this.keytool});

  final String java;
  final String keytool;

  /// JAVA_HOME first, then Android Studio's bundled JBR, then PATH.
  static JavaTools locate({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final exe = Platform.isWindows ? '.exe' : '';
    final homes = [
      env['JAVA_HOME'],
      if (Platform.isWindows) ...[
        r'C:\Program Files\Android\Android Studio\jbr',
        p.join(env['LOCALAPPDATA'] ?? '', 'Programs', 'Android Studio', 'jbr'),
      ],
      if (Platform.isMacOS)
        '/Applications/Android Studio.app/Contents/jbr/Contents/Home',
    ];
    for (final home in homes) {
      if (home == null || home.trim().isEmpty) continue;
      final java = p.join(home, 'bin', 'java$exe');
      final keytool = p.join(home, 'bin', 'keytool$exe');
      if (File(java).existsSync() && File(keytool).existsSync()) {
        return JavaTools(java: java, keytool: keytool);
      }
    }
    return const JavaTools(java: 'java', keytool: 'keytool');
  }
}

/// Reads a keystore's certificate fingerprint with `keytool`.
///
/// The password goes through an environment variable (`-storepass:env`), so it
/// never appears on a command line another process could list.
class KeystoreFingerprintReader {
  const KeystoreFingerprintReader({required this.runner, required this.tools});

  final BundleProcessRunner runner;
  final JavaTools tools;

  static const _passwordVariable = 'AMC_KEYSTORE_PASSWORD';

  Future<String> sha256Of(KeystoreRef keystore) async {
    if (!File(keystore.path).existsSync()) {
      throw BundleToolException('Không thấy keystore ${keystore.path}.');
    }
    final result = await runner.run(
      tools.keytool,
      [
        '-list',
        '-v',
        '-keystore',
        keystore.path,
        '-alias',
        keystore.alias,
        '-storepass:env',
        _passwordVariable,
      ],
      environment: {_passwordVariable: keystore.storePassword},
      timeout: const Duration(seconds: 30),
    );
    if (result.missingExecutable) {
      throw const BundleToolException('Không tìm thấy keytool (cần JDK).');
    }
    final match = RegExp(
      r'SHA-?256:\s*((?:[0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2})',
    ).firstMatch(result.output);
    if (result.exitCode != 0 || match == null) {
      final line = result.output
          .split('\n')
          .map((l) => l.trim())
          .firstWhere(
            (l) => l.startsWith('keytool error') || l.isNotEmpty,
            orElse: () => 'keytool thoát mã ${result.exitCode}',
          );
      throw BundleToolException(line);
    }
    return match.group(1)!.toUpperCase();
  }
}

/// A keystore the project signs releases with. Held in memory only.
class KeystoreRef {
  const KeystoreRef({
    required this.path,
    required this.alias,
    required this.storePassword,
    required this.keyPassword,
    required this.source,
  });

  final String path;
  final String alias;
  final String storePassword;
  final String keyPassword;

  /// e.g. `android/env.properties`.
  final String source;
}

/// Reads the release keystore a project's Gradle config points at:
/// `android/env.properties` (AMC's template) or `android/key.properties`
/// (Flutter's documented setup).
KeystoreRef? readProjectKeystore(String projectPath) {
  final android = p.join(projectPath, 'android');
  final envProperties = _properties(p.join(android, 'env.properties'));
  if (envProperties != null) {
    final path = envProperties['ANDROID_JKS_PATH'];
    final alias = envProperties['KEY_ALIAS'];
    final store = envProperties['STORE_PASSWORD'];
    if (_filled(path) && _filled(alias) && _filled(store)) {
      return KeystoreRef(
        path: _resolveProjectKeystore(path!, projectPath, android),
        alias: alias!,
        storePassword: store!,
        keyPassword: _filled(envProperties['KEY_PASSWORD'])
            ? envProperties['KEY_PASSWORD']!
            : store,
        source: 'android/env.properties',
      );
    }
  }
  final keyProperties = _properties(p.join(android, 'key.properties'));
  if (keyProperties != null) {
    final path = keyProperties['storeFile'];
    final alias = keyProperties['keyAlias'];
    final store = keyProperties['storePassword'];
    if (_filled(path) && _filled(alias) && _filled(store)) {
      return KeystoreRef(
        path: _resolveProjectKeystore(
          path!,
          projectPath,
          p.join(android, 'app'),
        ),
        alias: alias!,
        storePassword: store!,
        keyPassword: _filled(keyProperties['keyPassword'])
            ? keyProperties['keyPassword']!
            : store,
        source: 'android/key.properties',
      );
    }
  }
  return null;
}

bool _filled(String? value) =>
    value != null && value.trim().isNotEmpty && value.trim() != 'change-me';

String _resolveProjectKeystore(
  String raw,
  String projectPath,
  String defaultBase,
) {
  final android = p.join(projectPath, 'android');
  // Gradle may resolve a configured relative path in the app module or in
  // rootProject (android). Inspect direct storeFile calls and custom helpers.
  String? configuredBase;
  for (final name in ['build.gradle', 'build.gradle.kts']) {
    final file = File(p.join(android, 'app', name));
    if (!file.existsSync()) continue;
    final gradle = file.readAsStringSync().replaceAll(
      RegExp(r'/\*[\s\S]*?\*/|//[^\r\n]*'),
      '',
    );
    if (RegExp(
          r'storeFile\s*(?:=\s*)?rootProject\.file\s*\(',
        ).hasMatch(gradle) ||
        RegExp(
          r'\bresolveKeystoreFile\b[\s\S]*?rootProject\.file\s*\(\s*path\s*\)',
        ).hasMatch(gradle)) {
      configuredBase = android;
    } else if (RegExp(r'storeFile\s*(?:=\s*)?file\s*\(').hasMatch(gradle)) {
      configuredBase = p.join(android, 'app');
    }
  }
  // When Gradle declares the base, do not silently select a different key.
  if (configuredBase != null) return _resolve(raw, configuredBase);
  final candidates = {
    for (final base in [
      defaultBase,
      android,
      p.join(android, 'app'),
      projectPath,
    ])
      _resolve(raw, base),
  };
  final existing = candidates.where((path) => File(path).existsSync()).toList();
  if (existing.length == 1) return existing.single;
  if (existing.length > 1) {
    throw const BundleToolException(
      'Có nhiều keystore khớp đường dẫn tương đối nhưng chưa xác định được '
      'cách Gradle chọn file. Lưu đường dẫn keystore tuyệt đối trong AMC.',
    );
  }
  return _resolve(raw, defaultBase);
}

String _resolve(String raw, String base) {
  var path = raw.trim();
  if (path.startsWith('~')) {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    path = p.join(home, path.substring(1).replaceFirst(RegExp(r'^[/\\]'), ''));
  }
  return p.normalize(p.isAbsolute(path) ? path : p.join(base, path));
}

Map<String, String>? _properties(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    final values = <String, String>{};
    for (final raw in file.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) {
        continue;
      }
      final index = line.indexOf(RegExp('[=:]'));
      if (index <= 0) continue;
      values[line.substring(0, index).trim()] = line
          .substring(index + 1)
          .trim();
    }
    return values;
  } on FileSystemException {
    return null;
  }
}

/// The pinned bundletool jar: one version, verified by SHA-256 before use.
class BundletoolManager {
  BundletoolManager({required this.toolsDirectory, HttpClient Function()? http})
    : _http = http ?? HttpClient.new;

  static const version = '1.18.3';
  static const sha256 =
      'a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29';
  static const sizeBytes = 32520401;
  static final downloadUrl = Uri.parse(
    'https://github.com/google/bundletool/releases/download/$version/'
    'bundletool-all-$version.jar',
  );

  final Directory toolsDirectory;
  final HttpClient Function() _http;
  bool _verified = false;

  File get jar =>
      File(p.join(toolsDirectory.path, 'bundletool-all-$version.jar'));

  /// The jar, when present and intact. Hashes it once per session.
  Future<File?> find() async {
    final override = Platform.environment['BUNDLETOOL_JAR'];
    if (override != null && File(override).existsSync()) return File(override);
    final file = jar;
    if (!file.existsSync() || file.lengthSync() != sizeBytes) return null;
    if (!_verified) {
      _verified = await _sha256Of(file) == sha256;
      if (!_verified) return null;
    }
    return file;
  }

  /// Downloads the jar next to a temporary name, checks size and SHA-256,
  /// then moves it into place. A bad or partial download never becomes [jar].
  Future<File> download({
    void Function(int received, int total)? onProgress,
  }) async {
    await toolsDirectory.create(recursive: true);
    final partial = File('${jar.path}.part');
    final client = _http()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(downloadUrl);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw BundleToolException(
          'Tải bundletool lỗi HTTP ${response.statusCode}.',
        );
      }
      final digest = SHA256Digest();
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 60),
        )) {
          final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
          digest.update(bytes, 0, bytes.length);
          sink.add(bytes);
          received += bytes.length;
          if (received > sizeBytes) {
            throw const BundleToolException('File tải về lớn hơn dự kiến.');
          }
          onProgress?.call(received, sizeBytes);
        }
      } finally {
        await sink.close();
      }
      final hash = _hex(digest);
      if (received != sizeBytes || hash != sha256) {
        throw const BundleToolException(
          'bundletool tải về không khớp SHA-256 — đã bỏ file.',
        );
      }
      if (jar.existsSync()) await jar.delete();
      await partial.rename(jar.path);
      _verified = true;
      return jar;
    } on SocketException catch (error) {
      throw BundleToolException(
        'Lỗi mạng khi tải bundletool: ${error.message}',
      );
    } on TimeoutException {
      throw const BundleToolException('Tải bundletool quá hạn.');
    } on HttpException catch (error) {
      throw BundleToolException('Tải bundletool lỗi: ${error.message}');
    } finally {
      client.close(force: true);
      if (partial.existsSync()) {
        try {
          await partial.delete();
        } on FileSystemException {
          // A locked leftover is retried on the next download.
        }
      }
    }
  }

  static Future<String> _sha256Of(File file) async {
    final digest = SHA256Digest();
    await for (final chunk in file.openRead()) {
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      digest.update(bytes, 0, bytes.length);
    }
    return _hex(digest);
  }

  static String _hex(SHA256Digest digest) {
    final out = Uint8List(digest.digestSize);
    digest.doFinal(out, 0);
    return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// The two bundletool commands Phase 1 needs.
class BundletoolClient {
  const BundletoolClient({
    required this.runner,
    required this.tools,
    required this.jar,
  });

  final BundleProcessRunner runner;
  final JavaTools tools;
  final File jar;

  Future<(bool, String)> validate(String bundlePath) async {
    final result = await runner.run(tools.java, [
      '-jar',
      jar.path,
      'validate',
      '--bundle=$bundlePath',
    ], timeout: const Duration(minutes: 3));
    if (result.missingExecutable) {
      throw const BundleToolException(
        'Không tìm thấy java để chạy bundletool.',
      );
    }
    if (result.exitCode == 0) return (true, '');
    return (false, _lastError(result.output));
  }

  /// Builds one APK that installs on any device, signed with [keystore] or,
  /// without one, bundletool's debug key.
  Future<File> buildUniversalApk({
    required String bundlePath,
    required Directory outputDirectory,
    required String apkFileName,
    KeystoreRef? keystore,
  }) async {
    await outputDirectory.create(recursive: true);
    final apks = File(p.join(outputDirectory.path, 'universal.apks'));
    final storePass = File(p.join(outputDirectory.path, '.ks-pass'));
    final keyPass = File(p.join(outputDirectory.path, '.key-pass'));
    try {
      if (keystore != null) {
        await storePass.writeAsString(keystore.storePassword, flush: true);
        await keyPass.writeAsString(keystore.keyPassword, flush: true);
      }
      final result = await runner.run(tools.java, [
        '-jar',
        jar.path,
        'build-apks',
        '--bundle=$bundlePath',
        '--output=${apks.path}',
        '--mode=universal',
        '--overwrite',
        if (keystore != null) ...[
          '--ks=${keystore.path}',
          '--ks-key-alias=${keystore.alias}',
          '--ks-pass=file:${storePass.path}',
          '--key-pass=file:${keyPass.path}',
        ],
      ], timeout: const Duration(minutes: 10));
      if (result.missingExecutable) {
        throw const BundleToolException(
          'Không tìm thấy java để chạy bundletool.',
        );
      }
      if (result.exitCode != 0) {
        throw BundleToolException(
          'bundletool build-apks lỗi: ${_lastError(result.output)}',
        );
      }
      final target = File(p.join(outputDirectory.path, apkFileName));
      final zip = await BundleZip.open(apks.path);
      try {
        final entry = zip.entry('universal.apk');
        if (entry == null) {
          throw const BundleToolException('File .apks không có universal.apk.');
        }
        await target.writeAsBytes(
          await zip.read(entry, maxBytes: 2 * 1024 * 1024 * 1024),
          flush: true,
        );
      } finally {
        await zip.close();
      }
      return target;
    } finally {
      for (final file in [storePass, keyPass, apks]) {
        if (file.existsSync()) await file.delete();
      }
    }
  }

  /// APKs for exactly the connected device [serial], as Play would serve it.
  Future<File> buildDeviceApks({
    required String bundlePath,
    required File output,
    required String serial,
    required String adb,
    KeystoreRef? keystore,
  }) async {
    await output.parent.create(recursive: true);
    final storePass = File('${output.path}.ks-pass');
    final keyPass = File('${output.path}.key-pass');
    try {
      if (keystore != null) {
        await storePass.writeAsString(keystore.storePassword, flush: true);
        await keyPass.writeAsString(keystore.keyPassword, flush: true);
      }
      final result = await runner.run(tools.java, [
        '-jar',
        jar.path,
        'build-apks',
        '--bundle=$bundlePath',
        '--output=${output.path}',
        '--overwrite',
        '--connected-device',
        '--device-id=$serial',
        '--adb=$adb',
        if (keystore != null) ...[
          '--ks=${keystore.path}',
          '--ks-key-alias=${keystore.alias}',
          '--ks-pass=file:${storePass.path}',
          '--key-pass=file:${keyPass.path}',
        ],
      ], timeout: const Duration(minutes: 10));
      if (result.missingExecutable) {
        throw const BundleToolException(
          'Không tìm thấy java để chạy bundletool.',
        );
      }
      if (result.exitCode != 0 || !output.existsSync()) {
        throw BundleToolException(lastError(result.output));
      }
      return output;
    } finally {
      for (final file in [storePass, keyPass]) {
        if (file.existsSync()) await file.delete();
      }
    }
  }

  /// Installs an APK set; returns bundletool's output so the caller can read
  /// an `INSTALL_FAILED_*` reason out of it.
  Future<BundleProcessResult> installApks({
    required File apks,
    required String serial,
    required String adb,
  }) {
    return runner.run(tools.java, [
      '-jar',
      jar.path,
      'install-apks',
      '--apks=${apks.path}',
      '--device-id=$serial',
      '--adb=$adb',
      '--allow-downgrade',
    ], timeout: const Duration(minutes: 5));
  }

  static String lastError(String output) => _lastError(output);

  static String _lastError(String output) {
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final error = lines.lastWhere(
      (line) => line.contains('Error') || line.contains('Exception'),
      orElse: () => lines.isEmpty ? '' : lines.last,
    );
    return error.length > 400 ? '${error.substring(0, 400)}…' : error;
  }
}
