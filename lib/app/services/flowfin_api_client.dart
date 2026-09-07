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
  const FlowFinAuthRequiredException([this.message = 'Sign in to FlowFin first.']);

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

  Future<FlowFinStatsOverview> statsOverview({
    required String from,
    required String to,
  }) async {
    final body = await _send(
      'GET',
      '/stats/overview',
      query: {'from': from, 'to': to},
    );
    return FlowFinStatsOverview.fromJson(body);
  }

  Future<FlowFinTransactionPage> listTransactions({
    String? walletId,
    String? categoryId,
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
        if (categoryId != null && categoryId.isNotEmpty) 'categoryId': categoryId,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': '$limit',
      },
    );
    return FlowFinTransactionPage.fromJson(body);
  }

  Future<List<FlowFinWallet>> listWallets({bool includeArchived = false}) async {
    final body = await _send(
      'GET',
      '/wallets',
      query: {if (includeArchived) 'includeArchived': 'true'},
    );
    final items = body['items'] ?? body['wallets'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((entry) => FlowFinWallet.fromJson(entry.cast<String, Object?>()))
        .toList(growable: false);
  }

  /// Creates a transaction. [id] and [clientMutationId] default to fresh UUIDs;
  /// pass the same pair again to retry safely after a timeout.
  Future<FlowFinTransaction> createTransaction({
    required String type,
    required int amountMinor,
    required String walletId,
    required String localDate,
    String? categoryId,
    String? toWalletId,
    String note = '',
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
        if (categoryId != null && categoryId.isNotEmpty) 'categoryId': categoryId,
        if (toWalletId != null && toWalletId.isNotEmpty) 'toWalletId': toWalletId,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return FlowFinTransaction.fromJson(body);
  }

  Future<void> deleteTransaction({
    required String id,
    String? clientMutationId,
  }) async {
    await _send(
      'DELETE',
      '/transactions/$id',
      query: {'clientMutationId': clientMutationId ?? newId()},
    );
  }

  // --------------------------------------------------------------- plumbing

  Future<FlowFinSession> _adoptSession(Map<String, Object?> body) async {
    final session = FlowFinSession.fromJson(body);
    if (session.accessToken.isEmpty || session.refreshToken.isEmpty) {
      throw const FlowFinApiException(
        statusCode: 500,
        code: 'invalid_session',
        message: 'FlowFin returned a session without tokens.',
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
  }) async {
    final token = await _validAccessToken();

    try {
      return await _rawSend(
        method,
        path,
        query: query,
        body: body,
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
    String? accessToken,
  }) async {
    final uri = Uri.parse('${settings.baseUrl}$path').replace(
      queryParameters: query.isEmpty ? null : query,
    );

    final request = http.Request(method, uri);
    request.headers['accept'] = 'application/json';
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
        message: 'FlowFin returned a response that is not JSON.',
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
          message: (error['message'] as String?) ?? 'FlowFin request failed.',
          requestId: (error['requestId'] as String?) ?? '',
          details: _parseDetails(error['details']),
        );
      }
    }

    return FlowFinApiException(
      statusCode: response.statusCode,
      code: 'http_${response.statusCode}',
      message: 'FlowFin request failed with HTTP ${response.statusCode}.',
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
