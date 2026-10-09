import 'package:cloud_firestore/cloud_firestore.dart';

import 'account_vault.dart';

/// The team vault in Firestore, beside the team's API Tool collections:
///
/// - `teams/{team}/qaVault/meta`: salt, KDF cost and key check;
/// - `qaAccounts/{id}`: role, app, environment in clear, the rest encrypted;
/// - `qaAccountStatus/{id}`: last login result, written by any member;
/// - `qaAccountLeases/{id}`: who is using the account until when;
/// - `qaAccountAudit/{auto}`: append-only history.
///
/// `firestore.rules` holds the matching permissions.
class FirestoreVaultBackend implements VaultBackend {
  FirestoreVaultBackend({required this.teamId, FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final String teamId;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _team =>
      _db.collection('teams').doc(teamId);

  CollectionReference<Map<String, dynamic>> _collection(String name) =>
      _team.collection(name);

  @override
  Future<Map<String, dynamic>?> readMeta() async =>
      (await _collection('qaVault').doc('meta').get()).data();

  @override
  Future<void> writeMeta(Map<String, dynamic> meta) =>
      _collection('qaVault').doc('meta').set(meta);

  Future<Map<String, Map<String, dynamic>>> _all(String name) async {
    final snapshot = await _collection(name).get();
    return {for (final doc in snapshot.docs) doc.id: doc.data()};
  }

  @override
  Future<Map<String, Map<String, dynamic>>> listAccounts() =>
      _all('qaAccounts');

  @override
  Future<void> putAccount(String id, Map<String, dynamic> document) =>
      _collection('qaAccounts').doc(id).set(document);

  @override
  Future<void> deleteAccount(String id) =>
      _collection('qaAccounts').doc(id).delete();

  @override
  Future<Map<String, Map<String, dynamic>>> listStatuses() =>
      _all('qaAccountStatus');

  @override
  Future<void> putStatus(String id, Map<String, dynamic> status) =>
      _collection('qaAccountStatus').doc(id).set(status);

  @override
  Future<Map<String, AccountLease>> listLeases() async {
    final docs = await _all('qaAccountLeases');
    return {
      for (final entry in docs.entries)
        entry.key: AccountLease.fromJson(
          entry.key,
          _fromFirestore(entry.value),
        ),
    };
  }

  @override
  Future<bool> tryLease(AccountLease lease, DateTime now) async {
    final ref = _collection('qaAccountLeases').doc(lease.accountId);
    try {
      return await _db.runTransaction((transaction) async {
        final current = await transaction.get(ref);
        final data = current.data();
        if (data != null) {
          final held = AccountLease.fromJson(
            lease.accountId,
            _fromFirestore(data),
          );
          if (held.holderUid != lease.holderUid && !held.expiredAt(now)) {
            return false;
          }
        }
        transaction.set(ref, {
          ...lease.toJson(),
          // A Timestamp, so the rules can compare it with request.time.
          'expiresAt': Timestamp.fromDate(lease.expiresAt),
        });
        return true;
      });
    } on FirebaseException catch (error) {
      // The rules refuse a lease someone else still holds, by server time.
      if (error.code == 'permission-denied') return false;
      rethrow;
    }
  }

  @override
  Future<void> releaseLease(
    String accountId,
    String holderUid,
    String runId,
  ) async {
    final ref = _collection('qaAccountLeases').doc(accountId);
    await _db.runTransaction((transaction) async {
      final current = (await transaction.get(ref)).data();
      if (current != null &&
          current['holderUid'] == holderUid &&
          current['runId'] == runId) {
        transaction.delete(ref);
      }
    });
  }

  @override
  Future<void> addAudit(Map<String, dynamic> event) => _collection(
    'qaAccountAudit',
  ).add({...event, 'serverAt': FieldValue.serverTimestamp()});

  static Map<String, dynamic> _fromFirestore(Map<String, dynamic> data) => {
    for (final entry in data.entries)
      entry.key: entry.value is Timestamp
          ? (entry.value as Timestamp).toDate()
          : entry.value,
  };
}
