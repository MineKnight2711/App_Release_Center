import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef DetachedStarter =
    Future<bool> Function(
      String executable,
      List<String> arguments,
      Map<String, String> environment,
    );

typedef ServerProbe = Future<bool> Function(Uri url);

class LocalBotServerException implements Exception {
  const LocalBotServerException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Starts `telegram-bot-api` in `--local` mode when it is not already up.
///
/// It listens on 127.0.0.1 only: anyone who can reach the port could act as
/// the bot with its token. api_id and api_hash travel through the
/// environment variables the server reads, never on its command line. The
/// server is left running when AMC exits, so release notifications from a
/// later session still have somewhere to go.
class LocalBotServer {
  LocalBotServer({
    DetachedStarter? start,
    ServerProbe? probe,
    Future<void> Function(Duration)? sleep,
  }) : _start = start ?? _startDetached,
       _probe = probe ?? isHttpServerUp,
       _sleep = sleep ?? Future<void>.delayed;

  final DetachedStarter _start;
  final ServerProbe _probe;
  final Future<void> Function(Duration) _sleep;

  Future<bool> isUp(int port) => _probe(Uri.parse('http://127.0.0.1:$port/'));

  /// Returns once the server answers on [port], starting it when needed.
  /// True when this call started it.
  Future<bool> ensureRunning({
    required String executable,
    required int port,
    required Directory workDirectory,
    required String apiId,
    required String apiHash,
    Duration startupTimeout = const Duration(seconds: 20),
  }) async {
    if (await isUp(port)) return false;
    if (executable.trim().isEmpty || !File(executable).existsSync()) {
      throw LocalBotServerException(
        executable.trim().isEmpty
            ? 'Chưa chọn file telegram-bot-api.exe.'
            : 'Không thấy $executable.',
      );
    }
    await Directory(p.join(workDirectory.path, 'temp')).create(recursive: true);
    final started = await _start(
      executable,
      [
        '--local',
        '--http-port=$port',
        '--http-ip-address=127.0.0.1',
        '--dir=${workDirectory.path}',
        '--temp-dir=${p.join(workDirectory.path, 'temp')}',
        '--log=${p.join(workDirectory.path, 'server.log')}',
        '--verbosity=1',
      ],
      {'TELEGRAM_API_ID': apiId, 'TELEGRAM_API_HASH': apiHash},
    );
    if (!started) {
      throw LocalBotServerException('Không chạy được $executable.');
    }
    final deadline = DateTime.now().add(startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await _sleep(const Duration(milliseconds: 500));
      if (await isUp(port)) return true;
    }
    throw LocalBotServerException(
      'Server không trả lời trên cổng $port sau '
      '${startupTimeout.inSeconds} giây. Xem '
      '${p.join(workDirectory.path, 'server.log')}.',
    );
  }

  static Future<bool> _startDetached(
    String executable,
    List<String> arguments,
    Map<String, String> environment,
  ) async {
    try {
      await Process.start(
        executable,
        arguments,
        environment: environment,
        mode: ProcessStartMode.detached,
      );
      return true;
    } on ProcessException {
      return false;
    }
  }
}

/// A server built from source into the usual place, following the official
/// Windows instructions under `%USERPROFILE%\Tools`. Null when absent.
String? findBuiltServerExecutable({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final home = env['USERPROFILE'] ?? env['HOME'];
  if (home == null) return null;
  final exe = Platform.isWindows ? 'telegram-bot-api.exe' : 'telegram-bot-api';
  final path = p.join(
    home,
    'Tools',
    'telegram-bot-api',
    'telegram-bot-api',
    'bin',
    exe,
  );
  return File(path).existsSync() ? path : null;
}

/// Whether anything answers HTTP at [url]. Any status counts: the Bot API
/// server replies 404 to `/`, which still means it is there.
Future<bool> isHttpServerUp(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(url);
    final response = await request.close().timeout(const Duration(seconds: 3));
    await response.drain<void>();
    return true;
  } on SocketException {
    return false;
  } on TimeoutException {
    return false;
  } on HttpException {
    return false;
  } finally {
    client.close(force: true);
  }
}
