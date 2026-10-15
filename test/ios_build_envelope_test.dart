import 'dart:convert';

import 'package:app_management_center/app/services/ios_build_envelope.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SimpleKeyPair host;
  late List<int> hostPublic;
  final aad = IosBuildEnvelope.associatedData(
    desktopId: 'mac-mini',
    action: 'submit',
    runId: '42',
    projectId: 'app',
  );

  setUp(() async {
    host = await X25519().newKeyPair();
    hostPublic = (await host.extractPublicKey()).bytes;
  });

  test('opens what was sealed for it, in the relay alphabet', () async {
    final sealed = await IosBuildEnvelope.seal(
      hostPublicKey: hostPublic,
      body: {
        'credentials': {'p8PrivateKey': '-----BEGIN PRIVATE KEY-----'},
      },
      associatedData: aad,
    );
    // What the relay accepts and stores; the key must not be readable in it.
    expect(sealed, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(sealed, isNot(contains('PRIVATE')));

    final opened = await IosBuildEnvelope.open(
      hostKeyPair: host,
      envelope: sealed,
      associatedData: aad,
    );
    expect(opened['credentials'], {
      'p8PrivateKey': '-----BEGIN PRIVATE KEY-----',
    });
  });

  test('seals differently every time', () async {
    Future<String> seal() => IosBuildEnvelope.seal(
      hostPublicKey: hostPublic,
      body: const {'same': true},
      associatedData: aad,
    );
    expect(await seal(), isNot(await seal()));
  });

  test('refuses a different action, run or host', () async {
    final sealed = await IosBuildEnvelope.seal(
      hostPublicKey: hostPublic,
      body: const {'id': 'x'},
      associatedData: aad,
    );
    // The relay re-labelling a sealed "submit" as a "release".
    final relabelled = IosBuildEnvelope.associatedData(
      desktopId: 'mac-mini',
      action: 'release',
      runId: '42',
      projectId: 'app',
    );
    await expectLater(
      IosBuildEnvelope.open(
        hostKeyPair: host,
        envelope: sealed,
        associatedData: relabelled,
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      IosBuildEnvelope.open(
        hostKeyPair: await X25519().newKeyPair(),
        envelope: sealed,
        associatedData: aad,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('refuses an envelope altered in transit', () async {
    final sealed = await IosBuildEnvelope.seal(
      hostPublicKey: hostPublic,
      body: const {'commit': 'abc'},
      associatedData: aad,
    );
    final bytes = base64Url.decode(base64Url.normalize(sealed));
    bytes[bytes.length - 20] ^= 1;
    final tampered = base64Url.encode(bytes).replaceAll('=', '');
    await expectLater(
      IosBuildEnvelope.open(
        hostKeyPair: host,
        envelope: tampered,
        associatedData: aad,
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      IosBuildEnvelope.open(
        hostKeyPair: host,
        envelope: 'not-an-envelope',
        associatedData: aad,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('a fingerprint is short, stable and readable', () async {
    final first = await IosBuildEnvelope.fingerprint(hostPublic);
    expect(first, matches(RegExp(r'^[0-9A-F]{4}(-[0-9A-F]{4}){3}$')));
    expect(await IosBuildEnvelope.fingerprint(hostPublic), first);
    final other =
        (await (await X25519().newKeyPair()).extractPublicKey()).bytes;
    expect(await IosBuildEnvelope.fingerprint(other), isNot(first));
  });
}
