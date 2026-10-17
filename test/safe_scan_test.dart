import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/modules/safe/controllers/safe_controller.dart';
import 'package:app_management_center/app/modules/safe/controllers/safe_scan_controller.dart';
import 'package:app_management_center/app/modules/safe/models/safe_item.dart';
import 'package:app_management_center/app/modules/safe/services/safe_secret_scanner.dart';
import 'package:app_management_center/app/modules/safe/services/safe_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 39 characters, the shape of a real Google API key; not a real one.
const googleKey = 'AIzaSyD3fakeFAKEfake0123456789abcdEFGHi';
const awsKey = 'AKIAIOSFODNN7EXAMPLE';
const stripeKey = 'sk_live_' + '51abcdefghijklmnopqrstuv';
const pem =
    '-----BEGIN PRIVATE KEY-----\n'
    'MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQgfakefakefakefake\n'
    '-----END PRIVATE KEY-----\n';

/// A folder of projects the way people keep them, with the traps a scanner
/// has to step around.
Future<void> writeFixture(String root) async {
  Future<void> write(String path, Object content) async {
    final file = File(p.join(root, path));
    await file.parent.create(recursive: true);
    if (content is List<int>) {
      await file.writeAsBytes(content);
    } else {
      await file.writeAsString('$content');
    }
  }

  // A Flutter app: its android/ and ios/ folders must stay part of it.
  await write('ShopApp/pubspec.yaml', 'name: shop_app\n');
  await write(
    'ShopApp/.env',
    'API_URL=https://api.shop.vn\nAPI_KEY=$stripeKey\n',
  );
  await write('ShopApp/.env.example', 'API_URL=\nAPI_KEY=changeme\n');
  await write('ShopApp/android/build.gradle', '// root gradle\n');
  await write('ShopApp/android/app/build.gradle', '// app gradle\n');
  await write(
    'ShopApp/android/key.properties',
    'storePassword=p4ssw0rd!\nkeyPassword=p4ssw0rd!\nkeyAlias=upload\nstoreFile=upload.jks\n',
  );
  await write(
    'ShopApp/android/gradle.properties',
    'org.gradle.jvmargs=-Xmx4g\nandroid.useAndroidX=true\n',
  );
  await write('ShopApp/android/app/upload.jks', [
    0xFE,
    0xED,
    0xFE,
    0xED,
    0,
    0,
    0,
    2,
    1,
    2,
    3,
  ]);
  await write(
    'ShopApp/android/app/google-services.json',
    jsonEncode({
      'project_info': {'project_id': 'shop-prod'},
      'client': [
        {
          'api_key': [
            {'current_key': googleKey},
          ],
        },
      ],
    }),
  );
  await write(
    'ShopApp/android/fastlane/play.json',
    jsonEncode({
      'type': 'service_account',
      'client_email': 'ci@shop-prod.iam.gserviceaccount.com',
      'private_key': pem,
    }),
  );
  await write(
    'ShopApp/ios/Runner/GoogleService-Info.plist',
    '<plist><dict><key>API_KEY</key><string>$googleKey</string></dict></plist>',
  );
  await write(
    'ShopApp/lib/firebase_options.dart',
    "const options = FirebaseOptions(apiKey: '$googleKey');\n",
  );
  await write('ShopApp/lib/config.dart', "const mapsKey = '$googleKey';\n");
  await write(
    'ShopApp/lib/strings.dart',
    "const labels = {'password': 'Forgot your password please'};\n",
  );
  await write(
    'ShopApp/assets/langs/en.json',
    jsonEncode({
      'forgot_password': 'Forgot password?',
      'password_hint': 'Enter your password',
    }),
  );
  await write('ShopApp/keys/AuthKey_ABC123.p8', pem);
  await write(
    'ShopApp/certs/public.pem',
    '-----BEGIN CERTIFICATE-----\nabc\n-----END CERTIFICATE-----\n',
  );
  await write('ShopApp/build/app/secret.env', 'LEAKED=yes\n');
  await write('ShopApp/node_modules/pkg/.env', 'X=1\n');

  // A web project beside it.
  await write('web-admin/package.json', '{"name": "web-admin"}');
  await write('web-admin/.env.production', 'DB_PASSWORD=Zx8vQ2mN7pL4kR9t\n');
  await write('web-admin/src/aws.ts', "export const key = '$awsKey';\n");
  await write(
    'web-admin/src/endpoints.ts',
    "const password = '/api/v1/auth/forgot-password-reset';\n",
  );

  // Secrets kept in a plain folder, outside any project.
  await write('loose/notes/prod.env', 'TOKEN=abc123def456\n');
}

