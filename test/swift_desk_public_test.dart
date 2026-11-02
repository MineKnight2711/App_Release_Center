import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/lan_identity.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/public_broker.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/remote_storage.dart';
import 'package:app_management_center/app/modules/swift_desk/services/swift_desk_public.dart';
import 'package:app_management_center/app/modules/swift_desk/services/swift_desk_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'swift_desk_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LanIdentity hostId, viewerId;
  late Directory directory;
  late SwiftDeskRuntime host, viewer;
  late FakeRemoteEngine hostEngine, viewerEngine;
  late FakeRemoteNative native;
  late SwiftDeskPublic hostService, viewerService;
  late _Bus bus;
  late DateTime testNow;
  setUpAll(() async {
    hostId = await LanIdentity.generate();
    viewerId = await LanIdentity.generate();
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('amc-public-id-test-');
    bus = _Bus();
    testNow = DateTime.now();
    hostEngine = FakeRemoteEngine();
    viewerEngine = FakeRemoteEngine();
    hostEngine.other = viewerEngine;
    viewerEngine.other = hostEngine;
    native = FakeRemoteNative();
    host = SwiftDeskRuntime(
      engine: hostEngine,
      repository: FileRemoteDeviceRepository(
        File('${directory.path}/host.json'),
      ),
      credentials: MemoryRemoteCredentials(),
      identity: hostId,
      name: 'Private host name',
      platform: 'macos',
      native: native,
    );
    viewer = SwiftDeskRuntime(
      engine: viewerEngine,
      repository: FileRemoteDeviceRepository(
        File('${directory.path}/viewer.json'),
      ),
      credentials: MemoryRemoteCredentials(),
      identity: viewerId,
      name: 'Private viewer name',
      platform: 'windows',
      native: FakeRemoteNative()..screenAllowed = false,
    );
    await host.initialize();
    await viewer.initialize();
    await host.enableHost(port: 0, bindAddress: InternetAddress.loopbackIPv4);
    hostService = SwiftDeskPublic(
      host,
      broker: bus.client(),
      now: () => testNow,
      handshakeTimeout: const Duration(seconds: 2),
    );
    viewerService = SwiftDeskPublic(
      viewer,
      broker: bus.client(),
      handshakeTimeout: const Duration(seconds: 2),
    );
    await hostService.start();
    expect(hostService.online, isTrue);
  });
  tearDown(() async {
    await viewer.shutdown();
    await host.shutdown();
    await directory.delete(recursive: true);
  });

  Future<void> connected({bool remembered = false}) async {
    if (remembered) {
      await viewerService.connect(hostService.codeId);
    } else {
      await viewerService.connect(hostService.code.encode());
    }
    expect(
      viewerService.error,
      isNull,
      reason:
          '${hostService.diagnostics()} / ${viewerService.diagnostics()} / ${bus.wire.map((m) => (jsonDecode(m.payload) as Map)['type']).toList()}',
    );
    await waitRemote(() => host.pendingRequest != null);
    expect(native.begins, 0);
    expect(host.session!.state, RemoteSessionState.awaitingApproval);
    host.accept();
    await waitRemote(() => hostEngine.answered && viewerEngine.answered);
    hostEngine.emit(EngineEventKind.connected);
    hostEngine.emit(EngineEventKind.channelReady);
    viewerEngine.emit(EngineEventKind.connected);
    viewerEngine.emit(EngineEventKind.channelReady);
    viewerEngine.emit(EngineEventKind.firstFrame);
    await waitRemote(
      () =>
          host.session?.state == RemoteSessionState.connected &&
          viewer.session?.state == RemoteSessionState.connected,
    );
  }

  test(
    'stable nine-digit ID and short copy code; no account or capture permission required by viewer',
    () async {
      expect(hostService.codeId, matches(r'^[1-9][0-9]{8}$'));
      expect(publicRemoteId(hostId), hostService.codeId);
      expect(
        normalizePublicRemoteId(hostService.formattedId),
        hostService.codeId,
      );
      final code = PublicRemoteCode.decode(hostService.code.encode());
      expect(code.password.length, 16);
      expect(code.id, hostService.codeId);
      expect(viewer.permissions!.screen, isFalse);
      await connected();
      expect(native.begins, 0);
      expect(host.session!.scopes, {RemoteScope.view});
      expect(viewerService.saved.single.id, hostId.id);
    },
  );
  test(
    'knowing only a public ID cannot allocate pending pairing slots or exhaust authenticated challenge quota',
    () async {
      for (var i = 0; i < 24; i++) {
        bus.send(
          RemoteBrokerMessage(
            '${SwiftDeskPublic.namespace}/host/${hostService.codeId}',
            jsonEncode({
              'type': 'hello',
              'sid': '12345678-1234-1234-1234-${i.toString().padLeft(12, '0')}',
              'viewerId': viewerId.id,
              'known': false,
              'nonce': remoteToken(),
              'key': base64.encode(List.filled(32, 1)),
              'proof': 'not-authenticated',
            }),
          ),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(hostService.diagnostics()['sessions'], 0);
      expect(host.pendingRequest, isNull);
      await connected();
    },
  );
  test(
    'public broker never sees password, trust token, names or SDP; duplicate and replayed envelopes do not interrupt session',
    () async {
      bus.duplicate = true;
      final password = hostService.password;
      await connected();
      final token = await viewer.credentials.read('peer.${hostId.id}');
      final wire = bus.wire.map((m) => m.payload).join();
      for (final secret in [
        password,
        token!,
        'Private host name',
        'Private viewer name',
        FakeRemoteEngine.sdp,
        '"credential"',
      ]) {
        expect(wire, isNot(contains(secret)));
      }
      final packet = bus.wire.firstWhere(
        (m) => (jsonDecode(m.payload) as Map)['type'] == 'data',
      );
      bus.send(packet);
      final tampered = jsonDecode(packet.payload) as Map<String, dynamic>;
      tampered['payload'] = 'attacker';
      bus.send(RemoteBrokerMessage(packet.topic, jsonEncode(tampered)));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(host.session!.state, RemoteSessionState.connected);
      expect(viewer.session!.state, RemoteSessionState.connected);
    },
  );
  test('wrong or rotated password cannot reach host approval', () async {
    final stale = hostService.code.encode();
    hostService.renewPassword();
    await viewerService.connect(stale);
    expect(viewerService.error, isNotNull);
    expect(host.pendingRequest, isNull);
    expect(host.controllers, isEmpty);
    expect(native.begins, 0);
  });
  test(
    'expired pairing password cannot reach approval even if viewer kept the old copied code',
    () async {
      final stale = hostService.code.encode();
      testNow = testNow.add(const Duration(minutes: 6));
      await viewerService.connect(stale);
      expect(viewerService.error, isNotNull);
      expect(host.pendingRequest, isNull);
      expect(native.begins, 0);
    },
  );
  test(
    'public broker cannot replace a host identity without knowing pairing password',
    () async {
      bus.intercept = (message) {
        final value = jsonDecode(message.payload) as Map<String, dynamic>;
        if (value['type'] == 'challenge') value['fingerprint'] = '0' * 64;
        return RemoteBrokerMessage(message.topic, jsonEncode(value));
      };
      await viewerService.connect(hostService.code.encode());
      expect(viewerService.error, isNotNull);
      expect(host.pendingRequest, isNull);
      expect(native.begins, 0);
    },
  );
  test(
    'valid password proof cannot replace the pinned host private-key signature',
    () async {
      bus.intercept = (message) {
        final value = jsonDecode(message.payload) as Map<String, dynamic>;
        if (value['type'] == 'challenge') {
          value['signature'] = base64.encode(List.filled(256, 0));
        }
        return RemoteBrokerMessage(message.topic, jsonEncode(value));
      };
      await viewerService.connect(hostService.code.encode());
      expect(viewerService.error, isNotNull);
      expect(host.pendingRequest, isNull);
      expect(native.begins, 0);
    },
  );
  test(
    'password is consumed before approval; saved token reconnect still asks host; revoke blocks next attempt',
    () async {
      final old = hostService.password;
      await connected();
      expect(hostService.password, isNot(old));
      await viewer.disconnect();
      await waitRemote(
        () =>
            !host.active &&
            !viewerService.hasSession &&
            !hostService.hasSession,
      );
      hostEngine.answered = viewerEngine.answered = false;
      await connected(remembered: true);
      await host.revokeController(viewerId.id);
      await waitRemote(() => !viewer.active && !viewerService.hasSession);
      await viewerService.connect(hostService.codeId);
      expect(viewerService.error, isNotNull);
      expect(host.pendingRequest, isNull);
      expect(host.controllers, isEmpty);
    },
  );
  test(
    'host rejection grants nothing and public listener remains usable',
    () async {
      await viewerService.connect(hostService.code.encode());
      await waitRemote(() => host.pendingRequest != null);
      host.reject();
      await waitRemote(() => !viewer.active && !viewerService.hasSession);
      expect(hostService.online, isTrue);
      expect(native.begins, 0);
      expect(host.controllers, isEmpty);
    },
  );
  test(
    'public rendezvous does not silently downgrade forced TURN or incompatible IPv6/TURN settings',
    () async {
      await viewer.settings.setConnectionMode(RemoteConnectionMode.relay);
      await viewerService.connect(hostService.code.encode());
      expect(viewerService.error, contains('TURN'));
      expect(host.pendingRequest, isNull);
    },
  );
  test(
    'stopping host or shutting down removes public subscriptions and drains session owners',
    () async {
      await connected();
      await hostService.stop();
      await waitRemote(() => !host.active && !viewer.active);
      expect(hostService.online, isFalse);
      expect(bus.clients.first.topics, isEmpty);
      expect(hostEngine.stops, greaterThan(0));
    },
  );
  test(
    'a failing optional AMC backend shutdown cannot leave public rendezvous running',
    () async {
      host.stopInternet = () async =>
          throw StateError('Optional backend unavailable');
      await host.shutdown();
      expect(bus.clients.first.closed, isTrue);
      expect(bus.clients.first.topics, isEmpty);
      expect(hostEngine.disposed, isTrue);
    },
  );
}

class _Bus {
  final clients = <_Broker>[];
  final wire = <RemoteBrokerMessage>[];
  bool duplicate = false;
  RemoteBrokerMessage Function(RemoteBrokerMessage)? intercept;
  _Broker client() {
    final c = _Broker(this);
    clients.add(c);
    return c;
  }

  void send(RemoteBrokerMessage message) {
    wire.add(message);
    final delivered = intercept?.call(message) ?? message;
    for (final client in clients) {
      if (client.online && client.topics.contains(message.topic)) {
        scheduleMicrotask(() {
          if (!client.closed) {
            client.input.add(delivered);
            if (duplicate) client.input.add(delivered);
          }
        });
      }
    }
  }
}

class _Broker implements RemotePublicBroker {
  _Broker(this.bus);
  final _Bus bus;
  bool closed = false;
  @override
  bool online = false;
  final input = StreamController<RemoteBrokerMessage>.broadcast();
  final changes = StreamController<bool>.broadcast();
  final topics = <String>{};
  @override
  Stream<RemoteBrokerMessage> get messages => input.stream;
  @override
  Stream<bool> get states => changes.stream;
  @override
  Future<void> connect() async {
    online = true;
    changes.add(true);
  }

  @override
  Future<void> subscribe(String topic) async {
    topics.add(topic);
  }

  @override
  void unsubscribe(String topic) => topics.remove(topic);
  @override
  void publish(String topic, String payload) =>
      bus.send(RemoteBrokerMessage(topic, payload));
  @override
  Future<void> close() async {
    closed = true;
    online = false;
    topics.clear();
    await input.close();
    await changes.close();
  }
}
