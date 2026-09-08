import 'dart:convert';

import 'package:app_management_center/app/controllers/flowfin_controller.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/flowfin_api_client.dart';
import 'package:app_management_center/app/services/flowfin_credential_store_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:app_management_center/app/services/theme_service.dart';
import 'package:app_management_center/app/views/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecureStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async => values.remove(key);
}

class _Sent {
  _Sent(this.method, this.url, this.body);

  final String method;
  final Uri url;
  final String body;

  Map<String, Object?> get json => jsonDecode(body) as Map<String, Object?>;
}

/// Answers by route rather than by call order, so a test does not break when a
/// tab happens to issue one extra request.
class _RoutedHttpClient extends http.BaseClient {
  _RoutedHttpClient(this.routes);

  /// Keyed by `METHOD <path fragment>`, matched in insertion order.
  final Map<String, Object?> routes;
  final sent = <_Sent>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    sent.add(_Sent(request.method, request.url, body));

    for (final entry in routes.entries) {
      final parts = entry.key.split(' ');
      if (parts.first != request.method) continue;
      if (!request.url.path.contains(parts[1])) continue;
      return _respond(request, entry.value);
    }
    return _respond(request, const <String, Object?>{});
  }

  http.StreamedResponse _respond(http.BaseRequest request, Object? payload) {
    final bytes = utf8.encode(jsonEncode(payload));
    return http.StreamedResponse(Stream.value(bytes), 200, request: request);
  }
}

Map<String, Object?> _session() {
  final now = DateTime.now().toUtc();
  return {
    'accessToken': 'access-1',
    'refreshToken': 'refresh-1',
    'accessTokenExpiresAt': now.add(const Duration(minutes: 15)).toIso8601String(),
    'refreshTokenExpiresAt': now.add(const Duration(days: 60)).toIso8601String(),
    'user': {'id': 'u1', 'email': 'dat@flowfin.app'},
  };
}

final _wallets = [
  {
    'id': 'w1',
    'name': 'Tiền mặt',
    'type': 'cash',
    'currency': 'VND',
    'initialBalanceMinor': '0',
    'version': 2,
    'sortOrder': 0,
  },
  {
    'id': 'w2',
    'name': 'Vietcombank',
    'type': 'bank',
    'currency': 'VND',
    'initialBalanceMinor': '0',
    'version': 1,
    'sortOrder': 1,
  },
];

final _categories = [
  {'id': 'c1', 'name': 'Ăn uống', 'kind': 'expense', 'version': 1},
  {'id': 'c2', 'name': 'Lương', 'kind': 'income', 'version': 1},
];

Map<String, Object?> _bootstrap() => {
  'user': {'id': 'u1', 'email': 'dat@flowfin.app'},
  'wallets': _wallets,
  'categories': _categories,
  'budgets': const [],
  'latestInsight': null,
  'cursor': 'c1',
};

Map<String, Object?> _overview() => {
  'from': '2026-09-01',
  'to': '2026-09-08',
  'totalBalanceMinor': '1250000',
  'incomeMinor': '3000000',
  'expenseMinor': '1750000',
  'netMinor': '1250000',
  'walletBalances': const [],
  'estimated': false,
  'missingCheckInWalletIds': <String>[],
};

Map<String, Object?> _transactions() => {
  'items': [
    {
      'id': 't1',
      'type': 'expense',
      'amountMinor': '150000',
      'currency': 'VND',
      'walletId': 'w1',
      'categoryId': 'c1',
      'localDate': '2026-09-07',
      'note': 'Cà phê',
      'version': 3,
    },
  ],
  'nextCursor': null,
  'totals': {'incomeMinor': '3000000', 'expenseMinor': '1750000'},
};

late _RoutedHttpClient client;

