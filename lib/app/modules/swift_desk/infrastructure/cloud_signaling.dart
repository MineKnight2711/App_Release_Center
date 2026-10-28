import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:cryptography/cryptography.dart' as crypt;
import 'package:pointycastle/export.dart' as pc;
import 'lan_identity.dart';

/// A pinned host certificate wraps a fresh AES-256-GCM secret. The relay sees
/// routing IDs and opaque ciphertext only, including for remembered tokens.
class CloudSignalingTransport implements SignalingTransport {
  CloudSignalingTransport._(this.sessionId, this.host, this.emit, this.closed);
  final String sessionId;
  final bool host;
  final void Function(String payload) emit;
  final Future<void> Function() closed;
  final _messages = StreamController<RemoteSignal>();
  Stream<RemoteSignal>? _broadcast;
  final _done = Completer<void>(), _ready = Completer<void>();
  final _aes = crypt.AesGcm.with256bits();
  crypt.SecretKey? _out, _in;
  Future<void> _readTail = Future.value(), _writeTail = Future.value();
  Timer? _deadline;
  bool _closing = false, _draining = false;
  int _send = 0, _receive = -1;
  @override
  Stream<RemoteSignal> get messages =>
      _broadcast ??= _messages.stream.asBroadcastStream();
  @override
  Future<void> get done => _done.future;
  Future<void> get ready => _ready.future;

  static Future<CloudSignalingTransport> viewer({
    required String sessionId,
    required String certificate,
    required String fingerprint,
    required void Function(String) emit,
    required Future<void> Function() closed,
  }) async {
    final certHash = LanIdentity(
      id: 'unused',
      certificate: certificate,
      privateKey: '',
    ).fingerprint;
    if (certHash != fingerprint) {
      throw const FormatException('Chứng chỉ Internet không khớp.');
    }
    final cert = X509Utils.x509CertificateFromPem(certificate).tbsCertificate!;
    if (!cert.validity.notAfter.isAfter(DateTime.now()) ||
        cert.validity.notBefore.isAfter(DateTime.now())) {
      throw const FormatException('Chứng chỉ Internet hết hạn.');
    }
    final transport = CloudSignalingTransport._(sessionId, false, emit, closed);
    final secret = base64Url.decode('${remoteToken()}=');
    await transport._keys(secret);
    final hex = cert.subjectPublicKeyInfo.bytes!;
    final key = CryptoUtils.rsaPublicKeyFromDERBytes(
      Uint8List.fromList([
        for (var offset = 0; offset < hex.length; offset += 2)
          int.parse(hex.substring(offset, offset + 2), radix: 16),
      ]),
    );
    final rsa = pc.OAEPEncoding.withSHA256(pc.RSAEngine())
      ..init(true, pc.PublicKeyParameter<pc.RSAPublicKey>(key));
    emit(
      jsonEncode({
        'key': base64.encode(rsa.process(Uint8List.fromList(secret))),
      }),
    );
    transport._ready.complete();
    return transport;
  }

  static CloudSignalingTransport receiver({
    required String sessionId,
    required LanIdentity identity,
    required void Function(String) emit,
    required Future<void> Function() closed,
  }) {
    final transport = CloudSignalingTransport._(sessionId, true, emit, closed);
    transport._identity = identity;
    transport._deadline = Timer(
      const Duration(seconds: 8),
      () => unawaited(transport.close()),
    );
    return transport;
  }

  LanIdentity? _identity;
  Future<void> _keys(List<int> secret) async {
    if (secret.length != 32) throw const FormatException('Invalid session key');
    final hkdf = crypt.Hkdf(hmac: crypt.Hmac.sha256(), outputLength: 32);
    Future<crypt.SecretKey> derive(String direction) => hkdf.deriveKey(
      secretKey: crypt.SecretKey(secret),
      nonce: utf8.encode(sessionId),
      info: utf8.encode('amc-desktop-v1:$direction'),
    );
    _out = await derive(host ? 'host' : 'viewer');
    _in = await derive(host ? 'viewer' : 'host');
  }

