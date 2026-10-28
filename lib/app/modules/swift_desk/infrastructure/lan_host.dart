import 'dart:async';
import 'dart:io';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:uuid/uuid.dart';
import 'lan_identity.dart';
import 'lan_transport.dart';

class RemotePairRequest {
  RemotePairRequest({
    required this.sessionId,
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.address,
    required this.availableScopes,
    required this.remember,
    required this.knownDevice,
    this.internet = false,
    this.connectionMode = RemoteConnectionMode.automatic,
  });
  final String sessionId, deviceId, name, platform, address;
  final Set<RemoteScope> availableScopes;
  final bool remember, knownDevice;
  final bool internet;
  final RemoteConnectionMode connectionMode;
  final decision = Completer<Set<RemoteScope>?>();
  void decide(Set<RemoteScope>? scopes) {
    if (!decision.isCompleted) decision.complete(scopes);
  }
}

class AuthorizedLanPeer {
  AuthorizedLanPeer({
    required this.connection,
    required this.request,
    required this.scopes,
  });
  final SignalingTransport connection;
  final RemotePairRequest request;
  final Set<RemoteScope> scopes;
  String get sessionId => request.sessionId;
}

/// Attended LAN host. An invite or remembered bearer only authenticates a
/// request; the human approval below is mandatory on every connection.
class LanHostService {
  LanHostService({
    required this.identity,
    required this.name,
    required this.platform,
    required this.repository,
    required this.onRequest,
    required this.onAuthorized,
  });
  final LanIdentity identity;
  final String name, platform;
  final RemoteDeviceRepository repository;
  final void Function(RemotePairRequest request) onRequest;
  final Future<void> Function(AuthorizedLanPeer peer) onAuthorized;
  SecureServerSocket? _server;
  final _clients = <SignalingTransport, _Client>{};
  final _attempts = <String, List<DateTime>>{};
  _Client? _reserved;
  String? _invitationHash;
  DateTime? _invitationExpiry;
  bool _stopped = false;
  int get port => _server?.port ?? 0;
  bool get isEnabled => _server != null && !_stopped;

  Future<void> start({int port = 9877, InternetAddress? bindAddress}) async {
    if (_server != null) return;
    _stopped = false;
    _server = await SecureServerSocket.bind(
      bindAddress ?? InternetAddress.anyIPv4,
      port,
      identity.context,
      supportedProtocols: [LanConnection.protocol],
    );
    _server!.listen(_accept, onError: (Object _) {});
  }

  RemoteInvitation invitation(String address) {
    if (!isEnabled) throw StateError('Máy này chưa bật nhận kết nối.');
    final token = remoteToken();
    _invitationHash = remoteHash(token);
    _invitationExpiry = DateTime.now().add(const Duration(minutes: 5));
    return RemoteInvitation(
      endpoint: RemoteEndpoint(
        address: address,
        port: port,
        fingerprint: identity.fingerprint,
        deviceId: identity.id,
        name: name,
      ),
      token: token,
      expiresAt: _invitationExpiry!,
    );
  }

  void _accept(SecureSocket socket) {
    final address = socket.remoteAddress.address;
    final now = DateTime.now();
    if (_attempts.length > 512) _attempts.clear();
    final attempts = _attempts.putIfAbsent(address, () => []);
    attempts.removeWhere(
      (at) => now.difference(at) > const Duration(minutes: 1),
    );
    if (_stopped ||
        !isLanAddress(address) ||
        _clients.length >= 4 ||
        attempts.length >= 6 ||
        (socket.selectedProtocol != null &&
            socket.selectedProtocol != LanConnection.protocol)) {
      socket.destroy();
      return;
    }
    attempts.add(now);
    final connection = LanConnection(socket);
    acceptTransport(connection, address: address);
  }

  /// Internet transports arrive only after authenticated room admission and
  /// end-to-end key establishment. The same attended pairing policy applies.
  void acceptTransport(
    SignalingTransport connection, {
    required String address,
    String? sessionId,
    bool internet = false,
  }) {
    if (_stopped || _clients.length >= 4) {
      unawaited(connection.close());
      return;
    }
    final client = _Client(
      connection,
      sessionId ?? const Uuid().v4(),
      address,
      internet,
    );
    _clients[connection] = client;
    client.timer = Timer(
      const Duration(seconds: 8),
      () => unawaited(connection.close()),
    );
    client.subscription = connection.messages.listen((signal) {
      if (client.authorized) return;
      if (signal.kind == 'disconnect') {
        unawaited(connection.close());
        return;
      }
      if (signal.kind != 'request' || client.authenticating) {
        unawaited(connection.close());
        return;
      }
      client.authenticating = true;
      unawaited(
        _request(
          client,
          signal,
        ).catchError((Object _) => _reject(client, 'Yêu cầu không hợp lệ.')),
      );
    });
    unawaited(
      connection.done.then((_) {
        client.timer?.cancel();
        client.request?.decide(null);
        _clients.remove(connection);
        if (identical(_reserved, client)) _reserved = null;
        unawaited(client.subscription?.cancel());
      }),
    );
    connection.send(client.sessionId, 'hello', {
      'deviceId': identity.id,
      'name': name,
      'platform': platform,
    });
  }

