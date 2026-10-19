import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_management_center/app/modules/safe/models/safe_item.dart';
import 'package:app_management_center/app/modules/safe/services/safe_zip_packer.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const password = 'Abc12345!xyz-Long';
final created = DateTime(2026, 10, 19, 9, 30);

SafeItem item(
  String id,
  SafeItemKind kind,
  String title,
  String secret, {
  String fileName = '',
  String source = '',
  String username = '',
  String url = '',
  String notes = '',
  String project = 'Shop Ứng dụng',
}) => SafeItem(
  id: id,
  kind: kind,
  title: title,
  secret: secret,
  fileName: fileName,
  source: source,
  username: username,
  url: url,
  notes: notes,
  project: project,
  createdAt: created,
  updatedAt: created,
);

final jksBytes = Uint8List.fromList(List.generate(6000, (i) => (i * 7) % 256));
const envText = 'API_URL=https://api.shop.vn\nAPI_KEY=env-secret-value\n';

List<SafeItem> shopItems() => [
  item(
    'env',
    SafeItemKind.env,
    '.env',
    envText,
    fileName: '.env',
    source: '/work/Shop Ứng dụng/.env',
  ),
  item(
    'props',
    SafeItemKind.env,
    'key.properties',
    'storePassword=props-secret\n',
    fileName: 'key.properties',
    source: r'C:\work\Shop Ứng dụng\android\key.properties',
  ),
  item(
    'jks',
    SafeItemKind.file,
    'upload.jks',
    base64Encode(jksBytes),
    fileName: 'upload.jks',
    source: '/work/Shop Ứng dụng/android/app/upload.jks',
  ),
  item(
    'p8',
    SafeItemKind.apiKey,
    'AuthKey_ABC.p8',
    '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n',
    fileName: 'AuthKey_ABC.p8',
    source: '/work/Shop Ứng dụng/keys/AuthKey_ABC.p8',
  ),
  item(
    'gh',
    SafeItemKind.password,
    'GitHub công ty',
    'gh-password-secret',
    username: 'dat@shop.vn',
    url: 'github.com',
  ),
  item(
    'token',
    SafeItemKind.apiKey,
    'Google API key · lib/config.dart',
    'token-value-secret',
    source: '/work/Shop Ứng dụng/lib/config.dart:12',
  ),
  item('note', SafeItemKind.note, 'Mã khôi phục 2FA', 'abcd efgh\nijkl mnop'),
  item(
    'manual',
    SafeItemKind.jsonKey,
    'Play service account',
    '{"type":"service_account"}',
  ),
  // A second .env from elsewhere in the project must not overwrite the first.
  item('env2', SafeItemKind.env, '.env', 'OTHER=1\n', fileName: '.env'),
];

/// Decodes a copy: the archive package decrypts in place, which would leave
/// plaintext in [bytes] and fool any later check on them.
Map<String, List<int>> unzipWith(Uint8List bytes, String password) {
  final archive = ZipDecoder().decodeBytes(
    Uint8List.fromList(bytes),
    password: password,
  );
  return {
    for (final file in archive.files)
      if (file.isFile) file.name: file.content as List<int>,
  };
}

