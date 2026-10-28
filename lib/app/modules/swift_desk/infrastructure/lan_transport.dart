import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:crypto/crypto.dart';

/// Bounded length-prefixed JSON over TLS. Only signaling goes here; desktop
/// media and input use the authenticated WebRTC session.
class LanConnection implements SignalingTransport {
  LanConnection(this.socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    _subscription = socket.listen(
      _read,
      onError: (Object _) => unawaited(close()),
      onDone: () => unawaited(close()),
    );
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      if (DateTime.now().difference(_lastRead) > const Duration(seconds: 35)) {
        unawaited(close());
      } else if (_sessionId != null) {
        try {
          send(_sessionId!, 'ping');
        } catch (_) {
          unawaited(close());
        }
      }
    });
  }
  static const protocol = 'amc-remote/1';
  final SecureSocket socket;
  final _messages = StreamController<RemoteSignal>.broadcast();
  final _done = Completer<void>();
  late final StreamSubscription<Uint8List> _subscription;
  late final Timer _heartbeat;
  Timer? _frameTimer;
  final _header = Uint8List(4);
  int _headerOffset = 0, _payloadOffset = 0;
  Uint8List? _payload;
  int _sendSequence = 0, _receiveSequence = -1;
  String? _sessionId;
  bool _closed = false;
  DateTime _lastRead = DateTime.now();
  @override
  Stream<RemoteSignal> get messages => _messages.stream;
  @override
  Future<void> get done => _done.future;
  String get remoteAddress => socket.remoteAddress.address;

  static Future<LanConnection> connect(RemoteEndpoint endpoint) async {
    final context = SecurityContext(withTrustedRoots: false)
      ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2;
    bool pinned(X509Certificate cert) =>
        DateTime.now().isAfter(cert.startValidity) &&
        DateTime.now().isBefore(cert.endValidity) &&
        sha256.convert(cert.der).toString() == endpoint.fingerprint;
    final socket = await SecureSocket.connect(
      endpoint.address,
      endpoint.port,
      context: context,
      onBadCertificate: pinned,
      supportedProtocols: [protocol],
      timeout: const Duration(seconds: 8),
    );
    if (socket.peerCertificate == null ||
        !pinned(socket.peerCertificate!) ||
        (socket.selectedProtocol != null &&
            socket.selectedProtocol != protocol)) {
      socket.destroy();
      throw const HandshakeException(
        'Danh tính máy đích không khớp. Hãy ghép lại bằng mã mới.',
      );
    }
    return LanConnection(socket);
  }

  void _read(Uint8List bytes) {
    var offset = 0;
    try {
      while (offset < bytes.length && !_closed) {
        _frameTimer ??= Timer(
          const Duration(seconds: 8),
          () => unawaited(close()),
        );
        if (_payload == null) {
          final count = (4 - _headerOffset).clamp(0, bytes.length - offset);
          _header.setRange(_headerOffset, _headerOffset + count, bytes, offset);
          offset += count;
          _headerOffset += count;
          if (_headerOffset < 4) continue;
          final length = ByteData.sublistView(_header).getUint32(0);
          if (length == 0 || length > RemoteSignal.maxBytes) {
            throw const FormatException('Oversized frame');
          }
          _payload = Uint8List(length);
        }
        final payload = _payload!;
        final count = (payload.length - _payloadOffset).clamp(
          0,
          bytes.length - offset,
        );
        payload.setRange(_payloadOffset, _payloadOffset + count, bytes, offset);
        offset += count;
        _payloadOffset += count;
        if (_payloadOffset != payload.length) continue;
        final signal = RemoteSignal.decode(utf8.decode(payload));
        if (signal.sequence != _receiveSequence + 1 ||
            (_sessionId != null && signal.sessionId != _sessionId)) {
          throw const FormatException('Replayed or foreign signaling');
        }
        _sessionId ??= signal.sessionId;
        _receiveSequence = signal.sequence;
        _lastRead = DateTime.now();
        _headerOffset = _payloadOffset = 0;
        _payload = null;
        _frameTimer?.cancel();
        _frameTimer = null;
        if (signal.kind == 'ping') {
          send(signal.sessionId, 'pong');
        } else if (signal.kind != 'pong') {
          _messages.add(signal);
        }
      }
    } catch (_) {
      unawaited(close());
    }
  }

  @override
  void send(
    String sessionId,
    String kind, [
    Map<String, dynamic> data = const {},
  ]) {
    if (_closed) throw StateError('Kết nối đã đóng.');
    if (_sessionId != null && _sessionId != sessionId) {
      throw StateError('Sai phiên signaling.');
    }
    _sessionId = sessionId;
    final bytes = utf8.encode(
      RemoteSignal(
        sessionId: sessionId,
        sequence: _sendSequence++,
        kind: kind,
        data: data,
      ).encode(),
    );
    if (bytes.length > RemoteSignal.maxBytes) {
      throw const FormatException('Signaling quá lớn.');
    }
    final header = ByteData(4)..setUint32(0, bytes.length);
    socket.add(header.buffer.asUint8List());
    socket.add(bytes);
  }

  @override
  Future<void> close() async {
    if (_closed) return done;
    _closed = true;
    _heartbeat.cancel();
    _frameTimer?.cancel();
    try {
      await socket.flush().timeout(const Duration(milliseconds: 500));
    } catch (_) {}
    socket.destroy();
    await _subscription.cancel();
    if (!_done.isCompleted) _done.complete();
    // A paused observer must not prevent socket teardown or host revocation.
    unawaited(_messages.close());
  }
}
