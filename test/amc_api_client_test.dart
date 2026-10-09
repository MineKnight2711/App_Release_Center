import 'dart:convert';

import 'package:app_management_center/app/data/amc_api_client.dart';
import 'package:app_management_center/app/models/auth_models.dart';
import 'package:app_management_center/app/services/auth_service.dart';
import 'package:app_management_center/app/services/auth_token_store_service.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('derives the password key exactly like PBKDF2-HMAC-SHA256', () async {
    // Reference: hashlib.pbkdf2_hmac('sha256', b'secret123',
    //   b'amc-auth-v1:dev@example.com', 1000), base64url without padding.
    final key = await derivePasswordKey(
      email: ' Dev@Example.com ',
      password: 'secret123',
      iterations: 1000,
    );
    expect(key, 'oE1MVf3apk9AqolRwZ3usjUJMPI3rvwW4RDA6akWJuE');
  });

  test('sends bearer token and JSON to the versioned API path', () async {
    late http.Request captured;
    final api = AmcApiClient(
      baseUrl: Uri.parse('https://api.example.com/base'),
      readToken: () async => 'amc_token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"ok":true}', 200);
      }),
    );

    final body = await api.put(
      '/teams/t1/api-tools/requests',
      body: {'items': []},
    );

    expect(body, {'ok': true});
    expect(captured.method, 'PUT');
    expect(
      captured.url.toString(),
      'https://api.example.com/base/v1/teams/t1/api-tools/requests',
    );
    expect(captured.headers['Authorization'], 'Bearer amc_token');
    expect(jsonDecode(captured.body), {'items': []});
  });

  test('maps server errors and reports rejected sessions', () async {
    var rejected = 0;
    final api = AmcApiClient(
      baseUrl: Uri.parse('https://api.example.com'),
      readToken: () async => 'amc_token',
      httpClient: MockClient(
        (_) async => http.Response(
          '{"error":{"code":"session-expired","message":"Your session expired."}}',
          401,
        ),
      ),
    )..onUnauthorized = () => rejected++;

    await expectLater(
      api.get('/me'),
      throwsA(
        isA<AmcApiException>()
            .having((e) => e.code, 'code', 'session-expired')
            .having(
              (e) => e.message,
              'message',
              'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.',
            ),
      ),
    );
    expect(rejected, 1);
  });

  test('login failures do not count as rejected sessions', () async {
    var rejected = 0;
    final api = AmcApiClient(
      baseUrl: Uri.parse('https://api.example.com'),
      readToken: () async => 'amc_old',
      httpClient: MockClient((request) async {
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response(
          '{"error":{"code":"invalid-credential","message":"Email or password is not correct."}}',
          401,
        );
      }),
    )..onUnauthorized = () => rejected++;

    await expectLater(
      api.post('/auth/login', authenticated: false, body: const {}),
      throwsA(isA<AmcApiException>()),
    );
    expect(rejected, 0);
  });

  test(
    'AmcAuthBackend stores the session token and restores the user',
    () async {
      final secureStore = _MemorySecureStore();
      final tokenStore = AuthTokenStoreService(secureStore: secureStore);
      final requests = <http.Request>[];
      final api = AmcApiClient(
        baseUrl: Uri.parse('https://api.example.com'),
        readToken: tokenStore.readToken,
        httpClient: MockClient((request) async {
          requests.add(request);
          return switch (request.url.path) {
            '/v1/auth/login' => http.Response(
              jsonEncode({
                'token': 'amc_new',
                'expiresAt': '2026-11-08T00:00:00.000Z',
                'user': {
                  'uid': 'uid-1',
                  'email': 'dev@example.com',
                  'displayName': 'Dev',
                },
              }),
              200,
            ),
            '/v1/me' => http.Response(
              jsonEncode({
                'user': {
                  'uid': 'uid-1',
                  'email': 'dev@example.com',
                  'displayName': 'Dev',
                },
                'membership': null,
              }),
              200,
            ),
            '/v1/auth/logout' => http.Response('', 204),
            _ => http.Response('', 404),
          };
        }),
      );
      final backend = AmcAuthBackend(
        api: api,
        tokenStore: tokenStore,
        deriveKey: ({required email, required password}) async => 'k' * 43,
      );

      final user = await backend.signIn(
        email: 'dev@example.com',
        password: 'secret123',
      );
      expect(user.uid, 'uid-1');
      expect(jsonDecode(requests.single.body), {
        'email': 'dev@example.com',
        'passwordKey': 'k' * 43,
      });
      expect(secureStore.values['auth.session_token'], 'amc_new');

      final restored = AmcAuthBackend(
        api: api,
        tokenStore: AuthTokenStoreService(secureStore: secureStore),
      );
      await restored.restore();
      expect(restored.currentUser?.email, 'dev@example.com');
      expect(requests.last.headers['Authorization'], 'Bearer amc_new');

      await backend.signOut();
      expect(requests.last.url.path, '/v1/auth/logout');
      expect(secureStore.values.containsKey('auth.session_token'), isFalse);
      expect(backend.currentUser, isNull);
    },
  );

  test('AmcAuthBackend drops a token the server no longer accepts', () async {
    final secureStore = _MemorySecureStore()
      ..values['auth.session_token'] = 'amc_revoked';
    final tokenStore = AuthTokenStoreService(secureStore: secureStore);
    final backend = AmcAuthBackend(
      api: AmcApiClient(
        baseUrl: Uri.parse('https://api.example.com'),
        readToken: tokenStore.readToken,
        httpClient: MockClient(
          (_) async =>
              http.Response('{"error":{"code":"session-expired"}}', 401),
        ),
      ),
      tokenStore: tokenStore,
    );

    await backend.restore();

    expect(backend.currentUser, isNull);
    expect(secureStore.values, isEmpty);
  });

  test(
    'AmcAuthBackend rejects short passwords before calling the server',
    () async {
      final backend = AmcAuthBackend(
        api: AmcApiClient(
          baseUrl: Uri.parse('https://api.example.com'),
          readToken: () async => null,
          httpClient: MockClient((_) async => fail('should not call server')),
        ),
        tokenStore: AuthTokenStoreService(secureStore: _MemorySecureStore()),
      );

      await expectLater(
        backend.createUser(
          email: 'dev@example.com',
          password: 'short',
          displayName: 'Dev',
        ),
        throwsA(isA<AuthServiceException>()),
      );
    },
  );

  test('AmcTeamDataSource maps team responses', () async {
    final api = AmcApiClient(
      baseUrl: Uri.parse('https://api.example.com'),
      readToken: () async => 'amc_token',
      httpClient: MockClient((request) async {
        return switch ('${request.method} ${request.url.path}') {
          'POST /v1/teams/join' => http.Response(
            jsonEncode({
              'membership': {
                'teamId': 'team-1',
                'teamName': 'Release Team',
                'role': 'dev',
                'status': 'active',
              },
            }),
            200,
          ),
          'GET /v1/teams/team-1/members' => http.Response(
            jsonEncode({
              'members': [
                {
                  'uid': 'uid-1',
                  'email': 'admin@example.com',
                  'displayName': 'Admin',
                  'role': 'admin',
                  'status': 'active',
                  'joinedAt': '2026-10-01T00:00:00.000Z',
                },
              ],
            }),
            200,
          ),
          _ => http.Response('', 404),
        };
      }),
    );
    final teams = AmcTeamDataSource(api);

    final membership = await teams.joinTeamWithInvite('team-1:ABC');
    expect(membership.teamName, 'Release Team');
    expect(membership.role, TeamRole.dev);

    final members = await teams.listMembers('team-1');
    expect(members.single.role, TeamRole.admin);
    expect(members.single.joinedAt?.toUtc(), DateTime.utc(2026, 10, 1));
  });
}

class _MemorySecureStore implements SecureKeyValueStore {
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
