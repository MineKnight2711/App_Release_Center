import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:flutter/foundation.dart';
import '../../../config/backend_config.dart';
import '../../../services/auth_token_store_service.dart';
import '../infrastructure/cloud_signaling.dart';
import '../infrastructure/lan_identity.dart';
import 'swift_desk_runtime.dart';

class CloudRemotePeer {
  CloudRemotePeer({
    required this.id,
    required this.cloudId,
    required this.name,
    required this.certificate,
    required this.fingerprint,
  }) {
    if (!isRemoteId(id) ||
        !RegExp(r'^\d{12}$').hasMatch(cloudId) ||
        certificate.length > 4096 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      throw const FormatException('Danh tính Internet không hợp lệ.');
    }
    remoteName(name);
    if (LanIdentity(
          id: id,
          certificate: certificate,
          privateKey: '',
        ).fingerprint !=
        fingerprint) {
      throw const FormatException('Chứng chỉ Internet không khớp.');
    }
  }
  final String id, cloudId, name, certificate, fingerprint;
  Map<String, dynamic> toJson() => {
    'id': id,
    'cloudId': cloudId,
    'name': name,
    'certificate': certificate,
    'fingerprint': fingerprint,
  };
  factory CloudRemotePeer.fromJson(Map<String, dynamic> data) =>
      CloudRemotePeer(
        id: data['id'] as String,
        cloudId: data['cloudId'] as String,
        name: data['name'] as String,
        certificate: data['certificate'] as String,
        fingerprint: data['fingerprint'] as String,
      );
}

