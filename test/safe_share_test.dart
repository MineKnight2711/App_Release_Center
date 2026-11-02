import 'dart:convert';
import 'dart:math';

import 'package:app_management_center/app/data/amc_api_client.dart';
import 'package:app_management_center/app/modules/safe/models/safe_item.dart';
import 'package:app_management_center/app/modules/safe/services/safe_share_crypto.dart';
import 'package:app_management_center/app/modules/safe/services/safe_share_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Sealed by this app and opened by the Web Crypto code of
/// `cloudflare/amc-api/src/sharePage.html` (the Worker tests open the same
/// vector). Changing either side of the format breaks one of the two.
const _vector = (
  id: 'HGW-FZJe6hd71He22BrlUA',
  secret: 'BUjd8zykgy2SfDRVaT6o0ortQKuGtIImb65ahvhaZ3s',
  ciphertext:
      'y5z3ieEzK4sQDZjQVpoclOJXOSvwH1y7PcRmLOZ34H4QXc-Riqdzb8-DxxUWth7B-l7PM8dc'
      'AHgoYVUk3WAbPwki8Qe1mflHIIrgfOYGskihzKvte2xEtK45mQzP9Zk2',
  accessHash: 'PAaCOW2JQecbbNhHnh3lkOGga25FlKq341DlBVqzj-Y',
  passwordSalt: 'dSU7QM9nq5lVIOYkqv3jPQ',
  kdfIterations: 100000,
  access: 'zsbkx9-SW66jizZa8JhTx7y9Z1OZbQrjU8cX6c4XRgo',
  password: 'Correct-Horse-9',
);

SafeItem _item({
  SafeItemKind kind = SafeItemKind.apiKey,
  String secret = 'sk_live_123',
  String notes = '',
}) => SafeItem(
  id: 'item-1',
  kind: kind,
  title: 'Stripe live',
  secret: secret,
  url: 'https://dashboard.stripe.com',
  notes: notes,
  project: 'flowfin',
  source: r'C:\work\flowfin\.env:3',
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: DateTime.utc(2026, 10, 1),
);

