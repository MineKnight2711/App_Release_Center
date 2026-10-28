import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:amc_remote_core/probe_signal.dart';
import 'package:amc_remote_platform/amc_remote_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

enum ProbeMode { loopback, host, viewer }

/// Disposable Phase 0 experiment. No cloud registration, listener socket, saved
/// passwords or automatic input; production runtime will be built after the
/// two-machine engine gate has passed.
class SwiftDeskProbe extends ChangeNotifier {
  SwiftDeskProbe({AmcRemotePlatform platform = const AmcRemotePlatform()})
    : _platform = platform;

  final AmcRemotePlatform _platform;
  final renderer = RTCVideoRenderer();
  final sources = <DesktopCapturerSource>[];
  RemotePlatformPermissions? permissions;
  String? sourceId;
  String status = 'Chưa bắt đầu';
  String? error;
  bool initialized = false;
  bool busy = false;
  bool inputEnabled = false;
  bool firstFrame = false;
  ProbeMode? mode;
  String? localSignal;
  int framesDecoded = 0;
  double framesPerSecond = 0;
  int receivedBytes = 0;
  int? dataRoundTripMs;
  String candidateType = '';
  int appliedInputs = 0;

  String? _sessionId;
  String? _capturedSourceId;
  RemoteInputGate? _inputGate;
  MediaStream? _capture;
  RTCPeerConnection? _host;
  RTCPeerConnection? _viewer;
  RTCDataChannel? _sender;
  final _channels = <RTCDataChannel>[];
  Timer? _statsTimer;
  Timer? _frameDeadline;
  DateTime? _lastSample;
  int _lastFrames = 0;
  int _sequence = 0;
  bool _cancelled = false;
  bool _closed = false;
  bool _sampling = false;
  Future<void>? _operation;
  Future<void>? _closing;
  Completer<void>? _frameWaiter;

  static bool get supported => Platform.isWindows || Platform.isMacOS;
  bool get hasSession => _host != null || _viewer != null;
  bool get dataReady =>
      _sender?.state == RTCDataChannelState.RTCDataChannelOpen;
  bool get canReceiveInput =>
      _host?.connectionState ==
      RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _check() {
    if (_cancelled || _closed) throw StateError('Đã dừng phiên');
  }

  Future<void> initialize() => _run(() async {
    if (!supported) throw UnsupportedError('Bản thử hỗ trợ Windows và macOS.');
    await renderer.initialize();
    initialized = true;
    renderer.onFirstFrameRendered = () {
      if (_cancelled || _closed) return;
      firstFrame = true;
      status = 'Đã nhận hình qua WebRTC';
      if (!(_frameWaiter?.isCompleted ?? true)) _frameWaiter!.complete();
      _notify();
    };
    await _refreshPermissions();
    status = permissions!.screen
        ? 'Sẵn sàng thử'
        : 'Cần cấp quyền ghi màn hình';
  });

  Future<void> refreshPermissions({bool request = false}) => _run(() async {
    await _refreshPermissions(request: request);
  });

  Future<void> _refreshPermissions({bool request = false}) async {
    permissions = await _platform.permissions(request: request);
    _check();
    if (permissions!.screen) {
      final available = await desktopCapturer.getSources(
        types: [SourceType.Screen],
      );
      _check();
      sources
        ..clear()
        ..addAll(available);
      if (!sources.any((s) => s.id == sourceId)) {
        sourceId = sources.firstOrNull?.id;
      }
    } else {
      sources.clear();
      sourceId = null;
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool preserveSessionOnError = false,
  }) async {
    if (_closed || busy) return;
    busy = true;
    _cancelled = false;
    error = null;
    _notify();
    final done = Completer<void>();
    _operation = done.future;
    try {
      await action();
      _check();
    } catch (e) {
      if (!_cancelled && !_closed) {
        // Never include pasted SDP or TURN credentials in diagnostics.
        error = e is FormatException
            ? e.message.toString()
            : e is StateError
            ? e.message.toString()
            : 'Không hoàn tất được thao tác (${e.runtimeType}). Kiểm tra quyền và thử lại.';
        status = 'Thao tác chưa hoàn tất';
      }
      if (!preserveSessionOnError || _cancelled || _closed) await _cleanup();
    } finally {
      busy = false;
      _operation = null;
      done.complete();
      _notify();
    }
  }

  Map<String, dynamic> _configuration({
    required bool relayOnly,
    required String turnUrl,
    required String turnUser,
    required String turnPassword,
  }) {
    if (relayOnly &&
        (!RegExp(r'^turns?:[^\s]+$').hasMatch(turnUrl) ||
            turnUser.isEmpty ||
            turnPassword.isEmpty)) {
      throw const FormatException(
        'Nhập TURN URL, tài khoản và credential để thử relay.',
      );
    }
    return {
      'iceServers': [
        if (relayOnly)
          {'urls': turnUrl, 'username': turnUser, 'credential': turnPassword},
      ],
      'iceTransportPolicy': relayOnly ? 'relay' : 'all',
      'sdpSemantics': 'unified-plan',
    };
  }

