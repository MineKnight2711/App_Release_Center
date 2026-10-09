import 'dart:async';
import 'dart:convert';

import 'package:app_management_center/app/models/flowfin_models.dart';
import 'package:app_management_center/app/models/flowfin_settings.dart';
import 'package:app_management_center/app/services/flowfin_credential_store_service.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

const defaultFlowFinRequestTimeout = Duration(seconds: 30);

class FlowFinErrorDetail {
  const FlowFinErrorDetail({required this.path, required this.message});

  final String path;
  final String message;

  @override
  String toString() => '$path: $message';
}

/// The API's error envelope: `{"error":{"code","message","details","requestId"}}`.
class FlowFinApiException implements Exception {
  const FlowFinApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.requestId = '',
    this.details = const [],
  });

  final int statusCode;
  final String code;
  final String message;
  final String requestId;
  final List<FlowFinErrorDetail> details;

  bool get isUnauthorized => statusCode == 401;
  bool get isRateLimited => statusCode == 429;
  bool get isVersionConflict => code == 'version_conflict';
  bool get isValidationFailure => code == 'validation_failed';

  @override
  String toString() {
    if (details.isEmpty) return message;
    return '$message (${details.join('; ')})';
  }
}

/// Raised when the module has no usable session for the active environment.
class FlowFinAuthRequiredException implements Exception {
  const FlowFinAuthRequiredException([this.message = 'Hãy đăng nhập FlowFin trước.']);

  final String message;

  @override
  String toString() => message;
}

/// Talks to the FlowFin Worker directly.
///
/// Nothing here touches App Management Center's Firebase project or its
/// notification relay — the desktop app is just another FlowFin API client.
///
/// Two FlowFin contracts are enforced on this side:
/// every mutation carries a client-generated id plus a `clientMutationId` so
/// resending is safe, and money stays an integer count of minor units.
class FlowFinApiClient extends GetxService {
  FlowFinApiClient({
    required FlowFinCredentialStoreService credentialStore,
    http.Client? httpClient,
    Uuid? uuid,
    Duration timeout = defaultFlowFinRequestTimeout,
    DateTime Function()? now,
  }) : _credentialStore = credentialStore,
       _httpClient = httpClient ?? http.Client(),
       _uuid = uuid ?? const Uuid(),
       _timeout = timeout,
       _now = now ?? (() => DateTime.now().toUtc());

  final FlowFinCredentialStoreService _credentialStore;
  final http.Client _httpClient;
  final Uuid _uuid;
  final Duration _timeout;
  final DateTime Function() _now;

  FlowFinSettings settings = const FlowFinSettings();
  FlowFinSession? _session;
  Future<FlowFinSession?>? _refreshInFlight;

  FlowFinEnvironment get environment => settings.environment;
  FlowFinSession? get session => _session;
  bool get isSignedIn => _session != null;

  String newId() => _uuid.v4();

  /// Loads the stored session for the active environment, if any.
  Future<FlowFinSession?> restoreSession() async {
    final stored = await _credentialStore.readSession(environment);
    if (stored == null || stored.isRefreshTokenExpired(now: _now())) {
      _session = null;
      return null;
    }
    _session = stored;
    return stored;
  }

  void forgetSessionInMemory() => _session = null;

  // ---------------------------------------------------------------- health

  /// `GET /health` sits outside `/v1`, so the version suffix is trimmed.
  Future<Map<String, Object?>> health({FlowFinEnvironment? target}) async {
    final env = target ?? environment;
    final base = settings.baseUrlFor(env);
    final root = base.endsWith('/v1') ? base.substring(0, base.length - 3) : base;
    final response = await _httpClient
        .get(Uri.parse('$root/health'), headers: const {'accept': 'application/json'})
        .timeout(_timeout);
    return _decodeBody(response);
  }

  // ------------------------------------------------------------------ auth

