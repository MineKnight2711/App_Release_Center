import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// The Node relay, run for real.
class RelayProcess {
  RelayProcess(
    this.process,
    this.baseUrl,
    this.desktopToken,
    this.stateDirectory,
  ) {
    // Wrangler is chatty, and a child whose pipes nobody reads blocks once the
    // buffer fills — which looks exactly like a server that never starts.
    process.stdout.transform(utf8.decoder).listen(_remember);
    process.stderr.transform(utf8.decoder).listen(_remember);
  }

  final Process process;
  final String baseUrl;
  final String desktopToken;
  final Directory stateDirectory;
  final _output = <String>[];

  void _remember(String chunk) {
    _output.add(chunk);
    if (_output.length > 200) _output.removeAt(0);
  }

  String get _tail => _output.join().trimRight();

  static const _projectDirectory = 'serverless/notifications';

  static bool isAvailable() {
    return File('$_projectDirectory/wrangler.toml').existsSync() &&
        File(_wranglerBinary).existsSync();
  }

  /// The locally installed wrangler, not one resolved through npx: the tests
  /// must run the version the project pins, and npx would go to the network.
  ///
  /// Absolute because Windows runs this through cmd, which reads a path with
  /// forward slashes as a command followed by arguments.
  static String get _wranglerBinary {
    final suffix = Platform.isWindows ? '.cmd' : '';
    return File(
      '$_projectDirectory/node_modules/.bin/wrangler$suffix',
    ).absolute.path;
  }

  static Future<RelayProcess> start({required String desktopToken}) async {
    final port = await _freePort();
    // Its own D1 state directory, so a previous run cannot leave rows behind
    // and nothing here can reach the deployed database.
    final stateDirectory = Directory.systemTemp.createTempSync('amc-relay-');

    final schema = await Process.run(
      _wranglerBinary,
      [
        'd1',
        'execute',
        'amc-relay',
        '--local',
        '--persist-to',
        stateDirectory.path,
        '--file',
        'worker/schema.sql',
      ],
      workingDirectory: _projectDirectory,
      runInShell: Platform.isWindows,
    );
    if (schema.exitCode != 0) {
      throw StateError(
        'Could not create the local D1 schema: ${schema.stderr}',
      );
    }

    final process = await Process.start(
      _wranglerBinary,
      [
        'dev',
        '--local',
        '--port',
        '$port',
        '--persist-to',
        stateDirectory.path,
        '--var',
        'DESKTOP_API_TOKEN:$desktopToken',
      ],
      workingDirectory: _projectDirectory,
      runInShell: Platform.isWindows,
    );

    final relay = RelayProcess(
      process,
      'http://127.0.0.1:$port/api',
      desktopToken,
      stateDirectory,
    );
    await relay._waitUntilListening();
    return relay;
  }

  Future<void> _waitUntilListening() async {
    // Wrangler has a workerd runtime to boot, so this is slower than a bare
    // Node process and the window has to allow for it.
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final response = await http
            .get(
              Uri.parse('$baseUrl/config'),
              headers: const {'User-Agent': 'amc-e2e/1.0'},
            )
            .timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) return;
      } catch (_) {
        // Not up yet.
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    final output = _tail;
    await stop();
    throw StateError('Wrangler did not start listening.\n$output');
  }

  Future<void> stop() async {
    // Wrangler spawns workerd as a child, and killing only the parent leaves
    // it holding the port.
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/pid', '${process.pid}', '/T', '/F']);
    } else {
      process.kill();
    }
    await process.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () => -1,
    );
    try {
      if (stateDirectory.existsSync()) {
        stateDirectory.deleteSync(recursive: true);
      }
    } catch (_) {
      // Windows sometimes still holds a handle; a temp directory left behind
      // is not worth failing a test run over.
    }
  }

  Map<String, String> get desktopHeaders => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $desktopToken',
  };

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }
}
