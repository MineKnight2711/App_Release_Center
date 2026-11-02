import 'dart:async';
import 'dart:convert';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as crypt;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../infrastructure/cloud_signaling.dart';
import '../infrastructure/lan_identity.dart';
import '../infrastructure/public_broker.dart';
import 'swift_desk_runtime.dart';

String normalizePublicRemoteId(String value) {
  final id = value.trim().replaceAll(RegExp(r'[ -]'), '');
  if (!RegExp(r'^[1-9][0-9]{8}$').hasMatch(id)) {
    throw const FormatException('Mã máy gồm 9 chữ số.');
  }
  return id;
}

String formatPublicRemoteId(String id) =>
    '${id.substring(0, 3)} ${id.substring(3, 6)} ${id.substring(6)}';
String publicRemoteId(LanIdentity identity) =>
    (BigInt.parse(remoteHash(identity.id).substring(0, 16), radix: 16) %
                BigInt.from(900000000) +
            BigInt.from(100000000))
        .toString();

class PublicRemoteCode {
  PublicRemoteCode(String id, this.password)
    : id = normalizePublicRemoteId(id) {
    if (!RegExp(r'^[A-Za-z0-9_-]{16}$').hasMatch(password)) {
      throw const FormatException('Mật khẩu ghép không hợp lệ.');
    }
  }
  final String id, password;
  String encode() => 'amc-id:1:$id:$password';
  static PublicRemoteCode decode(String source) {
    final parts = source.trim().split(':');
    if (parts.length != 4 || parts[0] != 'amc-id' || parts[1] != '1') {
      throw const FormatException('Mã kết nối không hợp lệ.');
    }
    return PublicRemoteCode(parts[2], parts[3]);
  }
}

class PublicRemotePeer {
  PublicRemotePeer({
    required this.codeId,
    required this.id,
    required this.name,
    required this.certificate,
    required this.fingerprint,
  }) {
    normalizePublicRemoteId(codeId);
    remoteName(name);
    if (!isRemoteId(id) ||
        certificate.length > 4096 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint) ||
        LanIdentity(
              id: id,
              certificate: certificate,
              privateKey: '',
            ).fingerprint !=
            fingerprint) {
      throw const FormatException('Danh tính máy không hợp lệ.');
    }
  }
  final String codeId, id, name, certificate, fingerprint;
  Map<String, dynamic> toJson() => {
    'codeId': codeId,
    'id': id,
    'name': name,
    'certificate': certificate,
    'fingerprint': fingerprint,
  };
  factory PublicRemotePeer.fromJson(Map<String, dynamic> value) =>
      PublicRemotePeer(
        codeId: value['codeId'] as String,
        id: value['id'] as String,
        name: value['name'] as String,
        certificate: value['certificate'] as String,
        fingerprint: value['fingerprint'] as String,
      );
}

