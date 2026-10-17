import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/modules/safe/controllers/safe_controller.dart';
import 'package:app_management_center/app/modules/safe/models/safe_item.dart';
import 'package:app_management_center/app/modules/safe/services/safe_password_tools.dart';
import 'package:app_management_center/app/modules/safe/services/safe_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Cheap enough that the suite does not wait on Argon2id, same code path.
const testKdf = SafeKdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

SafeVault vaultAt(String path) => SafeVault(
  locate: () async => File(path),
  kdfParams: testKdf,
  deriveKey: deriveSafeKey,
);

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('amc-safe-test');
    path = p.join(dir.path, 'safe', 'amc-safe.vault');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  SafeItem item(String id, SafeItemKind kind, String secret) => SafeItem(
    id: id,
    kind: kind,
    title: 'Item $id',
    secret: secret,
    createdAt: DateTime(2026, 10, 1),
    updatedAt: DateTime(2026, 10, 1),
  );

  group('SafeVault', () {
    test('seals contents so nothing readable reaches the disk', () async {
      final vault = vaultAt(path);
      final opened = await vault.create('correct horse battery');
      await vault.save(
        opened.session,
        SafeContents(
          items: [item('a', SafeItemKind.password, 'hunter2-very-secret')],
        ),
      );

      final raw = await File(path).readAsString();
      expect(raw, isNot(contains('hunter2-very-secret')));
      expect(raw, isNot(contains('Item a')));
      expect(raw, isNot(contains('correct horse battery')));
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      expect(envelope['format'], 'amc-safe');
      expect(envelope['kdf']['algorithm'], 'argon2id');
    });

    test('opens again with the same code and keeps every field', () async {
      final first = vaultAt(path);
      final opened = await first.create('correct horse battery');
      final stored = item(
        'a',
        SafeItemKind.env,
        'API_URL=https://x\nTOKEN=t',
      ).copyWith(username: 'u', url: 'https://u', notes: 'n', favorite: true);
      await first.save(
        opened.session,
        SafeContents(
          items: [stored],
          settings: const SafeSettings(autoLockMinutes: 15, lockOnClose: true),
        ),
      );

      final again = await vaultAt(path).unlock('correct horse battery');
      final restored = again.contents.items.single;
      expect(restored.secret, stored.secret);
      expect(restored.username, 'u');
      expect(restored.url, 'https://u');
      expect(restored.notes, 'n');
      expect(restored.favorite, isTrue);
      expect(restored.envEntries, {'API_URL': 'https://x', 'TOKEN': 't'});
      expect(again.contents.settings.autoLockMinutes, 15);
      expect(again.contents.settings.lockOnClose, isTrue);
    });

    test('refuses a wrong code with its own exception', () async {
      await vaultAt(path).create('correct horse battery');
      await expectLater(
        vaultAt(path).unlock('wrong horse battery'),
        throwsA(isA<SafeWrongCodeException>()),
      );
    });

    test('a tampered file is damaged, not a wrong code', () async {
      final vault = vaultAt(path);
      final opened = await vault.create('correct horse battery');
      await vault.save(
        opened.session,
        SafeContents(items: [item('a', SafeItemKind.note, 'text')]),
      );
      final envelope =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      final data = envelope['data'] as Map<String, dynamic>;
      final bytes = base64Decode(data['cipherText'] as String);
      bytes[0] ^= 0xff;
      data['cipherText'] = base64Encode(bytes);
      await File(path).writeAsString(jsonEncode(envelope));

      Object? error;
      try {
        await vaultAt(path).unlock('correct horse battery');
      } catch (e) {
        error = e;
      }
      expect(error, isA<SafeException>());
      expect(error, isNot(isA<SafeWrongCodeException>()));
    });

    test('refuses a file that is not a safe', () async {
      await File(path).create(recursive: true);
      await File(path).writeAsString('{"hello": 1}');
      await expectLater(
        vaultAt(path).unlock('anything at all'),
        throwsA(isA<SafeException>()),
      );
    });

    test('refuses absurd KDF costs from a crafted file', () async {
      await vaultAt(path).create('correct horse battery');
      final envelope =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      (envelope['kdf'] as Map<String, dynamic>)['memoryKiB'] = 1 << 30;
      await File(path).writeAsString(jsonEncode(envelope));
      await expectLater(
        vaultAt(path).unlock('correct horse battery'),
        throwsA(
          isA<SafeException>().having(
            (e) => e.message,
            'message',
            contains('Thông số'),
          ),
        ),
      );
    });

    test('changing the code keeps contents and retires the old code', () async {
      final vault = vaultAt(path);
      final opened = await vault.create('correct horse battery');
      final contents = SafeContents(
        items: [item('a', SafeItemKind.apiKey, 'sk-live-123')],
      );
      await vault.save(opened.session, contents);

      await expectLater(
        vault.changeCode(
          opened.session,
          'not the code',
          'new code 12345',
          contents,
        ),
        throwsA(isA<SafeWrongCodeException>()),
      );
      final next = await vault.changeCode(
        opened.session,
        'correct horse battery',
        'new code 12345',
        contents,
      );
      expect(next.isClosed, isFalse);

      await expectLater(
        vaultAt(path).unlock('correct horse battery'),
        throwsA(isA<SafeWrongCodeException>()),
      );
      final reopened = await vaultAt(path).unlock('new code 12345');
      expect(reopened.contents.items.single.secret, 'sk-live-123');
      // No copy wrapped under the old code is left beside the safe.
      expect(File('$path.bak').existsSync(), isFalse);
    });

    test('a backup restores only with its own code', () async {
      final vault = vaultAt(path);
      final opened = await vault.create('correct horse battery');
      await vault.save(
        opened.session,
        SafeContents(items: [item('a', SafeItemKind.note, 'from backup')]),
      );
      final backup = p.join(dir.path, 'backup.vault');
      await vault.exportBackup(backup);

      // A different safe now lives on the machine.
      await File(path).delete();
      final other = await vault.create('another code 999');
      await vault.save(
        other.session,
        SafeContents(items: [item('b', SafeItemKind.note, 'current')]),
      );

      await expectLater(
        vault.restoreBackup(backup, 'another code 999'),
        throwsA(isA<SafeWrongCodeException>()),
      );
      final restored = await vault.restoreBackup(
        backup,
        'correct horse battery',
      );
      expect(restored.contents.items.single.secret, 'from backup');
      final asides = dir
          .listSync(recursive: true)
          .where((entry) => entry.path.contains('before-restore'));
      expect(asides, hasLength(1));
    });

    test('a closed session cannot save', () async {
      final vault = vaultAt(path);
      final opened = await vault.create('correct horse battery');
      opened.session.close();
      await expectLater(
        vault.save(opened.session, const SafeContents()),
        throwsA(isA<SafeException>()),
      );
    });
  });

  group('SafeController', () {
    late DateTime now;
    late String clipboard;

    SafeController controller() => SafeController(
      vault: vaultAt(path),
      now: () => now,
      writeClipboard: (text) async => clipboard = text,
      readClipboard: () async => clipboard,
    );

    setUp(() {
      now = DateTime(2026, 10, 17, 9);
      clipboard = '';
    });

    test('creates, locks and reopens a safe', () async {
      final safe = controller();
      await safe.load();
      expect(safe.stage, SafeStage.uncreated);

      expect(await safe.create('short', 'short'), isFalse);
      expect(safe.doorMessage, contains('ít nhất'));
      expect(await safe.create('long enough 1', 'long enough 2'), isFalse);
      expect(safe.doorMessage, contains('không khớp'));

      expect(await safe.create('long enough 1', 'long enough 1'), isTrue);
      expect(safe.stage, SafeStage.open);
      await safe.put(
        safe
            .draft(SafeItemKind.password)
            .copyWith(title: 'GitHub', username: 'dat', secret: 'pw'),
      );
      await safe.lock();
      expect(safe.stage, SafeStage.locked);
      expect(safe.items, isEmpty);

      expect(await safe.unlock('long enough 1'), isTrue);
      expect(safe.items.single.title, 'GitHub');
      safe.dispose();
    });

    test('slows down repeated wrong codes', () async {
      final safe = controller();
      await safe.load();
      await safe.create('long enough 1', 'long enough 1');
      await safe.lock();

      for (var i = 0; i < 2; i++) {
        expect(await safe.unlock('nope nope'), isFalse);
      }
      expect(safe.cooldownRemaining, Duration.zero);
      expect(await safe.unlock('nope nope'), isFalse);
      expect(safe.cooldownRemaining, const Duration(seconds: 5));
      expect(safe.refusals, 3);

      // Even the right code waits out the cooldown.
      expect(await safe.unlock('long enough 1'), isFalse);
      expect(safe.doorMessage, contains('tạm khoá'));
      now = now.add(const Duration(seconds: 6));
      expect(await safe.unlock('long enough 1'), isTrue);
      expect(safe.failedAttempts, 0);
      safe.dispose();
    });

    test('searches titles and env keys but never secret values', () async {
      final safe = controller();
      await safe.load();
      await safe.create('long enough 1', 'long enough 1');
      await safe.put(
        safe
            .draft(SafeItemKind.env)
            .copyWith(
              title: 'Prod env',
              secret: 'FIREBASE_KEY=abc123\nSENTRY_DSN=zzz',
            ),
      );
      await safe.put(
        safe
            .draft(SafeItemKind.password)
            .copyWith(title: 'Bank', secret: 'firebase-lookalike'),
      );

      safe.setQuery('sentry');
      expect(safe.visibleItems.map((i) => i.title), ['Prod env']);
      safe.setQuery('abc123');
      expect(safe.visibleItems, isEmpty);
      safe.setQuery('lookalike');
      expect(safe.visibleItems, isEmpty);

      safe.setQuery('');
      safe.setFilter(const SafeFilterKind(SafeItemKind.password));
      expect(safe.visibleItems.map((i) => i.title), ['Bank']);
      expect(safe.countFor(const SafeFilterAll()), 2);
      safe.dispose();
    });

    test('favourites sort first and survive a reopen', () async {
      final safe = controller();
      await safe.load();
      await safe.create('long enough 1', 'long enough 1');
      final a = safe.draft(SafeItemKind.note).copyWith(title: 'A');
      await safe.put(a);
      now = now.add(const Duration(minutes: 1));
      await safe.put(safe.draft(SafeItemKind.note).copyWith(title: 'B'));
      expect(safe.visibleItems.first.title, 'B');

      await safe.toggleFavorite(a.id);
      expect(safe.visibleItems.first.title, 'A');
      await safe.lock();
      await safe.unlock('long enough 1');
      expect(safe.visibleItems.first.title, 'A');
      safe.dispose();
    });

    test(
      'wipes a copied secret on lock unless something replaced it',
      () async {
        final safe = controller();
        await safe.load();
        await safe.create('long enough 1', 'long enough 1');

        await safe.copySecret('sk-secret');
        expect(clipboard, 'sk-secret');
        await safe.lock();
        expect(clipboard, '');

        await safe.unlock('long enough 1');
        await safe.copySecret('sk-secret');
        clipboard = 'something the user copied later';
        await safe.lock();
        expect(clipboard, 'something the user copied later');
        safe.dispose();
      },
    );

    test('locks on page close only when asked to', () async {
      final safe = controller();
      await safe.load();
      await safe.create('long enough 1', 'long enough 1');
      await safe.pageClosed();
      expect(safe.isOpen, isTrue);

      await safe.updateSettings(safe.settings.copyWith(lockOnClose: true));
      await safe.pageClosed();
      expect(safe.stage, SafeStage.locked);
      safe.dispose();
    });

    test('changes the code', () async {
      final safe = controller();
      await safe.load();
      await safe.create('long enough 1', 'long enough 1');
      expect(
        await safe.changeCode('wrong', 'new code 999', 'new code 999'),
        contains('không đúng'),
      );
      expect(
        await safe.changeCode('long enough 1', 'new code 999', 'new code 999'),
        isNull,
      );
      await safe.lock();
      expect(await safe.unlock('long enough 1'), isFalse);
      expect(await safe.unlock('new code 999'), isTrue);
      safe.dispose();
    });
  });

  group('SafeItem', () {
    test('summarises without leaking the secret', () {
      final json = item(
        'j',
        SafeItemKind.jsonKey,
        '{"type":"service_account","client_email":"ci@p.iam.gserviceaccount.com","private_key":"-----BEGIN"}',
      );
      expect(json.summary, 'ci@p.iam.gserviceaccount.com');
      expect(
        item('n', SafeItemKind.note, 'my secret line').summary,
        '14 ký tự',
      );
      expect(item('k', SafeItemKind.apiKey, 'sk-123').summary, '6 ký tự');
      final file = item(
        'f',
        SafeItemKind.file,
        base64Encode(List.filled(2000, 7)),
      ).copyWith(fileName: 'upload.jks');
      expect(file.fileSize, 2000);
      expect(file.summary, 'upload.jks · 2.0 KB');
    });
  });

  group('password tools', () {
    test('generates from every chosen group', () {
      for (var i = 0; i < 50; i++) {
        final value = generatePassword(const PasswordRecipe(length: 12));
        expect(value, hasLength(12));
        expect(value, matches(RegExp('[A-Z]')));
        expect(value, matches(RegExp('[a-z]')));
        expect(value, matches(RegExp('[0-9]')));
        expect(value, matches(RegExp(r'[^A-Za-z0-9]')));
        expect(value, isNot(matches(RegExp('[Il1O0o]'))));
      }
      expect(
        generatePassword(const PasswordRecipe(symbols: false, upper: false)),
        matches(RegExp(r'^[a-z0-9]+$')),
      );
    });

    test('rates obvious passwords low and long random ones high', () {
      expect(ratePassword(''), PasswordStrength.empty);
      expect(ratePassword('aaaaaaaaaaaa'), PasswordStrength.weak);
      expect(ratePassword('password'), PasswordStrength.fair);
      expect(
        ratePassword(generatePassword(const PasswordRecipe(length: 24))),
        PasswordStrength.strong,
      );
    });
  });
}
