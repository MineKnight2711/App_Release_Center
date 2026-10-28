import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:amc_remote_platform/amc_remote_platform.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'remote_network.dart';

class WebRtcDesktopEngine implements RemoteDesktopEngine, RemoteNetworkEngine {
  RemoteIcePolicy _network = RemoteIcePolicy([]);
  @override
  void configureNetwork(
    List<Map<String, dynamic>> iceServers, {
    RemoteConnectionMode mode = RemoteConnectionMode.automatic,
  }) {
    if (_peer != null || _work != null) {
      throw StateError('Hãy ngắt phiên trước khi đổi mạng.');
    }
    _network = RemoteIcePolicy(iceServers, mode: mode);
  }

  final renderer = RTCVideoRenderer();
  final _events = StreamController<RemoteEngineEvent>.broadcast();
  RTCPeerConnection? _peer;
  MediaStream? _capture;
  RTCRtpSender? _videoSender;
  RTCDataChannel? _reliable, _pointer;
  final _channels = <RTCDataChannel>[];
  Timer? _statsTimer;
  bool _initialized = false, _disposed = false, _sampling = false;
  int _generation = 0;
  Future<void>? _work;
  bool _viewer = false;
  bool _confirmedFrame = false;
  bool _transportConnected = false, _connectedReported = false;
  String _selectedPath = 'unknown';
  int _lastFrames = 0, _lastBytes = 0;
  DateTime? _lastSample;
  List<DisplayDescriptor> _displays = [];
  RemoteQuality _activeQuality = RemoteQuality.balanced;
  String? _activeDisplay;
  @override
  Stream<RemoteEngineEvent> get events => _events.stream;
  bool get ready =>
      _reliable?.state == RTCDataChannelState.RTCDataChannelOpen &&
      _pointer?.state == RTCDataChannelState.RTCDataChannelOpen;
  void _emit(EngineEventKind kind, [Map<String, dynamic> data = const {}]) {
    if (!_disposed) _events.add(RemoteEngineEvent(kind, data));
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) {
      throw StateError('Phiên media đã dừng.');
    }
  }

  Future<T> _perform<T>(Future<T> Function() action) async {
    if (_work != null || _disposed) {
      throw StateError('Engine đang xử lý hoặc đã đóng.');
    }
    final done = Completer<void>();
    _work = done.future;
    try {
      return await action();
    } finally {
      _work = null;
      done.complete();
    }
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await renderer.initialize();
    _initialized = true;
  }

  @override
  Future<List<DisplayDescriptor>> displays() async {
    final capture = await desktopCapturer.getSources(
      types: [SourceType.Screen],
    );
    final native = await const AmcRemotePlatform().displays();
    _displays = capture.map((s) {
      final descriptor = native.where((v) => v['id'] == s.id).firstOrNull;
      return DisplayDescriptor(
        id: s.id,
        name: s.name,
        width: (descriptor?['width'] as num?)?.toInt() ?? 0,
        height: (descriptor?['height'] as num?)?.toInt() ?? 0,
        scaleFactor: (descriptor?['scaleFactor'] as num?)?.toDouble() ?? 1,
      );
    }).toList();
    return List.unmodifiable(_displays);
  }

  Future<void> _peerFor(bool viewer, int gen) async {
    await initialize();
    _check(gen);
    _viewer = viewer;
    _confirmedFrame = false;
    _transportConnected = _connectedReported = false;
    _selectedPath = 'unknown';
    _peer = await createPeerConnection(_network.configuration);
    _check(gen);
    final peer = _peer!;
    peer.onConnectionState = (state) {
      if (gen != _generation || _disposed) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _transportConnected = true;
        _reportConnected();
      } else if ({
        RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
        RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        RTCPeerConnectionState.RTCPeerConnectionStateClosed,
      }.contains(state)) {
        _transportConnected = _connectedReported = false;
        _selectedPath = 'unknown';
        _emit(EngineEventKind.disconnected, {'channelsOpen': ready});
      }
    };
    if (viewer) {
      renderer.onFirstFrameRendered = () {
        if (gen == _generation && !_confirmedFrame) {
          _confirmedFrame = true;
          _emit(EngineEventKind.firstFrame);
        }
      };
      peer.onTrack = (event) {
        if (gen == _generation &&
            event.track.kind == 'video' &&
            event.streams.isNotEmpty) {
          renderer.srcObject = event.streams.first;
        }
      };
      peer.onDataChannel = (channel) => _bind(channel, gen);
    }
    _lastFrames = _lastBytes = 0;
    _lastSample = null;
    _statsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_sample(gen)),
    );
  }

  void _reportConnected() {
    if (!_transportConnected || _connectedReported) return;
    if (_network.mode == RemoteConnectionMode.directIpv6 &&
        _selectedPath != 'direct-ipv6') {
      return;
    }
    _connectedReported = true;
    _emit(EngineEventKind.connected);
  }

  Future<MediaStream> _captureDisplay(String id, RemoteQuality quality) async {
    if (!_displays.any((d) => d.id == id)) {
      throw StateError('Màn hình không còn hoạt động.');
    }
    final stream = await navigator.mediaDevices.getDisplayMedia({
      'audio': false,
      'video': {
        'deviceId': {'exact': id},
        'mandatory': {'frameRate': quality == RemoteQuality.high ? 60.0 : 30.0},
      },
    });
    if (stream.getVideoTracks().isEmpty) {
      await stream.dispose();
      throw StateError('Không có video track.');
    }
    return stream;
  }

  void _bind(RTCDataChannel channel, int gen) {
    if (gen != _generation || _disposed) {
      unawaited(channel.close().catchError((Object _) {}));
      return;
    }
    if (!{'amc-input-reliable-v1', 'amc-pointer-v1'}.contains(channel.label)) {
      unawaited(channel.close().catchError((Object _) {}));
      return;
    }
    _channels.add(channel);
    if (channel.label == 'amc-pointer-v1') {
      _pointer = channel;
    } else {
      _reliable = channel;
    }
    channel.onDataChannelState = (state) {
      if (gen != _generation || _disposed) return;
      if (ready) _emit(EngineEventKind.channelReady);
      if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _emit(EngineEventKind.disconnected, {'channelsOpen': false});
      }
    };
    channel.onMessage = (message) {
      if (gen != _generation ||
          _disposed ||
          message.isBinary ||
          message.text.length > 100000) {
        return;
      }
      try {
        final value = jsonDecode(message.text);
        if (value is! Map<String, dynamic>) return;
        if (value['control'] == true &&
            channel.label == 'amc-input-reliable-v1') {
          _emit(EngineEventKind.control, value);
        } else {
          final packet = RemoteInputPacket.decode(message.text);
          if ((channel.label == 'amc-pointer-v1') !=
              (packet.input is RemotePointer)) {
            return;
          }
          _emit(EngineEventKind.packet, {'packet': packet});
        }
      } catch (_) {
        _emit(EngineEventKind.error, {
          'reason': 'Dữ liệu điều khiển không hợp lệ.',
        });
      }
    };
    if (ready) _emit(EngineEventKind.channelReady);
  }

  Future<String> _description(bool offer, int gen) async {
    final peer = _peer!;
    final description = offer
        ? await peer.createOffer()
        : await peer.createAnswer();
    _check(gen);
    await peer.setLocalDescription(description);
    final timer = Stopwatch()..start();
    while (await peer.getIceGatheringState() !=
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      _check(gen);
      if (timer.elapsed > const Duration(seconds: 12)) {
        throw StateError('Hết thời gian thương lượng đường truyền.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    _check(gen);
    final result = await peer.getLocalDescription();
    if (result?.sdp == null ||
        !result!.sdp!.contains('a=fingerprint:sha-256 ')) {
      throw StateError('SDP thiếu danh tính DTLS.');
    }
    return _network.description(result.sdp!);
  }

  @override
  Future<String> createOffer(String displayId, RemoteQuality quality) =>
      _perform(() async {
        final gen = ++_generation;
        await _clear();
        _check(gen);
        await _peerFor(false, gen);
        _capture = await _captureDisplay(displayId, quality);
        _check(gen);
        final track = _capture!.getVideoTracks().first;
        track.onEnded = () {
          if (gen == _generation) _emit(EngineEventKind.disconnected);
        };
        _activeQuality = quality;
        _activeDisplay = displayId;
        _videoSender = await _peer!.addTrack(track, _capture!);
        _check(gen);
        _bind(
          await _peer!.createDataChannel(
            'amc-input-reliable-v1',
            RTCDataChannelInit()..id = -1,
          ),
          gen,
        );
        _bind(
          await _peer!.createDataChannel(
            'amc-pointer-v1',
            _PointerChannelInit(),
          ),
          gen,
        );
        return _description(true, gen);
      });
  @override
  Future<String> answerOffer(String offer) => _perform(() async {
    final gen = ++_generation;
    await _clear();
    _check(gen);
    await _peerFor(true, gen);
    await _peer!.setRemoteDescription(
      RTCSessionDescription(_network.description(offer), 'offer'),
    );
    _check(gen);
    return _description(false, gen);
  });
  @override
  Future<void> applyAnswer(String answer) => _perform(() async {
    await _peer!.setRemoteDescription(
      RTCSessionDescription(_network.description(answer), 'answer'),
    );
    if (_activeDisplay != null) await _quality(_activeQuality, _activeDisplay!);
  });

  Future<void> _quality(RemoteQuality quality, String displayId) async {
    final previous = _videoSender;
    if (previous == null) return;
    final senders = await _peer!.getSenders();
    final sender = senders
        .where((s) => s.senderId == previous.senderId)
        .firstOrNull;
    if (sender == null) return;
    _videoSender = sender;
    final params = sender.parameters;
    final encodings = params.encodings;
    if (encodings == null || encodings.isEmpty) return;
    final display = _displays.where((d) => d.id == displayId).firstOrNull;
    for (final encoding in encodings) {
      encoding.maxBitrate = switch (quality) {
        RemoteQuality.low => 1500000,
        RemoteQuality.balanced => 6000000,
        RemoteQuality.high => 15000000,
      };
      encoding.maxFramerate = quality == RemoteQuality.high ? 60 : 30;
      encoding.scaleResolutionDownBy = math.max(
        1,
        (display?.width ?? 1920) /
            (quality == RemoteQuality.low
                ? 1280
                : quality == RemoteQuality.balanced
                ? 1920
                : 7680),
      );
    }
    if (!await sender.setParameters(params)) {
      throw StateError('Engine không áp dụng được chất lượng đã chọn.');
    }
  }

  @override
  Future<void> switchDisplay(String displayId, RemoteQuality quality) =>
      _perform(() async {
        if (_viewer || _videoSender == null) {
          throw StateError('Chỉ host được đổi màn hình.');
        }
        final gen = _generation;
        final next = await _captureDisplay(displayId, quality);
        try {
          _check(gen);
          await _videoSender!.replaceTrack(next.getVideoTracks().first);
          _check(gen);
          final old = _capture;
          _capture = next;
          next.getVideoTracks().first.onEnded = () {
            if (gen == _generation) _emit(EngineEventKind.disconnected);
          };
          if (old != null) await _disposeStream(old);
          await _quality(quality, displayId);
        } catch (_) {
          if (!identical(_capture, next)) await _disposeStream(next);
          rethrow;
        }
      });
  @override
  Future<void> sendPacket(RemoteInputPacket packet) async {
    final pointer = packet.input is RemotePointer;
    final channel = pointer ? _pointer : _reliable;
    if (channel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('Kênh điều khiển chưa sẵn sàng.');
    }
    final backlog = channel!.bufferedAmount ?? 0;
    if (pointer && backlog > 16384) return;
    if (backlog > 262144) throw StateError('Kênh điều khiển đang nghẽn.');
    await channel.send(RTCDataChannelMessage(packet.encode()));
  }

  @override
  Future<void> sendControl(Map<String, dynamic> value) async {
    if (_reliable?.state != RTCDataChannelState.RTCDataChannelOpen) return;
    final encoded = jsonEncode({...value, 'control': true});
    if (encoded.length > 32768) {
      throw const FormatException('Control message quá lớn.');
    }
    await _reliable!.send(RTCDataChannelMessage(encoded));
  }

  Future<void> _sample(int gen) async {
    if (_sampling || _peer == null) return;
    _sampling = true;
    try {
      final reports = await _peer!.getStats();
      _check(gen);
      String path = 'unknown';
      final transports = reports.where((v) => v.type == 'transport');
      final selectedId = transports
          .map((v) => v.values['selectedCandidatePairId'])
          .whereType<String>()
          .firstOrNull;
      final pair = reports
          .where(
            (v) =>
                v.type == 'candidate-pair' &&
                (v.id == selectedId ||
                    (selectedId == null &&
                        v.values['nominated'] == true &&
                        v.values['state'] == 'succeeded')),
          )
          .firstOrNull;
      if (pair != null) {
        final local = reports
            .where((v) => v.id == pair.values['localCandidateId'])
            .firstOrNull
            ?.values;
        final remote = reports
            .where((v) => v.id == pair.values['remoteCandidateId'])
            .firstOrNull
            ?.values;
        path = selectedRemoteNetworkPath(local, remote);
      }
      _selectedPath = path;
      if (_network.mode == RemoteConnectionMode.directIpv6 &&
          _transportConnected &&
          {'relay', 'direct-ipv4'}.contains(path)) {
        _emit(EngineEventKind.error, {
          'reason':
              'Đường truyền không phải P2P IPv6. Phiên đã dừng theo lựa chọn kết nối.',
        });
        return;
      }
      _reportConnected();
      final now = DateTime.now();
      for (final report in reports) {
        final data = report.values;
        if (report.type == (_viewer ? 'inbound-rtp' : 'outbound-rtp') &&
            (data['kind'] == 'video' || data['mediaType'] == 'video')) {
          final frames =
              (data[_viewer ? 'framesDecoded' : 'framesEncoded'] as num?)
                  ?.toInt() ??
              0;
          final bytes =
              (data[_viewer ? 'bytesReceived' : 'bytesSent'] as num?)
                  ?.toInt() ??
              0;
          // Native texture's first-frame event can be missed while the view
          // is being attached. A bound stream with decoded video frames is
          // independent evidence of real received pixels, unlike onTrack.
          if (_viewer &&
              frames > 0 &&
              renderer.srcObject != null &&
              !_confirmedFrame) {
            _confirmedFrame = true;
            _emit(EngineEventKind.firstFrame);
          }
          final seconds = _lastSample == null
              ? 0.0
              : now.difference(_lastSample!).inMilliseconds / 1000;
          _emit(EngineEventKind.stats, {
            'path': path,
            'frames': frames,
            'bytes': bytes,
            'fps': seconds > 0
                ? math.max(0, (frames - _lastFrames) / seconds)
                : 0.0,
            'kbps': seconds > 0
                ? math.max(0, (bytes - _lastBytes) * 8 / 1000 / seconds)
                : 0.0,
          });
          _lastFrames = frames;
          _lastBytes = bytes;
          _lastSample = now;
        }
      }
    } catch (_) {
    } finally {
      _sampling = false;
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _work;
    await _clear();
  }

  Future<void> _disposeStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      track.onEnded = null;
      await track.stop().catchError((Object _) {});
    }
    await stream.dispose().catchError((Object _) {});
  }

  Future<void> _clear() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    renderer.onFirstFrameRendered = null;
    for (final channel in _channels) {
      channel.onMessage = null;
      channel.onDataChannelState = null;
      await channel.close().catchError((Object _) {});
    }
    _channels.clear();
    _reliable = _pointer = null;
    final peer = _peer;
    _peer = null;
    _videoSender = null;
    if (peer != null) {
      peer.onConnectionState = null;
      peer.onDataChannel = null;
      peer.onTrack = null;
      await peer.close().catchError((Object _) {});
      await peer.dispose().catchError((Object _) {});
    }
    if (_initialized) {
      await renderer.setSrcObject(stream: null).catchError((Object _) {});
    }
    final capture = _capture;
    _capture = null;
    if (capture != null) await _disposeStream(capture);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    if (_initialized) await renderer.dispose();
    await _events.close();
  }
}

/// The pinned plugin's default serializer omits zero. Explicitly send zero so
/// the pointer channel really is unordered/unreliable on both native backends.
class _PointerChannelInit extends RTCDataChannelInit {
  _PointerChannelInit() {
    id = -1;
    ordered = false;
    maxRetransmits = 0;
  }
  @override
  Map<String, dynamic> toMap() => {...super.toMap(), 'maxRetransmits': 0};
}
