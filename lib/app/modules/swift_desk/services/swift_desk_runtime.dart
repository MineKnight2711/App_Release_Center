import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:amc_remote_platform/amc_remote_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/app_background_service.dart';
import '../infrastructure/remote_settings.dart';
import '../infrastructure/lan_host.dart';
import '../infrastructure/lan_identity.dart';
import '../infrastructure/lan_transport.dart';
import '../infrastructure/remote_storage.dart';
import '../infrastructure/webrtc_desktop_engine.dart';

/// App-owned attended LAN runtime. Views subscribe to this owner; leaving the
/// device page cannot dispose its listener/capture or silently approve a peer.
class SwiftDeskRuntime extends ChangeNotifier {
  SwiftDeskRuntime({
    required this.engine,
    required this.repository,
    required this.credentials,
    required this.identity,
    required this.name,
    required this.platform,
    SwiftDeskSettings? settings,
    this.backgroundService,
    this.captureRetryDelay = const Duration(seconds: 5),
    AmcRemotePlatform native = const AmcRemotePlatform(),
  }) : settings = settings ?? SwiftDeskSettings(),
       _native = native {
    _engineSubscription = engine.events.listen((event) {
      unawaited(
        _engineEvent(
          event,
        ).catchError((Object _) => _fail('Không xử lý được sự kiện màn hình.')),
      );
    });
  }
  static Future<SwiftDeskRuntime>? _opening;
  static final current = ValueNotifier<SwiftDeskRuntime?>(null);
  static Future<SwiftDeskRuntime> open() => _opening ??= _open();
  static Future<SwiftDeskRuntime> _open() async {
    try {
      final root = await getApplicationSupportDirectory();
      final secrets = AmcRemoteCredentials();
      final identity = await LanIdentity.load(secrets);
      final runtime = SwiftDeskRuntime(
        engine: WebRtcDesktopEngine(),
        repository: FileRemoteDeviceRepository(
          File(p.join(root.path, 'swift_desk', 'devices.json')),
        ),
        credentials: secrets,
        identity: identity,
        name: Platform.localHostname.isEmpty
            ? 'Máy tính AMC'
            : Platform.localHostname,
        platform: Platform.operatingSystem,
        settings: SwiftDeskSettings(await SharedPreferences.getInstance()),
        backgroundService: AppBackgroundService.shared,
      );
      try {
        await runtime.initialize();
      } catch (_) {
        await runtime.shutdown();
        rethrow;
      }
      runtime._lifecycle = AppLifecycleListener(
        onExitRequested: () async {
          await runtime.shutdown();
          return AppExitResponse.exit;
        },
      );
      current.value = runtime;
      return runtime;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  final RemoteDesktopEngine engine;
  final RemoteDeviceRepository repository;
  final RemoteCredentialStore credentials;
  final LanIdentity identity;
  final String name, platform;
  final SwiftDeskSettings settings;
  final AppBackgroundService? backgroundService;
  final Duration captureRetryDelay;
  Future<void> Function(AuthorizedLanPeer peer)? onPeerAuthorized;
  Future<void> Function()? onCloudRemembered;
  Future<void> Function(String id)? onControllerRevoked;
  Future<void> Function()? stopInternet;
  String? _cloudPeerId;
  bool _cloudSession = false;
  final AmcRemotePlatform _native;
  late final StreamSubscription<RemoteEngineEvent> _engineSubscription;
  AppLifecycleListener? _lifecycle;
  LanHostService? _host;
  SignalingTransport? _connection;
  StreamSubscription<RemoteSignal>? _signalSubscription;
  Future<void> _signalTail = Future.value();
  RemoteSession? session;
  RemoteAccessPolicy? _policy;
  RemotePairRequest? pendingRequest;
  RemotePlatformPermissions? permissions;
  List<DisplayDescriptor> displays = [], remoteDisplays = [];
  List<RemoteDevice> devices = [];
  List<TrustedRemoteController> controllers = [];
  List<RemoteSessionRecord> history = [];
  final deviceOnline = <String, bool>{};
  DateTime? _lastProbe;
  List<String> addresses = [];
  String? displayId, remoteDisplayId, remotePlatform;
  RemoteQuality quality = RemoteQuality.balanced;
  String status = 'Chưa bật nhận kết nối';
  String? error;
  bool busy = false,
      initialized = false,
      viewerControl = false,
      clipboardEnabled = false;
  bool _closed = false, _nativeActive = false, _displayChanging = false;
  bool _firstFrame = false,
      _channelsReady = false,
      _engineConnected = false,
      _viewerReady = false;
  bool _markingConnected = false;
  bool get firstFrame => _firstFrame;
  int _generation = 0, _sendSequence = 0, frames = 0;
  int receivedPackets = 0, appliedInputs = 0;
  final _clipboardAcks = <int, Completer<void>>{};
  double fps = 0, kbps = 0;
  String networkPath = 'unknown';
  RemoteConnectionMode _connectionMode = RemoteConnectionMode.automatic;
  bool captureRecoveryAttempted = false;
  int _framesAtDisconnect = 0;
  DateTime _lastHeartbeat = DateTime.now();
  Timer? _deadline, _heartbeat, _expiry, _recovery, _captureRecovery;
  Future<void>? _disconnecting;
  Future<void>? _shutdownFuture;
  RemoteEndpoint? _lastEndpoint;
  bool get hostEnabled => _host?.isEnabled == true;
  int get listenPort => _host?.port ?? 9877;
  bool get active => session != null && !session!.terminal;
  bool get viewing => active && session!.role == RemoteRole.viewer;
  bool get hosting => active && session!.role == RemoteRole.host;
  bool allows(RemoteScope scope) =>
      session?.allows(scope, DateTime.now()) == true;
  void _notify() {
    if (!_closed) notifyListeners();
    if (!_closed && backgroundService != null) unawaited(_syncBackground());
  }

  bool? _lastBackground;
  Future<void> _syncBackground() async {
    final requested = active || (hostEnabled && settings.flag('background'));
    if (requested == _lastBackground) return;
    _lastBackground = requested;
    try {
      await backgroundService!.reason('remoteHost', requested);
    } catch (_) {
      _lastBackground = null;
      error ??= 'Không tạo được tray. Giữ cửa sổ AMC mở để nhận kết nối.';
    }
  }

  void _check(int generation) {
    if (_closed || generation != _generation) {
      throw StateError('Đã hủy thao tác.');
    }
  }

  Future<void> initialize() async {
    if (initialized) return;
    await reloadDevices();
    await engine.initialize();
    await refreshPermissions();
    backgroundService?.register('remoteHost', shutdown: shutdown);
    initialized = true;
    _notify();
    if (settings.flag('restoreHost') && permissions?.screen == true) {
      await enableHost(port: settings.port);
    }
  }

  Future<void> reloadDevices() async {
    devices = await repository.devices();
    controllers = await repository.controllers();
    history = await repository.history();
    _notify();
  }

  Future<void> refreshPermissions({bool request = false}) async {
    permissions = await _native.permissions(request: request);
    if (permissions!.screen) {
      displays = await engine.displays();
      if (!displays.any((d) => d.id == displayId)) {
        displayId = displays.firstOrNull?.id;
      }
    } else {
      displays = [];
      displayId = null;
    }
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    addresses = interfaces
        .expand((v) => v.addresses)
        .map((v) => v.address)
        .where((v) => isLanAddress(v) && !v.startsWith('127.'))
        .toSet()
        .toList();
    if (hosting && permissions!.screen == false) {
      await disableHost();
    } else if (hosting && permissions!.input == false) {
      await revokeScope(RemoteScope.input);
    }
    _notify();
  }

  Future<void> _action(Future<void> Function() action) async {
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
          : e is HandshakeException
          ? 'Chứng chỉ máy đích không khớp hoặc đã hết hạn. Hãy ghép lại bằng mã mới.'
          : e is SocketException
          ? 'Không tới được máy đích. Kiểm tra IP, cổng, LAN và tường lửa.'
          : 'Không hoàn tất được thao tác. Kiểm tra quyền và thử lại.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> enableHost({int port = 9877, InternetAddress? bindAddress}) =>
      _action(() async {
        if (hostEnabled) return;
        if (permissions?.screen != true || displayId == null) {
          throw StateError('Cấp quyền ghi màn hình và chọn màn hình trước.');
        }
        final generation = _generation;
        final host = LanHostService(
          identity: identity,
          name: name,
          platform: platform,
          repository: repository,
          onRequest: _request,
          onAuthorized: _startHost,
        );
        await host.start(port: port, bindAddress: bindAddress);
        if (_closed || generation != _generation) {
          await host.stop();
          return;
        }
        _host = host;
        if (port > 0) await settings.setPort(host.port);
        status = 'Sẵn sàng nhận yêu cầu trên LAN';
      });
  RemoteInvitation invitation(String address) {
    if (_host == null) throw StateError('Chưa bật nhận kết nối.');
    return _host!.invitation(address);
  }

  Future<void> disableHost() async {
    pendingRequest?.decide(null);
    if (hosting) await disconnect();
    final host = _host;
    _host = null;
    await host?.stop();
    status = 'Đã tắt nhận kết nối';
    _notify();
  }

  void _request(RemotePairRequest request) {
    if (_closed || active || busy || draining) {
      request.decide(null);
      return;
    }
    if (request.internet) {
      try {
        resolveRemoteConnectionMode(
          settings.connectionMode,
          request.connectionMode,
        );
      } on StateError catch (e) {
        error = e.message.toString();
        request.decide(null);
        _notify();
        return;
      }
    }
    pendingRequest = request;
    error = null;
    _cloudSession = request.internet;
    session =
        RemoteSession(
            id: request.sessionId,
            peerId: request.deviceId,
            peerName: request.name,
            role: RemoteRole.host,
            expiresAt: DateTime.now().add(
              request.internet
                  ? const Duration(minutes: 15)
                  : const Duration(hours: 2),
            ),
          )
          ..transition(RemoteSessionState.requesting)
          ..transition(RemoteSessionState.awaitingApproval);
    status = '${request.name} đang xin kết nối';
    unawaited(
      request.decision.future.then((grant) {
        if (identical(pendingRequest, request)) pendingRequest = null;
        if (grant == null && session?.id == request.sessionId && active) {
          session!.transition(RemoteSessionState.ended);
          status = 'Đã từ chối yêu cầu';
        }
        _notify();
      }),
    );
    _notify();
  }

  void accept({bool input = false, bool clipboard = false}) {
    final request = pendingRequest;
    if (request == null) return;
    request.decide({
      RemoteScope.view,
      if (input &&
          permissions?.input == true &&
          request.availableScopes.contains(RemoteScope.input))
        RemoteScope.input,
      if (clipboard && request.availableScopes.contains(RemoteScope.clipboard))
        RemoteScope.clipboard,
    });
  }

  void reject() => pendingRequest?.decide(null);

  void _attach(SignalingTransport connection) {
    _connection = connection;
    _peerClosing = false;
    _signalTail = Future.value();
    _signalSubscription = connection.messages.listen((signal) {
      if ({'disconnect', 'rejected', 'error'}.contains(signal.kind)) {
        _peerClosing = true;
      }
      _signalTail = _signalTail
          .then<void>((_) async {
            if (identical(_connection, connection)) await _signal(signal);
          })
          .catchError((Object e) async {
            if (identical(_connection, connection)) {
              await _fail(
                e is StateError
                    ? e.message.toString()
                    : 'Dữ liệu phiên không hợp lệ hoặc engine không thể xử lý.',
              );
            }
          });
    });
    unawaited(
      connection.done.then((_) {
        if (identical(_connection, connection) && !_closed && !_peerClosing) {
          unawaited(_fail('Kết nối LAN đã đóng.'));
        }
      }),
    );
  }

  void _resetMedia() {
    _firstFrame = _channelsReady = _engineConnected = _viewerReady = false;
    _nativeActive = _displayChanging = _markingConnected = false;
    _sendSequence = frames = 0;
    receivedPackets = appliedInputs = 0;
    fps = kbps = 0;
    networkPath = 'unknown';
    captureRecoveryAttempted = false;
    viewerControl = clipboardEnabled = false;
    remoteDisplays = [];
    remoteDisplayId = null;
  }

  void _watch() {
    _captureRecovery?.cancel();
    final watched = session;
    final generation = _generation;
    _captureRecovery = Timer(captureRetryDelay, () {
      if (!hosting ||
          !identical(session, watched) ||
          session!.state != RemoteSessionState.negotiating ||
          !_engineConnected ||
          !_channelsReady ||
          _viewerReady ||
          displayId == null) {
        return;
      }
      // Reacquire once when transport setup succeeded but the native source
      // has not delivered a usable frame. Never grant input or fake a frame.
      captureRecoveryAttempted = true;
      unawaited(
        engine.switchDisplay(displayId!, quality).catchError((Object _) async {
          if (!_closed && generation == _generation) {
            await _fail('Không khôi phục được capture màn hình.');
          }
        }),
      );
    });
    _deadline?.cancel();
    _deadline = Timer(const Duration(seconds: 25), () {
      if (active && session!.state != RemoteSessionState.connected) {
        unawaited(_fail('Không nhận được hình hoặc kênh dữ liệu sau 25 giây.'));
      }
    });
    _expiry?.cancel();
    _expiry = Timer(
      session!.expiresAt.difference(DateTime.now()),
      () => unawaited(_fail('Phiên đã hết thời hạn. Hãy kết nối lại.')),
    );
    _heartbeat?.cancel();
    _lastHeartbeat = DateTime.now();
    _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!active || session!.state != RemoteSessionState.connected) return;
      if (viewing) {
        unawaited(
          engine.sendControl({'action': 'heartbeat'}).catchError((Object _) {}),
        );
      } else if (DateTime.now().difference(_lastHeartbeat) >
          const Duration(seconds: 4)) {
        unawaited(_native.releaseInputs(session!.id).catchError((Object _) {}));
      }
    });
  }

