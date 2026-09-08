import 'dart:convert';

import 'package:app_management_center/app/models/flowfin_models.dart';
import 'package:app_management_center/app/models/flowfin_settings.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/flowfin_api_client.dart';
import 'package:app_management_center/app/services/flowfin_credential_store_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _InMemorySecureStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

class _RecordedRequest {
  _RecordedRequest(this.method, this.url, this.headers, this.body);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;

  Map<String, Object?> get jsonBody =>
      jsonDecode(body) as Map<String, Object?>;
}

/// Replays queued responses and records what was sent.
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._responses);

  final List<http.Response> _responses;
  final requests = <_RecordedRequest>[];
  var _index = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    requests.add(
      _RecordedRequest(request.method, request.url, request.headers, body),
    );

    if (_index >= _responses.length) {
      throw StateError('No queued response for ${request.method} ${request.url}');
    }
    final response = _responses[_index++];
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

http.Response _json(Object? body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Map<String, Object?> _sessionPayload({
  String accessToken = 'access-1',
  String refreshToken = 'refresh-1',
  Duration accessTtl = const Duration(minutes: 15),
  Duration refreshTtl = const Duration(days: 60),
}) {
  final now = DateTime.utc(2026, 9, 7, 12);
  return {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'accessTokenExpiresAt': now.add(accessTtl).toIso8601String(),
    'refreshTokenExpiresAt': now.add(refreshTtl).toIso8601String(),
    'user': {'id': 'u1', 'email': 'someone@example.com'},
  };
}

void main() {
  late _InMemorySecureStore secureStore;
  late FlowFinCredentialStoreService credentials;
  final fixedNow = DateTime.utc(2026, 9, 7, 12);

  FlowFinApiClient buildClient(
    List<http.Response> responses, {
    FlowFinEnvironment environment = FlowFinEnvironment.staging,
    DateTime? now,
  }) {
    final client = FlowFinApiClient(
      credentialStore: credentials,
      httpClient: _FakeHttpClient(responses),
      now: () => now ?? fixedNow,
    );
    client.settings = FlowFinSettings(environment: environment);
    return client;
  }

  setUp(() {
    secureStore = _InMemorySecureStore();
    credentials = FlowFinCredentialStoreService(secureStore: secureStore);
  });

  group('money contract', () {
    test('parses amountMinor from the wire string', () {
      expect(parseMinor('150000'), 150000);
      expect(parseMinor('-42'), -42);
      expect(parseMinor(150000), 150000);
    });

    test('rejects anything that is not an integer string', () {
      expect(() => parseMinor('150000.5'), throwsFormatException);
      expect(() => parseMinor(1500.5), throwsFormatException);
      expect(() => parseMinor(null), throwsFormatException);
    });

    test('formatMinor round-trips through parseMinor', () {
      for (final value in [0, 1, -1, 150000, 9007199254740991]) {
        expect(parseMinor(formatMinor(value)), value);
      }
    });
  });

  group('settings defaults', () {
    test('a fresh install points at production', () {
      expect(
        const FlowFinSettings().environment,
        FlowFinEnvironment.production,
      );
      expect(
        const FlowFinSettings().baseUrl,
        'https://qlct-api.huynhphuocdat2.workers.dev/v1',
      );
    });

    test('unreadable stored settings fall back to the same default', () {
      expect(
        FlowFinSettings.fromJson(const {}).environment,
        FlowFinEnvironmentMeta.defaultEnvironment,
      );
      expect(
        FlowFinSettings.fromJson(const {'environment': 'nonsense'}).environment,
        FlowFinEnvironmentMeta.defaultEnvironment,
      );
    });

    test('an explicitly stored environment still round-trips', () {
      for (final environment in FlowFinEnvironment.values) {
        final restored = FlowFinSettings.fromJson(
          FlowFinSettings(environment: environment).toJson(),
        );
        expect(restored.environment, environment);
      }
    });
  });

  group('login', () {
    test('stores the session in the secure store, namespaced per environment',
        () async {
      final client = buildClient([_json(_sessionPayload())]);

      final session = await client.login(email: 'a@b.c', password: 'secret');

      expect(session.accessToken, 'access-1');
      expect(secureStore.values.keys, contains('flowfin.session.staging'));
      expect(secureStore.values.keys, isNot(contains('flowfin.session.production')));
    });

    test('surfaces the API error envelope', () async {
      final client = buildClient([
        _json({
          'error': {
            'code': 'invalid_credentials',
            'message': 'Email hoặc mật khẩu không đúng',
            'requestId': 'req-9',
          },
        }, status: 401),
      ]);

      await expectLater(
        client.login(email: 'a@b.c', password: 'nope'),
        throwsA(
          isA<FlowFinApiException>()
              .having((e) => e.code, 'code', 'invalid_credentials')
              .having((e) => e.requestId, 'requestId', 'req-9')
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('reports validation details', () async {
      final client = buildClient([
        _json({
          'error': {
            'code': 'validation_failed',
            'message': 'Dữ liệu không hợp lệ',
            'details': [
              {'path': 'amountMinor', 'message': 'Số tiền phải là chuỗi số nguyên'},
            ],
          },
        }, status: 422),
      ]);

      try {
        await client.login(email: 'bad', password: '');
        fail('expected FlowFinApiException');
      } on FlowFinApiException catch (error) {
        expect(error.isValidationFailure, isTrue);
        expect(error.details.single.path, 'amountMinor');
        expect(error.toString(), contains('Số tiền phải là chuỗi số nguyên'));
      }
    });
  });

  group('token refresh', () {
    test('refreshes once on 401 and replays the request', () async {
      final client = buildClient([
        _json(_sessionPayload()),
        _json({
          'error': {'code': 'unauthorized', 'message': 'Token hết hạn'},
        }, status: 401),
        _json(_sessionPayload(accessToken: 'access-2', refreshToken: 'refresh-2')),
        _json({'user': {'id': 'u1', 'email': 'a@b.c'}, 'cursor': 'c1'}),
      ]);
      await client.login(email: 'a@b.c', password: 'secret');

      final bootstrap = await client.bootstrap();

      expect(bootstrap.cursor, 'c1');
      expect(client.session?.accessToken, 'access-2');
    });

    test('refreshes proactively when the access token is near expiry', () async {
      final client = buildClient(
        [
          _json(_sessionPayload(accessTtl: const Duration(seconds: 5))),
          _json(_sessionPayload(accessToken: 'access-2')),
          _json({'user': {'id': 'u1', 'email': 'a@b.c'}, 'cursor': 'c2'}),
        ],
      );
      await client.login(email: 'a@b.c', password: 'secret');

      await client.bootstrap();

      expect(client.session?.accessToken, 'access-2');
    });

    test('gives up and clears the session when the refresh token is rejected',
        () async {
      final client = buildClient([
        _json(_sessionPayload()),
        _json({
          'error': {'code': 'unauthorized', 'message': 'Token hết hạn'},
        }, status: 401),
        _json({
          'error': {'code': 'unauthorized', 'message': 'Refresh token không hợp lệ'},
        }, status: 401),
      ]);
      await client.login(email: 'a@b.c', password: 'secret');

      await expectLater(
        client.bootstrap(),
        throwsA(isA<FlowFinAuthRequiredException>()),
      );
      expect(client.isSignedIn, isFalse);
      expect(secureStore.values.containsKey('flowfin.session.staging'), isFalse);
    });

    test('does not retry a rate-limited request', () async {
      final client = buildClient([
        _json(_sessionPayload()),
        _json({
          'error': {'code': 'rate_limited', 'message': 'Quá nhiều yêu cầu'},
        }, status: 429),
      ]);
      await client.login(email: 'a@b.c', password: 'secret');

      await expectLater(
        client.bootstrap(),
        throwsA(
          isA<FlowFinApiException>().having((e) => e.isRateLimited, 'isRateLimited', isTrue),
        ),
      );
    });
  });

  group('session restore', () {
    test('rejects a stored session whose refresh token has expired', () async {
      await credentials.saveSession(
        FlowFinEnvironment.staging,
        FlowFinSession.fromJson(
          _sessionPayload(refreshTtl: const Duration(days: -1)),
        ),
      );
      final client = buildClient([]);

      expect(await client.restoreSession(), isNull);
      expect(client.isSignedIn, isFalse);
    });

    test('restores a still-valid stored session', () async {
      await credentials.saveSession(
        FlowFinEnvironment.staging,
        FlowFinSession.fromJson(_sessionPayload()),
      );
      final client = buildClient([]);

      final restored = await client.restoreSession();

      expect(restored?.accessToken, 'access-1');
    });
  });

  group('requests', () {
    test('signs requests with the bearer token and hits the configured base URL',
        () async {
      final fake = _FakeHttpClient([
        _json(_sessionPayload()),
        _json({'user': {'id': 'u1', 'email': 'a@b.c'}, 'cursor': 'c1'}),
      ]);
      final client = FlowFinApiClient(
        credentialStore: credentials,
        httpClient: fake,
        now: () => fixedNow,
      )..settings = const FlowFinSettings(environment: FlowFinEnvironment.staging);

      await client.login(email: 'a@b.c', password: 'secret');
      await client.bootstrap();

      final bootstrapRequest = fake.requests.last;
      expect(
        bootstrapRequest.url.toString(),
        'https://qlct-api-staging.huynhphuocdat2.workers.dev/v1/bootstrap',
      );
      expect(bootstrapRequest.headers['authorization'], 'Bearer access-1');
    });

    test('creates transactions with a client id and clientMutationId', () async {
      final fake = _FakeHttpClient([
        _json(_sessionPayload()),
        _json({
          'id': 't1',
          'type': 'expense',
          'amountMinor': '150000',
          'currency': 'VND',
          'walletId': 'w1',
          'localDate': '2026-09-07',
        }),
      ]);
      final client = FlowFinApiClient(
        credentialStore: credentials,
        httpClient: fake,
        now: () => fixedNow,
      )..settings = const FlowFinSettings(environment: FlowFinEnvironment.staging);
      await client.login(email: 'a@b.c', password: 'secret');

      await client.createTransaction(
        type: 'expense',
        amountMinor: 150000,
        walletId: 'w1',
        localDate: '2026-09-07',
      );

      final body = fake.requests.last.jsonBody;
      expect(body['amountMinor'], isA<String>());
      expect(body['amountMinor'], '150000');
      expect((body['id'] as String).isNotEmpty, isTrue);
      expect((body['clientMutationId'] as String).isNotEmpty, isTrue);
    });

    test('reuses the caller ids so a retry stays idempotent', () async {
      final fake = _FakeHttpClient([
        _json(_sessionPayload()),
        _json({
          'id': 'fixed-id',
          'type': 'expense',
          'amountMinor': '1',
          'currency': 'VND',
          'walletId': 'w1',
          'localDate': '2026-09-07',
        }),
      ]);
      final client = FlowFinApiClient(
        credentialStore: credentials,
        httpClient: fake,
        now: () => fixedNow,
      )..settings = const FlowFinSettings(environment: FlowFinEnvironment.staging);
      await client.login(email: 'a@b.c', password: 'secret');

      await client.createTransaction(
        type: 'expense',
        amountMinor: 1,
        walletId: 'w1',
        localDate: '2026-09-07',
        id: 'fixed-id',
        clientMutationId: 'fixed-mutation',
      );

      final body = fake.requests.last.jsonBody;
      expect(body['id'], 'fixed-id');
      expect(body['clientMutationId'], 'fixed-mutation');
    });

    test('health strips the /v1 suffix', () async {
      final fake = _FakeHttpClient([
        _json({'ok': true, 'environment': 'staging'}),
      ]);
      final client = FlowFinApiClient(
        credentialStore: credentials,
        httpClient: fake,
        now: () => fixedNow,
      )..settings = const FlowFinSettings(environment: FlowFinEnvironment.staging);

      final body = await client.health();

      expect(body['ok'], isTrue);
      expect(
        fake.requests.single.url.toString(),
        'https://qlct-api-staging.huynhphuocdat2.workers.dev/health',
      );
    });

    test('logout clears the stored session even if the server call fails',
        () async {
      final client = buildClient([
        _json(_sessionPayload()),
        _json({
          'error': {'code': 'internal_error', 'message': 'Lỗi hệ thống'},
        }, status: 500),
      ]);
      await client.login(email: 'a@b.c', password: 'secret');

      await client.logout();

      expect(client.isSignedIn, isFalse);
      expect(secureStore.values.containsKey('flowfin.session.staging'), isFalse);
    });
  });
}
