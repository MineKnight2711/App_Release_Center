import 'dart:async';
import 'dart:io';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/lan_identity.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/cloud_signaling.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/remote_storage.dart';
import 'package:app_management_center/app/modules/swift_desk/services/swift_desk_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'swift_desk_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LanIdentity hostIdentity, viewerIdentity;
  late Directory directory;
  late SwiftDeskRuntime host, viewer;
  late FakeRemoteEngine hostEngine, viewerEngine;
  late FakeRemoteNative native;
  setUpAll(() async {
    hostIdentity = await LanIdentity.generate();
    viewerIdentity = await LanIdentity.generate();
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('amc-runtime-test-');
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
      identity: hostIdentity,
      name: 'Host',
      platform: 'macos',
      native: native,
    );
    viewer = SwiftDeskRuntime(
      engine: viewerEngine,
      repository: FileRemoteDeviceRepository(
        File('${directory.path}/viewer.json'),
      ),
      credentials: MemoryRemoteCredentials(),
      identity: viewerIdentity,
      name: 'Viewer',
      platform: 'windows',
      native: FakeRemoteNative(),
    );
    await host.initialize();
    await viewer.initialize();
    await host.enableHost(port: 0, bindAddress: InternetAddress.loopbackIPv4);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await viewer.shutdown();
    await host.shutdown();
    await directory.delete(recursive: true);
  });

  Future<void> pair({bool input = false, bool clipboard = false}) async {
    await viewer.connectInvitation(host.invitation('127.0.0.1').encode());
    await waitRemote(() => host.pendingRequest != null);
    expect(host.session!.state, RemoteSessionState.awaitingApproval);
    expect(native.begins, 0);
    host.accept(input: input, clipboard: clipboard);
    await waitRemote(() => hostEngine.answered && viewerEngine.answered);
    hostEngine.emit(EngineEventKind.connected);
    hostEngine.emit(EngineEventKind.channelReady);
    viewerEngine.emit(EngineEventKind.connected);
    viewerEngine.emit(EngineEventKind.channelReady);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      viewer.session!.state,
      RemoteSessionState.negotiating,
      reason: 'A connected peer and tracks alone are not a live screen',
    );
    viewerEngine.emit(EngineEventKind.firstFrame);
    await waitRemote(
      () =>
          host.session!.state == RemoteSessionState.connected &&
          viewer.session!.state == RemoteSessionState.connected,
    );
  }

  Future<void> requestCloud(RemoteConnectionMode mode) async {
    await viewer.settings.setConnectionMode(mode);
    const sid = '12345678-1234-1234-1234-123456789abc';
    CloudSignalingTransport? receiver;
    late CloudSignalingTransport sender;
    receiver = CloudSignalingTransport.receiver(
      sessionId: sid,
      identity: hostIdentity,
      emit: (value) => sender.receive(value),
      closed: () async {},
    );
    sender = await CloudSignalingTransport.viewer(
      sessionId: sid,
      certificate: hostIdentity.certificate,
      fingerprint: hostIdentity.fingerprint,
      emit: receiver.receive,
      closed: () async {},
    );
    addTearDown(() async {
      await sender.close();
      await receiver?.close();
    });
    await receiver.ready;
    final credential = host.invitation('127.0.0.1').token;
    await viewer.connectCloud(
      sender,
      peerId: hostIdentity.id,
      peerName: 'Host',
      credential: credential,
      remember: false,
    );
    host.acceptCloudTransport(receiver, sid, 'Viewer');
  }

  test(
    'IPv6-only intent reaches host over encrypted signaling and still waits for human approval',
    () async {
      await requestCloud(RemoteConnectionMode.directIpv6);
      await waitRemote(() => host.pendingRequest != null);
      expect(host.pendingRequest!.internet, isTrue);
      expect(
        host.pendingRequest!.connectionMode,
        RemoteConnectionMode.directIpv6,
      );
      expect(host.session!.state, RemoteSessionState.awaitingApproval);
      expect(native.begins, 0);
      expect(hostEngine.answered, isFalse);
      host.reject();
      await waitRemote(() => !viewer.active);
    },
  );

  test(
    'IPv6-only versus forced TURN is rejected before granting or remembering a controller',
    () async {
      await host.settings.setConnectionMode(RemoteConnectionMode.relay);
      await requestCloud(RemoteConnectionMode.directIpv6);
      await waitRemote(() => host.error != null && !viewer.active);
      expect(host.error, contains('P2P IPv6 và TURN'));
      expect(host.pendingRequest, isNull);
      expect(host.controllers, isEmpty);
      expect(hostEngine.answered, isFalse);
      expect(native.begins, 0);
    },
  );

  test(
    'revoking clipboard while the OS read is pending prevents sending its content',
    () async {
      await pair(clipboard: true);
      final content = Completer<Object?>();
      var reading = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              reading = true;
              return content.future;
            }
            return null;
          });
      viewer.clipboardEnabled = true;
      await viewer.clipboard(pull: true);
      await waitRemote(() => reading);
      await host.revokeScope(RemoteScope.clipboard);
      content.complete({'text': 'never sent after revoke'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        hostEngine.sentPackets.where((p) => p.input is RemoteClipboard),
        isEmpty,
      );
    },
  );

  test(
    'paste waits for destination clipboard acknowledgement and local revoke works while Internet is unavailable',
    () async {
      await pair(input: true, clipboard: true);
      var clipboard = 'new clipboard';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return {'text': clipboard};
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      viewer.clipboardEnabled = true;
      expect(await viewer.syncClipboardForPaste(), isTrue);
      expect(clipboard, 'new clipboard');
      host.onControllerRevoked = (_) async =>
          throw StateError('Internet unavailable');
      await host.revokeController(viewerIdentity.id);
      expect(host.controllers, isEmpty);
      expect(host.active, isFalse);
      expect(native.session, isNull);
    },
  );

  test(
    'initial capture recovery is bounded and cannot authorize input without a real viewer frame',
    () async {
      await host.shutdown();
      hostEngine = FakeRemoteEngine()..other = viewerEngine;
      viewerEngine.other = hostEngine;
      host = SwiftDeskRuntime(
        engine: hostEngine,
        repository: FileRemoteDeviceRepository(
          File('${directory.path}/recovery.json'),
        ),
        credentials: MemoryRemoteCredentials(),
        identity: hostIdentity,
        name: 'Host',
        platform: 'macos',
        native: native,
        captureRetryDelay: const Duration(milliseconds: 30),
      );
      await host.initialize();
      await host.enableHost(port: 0, bindAddress: InternetAddress.loopbackIPv4);
      await viewer.connectInvitation(host.invitation('127.0.0.1').encode());
      await waitRemote(() => host.pendingRequest != null);
      host.accept(input: true);
      await waitRemote(() => hostEngine.answered && viewerEngine.answered);
      hostEngine.emit(EngineEventKind.connected);
      hostEngine.emit(EngineEventKind.channelReady);
      viewerEngine.emit(EngineEventKind.connected);
      viewerEngine.emit(EngineEventKind.channelReady);
      await waitRemote(() => hostEngine.switches == 1);
      expect(host.captureRecoveryAttempted, isTrue);
      expect(host.session!.state, RemoteSessionState.negotiating);
      expect(native.begins, 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(hostEngine.switches, 1);
      viewerEngine.emit(EngineEventKind.firstFrame);
      await waitRemote(
        () => host.session!.state == RemoteSessionState.connected,
      );
      expect(native.begins, 1);
    },
  );

  test(
    'host and grant survive leaving the device page; disconnect drains native input and keeps listener alive',
    () async {
      await pair(input: true);
      expect(native.begins, 1);
      viewer.takeControl();
      await viewer.sendInput(RemoteKey(0x700e1, down: true));
      await waitRemote(() => native.inputs.length == 1);
      await viewer.disconnect();
      await waitRemote(() => !host.active && !host.draining);
      expect(native.session, isNull);
      expect(native.releases, greaterThanOrEqualTo(1));
      expect(host.hostEnabled, isTrue);
      expect(viewer.history, hasLength(1));
      expect(hostEngine.stops, greaterThanOrEqualTo(1));
      expect(host.error, isNull);
      expect(viewer.error, isNull);
      expect(host.history.single.failed, isFalse);
    },
  );

  test(
    'view-only session rejects forged input and clipboard packets even with valid channel/session',
    () async {
      await pair();
      await viewerEngine.sendPacket(
        RemoteInputPacket(
          sessionId: viewer.session!.id,
          sequence: 0,
          input: RemoteText('not injected'),
          displayId: host.displayId,
        ),
      );
      await viewerEngine.sendPacket(
        RemoteInputPacket(
          sessionId: viewer.session!.id,
          sequence: 1,
          input: RemoteClipboard('not copied'),
        ),
      );
      await waitRemote(() => host.receivedPackets == 2);
      expect(native.inputs, isEmpty);
      expect(native.begins, 0);
      expect(host.appliedInputs, 0);
    },
  );

  test(
    'wrong display, foreign session and revoked input cannot reach OS; trusted request does not self-upgrade',
    () async {
      await pair(input: true);
      await viewerEngine.sendPacket(
        RemoteInputPacket(
          sessionId: viewer.session!.id,
          sequence: 1,
          input: RemotePointer(.2, .3),
          displayId: 'display-2',
        ),
      );
      await viewerEngine.sendPacket(
        RemoteInputPacket(
          sessionId: '12345678-1234-1234-1234-123456789abc',
          sequence: 2,
          input: RemoteText('ignored'),
          displayId: host.displayId,
        ),
      );
      await waitRemote(() => host.receivedPackets == 2);
      expect(native.inputs, isEmpty);
      await host.revokeScope(RemoteScope.input);
      await viewerEngine.sendPacket(
        RemoteInputPacket(
          sessionId: viewer.session!.id,
          sequence: 3,
          input: RemoteKey(0x70004, down: true),
          displayId: host.displayId,
        ),
      );
      await waitRemote(() => host.receivedPackets == 3);
      expect(native.inputs, isEmpty);
      expect(native.session, isNull);
      await waitRemote(() => !viewer.allows(RemoteScope.input));
    },
  );

  test(
    'display switch releases pressed state and fences packets for the previous display',
    () async {
      await pair(input: true);
      viewer.takeControl();
      await viewer.sendInput(
        RemoteButton(button: 'left', down: true, x: .1, y: .1),
      );
      await waitRemote(() => native.inputs.isNotEmpty);
      await viewer.changeDisplay('display-2', RemoteQuality.low);
      await waitRemote(() => viewer.remoteDisplayId == 'display-2');
      expect(host.displayId, 'display-2');
      expect(hostEngine.switches, 1);
      expect(native.releases, greaterThanOrEqualTo(1));
      final count = native.inputs.length;
      await viewerEngine.sendPacket(
        RemoteInputPacket(
          sessionId: viewer.session!.id,
          sequence: 100,
          input: RemotePointer(.8, .8),
          displayId: 'display-1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(native.inputs.length, count);
    },
  );

  test(
    'transport failure immediately revokes native state and cannot report connected on closed channels',
    () async {
      await pair(input: true);
      hostEngine.emit(EngineEventKind.disconnected, {'channelsOpen': false});
      await waitRemote(
        () => host.session!.state == RemoteSessionState.reconnecting,
      );
      await waitRemote(() => native.session == null);
      hostEngine.emit(EngineEventKind.connected);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(host.session!.state, RemoteSessionState.reconnecting);
      await host.disconnect();
      expect(host.hostEnabled, isTrue);
    },
  );

  test(
    'permission denial permits view while removing input; host revoke closes current peer',
    () async {
      await pair(input: true);
      native.inputAllowed = false;
      await host.refreshPermissions();
      await waitRemote(() => !viewer.allows(RemoteScope.input));
      expect(host.allows(RemoteScope.view), isTrue);
      expect(native.session, isNull);
      await host.revokeController(viewerIdentity.id);
      await waitRemote(() => !viewer.active && !host.active);
      expect(host.controllers, isEmpty);
    },
  );

  test(
    'saved device probe does not request approval and IP edits preserve identity pin',
    () async {
      await pair();
      await viewer.disconnect();
      await waitRemote(() => !host.active && !host.draining);
      final saved = viewer.devices.single;
      await viewer.probeDevices();
      expect(viewer.deviceOnline[saved.endpoint.deviceId], isTrue);
      expect(host.pendingRequest, isNull);
      expect(host.active, isFalse);
      await viewer.updateDeviceAddress(saved, '192.168.1.45', 9878, 'Mac mới');
      final updated = viewer.devices.single;
      expect(updated.endpoint.address, '192.168.1.45');
      expect(updated.endpoint.port, 9878);
      expect(updated.endpoint.fingerprint, saved.endpoint.fingerprint);
      expect(updated.endpoint.deviceId, saved.endpoint.deviceId);
      expect(
        await viewer.credentials.read('peer.${saved.endpoint.deviceId}'),
        isNotNull,
      );
    },
  );
}