void main() {
  group('validateSafeZipPassword', () {
    test('needs eight printable ASCII characters typed twice', () {
      expect(validateSafeZipPassword('short', 'short'), contains('ít nhất'));
      expect(
        validateSafeZipPassword('mậtkhẩu123', 'mậtkhẩu123'),
        contains('ASCII'),
      );
      expect(
        validateSafeZipPassword('Abc12345!', 'Abc12345?'),
        contains('không khớp'),
      );
      expect(validateSafeZipPassword('Abc12345!', 'Abc12345!'), isNull);
    });
  });

  test('zip names fold Vietnamese and drop unsafe characters', () {
    expect(zipSafeSegment('Shop Ứng dụng'), 'Shop Ung dung');
    expect(zipSafeSegment('Đơn hàng: v2/beta'), 'Don hang_ v2_beta');
    expect(zipSafeSegment('..'), '_');
    expect(zipSafeSegment('.env'), '.env');
  });

  group('SafeProjectKit', () {
    test(
      'keeps project paths for files and gathers the rest in secrets.txt',
      () {
        final kit = SafeProjectKit.build(
          project: 'Shop Ứng dụng',
          items: shopItems(),
          createdAt: created,
        );
        expect(kit.folder, 'Shop Ung dung');
        final paths = {for (final x in kit.placements) x.item.id: x.path};
        expect(paths, {
          'env': '.env',
          'props': 'android/key.properties',
          'jks': 'android/app/upload.jks',
          'p8': 'keys/AuthKey_ABC.p8',
          'gh': 'secrets.txt',
          'token': 'secrets.txt',
          'note': 'secrets.txt',
          'manual': 'Play service account.json',
          'env2': '.env (2)',
        });
        expect(kit.fileCount, 6);
        expect(kit.secretCount, 3);
        expect(
          kit.entries.map((e) => e.path).first,
          'Shop Ung dung/README.txt',
        );

        String text(String name) => utf8.decode(
          kit.entries.singleWhere((e) => e.path == 'Shop Ung dung/$name').bytes,
        );
        final secrets = text('secrets.txt');
        expect(secrets, contains('Tài khoản: dat@shop.vn'));
        expect(secrets, contains('Mật khẩu: gh-password-secret'));
        expect(secrets, contains('Giá trị: token-value-secret'));
        expect(secrets, contains('ijkl mnop'));
        expect(
          secrets,
          contains('Nguồn: /work/Shop Ứng dụng/lib/config.dart:12'),
        );

        final readme = text('README.txt');
        expect(readme, contains('android/key.properties'));
        expect(readme, contains('GitHub công ty'));
        for (final secret in [
          'env-secret-value',
          'props-secret',
          'gh-password-secret',
          'token-value-secret',
          'PRIVATE KEY',
        ]) {
          expect(readme, isNot(contains(secret)), reason: secret);
        }
      },
    );

    test('a kit with only files has no secrets.txt', () {
      final kit = SafeProjectKit.build(
        project: 'Shop Ứng dụng',
        items: shopItems().where((x) => x.id == 'env').toList(),
      );
      expect(kit.entries.map((e) => e.path), [
        'Shop Ung dung/README.txt',
        'Shop Ung dung/.env',
      ]);
    });
  });

  group('encodeSafeZip', () {
    late SafeProjectKit kit;
    setUp(
      () => kit = SafeProjectKit.build(
        project: 'Shop Ứng dụng',
        items: shopItems(),
      ),
    );

    for (final mode in SafeZipEncryption.values) {
      test('${mode.name} opens with the password, byte for byte', () {
        final bytes = encodeSafeZip(
          kit.entries,
          password: password,
          encryption: mode,
        );
        // Nothing readable without the password.
        final raw = latin1.decode(bytes, allowInvalid: true);
        for (final secret in [
          'env-secret-value',
          'gh-password-secret',
          'props-secret',
        ]) {
          expect(raw, isNot(contains(secret)), reason: secret);
        }
        final files = unzipWith(bytes, password);
        expect(files.keys.toSet(), kit.entries.map((e) => e.path).toSet());
        expect(files['Shop Ung dung/android/app/upload.jks'], jksBytes);
        expect(utf8.decode(files['Shop Ung dung/.env']!), envText);
      });

      test('${mode.name} does not open with a wrong password', () {
        final bytes = encodeSafeZip(
          kit.entries,
          password: password,
          encryption: mode,
        );
        Map<String, List<int>>? files;
        try {
          files = unzipWith(bytes, 'not-the-password');
        } catch (_) {
          files = null;
        }
        final env = files?['Shop Ung dung/.env'];
        expect(
          env == null || utf8.decode(env, allowMalformed: true) != envText,
          isTrue,
        );
      });
    }

    // The writer for traditional encryption is our own, so it is checked
    // against the unzip tools people actually have, where they exist.
    group('with system tools', () {
      late Directory dir;
      setUp(() async => dir = await Directory.systemTemp.createTemp('amc-zip'));
      tearDown(() => dir.delete(recursive: true));

      test(
        'Info-ZIP unzip opens the compatible zip',
        () async {
          final zip = File(p.join(dir.path, 'kit.zip'))
            ..writeAsBytesSync(
              encodeSafeZip(
                kit.entries,
                password: password,
                encryption: SafeZipEncryption.zipCrypto,
              ),
            );
          final out = p.join(dir.path, 'out');
          final result = await Process.run('unzip', [
            '-q',
            '-P',
            password,
            zip.path,
            '-d',
            out,
          ]);
          expect(result.exitCode, 0, reason: '${result.stderr}');
          expect(
            File(
              p.join(out, 'Shop Ung dung', 'android', 'app', 'upload.jks'),
            ).readAsBytesSync(),
            jksBytes,
          );

          final wrong = await Process.run('unzip', [
            '-q',
            '-P',
            'not-the-password',
            zip.path,
            '-d',
            p.join(dir.path, 'bad'),
          ]);
          expect(wrong.exitCode, isNot(0));
        },
        skip: Platform.isWindows || !File('/usr/bin/unzip').existsSync()
            ? 'no unzip'
            : false,
      );

      test(
        'bsdtar opens the AES zip',
        () async {
          final zip = File(p.join(dir.path, 'kit.zip'))
            ..writeAsBytesSync(
              encodeSafeZip(
                kit.entries,
                password: password,
                encryption: SafeZipEncryption.aes256,
              ),
            );
          final out = Directory(p.join(dir.path, 'out'))..createSync();
          final result = await Process.run('bsdtar', [
            '-xf',
            zip.path,
            '-C',
            out.path,
            '--passphrase',
            password,
          ]);
          expect(result.exitCode, 0, reason: '${result.stderr}');
          expect(
            File(p.join(out.path, 'Shop Ung dung', '.env')).readAsStringSync(),
            envText,
          );
        },
        skip: Platform.isWindows || !File('/usr/bin/bsdtar').existsSync()
            ? 'no bsdtar'
            : false,
      );
    });
  });
}
