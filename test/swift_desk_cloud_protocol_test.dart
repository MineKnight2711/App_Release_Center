import 'dart:async';
import 'dart:convert';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/cloud_signaling.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/lan_identity.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/webrtc_desktop_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sid = '12345678-1234-1234-1234-123456789abc';
  late LanIdentity identity;
  setUpAll(() async {
    identity = await LanIdentity.generate();
  });
  test('forced relay refuses a configuration containing only STUN', () async {
    final engine = WebRtcDesktopEngine();
    expect(
      () => engine.configureNetwork([
        {
          'urls': ['stun:turn.example:3478'],
        },
      ], mode: RemoteConnectionMode.relay),
      throwsStateError,
    );
    await engine.dispose();
  });
  test(
    'pinned RSA handshake encrypts secrets in both directions and flushes disconnect before close',
    () async {
      final wire = <String>[];
      CloudSignalingTransport? viewer;
      final host = CloudSignalingTransport.receiver(
        sessionId: sid,
        identity: identity,
        emit: (payload) {
          wire.add(payload);
          viewer!.receive(payload);
        },
        closed: () async {},
      );
      viewer = await CloudSignalingTransport.viewer(
        sessionId: sid,
        certificate: identity.certificate,
        fingerprint: identity.fingerprint,
        emit: (payload) {
          wire.add(payload);
          host.receive(payload);
        },
        closed: () async {},
      );
      addTearDown(() async {
        await viewer?.close();
        await host.close();
      });
      await host.ready;
      final admission = host.messages.listen((_) {});
      addTearDown(admission.cancel);
      final request = host.messages.first;
      viewer.send(sid, 'request', {'credential': 'SECRET-NEVER-IN-RELAY'});
      expect((await request).data['credential'], 'SECRET-NEVER-IN-RELAY');
      final stream = StreamIterator(viewer.messages);
      host.send(sid, 'hello', {'deviceId': identity.id});
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.kind, 'hello');
      host.send(sid, 'disconnect');
      await host.close();
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.kind, 'disconnect');
      expect(wire.join(), isNot(contains('SECRET-NEVER-IN-RELAY')));
      expect(wire.join(), isNot(contains('credential')));
      await stream.cancel();
    },
  );
  test('replayed encrypted sequence closes the transport', () async {
    final frames = <String>[];
    final host = CloudSignalingTransport.receiver(
      sessionId: sid,
      identity: identity,
      emit: (_) {},
      closed: () async {},
    );
    final viewer = await CloudSignalingTransport.viewer(
      sessionId: sid,
      certificate: identity.certificate,
      fingerprint: identity.fingerprint,
      emit: (p) {
        frames.add(p);
        host.receive(p);
      },
      closed: () async {},
    );
    addTearDown(() async {
      await viewer.close();
      await host.close();
    });
    await host.ready;
    final first = host.messages.first;
    viewer.send(sid, 'request');
    await first;
    host.receive(frames.last);
    await host.done.timeout(const Duration(seconds: 2));
  });
  test(
    'wrong certificate pin is rejected before sending a session key',
    () async {
      var sent = false;
      await expectLater(
        CloudSignalingTransport.viewer(
          sessionId: sid,
          certificate: identity.certificate,
          fingerprint: 'a' * 64,
          emit: (_) => sent = true,
          closed: () async {},
        ),
        throwsFormatException,
      );
      expect(sent, isFalse);
    },
  );
  test('tampered ciphertext cannot produce a signaling message', () async {
    final host = CloudSignalingTransport.receiver(
      sessionId: sid,
      identity: identity,
      emit: (_) {},
      closed: () async {},
    );
    final viewer = await CloudSignalingTransport.viewer(
      sessionId: sid,
      certificate: identity.certificate,
      fingerprint: identity.fingerprint,
      emit: (p) {
        final json = jsonDecode(p) as Map<String, dynamic>;
        if (json.containsKey('box')) {
          final bytes = base64.decode(json['box'] as String);
          bytes[15] ^= 1;
          json['box'] = base64.encode(bytes);
        }
        host.receive(jsonEncode(json));
      },
      closed: () async {},
    );
    addTearDown(() async {
      await viewer.close();
      await host.close();
    });
    final signals = <RemoteSignal>[];
    host.messages.listen(signals.add);
    await host.ready;
    viewer.send(sid, 'request');
    await host.done.timeout(const Duration(seconds: 2));
    expect(signals, isEmpty);
  });
}
