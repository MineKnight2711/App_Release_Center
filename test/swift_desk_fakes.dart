import 'dart:async';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:amc_remote_platform/amc_remote_platform.dart';

class MemoryRemoteCredentials implements RemoteCredentialStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class FakeRemoteNative extends AmcRemotePlatform {
  bool screenAllowed = true, inputAllowed = true;
  String? session;
  int begins = 0, releases = 0;
  final inputs = <Map<String, Object>>[];
  @override
  Future<RemotePlatformPermissions> permissions({bool request = false}) async =>
      RemotePlatformPermissions(screen: screenAllowed, input: inputAllowed);
  @override
  Future<void> beginInput(String sessionId, String displayId) async {
    if (!inputAllowed) throw StateError('Permission denied');
    session = sessionId;
    begins++;
  }

  @override
  Future<void> sendInput(String sessionId, Map<String, Object> input) async {
    if (session != sessionId || !inputAllowed) {
      throw StateError('Input not authorized');
    }
    inputs.add(input);
  }

  @override
  Future<void> endInput(String sessionId) async {
    if (session == sessionId) {
      session = null;
      releases++;
    }
  }

  @override
  Future<void> releaseInputs(String sessionId) async {
    if (session == sessionId) releases++;
  }
}

class FakeRemoteEngine implements RemoteDesktopEngine {
  final controller = StreamController<RemoteEngineEvent>.broadcast();
  FakeRemoteEngine? other;
  bool answered = false, disposed = false;
  int stops = 0, switches = 0;
  final sentPackets = <RemoteInputPacket>[];
  void emit(EngineEventKind kind, [Map<String, dynamic> data = const {}]) =>
      controller.add(RemoteEngineEvent(kind, data));
  static const sdp = 'v=0\r\na=fingerprint:sha-256 AB:CD\r\n';
  @override
  Stream<RemoteEngineEvent> get events => controller.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<List<DisplayDescriptor>> displays() async => const [
    DisplayDescriptor(
      id: 'display-1',
      name: 'Screen 1',
      width: 1920,
      height: 1080,
    ),
    DisplayDescriptor(
      id: 'display-2',
      name: 'Screen 2',
      width: 3840,
      height: 2160,
      scaleFactor: 2,
    ),
  ];
  @override
  Future<String> createOffer(String displayId, RemoteQuality quality) async =>
      sdp;
  @override
  Future<String> answerOffer(String offer) async {
    answered = true;
    return sdp;
  }

  @override
  Future<void> applyAnswer(String answer) async {
    answered = true;
  }

  @override
  Future<void> switchDisplay(String displayId, RemoteQuality quality) async {
    switches++;
  }

  @override
  Future<void> sendPacket(RemoteInputPacket packet) async {
    sentPackets.add(packet);
    other?.emit(EngineEventKind.packet, {'packet': packet});
  }

  @override
  Future<void> sendControl(Map<String, dynamic> value) async {
    other?.emit(EngineEventKind.control, value);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    if (!disposed) {
      disposed = true;
      await controller.close();
    }
  }
}

Future<void> waitRemote(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final timer = Stopwatch()..start();
  while (!condition()) {
    if (timer.elapsed > timeout) {
      throw TimeoutException('Remote condition not reached', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