  Future<void> _request(_Client client, RemoteSignal signal) async {
    if (signal.sessionId != client.sessionId || _reserved != null) {
      _reject(client, 'Máy đang có phiên hoặc yêu cầu khác.');
      return;
    }
    final data = signal.data;
    final id = data['deviceId'];
    if (id is! String ||
        !isRemoteId(id) ||
        id == identity.id ||
        data['remember'] is! bool ||
        data['platform'] is! String ||
        (data['platform'] as String).length > 20) {
      _reject(client, 'Danh tính viewer không hợp lệ.');
      return;
    }
    final peerName = remoteName(data['name']);
    final requested = parseScopes(data['scopes']);
    final credential = data['credential'];
    if (credential is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(credential)) {
      _reject(client, 'Mã ghép nối sai hoặc đã hết hạn.');
      return;
    }
    final credentialHash = remoteHash(credential);
    TrustedRemoteController? known;
    for (final controller in await repository.controllers()) {
      if (controller.id == id &&
          remoteHashEquals(controller.tokenHash, credentialHash)) {
        known = controller;
        break;
      }
    }
    // Check again after awaiting storage; two concurrent requests cannot both
    // reserve the host or consume the same single-use invitation.
    if (_stopped ||
        !_clients.containsKey(client.connection) ||
        _reserved != null) {
      _reject(client, 'Yêu cầu đã đóng hoặc máy đang bận.');
      return;
    }
    if (known == null) {
      if (_invitationHash == null ||
          _invitationExpiry == null ||
          !DateTime.now().isBefore(_invitationExpiry!) ||
          !remoteHashEquals(_invitationHash!, credentialHash)) {
        _reject(client, 'Thiết bị chưa được ghép hoặc đã bị thu hồi.');
        return;
      }
      _invitationHash = null; // Consume before asking the host for approval.
    }
    final scopes = known == null
        ? requested
        : requested.intersection(known.scopes);
    if (!scopes.contains(RemoteScope.view)) {
      _reject(client, 'Thiếu quyền xem màn hình.');
      return;
    }
    _reserved = client;
    client.timer?.cancel();
    final request = RemotePairRequest(
      sessionId: client.sessionId,
      deviceId: id,
      name: peerName,
      platform: data['platform'] as String,
      address: client.address,
      availableScopes: Set.unmodifiable(scopes),
      remember: data['remember'] as bool,
      knownDevice: known != null,
      internet: client.internet,
      connectionMode: client.internet
          ? parseRemoteConnectionMode(data['connectionMode'])
          : RemoteConnectionMode.automatic,
    );
    client.request = request;
    client.timer = Timer(
      const Duration(seconds: 60),
      () => request.decide(null),
    );
    client.connection.send(client.sessionId, 'pending');
    onRequest(request);
    final grant = await request.decision.future;
    client.timer?.cancel();
    if (_stopped || !_clients.containsKey(client.connection)) return;
    if (grant == null ||
        !grant.contains(RemoteScope.view) ||
        !scopes.containsAll(grant)) {
      _reject(client, 'Máy đích đã từ chối hoặc yêu cầu hết thời gian.');
      return;
    }
    String? token;
    if (request.remember && known == null) {
      token = remoteToken();
      await repository.saveController(
        TrustedRemoteController(
          id: id,
          name: peerName,
          tokenHash: remoteHash(token),
          scopes: grant,
        ),
      );
    }
    if (_stopped || !_clients.containsKey(client.connection)) return;
    client.authorized = true;
    client.connection.send(client.sessionId, 'approved', {
      'scopes': grant.map((s) => s.name).toList(),
      'trustToken': ?token,
      'name': name,
      'deviceId': identity.id,
      'platform': platform,
    });
    unawaited(
      onAuthorized(
        AuthorizedLanPeer(
          connection: client.connection,
          request: request,
          scopes: Set.unmodifiable(grant),
        ),
      ).catchError(
        (Object _) => _reject(client, 'Không khởi động được phiên màn hình.'),
      ),
    );
  }

  void _reject(_Client client, String reason) {
    try {
      client.connection.send(client.sessionId, 'rejected', {'reason': reason});
    } catch (_) {}
    unawaited(client.connection.close());
  }

  Future<void> revoke(String id) async {
    await repository.removeController(id);
    for (final client in List<_Client>.of(_clients.values)) {
      if (client.request?.deviceId == id) {
        client.request?.decide(null);
        await client.connection.close();
      }
    }
  }

  Future<void> stop() async {
    _stopped = true;
    _invitationHash = null;
    await _server?.close();
    _server = null;
    for (final client in List<_Client>.of(_clients.values)) {
      client.request?.decide(null);
      await client.connection.close();
    }
    _reserved = null;
  }
}

class _Client {
  _Client(this.connection, this.sessionId, this.address, this.internet);
  final SignalingTransport connection;
  final String sessionId, address;
  final bool internet;
  bool authenticating = false, authorized = false;
  RemotePairRequest? request;
  Timer? timer;
  StreamSubscription<RemoteSignal>? subscription;
}
