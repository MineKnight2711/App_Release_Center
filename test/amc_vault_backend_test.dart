import 'dart:convert';

import 'package:app_management_center/app/data/amc_api_client.dart';
import 'package:app_management_center/app/modules/qa_desk/services/account_vault.dart';
import 'package:app_management_center/app/services/amc_vault_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('maps the vault calls to the team qa-vault routes', () async {
    final requests = <http.Request>[];
    final backend = AmcVaultBackend(
      teamId: 'team 1',
      api: AmcApiClient(
        baseUrl: Uri.parse('https://api.example.com'),
        readToken: () async => 'amc_token',
        httpClient: MockClient((request) async {
          requests.add(request);
          return switch ('${request.method} ${request.url.path}') {
            'GET /v1/teams/team%201/qa-vault/leases' => http.Response(
              jsonEncode({
                'leases': {
                  'a1': {
                    'holderUid': 'uid-1',
                    'holderName': 'Dev',
                    'machine': 'mac',
                    'runId': 'run-1',
                    'expiresAt': '2026-10-09T10:00:00.000Z',
                  },
                },
              }),
              200,
            ),
            'POST /v1/teams/team%201/qa-vault/leases/a1' => http.Response(
              '{"acquired":false}',
              200,
            ),
            'GET /v1/teams/team%201/qa-vault/meta' => http.Response(
              '{"meta":null}',
              200,
            ),
            _ => http.Response('', 204),
          };
        }),
      ),
    );

    expect(await backend.readMeta(), isNull);

    final leases = await backend.listLeases();
    expect(leases['a1']?.holderUid, 'uid-1');
    expect(leases['a1']?.expiresAt, DateTime.utc(2026, 10, 9, 10));

    final acquired = await backend.tryLease(
      AccountLease(
        accountId: 'a1',
        holderUid: 'uid-2',
        holderName: 'QA',
        machine: 'win',
        runId: 'run-2',
        expiresAt: DateTime.utc(2026, 10, 9, 11),
      ),
      DateTime.utc(2026, 10, 9, 9),
    );
    expect(acquired, isFalse);
    expect(jsonDecode(requests.last.body), containsPair('runId', 'run-2'));

    await backend.releaseLease('a1', 'uid-2', 'run 2&x');
    expect(requests.last.method, 'DELETE');
    expect(requests.last.url.path, '/v1/teams/team%201/qa-vault/leases/a1');
    expect(requests.last.url.queryParameters, {'runId': 'run 2&x'});
  });
}