  void receive(String payload) {
    _readTail = _readTail
        .then<void>((_) async {
          if (_closing || payload.length > 360000) {
            throw const FormatException('Invalid encrypted frame');
          }
          final value = jsonDecode(payload) as Map<String, dynamic>;
          if (_in == null) {
            if (!host ||
                value.length != 1 ||
                (value['key'] as String).length > 1024) {
              throw const FormatException('Invalid key frame');
            }
            final rsa = pc.OAEPEncoding.withSHA256(pc.RSAEngine())
              ..init(
                false,
                pc.PrivateKeyParameter<pc.RSAPrivateKey>(
                  CryptoUtils.rsaPrivateKeyFromPem(_identity!.privateKey),
                ),
              );
            await _keys(rsa.process(base64.decode(value['key'] as String)));
            _identity = null;
            _deadline?.cancel();
            _ready.complete();
            return;
          }
          if (value['seq'] != _receive + 1) {
            throw const FormatException('Replayed encrypted frame');
          }
          final seq = value['seq'] as int;
          final bytes = base64.decode(value['box'] as String);
          if (bytes.length < 28 || bytes.length > RemoteSignal.maxBytes + 28) {
            throw const FormatException('Invalid ciphertext size');
          }
          final box = crypt.SecretBox(
            bytes.sublist(12, bytes.length - 16),
            nonce: bytes.sublist(0, 12),
            mac: crypt.Mac(bytes.sublist(bytes.length - 16)),
          );
          final plaintext = await _aes.decrypt(
            box,
            secretKey: _in!,
            aad: utf8.encode('$sessionId:$seq'),
          );
          final signal = RemoteSignal.decode(utf8.decode(plaintext));
          if (signal.sessionId != sessionId || signal.sequence != seq) {
            throw const FormatException('Foreign signaling');
          }
          _receive = seq;
          _messages.add(signal);
        })
        .catchError((Object _) {
          unawaited(_close(flush: false));
        });
  }

  @override
  void send(String id, String kind, [Map<String, dynamic> data = const {}]) {
    if (_closing || _draining || id != sessionId) {
      throw StateError('Phiên Internet đã đóng.');
    }
    final seq = _send++;
    final bytes = utf8.encode(
      RemoteSignal(
        sessionId: id,
        sequence: seq,
        kind: kind,
        data: data,
      ).encode(),
    );
    if (bytes.length > RemoteSignal.maxBytes) {
      throw const FormatException('Signaling quá lớn.');
    }
    _writeTail = _writeTail
        .then<void>((_) async {
          await ready;
          if (_closing) return;
          final box = await _aes.encrypt(
            bytes,
            secretKey: _out!,
            aad: utf8.encode('$sessionId:$seq'),
          );
          if (!_closing) {
            emit(
              jsonEncode({
                'seq': seq,
                'box': base64.encode([
                  ...box.nonce,
                  ...box.cipherText,
                  ...box.mac.bytes,
                ]),
              }),
            );
          }
        })
        .catchError((Object _) {
          unawaited(_close(flush: false));
        });
  }

  @override
  Future<void> close() => _close(flush: true);
  Future<void> _close({required bool flush}) async {
    if (_closing || _draining) return done;
    _draining = true;
    if (flush) {
      try {
        await Future.wait([
          _writeTail,
          _readTail,
        ]).timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    }
    _closing = true;
    _deadline?.cancel();
    _identity = null;
    if (!_ready.isCompleted) _ready.complete();
    try {
      await closed();
    } catch (_) {}
    if (!_done.isCompleted) _done.complete();
    unawaited(_messages.close());
  }
}

class DesktopCloudApi {
  DesktopCloudApi(
    this.baseUrl,
    this.readToken, {
    HttpClient? client,
    this.allowLocalTest = false,
  }) : _client = client ?? HttpClient() {
    if (baseUrl.scheme != 'https' &&
        !(allowLocalTest &&
            baseUrl.scheme == 'http' &&
            baseUrl.host == '127.0.0.1')) {
      throw const FormatException('Internet desktop cần API HTTPS.');
    }
    if (baseUrl.userInfo.isNotEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment) {
      throw const FormatException('API URL không hợp lệ.');
    }
  }
  final Uri baseUrl;
  final Future<String?> Function() readToken;
  final HttpClient _client;
  final bool allowLocalTest;
  Uri uri(String action, Map<String, String> query) =>
      baseUrl.resolve('/v1/desktop/$action').replace(queryParameters: query);
  Future<Map<String, dynamic>> post(
    String action,
    Map<String, Object?> body, [
    Map<String, String> query = const {},
  ]) async {
    final token = await readToken();
    if (token == null) {
      throw StateError('Đăng nhập tài khoản AMC trước khi dùng Internet.');
    }
    final request = await _client
        .postUrl(uri(action, query))
        .timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 10));
    final content = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      content.addAll(chunk);
      if (content.length > 32768) {
        throw const FormatException('API response quá lớn.');
      }
    }
    final decoded = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
    if (response.statusCode >= 300) {
      throw StateError(
        (decoded['error'] as Map?)?['message'] as String? ??
            'Không kết nối được dịch vụ Internet.',
      );
    }
    return decoded;
  }

  Future<WebSocket> socket(Map<String, String> query, {String? ticket}) async {
    final token = await readToken();
    if (token == null) throw StateError('Cần đăng nhập AMC.');
    final url = uri('socket', query).replace(
      scheme: allowLocalTest && baseUrl.scheme == 'http' ? 'ws' : 'wss',
    );
    final socket = await WebSocket.connect(
      url.toString(),
      headers: {'Authorization': 'Bearer $token', 'X-Desktop-Ticket': ?ticket},
    ).timeout(const Duration(seconds: 10));
    socket.pingInterval = const Duration(seconds: 20);
    return socket;
  }

  void dispose() => _client.close(force: true);
}