  Future<void> _startHost(AuthorizedLanPeer peer) async {
    if (_closed ||
        !hostEnabled ||
        session?.id != peer.sessionId ||
        session!.terminal) {
      await peer.connection.close();
      return;
    }
    final generation = ++_generation;
    session!.grant(peer.scopes);
    session!.transition(RemoteSessionState.negotiating);
    _policy = RemoteAccessPolicy(session!);
    _resetMedia();
    _attach(peer.connection);
    _watch();
    status = 'Đang chia sẻ cho ${session!.peerName}';
    _notify();
    try {
      if (!_cloudSession && engine is RemoteNetworkEngine) {
        (engine as RemoteNetworkEngine).configureNetwork([]);
      }
      await onPeerAuthorized?.call(peer);
      _check(generation);
      final offer = await engine.createOffer(displayId!, quality);
      _check(generation);
      peer.connection.send(peer.sessionId, 'offer', {
        'sdp': offer,
        'displayId': displayId,
        'displays': displays.map((v) => v.toJson()).toList(),
        'quality': quality.name,
      });
      await reloadDevices();
    } catch (e) {
      if (!_closed && generation == _generation) {
        await _fail(
          e is StateError
              ? e.message.toString()
              : 'Không capture được màn hình. Kiểm tra quyền ghi màn hình.',
        );
      }
    }
  }