void main() {
  // The server's minimum keeps the tests quick; the app uses 600 000.
  SafeShareCrypto fastCrypto([int seed = 1]) =>
      SafeShareCrypto(random: Random(seed), iterations: 100000);

  group('SafeShareCrypto', () {
    test('opens the vector the share page opens', () async {
      final crypto = fastCrypto();
      final payload = await crypto.open(
        id: _vector.id,
        secret: _vector.secret,
        ciphertext: _vector.ciphertext,
        password: _vector.password,
        passwordSalt: _vector.passwordSalt,
        kdfIterations: _vector.kdfIterations,
      );
      expect(payload, {
        'v': 1,
        'kind': 'apiKey',
        'title': 'Khoá thử',
        'secret': 'sk_live_123',
      });
      final access = await crypto.accessKey(
        id: _vector.id,
        secret: _vector.secret,
        password: _vector.password,
        passwordSalt: _vector.passwordSalt,
        kdfIterations: _vector.kdfIterations,
      );
      expect(access, _vector.access);
      expect(
        await SafeShareCrypto.accessHashOf(base64UrlDecodeNoPad(access)),
        _vector.accessHash,
      );
    });

    test('seals with a password that the link alone cannot open', () async {
      final crypto = fastCrypto();
      final seal = await crypto.seal({
        'title': 'x',
        'secret': 's',
      }, password: 'Open-Sesame-42');
      expect(seal.id, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      expect(seal.secret, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(seal.accessHash, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(seal.kdfIterations, 100000);
      expect(
        seal.link('https://amc.test/s/${seal.id}'),
        endsWith('#${seal.secret}'),
      );

      final opened = await crypto.open(
        id: seal.id,
        secret: seal.secret,
        ciphertext: seal.ciphertext,
        password: 'Open-Sesame-42',
        passwordSalt: seal.passwordSalt,
        kdfIterations: seal.kdfIterations,
      );
      expect(opened['secret'], 's');

      await expectLater(
        crypto.open(
          id: seal.id,
          secret: seal.secret,
          ciphertext: seal.ciphertext,
          password: 'open-sesame-42',
          passwordSalt: seal.passwordSalt,
          kdfIterations: seal.kdfIterations,
        ),
        throwsA(isA<SafeShareException>()),
      );
      // The key is bound to the id: the same ciphertext under another id fails.
      await expectLater(
        crypto.open(
          id: 'AAAAAAAAAAAAAAAAAAAAAA',
          secret: seal.secret,
          ciphertext: seal.ciphertext,
          password: 'Open-Sesame-42',
          passwordSalt: seal.passwordSalt,
          kdfIterations: seal.kdfIterations,
        ),
        throwsA(isA<SafeShareException>()),
      );
    });

    test('seals without a password', () async {
      final crypto = fastCrypto();
      final seal = await crypto.seal({'title': 'x'});
      expect(seal.hasPassword, isFalse);
      expect(seal.kdfIterations, 0);
      final opened = await crypto.open(
        id: seal.id,
        secret: seal.secret,
        ciphertext: seal.ciphertext,
      );
      expect(opened['title'], 'x');
    });

    test('refuses an item over 1 MB', () async {
      final big = {'secret': 'a' * (safeShareMaxPlainBytes + 1)};
      await expectLater(
        fastCrypto().seal(big),
        throwsA(
          isA<SafeShareException>().having(
            (e) => e.message,
            'message',
            contains('file ZIP'),
          ),
        ),
      );
    });
  });

  test('payload leaves out the source path, and notes unless asked', () {
    final item = _item(notes: 'only for me');
    final plain = safeSharePayload(
      item,
      message: '  Key prod nhé  ',
      from: 'Đạt',
      now: DateTime.utc(2026, 10, 20, 8),
    );
    expect(plain, {
      'v': 1,
      'kind': 'apiKey',
      'title': 'Stripe live',
      'secret': 'sk_live_123',
      'url': 'https://dashboard.stripe.com',
      'project': 'flowfin',
      'message': 'Key prod nhé',
      'from': 'Đạt',
      'sharedAt': '2026-10-20T08:00:00.000Z',
    });
    expect(safeSharePayload(item, includeNotes: true)['notes'], 'only for me');
  });

  test('share passwords are printable ASCII of 8 or more', () {
    expect(validateSafeSharePassword('short'), contains('8 ký tự'));
    expect(validateSafeSharePassword('mật khẩu dài'), contains('ASCII'));
    expect(validateSafeSharePassword('Plain-Ascii-9'), isNull);
  });

  group('SafeShareService', () {
    late List<http.Request> requests;

    SafeShareService service(
      Future<http.Response> Function(http.Request request) reply,
    ) {
      requests = [];
      return SafeShareService(
        api: AmcApiClient(
          baseUrl: Uri.parse('https://amc.test'),
          readToken: () async => 'amc_token',
          httpClient: MockClient((request) {
            requests.add(request);
            return reply(request);
          }),
        ),
        crypto: fastCrypto(),
        senderName: 'Đạt',
      );
    }

    Map<String, Object?> shareJson(String id) => {
      'id': id,
      'itemId': 'item-1',
      'status': 'active',
      'passwordProtected': true,
      'maxViews': 1,
      'views': 0,
      'failedAttempts': 0,
      'createdAt': '2026-10-20T08:00:00.000Z',
      'expiresAt': '2026-10-21T08:00:00.000Z',
      'lastViewedAt': null,
    };

    test('uploads only ciphertext and returns the link with its key', () async {
      final shares = service((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'share': shareJson(body['id'] as String),
            'url': 'https://amc.test/s/${body['id']}',
          }),
          201,
        );
      });
      final created = await shares.create(
        _item(),
        const SafeShareOptions(
          expiresIn: Duration(days: 1),
          maxViews: 1,
          password: 'Open-Sesame-42',
        ),
      );

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://amc.test/v1/shares');
      expect(request.headers['Authorization'], 'Bearer amc_token');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body.keys, {
        'id',
        'itemId',
        'ciphertext',
        'accessHash',
        'passwordSalt',
        'kdfIterations',
        'expiresInHours',
        'maxViews',
      });
      expect(body['expiresInHours'], 24);
      expect(body['maxViews'], 1);
      // Nothing readable leaves the machine.
      expect(request.body, isNot(contains('sk_live_123')));
      expect(request.body, isNot(contains('Stripe')));

      final secret = created.link.split('#').last;
      expect(created.link, 'https://amc.test/s/${body['id']}#$secret');
      expect(request.body, isNot(contains(secret)));
      expect(created.share.status, SafeShareStatus.active);

      final opened = await fastCrypto().open(
        id: body['id'] as String,
        secret: secret,
        ciphertext: body['ciphertext'] as String,
        password: 'Open-Sesame-42',
        passwordSalt: body['passwordSalt'] as String,
        kdfIterations: body['kdfIterations'] as int,
      );
      expect(opened['secret'], 'sk_live_123');
      expect(opened['from'], 'Đạt');
      expect(opened.containsKey('source'), isFalse);
    });

    test('refuses a weak password before contacting the server', () async {
      final shares = service((_) async => http.Response('{}', 500));
      await expectLater(
        shares.create(_item(), const SafeShareOptions(password: 'abc')),
        throwsA(isA<SafeShareException>()),
      );
      expect(requests, isEmpty);
    });

    test('lists and revokes', () async {
      final shares = service((request) async {
        if (request.method == 'DELETE') return http.Response('', 204);
        return http.Response(
          jsonEncode({
            'shares': [
              shareJson('one'),
              {...shareJson('two'), 'status': 'used-up', 'views': 1},
            ],
          }),
          200,
        );
      });
      final links = await shares.list();
      expect(links.map((link) => link.status), [
        SafeShareStatus.active,
        SafeShareStatus.usedUp,
      ]);
      expect(links.first.expiresAt, DateTime.utc(2026, 10, 21, 8).toLocal());

      await shares.revoke('two');
      expect(requests.last.method, 'DELETE');
      expect(requests.last.url.path, '/v1/shares/two');
    });

    test('shares a whole kit as one link', () async {
      final shares = service((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'share': {
              ...shareJson(body['id'] as String),
              'itemId': body['itemId'],
            },
            'url': 'https://amc.test/s/${body['id']}',
          }),
          201,
        );
      });
      final created = await shares.createBundle(
        project: 'ShopApp',
        items: _kitItems(),
        options: const SafeShareOptions(password: 'Open-Sesame-42'),
      );
      final body = jsonDecode(requests.single.body) as Map<String, Object?>;
      expect(body['itemId'], 'bundle:ShopApp');
      expect(created.share.bundleProject, 'ShopApp');
      expect(requests.single.body, isNot(contains('upload.jks')));

      final opened = await fastCrypto().open(
        id: body['id'] as String,
        secret: created.link.split('#').last,
        ciphertext: body['ciphertext'] as String,
        password: 'Open-Sesame-42',
        passwordSalt: body['passwordSalt'] as String,
        kdfIterations: body['kdfIterations'] as int,
      );
      expect(opened['kind'], 'bundle');
      expect((opened['items'] as List).length, 3);

      await expectLater(
        shares.createBundle(
          project: 'ShopApp',
          items: const [],
          options: const SafeShareOptions(),
        ),
        throwsA(isA<SafeShareException>()),
      );
    });
  });

  group('kit payload', () {
    test('lays items out like the zip, without local paths', () {
      final payload = safeShareBundlePayload(
        project: 'ShopApp',
        items: _kitItems(),
        message: 'Bộ keys bản 2.4',
        from: 'Đạt',
        now: DateTime.utc(2026, 10, 20, 8),
      );
      expect(payload['kind'], 'bundle');
      expect(payload['title'], 'Bộ keys ShopApp');
      expect(payload['folder'], 'ShopApp');
      expect(payload['message'], 'Bộ keys bản 2.4');

      final items = [
        for (final item in payload['items'] as List)
          Map<String, Object?>.from(item as Map),
      ];
      expect(
        {for (final item in items) item['title']: item['path']},
        {
          'upload.jks': 'android/app/upload.jks',
          '.env': '.env',
          'Firebase console': 'secrets.txt',
        },
      );
      final keystore = items.firstWhere((i) => i['title'] == 'upload.jks');
      expect(keystore['secret'], base64Encode([1, 2, 3, 4, 5]));

      final files = {
        for (final file in payload['files'] as List)
          (file as Map)['path']: file['text'] as String,
      };
      expect(files.keys, {'README.txt', 'secrets.txt'});
      expect(files['secrets.txt'], contains('Mật khẩu: firebase-password'));
      expect(files['README.txt'], contains('android/app/upload.jks'));

      // Nothing about where the keys sat on this machine, nor notes.
      final text = jsonEncode(payload);
      expect(text, isNot(contains('/work/ShopApp')));
      expect(text, isNot(contains('Nguồn')));
      expect(text, isNot(contains('alias upload')));
    });

    test('carries notes only when asked', () {
      final payload = safeShareBundlePayload(
        project: 'ShopApp',
        items: _kitItems(),
        includeNotes: true,
      );
      final keystore = (payload['items'] as List).cast<Map>().firstWhere(
        (item) => item['title'] == 'upload.jks',
      );
      expect(keystore['notes'], 'alias upload');
      final secrets = (payload['files'] as List).cast<Map>().firstWhere(
        (file) => file['path'] == 'secrets.txt',
      );
      expect(secrets['text'], contains('Ghi chú: 2FA on'));
    });
  });
}

/// A scanned project: a keystore, an env file and a console login.
List<SafeItem> _kitItems() {
  final now = DateTime.utc(2026, 10, 1);
  return [
    SafeItem(
      id: 'jks',
      kind: SafeItemKind.file,
      title: 'upload.jks',
      fileName: 'upload.jks',
      project: 'ShopApp',
      source: '/work/ShopApp/android/app/upload.jks',
      notes: 'alias upload',
      secret: base64Encode([1, 2, 3, 4, 5]),
      createdAt: now,
      updatedAt: now,
    ),
    SafeItem(
      id: 'env',
      kind: SafeItemKind.env,
      title: '.env',
      fileName: '.env',
      project: 'ShopApp',
      source: '/work/ShopApp/.env',
      secret: 'API_KEY=shop\n',
      createdAt: now,
      updatedAt: now,
    ),
    SafeItem(
      id: 'firebase',
      kind: SafeItemKind.password,
      title: 'Firebase console',
      username: 'dev@shop.vn',
      project: 'ShopApp',
      source: '/work/ShopApp/docs/accounts.md:4',
      notes: '2FA on',
      secret: 'firebase-password',
      createdAt: now,
      updatedAt: now,
    ),
  ];
}
