import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../../bundle_check/services/android_toolchain.dart';
import 'safe_process_runner.dart';

class MaestroException implements Exception {
  const MaestroException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Whether Maestro can run on this machine, and what is missing if not.
class MaestroStatus {
  const MaestroStatus({
    required this.installed,
    required this.javaVersion,
    this.javaHome,
    this.java = '',
  });

  final bool installed;

  /// Major version of the Java found, 0 when none.
  final int javaVersion;

  /// Set when Java was found outside PATH and must be handed to Maestro.
  final String? javaHome;

  /// Absolute path of the `java` that runs Maestro.
  final String java;

  bool get javaOk => javaVersion >= MaestroManager.minimumJava;
  bool get ready => installed && javaOk;

  /// What stands in the way, for the setup card.
  String? get problem {
    if (!installed) return 'Chưa tải Maestro.';
    if (javaVersion == 0) {
      return 'Không tìm thấy Java. Maestro cần Java '
          '${MaestroManager.minimumJava} trở lên.';
    }
    if (!javaOk) {
      return 'Java $javaVersion quá cũ; Maestro cần Java '
          '${MaestroManager.minimumJava} trở lên.';
    }
    return null;
  }
}

/// The pinned Maestro CLI: one version, verified by size and SHA-256 before
/// it is unpacked, kept outside PATH in AMC's own folder.
///
/// Lives next to `qa_desk/`, not inside it: the one-time import of the
/// standalone app's data only runs into an empty `qa_desk/`.
class MaestroManager {
  MaestroManager({required this.toolsDirectory, HttpClient Function()? http})
    : _http = http ?? HttpClient.new;

  static const version = '2.11.0';
  static const sha256 =
      '5384593cb4e7a106489e75a821d157dd43f4e438df6bc308b72e82c685e1283a';
  static const sizeBytes = 314886578;
  static const minimumJava = 17;
  static final downloadUrl = Uri.parse(
    'https://github.com/mobile-dev-inc/Maestro/releases/download/'
    'cli-$version/maestro.zip',
  );

  static Future<MaestroManager> forApp() async => MaestroManager(
    toolsDirectory: Directory(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'qa_desk_tools',
        'maestro',
      ),
    ),
  );

  final Directory toolsDirectory;
  final HttpClient Function() _http;

  Directory get installDirectory =>
      Directory(p.join(toolsDirectory.path, version));

  /// `maestro.bat` on Windows, the shell launcher elsewhere.
  File get executable => File(
    p.join(
      installDirectory.path,
      'maestro',
      'bin',
      Platform.isWindows ? 'maestro.bat' : 'maestro',
    ),
  );

  bool get isInstalled => executable.existsSync();

  Directory get _libraries =>
      Directory(p.join(installDirectory.path, 'maestro', 'lib'));

  Future<MaestroStatus> status() async {
    final located = JavaTools.locate().java;
    final java = located == 'java' ? await _onPath('java') : located;
    final major = java == null ? 0 : await javaMajorVersion(java);
    return MaestroStatus(
      installed: isInstalled,
      javaVersion: major,
      javaHome: java == null || located == 'java'
          ? null
          : p.dirname(p.dirname(java)),
      java: java ?? '',
    );
  }

  /// Maestro as the command its launcher script would run. Starting Java
  /// directly keeps `cmd.exe` out: Dart does not quote a batch file's own
  /// path, and AMC's folder name has spaces in it.
  ManagedTool? command(MaestroStatus status) {
    if (!status.ready || status.java.isEmpty) return null;
    return ManagedTool(
      executable: status.java,
      prefix: [
        // Piped, Java writes in the Windows ANSI code page (Cp1252 here), so
        // a flow named "Đăng nhập và…" reached QA Desk as bytes that are not
        // UTF-8. `stdout.encoding` is Java 19+, `sun.stdout.encoding` 17–18;
        // `file.encoding` keeps Maestro's own logs UTF-8 on Java 17.
        '-Dstdout.encoding=UTF-8',
        '-Dstderr.encoding=UTF-8',
        '-Dsun.stdout.encoding=UTF-8',
        '-Dsun.stderr.encoding=UTF-8',
        '-Dfile.encoding=UTF-8',
        '--enable-native-access=ALL-UNNAMED',
        '-classpath',
        p.join(_libraries.path, '*'),
        'maestro.cli.AppKt',
      ],
    );
  }