  void acceptCloudTransport(
    SignalingTransport transport,
    String sessionId,
    String peerName,
  ) {
    if (!hostEnabled || active || draining || _closed) {
      unawaited(transport.close());
      return;
    }
    _host!.acceptTransport(
      transport,
      sessionId: sessionId,
      address: 'Internet · $peerName',
      internet: true,
    );
  }

  Future<void> connectCloud(
    SignalingTransport transport, {
    required String peerId,
    required String peerName,
    required String credential,
    bool remember = true,
  }) => _action(() async {
    if (active ||
        draining ||
        _closed ||
        _connection != null ||
        peerId == identity.id) {
      await transport.close();
      throw StateError('Không mở được phiên Internet lúc này.');
    }
    _generation++;
    _resetMedia();
    _cloudSession = true;
    _connectionMode = settings.connectionMode;
    _cloudPeerId = peerId;
    _lastEndpoint = null;
    _clientCredential = credential;
    _remember = remember;
    _attach(transport);
    status = 'Đang chờ $peerName chấp nhận qua Internet';
    _deadline?.cancel();
    _deadline = Timer(
      const Duration(seconds: 70),
      () => unawaited(_fail('Yêu cầu Internet đã hết thời gian.')),
    );
  });

  Future<void> connectInvitation(
    String value, {
    bool remember = true,
  }) => _action(() async {
    final invitation = RemoteInvitation.decode(value.trim(), DateTime.now());
    await _connect(invitation.endpoint, invitation.token, remember: remember);
  });
  Future<void> connectSaved(RemoteDevice device) => _action(() async {
    final token = await credentials.read('peer.${device.endpoint.deviceId}');
    if (token == null) {
      throw StateError('Thiếu credential trên máy này. Ghép lại bằng mã mới.');
    }
    await _connect(device.endpoint, token, remember: true);
  });
  Future<void> _connect(
    RemoteEndpoint endpoint,
    String credential, {
    required bool remember,
  }) async {
    if (active || _connection != null || draining) {
      throw StateError('Hãy ngắt phiên hiện tại trước.');
    }
    if (endpoint.deviceId == identity.id) {
      throw StateError('Đây là chính máy này.');
    }
    final generation = ++_generation;
    _cloudSession = false;
    _cloudPeerId = null;
    if (engine is RemoteNetworkEngine) {
      (engine as RemoteNetworkEngine).configureNetwork([]);
    }
    _resetMedia();
    status = 'Đang kết nối ${endpoint.name}';
    _lastEndpoint = endpoint;
    _notify();
    final connection = await LanConnection.connect(endpoint);
    if (_closed || generation != _generation) {
      await connection.close();
      return;
    }
    _attach(connection);
    _clientCredential = credential;
    _remember = remember;
    _deadline?.cancel();
    _deadline = Timer(
      const Duration(seconds: 70),
      () => unawaited(
        _fail('Máy đích chưa chấp nhận yêu cầu hoặc đã hết thời gian.'),
      ),
    );
  }