  Future<FlowFinSession> login({
    required String email,
    required String password,
  }) async {
    final body = await _sendUnauthenticated(
      'POST',
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    return _adoptSession(body);
  }

  Future<FlowFinSession> register({
    required String email,
    required String password,
    String displayName = '',
  }) async {
    final body = await _sendUnauthenticated(
      'POST',
      '/auth/register',
      body: {
        'email': email.trim(),
        'password': password,
        if (displayName.trim().isNotEmpty) 'displayName': displayName.trim(),
      },
    );
    return _adoptSession(body);
  }

  Future<void> logout({bool allDevices = false}) async {
    final current = _session;
    _session = null;
    await _credentialStore.deleteSession(environment);
    if (current == null) return;

    try {
      await _rawSend(
        'POST',
        '/auth/logout',
        accessToken: current.accessToken,
        body: {'allDevices': allDevices, 'refreshToken': current.refreshToken},
      );
    } on FlowFinApiException {
      // The local session is already gone; a failed server logout is not worth
      // surfacing as an error the user has to act on.
    } on TimeoutException {
      // Same reasoning.
    }
  }

  // ------------------------------------------------------------------ data

  Future<FlowFinBootstrap> bootstrap() async {
    return FlowFinBootstrap.fromJson(await _send('GET', '/bootstrap'));
  }

  // ----- stats

  Future<FlowFinStatsOverview> statsOverview({
    required String from,
    required String to,
  }) async {
    return FlowFinStatsOverview.fromJson(
      await _send('GET', '/stats/overview', query: {'from': from, 'to': to}),
    );
  }

  Future<FlowFinTimeline> statsTimeline({
    required String from,
    required String to,
    String bucket = 'day',
  }) async {
    return FlowFinTimeline.fromJson(
      await _send(
        'GET',
        '/stats/timeline',
        query: {'from': from, 'to': to, 'bucket': bucket},
      ),
    );
  }

  Future<FlowFinBreakdown> statsBreakdown({
    required String from,
    required String to,
    String groupBy = 'category',
    String kind = 'expense',
  }) async {
    return FlowFinBreakdown.fromJson(
      await _send(
        'GET',
        '/stats/breakdown',
        query: {'from': from, 'to': to, 'groupBy': groupBy, 'kind': kind},
      ),
    );
  }

  // ----- transactions

  Future<FlowFinTransactionPage> listTransactions({
    String? walletId,
    String? categoryId,
    String? type,
    String? query,
    String? from,
    String? to,
    String? cursor,
    int limit = 50,
  }) async {
    final body = await _send(
      'GET',
      '/transactions',
      query: {
        if (walletId != null && walletId.isNotEmpty) 'walletId': walletId,
        if (categoryId != null && categoryId.isNotEmpty)
          'categoryId': categoryId,
        if (type != null && type.isNotEmpty) 'type': type,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': '$limit',
      },
    );
    return FlowFinTransactionPage.fromJson(body);
  }

  Future<FlowFinTransaction> getTransaction(String id) async {
    final body = await _send('GET', '/transactions/$id');
    return FlowFinTransaction.fromJson(_unwrap(body, 'transaction'));
  }

  /// [id] and [clientMutationId] default to fresh UUIDs; pass the same pair
  /// again to retry safely after a timeout.
  ///
  /// The API enforces the rules this app must not fight: a transfer needs a
  /// different destination wallet and carries no category; an adjustment is
  /// non-zero and carries no category; everything else is strictly positive.
  Future<FlowFinTransaction> createTransaction({
    required String type,
    required int amountMinor,
    required String walletId,
    required String localDate,
    String? categoryId,
    String? toWalletId,
    String note = '',
    String source = 'manual',
    String? id,
    String? clientMutationId,
  }) async {
    final body = await _send(
      'POST',
      '/transactions',
      body: {
        'id': id ?? newId(),
        'clientMutationId': clientMutationId ?? newId(),
        'type': type,
        // Money crosses the wire as a string, never a JSON number.
        'amountMinor': formatMinor(amountMinor),
        'walletId': walletId,
        'localDate': localDate,
        'source': source,
        if (categoryId != null && categoryId.isNotEmpty)
          'categoryId': categoryId,
        if (toWalletId != null && toWalletId.isNotEmpty)
          'toWalletId': toWalletId,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return FlowFinTransaction.fromJson(_unwrap(body, 'transaction'));
  }

  Future<FlowFinTransaction> updateTransaction({
    required String id,
    required int baseVersion,
    int? amountMinor,
    String? walletId,
    String? categoryId,
    String? toWalletId,
    String? localDate,
    String? note,
    String? clientMutationId,
  }) async {
    final body = await _send(
      'PATCH',
      '/transactions/$id',
      body: {
        'clientMutationId': clientMutationId ?? newId(),
        'baseVersion': baseVersion,
        if (amountMinor != null) 'amountMinor': formatMinor(amountMinor),
        'walletId': ?walletId,
        if (categoryId != null) 'categoryId': categoryId.isEmpty ? null : categoryId,
        if (toWalletId != null) 'toWalletId': toWalletId.isEmpty ? null : toWalletId,
        'localDate': ?localDate,
        if (note != null) 'note': note.trim().isEmpty ? null : note.trim(),
      },
    );
    return FlowFinTransaction.fromJson(_unwrap(body, 'transaction'));
  }

  Future<void> deleteTransaction({
    required String id,
    required int baseVersion,
    String? clientMutationId,
  }) {
    return _delete('/transactions/$id', baseVersion, clientMutationId);
  }

  // ----- wallets

  Future<List<FlowFinWallet>> listWallets({bool includeArchived = false}) async {
    final body = await _send(
      'GET',
      '/wallets',
      query: {if (includeArchived) 'includeArchived': 'true'},
    );
    return _items(body, FlowFinWallet.fromJson);
  }

  Future<FlowFinWallet> createWallet({
    required String name,
    required String type,
    required int initialBalanceMinor,
    required String openedOn,
    String? color,
    String? icon,
    bool includeInTotal = true,
    int sortOrder = 0,
    String? id,
    String? clientMutationId,
  }) async {
    final body = await _send(
      'POST',
      '/wallets',
      body: {
        'id': id ?? newId(),
        'clientMutationId': clientMutationId ?? newId(),
        'name': name.trim(),
        'type': type,
        'initialBalanceMinor': formatMinor(initialBalanceMinor),
        'openedOn': openedOn,
        'includeInTotal': includeInTotal,
        'sortOrder': sortOrder,
        if (color != null && color.isNotEmpty) 'color': color,
        if (icon != null && icon.isNotEmpty) 'icon': icon,
      },
    );
    return FlowFinWallet.fromJson(_unwrap(body, 'wallet'));
  }

  Future<FlowFinWallet> updateWallet({
    required String id,
    required int baseVersion,
    String? name,
    String? type,
    String? color,
    String? icon,
    bool? includeInTotal,
    int? sortOrder,
    bool? archived,
    String? clientMutationId,
  }) async {
    final body = await _send(
      'PATCH',
      '/wallets/$id',
      body: {
        'clientMutationId': clientMutationId ?? newId(),
        'baseVersion': baseVersion,
        if (name != null) 'name': name.trim(),
        'type': ?type,
        if (color != null) 'color': color.isEmpty ? null : color,
        if (icon != null) 'icon': icon.isEmpty ? null : icon,
        'includeInTotal': ?includeInTotal,
        'sortOrder': ?sortOrder,
        'archived': ?archived,
      },
    );
    return FlowFinWallet.fromJson(_unwrap(body, 'wallet'));
  }

  Future<void> deleteWallet({
    required String id,
    required int baseVersion,
    String? clientMutationId,
  }) {
    return _delete('/wallets/$id', baseVersion, clientMutationId);
  }

  // ----- categories

  Future<List<FlowFinCategory>> listCategories({String? kind}) async {
    final body = await _send(
      'GET',
      '/categories',
      query: {if (kind != null && kind.isNotEmpty) 'kind': kind},
    );
    return _items(body, FlowFinCategory.fromJson);
  }

  Future<FlowFinCategory> createCategory({
    required String name,
    required String kind,
    String? icon,
    String? color,
    int sortOrder = 0,
    String? id,
    String? clientMutationId,
  }) async {
    final body = await _send(
      'POST',
      '/categories',
      body: {
        'id': id ?? newId(),
        'clientMutationId': clientMutationId ?? newId(),
        'name': name.trim(),
        'kind': kind,
        'sortOrder': sortOrder,
        if (icon != null && icon.isNotEmpty) 'icon': icon,
        if (color != null && color.isNotEmpty) 'color': color,
      },
    );
    return FlowFinCategory.fromJson(_unwrap(body, 'category'));
  }

  Future<FlowFinCategory> updateCategory({
    required String id,
    required int baseVersion,
    String? name,
    String? icon,
    String? color,
    int? sortOrder,
    bool? archived,
    String? clientMutationId,
  }) async {
    final body = await _send(
      'PATCH',
      '/categories/$id',
      body: {
        'clientMutationId': clientMutationId ?? newId(),
        'baseVersion': baseVersion,
        if (name != null) 'name': name.trim(),
        if (icon != null) 'icon': icon.isEmpty ? null : icon,
        if (color != null) 'color': color.isEmpty ? null : color,
        'sortOrder': ?sortOrder,
        'archived': ?archived,
      },
    );
    return FlowFinCategory.fromJson(_unwrap(body, 'category'));
  }

  Future<void> deleteCategory({
    required String id,
    required int baseVersion,
    String? clientMutationId,
  }) {
    return _delete('/categories/$id', baseVersion, clientMutationId);
  }

  // ----- budgets

  Future<List<FlowFinBudget>> listBudgets({String? periodKey}) async {
    final body = await _send(
      'GET',
      '/budgets',
      query: {if (periodKey != null && periodKey.isNotEmpty) 'periodKey': periodKey},
    );
    return _items(body, FlowFinBudget.fromJson);
  }

  Future<FlowFinBudget> createBudget({
    required String scope,
    required int limitMinor,
    String? categoryId,
    String? periodKey,
    String? id,
    String? clientMutationId,
  }) async {
    final body = await _send(
      'POST',
      '/budgets',
      body: {
        'id': id ?? newId(),
        'clientMutationId': clientMutationId ?? newId(),
        'scope': scope,
        'limitMinor': formatMinor(limitMinor),
        if (categoryId != null && categoryId.isNotEmpty)
          'categoryId': categoryId,
        if (periodKey != null && periodKey.isNotEmpty) 'periodKey': periodKey,
      },
    );
    return FlowFinBudget.fromJson(_unwrap(body, 'budget'));
  }

  Future<FlowFinBudget> updateBudget({
    required String id,
    required int baseVersion,
    required int limitMinor,
    String? clientMutationId,
  }) async {
    final body = await _send(
      'PATCH',
      '/budgets/$id',
      body: {
        'clientMutationId': clientMutationId ?? newId(),
        'baseVersion': baseVersion,
        'limitMinor': formatMinor(limitMinor),
      },
    );
    return FlowFinBudget.fromJson(_unwrap(body, 'budget'));
  }

  Future<void> deleteBudget({
    required String id,
    required int baseVersion,
    String? clientMutationId,
  }) {
    return _delete('/budgets/$id', baseVersion, clientMutationId);
  }

  // ----- check-in and reconciliation

  Future<List<FlowFinSnapshot>> listSnapshots({
    String? walletId,
    String? from,
    String? to,
  }) async {
    final body = await _send(
      'GET',
      '/balance-snapshots',
      query: {
        if (walletId != null && walletId.isNotEmpty) 'walletId': walletId,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      },
    );
    return _items(body, FlowFinSnapshot.fromJson);
  }

  /// Records a counted balance and returns how it compares with the ledger.
  /// A difference is reported, never auto-corrected.
  Future<({FlowFinSnapshot snapshot, FlowFinReconciliation? reconciliation})>
  upsertSnapshot({
    required String walletId,
    required String localDate,
    required int balanceMinor,
    String note = '',
    String? id,
    String? clientMutationId,
  }) async {
    final body = await _send(
      'PUT',
      '/balance-snapshots',
      body: {
        'id': id ?? newId(),
        'clientMutationId': clientMutationId ?? newId(),
        'walletId': walletId,
        'localDate': localDate,
        'balanceMinor': formatMinor(balanceMinor),
        if (note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    final rawReconciliation = body['reconciliation'];
    return (
      snapshot: FlowFinSnapshot.fromJson(_unwrap(body, 'snapshot')),
      reconciliation: rawReconciliation is Map
          ? FlowFinReconciliation.fromJson(
              rawReconciliation.cast<String, Object?>(),
            )
          : null,
    );
  }

  Future<void> deleteSnapshot({
    required String id,
    required int baseVersion,
    String? clientMutationId,
  }) {
    return _delete('/balance-snapshots/$id', baseVersion, clientMutationId);
  }

  Future<List<FlowFinReconciliation>> reconciliation({
    required String date,
    String? walletId,
  }) async {
    final body = await _send(
      'GET',
      '/reconciliation',
      query: {
        'date': date,
        if (walletId != null && walletId.isNotEmpty) 'walletId': walletId,
      },
    );
    return _items(body, FlowFinReconciliation.fromJson);
  }

  // ----- insights

  Future<List<FlowFinInsight>> listInsights({
    String? type,
    String? periodKey,
    int limit = 20,
  }) async {
    final body = await _send(
      'GET',
      '/insights',
      query: {
        if (type != null && type.isNotEmpty) 'type': type,
        if (periodKey != null && periodKey.isNotEmpty) 'periodKey': periodKey,
        'limit': '$limit',
      },
    );
    return _items(body, FlowFinInsight.fromJson);
  }

  Future<FlowFinInsight?> latestInsight() async {
    final body = await _send('GET', '/insights/latest');
    final raw = body['insight'];
    if (raw is! Map) return null;
    return FlowFinInsight.fromJson(raw.cast<String, Object?>());
  }

  /// Queues a fresh insight. AI is best-effort: a failure here must never stop
  /// the rest of the module from working.
  Future<Map<String, Object?>> refreshInsight({
    required String insightType,
    String? periodKey,
  }) {
    return _send(
      'POST',
      '/insights/refresh',
      body: {
        'insightType': insightType,
        if (periodKey != null && periodKey.isNotEmpty) 'periodKey': periodKey,
      },
    );
  }

  // ----- imports

  /// Desktop has no camera, so batches are created from pasted text — a MoMo
  /// notification or a receipt transcription — which is what the API takes.
  Future<FlowFinImportBatch> createImport({
    required String source,
    required String text,
    String? defaultWalletId,
    String? id,
    String? clientMutationId,
  }) async {
    final body = await _send(
      'POST',
      '/imports',
      body: {
        'id': id ?? newId(),
        'clientMutationId': clientMutationId ?? newId(),
        'source': source,
        'text': text,
        if (defaultWalletId != null && defaultWalletId.isNotEmpty)
          'defaultWalletId': defaultWalletId,
      },
    );
    return FlowFinImportBatch.fromJson(_unwrap(body, 'batch'));
  }

  Future<List<FlowFinImportBatch>> listImports({int limit = 20}) async {
    final body = await _send('GET', '/imports', query: {'limit': '$limit'});
    return _items(body, FlowFinImportBatch.fromJson);
  }

  Future<FlowFinImportBatch> getImport(String id) async {
    final body = await _send('GET', '/imports/$id');
    return FlowFinImportBatch.fromJson(_unwrap(body, 'batch'));
  }

  Future<FlowFinImportItem> updateImportItem({
    required String batchId,
    required String itemId,
    required int baseVersion,
    int? amountMinor,
    String? direction,
    String? localDate,
    String? merchant,
    String? clientMutationId,
  }) async {
    final body = await _send(
      'PATCH',
      '/imports/$batchId/items/$itemId',
      body: {
        'clientMutationId': clientMutationId ?? newId(),
        'baseVersion': baseVersion,
        if (amountMinor != null) 'amountMinor': formatMinor(amountMinor),
        'direction': ?direction,
        'localDate': ?localDate,
        if (merchant != null) 'merchant': merchant.isEmpty ? null : merchant,
      },
    );
    return FlowFinImportItem.fromJson(_unwrap(body, 'item'));
  }

  Future<Map<String, Object?>> confirmImport({
    required String batchId,
    required List<FlowFinImportConfirmEntry> entries,
    String? clientMutationId,
  }) {
    return _send(
      'POST',
      '/imports/$batchId/confirm',
      body: {
        'clientMutationId': clientMutationId ?? newId(),
        'items': entries.map((entry) => entry.toJson()).toList(),
      },
    );
  }

  Future<void> deleteImport({
    required String id,
    required int baseVersion,
    String? clientMutationId,
  }) {
    return _delete('/imports/$id', baseVersion, clientMutationId);
  }

  // ----- account

  Future<({FlowFinUser user, FlowFinNotificationPrefs prefs})> me() async {
    final body = await _send('GET', '/me');
    return (
      user: FlowFinUser.fromJson(_unwrap(body, 'user')),
      prefs: FlowFinNotificationPrefs.fromJson(
        _unwrap(body, 'notificationPreferences'),
      ),
    );
  }

  Future<({FlowFinUser user, FlowFinNotificationPrefs prefs})> updateMe({
    String? displayName,
    String? timezone,
    String? locale,
    FlowFinNotificationPrefs? notificationPreferences,
  }) async {
    final body = await _send(
      'PATCH',
      '/me',
      body: {
        if (displayName != null) 'displayName': displayName.trim(),
        'timezone': ?timezone,
        'locale': ?locale,
        if (notificationPreferences != null)
          'notificationPreferences': notificationPreferences.toJson(),
      },
    );
    return (
      user: FlowFinUser.fromJson(_unwrap(body, 'user')),
      prefs: FlowFinNotificationPrefs.fromJson(
        _unwrap(body, 'notificationPreferences'),
      ),
    );
  }

  Future<Map<String, Object?>> exportMyData() => _send('GET', '/me/export');

  // --------------------------------------------------------------- plumbing

  /// Deletes carry the mutation id in `X-Client-Mutation-Id` rather than the
  /// body, and the API requires `baseVersion` so a stale tab cannot delete a
  /// row someone else has since changed.
  Future<void> _delete(
    String path,
    int baseVersion,
    String? clientMutationId,
  ) async {
    await _send(
      'DELETE',
      path,
      query: {'baseVersion': '$baseVersion'},
      headers: {'x-client-mutation-id': clientMutationId ?? newId()},
    );
  }

  /// Responses wrap their payload (`{"wallet": {...}, "meta": {...}}`). A bare
  /// payload is tolerated so a future unwrapped endpoint does not break here.
  Map<String, Object?> _unwrap(Map<String, Object?> body, String key) {
    final inner = body[key];
    if (inner is Map) return inner.cast<String, Object?>();
    return body;
  }

  List<T> _items<T>(
    Map<String, Object?> body,
    T Function(Map<String, Object?>) build,
  ) {
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((entry) => build(entry.cast<String, Object?>()))
        .toList(growable: false);
  }

  Future<FlowFinSession> _adoptSession(Map<String, Object?> body) async {
    final session = FlowFinSession.fromJson(body);
    if (session.accessToken.isEmpty || session.refreshToken.isEmpty) {
      throw const FlowFinApiException(
        statusCode: 500,
        code: 'invalid_session',
        message: 'FlowFin trả về phiên không có token.',
      );
    }
    _session = session;
    await _credentialStore.saveSession(environment, session);
    return session;
  }

  Future<Map<String, Object?>> _sendUnauthenticated(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) {
    return _rawSend(method, path, body: body);
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
    Map<String, String> headers = const {},
  }) async {
    final token = await _validAccessToken();

    try {
      return await _rawSend(
        method,
        path,
        query: query,
        body: body,
        headers: headers,
        accessToken: token,
      );
    } on FlowFinApiException catch (error) {
      // One retry, and only for an expired access token. A 429 is never
      // retried here — FlowFin rate-limits auth routes and a retry loop would
      // just burn the budget.
      if (!error.isUnauthorized) rethrow;

      final refreshed = await _refreshSession();
      if (refreshed == null) throw const FlowFinAuthRequiredException();

      return _rawSend(
        method,
        path,
        query: query,
        body: body,
        headers: headers,
        accessToken: refreshed.accessToken,
      );
    }
  }

  Future<String> _validAccessToken() async {
    var current = _session ?? await restoreSession();
    if (current == null) throw const FlowFinAuthRequiredException();

    if (current.isAccessTokenExpired(now: _now())) {
      final refreshed = await _refreshSession();
      if (refreshed == null) throw const FlowFinAuthRequiredException();
      current = refreshed;
    }

    return current.accessToken;
  }

  /// Refreshes at most once at a time; parallel callers await the same call.
  Future<FlowFinSession?> _refreshSession() {
    return _refreshInFlight ??= _performRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<FlowFinSession?> _performRefresh() async {
    final current = _session;
    if (current == null || current.isRefreshTokenExpired(now: _now())) {
      _session = null;
      await _credentialStore.deleteSession(environment);
      return null;
    }

    try {
      final body = await _rawSend(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': current.refreshToken},
      );
      return await _adoptSession(body);
    } on FlowFinApiException {
      _session = null;
      await _credentialStore.deleteSession(environment);
      return null;
    }
  }

  Future<Map<String, Object?>> _rawSend(
    String method,
    String path, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
    Map<String, String> headers = const {},
    String? accessToken,
  }) async {
    final uri = Uri.parse('${settings.baseUrl}$path').replace(
      queryParameters: query.isEmpty ? null : query,
    );

    final request = http.Request(method, uri);
    request.headers['accept'] = 'application/json';
    request.headers.addAll(headers);
    if (accessToken != null) {
      request.headers['authorization'] = 'Bearer $accessToken';
    }
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }

    final streamed = await _httpClient.send(request).timeout(_timeout);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decodeBody(response);
    }
    throw _toException(response);
  }

  Map<String, Object?> _decodeBody(http.Response response) {
    if (response.statusCode == 204 || response.bodyBytes.isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) return decoded.cast<String, Object?>();
      return {'data': decoded};
    } on FormatException {
      throw FlowFinApiException(
        statusCode: response.statusCode,
        code: 'invalid_response',
        message: 'FlowFin trả về nội dung không phải JSON.',
      );
    }
  }

  FlowFinApiException _toException(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      decoded = null;
    }

    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map) {
        return FlowFinApiException(
          statusCode: response.statusCode,
          code: (error['code'] as String?) ?? 'unknown',
          message: (error['message'] as String?) ?? 'Gọi FlowFin thất bại.',
          requestId: (error['requestId'] as String?) ?? '',
          details: _parseDetails(error['details']),
        );
      }
    }

    return FlowFinApiException(
      statusCode: response.statusCode,
      code: 'http_${response.statusCode}',
      message: 'Gọi FlowFin thất bại với HTTP ${response.statusCode}.',
    );
  }

  List<FlowFinErrorDetail> _parseDetails(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (entry) => FlowFinErrorDetail(
            path: (entry['path'] as String?) ?? '',
            message: (entry['message'] as String?) ?? '',
          ),
        )
        .toList(growable: false);
  }
}