void main() {
  late Directory dir;
  late String root;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('amc-safe-scan');
    root = p.join(dir.path, 'source');
    await writeFixture(root);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  SecretProject projectNamed(SecretScanResult result, String name) =>
      result.projects.singleWhere((project) => project.name == name);

  group('SafeSecretScanner', () {
    test('groups findings by the outermost project and skips the noise', () {
      final result = SafeSecretScanner.scan(root);

      expect(result.projects.map((project) => project.name), [
        'loose',
        'ShopApp',
        'web-admin',
      ]);
      expect(projectNamed(result, 'ShopApp').kind, SecretProjectKind.flutter);
      expect(projectNamed(result, 'web-admin').kind, SecretProjectKind.node);
      expect(projectNamed(result, 'loose').kind, SecretProjectKind.folder);

      final shop = projectNamed(result, 'ShopApp');
      final byPath = {for (final f in shop.findings) f.relativePath: f.type};
      // android/ and ios/ stay inside the app; one token for two files.
      expect(byPath.length, 8);
      expect(byPath['.env'], SecretFindingType.envFile);
      expect(byPath['android/key.properties'], SecretFindingType.properties);
      expect(
        byPath['android/fastlane/play.json'],
        SecretFindingType.serviceAccount,
      );
      expect(
        byPath['android/app/google-services.json'],
        SecretFindingType.firebaseConfig,
      );
      expect(byPath['android/app/upload.jks'], SecretFindingType.keystore);
      expect(
        byPath['ios/Runner/GoogleService-Info.plist'],
        SecretFindingType.appleConfig,
      );
      expect(byPath['keys/AuthKey_ABC123.p8'], SecretFindingType.privateKey);

      final token = shop.findings.singleWhere(
        (f) => f.type == SecretFindingType.inlineToken,
      );
      expect(token.label, 'Google API key');
      expect(token.value, googleKey);
      expect(token.otherPlaces, 1);
      expect(token.line, 1);
      expect(token.preview, isNot(contains(googleKey)));

      // Templates, build output, node_modules, public certificates,
      // translations and plain gradle settings are not secrets.
      final everything = [
        for (final project in result.projects)
          for (final f in project.findings) f.path,
      ].join('\n');
      for (final ignored in [
        '.env.example',
        'build/',
        'node_modules',
        'public.pem',
        'en.json',
        'gradle.properties',
        'strings.dart',
        'endpoints.ts',
      ]) {
        expect(everything, isNot(contains(ignored)), reason: ignored);
      }

      final web = projectNamed(result, 'web-admin');
      expect(web.findings.map((f) => (f.relativePath, f.type, f.label)), [
        ('.env.production', SecretFindingType.envFile, ''),
        ('src/aws.ts', SecretFindingType.inlineToken, 'AWS access key'),
      ]);
      expect(
        projectNamed(result, 'loose').findings.single.relativePath,
        'notes/prod.env',
      );
    });

    test('previews key names and masks values', () {
      final result = SafeSecretScanner.scan(root);
      final shop = projectNamed(result, 'ShopApp');
      final env = shop.findings.singleWhere((f) => f.relativePath == '.env');
      expect(env.preview, 'API_URL, API_KEY');
      expect(
        env.fingerprint,
        fingerprintBytes(File(env.path).readAsBytesSync()),
      );
      final account = shop.findings.singleWhere(
        (f) => f.type == SecretFindingType.serviceAccount,
      );
      expect(account.preview, 'ci@shop-prod.iam.gserviceaccount.com');
      for (final project in result.projects) {
        for (final finding in project.findings) {
          expect(finding.preview, isNot(contains('p4ssw0rd')));
          expect(finding.preview, isNot(contains('sk_live')));
        }
      }
    });

    test('a scan of one project is one group', () {
      final result = SafeSecretScanner.scan(p.join(root, 'ShopApp'));
      expect(result.projects.single.name, 'ShopApp');
    });

    test('runs in an isolate with progress, and can be cancelled', () async {
      final progress = <SecretScanProgress>[];
      final job = SafeSecretScanner.start(root, onProgress: progress.add);
      final result = await job.result;
      expect(result, isNotNull);
      expect(result!.findingCount, SafeSecretScanner.scan(root).findingCount);
      expect(progress, isNotEmpty);

      final cancelled = SafeSecretScanner.start(root);
      cancelled.cancel();
      expect(await cancelled.result, isNull);
    });
  });

  group('SafeScanController', () {
    late SafeController safe;

    setUp(() async {
      safe = SafeController(
        vault: SafeVault(
          locate: () async => File(p.join(dir.path, 'safe.vault')),
          kdfParams: const SafeKdfParams(
            memoryKiB: 64,
            iterations: 1,
            parallelism: 1,
          ),
          deriveKey: deriveSafeKey,
        ),
        writeClipboard: (_) async {},
        readClipboard: () async => '',
      );
      await safe.load();
      await safe.create('correct horse battery', 'correct horse battery');
    });

    tearDown(() => safe.dispose());

    SafeScanController scanner() => SafeScanController(
      safe: safe,
      runner: (root, {onProgress}) => SecretScanJob(
        Future.value(SafeSecretScanner.scan(root, onProgress: onProgress)),
        () {},
      ),
    );

    test(
      'ticks every finding by default and imports them per project',
      () async {
        final scan = scanner();
        await scan.scan(root);
        expect(scan.stage, SafeScanStage.done);
        expect(scan.selectedCount, scan.findingCount);
        expect(scan.selectedProjectCount, 3);

        final result = await scan.importSelected();
        expect(result.imported, scan.findingCount);
        expect(result.projects, 3);
        expect(result.failed, isEmpty);
        expect(safe.projects, ['loose', 'ShopApp', 'web-admin']);

        final env = safe.items.singleWhere(
          (item) => item.project == 'ShopApp' && item.title == '.env',
        );
        expect(env.kind, SafeItemKind.env);
        expect(env.envEntries['API_KEY'], stripeKey);
        expect(env.fileName, '.env');
        expect(env.source, p.join(root, 'ShopApp', '.env'));

        expect(
          safe.items
              .singleWhere((item) => item.fileName == 'key.properties')
              .title,
          'key.properties',
        );
        final jks = safe.items.singleWhere(
          (item) =>
              item.kind == SafeItemKind.file && item.fileName == 'upload.jks',
        );
        expect(jks.fileBytes, [0xFE, 0xED, 0xFE, 0xED, 0, 0, 0, 2, 1, 2, 3]);

        final aws = safe.items.singleWhere((item) => item.secret == awsKey);
        expect(aws.kind, SafeItemKind.apiKey);
        expect(aws.project, 'web-admin');
        expect(aws.title, 'AWS access key · src/aws.ts');
        expect(aws.source, endsWith('aws.ts:1'));

        final google = safe.items.singleWhere(
          (item) => item.secret == googleKey,
        );
        expect(google.notes, contains('1 tệp khác'));

        // Filtering the safe by project.
        safe.setFilter(const SafeFilterProject('web-admin'));
        expect(safe.visibleItems.map((item) => item.title).toSet(), {
          '.env.production',
          'AWS access key · src/aws.ts',
        });
      },
    );

    test('a second scan only offers what the safe does not hold yet', () async {
      final first = scanner();
      await first.scan(root);
      await first.importSelected();

      await File(
        p.join(root, 'web-admin', '.env.staging'),
      ).writeAsString('DB_PASSWORD=n3wS3cretValue99\n');
      final second = scanner();
      await second.scan(root);
      final known = [
        for (final project in second.projects)
          for (final f in project.findings)
            if (second.isKnown(f)) f,
      ];
      expect(known.length, second.findingCount - 1);
      expect(second.selectedCount, 1);
      final web = second.projects.singleWhere((x) => x.name == 'web-admin');
      final staging = web.findings.singleWhere(
        (f) => f.relativePath == '.env.staging',
      );
      expect(second.isSelected(web, staging), isTrue);

      // A known finding cannot be ticked.
      final known0 = known.first;
      final owner = second.projects.firstWhere(
        (x) => x.findings.contains(known0),
      );
      second.toggleFinding(owner, known0);
      expect(second.isSelected(owner, known0), isFalse);
    });

    test(
      'project ticks are tri-state and filters narrow what they touch',
      () async {
        final scan = scanner();
        await scan.scan(root);
        final shop = scan.projects.singleWhere((x) => x.name == 'ShopApp');
        expect(scan.projectState(shop), isTrue);

        scan.toggleFinding(shop, shop.findings.first);
        expect(scan.projectState(shop), isNull);
        scan.toggleProject(shop);
        expect(scan.projectState(shop), isTrue);
        scan.toggleProject(shop);
        expect(scan.projectState(shop), isFalse);
        expect(scan.selectedIn(shop), 0);

        scan.selectAll(true);
        scan.toggleType(SecretFindingType.inlineToken);
        scan.selectAll(false);
        // Hidden inline tokens kept their ticks.
        expect(scan.selectedCount, 2);
        expect(scan.visibleProjects.map((x) => x.name), [
          'loose',
          'ShopApp',
          'web-admin',
        ]);

        scan.setQuery('keystore');
        expect(scan.visibleProjects.single.name, 'ShopApp');
        expect(
          scan.visibleFindings(shop).single.relativePath,
          'android/app/upload.jks',
        );
      },
    );
  });
}
