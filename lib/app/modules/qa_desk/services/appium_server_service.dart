import 'dart:async';
import 'dart:io';

import '../models/qa_models.dart';
import 'safe_process_runner.dart';

enum AppiumStatus { unavailable, stopped, starting, running, error }

class AppiumServerService {
  AppiumServerService([this._processRunner = const SafeProcessRunner()]);

  final SafeProcessRunner _processRunner;
  RunningProcess? _process;
  bool _intentionalStop = false;

  bool get isRunning => _process != null;

  Future<bool> isInstalled() async {
    final result = await Process.run(
      Platform.isWindows ? 'where.exe' : 'which',
      ['appium'],
      runInShell: false,
    );
    return result.exitCode == 0;
  }

  Future<String?> start({
    required int port,
    required String workingDirectory,
    required void Function(String line) onLog,
  }) async {
    if (_process != null) return null;
    if (!await isInstalled()) {
      return 'Không tìm thấy Appium trong PATH. Cài bằng: npm install -g appium';
    }

    try {
      _intentionalStop = false;
      final running = await _processRunner.start(
        suite: QaSuite(
          id: 'appium-server',
          name: 'Appium Server',
          executable: 'appium',
          arguments: ['--port', '$port'],
        ),
        workingDirectory: workingDirectory,
      );
      _process = running;
      var exited = false;
      int? earlyExitCode;
      unawaited(
        running.output.forEach(onLog).catchError((Object error) {
          onLog('Appium output error: $error');
        }),
      );
      unawaited(
        running.exitCode.then((code) {
          exited = true;
          earlyExitCode = code;
          _process = null;
          onLog(
            _intentionalStop
                ? 'Appium stopped.'
                : 'Appium exited with code $code.',
          );
        }),
      );
      final ready = await _waitUntilReady(port, () => exited);
      if (exited) return 'Appium dừng sớm với exit code $earlyExitCode.';
      if (!ready) {
        await stop();
        return 'Appium không phản hồi tại http://127.0.0.1:$port/status.';
      }
      return null;
    } on Object catch (error) {
      _process = null;
      return 'Không thể khởi động Appium: $error';
    }
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    _intentionalStop = true;
    if (process != null) await process.stop();
  }

  Future<bool> _waitUntilReady(int port, bool Function() hasExited) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!hasExited() && DateTime.now().isBefore(deadline)) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 1);
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/status'),
        );
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == HttpStatus.ok) return true;
      } on Object {
        // Server is still booting.
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }
}
