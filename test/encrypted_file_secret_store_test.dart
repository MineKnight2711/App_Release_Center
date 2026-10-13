import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/services/encrypted_file_secret_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late File file;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('amc_secret_store_');
    file = File(p.join(root.path, 'secrets.json'));
  });

  tearDown(() => root.delete(recursive: true));

  EncryptedFileSecretStore open({
    String machine = 'MACHINE-A',
    _FakeKeychain? legacy,
  }) {
    return EncryptedFileSecretStore(
      locate: () async => file,
      machineSecret: () async => utf8.encode(machine),
      legacy: legacy,
    );
  }

  test('keeps values across launches without writing them in clear', () async {
    await open().write('telegram.token', 'bot-secret-123');
    await open().write('drive.refresh', 'refresh-xyz');

    final reopened = open();
    expect(await reopened.read('telegram.token'), 'bot-secret-123');
    expect(await reopened.read('drive.refresh'), 'refresh-xyz');
    expect(await reopened.read('missing'), isNull);

    final onDisk = await file.readAsString();
    expect(onDisk, isNot(contains('bot-secret-123')));
    expect(onDisk, isNot(contains('telegram.token')));
  });

  test(
    'moves a keychain secret on first read, then forgets the keychain',
    () async {
      final keychain = _FakeKeychain({'chplay.json': '{"key":1}'});

      expect(await open(legacy: keychain).read('chplay.json'), '{"key":1}');
      expect(keychain.values, isEmpty);
      expect(keychain.reads, ['chplay.json']);

      // Another launch reads the file only, even for a key that never existed.
      final again = open(legacy: keychain);
      expect(await again.read('chplay.json'), '{"key":1}');
      expect(await again.read('never.saved'), isNull);
      expect(await again.read('never.saved'), isNull);
      expect(keychain.reads, ['chplay.json', 'never.saved']);
    },
  );

  test(
    'a deleted or overwritten key never comes back from the keychain',
    () async {
      final keychain = _FakeKeychain({'a': 'old-a', 'b': 'old-b'});
      final store = open(legacy: keychain);

      await store.delete('a');
      await store.write('b', 'new-b');

      expect(keychain.values, isEmpty);
      final reopened = open(legacy: keychain);
      expect(await reopened.read('a'), isNull);
      expect(await reopened.read('b'), 'new-b');
      expect(keychain.reads, isEmpty);
    },
  );

  test('asks the keychain again after a denied prompt', () async {
    final keychain = _FakeKeychain({'app_store.p8': 'pem'})..deny = true;
    final store = open(legacy: keychain);

    await expectLater(store.read('app_store.p8'), throwsA(isA<StateError>()));

    keychain.deny = false;
    expect(await store.read('app_store.p8'), 'pem');
  });

  test('starts empty when the file was encrypted on another Mac', () async {
    await open(machine: 'MACHINE-A').write('k', 'v');

    final elsewhere = open(machine: 'MACHINE-B');
    expect(await elsewhere.read('k'), isNull);
    await elsewhere.write('k2', 'v2');

    final kept = root.listSync().whereType<File>().where(
      (f) => p.basename(f.path).contains('.unreadable-'),
    );
    expect(kept, hasLength(1));
    expect(await open(machine: 'MACHINE-B').read('k2'), 'v2');
  });

  test('concurrent writes from several services all land', () async {
    final store = open();
    await Future.wait([
      for (var i = 0; i < 20; i++) store.write('key$i', 'value$i'),
    ]);

    final reopened = open();
    for (var i = 0; i < 20; i++) {
      expect(await reopened.read('key$i'), 'value$i');
    }
  });
}

class _FakeKeychain implements LegacySecretSource {
  _FakeKeychain([Map<String, String>? values]) : values = {...?values};

  final Map<String, String> values;
  final reads = <String>[];
  bool deny = false;

  @override
  Future<String?> read(String key) async {
    if (deny) throw StateError('User denied keychain access');
    reads.add(key);
    return values[key];
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}