class SwiftDeskCloud extends ChangeNotifier {
  SwiftDeskCloud(this.runtime, this.api) {
    runtime.onPeerAuthorized = (peer) async {
      if (!_peers.containsKey(peer.sessionId)) return;
      final mode = resolveRemoteConnectionMode(
        runtime.settings.connectionMode,
        peer.request.connectionMode,
      );
      final response = await api.post('approve', {
        'sessionId': peer.sessionId,
        'remember': peer.request.remember,
        'scopes': peer.scopes.map((v) => v.name).toList(),
      }, query);
      _network(response, mode: mode);
    };
    runtime.onControllerRevoked = (id) async {
      if (cloudId != null) await api.post('revoke', {'id': id}, query);
    };
    runtime.stopInternet = disposeAsync;
    runtime.addListener(_runtimeChanged);
    _authGuard = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_authChecking || _closed || _accountToken == null) return;
      _authChecking = true;
      unawaited(() async {
        try {
          if (await api.readToken() != _accountToken) {
            await stop();
            for (final transport in _viewerPeers.toList()) {
              await transport.close();
            }
            cloudId = null;
            _accountToken = null;
            status =
                'Tài khoản đã thay đổi. Bật lại Internet sau khi đăng nhập.';
            if (!_closed) notifyListeners();
          }
        } catch (_) {
          await stop();
          for (final transport in _viewerPeers.toList()) {
            await transport.close();
          }
          _accountToken = null;
        } finally {
          _authChecking = false;
        }
      }());
    });
  }
  static final _instances = Expando<Future<SwiftDeskCloud>>();
  static Future<SwiftDeskCloud> open(SwiftDeskRuntime runtime) =>
      _instances[runtime] ??= _open(runtime);
  static Future<SwiftDeskCloud> _open(SwiftDeskRuntime runtime) async {
    try {
      final config = await BackendConfig.load();
      return SwiftDeskCloud(
        runtime,
        DesktopCloudApi(config.apiBaseUrl, AuthTokenStoreService().readToken),
      );
    } catch (_) {
      _instances[runtime] = null;
      rethrow;
    }
  }

  final SwiftDeskRuntime runtime;
  final DesktopCloudApi api;
  WebSocket? _host, _viewer;
  final _peers = <String, CloudSignalingTransport>{};
  final _viewerPeers = <CloudSignalingTransport>{};
  Timer? _retry, _heartbeat;
  Timer? _authGuard;
  String? _accountToken;
  bool _authChecking = false;
  bool _wanted = false, _closed = false, busy = false;
  int _retrySeconds = 3;
  String? cloudId, error;
  String status = 'Internet đang tắt';
  bool get online => _host?.readyState == WebSocket.open;
  bool get wanted => _wanted;
  Map<String, String> get query => {
    'hostId': cloudId!,
    'deviceId': runtime.identity.id,
  };
  List<CloudRemotePeer> get saved => runtime.settings
      .metadata('cloudDevices')
      .map(CloudRemotePeer.fromJson)
      .toList();
  Future<void> _enroll() async {
    if (cloudId != null) return;
    _accountToken = await api.readToken();
    final value = await api.post('enroll', {
      'id': runtime.identity.id,
      'fingerprint': runtime.identity.fingerprint,
      'name': runtime.name,
      'platform': runtime.platform,
    });
    final id = value['cloud_id'] as String;
    if (!RegExp(r'^\d{12}$').hasMatch(id)) {
      throw const FormatException('Invalid cloud ID');
    }
    cloudId = id;
  }

  Future<void> _action(Future<void> Function() work) async {
    if (busy || _closed) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await work();
    } catch (e) {
      error = e is StateError
          ? e.message.toString()
          : e is FormatException
          ? e.message.toString()
          : 'Không kết nối được Internet desktop. Kiểm tra API, tài khoản và mạng.';
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> start() => _action(() async {
    if (!runtime.hostEnabled) {
      throw StateError('Bật nhận kết nối trên máy này trước.');
    }
    _wanted = true;
    await _listen();
  });
  Future<void> _listen() async {
    await _enroll();
    if (!_wanted || _closed) return;
    final socket = await api.socket(query);
    if (!_wanted || _closed) {
      await socket.close();
      return;
    }
    final previous = _host;
    _host = socket;
    unawaited(previous?.close());
    socket.listen(
      (raw) {
        if (identical(_host, socket)) {
          try {
            _hostMessage(raw);
          } catch (_) {
            unawaited(stop());
          }
        }
      },
      onDone: () => _lost(socket),
      onError: (Object _) => _lost(socket),
    );
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (socket.readyState == WebSocket.open) socket.add('{"event":"ping"}');
    });
    _retrySeconds = 3;
    status = 'Đang nhận kết nối Internet';
    error = null;
    notifyListeners();
  }

  void _lost(WebSocket socket) {
    if (!identical(_host, socket)) return;
    _host = null;
    _heartbeat?.cancel();
    for (final transport in _peers.values.toList()) {
      unawaited(transport.close());
    }
    status = _wanted ? 'Mất signaling, đang kết nối lại' : 'Internet đang tắt';
    if (!_closed) notifyListeners();
    if (_wanted && !_closed) {
      _retry?.cancel();
      _retry = Timer(Duration(seconds: _retrySeconds), () {
        unawaited(
          _listen().catchError((Object _) {
            _scheduleRetry();
          }),
        );
      });
      _retrySeconds = (_retrySeconds * 2).clamp(3, 30);
    }
  }

  void _scheduleRetry() {
    if (!_wanted || _closed) return;
    _retry?.cancel();
    _retry = Timer(
      const Duration(seconds: 30),
      () => unawaited(_listen().catchError((Object _) => _scheduleRetry())),
    );
  }

  Map<String, dynamic> _message(Object? raw) {
    if (raw is! String || raw.length > 400000) {
      throw const FormatException('Invalid cloud message');
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  void _hostMessage(Object? raw) {
    final value = _message(raw), sid = valueId(raw);
    if (value['event'] == 'pong') return;
    if (value['event'] == 'peer') {
      if (!runtime.hostEnabled ||
          runtime.active ||
          runtime.draining ||
          _peers.isNotEmpty) {
        _host?.add(jsonEncode({'event': 'close', 'sessionId': sid}));
        return;
      }
      final transport = CloudSignalingTransport.receiver(
        sessionId: sid,
        identity: runtime.identity,
        emit: (payload) => _host?.add(
          jsonEncode({'event': 'data', 'sessionId': sid, 'payload': payload}),
        ),
        closed: () async {
          _peers.remove(sid);
          _host?.add(jsonEncode({'event': 'close', 'sessionId': sid}));
        },
      );
      _peers[sid] = transport;
      unawaited(
        transport.ready.then((_) {
          if (identical(_peers[sid], transport)) {
            runtime.acceptCloudTransport(
              transport,
              sid,
              value['name'] as String,
            );
          }
        }),
      );
    } else if (value['event'] == 'data') {
      _peers[sid]?.receive(value['payload'] as String);
    } else if (value['event'] == 'closed') {
      unawaited(_peers[sid]?.close());
    }
  }

  String valueId(Object? raw) {
    final value = _message(raw);
    if (value['event'] == 'pong') return '';
    final id = value['sessionId'];
    if (id is! String || !isRemoteId(id)) {
      throw const FormatException('Invalid room session');
    }
    return id;
  }

  void _network(Map<String, dynamic> response, {RemoteConnectionMode? mode}) {
    final entries = response['iceServers'];
    if (entries is! List || entries.length > 8) {
      throw const FormatException('Invalid ICE settings');
    }
    if (runtime.engine is! RemoteNetworkEngine) {
      throw StateError('Engine chưa hỗ trợ Internet.');
    }
    (runtime.engine as RemoteNetworkEngine).configureNetwork(
      entries.map((v) => Map<String, dynamic>.from(v as Map)).toList(),
      mode: mode ?? runtime.settings.connectionMode,
    );
  }

  Future<String?> invitation() async {
    String? code;
    await _action(() async {
      if (!online || !runtime.hostEnabled) {
        throw StateError('Bật host Internet trước.');
      }
      final joinCode = remoteToken();
      final local = runtime.invitation('127.0.0.1');
      await api.post('invite', {'code': joinCode}, query);
      final peer = CloudRemotePeer(
        id: runtime.identity.id,
        cloudId: cloudId!,
        name: runtime.name,
        certificate: runtime.identity.certificate,
        fingerprint: runtime.identity.fingerprint,
      );
      code =
          'amc-net:1:${base64Url.encode(utf8.encode(jsonEncode({'server': api.baseUrl.toString(), 'peer': peer.toJson(), 'code': joinCode, 'pairToken': local.token, 'expiresAt': local.expiresAt.toUtc().toIso8601String()})))}';
    });
    return code;
  }

  Future<void> connectInvitation(
    String source, {
    bool remember = true,
  }) => _action(() async {
    if (!source.startsWith('amc-net:1:') || source.length > 10000) {
      throw const FormatException('Mã Internet không hợp lệ.');
    }
    final value =
        jsonDecode(utf8.decode(base64Url.decode(source.substring(10))))
            as Map<String, dynamic>;
    if (value['server'] != api.baseUrl.toString()) {
      throw const FormatException(
        'Mã thuộc API khác. Kiểm tra máy đích; không gửi token AMC sang API lạ.',
      );
    }
    final expiry = DateTime.parse(value['expiresAt'] as String);
    if (!expiry.isAfter(DateTime.now()) ||
        expiry.difference(DateTime.now()) > const Duration(minutes: 6)) {
      throw const FormatException('Mã Internet đã hết hạn.');
    }
    final pairToken = value['pairToken'] as String,
        code = value['code'] as String;
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(pairToken) ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(code)) {
      throw const FormatException('Mã Internet sai.');
    }
    await _connect(
      CloudRemotePeer.fromJson(value['peer'] as Map<String, dynamic>),
      pairToken,
      code: code,
      remember: remember,
    );
  });
  Future<void> connectSaved(CloudRemotePeer peer) => _action(() async {
    final token = await runtime.credentials.read('peer.${peer.id}');
    if (token == null) {
      throw StateError('Thiếu credential; ghép lại bằng mã Internet.');
    }
    await _connect(peer, token, remember: true);
  });
  Future<void> _connect(
    CloudRemotePeer peer,
    String credential, {
    String? code,
    required bool remember,
  }) async {
    if (runtime.active || runtime.busy || runtime.draining) {
      throw StateError('Ngắt phiên hiện tại trước.');
    }
    await _enroll();
    final query = {'deviceId': runtime.identity.id, 'hostId': peer.cloudId};
    final ticket = await api.post('ticket', {'code': code ?? ''}, query);
    _network(ticket);
    final sid = ticket['sessionId'] as String;
    if (!isRemoteId(sid)) throw const FormatException('Invalid ticket session');
    final socket = await api.socket(query, ticket: ticket['ticket'] as String);
    _viewer = socket;
    CloudSignalingTransport? transport;
    final waiting = <String>[];
    var finished = false;
    socket.listen(
      (raw) {
        try {
          final value = _message(raw);
          if (value['event'] == 'pong') return;
          if (value['sessionId'] != sid) {
            throw const FormatException('Foreign cloud session');
          }
          if (value['event'] == 'data') {
            final payload = value['payload'] as String;
            if (transport == null) {
              if (waiting.length >= 4) {
                throw const FormatException('Too many initial messages');
              }
              waiting.add(payload);
            } else {
              transport.receive(payload);
            }
          } else if (value['event'] == 'closed') {
            unawaited(transport?.close());
          }
        } catch (_) {
          finished = true;
          unawaited(transport?.close());
          unawaited(socket.close());
        }
      },
      onDone: () {
        finished = true;
        unawaited(transport?.close());
      },
      onError: (Object _) {
        finished = true;
        unawaited(transport?.close());
      },
    );
    try {
      transport = await CloudSignalingTransport.viewer(
        sessionId: sid,
        certificate: peer.certificate,
        fingerprint: peer.fingerprint,
        emit: (payload) => socket.add(
          jsonEncode({'event': 'data', 'sessionId': sid, 'payload': payload}),
        ),
        closed: () async {
          await socket.close().timeout(const Duration(seconds: 2));
        },
      );
      if (finished || _closed) {
        await transport.close();
        return;
      }
      _viewerPeers.add(transport);
      unawaited(transport.done.then((_) => _viewerPeers.remove(transport)));
      for (final payload in waiting) {
        transport.receive(payload);
      }
      runtime.onCloudRemembered = () async {
        final all = runtime.settings.metadata('cloudDevices');
        if (!all.any((p) => p['id'] == peer.id)) all.add(peer.toJson());
        await runtime.settings.setText('cloudDevices', jsonEncode(all));
        if (!_closed) notifyListeners();
      };
      await runtime.connectCloud(
        transport,
        peerId: peer.id,
        peerName: peer.name,
        credential: credential,
        remember: remember,
      );
    } catch (_) {
      await socket.close();
      rethrow;
    }
  }

  Future<void> forget(CloudRemotePeer peer) => _action(() async {
    final all = runtime.settings.metadata('cloudDevices')
      ..removeWhere((p) => p['id'] == peer.id);
    await runtime.settings.setText('cloudDevices', jsonEncode(all));
    await runtime.credentials.delete('peer.${peer.id}');
  });
  void _runtimeChanged() {
    if (!runtime.hostEnabled && _wanted) unawaited(stop());
  }

  Future<void> stop() async {
    _wanted = false;
    _retry?.cancel();
    _heartbeat?.cancel();
    final socket = _host;
    _host = null;
    for (final transport in _peers.values.toList()) {
      await transport.close();
    }
    try {
      await socket?.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    status = 'Internet đang tắt';
    if (!_closed) notifyListeners();
  }

  Future<void> disposeAsync() async {
    if (_closed) return;
    _closed = true;
    _authGuard?.cancel();
    runtime.removeListener(_runtimeChanged);
    await stop();
    for (final transport in _viewerPeers.toList()) {
      await transport.close();
    }
    try {
      await _viewer?.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    api.dispose();
    super.dispose();
  }
}
