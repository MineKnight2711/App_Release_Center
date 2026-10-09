import 'package:app_management_center/app/data/amc_api_client.dart';
import 'package:app_management_center/app/modules/qa_desk/services/account_vault.dart';

/// The team's QA Desk vault on the App Management Center Worker. Documents
/// arrive already encrypted; the Worker decides who may read, change or hold
/// an account (`cloudflare/amc-api/src/qaVault.ts`).
class AmcVaultBackend implements VaultBackend {
  AmcVaultBackend({required AmcApiClient api, required this.teamId})
    : _api = api;

  final AmcApiClient _api;
  final String teamId;

  String get _base => '/teams/${Uri.encodeComponent(teamId)}/qa-vault';

  @override
  Future<Map<String, dynamic>?> readMeta() async {
    final meta = (await _api.get('$_base/meta'))['meta'];
    return meta is Map ? Map<String, dynamic>.from(meta) : null;
  }

  @override
  Future<void> writeMeta(Map<String, dynamic> meta) =>
      _api.put('$_base/meta', body: {'meta': meta});

  @override
  Future<Map<String, Map<String, dynamic>>> listAccounts() async =>
      _documents((await _api.get('$_base/accounts'))['accounts']);

  @override
  Future<void> putAccount(String id, Map<String, dynamic> document) => _api.put(
    '$_base/accounts/${Uri.encodeComponent(id)}',
    body: {'document': document},
  );

  @override
  Future<void> deleteAccount(String id) =>
      _api.delete('$_base/accounts/${Uri.encodeComponent(id)}');

  @override
  Future<Map<String, Map<String, dynamic>>> listStatuses() async =>
      _documents((await _api.get('$_base/statuses'))['statuses']);

  @override
  Future<void> putStatus(String id, Map<String, dynamic> status) => _api.put(
    '$_base/statuses/${Uri.encodeComponent(id)}',
    body: {'status': status},
  );

  @override
  Future<Map<String, AccountLease>> listLeases() async {
    final docs = _documents((await _api.get('$_base/leases'))['leases']);
    return {
      for (final entry in docs.entries)
        entry.key: AccountLease.fromJson(entry.key, entry.value),
    };
  }

  /// The Worker compares expiry with its own clock and takes the lease in the
  /// session user's name, so [now] and [AccountLease.holderUid] are not sent.
  @override
  Future<bool> tryLease(AccountLease lease, DateTime now) async {
    final body = await _api.post(
      '$_base/leases/${Uri.encodeComponent(lease.accountId)}',
      body: lease.toJson(),
    );
    return body['acquired'] == true;
  }

  @override
  Future<void> releaseLease(String accountId, String holderUid, String runId) =>
      _api.delete(
        '$_base/leases/${Uri.encodeComponent(accountId)}'
        '?runId=${Uri.encodeQueryComponent(runId)}',
      );

  @override
  Future<void> addAudit(Map<String, dynamic> event) =>
      _api.post('$_base/audit', body: {'event': event});

  static Map<String, Map<String, dynamic>> _documents(Object? value) {
    if (value is! Map) return {};
    return {
      for (final entry in value.entries)
        if (entry.value is Map)
          entry.key.toString(): Map<String, dynamic>.from(entry.value as Map),
    };
  }
}
