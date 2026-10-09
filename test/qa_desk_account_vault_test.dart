import 'dart:convert';

import 'package:app_management_center/app/modules/qa_desk/models/automation_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/account_vault.dart';
import 'package:app_management_center/app/modules/qa_desk/services/qa_desk_host.dart';
import 'package:app_management_center/app/modules/qa_desk/services/vault_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cheap enough for tests; real vaults use [VaultKdfParams.standard].
const fastKdf = VaultKdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

const passphrase = 'đúng là passphrase dài';

const owner = DemoAccount(
  id: 'owner',
  app: 'shop',
  environment: 'staging',
  role: 'Chủ shop',
  username: '0912345678',
  password: 'S3cret-Owner',
  extra: {'shop': '001'},
);

const admin = QaTeamContext(
  teamId: 'team-1',
  teamName: 'Fiza',
  uid: 'uid-admin',
  email: 'admin@example.com',
  isAdmin: true,
);

const member = QaTeamContext(
  teamId: 'team-1',
  teamName: 'Fiza',
  uid: 'uid-member',
  email: 'member@example.com',
  isAdmin: false,
);

TeamAccountVault teamVault(
  MemoryVaultBackend backend,
  QaTeamContext team, [
  MemorySecretStore? store,
]) => TeamAccountVault(
  backend: backend,
  store: store ?? MemorySecretStore(),
  team: team,
  machine: 'test-pc',
  kdf: fastKdf,
);