  static Future<String?> _onPath(String name) async {
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where.exe' : 'which',
        [name],
      );
      if (result.exitCode != 0) return null;
      final lines = result.stdout
          .toString()
          .split(RegExp(r'[\r\n]+'))
          .where((line) => line.trim().isNotEmpty);
      return lines.isEmpty ? null : lines.first.trim();
    } on ProcessException {
      return null;
    }
  }

  /// The variables Maestro needs to start: Java, and no analytics prompt.
  Map<String, String> environment(MaestroStatus status) => {
    'MAESTRO_CLI_NO_ANALYTICS': '1',
    'MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED': 'true',
    if (status.javaHome != null) 'JAVA_HOME': status.javaHome!,
  };

  /// Reads `java -version`, which prints to stderr; 0 when Java is missing.
  static Future<int> javaMajorVersion(String java) async {
    try {
      final result = await Process.run(java, ['-version']);
      return parseJavaMajor('${result.stderr}\n${result.stdout}');
    } on ProcessException {
      return 0;
    }
  }

  /// `version "21.0.7"` → 21; `version "1.8.0_402"` → 8.
  static int parseJavaMajor(String output) {
    final match = RegExp(r'version "(\d+)(?:\.(\d+))?').firstMatch(output);
    if (match == null) return 0;
    final first = int.parse(match[1]!);
    if (first == 1 && match[2] != null) return int.parse(match[2]!);
    return first;
  }

  /// Downloads, checks size and SHA-256, then unpacks into a staging folder
  /// renamed into place. A bad or partial download is never unpacked.
  Future<void> install({
    void Function(int received, int total)? onProgress,
    void Function(String step)? onStep,
  }) async {
    await toolsDirectory.create(recursive: true);
    final archive = File(p.join(toolsDirectory.path, 'maestro-$version.zip'));
    final partial = File('${archive.path}.part');
    final staging = Directory('${installDirectory.path}.unpacking');
    final client = _http()..connectionTimeout = const Duration(seconds: 20);
    try {
      onStep?.call('Đang tải Maestro $version');
      final request = await client.getUrl(downloadUrl);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw MaestroException('Tải Maestro lỗi HTTP ${response.statusCode}.');
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
            throw const MaestroException('File tải về lớn hơn dự kiến.');
          }
          onProgress?.call(received, sizeBytes);
        }
      } finally {
        await sink.close();
      }
      final out = Uint8List(digest.digestSize);
      digest.doFinal(out, 0);
      final hash = out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      if (received != sizeBytes || hash != sha256) {
        throw const MaestroException(
          'Maestro tải về không khớp SHA-256, đã bỏ file.',
        );
      }
      if (archive.existsSync()) await archive.delete();
      await partial.rename(archive.path);

      onStep?.call('Đang giải nén Maestro');
      if (staging.existsSync()) await staging.delete(recursive: true);
      final zipPath = archive.path;
      final stagingPath = staging.path;
      // 300 MB of zip: off the UI isolate.
      await Isolate.run(() => extractFileToDisk(zipPath, stagingPath));
      final launcher = File(
        p.join(
          staging.path,
          'maestro',
          'bin',
          Platform.isWindows ? 'maestro.bat' : 'maestro',
        ),
      );
      if (!launcher.existsSync()) {
        throw const MaestroException(
          'Gói Maestro không có file chạy như mong đợi.',
        );
      }
      if (installDirectory.existsSync()) {
        await installDirectory.delete(recursive: true);
      }
      await staging.rename(installDirectory.path);
      await archive.delete();
    } on SocketException catch (error) {
      throw MaestroException('Lỗi mạng khi tải Maestro: ${error.message}');
    } on TimeoutException {
      throw const MaestroException('Tải Maestro quá hạn.');
    } on HttpException catch (error) {
      throw MaestroException('Tải Maestro lỗi: ${error.message}');
    } finally {
      client.close(force: true);
      for (final leftover in [partial]) {
        if (leftover.existsSync()) {
          try {
            await leftover.delete();
          } on FileSystemException {
            // Retried on the next install.
          }
        }
      }
      if (staging.existsSync()) {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException {
          // Retried on the next install.
        }
      }
    }
  }
}