/// Public brokers provide rendezvous, not identity or permission. A fresh
/// 96-bit pairing password authenticates an ephemeral X25519 transcript. A
/// remembered peer uses the existing 256-bit trust token's hash instead.
/// All bootstrap credentials and signaling then use directional AES-GCM.
class SwiftDeskPublic extends ChangeNotifier {
  SwiftDeskPublic(
    this.runtime, {
    RemotePublicBroker? broker,
    DateTime Function()? now,
    this.handshakeTimeout = const Duration(seconds: 25),
  }) : broker = broker ?? MqttPublicBroker(),
       now = now ?? DateTime.now {
    renewPassword();
    _messages = this.broker.messages.listen(_receive);
    _states = this.broker.states.listen((online) {
      if (!online) {
        for (final p in _sessions.values.toList()) {
          unawaited(_drop(p));
        }
      }
      _notify();
    });
    runtime.addListener(_runtimeChanged);
    runtime.internetServices['public'] = SwiftDeskInternetService(
      authorize: (peer) async {
        final p = _sessions[peer.sessionId];
        if (p == null || !p.host) return;
        final mode = resolveRemoteConnectionMode(
          runtime.settings.connectionMode,
          peer.request.connectionMode,
        );
        _network(mode);
      },
      remember: _remember,
      revoke: (id) async {
        for (final p
            in _sessions.values
                .where((p) => p.host && p.viewerId == id)
                .toList()) {
          await _drop(p);
        }
      },
      shutdown: disposeAsync,
    );
  }
  static final _instances = Expando<SwiftDeskPublic>();
  static SwiftDeskPublic open(SwiftDeskRuntime runtime) =>
      _instances[runtime] ??= SwiftDeskPublic(runtime);
  static const namespace = 'amc/swiftdesk/v1';
  static const stunServers = <Map<String, dynamic>>[
    {
      'urls': ['stun:stun.l.google.com:19302', 'stun:stun.cloudflare.com:3478'],
    },
  ];
  final SwiftDeskRuntime runtime;
  final RemotePublicBroker broker;
  final DateTime Function() now;
  final Duration handshakeTimeout;
  final _dh = crypt.X25519();
  final _sessions = <String, _PublicSession>{};
  final _attempts = <DateTime>[];
  late final StreamSubscription<RemoteBrokerMessage> _messages;
  late final StreamSubscription<bool> _states;
  Timer? _expiry;
  Future<void> _tail = Future.value();
  int _queued = 0;
  String? _protocolErrorType;
  bool _closed = false, busy = false, _wanted = false;
  String? _openingHost, error;
  late String password;
  late DateTime passwordExpiresAt;
  String get codeId => publicRemoteId(runtime.identity);
  String get formattedId => formatPublicRemoteId(codeId);
  bool get wanted => _wanted;
  bool get online => _wanted && runtime.hostEnabled && broker.online;
  bool get hasSession => _sessions.isNotEmpty;
  Map<String, Object?> diagnostics() => {
    'online': online,
    'sessions': _sessions.length,
    'protocolErrorType': _protocolErrorType,
    'stages': _sessions.values
        .map(
          (p) => {
            'host': p.host,
            'master': p.master != null,
            'confirmed': p.confirmed,
            'attached': p.attached,
          },
        )
        .toList(),
  };
  PublicRemoteCode get code => PublicRemoteCode(codeId, password);
  List<PublicRemotePeer> get saved => runtime.settings
      .metadata('publicDevices')
      .map(PublicRemotePeer.fromJson)
      .toList();
  String get status => online
      ? 'Sẵn sàng nhận kết nối bằng mã'
      : _wanted
      ? 'Đang nối lại dịch vụ ghép máy…'
      : 'Chưa bật nhận kết nối bằng mã';
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void renewPassword() {
    password = remoteToken().substring(0, 16);
    passwordExpiresAt = now().add(const Duration(minutes: 5));
    _notify();
  }

  void _network(RemoteConnectionMode mode) {
    if (mode == RemoteConnectionMode.relay) {
      throw StateError(
        'Ghép mã công cộng dùng P2P. Chọn Tự động hoặc P2P IPv6; TURN riêng nằm trong tùy chọn máy chủ AMC.',
      );
    }
    if (runtime.engine is RemoteNetworkEngine) {
      (runtime.engine as RemoteNetworkEngine).configureNetwork(
        stunServers,
        mode: mode,
      );
    }
  }

