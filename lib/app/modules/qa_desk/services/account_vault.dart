import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/automation_models.dart';
import 'qa_desk_host.dart';
import 'vault_cipher.dart';

enum VaultMode { local, team }

enum VaultState {
  loading,

  /// Team vault not created yet; an Admin creates it with a passphrase.
  needsSetup,

  /// Created, but this machine has not been given the passphrase.
  locked,
  ready,

  /// Could not reach the vault; [AccountVault.error] says why.
  failed,
}

/// One run holding an account, so two people never log the same account in
/// at once on an app that allows a single session.
class AccountLease {
  const AccountLease({
    required this.accountId,
    required this.holderUid,
    required this.holderName,
    required this.machine,
    required this.runId,
    required this.expiresAt,
  });

  final String accountId;
  final String holderUid;
  final String holderName;
  final String machine;
  final String runId;
  final DateTime expiresAt;

  bool expiredAt(DateTime now) => !expiresAt.isAfter(now);

  Map<String, dynamic> toJson() => {
    'holderUid': holderUid,
    'holderName': holderName,
    'machine': machine,
    'runId': runId,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory AccountLease.fromJson(String accountId, Map<String, dynamic> json) =>
      AccountLease(
        accountId: accountId,
        holderUid: json['holderUid']?.toString() ?? '',
        holderName: json['holderName']?.toString() ?? '',
        machine: json['machine']?.toString() ?? '',
        runId: json['runId']?.toString() ?? '',
        expiresAt: json['expiresAt'] is DateTime
            ? json['expiresAt'] as DateTime
            : DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Where the demo accounts live: on this machine, or shared with the team.
abstract class AccountVault extends ChangeNotifier {
  VaultMode get mode;
  VaultState get state;

  /// "Trên máy này", or the team's name.
  String get label;

  /// Who runs on this machine, for leases.
  String get holderUid;

  /// May add, edit, delete and reveal accounts: always on this machine, only
  /// Admins in a team.
  bool get canEdit;

  String? get error;
  List<DemoAccount> get accounts;
  Map<String, AccountLease> get leases;

  Future<void> load();
  Future<void> save(DemoAccount account);
  Future<void> delete(String id);

  /// Records that the password was shown; the value is already in memory.
  Future<void> recordReveal(String id);

  /// Takes [account] for [runId]; null when someone else holds it.
  Future<AccountLease?> acquire(
    DemoAccount account, {
    required String runId,
    Duration ttl = const Duration(minutes: 10),
  });
  Future<void> release(AccountLease lease);
  Future<void> setStatus(String id, AccountStatus status, String message);

  /// Team vaults only.
  Future<void> create(String passphrase) async =>
      throw const VaultException('Kho trên máy không cần passphrase.');
  Future<String?> unlock(String passphrase) async => null;
  Future<void> lock() async {}

  /// The account a scenario logs in with: one for its app, environment and
  /// role that nobody else holds, a working one before one that last failed.
  DemoAccount? pick({
    required String app,
    required String environment,
    required String role,
  }) {
    final now = DateTime.now();
    final candidates = accounts.where(
      (account) =>
          account.app == app &&
          account.environment == environment &&
          account.role == role &&
          account.status != AccountStatus.disabled,
    );
    int rank(DemoAccount account) {
      final lease = leases[account.id];
      final free =
          lease == null || lease.expiredAt(now) || lease.holderUid == holderUid;
      return (free ? 0 : 2) + (account.status == AccountStatus.ok ? 0 : 1);
    }

    final sorted = candidates.toList()
      ..sort((a, b) => rank(a).compareTo(rank(b)));
    return sorted.isEmpty ? null : sorted.first;
  }

  /// Every role the vault has for [app] in [environment].
  List<String> rolesFor(String app, String environment) => {
    for (final account in accounts)
      if (account.app == app && account.environment == environment)
        account.role,
  }.toList()..sort();
}

/// Accounts kept in this machine's secure storage, for AMC without a team
/// or before a team vault exists.
class LocalAccountVault extends AccountVault {
  LocalAccountVault({required SecretStore store, String? machine})
    : _store = store,
      _machine = machine ?? Platform.localHostname;

  static const storageKey = 'qa_desk.accounts.v1';

  final SecretStore _store;
  final String _machine;
  final _accounts = <DemoAccount>[];
  final _leases = <String, AccountLease>{};
  VaultState _state = VaultState.loading;
  String? _error;

  @override
  VaultMode get mode => VaultMode.local;

  @override
  VaultState get state => _state;

  @override
  String get label => 'Trên máy này';

  @override
  String get holderUid => 'local:$_machine';

  @override
  bool get canEdit => true;

  @override
  String? get error => _error;

  @override
  List<DemoAccount> get accounts => List.unmodifiable(_accounts);

  @override
  Map<String, AccountLease> get leases => Map.unmodifiable(_leases);

  @override
  Future<void> load() async {
    try {
      final raw = await _store.read(storageKey);
      _accounts
        ..clear()
        ..addAll([
          for (final item in raw == null ? const [] : jsonDecode(raw) as List)
            DemoAccount.fromJson(Map<String, dynamic>.from(item as Map)),
        ]);
      _state = VaultState.ready;
      _error = null;
    } on Object catch (error) {
      _state = VaultState.failed;
      _error = 'Không đọc được kho tài khoản trên máy: $error';
    }
    notifyListeners();
  }

  Future<void> _persist() => _store.write(
    storageKey,
    jsonEncode([for (final account in _accounts) account.toJson()]),
  );

  @override
  Future<void> save(DemoAccount account) async {
    final index = _accounts.indexWhere((item) => item.id == account.id);
    final stamped = account.copyWith(updatedAt: DateTime.now());
    if (index < 0) {
      _accounts.add(stamped);
    } else {
      _accounts[index] = stamped;
    }
    await _persist();
    notifyListeners();
  }

  @override
  Future<void> delete(String id) async {
    _accounts.removeWhere((item) => item.id == id);
    _leases.remove(id);
    await _persist();
    notifyListeners();
  }

  @override
  Future<void> recordReveal(String id) async {}

  @override
  Future<AccountLease?> acquire(
    DemoAccount account, {
    required String runId,
    Duration ttl = const Duration(minutes: 10),
  }) async {
    final now = DateTime.now();
    final current = _leases[account.id];
    if (current != null && !current.expiredAt(now) && current.runId != runId) {
      return null;
    }
    final lease = AccountLease(
      accountId: account.id,
      holderUid: holderUid,
      holderName: _machine,
      machine: _machine,
      runId: runId,
      expiresAt: now.add(ttl),
    );
    _leases[account.id] = lease;
    notifyListeners();
    return lease;
  }

  @override
  Future<void> release(AccountLease lease) async {
    if (_leases[lease.accountId]?.runId == lease.runId) {
      _leases.remove(lease.accountId);
      notifyListeners();
    }
  }

  @override
  Future<void> setStatus(
    String id,
    AccountStatus status,
    String message,
  ) async {
    final index = _accounts.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _accounts[index] = _accounts[index].copyWith(
      status: status,
      statusMessage: message,
      statusAt: DateTime.now(),
    );
    await _persist();
    notifyListeners();
  }
}

/// The team vault's storage, kept apart so the vault's rules and encryption
/// are tested without a server. Documents arrive already encrypted.
abstract interface class VaultBackend {
  Future<Map<String, dynamic>?> readMeta();
  Future<void> writeMeta(Map<String, dynamic> meta);
  Future<Map<String, Map<String, dynamic>>> listAccounts();
  Future<void> putAccount(String id, Map<String, dynamic> document);
  Future<void> deleteAccount(String id);
  Future<Map<String, Map<String, dynamic>>> listStatuses();
  Future<void> putStatus(String id, Map<String, dynamic> status);
  Future<Map<String, AccountLease>> listLeases();

  /// Takes the lease when it is free, expired, or already [lease]'s holder's;
  /// atomically, so two machines cannot both win.
  Future<bool> tryLease(AccountLease lease, DateTime now);
  Future<void> releaseLease(String accountId, String holderUid, String runId);
  Future<void> addAudit(Map<String, dynamic> event);
}

class MemoryVaultBackend implements VaultBackend {
  Map<String, dynamic>? meta;
  final accountDocs = <String, Map<String, dynamic>>{};
  final statuses = <String, Map<String, dynamic>>{};
  final leaseDocs = <String, AccountLease>{};
  final audit = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>?> readMeta() async => meta;

  @override
  Future<void> writeMeta(Map<String, dynamic> value) async => meta = value;

  @override
  Future<Map<String, Map<String, dynamic>>> listAccounts() async =>
      Map.of(accountDocs);

  @override
  Future<void> putAccount(String id, Map<String, dynamic> document) async =>
      accountDocs[id] = document;

  @override
  Future<void> deleteAccount(String id) async => accountDocs.remove(id);

  @override
  Future<Map<String, Map<String, dynamic>>> listStatuses() async =>
      Map.of(statuses);

  @override
  Future<void> putStatus(String id, Map<String, dynamic> status) async =>
      statuses[id] = status;

  @override
  Future<Map<String, AccountLease>> listLeases() async => Map.of(leaseDocs);

  @override
  Future<bool> tryLease(AccountLease lease, DateTime now) async {
    final current = leaseDocs[lease.accountId];
    if (current != null &&
        !current.expiredAt(now) &&
        current.holderUid != lease.holderUid) {
      return false;
    }
    leaseDocs[lease.accountId] = lease;
    return true;
  }

  @override
  Future<void> releaseLease(
    String accountId,
    String holderUid,
    String runId,
  ) async {
    final current = leaseDocs[accountId];
    if (current != null &&
        current.holderUid == holderUid &&
        current.runId == runId) {
      leaseDocs.remove(accountId);
    }
  }

  @override
  Future<void> addAudit(Map<String, dynamic> event) async => audit.add(event);
}

/// Accounts shared with the team, encrypted end to end with the team's
/// passphrase. Admins edit; every member may run with them.
class TeamAccountVault extends AccountVault {
  TeamAccountVault({
    required VaultBackend backend,
    required SecretStore store,
    required this.team,
    String? machine,
    this.kdf = VaultKdfParams.standard,
  }) : _backend = backend,
       _store = store,
       _machine = machine ?? Platform.localHostname;

  final VaultBackend _backend;
  final SecretStore _store;
  final QaTeamContext team;
  final String _machine;

  /// Cost for a newly created vault; existing vaults keep theirs.
  final VaultKdfParams kdf;

  final _accounts = <DemoAccount>[];
  var _leases = <String, AccountLease>{};
  VaultState _state = VaultState.loading;
  VaultCipher? _cipher;
  Map<String, dynamic>? _meta;
  String? _error;

  String get _keyName => 'qa_desk.vault.${team.teamId}';

  @override
  VaultMode get mode => VaultMode.team;

  @override
  VaultState get state => _state;

  @override
  String get label => team.teamName.isEmpty ? 'Team' : team.teamName;

  @override
  String get holderUid => team.uid;

  @override
  bool get canEdit => team.isAdmin;

  @override
  String? get error => _error;

  @override
  List<DemoAccount> get accounts => List.unmodifiable(_accounts);

  @override
  Map<String, AccountLease> get leases => Map.unmodifiable(_leases);

  @override
  Future<void> load() async {
    _state = VaultState.loading;
    notifyListeners();
    try {
      _meta = await _backend.readMeta();
      final meta = _meta;
      if (meta == null) {
        _state = VaultState.needsSetup;
      } else {
        final cached = await _store.read(_keyName);
        final cipher = cached == null
            ? null
            : VaultCipher.fromKeyBytes(base64Url.decode(cached));
        if (cipher != null && await cipher.opens(meta['check'].toString())) {
          _cipher = cipher;
          await _refresh();
          _state = VaultState.ready;
        } else {
          // A passphrase change elsewhere makes the cached key stale.
          if (cached != null) await _store.delete(_keyName);
          _state = VaultState.locked;
        }
      }
      _error = null;
    } on Object catch (error) {
      _state = VaultState.failed;
      _error = 'Không mở được kho tài khoản của team: $error';
    }
    notifyListeners();
  }

  @override
  Future<void> create(String passphrase) async {
    if (!team.isAdmin) {
      throw const VaultException('Chỉ Admin của team được tạo kho.');
    }
    if (passphrase.length < 12) {
      throw const VaultException('Passphrase cần ít nhất 12 ký tự.');
    }
    if (await _backend.readMeta() != null) {
      throw const VaultException('Team đã có kho tài khoản.');
    }
    final salt = VaultCipher.randomBytes(16);
    final cipher = await VaultCipher.derive(passphrase, salt, kdf);
    final meta = {
      'version': 1,
      'salt': base64UrlEncode(salt),
      'kdf': kdf.toJson(),
      'check': await cipher.encrypt(VaultCipher.checkPlaintext),
      'createdBy': team.email,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _backend.writeMeta(meta);
    await _audit('createVault');
    await _remember(cipher);
    _meta = meta;
    await _refresh();
    _state = VaultState.ready;
    notifyListeners();
  }

  @override
  Future<String?> unlock(String passphrase) async {
    final meta = _meta ?? await _backend.readMeta();
    if (meta == null) return 'Team chưa có kho tài khoản.';
    final cipher = await VaultCipher.derive(
      passphrase,
      base64Url.decode(meta['salt'].toString()),
      VaultKdfParams.fromJson(Map<String, dynamic>.from(meta['kdf'] as Map)),
    );
    if (!await cipher.opens(meta['check'].toString())) {
      return 'Passphrase không đúng.';
    }
    _meta = meta;
    await _remember(cipher);
    await _refresh();
    _state = VaultState.ready;
    notifyListeners();
    return null;
  }

  @override
  Future<void> lock() async {
    await _store.delete(_keyName);
    _cipher = null;
    _accounts.clear();
    _state = VaultState.locked;
    notifyListeners();
  }

  Future<void> _remember(VaultCipher cipher) async {
    _cipher = cipher;
    await _store.write(_keyName, base64UrlEncode(cipher.keyBytes));
  }

  VaultCipher get _readyCipher {
    // [lock] drops the key; while unlocking, the state is still `locked`
    // until the accounts have been read with the new key.
    final cipher = _cipher;
    if (cipher == null) {
      throw const VaultException('Kho đang khoá.');
    }
    return cipher;
  }

  Future<void> _refresh() async {
    final cipher = _readyCipher;
    final docs = await _backend.listAccounts();
    final statuses = await _backend.listStatuses();
    final accounts = <DemoAccount>[];
    for (final entry in docs.entries) {
      final doc = entry.value;
      final secret =
          jsonDecode(await cipher.decrypt(doc['secret'].toString()))
              as Map<String, dynamic>;
      final status = statuses[entry.key] ?? const {};
      accounts.add(
        DemoAccount(
          id: entry.key,
          app: doc['app']?.toString() ?? '',
          environment: doc['environment']?.toString() ?? '',
          role: doc['role']?.toString() ?? '',
          username: secret['username']?.toString() ?? '',
          password: secret['password']?.toString() ?? '',
          extra: {
            for (final item
                in (secret['extra'] as Map<dynamic, dynamic>? ?? const {})
                    .entries)
              item.key.toString(): item.value.toString(),
          },
          notes: secret['notes']?.toString() ?? '',
          access: AccountAccess.parse(doc['access']?.toString()),
          status: AccountStatus.parse(status['status']?.toString()),
          statusMessage: status['message']?.toString() ?? '',
          statusAt: DateTime.tryParse(status['at']?.toString() ?? ''),
          updatedAt: DateTime.tryParse(doc['updatedAt']?.toString() ?? ''),
          updatedBy: doc['updatedBy']?.toString() ?? '',
        ),
      );
    }
    accounts.sort(
      (a, b) => '${a.app}${a.environment}${a.role}'.compareTo(
        '${b.app}${b.environment}${b.role}',
      ),
    );
    _accounts
      ..clear()
      ..addAll(accounts);
    _leases = await _backend.listLeases();
  }

  /// Re-reads accounts and leases, for the sheet's refresh button.
  Future<void> refresh() async {
    if (_state != VaultState.ready) return load();
    await _refresh();
    notifyListeners();
  }

  void _requireAdmin() {
    if (!team.isAdmin) {
      throw const VaultException('Chỉ Admin của team được sửa kho tài khoản.');
    }
  }

  @override
  Future<void> save(DemoAccount account) async {
    _requireAdmin();
    final cipher = _readyCipher;
    final exists = _accounts.any((item) => item.id == account.id);
    await _backend.putAccount(account.id, {
      'app': account.app,
      'environment': account.environment,
      'role': account.role,
      'access': account.access.value,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'updatedBy': team.email,
      'secret': await cipher.encrypt(
        jsonEncode({
          'username': account.username,
          'password': account.password,
          'extra': account.extra,
          'notes': account.notes,
        }),
      ),
    });
    await _audit(exists ? 'update' : 'create', accountId: account.id);
    await _refresh();
    notifyListeners();
  }

  /// Copies accounts from this machine's vault into the team's.
  Future<int> importAccounts(List<DemoAccount> accounts) async {
    for (final account in accounts) {
      await save(account);
    }
    return accounts.length;
  }

  @override
  Future<void> delete(String id) async {
    _requireAdmin();
    await _backend.deleteAccount(id);
    await _audit('delete', accountId: id);
    await _refresh();
    notifyListeners();
  }

  @override
  Future<void> recordReveal(String id) async {
    _requireAdmin();
    await _audit('reveal', accountId: id);
  }

  @override
  Future<AccountLease?> acquire(
    DemoAccount account, {
    required String runId,
    Duration ttl = const Duration(minutes: 10),
  }) async {
    final now = DateTime.now();
    final lease = AccountLease(
      accountId: account.id,
      holderUid: team.uid,
      holderName: team.email,
      machine: _machine,
      runId: runId,
      expiresAt: now.add(ttl),
    );
    if (!await _backend.tryLease(lease, now)) {
      _leases = await _backend.listLeases();
      notifyListeners();
      return null;
    }
    await _audit('lease', accountId: account.id, runId: runId);
    _leases = {..._leases, account.id: lease};
    notifyListeners();
    return lease;
  }

  @override
  Future<void> release(AccountLease lease) async {
    await _backend.releaseLease(lease.accountId, lease.holderUid, lease.runId);
    _leases = {..._leases}..remove(lease.accountId);
    notifyListeners();
  }

  @override
  Future<void> setStatus(
    String id,
    AccountStatus status,
    String message,
  ) async {
    final at = DateTime.now();
    await _backend.putStatus(id, {
      'status': status.value,
      'message': message,
      'at': at.toUtc().toIso8601String(),
      'by': team.email,
    });
    final index = _accounts.indexWhere((item) => item.id == id);
    if (index >= 0) {
      _accounts[index] = _accounts[index].copyWith(
        status: status,
        statusMessage: message,
        statusAt: at,
      );
    }
    notifyListeners();
  }

  Future<void> _audit(String type, {String? accountId, String? runId}) =>
      _backend.addAudit({
        'type': type,
        'uid': team.uid,
        'email': team.email,
        'machine': _machine,
        'at': DateTime.now().toUtc().toIso8601String(),
        'accountId': ?accountId,
        'runId': ?runId,
      });
}
