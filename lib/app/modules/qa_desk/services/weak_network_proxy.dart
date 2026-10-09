import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// `0,5` for half a kilobyte, `8` for eight: how people write these rates.
String kilobytes(int bytes) {
  final value = bytes / 1024;
  return value == value.roundToDouble()
      ? value.round().toString()
      : value.toString().replaceAll('.', ',');
}

class NetworkProfile {
  const NetworkProfile(this.name, this.bytesPerSecond, this.latencyMs);
  final String name;
  final int bytesPerSecond;
  final int latencyMs;
  String get description =>
      '$name · ${kilobytes(bytesPerSecond)} KB/s mỗi chiều · trễ $latencyMs ms';
  static const presets = [
    NetworkProfile('Siêu yếu', 512, 2000),
    NetworkProfile('Rất yếu', 2048, 1500),
    NetworkProfile('Yếu', 8192, 800),
    NetworkProfile('Chậm', 32768, 400),
  ];
}

/// Loopback-only forward proxy. HTTPS is an opaque CONNECT tunnel, no MITM.
/// Rates apply to all forwarded bytes per connection/direction (including TLS).
class WeakNetworkProxy {
  WeakNetworkProxy(this.profile);
  final NetworkProfile profile;
  ServerSocket? _server;
  final _closed = Completer<void>();
  final _sockets = <Socket>{};
  int connections = 0;
  int uploaded = 0;
  int downloaded = 0;
  int get port => _server!.port;
  String get url => 'http://127.0.0.1:$port';

  Future<void> start() async {
    if (profile.bytesPerSecond <= 0 || profile.latencyMs < 0) {
      throw ArgumentError('Cấu hình mạng không hợp lệ.');
    }
    if (_server != null || _closed.isCompleted) {
      throw StateError('Proxy đã khởi động hoặc đóng.');
    }
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    if (_closed.isCompleted) {
      await server.close();
      return;
    }
    _server = server;
    server.listen((socket) {
      _sockets.add(socket);
      unawaited(_handle(socket));
    });
  }

  Future<void> stop() async {
    if (!_closed.isCompleted) _closed.complete();
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    await _server?.close();
  }

  Future<bool> _wait(Duration duration) async {
    if (_closed.isCompleted) return false;
    final done = Completer<void>();
    final timer = Timer(duration, done.complete);
    try {
      await Future.any([done.future, _closed.future]);
      return !_closed.isCompleted;
    } finally {
      timer.cancel();
    }
  }

  Stream<List<int>> _paced(
    Stream<List<int>> input, {
    required bool upload,
  }) async* {
    final chunkSize = max(1, min(4096, profile.bytesPerSecond ~/ 10));
    await for (final data in input) {
      for (var offset = 0; offset < data.length; offset += chunkSize) {
        final chunk = data.sublist(
          offset,
          min(data.length, offset + chunkSize),
        );
        if (!await _wait(
          Duration(
            microseconds: (chunk.length * 1000000 / profile.bytesPerSecond)
                .ceil(),
          ),
        )) {
          return;
        }
        if (upload) {
          uploaded += chunk.length;
        } else {
          downloaded += chunk.length;
        }
        yield chunk;
      }
    }
  }

  Stream<List<int>> _remaining(
    StreamIterator<List<int>> reader,
    List<int> initial,
  ) async* {
    if (initial.isNotEmpty) yield initial;
    while (await reader.moveNext()) {
      yield reader.current;
    }
  }

  Future<void> _handle(Socket downstream) async {
    final reader = StreamIterator<List<int>>(downstream);
    Socket? upstream;
    var connected = false;
    try {
      // Parse only the proxy handshake; the remaining stream is forwarded raw.
      // A raw parser also accepts CONNECT with numeric IPs and IPv6 authorities.
      final buffer = <int>[];
      var end = -1;
      final deadline = Stopwatch()..start();
      while (end < 0) {
        final remaining = const Duration(seconds: 10) - deadline.elapsed;
        if (remaining.isNegative ||
            !await reader.moveNext().timeout(remaining)) {
          throw const FormatException('Incomplete proxy headers');
        }
        final start = max(0, buffer.length - 3);
        buffer.addAll(reader.current);
        for (var i = start; i + 3 < buffer.length; i++) {
          if (buffer[i] == 13 &&
              buffer[i + 1] == 10 &&
              buffer[i + 2] == 13 &&
              buffer[i + 3] == 10) {
            end = i + 4;
            break;
          }
        }
        if ((end < 0 && buffer.length > 65536) || end > 65536) {
          throw const FormatException('Proxy headers too large');
        }
      }
      final lines = latin1.decode(buffer.sublist(0, end - 4)).split('\r\n');
      final first = lines.first.split(' ');
      if (first.length != 3) {
        throw const FormatException('Invalid request line');
      }
      final tunnel = first[0] == 'CONNECT';
      final target = Uri.parse(tunnel ? 'http://${first[1]}' : first[1]);
      if (target.scheme != 'http' ||
          target.host.isEmpty ||
          target.userInfo.isNotEmpty ||
          target.port <= 0 ||
          target.port > 65535) {
        throw const FormatException('Invalid target');
      }
      if (target.port == port &&
          ['localhost', '127.0.0.1', '::1'].contains(target.host)) {
        throw const FormatException('Proxy loop');
      }
      connections++;
      if (!await _wait(Duration(milliseconds: profile.latencyMs))) return;
      upstream = await Socket.connect(
        target.host,
        target.port,
        timeout: const Duration(seconds: 15),
      );
      if (_closed.isCompleted) return;
      _sockets.add(upstream);
      var initial = buffer.sublist(end);
      if (tunnel) {
        downstream.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        await downstream.flush();
      } else {
        // Force a single HTTP request per connection; HTTPS can reuse its tunnel.
        final path =
            '${target.path.isEmpty ? '/' : target.path}${target.hasQuery ? '?${target.query}' : ''}';
        final headers = lines.skip(1).where((line) {
          final name = line.split(':').first.toLowerCase();
          return ![
            'host',
            'connection',
            'proxy-connection',
            'proxy-authorization',
          ].contains(name);
        });
        initial = [
          ...latin1.encode(
            '${first[0]} $path ${first[2]}\r\nHost: ${target.authority}\r\nConnection: close\r\n${headers.map((line) => '$line\r\n').join()}\r\n',
          ),
          ...initial,
        ];
      }
      connected = true;
      Future<void> forward(
        Stream<List<int>> input,
        Socket output,
        bool upload,
      ) async {
        try {
          await output.addStream(_paced(input, upload: upload));
          await output.flush();
        } on Object {
          /* The peer may cancel or time out. */
        } finally {
          upstream?.destroy();
          downstream.destroy();
        }
      }

      await Future.wait([
        forward(_remaining(reader, initial), upstream, true),
        forward(upstream, downstream, false),
      ]);
    } on Object {
      if (!connected && !_closed.isCompleted) {
        try {
          downstream.write(
            'HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n',
          );
          await downstream.flush();
        } on Object {
          /* Client already closed. */
        }
      }
    } finally {
      upstream?.destroy();
      downstream.destroy();
      _sockets.remove(upstream);
      _sockets.remove(downstream);
      await reader.cancel();
    }
  }
}
