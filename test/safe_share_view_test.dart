import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_management_center/app/data/amc_api_client.dart';
import 'package:app_management_center/app/modules/safe/controllers/safe_controller.dart';
import 'package:app_management_center/app/modules/safe/models/safe_item.dart';
import 'package:app_management_center/app/modules/safe/services/safe_share_crypto.dart';
import 'package:app_management_center/app/modules/safe/services/safe_share_service.dart';
import 'package:app_management_center/app/modules/safe/services/safe_vault.dart';
import 'package:app_management_center/app/modules/safe/views/safe_pack_dialog.dart';
import 'package:app_management_center/app/modules/safe/views/safe_share_dialog.dart';
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

const _code = 'correct horse battery';

void main() {
  late Directory dir;
  late String clipboard;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('amc-safe-share');
    clipboard = '';
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
  }

  Future<SafeController> openSafe(WidgetTester tester) async {
    final safe = SafeController(
      vault: SafeVault(
        locate: () async => File(p.join(dir.path, 'safe.vault')),
        kdfParams: const SafeKdfParams(
          memoryKiB: 64,
          iterations: 1,
          parallelism: 1,
        ),
        deriveKey: deriveSafeKey,
      ),
      writeClipboard: (text) async => clipboard = text,
      readClipboard: () async => clipboard,
    );
    unawaited(safe.load());
    await settle(tester, () => safe.stage == SafeStage.uncreated);
    unawaited(safe.create(_code, _code));
    await settle(tester, () => safe.isOpen);
    var saved = false;
    unawaited(
      safe
          .putAll([
            safe
                .draft(SafeItemKind.file)
                .copyWith(
                  title: 'upload.jks',
                  fileName: 'upload.jks',
                  project: 'ShopApp',
                  notes: 'alias upload, store pass in 1Password',
                  secret: base64Encode([1, 2, 3, 4, 5]),
                ),
          ])
          .then((_) => saved = true),
    );
    await settle(tester, () => saved);
    return safe;
  }

  void sizeWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppCyberTheme.activate(AppThemeChoice.console);
  }

  Map<String, Object?> shareJson(
    String id, {
    String itemId = '',
    String status = 'active',
    int? maxViews = 3,
  }) => {
    'id': id,
    'itemId': itemId,
    'status': status,
    'passwordProtected': true,
    'maxViews': maxViews,
    'views': 1,
    'failedAttempts': 0,
    'createdAt': '2026-10-20T08:00:00.000Z',
    'expiresAt': '2099-10-21T08:00:00.000Z',
    'lastViewedAt': '2026-10-20T09:00:00.000Z',
  };

  SafeShareService serviceFor(
    List<http.Request> requests,
    Future<http.Response> Function(http.Request request) reply,
  ) => SafeShareService(
    api: AmcApiClient(
      baseUrl: Uri.parse('https://amc.test'),
      readToken: () async => 'amc_token',
      httpClient: MockClient((request) {
        requests.add(request);
        return reply(request);
      }),
    ),
    crypto: SafeShareCrypto(random: Random(3), iterations: 100000),
    senderName: 'Đạt',
  );

  Future<void> pumpLauncher(
    WidgetTester tester,
    Future<void> Function(BuildContext context) open,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppCyberTheme.themeData(AppThemeChoice.console),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('makes a one-view link with a password and shows it once', (
    tester,
  ) async {
    sizeWindow(tester);
    final safe = await openSafe(tester);
    final item = safe.items.single;
    final requests = <http.Request>[];
    final service = serviceFor(requests, (request) async {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'shares': [
              shareJson('old-link', itemId: item.id),
              shareJson('other-item', itemId: 'someone-else'),
            ],
          }),
          200,
        );
      }
      final body = jsonDecode(request.body) as Map<String, Object?>;
      return http.Response(
        jsonEncode({
          'share': shareJson(
            body['id'] as String,
            itemId: item.id,
            maxViews: body['maxViews'] as int?,
          ),
          'url': 'https://amc.test/s/${body['id']}',
        }),
        201,
      );
    });

    SafeShareCreated? created;
    await pumpLauncher(tester, (context) async {
      created = await showSafeShareDialog(
        context,
        safe,
        item,
        service: service,
        signedIn: true,
      );
    });
    await settle(
      tester,
      () => find
          .byKey(const Key('safe-share-link-old-link'))
          .evaluate()
          .isNotEmpty,
    );
    // Only this item's live links are listed.
    expect(find.byKey(const Key('safe-share-link-other-item')), findsNothing);

    final password = tester
        .widget<TextField>(find.byKey(const Key('safe-share-password')))
        .controller!
        .text;
    expect(validateSafeSharePassword(password), isNull);
    expect(password, hasLength(16));

    await tester.tap(find.byKey(const Key('safe-share-views-1')));
    await tester.tap(find.byKey(const Key('safe-share-expiry-1')));
    await tester.enterText(
      find.byKey(const Key('safe-share-message')),
      'Keystore bản release',
    );
    await tester.ensureVisible(find.byKey(const Key('safe-share-notes')));
    await tester.tap(find.byKey(const Key('safe-share-notes')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('safe-share-submit')));
    await settle(
      tester,
      () => find.byKey(const Key('safe-share-done')).evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);

    final post = requests.singleWhere((request) => request.method == 'POST');
    final body = jsonDecode(post.body) as Map<String, Object?>;
    expect(body['maxViews'], 1);
    expect(body['expiresInHours'], 1);
    expect(body['itemId'], item.id);
    expect(post.body, isNot(contains('upload.jks')));

    final link = tester
        .widget<SelectableText>(
          find.descendant(
            of: find.byKey(const Key('safe-share-link')),
            matching: find.byType(SelectableText),
          ),
        )
        .data!;
    expect(link, startsWith('https://amc.test/s/${body['id']}#'));
    expect(find.text(password), findsOneWidget);
    expect(find.text('Xem 1 lần rồi tự huỷ'), findsOneWidget);

    // What the recipient's browser will see.
    final opened = await tester.runAsync(
      () => SafeShareCrypto(iterations: 100000).open(
        id: body['id'] as String,
        secret: link.split('#').last,
        ciphertext: body['ciphertext'] as String,
        password: password,
        passwordSalt: body['passwordSalt'] as String,
        kdfIterations: body['kdfIterations'] as int,
      ),
    );
    expect(opened, containsPair('fileName', 'upload.jks'));
    expect(opened, containsPair('message', 'Keystore bản release'));
    expect(
      opened,
      containsPair('notes', 'alias upload, store pass in 1Password'),
    );
    expect(opened, containsPair('from', 'Đạt'));

    // The message to send carries the link, never the password.
    await tester.tap(find.byKey(const Key('safe-share-copy-message')));
    await tester.pump();
    expect(clipboard, contains(link));
    expect(clipboard, isNot(contains(password)));

    await tester.tap(find.text('Xong'));
    await tester.pumpAndSettle();
    expect(created?.link, link);
    safe.lock();
  });

  testWidgets('cannot make a link without an AMC account', (tester) async {
    sizeWindow(tester);
    final safe = await openSafe(tester);
    final requests = <http.Request>[];
    final service = serviceFor(requests, (_) async => http.Response('{}', 500));
    await pumpLauncher(tester, (context) async {
      await showSafeShareDialog(
        context,
        safe,
        safe.items.single,
        service: service,
        signedIn: false,
      );
    });
    expect(find.textContaining('Đăng nhập tài khoản AMC'), findsOneWidget);
    final submit = tester.widget<FilledButton>(
      find.byKey(const Key('safe-share-submit')),
    );
    expect(submit.onPressed, isNull);
    expect(requests, isEmpty);
    safe.lock();
  });

  testWidgets('lists every link and revokes one after confirming', (
    tester,
  ) async {
    sizeWindow(tester);
    final safe = await openSafe(tester);
    final item = safe.items.single;
    final requests = <http.Request>[];
    final service = serviceFor(requests, (request) async {
      if (request.method == 'DELETE') return http.Response('', 204);
      return http.Response(
        jsonEncode({
          'shares': [
            shareJson('live', itemId: item.id),
            shareJson('kit', itemId: 'bundle:ShopApp'),
            shareJson('burned', itemId: 'gone-item', status: 'used-up'),
          ],
        }),
        200,
      );
    });

    var kitOpened = 0;
    await pumpLauncher(tester, (context) async {
      await showSafeSharesDialog(
        context,
        safe,
        service: service,
        onShareKit: () => kitOpened++,
      );
    });
    await settle(
      tester,
      () => find.byKey(const Key('safe-share-link-live')).evaluate().isNotEmpty,
    );
    expect(find.text('ĐANG MỞ (2)'), findsOneWidget);
    expect(find.text('Bộ keys ShopApp'), findsOneWidget);
    expect(find.text('ĐÃ ĐÓNG (1)'), findsOneWidget);
    expect(find.text('upload.jks'), findsOneWidget);
    expect(find.text('(Mục đã xoá khỏi két)'), findsOneWidget);
    expect(find.text('Hết lượt xem'), findsOneWidget);

    await tester.tap(find.byKey(const Key('safe-share-revoke-live')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Thu hồi'));
    await settle(
      tester,
      () => find.byKey(const Key('safe-share-link-live')).evaluate().isEmpty,
    );
    expect(requests.last.method, 'DELETE');
    expect(requests.last.url.path, '/v1/shares/live');

    await tester.tap(find.byKey(const Key('safe-shares-share-kit')));
    await tester.pumpAndSettle();
    expect(kitOpened, 1);
    expect(find.text('Link chia sẻ'), findsNothing);
    safe.lock();
  });

  testWidgets('shares a project kit as one link from the pack dialog', (
    tester,
  ) async {
    sizeWindow(tester);
    final safe = await openSafe(tester);
    var saved = false;
    unawaited(
      safe
          .putAll([
            safe
                .draft(SafeItemKind.env)
                .copyWith(
                  title: '.env',
                  fileName: '.env',
                  project: 'ShopApp',
                  source: '/work/ShopApp/.env',
                  secret: 'API_KEY=shop-env-secret\n',
                ),
            safe
                .draft(SafeItemKind.password)
                .copyWith(
                  title: 'Firebase console',
                  username: 'dev@shop.vn',
                  project: 'ShopApp',
                  secret: 'firebase-password',
                ),
          ])
          .then((_) => saved = true),
    );
    await settle(tester, () => saved);

    final requests = <http.Request>[];
    final service = serviceFor(requests, (request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      return http.Response(
        jsonEncode({
          'share': shareJson(
            body['id'] as String,
            itemId: body['itemId'] as String,
            maxViews: body['maxViews'] as int?,
          ),
          'url': 'https://amc.test/s/${body['id']}',
        }),
        201,
      );
    });

    await pumpLauncher(tester, (context) async {
      await showSafePackDialog(
        context,
        safe,
        project: 'ShopApp',
        shareService: service,
        signedIn: true,
      );
    });
    // Opens on the zip; the link is one tap away.
    expect(find.byKey(const Key('safe-pack-password')), findsOneWidget);
    await tester.tap(find.byKey(const Key('safe-pack-output-link')));
    await tester.pump();
    expect(find.byKey(const Key('safe-pack-password')), findsNothing);
    expect(find.byKey(const Key('safe-share-password')), findsOneWidget);
    expect(find.text('Tạo link cho 3 mục'), findsOneWidget);

    // Leave the console login out.
    final firebase = safe.items.singleWhere(
      (item) => item.title == 'Firebase console',
    );
    await tester.tap(find.byKey(Key('safe-pack-item-${firebase.id}')));
    await tester.pump();
    expect(find.text('Tạo link cho 2 mục'), findsOneWidget);

    final password = tester
        .widget<TextField>(find.byKey(const Key('safe-share-password')))
        .controller!
        .text;
    await tester.ensureVisible(find.byKey(const Key('safe-pack-submit')));
    await tester.tap(find.byKey(const Key('safe-pack-submit')));
    await settle(
      tester,
      () => find.byKey(const Key('safe-share-done')).evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);

    final post = requests.single;
    final body = jsonDecode(post.body) as Map<String, Object?>;
    expect(body['itemId'], 'bundle:ShopApp');
    expect(post.body, isNot(contains('shop-env-secret')));

    final link = tester
        .widget<SelectableText>(
          find.descendant(
            of: find.byKey(const Key('safe-share-link')),
            matching: find.byType(SelectableText),
          ),
        )
        .data!;
    final opened = await tester.runAsync(
      () => SafeShareCrypto(iterations: 100000).open(
        id: body['id'] as String,
        secret: link.split('#').last,
        ciphertext: body['ciphertext'] as String,
        password: password,
        passwordSalt: body['passwordSalt'] as String,
        kdfIterations: body['kdfIterations'] as int,
      ),
    );
    expect(opened!['kind'], 'bundle');
    final items = (opened['items'] as List).cast<Map>();
    expect(
      {for (final item in items) item['title']: item['path']},
      {'upload.jks': 'upload.jks', '.env': '.env'},
    );
    expect(jsonEncode(opened), isNot(contains('/work/ShopApp')));

    await tester.tap(find.byKey(const Key('safe-share-copy-message')));
    await tester.pump();
    expect(clipboard, contains('Bộ keys ShopApp'));
    expect(clipboard, contains(link));
    expect(clipboard, isNot(contains(password)));
    safe.lock();
  });
}
