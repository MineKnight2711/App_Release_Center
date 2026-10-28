import 'dart:convert';
import 'dart:io';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/remote_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sessionId = '12345678-1234-1234-1234-123456789abc';
  const peerId = '22345678-1234-1234-1234-123456789abc';
  final now = DateTime.utc(2026, 10, 23);
  RemoteSession session() => RemoteSession(
    id: sessionId,
    peerId: peerId,
    peerName: 'Viewer',
    role: RemoteRole.host,
    expiresAt: now.add(const Duration(hours: 2)),
  );
  RemoteInputPacket packet(
    int seq,
    RemoteInput input, {
    String id = sessionId,
  }) => RemoteInputPacket(sessionId: id, sequence: seq, input: input);

  test('remote display descriptors reject invalid dimensions and scale', () {
    final valid = const DisplayDescriptor(
      id: '1',
      name: 'Retina',
      width: 3024,
      height: 1964,
      scaleFactor: 2,
    ).toJson();
    expect(DisplayDescriptor.fromJson(valid).scaleFactor, 2);
    for (final invalid in [
      {...valid, 'width': 0},
      {...valid, 'height': 40000},
      {...valid, 'scaleFactor': double.nan},
      {...valid, 'scaleFactor': -1},
      {...valid, 'id': ''},
      {...valid, 'name': 'x' * 81},
    ]) {
      expect(() => DisplayDescriptor.fromJson(invalid), throwsFormatException);
    }
  });

  test(
    'grant and media confirmation are required; expiry, reconnect and termination deny input',
    () {
      final s = session();
      final policy = RemoteAccessPolicy(s);
      expect(
        () => s.transition(RemoteSessionState.connected),
        throwsStateError,
      );
      expect(
        () => s.grant({RemoteScope.view, RemoteScope.input}),
        throwsStateError,
      );
      s
        ..transition(RemoteSessionState.requesting)
        ..transition(RemoteSessionState.awaitingApproval);
      s.grant({RemoteScope.view, RemoteScope.input});
      s.transition(RemoteSessionState.negotiating);
      expect(policy.accept(packet(1, RemoteText('x')), now), isFalse);
      s.transition(RemoteSessionState.connected);
      expect(policy.accept(packet(1, RemoteText('x')), now), isTrue);
      s.transition(RemoteSessionState.reconnecting);
      expect(policy.accept(packet(2, RemoteText('x')), now), isFalse);
      s.transition(RemoteSessionState.connected);
      expect(
        policy.accept(
          packet(2, RemoteText('x')),
          now.add(const Duration(hours: 2)),
        ),
        isFalse,
      );
      s.transition(RemoteSessionState.ended);
      expect(policy.accept(packet(2, RemoteText('x')), now), isFalse);
      expect(s.scopes, isEmpty);
      expect(
        () => s.transition(RemoteSessionState.connected),
        throwsStateError,
      );
    },
  );

  test(
    'pointer packets cannot suppress reliable key up or move behind a later button',
    () {
      final gate = RemoteInputGate(
        sessionId: sessionId,
        expiresAt: now.add(const Duration(minutes: 1)),
      )..setEnabled(true);
      expect(gate.accept(packet(20, RemotePointer(.2, .2)), now: now), isTrue);
      expect(
        gate.accept(packet(18, RemoteKey(0x70004, down: false)), now: now),
        isTrue,
      );
      expect(
        gate.accept(
          packet(22, RemoteButton(button: 'left', down: true, x: .3, y: .3)),
          now: now,
        ),
        isTrue,
      );
      expect(gate.accept(packet(21, RemotePointer(.2, .2)), now: now), isFalse);
      expect(
        gate.accept(
          packet(22, RemoteButton(button: 'left', down: true, x: .3, y: .3)),
          now: now,
        ),
        isFalse,
      );
      expect(
        gate.accept(packet(23, const RemoteRelease(), id: peerId), now: now),
        isFalse,
      );
    },
  );

  test(
    'clipboard scope is independent of input and a revoke cannot be reversed by the peer',
    () {
      final s = session()
        ..transition(RemoteSessionState.requesting)
        ..transition(RemoteSessionState.awaitingApproval);
      s.grant({RemoteScope.view, RemoteScope.clipboard});
      s.transition(RemoteSessionState.negotiating);
      s.transition(RemoteSessionState.connected);
      final policy = RemoteAccessPolicy(s);
      expect(policy.accept(packet(0, RemoteText('secret')), now), isFalse);
      expect(
        policy.accept(packet(1, RemoteClipboard('Tiếng Việt')), now),
        isTrue,
      );
      s.revoke(RemoteScope.clipboard);
      expect(
        policy.accept(packet(2, RemoteClipboard('ignored')), now),
        isFalse,
      );
      expect(
        () => s.grant({RemoteScope.view, RemoteScope.input}),
        throwsStateError,
      );
    },
  );

  test(
    'LAN codes reject external destinations, tampering, wrong version and expiry',
    () {
      final endpoint = RemoteEndpoint(
        address: '192.168.1.7',
        port: 9877,
        fingerprint: 'a' * 64,
        deviceId: peerId,
        name: 'Mac',
      );
      final invite = RemoteInvitation(
        endpoint: endpoint,
        token: 'x' * 43,
        expiresAt: now.add(const Duration(minutes: 5)),
      );
      expect(
        RemoteInvitation.decode(invite.encode(), now).endpoint.fingerprint,
        endpoint.fingerprint,
      );
      for (final address in [
        '8.8.8.8',
        'example.com',
        '192.168.1.999',
        '192.168.01.2',
        '0.0.0.0',
      ]) {
        expect(
          () => RemoteEndpoint(
            address: address,
            port: 9877,
            fingerprint: 'a' * 64,
            deviceId: peerId,
            name: 'bad',
          ),
          throwsFormatException,
        );
      }
      expect(
        () => RemoteInvitation.decode(
          invite.encode(),
          now.add(const Duration(minutes: 5)),
        ),
        throwsFormatException,
      );
      expect(
        () => RemoteInvitation.decode(
          invite.encode().replaceFirst(':1:', ':2:'),
          now,
        ),
        throwsFormatException,
      );
      expect(
        () => RemoteInvitation.decode('amc-lan:1:broken', now),
        throwsFormatException,
      );
    },
  );

  test(
    'new input events enforce bounds, Boolean state, HID usage and text-only clipboard',
    () {
      final valid =
          jsonDecode(packet(0, RemoteText('x')).encode())
              as Map<String, dynamic>;
      for (final event in [
        {'type': 'button', 'button': 'left', 'down': 'yes', 'x': .5, 'y': .5},
        {'type': 'button', 'button': 'extra', 'down': true, 'x': .5, 'y': .5},
        {'type': 'wheel', 'dx': 'bad', 'dy': 0},
        {'type': 'wheel', 'dx': 2401, 'dy': 0},
        {'type': 'key', 'usage': 0x90001, 'down': true},
        {'type': 'clipboard', 'text': 'x' * 16385},
        {'type': 'clipboard', 'text': 'bad\u0000'},
      ]) {
        expect(
          () =>
              RemoteInputPacket.decode(jsonEncode({...valid, 'input': event})),
          throwsFormatException,
        );
      }
    },
  );

  group('repository', () {
    late Directory directory;
    late File file;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('amc-remote-store-');
      file = File('${directory.path}/devices.json');
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });
    test(
      'concurrent writes survive reopen and contain no pairing/password secrets',
      () async {
        final repo = FileRemoteDeviceRepository(file);
        final devices = List.generate(
          8,
          (i) => RemoteDevice(
            endpoint: RemoteEndpoint(
              address: '192.168.1.${i + 1}',
              port: 9877,
              fingerprint: 'a' * 64,
              deviceId: '12345678-1234-1234-1234-123456789ab$i',
              name: 'Host $i',
            ),
            platform: 'test',
            lastConnectedAt: now,
          ),
        );
        await Future.wait(devices.map(repo.saveDevice));
        final reopened = FileRemoteDeviceRepository(file);
        expect(await reopened.devices(), hasLength(8));
        final data = await file.readAsString();
        for (final secretKey in [
          'password',
          'trustToken',
          'privateKey',
          'credential',
        ]) {
          expect(data, isNot(contains(secretKey)));
        }
      },
    );
    test(
      'corrupt data is not silently replaced; a failed commit rolls memory back',
      () async {
        await file.writeAsString('{broken');
        await expectLater(
          FileRemoteDeviceRepository(file).devices(),
          throwsFormatException,
        );
        expect(await file.readAsString(), '{broken');
        await file.delete();
        await Directory(file.path).create();
        final repo = FileRemoteDeviceRepository(file);
        await expectLater(
          repo.saveDevice(
            RemoteDevice(
              endpoint: RemoteEndpoint(
                address: '127.0.0.1',
                port: 9877,
                fingerprint: 'b' * 64,
                deviceId: peerId,
                name: 'Host',
              ),
              platform: 'test',
              lastConnectedAt: now,
            ),
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await repo.devices(), isEmpty);
      },
    );
    test(
      'session history is bounded and idempotent without event contents',
      () async {
        final repo = FileRemoteDeviceRepository(file);
        for (var i = 0; i < 52; i++) {
          await repo.appendHistory(
            RemoteSessionRecord(
              sessionId: 'session-$i',
              peerName: 'Host',
              role: RemoteRole.viewer,
              endedAt: now,
              failed: false,
              frames: i,
            ),
          );
        }
        await repo.appendHistory(
          RemoteSessionRecord(
            sessionId: 'session-51',
            peerName: 'Host',
            role: RemoteRole.viewer,
            endedAt: now,
            failed: true,
            frames: 99,
          ),
        );
        final history = await FileRemoteDeviceRepository(file).history();
        expect(history, hasLength(50));
        expect(history.first.frames, 99);
        expect(history.first.failed, isTrue);
      },
    );
  });
}
