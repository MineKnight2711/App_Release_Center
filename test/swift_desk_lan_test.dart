import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/lan_host.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/lan_identity.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/lan_transport.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/remote_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LanIdentity identity;
  late Directory directory;
  late FileRemoteDeviceRepository repository;
  late LanHostService host;
  final requests = <RemotePairRequest>[];
  final peers = <AuthorizedLanPeer>[];
  final clients = <LanConnection>[];
  setUpAll(() async {
    identity = await LanIdentity.generate();
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('amc-lan-test-');
    repository = FileRemoteDeviceRepository(
      File('${directory.path}/devices.json'),
    );
    requests.clear();
    peers.clear();
    clients.clear();
    host = LanHostService(
      identity: identity,
      name: 'Host',
      platform: 'test',
      repository: repository,
      onRequest: requests.add,
      onAuthorized: (peer) async {
        peers.add(peer);
      },
    );
    await host.start(port: 0, bindAddress: InternetAddress.loopbackIPv4);
  });
  tearDown(() async {
    for (final client in clients) {
      await client.close();
    }
    await host.stop();
    await directory.delete(recursive: true);
  });
  Future<(LanConnection, StreamIterator<RemoteSignal>, String)> connect(
    RemoteInvitation invitation, {
    String? credential,
    bool remember = false,
    Set<RemoteScope> scopes = const {RemoteScope.view, RemoteScope.input},
  }) async {
    final connection = await LanConnection.connect(invitation.endpoint);
    clients.add(connection);
    final iterator = StreamIterator(connection.messages);
    expect(
      await iterator.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    final hello = iterator.current;
    expect(hello.kind, 'hello');
    connection.send(hello.sessionId, 'request', {
      'deviceId': '12345678-1234-1234-1234-123456789abc',
      'name': 'Viewer',
      'platform': 'test',
      'scopes': scopes.map((s) => s.name).toList(),
      'credential': credential ?? invitation.token,
      'remember': remember,
    });
    return (connection, iterator, hello.sessionId);
  }

  test(
    'pinned TLS rejects a different certificate before any auth secret is sent',
    () async {
      final invitation = host.invitation('127.0.0.1');
      final wrong = RemoteEndpoint(
        address: '127.0.0.1',
        port: host.port,
        fingerprint: '0' * 64,
        deviceId: identity.id,
        name: 'Host',
      );
      await expectLater(
        LanConnection.connect(wrong),
        throwsA(isA<HandshakeException>()),
      );
      expect(requests, isEmpty);
      expect(peers, isEmpty);
      final (_, iterator, _) = await connect(invitation);
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.kind, 'pending');
      expect(peers, isEmpty);
      requests.single.decide({RemoteScope.view});
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.kind, 'approved');
      expect(parseScopes(iterator.current.data['scopes']), {RemoteScope.view});
    },
  );

  test(
    'approval is required; rejection consumes the invite and cannot be replayed',
    () async {
      final invitation = host.invitation('127.0.0.1');
      final (first, iterator, _) = await connect(invitation);
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.kind, 'pending');
      requests.single.decide(null);
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.kind, 'rejected');
      await first.close();
      final (_, retry, _) = await connect(invitation);
      expect(await retry.moveNext(), isTrue);
      expect(retry.current.kind, 'rejected');
      expect(peers, isEmpty);
      expect(requests, hasLength(1));
    },
  );

  test(
    'remembered token is hashed, cannot escalate scopes, and revoke invalidates it',
    () async {
      final invitation = host.invitation('127.0.0.1');
      final (first, iterator, _) = await connect(invitation, remember: true);
      await iterator.moveNext();
      requests.single.decide({RemoteScope.view});
      expect(await iterator.moveNext(), isTrue);
      final token = iterator.current.data['trustToken'] as String;
      expect(token.length, 43);
      expect(await repository.file.readAsString(), isNot(contains(token)));
      await first.close();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final (second, retry, _) = await connect(
        invitation,
        credential: token,
        scopes: {RemoteScope.view, RemoteScope.input, RemoteScope.clipboard},
      );
      await retry.moveNext();
      expect(requests.last.knownDevice, isTrue);
      expect(requests.last.availableScopes, {RemoteScope.view});
      requests.last.decide({RemoteScope.view});
      expect(await retry.moveNext(), isTrue);
      expect(retry.current.kind, 'approved');
      await host.revoke(requests.last.deviceId);
      await second.done;
      final (_, revoked, _) = await connect(invitation, credential: token);
      expect(await revoked.moveNext(), isTrue);
      expect(revoked.current.kind, 'rejected');
    },
  );

  test(
    'unbounded frame length closes TLS transport without allocating its payload',
    () async {
      final connection = await LanConnection.connect(
        host.invitation('127.0.0.1').endpoint,
      );
      clients.add(connection);
      final iterator = StreamIterator(connection.messages);
      await iterator.moveNext();
      final header = ByteData(4)..setUint32(0, RemoteSignal.maxBytes + 1);
      connection.socket.add(header.buffer.asUint8List());
      await connection.socket.flush();
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 5)),
        isFalse,
      );
      expect(requests, isEmpty);
    },
  );
}