  Future<void> _work(Future<void> Function() action) async {
    if (busy || _closed) return;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
    } catch (e) {
      error = e is FormatException
          ? e.message.toString()
          : e is StateError
          ? e.message.toString()
          : 'Không ghép được máy. Kiểm tra Internet, mã máy và mật khẩu ghép.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> start() => _work(() async {
    if (runtime.active || runtime.busy || runtime.draining) {
      throw StateError('Ngắt phiên hiện tại trước.');
    }
    _network(runtime.settings.connectionMode);
    if (!runtime.hostEnabled) {
      await runtime.enableHost(port: runtime.settings.port);
    }
    if (!runtime.hostEnabled) {
      throw StateError(
        runtime.error ??
            'Cấp quyền ghi màn hình trước khi cho phép truy cập máy này.',
      );
    }
    await broker.connect();
    if (_closed) return;
    await broker.subscribe('$namespace/host/$codeId');
    if (_closed) return;
    _wanted = true;
    renewPassword();
    _expiry ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (!now().isBefore(passwordExpiresAt)) renewPassword();
    });
  });
  Future<void> stop() async {
    _wanted = false;
    _expiry?.cancel();
    _expiry = null;
    broker.unsubscribe('$namespace/host/$codeId');
    for (final p in _sessions.values.where((p) => p.host).toList()) {
      await _drop(p);
    }
    _notify();
  }

  void _runtimeChanged() {
    if (_wanted && !runtime.hostEnabled) unawaited(stop());
  }

  Future<void> connect(
    String source, {
    String password = '',
    bool remember = true,
  }) => _work(() async {
    if (runtime.active || runtime.busy || runtime.draining || hasSession) {
      throw StateError('Ngắt phiên hiện tại trước.');
    }
    String target;
    if (source.trim().startsWith('amc-id:')) {
      final code = PublicRemoteCode.decode(source);
      target = code.id;
      password = code.password;
    } else {
      target = normalizePublicRemoteId(source);
    }
    if (target == codeId) {
      throw StateError('Đây là mã của chính máy này. Nhập mã máy đối tác.');
    }
    final peer = saved.where((p) => p.codeId == target).firstOrNull;
    String? credential;
    if (password.isEmpty && peer != null) {
      credential = await runtime.credentials.read('peer.${peer.id}');
    }
    if (credential == null &&
        !RegExp(r'^[A-Za-z0-9_-]{16}$').hasMatch(password)) {
      throw const FormatException(
        'Nhập mật khẩu ghép trên máy đối tác, hoặc dán toàn bộ mã kết nối.',
      );
    }
    _network(runtime.settings.connectionMode);
    await broker.connect();
    final p = _PublicSession(
      host: false,
      sid: const Uuid().v4(),
      target: target,
      viewerId: runtime.identity.id,
      auth: credential == null ? remoteHash(password) : remoteHash(credential),
      known: credential != null,
      nonce: remoteToken(),
      key: await _dh.newKeyPair(),
      remembered: remember,
    );
    p.credential = credential;
    p.peer = credential == null ? null : peer;
    _sessions[p.sid] = p;
    _deadline(p);
    try {
      await broker.subscribe(_inbox(p));
      final key = await p.key.extractPublicKey();
      p.clientKey = base64.encode(key.bytes);
      final hello = <String, dynamic>{
        'type': 'hello',
        'sid': p.sid,
        'viewerId': p.viewerId,
        'known': p.known,
        'nonce': p.nonce,
        'key': p.clientKey,
      };
      hello['proof'] = _proof(p.auth, _helloTranscript(target, hello));
      _publish('$namespace/host/$target', hello);
      p.retry = Timer.periodic(const Duration(milliseconds: 800), (_) {
        if (p.closed || p.master != null) return;
        try {
          _publish('$namespace/host/$target', hello);
        } catch (_) {
          unawaited(_drop(p));
        }
      });
      await p.connected.future;
    } catch (_) {
      await _drop(p);
      rethrow;
    }
  });
  String _inbox(_PublicSession p) =>
      '$namespace/session/${p.sid}/${p.host ? 'host' : 'viewer'}';
  String _outbox(_PublicSession p) =>
      '$namespace/session/${p.sid}/${p.host ? 'viewer' : 'host'}';
  void _publish(String topic, Map<String, dynamic> value) =>
      broker.publish(topic, jsonEncode(value));
  String _proof(String secret, String value) => base64.encode(
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(value)).bytes,
  );
  String _helloTranscript(String target, Map<String, dynamic> value) =>
      jsonEncode([
        'hello-v1',
        target,
        value['sid'],
        value['viewerId'],
        value['known'],
        value['nonce'],
        value['key'],
      ]);
  String _transcript(_PublicSession p, Map<String, dynamic> c) => jsonEncode([
    1,
    p.target,
    p.sid,
    p.viewerId,
    p.known,
    p.nonce,
    c['nonce'],
    p.clientKey,
    c['key'],
    c['deviceId'],
    c['fingerprint'],
  ]);
  void _deadline(_PublicSession p) {
    p.deadline = Timer(handshakeTimeout, () {
      if (!p.connected.isCompleted) {
        p.connected.completeError(
          StateError(
            'Không nhận được phản hồi. Kiểm tra máy đối tác đã bật nhận mã và mật khẩu còn hiệu lực.',
          ),
        );
      }
      unawaited(_drop(p));
    });
    // Host handshakes have no waiting UI Future, but still need bounded cleanup.
    unawaited(p.connected.future.catchError((Object _) {}));
  }

  void _receive(RemoteBrokerMessage message) {
    if (_closed || _queued >= 64 || message.payload.length > 400000) return;
    _queued++;
    _tail = _tail
        .then((_) async {
          if (_closed) return;
          try {
            final value = jsonDecode(message.payload);
            if (value is! Map<String, dynamic> ||
                !isRemoteId(
                  value['sid'] is String ? value['sid'] as String : '',
                )) {
              return;
            }
            final sid = value['sid'] as String;
            if (message.topic == '$namespace/host/$codeId' &&
                value['type'] == 'hello') {
              await _hello(value);
              return;
            }
            final p = _sessions[sid];
            if (p == null || p.closed || message.topic != _inbox(p)) return;
            if (value['type'] == 'challenge' && !p.host && p.master == null) {
              await _challenge(p, value);
            } else if (value['type'] == 'confirm' && p.host && !p.confirmed) {
              await _confirm(p, value);
            } else if (p.master != null &&
                {'data', 'attach', 'bye'}.contains(value['type'])) {
              await _packet(p, value);
            }
          } catch (e) {
            _protocolErrorType = e.runtimeType.toString();
            /* Public, unauthenticated traffic must not end a real session. */
          }
        })
        .whenComplete(() => _queued--);
  }

  Future<void> _hello(Map<String, dynamic> value) async {
    if (!online ||
        runtime.active ||
        runtime.draining ||
        _openingHost != null ||
        _sessions.length >= 4 ||
        _sessions.containsKey(value['sid'])) {
      return;
    }
    _attempts.removeWhere(
      (t) => now().difference(t) > const Duration(minutes: 1),
    );
    if (_attempts.length >= 12 ||
        value['known'] is! bool ||
        value['nonce'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value['nonce'] as String) ||
        !isRemoteId(
          value['viewerId'] is String ? value['viewerId'] as String : '',
        )) {
      return;
    }
    final clientKey = value['key'];
    if (clientKey is! String ||
        clientKey.length != 44 ||
        base64.decode(clientKey).length != 32) {
      return;
    }
    final known = value['known'] == true;
    final controller = known
        ? (await runtime.repository.controllers())
              .where((c) => c.id == value['viewerId'])
              .firstOrNull
        : null;
    if (_closed || !online) return;
    if (known && controller == null) return;
    if (!now().isBefore(passwordExpiresAt)) renewPassword();
    final auth = known ? controller!.tokenHash : remoteHash(password);
    if (value['proof'] is! String ||
        !remoteHashEquals(
          _proof(auth, _helloTranscript(codeId, value)),
          value['proof'] as String,
        )) {
      return;
    }
    // Allocate timers/keys and sign a challenge only after proving possession
    // of a pairing password or remembered credential. A public ID is not auth.
    _attempts.add(now());
    final p = _PublicSession(
      host: true,
      sid: value['sid'] as String,
      target: codeId,
      viewerId: value['viewerId'] as String,
      auth: auth,
      known: known,
      nonce: value['nonce'] as String,
      key: await _dh.newKeyPair(),
      remembered: false,
    );
    p.clientKey = clientKey;
    p.passwordVersion = password;
    p.passwordExpiry = passwordExpiresAt;
    final key = await p.key.extractPublicKey();
    final challenge = <String, dynamic>{
      'type': 'challenge',
      'sid': p.sid,
      'nonce': remoteToken(),
      'key': base64.encode(key.bytes),
      'deviceId': runtime.identity.id,
      'certificate': runtime.identity.certificate,
      'fingerprint': runtime.identity.fingerprint,
    };
    p.transcript = _transcript(p, challenge);
    if (_closed) return;
    p.challenge = challenge;
    _sessions[p.sid] = p;
    _deadline(p);
    await broker.subscribe(_inbox(p));
    _publish(_outbox(p), {
      ...challenge,
      'signature': runtime.identity.signTranscript(
        'amc-public-host:${p.transcript}',
      ),
      'proof': _proof(p.auth, 'host:${p.transcript}'),
    });
  }

  Future<List<int>> _master(_PublicSession p, String peerKey) async {
    final shared = await _dh.sharedSecretKey(
      keyPair: p.key,
      remotePublicKey: crypt.SimplePublicKey(
        base64.decode(peerKey),
        type: crypt.KeyPairType.x25519,
      ),
    );
    final key = await crypt.Hkdf(hmac: crypt.Hmac.sha256(), outputLength: 32)
        .deriveKey(
          secretKey: shared,
          nonce: sha256.convert(utf8.encode(p.transcript)).bytes,
          info: utf8.encode('amc-public-v1:${p.auth}'),
        );
    return key.extractBytes();
  }

  Future<void> _challenge(_PublicSession p, Map<String, dynamic> value) async {
    if (jsonEncode(value).length > 7000 ||
        value['proof'] is! String ||
        value['key'] is! String ||
        (value['key'] as String).length != 44 ||
        value['nonce'] is! String) {
      return;
    }
    p.transcript = _transcript(p, value);
    if (!remoteHashEquals(
      _proof(p.auth, 'host:${p.transcript}'),
      value['proof'] as String,
    )) {
      return;
    }
    final peer = PublicRemotePeer(
      codeId: p.target,
      id: value['deviceId'] as String,
      name: 'Máy ${formatPublicRemoteId(p.target)}',
      certificate: value['certificate'] as String,
      fingerprint: value['fingerprint'] as String,
    );
    if (value['signature'] is! String ||
        !LanIdentity.verifyTranscript(
          peer.certificate,
          'amc-public-host:${p.transcript}',
          value['signature'] as String,
        )) {
      return;
    }
    if (p.peer != null &&
        (p.peer!.id != peer.id || p.peer!.fingerprint != peer.fingerprint)) {
      p.connected.completeError(
        StateError(
          'Danh tính máy đã đổi. Quên thiết bị rồi ghép lại bằng mật khẩu mới.',
        ),
      );
      await _drop(p);
      return;
    }
    p.peer = peer;
    p.master = await _master(p, value['key'] as String);
    if (_closed || p.closed) return;
    p.retry?.cancel();
    p.transport = await _transport(p);
    if (_closed || p.closed) {
      await p.transport!.close();
      return;
    }
    p.bootstrap = p.transport!.messages.listen((signal) {
      if (signal.kind == 'bootstrap' && !p.attached) {
        unawaited(_bootstrap(p, signal).catchError((Object _) => _drop(p)));
      }
    });
    _publish(_outbox(p), {
      'type': 'confirm',
      'sid': p.sid,
      'proof': _proof(p.auth, 'viewer:${p.transcript}'),
    });
  }

  Future<void> _confirm(_PublicSession p, Map<String, dynamic> value) async {
    if (value['proof'] is! String ||
        !remoteHashEquals(
          _proof(p.auth, 'viewer:${p.transcript}'),
          value['proof'] as String,
        )) {
      return;
    }
    if (!online ||
        runtime.active ||
        _openingHost != null ||
        (!p.known &&
            (password != p.passwordVersion ||
                !now().isBefore(p.passwordExpiry!)))) {
      await _drop(p);
      return;
    }
    p.confirmed = true;
    _openingHost = p.sid;
    p.master = await _master(p, p.clientKey);
    if (_closed || p.closed) return;
    p.transport = await _transport(p);
    if (_closed || p.closed) {
      await p.transport!.close();
      return;
    }
    final credential = p.known ? null : runtime.invitation('127.0.0.1').token;
    if (!p.known) renewPassword();
    p.transport!.send(p.sid, 'bootstrap', {'credential': ?credential});
  }

  Future<CloudSignalingTransport> _transport(_PublicSession p) =>
      CloudSignalingTransport.authenticated(
        sessionId: p.sid,
        host: p.host,
        secret: p.master!,
        emit: (payload) => _send(p, 'data', {'payload': payload}),
        closed: () => _drop(p, closeTransport: false),
      );
  void _send(
    _PublicSession p,
    String type, [
    Map<String, dynamic> data = const {},
  ]) {
    if (p.closed) return;
    final body = <String, dynamic>{
      'type': type,
      'sid': p.sid,
      'n': p.outgoing++,
      ...data,
    };
    _publish(_outbox(p), {
      ...body,
      'auth': _proof(base64.encode(p.master!), jsonEncode(body)),
    });
  }

  Future<void> _packet(_PublicSession p, Map<String, dynamic> value) async {
    final auth = value['auth'];
    final body = Map<String, dynamic>.of(value)..remove('auth');
    if (auth is! String ||
        !remoteHashEquals(
          _proof(base64.encode(p.master!), jsonEncode(body)),
          auth,
        )) {
      return;
    }
    final n = value['n'];
    if (n is! int ||
        n < p.incoming ||
        n > p.incoming + 32 ||
        p.buffer.containsKey(n)) {
      return;
    }
    p.buffer[n] = value;
    while (p.buffer.containsKey(p.incoming)) {
      final packet = p.buffer.remove(p.incoming++)!;
      if (packet['type'] == 'data' && packet['payload'] is String) {
        p.transport?.receive(packet['payload'] as String);
      } else if (packet['type'] == 'attach' &&
          p.host &&
          p.confirmed &&
          !p.attached) {
        p.attached = true;
        p.deadline?.cancel();
        if (!p.connected.isCompleted) p.connected.complete();
        runtime.acceptCloudTransport(p.transport!, p.sid, 'Máy đối tác');
      } else if (packet['type'] == 'bye') {
        await _drop(p);
        return;
      }
    }
  }

  Future<void> _bootstrap(_PublicSession p, RemoteSignal signal) async {
    if (_closed || p.closed) return;
    p.attached = true;
    final credential = p.credential ?? signal.data['credential'];
    if (credential is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(credential)) {
      throw const FormatException('Invalid bootstrap');
    }
    await runtime.connectCloud(
      p.transport!,
      peerId: p.peer!.id,
      peerName: p.peer!.name,
      credential: credential,
      remember: p.remembered,
    );
    if (!p.closed) _send(p, 'attach');
    p.deadline?.cancel();
    if (!p.connected.isCompleted) p.connected.complete();
  }

  Future<void> _remember(String peerId) async {
    final p = _sessions.values
        .where((p) => !p.host && p.peer?.id == peerId)
        .firstOrNull;
    if (p == null) return;
    final peer = p.peer!;
    final named = PublicRemotePeer(
      codeId: peer.codeId,
      id: peer.id,
      name: runtime.session!.peerName,
      certificate: peer.certificate,
      fingerprint: peer.fingerprint,
    );
    final all = runtime.settings.metadata('publicDevices')
      ..removeWhere((v) => v['id'] == peerId);
    all.add(named.toJson());
    await runtime.settings.setText('publicDevices', jsonEncode(all));
    _notify();
  }

  Future<void> forget(PublicRemotePeer peer) => _work(() async {
    final all = runtime.settings.metadata('publicDevices')
      ..removeWhere((v) => v['id'] == peer.id);
    await runtime.settings.setText('publicDevices', jsonEncode(all));
    await runtime.credentials.delete('peer.${peer.id}');
  });
  Future<void> _drop(_PublicSession p, {bool closeTransport = true}) async {
    if (p.closed) return;
    if (p.master != null && broker.online) {
      try {
        _send(p, 'bye');
      } catch (_) {}
    }
    p.closed = true;
    p.retry?.cancel();
    p.deadline?.cancel();
    _sessions.remove(p.sid);
    if (_openingHost == p.sid) _openingHost = null;
    broker.unsubscribe(_inbox(p));
    if (!p.connected.isCompleted) {
      p.connected.completeError(
        StateError(
          'Phiên ghép nối đã đóng. Kiểm tra mật khẩu ghép và thử lại.',
        ),
      );
    }
    await p.bootstrap?.cancel();
    if (closeTransport) await p.transport?.close();
    _notify();
  }

  Future<void> disposeAsync() async {
    if (_closed) return;
    _closed = true;
    _expiry?.cancel();
    runtime.removeListener(_runtimeChanged);
    runtime.internetServices.remove('public');
    try {
      await _tail.timeout(const Duration(seconds: 6));
    } catch (_) {}
    for (final p in _sessions.values.toList()) {
      await _drop(p);
    }
    await _messages.cancel();
    await _states.cancel();
    await broker.close();
    _instances[runtime] = null;
    super.dispose();
  }
}

class _PublicSession {
  _PublicSession({
    required this.host,
    required this.sid,
    required this.target,
    required this.viewerId,
    required this.auth,
    required this.known,
    required this.nonce,
    required this.key,
    required this.remembered,
  });
  final bool host, known, remembered;
  final String sid, target, viewerId, auth, nonce;
  final crypt.SimpleKeyPair key;
  String clientKey = '', transcript = '', passwordVersion = '';
  DateTime? passwordExpiry;
  Map<String, dynamic>? challenge;
  List<int>? master;
  String? credential;
  PublicRemotePeer? peer;
  CloudSignalingTransport? transport;
  StreamSubscription<RemoteSignal>? bootstrap;
  bool confirmed = false, attached = false, closed = false;
  int outgoing = 0, incoming = 0;
  final buffer = <int, Map<String, dynamic>>{};
  final connected = Completer<void>();
  Timer? deadline, retry;
}