  Future<RTCPeerConnection> _newPeer(
    Map<String, dynamic> config, {
    required bool viewer,
  }) async {
    final peer = await createPeerConnection(config);
    if (viewer) {
      _viewer = peer;
    } else {
      _host = peer;
    }
    _check();
    peer.onConnectionState = (state) {
      if (_cancelled || _closed) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _inputGate?.setEnabled(false);
        inputEnabled = false;
        unawaited(_endNativeInput());
        status = 'Kết nối đã gián đoạn; dừng và tạo phiên mới để thử lại';
      } else if (!firstFrame) {
        status = state == RTCPeerConnectionState.RTCPeerConnectionStateConnected
            ? (mode == ProbeMode.host
                  ? 'Viewer đã kết nối'
                  : 'Đã kết nối, đang chờ hình')
            : 'Đang thương lượng kết nối';
      }
      _notify();
    };
    if (viewer) {
      peer.onTrack = (event) {
        if (!_cancelled &&
            !_closed &&
            event.track.kind == 'video' &&
            event.streams.isNotEmpty) {
          renderer.srcObject = event.streams.first;
        }
      };
      peer.onDataChannel = (channel) => _bind(channel, receiveInput: false);
    }
    return peer;
  }

  Future<void> _startCapture() async {
    if (sourceId == null) {
      throw StateError('Chọn màn hình và cấp quyền trước khi thử.');
    }
    _capturedSourceId = sourceId;
    _capture = await navigator.mediaDevices.getDisplayMedia({
      'audio': false,
      'video': {
        'deviceId': {'exact': sourceId},
        'mandatory': {'frameRate': 30.0},
      },
    });
    _check();
    if (_capture!.getVideoTracks().isEmpty) {
      throw StateError('Engine không tạo được video track.');
    }
    for (final track in _capture!.getVideoTracks()) {
      track.onEnded = () {
        if (!_cancelled && !_closed) unawaited(stop());
      };
      await _host!.addTrack(track, _capture!);
      _check();
    }
    final channel = await _host!.createDataChannel(
      'amc-probe-reliable',
      RTCDataChannelInit(),
    );
    _check();
    _bind(channel, receiveInput: true);
  }

  void _bind(RTCDataChannel channel, {required bool receiveInput}) {
    if (_cancelled || _closed) {
      unawaited(channel.close().catchError((Object _) {}));
      return;
    }
    _channels.add(channel);
    if (!receiveInput) _sender = channel;
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _inputGate?.setEnabled(false);
        inputEnabled = false;
        unawaited(_endNativeInput());
      }
      _notify();
    };
    channel.onMessage = (message) {
      if (!message.isBinary && !_cancelled && !_closed) {
        unawaited(_receive(channel, message.text, receiveInput));
      }
    };
  }

  Future<void> _receive(
    RTCDataChannel channel,
    String text,
    bool receiveInput,
  ) async {
    try {
      if (text.length > 16384) return;
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return;
      if (json['probe'] == 'ping' && json['time'] is int && receiveInput) {
        await channel.send(
          RTCDataChannelMessage(
            jsonEncode({'probe': 'pong', 'time': json['time']}),
          ),
        );
      } else if (json['probe'] == 'pong' &&
          json['time'] is int &&
          !receiveInput) {
        final elapsed =
            DateTime.now().millisecondsSinceEpoch - (json['time'] as int);
        if (elapsed >= 0 && elapsed < 60000) dataRoundTripMs = elapsed;
      } else if (receiveInput && inputEnabled && canReceiveInput) {
        final packet = RemoteInputPacket.decode(text);
        if (_inputGate?.accept(packet, now: DateTime.now()) != true) return;
        await _platform.sendInput(packet.sessionId, packet.input.toJson());
        appliedInputs++;
      }
      _notify();
    } catch (_) {
      if (receiveInput && inputEnabled) {
        inputEnabled = false;
        _inputGate?.setEnabled(false);
        await _endNativeInput();
        error =
            'Đã tắt input vì sự kiện bị từ chối. Kiểm tra lại quyền trên host.';
        _notify();
      }
    }
  }

  Future<RTCSessionDescription> _description(
    RTCPeerConnection peer, {
    required bool offer,
  }) async {
    final description = offer
        ? await peer.createOffer()
        : await peer.createAnswer();
    _check();
    await peer.setLocalDescription(description);
    final started = DateTime.now();
    while (await peer.getIceGatheringState() !=
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      _check();
      if (DateTime.now().difference(started) > const Duration(seconds: 15)) {
        throw StateError(
          'Hết thời gian thu thập ICE. Kiểm tra TURN hoặc thử LAN.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _check();
    final result = await peer.getLocalDescription();
    if (result?.sdp == null) throw StateError('Engine không trả SDP.');
    return result!;
  }

  Future<void> startLoopback({
    bool relayOnly = false,
    String turnUrl = '',
    String turnUser = '',
    String turnPassword = '',
  }) => _run(() async {
    await _prepare(ProbeMode.loopback);
    final config = _configuration(
      relayOnly: relayOnly,
      turnUrl: turnUrl,
      turnUser: turnUser,
      turnPassword: turnPassword,
    );
    await _newPeer(config, viewer: false);
    await _newPeer(config, viewer: true);
    await _startCapture();
    final offer = await _description(_host!, offer: true);
    await _viewer!.setRemoteDescription(offer);
    final answer = await _description(_viewer!, offer: false);
    await _host!.setRemoteDescription(answer);
    _startStats();
  });

  Future<void> createHostOffer({
    bool relayOnly = false,
    String turnUrl = '',
    String turnUser = '',
    String turnPassword = '',
  }) => _run(() async {
    await _prepare(ProbeMode.host);
    await _newPeer(
      _configuration(
        relayOnly: relayOnly,
        turnUrl: turnUrl,
        turnUser: turnUser,
        turnPassword: turnPassword,
      ),
      viewer: false,
    );
    await _startCapture();
    final offer = await _description(_host!, offer: true);
    localSignal = _signal(offer);
    status = 'Gửi mã mời cho viewer, rồi nhập mã trả lời';
    _startStats();
  });

  Future<void> joinOffer(
    String value, {
    bool relayOnly = false,
    String turnUrl = '',
    String turnUser = '',
    String turnPassword = '',
  }) => _run(() async {
    final offer = ProbeSignal.decode(value, now: DateTime.now());
    if (offer.type != 'offer') {
      throw const FormatException('Cần mã mời của host.');
    }
    await _prepare(ProbeMode.viewer, sessionId: offer.sessionId);
    await _newPeer(
      _configuration(
        relayOnly: relayOnly,
        turnUrl: turnUrl,
        turnUser: turnUser,
        turnPassword: turnPassword,
      ),
      viewer: true,
    );
    await _viewer!.setRemoteDescription(
      RTCSessionDescription(offer.sdp, offer.type),
    );
    final answer = await _description(_viewer!, offer: false);
    localSignal = _signal(answer);
    status = 'Gửi mã trả lời về host để hoàn tất';
    _startStats();
  });

  Future<void> applyAnswer(String value) => _run(() async {
    final answer = ProbeSignal.decode(value, now: DateTime.now());
    if (mode != ProbeMode.host ||
        _host == null ||
        answer.type != 'answer' ||
        answer.sessionId != _sessionId) {
      throw const FormatException('Mã trả lời không thuộc phiên host đang mở.');
    }
    await _host!.setRemoteDescription(
      RTCSessionDescription(answer.sdp, answer.type),
    );
    localSignal = null;
  });

  String _signal(RTCSessionDescription description) => ProbeSignal(
    sessionId: _sessionId!,
    type: description.type!,
    sdp: description.sdp!,
    expiresAt: DateTime.now().add(const Duration(minutes: 10)),
  ).encode();

  Future<void> _prepare(ProbeMode next, {String? sessionId}) async {
    await _cleanup();
    _check();
    if (!initialized) throw StateError('Engine chưa sẵn sàng.');
    mode = next;
    _sessionId = sessionId ?? const Uuid().v4();
    _inputGate = RemoteInputGate(
      sessionId: _sessionId!,
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
    );
    _sequence = 0;
    firstFrame = false;
    framesDecoded = receivedBytes = appliedInputs = _lastFrames = 0;
    framesPerSecond = 0;
    candidateType = '';
    dataRoundTripMs = null;
    _lastSample = null;
    _frameWaiter = Completer<void>();
    status = 'Đang tạo phiên thử';
  }

  void _startStats() {
    _statsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(sampleStats()),
    );
    if (mode != ProbeMode.host) {
      _frameDeadline = Timer(const Duration(seconds: 20), () {
        if (!firstFrame && !_closed && !_cancelled) {
          error =
              'Không nhận được frame màn hình sau 20 giây. Kiểm tra quyền capture và mạng.';
          unawaited(stop());
        }
      });
    }
  }

  Future<void> sampleStats() async {
    if (_sampling || _cancelled || _closed) return;
    final peer = _viewer ?? _host;
    if (peer == null) return;
    _sampling = true;
    try {
      final reports = await peer.getStats();
      if (_cancelled || _closed || peer != (_viewer ?? _host)) return;
      final now = DateTime.now();
      for (final report in reports) {
        final values = report.values;
        if (report.type == 'inbound-rtp' &&
            (values['kind'] == 'video' || values['mediaType'] == 'video')) {
          framesDecoded = (values['framesDecoded'] as num?)?.toInt() ?? 0;
          receivedBytes = (values['bytesReceived'] as num?)?.toInt() ?? 0;
          final seconds = _lastSample == null
              ? 0.0
              : now.difference(_lastSample!).inMilliseconds / 1000;
          if (seconds > 0) {
            framesPerSecond = (framesDecoded - _lastFrames) / seconds;
          }
          _lastFrames = framesDecoded;
          _lastSample = now;
        }
        if (report.type == 'candidate-pair' &&
            values['state'] == 'succeeded' &&
            (values['nominated'] == true || values['selected'] == true)) {
          final id = values['localCandidateId'];
          for (final candidate in reports) {
            if (candidate.id == id) {
              candidateType =
                  candidate.values['candidateType']?.toString() ?? '';
            }
          }
        }
      }
      if (dataReady) {
        await _sender!.send(
          RTCDataChannelMessage(
            jsonEncode({
              'probe': 'ping',
              'time': DateTime.now().millisecondsSinceEpoch,
            }),
          ),
        );
      }
      _notify();
    } catch (_) {
      /* A peer may close while its last sample is in flight. */
    } finally {
      _sampling = false;
    }
  }

  Future<void> setInputEnabled(bool enabled) => _run(() async {
    if (enabled) {
      if (!canReceiveInput || _capturedSourceId == null) {
        throw StateError('Chỉ host đã kết nối mới nhận input.');
      }
      await _platform.beginInput(_sessionId!, _capturedSourceId!);
      _check();
    } else {
      await _endNativeInput();
    }
    inputEnabled = enabled;
    _inputGate?.setEnabled(enabled);
  }, preserveSessionOnError: true);

  Future<void> sendTestInput(RemoteInput input) async {
    if (!dataReady || _closed || _cancelled) return;
    try {
      await _sender!.send(
        RTCDataChannelMessage(
          RemoteInputPacket(
            sessionId: _sessionId!,
            sequence: _sequence++,
            input: input,
          ).encode(),
        ),
      );
    } catch (_) {
      if (!_closed && !_cancelled) {
        error = 'Không gửi được input. Kênh dữ liệu có thể đã đóng.';
        _notify();
      }
    }
  }

  Future<bool> waitForFrame({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (firstFrame) return true;
    try {
      await _frameWaiter?.future.timeout(timeout);
      return firstFrame;
    } on TimeoutException {
      return false;
    }
  }

  Map<String, Object?> report() => {
    'platform': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'engine': 'flutter_webrtc 1.6.2+hotfix.4',
    'screenPermission': permissions?.screen,
    'inputPermission': permissions?.input,
    'sourceCount': sources.length,
    'mode': mode?.name,
    'firstFrameRendered': firstFrame,
    'framesDecoded': framesDecoded,
    'framesPerSecond': framesPerSecond,
    'receivedBytes': receivedBytes,
    'dataRoundTripMs': dataRoundTripMs,
    'candidateType': candidateType,
    'appliedInputs': appliedInputs,
    'error': error,
  };

  Future<void> stop() async {
    _cancelled = true;
    await _operation;
    await _cleanup();
    status = 'Đã dừng';
    _notify();
  }

  Future<void> _cleanup() async {
    _inputGate?.close();
    _inputGate = null;
    inputEnabled = false;
    localSignal = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    _frameDeadline?.cancel();
    _frameDeadline = null;
    await _endNativeInput();
    final channels = List<RTCDataChannel>.of(_channels);
    _channels.clear();
    _sender = null;
    for (final channel in channels) {
      channel.onMessage = null;
      channel.onDataChannelState = null;
      await channel.close().catchError((Object _) {});
    }
    final peers = [_host, _viewer];
    _host = _viewer = null;
    for (final peer in peers) {
      if (peer == null) continue;
      peer.onConnectionState = null;
      peer.onDataChannel = null;
      peer.onTrack = null;
      await peer.close().catchError((Object _) {});
      await peer.dispose().catchError((Object _) {});
    }
    if (initialized) {
      await renderer.setSrcObject(stream: null).catchError((Object _) {});
    }
    final stream = _capture;
    _capture = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.onEnded = null;
        await track.stop().catchError((Object _) {});
      }
      await stream.dispose().catchError((Object _) {});
    }
  }

  Future<void> _endNativeInput() async {
    final id = _sessionId;
    if (id != null) await _platform.endInput(id).catchError((Object _) {});
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    await stop();
    if (initialized) {
      renderer.onFirstFrameRendered = null;
      await renderer.dispose();
    }
    super.dispose();
  }
}