Future<void> _openDialog(
  WidgetTester tester, {
  Map<String, Object?>? extraRoutes,
}) async {
  final store = await ProjectStoreService().init();
  final credentials = FlowFinCredentialStoreService(
    secureStore: _MemorySecureStore(),
  );
  client = _RoutedHttpClient({
    'POST /auth/login': _session(),
    'GET /bootstrap': _bootstrap(),
    'GET /stats/overview': _overview(),
    'GET /transactions': _transactions(),
    'GET /wallets': {'items': _wallets},
    'GET /categories': {'items': _categories},
    'GET /budgets': {'items': <Object?>[]},
    ...?extraRoutes,
  });
  final api = FlowFinApiClient(
    credentialStore: credentials,
    httpClient: client,
  );
  Get.put<ProjectStoreService>(store);
  Get.put<FlowFinApiClient>(api);
  Get.put<FlowFinController>(FlowFinController(client: api, store: store));

  await tester.pumpWidget(
    GetMaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFlowFinDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('flowfin-email')), 'a@b.c');
  await tester.enterText(find.byKey(const Key('flowfin-password')), 'secret');
  await tester.tap(find.byKey(const Key('flowfin-sign-in')));
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(Key('flowfin-tab-$name')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1600, 1000);
    view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    await Get.putAsync<ThemeService>(() => ThemeService().init());
  });

  tearDown(Get.reset);

  testWidgets('signing in reveals the full workspace, not just a dashboard',
      (tester) async {
    await _openDialog(tester);

    for (final tab in [
      'overview',
      'transactions',
      'accounts',
      'budgets',
      'statistics',
      'reconcile',
      'imports',
      'settings',
    ]) {
      expect(
        find.byKey(Key('flowfin-tab-$tab')),
        findsOneWidget,
        reason: 'missing the $tab tab',
      );
    }
  });

  testWidgets('a tab loads its data only when first opened', (tester) async {
    await _openDialog(tester);

    expect(
      client.sent.any((s) => s.url.path.endsWith('/transactions')),
      isFalse,
      reason: 'transactions must not load until the tab is visited',
    );

    await _openTab(tester, 'transactions');

    expect(client.sent.any((s) => s.url.path.endsWith('/transactions')), isTrue);
    expect(find.text('Cà phê'), findsNothing);
    expect(find.textContaining('Cà phê'), findsOneWidget);
  });

  testWidgets('the composer refuses a transfer without a destination wallet',
      (tester) async {
    await _openDialog(tester);
    await _openTab(tester, 'transactions');

    await tester.tap(find.byKey(const Key('flowfin-transaction-new')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('flowfin-composer-amount')),
      '50000',
    );
    await tester.tap(find.byKey(const Key('flowfin-composer-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('flowfin-composer-save')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('needs a destination wallet'),
      findsOneWidget,
    );
    // Nothing was sent — the rule is checked before spending a request.
    expect(client.sent.any((s) => s.method == 'POST' && s.url.path.endsWith('/transactions')), isFalse);
  });

  testWidgets('creating an expense posts money as a string', (tester) async {
    await _openDialog(tester, extraRoutes: {
      'POST /transactions': {
        'transaction': {
          'id': 't9',
          'type': 'expense',
          'amountMinor': '50000',
          'currency': 'VND',
          'walletId': 'w1',
          'localDate': '2026-09-08',
        },
      },
    });
    await _openTab(tester, 'transactions');

    await tester.tap(find.byKey(const Key('flowfin-transaction-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('flowfin-composer-amount')),
      '50000',
    );
    await tester.tap(find.byKey(const Key('flowfin-composer-save')));
    await tester.pumpAndSettle();

    final posted = client.sent.lastWhere(
      (s) => s.method == 'POST' && s.url.path.endsWith('/transactions'),
    );
    expect(posted.json['amountMinor'], '50000');
    expect(posted.json['type'], 'expense');
    expect(posted.json['walletId'], 'w1');
    expect((posted.json['clientMutationId'] as String).length, greaterThanOrEqualTo(8));
  });

  testWidgets('deleting a transaction asks first', (tester) async {
    await _openDialog(tester);
    await _openTab(tester, 'transactions');

    await tester.tap(find.byKey(const Key('flowfin-transaction-delete-t1')));
    await tester.pumpAndSettle();

    expect(find.text('Delete transaction?'), findsOneWidget);
    expect(
      client.sent.any((s) => s.method == 'DELETE'),
      isFalse,
      reason: 'nothing may be deleted before the prompt is confirmed',
    );
  });

  testWidgets('the accounts tab manages wallets and categories together',
      (tester) async {
    await _openDialog(tester);
    await _openTab(tester, 'accounts');

    expect(find.text('Tiền mặt'), findsOneWidget);
    expect(find.text('Vietcombank'), findsOneWidget);
    expect(find.text('Ăn uống'), findsOneWidget);
    expect(find.byKey(const Key('flowfin-wallet-new')), findsOneWidget);
    expect(find.byKey(const Key('flowfin-category-new')), findsOneWidget);
  });

  testWidgets('reconcile says nothing was posted when a wallet is unchecked',
      (tester) async {
    await _openDialog(tester, extraRoutes: {'GET /reconciliation': {'items': <Object?>[]}});
    await _openTab(tester, 'reconcile');

    expect(find.textContaining('No check-in recorded'), findsWidgets);
    expect(find.byKey(const Key('flowfin-checkin-w1')), findsOneWidget);
  });

  testWidgets('imports untick rows the parser flagged as duplicates',
      (tester) async {
    await _openDialog(tester, extraRoutes: {
      'GET /imports': {'items': <Object?>[]},
      'POST /imports': {
        'batch': {
          'id': 'b1',
          'source': 'momo',
          'status': 'ready',
          'itemCount': 2,
          'items': [
            {
              'id': 'i1',
              'batchId': 'b1',
              'amountMinor': '25000',
              'localDate': '2026-09-08',
              'merchant': 'Highlands',
              'direction': 'out',
            },
            {
              'id': 'i2',
              'batchId': 'b1',
              'amountMinor': '25000',
              'localDate': '2026-09-08',
              'merchant': 'Highlands',
              'direction': 'out',
              'duplicateOf': 't1',
            },
          ],
        },
      },
    });
    await _openTab(tester, 'imports');

    await tester.enterText(
      find.byKey(const Key('flowfin-import-text')),
      'Highlands 25.000d',
    );
    await tester.tap(find.byKey(const Key('flowfin-import-parse')));
    await tester.pumpAndSettle();

    final fresh = tester.widget<Checkbox>(
      find.byKey(const Key('flowfin-import-item-i1')),
    );
    final duplicate = tester.widget<Checkbox>(
      find.byKey(const Key('flowfin-import-item-i2')),
    );
    expect(fresh.value, isTrue);
    expect(duplicate.value, isFalse);
  });
}