  String? _clientCredential;
  bool _remember = false;
  bool _peerClosing = false;
  bool get draining => _disconnecting != null;
  Future<void> _signal(RemoteSignal signal) async {
    final connection = _connection;
    if (connection == null) return;
    if (signal.kind == 'hello') {
      final peerId = _lastEndpoint?.deviceId ?? _cloudPeerId;
      if (session != null && !session!.terminal ||
          signal.data['deviceId'] != peerId) {
        throw const FormatException('Host identity mismatch');
      }
      session =
          RemoteSession(
              id: signal.sessionId,
              peerId: peerId!,
              peerName: remoteName(signal.data['name']),
              role: RemoteRole.viewer,
              expiresAt: DateTime.now().add(
                _cloudSession
                    ? const Duration(minutes: 15)
                    : const Duration(hours: 2),
              ),
            )
            ..transition(RemoteSessionState.requesting)
            ..transition(RemoteSessionState.awaitingApproval);
      remotePlatform = signal.data['platform'] as String?;
      connection.send(signal.sessionId, 'request', {
        'deviceId': identity.id,
        'name': name,
        'platform': platform,
        'credential': _clientCredential,
        'remember': _remember,
        'scopes': RemoteScope.values.map((v) => v.name).toList(),
        if (_cloudSession) 'connectionMode': _connectionMode.name,
      });
      _clientCredential = null;
      status = 'Đang chờ máy đích chấp nhận';
    } else if (signal.kind == 'pending') {
      status = 'Máy đích đang xem yêu cầu kết nối';
    } else if (signal.kind == 'approved') {
      if (!viewing || session!.state != RemoteSessionState.awaitingApproval) {
        throw const FormatException('Unexpected approval');
      }
      session!.grant(parseScopes(signal.data['scopes']));
      session!.transition(RemoteSessionState.negotiating);
      _policy = RemoteAccessPolicy(session!);
      if (_remember && signal.data['trustToken'] is String) {
        final token = signal.data['trustToken'] as String;
        if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
          throw const FormatException('Invalid token');
        }
        await credentials.write('peer.${session!.peerId}', token);
      }
      if (_remember && _lastEndpoint != null) {
        await repository.saveDevice(
          RemoteDevice(
            endpoint: _lastEndpoint!,
            platform: remotePlatform ?? 'unknown',
            lastConnectedAt: DateTime.now(),
          ),
        );
        await reloadDevices();
      }
      if (_remember && _cloudSession) await onCloudRemembered?.call();
      status = 'Đã chấp nhận, đang chờ màn hình';
      _watch();
    } else if (signal.kind == 'offer') {
      if (!viewing || session!.state != RemoteSessionState.negotiating) {
        throw const FormatException('Unexpected offer');
      }
      remoteDisplays = _parseDisplays(signal.data['displays']);
      remoteDisplayId = signal.data['displayId'] as String;
      final answer = await engine.answerOffer(_sdp(signal.data['sdp']));
      if (!identical(connection, _connection)) return;
      connection.send(signal.sessionId, 'answer', {'sdp': answer});
    } else if (signal.kind == 'answer') {
      if (!hosting || session!.state != RemoteSessionState.negotiating) {
        throw const FormatException('Unexpected answer');
      }
      await engine.applyAnswer(_sdp(signal.data['sdp']));
    } else if (signal.kind == 'ready') {
      if (!hosting) {
        throw const FormatException('Unexpected media confirmation');
      }
      _viewerReady = true;
      await _maybeConnected();
    } else if (signal.kind == 'rejected' || signal.kind == 'error') {
      final reason = signal.data['reason'];
      await _fail(
        reason is String && reason.length <= 200
            ? reason
            : 'Máy đích từ chối kết nối.',
      );
    } else if (signal.kind == 'disconnect') {
      await disconnect();
    } else {
      throw const FormatException('Unexpected signaling message');
    }
    _notify();
  }

  String _sdp(Object? value) {
    if (value is! String ||
        value.length > 196608 ||
        !value.startsWith('v=0') ||
        !value.contains('a=fingerprint:sha-256 ')) {
      throw const FormatException('Invalid SDP');
    }
    return value;
  }

  List<DisplayDescriptor> _parseDisplays(Object? value) {
    if (value is! List || value.isEmpty || value.length > 32) {
      throw const FormatException('Invalid displays');
    }
    return value
        .map((v) => DisplayDescriptor.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  Future<void> _engineEvent(RemoteEngineEvent event) async {
    final current = session;
    if (_closed || current == null || current.terminal) return;
    switch (event.kind) {
      case EngineEventKind.firstFrame:
        _firstFrame = true;
        await _maybeConnected();
      case EngineEventKind.connected:
        _engineConnected = true;
        await _maybeConnected();
      case EngineEventKind.channelReady:
        _channelsReady = true;
        await _maybeConnected();
      case EngineEventKind.disconnected:
        if (current.state == RemoteSessionState.connected) {
          current.transition(RemoteSessionState.reconnecting);
          _engineConnected = false;
          _channelsReady = event.data['channelsOpen'] == true;
          _firstFrame = false;
          _viewerReady = false;
          _framesAtDisconnect = frames;
          viewerControl = false;
          await _endNative();
          status = 'Mất tín hiệu, đang khôi phục (tối đa 8 giây)';
          _recovery?.cancel();
          _recovery = Timer(
            const Duration(seconds: 8),
            () => unawaited(
              _fail('Không khôi phục được phiên. Hãy kết nối lại.'),
            ),
          );
        }
      case EngineEventKind.packet:
        await _packet(event.data['packet'] as RemoteInputPacket);
      case EngineEventKind.control:
        await _control(event.data);
      case EngineEventKind.stats:
        networkPath = event.data['path'] as String? ?? 'unknown';
        frames = event.data['frames'] as int;
        fps = (event.data['fps'] as num).toDouble();
        kbps = (event.data['kbps'] as num).toDouble();
        if (viewing &&
            current.state == RemoteSessionState.reconnecting &&
            frames > _framesAtDisconnect) {
          _firstFrame = true;
          await _maybeConnected();
        }
      case EngineEventKind.error:
        final reason = event.data['reason'];
        await _fail(
          reason is String && reason.length <= 240
              ? reason
              : 'Kênh điều khiển gửi dữ liệu không hợp lệ.',
        );
    }
    _notify();
  }

  Future<void> _maybeConnected() async {
    final current = session;
    if (current == null ||
        current.terminal ||
        _markingConnected ||
        !_engineConnected ||
        !_channelsReady ||
        !(current.role == RemoteRole.viewer ? _firstFrame : _viewerReady) ||
        !{
          RemoteSessionState.negotiating,
          RemoteSessionState.reconnecting,
        }.contains(current.state)) {
      return;
    }
    _markingConnected = true;
    try {
      current.transition(RemoteSessionState.connected);
      _deadline?.cancel();
      _captureRecovery?.cancel();
      _recovery?.cancel();
      if (current.role == RemoteRole.viewer) {
        _connection?.send(current.id, 'ready');
      } else if (current.allows(RemoteScope.input, DateTime.now())) {
        try {
          await _native.beginInput(current.id, displayId!);
          if (!identical(session, current) || current.terminal) {
            await _native.endInput(current.id);
            return;
          }
          _nativeActive = true;
        } catch (_) {
          await revokeScope(RemoteScope.input);
          error = 'Không nhận được quyền chuột/phím. Phiên vẫn xem được.';
        }
      }
      status = current.role == RemoteRole.viewer
          ? 'Đã nhận màn hình từ ${current.peerName}'
          : '${current.peerName} đang xem máy này';
    } finally {
      _markingConnected = false;
      _notify();
    }
  }

  Future<void> _packet(RemoteInputPacket packet) async {
    receivedPackets++;
    if (!active || _policy?.accept(packet, DateTime.now()) != true) return;
    if (packet.input is RemoteClipboard) {
      if ((hosting || clipboardEnabled) && allows(RemoteScope.clipboard)) {
        final current = session;
        await Clipboard.setData(
          ClipboardData(text: (packet.input as RemoteClipboard).text),
        );
        if (identical(current, session) && allows(RemoteScope.clipboard)) {
          await engine.sendControl({
            'action': 'clipboard-applied',
            'sequence': packet.sequence,
          });
        }
      }
    } else if (hosting &&
        _nativeActive &&
        !_displayChanging &&
        packet.displayId == displayId) {
      try {
        await _native.sendInput(session!.id, packet.input.toJson());
        appliedInputs++;
      } catch (_) {
        await revokeScope(RemoteScope.input);
        error = 'Đã dừng input vì hệ điều hành từ chối thao tác.';
      }
    }
  }

  Future<void> _control(Map<String, dynamic> value) async {
    if (!allows(RemoteScope.view)) return;
    switch (value['action']) {
      case 'heartbeat':
        if (hosting) _lastHeartbeat = DateTime.now();
      case 'clipboard-applied':
        final sequence = value['sequence'];
        if (viewing && sequence is int) {
          _clipboardAcks.remove(sequence)?.complete();
        }
      case 'display':
        if (!hosting || _displayChanging) return;
        final current = session!;
        final generation = _generation;
        final id = value['displayId'];
        final preset = value['quality'];
        if (id is! String ||
            !displays.any((d) => d.id == id) ||
            !RemoteQuality.values.any((q) => q.name == preset)) {
          return;
        }
        _displayChanging = true;
        try {
          await _endNative();
          await engine.switchDisplay(
            id,
            RemoteQuality.values.byName(preset as String),
          );
          if (!hosting || generation != _generation) return;
          displayId = id;
          quality = RemoteQuality.values.byName(preset);
          if (allows(RemoteScope.input)) {
            await _native.beginInput(current.id, id);
            if (!hosting || generation != _generation) {
              await _native.endInput(current.id);
              return;
            }
            _nativeActive = true;
          }
          await engine.sendControl({
            'action': 'display-changed',
            'displayId': id,
            'quality': quality.name,
          });
        } finally {
          if (generation == _generation) _displayChanging = false;
        }
      case 'display-changed':
        if (viewing && remoteDisplays.any((d) => d.id == value['displayId'])) {
          remoteDisplayId = value['displayId'] as String;
          quality = RemoteQuality.values.byName(value['quality'] as String);
        }
      case 'clipboard-request':
        if (hosting && allows(RemoteScope.clipboard)) {
          final current = session!;
          final text =
              (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
          if (!identical(session, current) ||
              !hosting ||
              !allows(RemoteScope.clipboard)) {
            return;
          }
          try {
            await engine.sendPacket(
              RemoteInputPacket(
                sessionId: current.id,
                sequence: _sendSequence++,
                input: RemoteClipboard(text),
              ),
            );
          } on FormatException {
            error = 'Clipboard lớn hơn 16 KB; chỉ đồng bộ văn bản ngắn.';
          }
        }
      case 'scopes':
        if (!viewing) return;
        final scopes = parseScopes(value['scopes']);
        for (final scope in session!.scopes.toList()) {
          if (!scopes.contains(scope)) session!.revoke(scope);
        }
        if (!allows(RemoteScope.input)) viewerControl = false;
        if (!allows(RemoteScope.clipboard)) clipboardEnabled = false;
    }
  }

  Future<void> sendInput(RemoteInput input) async {
    if (!viewing || !viewerControl || !allows(RemoteScope.input)) return;
    try {
      await engine.sendPacket(
        RemoteInputPacket(
          sessionId: session!.id,
          sequence: _sendSequence++,
          input: input,
          displayId: remoteDisplayId,
        ),
      );
    } catch (_) {
      await _fail('Không gửi được thao tác. Đã ngắt phiên để tránh kẹt phím.');
    }
  }

  Future<void> sendText(String text) async {
    if (!viewing || !allows(RemoteScope.input) || text.isEmpty) return;
    final current = session!;
    await releaseViewerInput();
    if (!identical(session, current) ||
        !viewing ||
        !allows(RemoteScope.input)) {
      return;
    }
    try {
      await engine.sendPacket(
        RemoteInputPacket(
          sessionId: session!.id,
          sequence: _sendSequence++,
          input: RemoteText(text),
          displayId: remoteDisplayId,
        ),
      );
    } on FormatException {
      error = 'Mỗi lần gửi tối đa 1024 ký tự.';
      _notify();
    } catch (_) {
      await _fail('Không gửi được văn bản.');
    }
  }

  Future<void> chooseHostDisplay(String id) => _action(() async {
    if (!displays.any((d) => d.id == id)) return;
    if (hosting) {
      await _control({
        'action': 'display',
        'displayId': id,
        'quality': quality.name,
      });
    } else {
      displayId = id;
    }
  });
  Future<void> releaseViewerInput() async {
    viewerControl = false;
    _notify();
    if (viewing && allows(RemoteScope.input)) {
      try {
        await engine.sendPacket(
          RemoteInputPacket(
            sessionId: session!.id,
            sequence: _sendSequence++,
            input: const RemoteRelease(),
            displayId: remoteDisplayId,
          ),
        );
      } catch (_) {
        await _fail('Kênh điều khiển đã đóng.');
      }
    }
  }

  void takeControl() {
    viewerControl = viewing && allows(RemoteScope.input);
    _notify();
  }

  Future<void> changeDisplay(String id, RemoteQuality preset) async {
    if (!viewing || !allows(RemoteScope.view)) return;
    final current = session!;
    await releaseViewerInput();
    if (!identical(session, current) || !viewing || !allows(RemoteScope.view)) {
      return;
    }
    await engine.sendControl({
      'action': 'display',
      'displayId': id,
      'quality': preset.name,
    });
  }

  Future<bool> syncClipboardForPaste() async {
    final current = session;
    if (!viewing || !clipboardEnabled || !allows(RemoteScope.clipboard)) {
      return false;
    }
    int? seq;
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      if (!identical(current, session) ||
          !viewing ||
          !clipboardEnabled ||
          !allows(RemoteScope.clipboard)) {
        return false;
      }
      seq = _sendSequence++;
      final ack = Completer<void>();
      _clipboardAcks[seq] = ack;
      await engine.sendPacket(
        RemoteInputPacket(
          sessionId: current!.id,
          sequence: seq,
          input: RemoteClipboard(text),
        ),
      );
      await ack.future.timeout(const Duration(seconds: 2));
      return identical(current, session) &&
          viewing &&
          allows(RemoteScope.clipboard) &&
          allows(RemoteScope.input);
    } catch (_) {
      error =
          'Chưa xác nhận clipboard ở máy đích; đã bỏ thao tác dán. Kiểm tra quyền hoặc gửi văn bản trực tiếp.';
      _notify();
      return false;
    } finally {
      if (seq != null) _clipboardAcks.remove(seq);
    }
  }

  Future<void> clipboard({required bool pull}) async {
    if (!viewing || !clipboardEnabled || !allows(RemoteScope.clipboard)) return;
    final current = session!;
    try {
      if (pull) {
        await engine.sendControl({'action': 'clipboard-request'});
      } else {
        final text =
            (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
        if (!identical(session, current) ||
            !viewing ||
            !clipboardEnabled ||
            !allows(RemoteScope.clipboard)) {
          return;
        }
        await engine.sendPacket(
          RemoteInputPacket(
            sessionId: session!.id,
            sequence: _sendSequence++,
            input: RemoteClipboard(text),
          ),
        );
      }
    } on FormatException {
      error = 'Clipboard lớn hơn 16 KB; chỉ đồng bộ văn bản ngắn.';
      _notify();
    }
  }

  Future<void> revokeScope(RemoteScope scope) async {
    if (!hosting || session == null) return;
    final current = session!;
    current.revoke(scope);
    if (scope == RemoteScope.input) await _endNative();
    if (!identical(session, current) || !hosting) return;
    await engine.sendControl({
      'action': 'scopes',
      'scopes': session!.scopes.map((s) => s.name).toList(),
    });
    _notify();
  }

  Future<void> _endNative() async {
    _nativeActive = false;
    final id = session?.id;
    if (id != null) await _native.endInput(id).catchError((Object _) {});
  }

  Future<void> forgetDevice(RemoteDevice device) => _action(() async {
    await repository.removeDevice(device.endpoint.deviceId);
    await credentials.delete('peer.${device.endpoint.deviceId}');
    await reloadDevices();
  });
  Future<void> updateDeviceAddress(
    RemoteDevice device,
    String address,
    int port,
    String alias,
  ) => _action(() async {
    final endpoint = RemoteEndpoint(
      address: address.trim(),
      port: port,
      fingerprint: device.endpoint.fingerprint,
      deviceId: device.endpoint.deviceId,
      name: alias.trim(),
    );
    await repository.saveDevice(
      RemoteDevice(
        endpoint: endpoint,
        platform: device.platform,
        lastConnectedAt: device.lastConnectedAt,
      ),
    );
    deviceOnline.remove(endpoint.deviceId);
    await reloadDevices();
  });
  Future<void> probeDevices() => _action(() async {
    if (_lastProbe != null &&
        DateTime.now().difference(_lastProbe!) < const Duration(seconds: 30)) {
      throw StateError('Chờ 30 giây trước khi kiểm tra trạng thái lần nữa.');
    }
    _lastProbe = DateTime.now();
    final targets = devices.take(12).toList();
    for (var offset = 0; offset < targets.length; offset += 4) {
      await Future.wait(
        targets.skip(offset).take(4).map((device) async {
          LanConnection? probe;
          try {
            probe = await LanConnection.connect(device.endpoint);
            final hello = await probe.messages.first.timeout(
              const Duration(seconds: 5),
            );
            deviceOnline[device.endpoint.deviceId] =
                hello.kind == 'hello' &&
                hello.data['deviceId'] == device.endpoint.deviceId;
          } catch (_) {
            deviceOnline[device.endpoint.deviceId] = false;
          } finally {
            await probe?.close();
            _notify();
          }
        }),
      );
      if (_closed) return;
    }
  });
  Future<void> revokeController(String id) => _action(() async {
    if (_host != null) {
      await _host!.revoke(id);
    } else {
      await repository.removeController(id);
    }
    if (hosting && session!.peerId == id) await disconnect();
    await reloadDevices();
    await onControllerRevoked?.call(id);
  });
  Future<void> _fail(String message) async {
    error = message;
    await disconnect(failed: true);
  }

  Future<void> disconnect({bool failed = false}) =>
      _disconnecting ??= _disconnect(failed).whenComplete(() {
        _disconnecting = null;
        _notify();
      });
  Future<void> _disconnect(bool failed) async {
    final ending = active ? session : null;
    _generation++;
    pendingRequest?.decide(null);
    pendingRequest = null;
    _deadline?.cancel();
    _heartbeat?.cancel();
    _expiry?.cancel();
    _recovery?.cancel();
    _captureRecovery?.cancel();
    viewerControl = clipboardEnabled = false;
    // A pending paste must not resume in a later session.
    for (final ack in _clipboardAcks.values) {
      if (!ack.isCompleted) ack.complete();
    }
    _clipboardAcks.clear();
    if (active) {
      session!.transition(
        failed ? RemoteSessionState.failed : RemoteSessionState.ended,
      );
    }
    await _endNative();
    final connection = _connection;
    _connection = null;
    await _signalSubscription?.cancel();
    _signalSubscription = null;
    try {
      if (connection != null && session != null) {
        connection.send(session!.id, 'disconnect');
      }
    } catch (_) {}
    await connection?.close();
    await engine.stop();
    if (ending != null) {
      try {
        await repository.appendHistory(
          RemoteSessionRecord(
            sessionId: ending.id,
            peerName: ending.peerName,
            role: ending.role,
            endedAt: DateTime.now(),
            failed: failed,
            frames: frames,
          ),
        );
        history = await repository.history();
      } catch (_) {
        error ??= 'Phiên đã ngắt nhưng chưa lưu được lịch sử trên máy này.';
      }
    }
    _firstFrame = false;
    _clientCredential = null;
    status = failed ? 'Phiên đã gián đoạn' : 'Đã ngắt phiên';
    _notify();
  }

  Future<void> shutdown() => _shutdownFuture ??= _shutdown();
  Map<String, Object?> diagnostics() => {
    'state': session?.state.name,
    'role': session?.role.name,
    'firstFrame': _firstFrame,
    'channelsReady': _channelsReady,
    'engineConnected': _engineConnected,
    'frames': frames,
    'fps': fps,
    'networkPath': networkPath,
    'captureRecoveryAttempted': captureRecoveryAttempted,
    'kbps': kbps,
    'receivedPackets': receivedPackets,
    'appliedInputs': appliedInputs,
    'nativeInputActive': _nativeActive,
    'draining': draining,
    'scopes': session?.scopes.map((s) => s.name).toList(),
    'savedDevices': devices.length,
    'trustedControllers': controllers.length,
    'history': history.length,
    'inputPermission': permissions?.input,
    'screenPermission': permissions?.screen,
    'error': error,
  };
  Future<void> _shutdown() async {
    _closed = true;
    await stopInternet?.call();
    _lifecycle?.dispose();
    await disconnect();
    await _host?.stop();
    _host = null;
    await _engineSubscription.cancel();
    await engine.dispose();
    await backgroundService
        ?.reason('remoteHost', false)
        .catchError((Object _) {});
    if (identical(current.value, this)) {
      current.value = null;
      _opening = null;
    }
    super.dispose();
  }
}
