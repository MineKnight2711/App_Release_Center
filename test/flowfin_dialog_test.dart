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

class _QueuedHttpClient extends http.BaseClient {
  _QueuedHttpClient(this.responses);

  final List<http.Response> responses;
  var _index = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = _index < responses.length
        ? responses[_index++]
        : http.Response('{}', 200);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      request: request,
    );
  }
}

/// Encoded as UTF-8 bytes: `http.Response(String, ...)` falls back to latin1
/// and would reject Vietnamese text outright.
http.Response _json(Object? body, {int status = 200}) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

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

Map<String, Object?> _bootstrap({Object? insight}) {
  return {
    'user': {'id': 'u1', 'email': 'dat@flowfin.app'},
    'wallets': [
      {
        'id': 'w1',
        'name': 'Tiền mặt',
        'type': 'cash',
        'currency': 'VND',
        'initialBalanceMinor': '0',
        'sortOrder': 0,
      },
    ],
    'categories': const [],
    'budgets': const [],
    'latestInsight': insight,
    'cursor': 'c1',
  };
}

Map<String, Object?> _overview() {
  return {
    'from': '2026-09-01',
    'to': '2026-09-07',
    'totalBalanceMinor': '1250000',
    'incomeMinor': '3000000',
    'expenseMinor': '1750000',
    'netMinor': '1250000',
    'transferCount': 2,
    'walletBalances': [
      {'walletId': 'w1', 'balanceMinor': '1250000', 'estimated': false},
    ],
    'estimated': false,
    'missingCheckInWalletIds': const [],
  };
}

Future<void> _pumpDialogHost(WidgetTester tester) async {
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
}

void main() {
  setUp(() async {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1280, 720);
    view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    await Get.putAsync<ThemeService>(() => ThemeService().init());
  });

  tearDown(Get.reset);

  Future<void> registerController(List<http.Response> responses) async {
    final store = await ProjectStoreService().init();
    final credentials = FlowFinCredentialStoreService(
      secureStore: _MemorySecureStore(),
    );
    final client = FlowFinApiClient(
      credentialStore: credentials,
      httpClient: _QueuedHttpClient(responses),
    );
    Get.put<ProjectStoreService>(store);
    Get.put<FlowFinApiClient>(client);
    Get.put<FlowFinController>(
      FlowFinController(client: client, store: store),
    );
  }

  testWidgets('asks for sign-in before showing any numbers', (tester) async {
    await registerController([]);
    await _pumpDialogHost(tester);

    expect(find.text('Đăng nhập FlowFin'), findsOneWidget);
    expect(find.byKey(const Key('flowfin-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('flowfin-sign-out')), findsNothing);
  });

  testWidgets('signs in and renders the overview with FlowFin money format',
      (tester) async {
    await registerController([
      _json(_session()),
      _json(_bootstrap()),
      _json(_overview()),
    ]);
    await _pumpDialogHost(tester);

    await tester.enterText(
      find.byKey(const Key('flowfin-email')),
      'dat@flowfin.app',
    );
    await tester.enterText(find.byKey(const Key('flowfin-password')), 'secret');
    await tester.tap(find.byKey(const Key('flowfin-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text('dat@flowfin.app'), findsOneWidget);
    expect(find.text('1.250.000 đ'), findsWidgets);
    expect(find.text('+1.250.000 đ'), findsOneWidget);
    expect(find.text('Tiền mặt'), findsOneWidget);
    expect(find.byKey(const Key('flowfin-sign-out')), findsOneWidget);
  });

  testWidgets('still shows the numbers when there is no AI insight',
      (tester) async {
    await registerController([
      _json(_session()),
      _json(_bootstrap(insight: null)),
      _json(_overview()),
    ]);
    await _pumpDialogHost(tester);

    await tester.enterText(find.byKey(const Key('flowfin-email')), 'a@b.c');
    await tester.enterText(find.byKey(const Key('flowfin-password')), 'secret');
    await tester.tap(find.byKey(const Key('flowfin-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text('1.250.000 đ'), findsWidgets);
    expect(find.textContaining('chưa có phân tích AI'), findsOneWidget);
    expect(find.byKey(const Key('flowfin-error')), findsNothing);
  });

  testWidgets('surfaces a failed sign-in without leaving the form',
      (tester) async {
    await registerController([
      _json({
        'error': {
          'code': 'invalid_credentials',
          'message': 'Email hoặc mật khẩu không đúng',
        },
      }, status: 401),
    ]);
    await _pumpDialogHost(tester);

    await tester.enterText(find.byKey(const Key('flowfin-email')), 'a@b.c');
    await tester.enterText(find.byKey(const Key('flowfin-password')), 'wrong');
    await tester.tap(find.byKey(const Key('flowfin-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('flowfin-error')), findsOneWidget);
    expect(find.text('Email hoặc mật khẩu không đúng'), findsOneWidget);
    expect(find.text('Đăng nhập FlowFin'), findsOneWidget);
  });

  testWidgets('defaults to production, where the real data lives',
      (tester) async {
    await registerController([]);
    await _pumpDialogHost(tester);

    expect(find.byKey(const Key('flowfin-environment')), findsOneWidget);
    expect(find.text('Production'), findsOneWidget);
    expect(find.text('Staging'), findsNothing);
  });
}