void main() {
  group('VaultCipher', () {
    test('round-trips, and only the right passphrase opens it', () async {
      final salt = VaultCipher.randomBytes(16);
      final cipher = await VaultCipher.derive(passphrase, salt, fastKdf);
      final first = await cipher.encrypt('mật khẩu');
      final second = await cipher.encrypt('mật khẩu');

      expect(first, startsWith('qav1:'));
      expect(first, isNot(second), reason: 'a fresh nonce every time');
      expect(await cipher.decrypt(first), 'mật khẩu');
      expect(
        await VaultCipher.fromKeyBytes(cipher.keyBytes).decrypt(second),
        'mật khẩu',
      );

      final check = await cipher.encrypt(VaultCipher.checkPlaintext);
      final wrong = await VaultCipher.derive(
        'sai passphrase rồi',
        salt,
        fastKdf,
      );
      expect(await wrong.opens(check), isFalse);
      expect(await cipher.opens(check), isTrue);
      expect(() => wrong.decrypt(first), throwsA(isA<VaultException>()));
      expect(
        () => cipher.decrypt('${first.substring(0, first.length - 4)}AAA='),
        throwsA(isA<VaultException>()),
      );
    });
  });

  group('LocalAccountVault', () {
    test('keeps accounts in secure storage across loads', () async {
      final store = MemorySecretStore();
      final vault = LocalAccountVault(store: store, machine: 'pc');
      await vault.load();
      expect(vault.state, VaultState.ready);
      await vault.save(owner);

      final again = LocalAccountVault(store: store, machine: 'pc');
      await again.load();
      expect(again.accounts.single.password, 'S3cret-Owner');
      expect(again.accounts.single.extra, {'shop': '001'});
      expect(again.rolesFor('shop', 'staging'), ['Chủ shop']);
    });

    test('picks a working account of the role, and leases it once', () async {
      final vault = LocalAccountVault(
        store: MemorySecretStore(),
        machine: 'pc',
      );
      await vault.load();
      await vault.save(owner.copyWith(status: AccountStatus.loginFailed));
      await vault.save(
        const DemoAccount(
          id: 'owner-2',
          app: 'shop',
          environment: 'staging',
          role: 'Chủ shop',
          username: '0900000002',
          password: 'S3cret-Two',
        ),
      );
      await vault.save(
        const DemoAccount(
          id: 'off',
          app: 'shop',
          environment: 'staging',
          role: 'Kế toán',
          username: 'kt',
          password: 'x',
          status: AccountStatus.disabled,
        ),
      );

      expect(
        vault.pick(app: 'shop', environment: 'staging', role: 'Chủ shop')?.id,
        'owner-2',
      );
      expect(
        vault.pick(app: 'shop', environment: 'staging', role: 'Kế toán'),
        isNull,
      );
      expect(
        vault.pick(app: 'shop', environment: 'production', role: 'Chủ shop'),
        isNull,
      );

      final account = vault.accounts.firstWhere((item) => item.id == 'owner-2');
      final lease = await vault.acquire(account, runId: 'run-1');
      expect(lease, isNotNull);
      expect(await vault.acquire(account, runId: 'run-2'), isNull);
      await vault.release(lease!);
      expect(await vault.acquire(account, runId: 'run-2'), isNotNull);
    });
  });

  group('TeamAccountVault', () {
    test('an Admin creates it; Firebase only sees ciphertext', () async {
      final backend = MemoryVaultBackend();
      final vault = teamVault(backend, admin);
      await vault.load();
      expect(vault.state, VaultState.needsSetup);

      await expectLater(
        vault.create('ngắn quá'),
        throwsA(isA<VaultException>()),
      );
      await vault.create(passphrase);
      expect(vault.state, VaultState.ready);
      await vault.save(owner);

      final stored = jsonEncode([backend.meta, backend.accountDocs]);
      for (final secret in ['0912345678', 'S3cret-Owner', '001', passphrase]) {
        expect(stored, isNot(contains(secret)));
      }
      expect(backend.accountDocs['owner']?['role'], 'Chủ shop');
      expect(vault.accounts.single.password, 'S3cret-Owner');
      expect(backend.audit.map((event) => event['type']), [
        'createVault',
        'create',
      ]);
      await expectLater(
        teamVault(backend, admin).create(passphrase),
        throwsA(isA<VaultException>()),
      );
    });

    test('a member unlocks once per machine and may not edit', () async {
      final backend = MemoryVaultBackend();
      final creator = teamVault(backend, admin);
      await creator.load();
      await creator.create(passphrase);
      await creator.save(owner);

      final store = MemorySecretStore();
      final vault = teamVault(backend, member, store);
      await vault.load();
      expect(vault.state, VaultState.locked);
      expect(vault.canEdit, isFalse);
      expect(
        await vault.unlock('sai passphrase rồi nhé'),
        'Passphrase không đúng.',
      );
      expect(await vault.unlock(passphrase), isNull);
      expect(vault.state, VaultState.ready);
      expect(vault.accounts.single.username, '0912345678');

      await expectLater(vault.save(owner), throwsA(isA<VaultException>()));
      await expectLater(vault.delete('owner'), throwsA(isA<VaultException>()));
      await expectLater(
        vault.recordReveal('owner'),
        throwsA(isA<VaultException>()),
      );

      // The same machine opens it next time without the passphrase.
      final later = teamVault(backend, member, store);
      await later.load();
      expect(later.state, VaultState.ready);

      await later.lock();
      expect(later.state, VaultState.locked);
      expect(store.values, isEmpty);
    });

    test('a passphrase changed elsewhere locks the cached key out', () async {
      final backend = MemoryVaultBackend();
      final store = MemorySecretStore();
      final vault = teamVault(backend, admin, store);
      await vault.load();
      await vault.create(passphrase);

      backend.meta = null;
      await teamVault(backend, admin).create('một passphrase mới hẳn');
      final again = teamVault(backend, admin, store);
      await again.load();
      expect(again.state, VaultState.locked);
      expect(store.values, isEmpty);
    });

    test(
      'two people never hold one account; an expired lease is free',
      () async {
        final backend = MemoryVaultBackend();
        final first = teamVault(backend, admin);
        await first.load();
        await first.create(passphrase);
        await first.save(owner);
        final second = teamVault(backend, member);
        await second.load();
        await second.unlock(passphrase);
        final account = second.accounts.single;

        final lease = await first.acquire(account, runId: 'run-a');
        expect(lease, isNotNull);
        expect(await second.acquire(account, runId: 'run-b'), isNull);
        expect(second.leases['owner']?.holderName, 'admin@example.com');

        await first.release(lease!);
        final taken = await second.acquire(account, runId: 'run-b');
        expect(taken, isNotNull);

        backend.leaseDocs['owner'] = AccountLease(
          accountId: 'owner',
          holderUid: 'uid-member',
          holderName: 'member@example.com',
          machine: 'other',
          runId: 'run-b',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        );
        expect(await first.acquire(account, runId: 'run-c'), isNotNull);
        expect(
          backend.audit.where((event) => event['type'] == 'lease').length,
          3,
        );
      },
    );

    test('login status is shared with the team', () async {
      final backend = MemoryVaultBackend();
      final first = teamVault(backend, admin);
      await first.load();
      await first.create(passphrase);
      await first.save(owner);
      final second = teamVault(backend, member);
      await second.load();
      await second.unlock(passphrase);

      await second.setStatus(
        'owner',
        AccountStatus.loginFailed,
        'Sai mật khẩu',
      );
      await first.refresh();
      expect(first.accounts.single.status, AccountStatus.loginFailed);
      expect(first.accounts.single.statusMessage, 'Sai mật khẩu');
    });
  });
}
