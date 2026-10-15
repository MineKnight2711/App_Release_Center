import 'dart:convert';

/// Keeps progress in order and leaves room for the result in relay requests.
class RemoteCommandPublisher {
  RemoteCommandPublisher({required this.send});

  final Future<void> Function(String commandId, Map<String, Object?> body) send;
  Future<void> _pending = Future<void>.value();

  Future<void> publish(String commandId, Map<String, Object?> body) {
    final snapshot = {
      ...body,
      'logLines': logTail((body['logLines'] as List<String>?) ?? const []),
    };
    final terminal = !const [
      'running',
      'claimed',
      'queued',
    ].contains(body['status']);
    final sent = _pending.then((_) async {
      for (var attempt = 0; ; attempt++) {
        try {
          await send(commandId, snapshot);
          return;
        } catch (_) {
          if (!terminal || attempt == 2) rethrow;
          await Future<void>.delayed(Duration(seconds: attempt + 1));
        }
      }
    });
    // One failed request must not prevent the terminal result from going out.
    _pending = sent.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return sent;
  }

  /// Git's NUL-separated file list can be a single enormous log line. A line
  /// count alone does not bound the JSON request size, especially with UTF-8
  /// and escaped control characters. Full command logs remain on the Mac.
  static List<String> logTail(List<String> lines) {
    const maxBytes = 24 * 1024;
    const suffix = '… [log đã rút gọn]';
    final tail = <String>[];
    var bytes = 2; // JSON array brackets.
    for (final line in lines.reversed.take(500)) {
      final shortened = String.fromCharCodes(line.runes.take(2000));
      final value = shortened.length < line.length ? '$shortened$suffix' : line;
      final size = utf8.encode(jsonEncode(value)).length + 1;
      if (bytes + size > maxBytes) break;
      tail.add(value);
      bytes += size;
    }
    return tail.reversed.toList();
  }
}
