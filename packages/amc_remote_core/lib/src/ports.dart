import 'dart:async';
import '../amc_remote_core.dart';

abstract interface class RemoteCredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

abstract interface class RemoteDeviceRepository {
  Future<List<RemoteDevice>> devices();
  Future<void> saveDevice(RemoteDevice device);
  Future<void> removeDevice(String id);
  Future<List<TrustedRemoteController>> controllers();
  Future<void> saveController(TrustedRemoteController controller);
  Future<void> removeController(String id);
  Future<List<RemoteSessionRecord>> history();
  Future<void> appendHistory(RemoteSessionRecord record);
}

abstract interface class SignalingTransport {
  Stream<RemoteSignal> get messages;
  Future<void> get done;
  void send(
    String sessionId,
    String kind, [
    Map<String, dynamic> data = const {},
  ]);
  Future<void> close();
}

enum EngineEventKind {
  firstFrame,
  connected,
  disconnected,
  channelReady,
  packet,
  control,
  stats,
  error,
}

final class RemoteEngineEvent {
  const RemoteEngineEvent(this.kind, [this.data = const {}]);
  final EngineEventKind kind;
  final Map<String, dynamic> data;
}

abstract interface class RemoteDesktopEngine {
  Stream<RemoteEngineEvent> get events;
  Future<void> initialize();
  Future<List<DisplayDescriptor>> displays();
  Future<String> createOffer(String displayId, RemoteQuality quality);
  Future<String> answerOffer(String offer);
  Future<void> applyAnswer(String answer);
  Future<void> switchDisplay(String displayId, RemoteQuality quality);
  Future<void> sendPacket(RemoteInputPacket packet);
  Future<void> sendControl(Map<String, dynamic> value);
  Future<void> stop();
  Future<void> dispose();
}

abstract interface class RemoteNetworkEngine {
  void configureNetwork(
    List<Map<String, dynamic>> iceServers, {
    RemoteConnectionMode mode = RemoteConnectionMode.automatic,
  });
}
