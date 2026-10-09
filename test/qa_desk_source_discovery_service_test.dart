import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/models/automation_models.dart';
import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/source_discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('fiza_qa_discovery_');
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('reads project-owned suites from manifest', () async {
    final config = Directory(
      '${sandbox.path}${Platform.pathSeparator}.fiza-qa',
    );
    await config.create();
    await File(
      '${config.path}${Platform.pathSeparator}project.yaml',
    ).writeAsString('''
schemaVersion: 1
id: sample-flutter
name: Sample Flutter
type: flutter
suites:
  - id: analyze
    name: Analyze
    executable: flutter
    arguments: [analyze]
    tags: [static]
    requiresDevice: true
    requiresAppium: true
    selected: false
''');

    final source = await const SourceDiscoveryService().discover(sandbox.path);

    expect(source.id, 'sample-flutter');
    expect(source.type, SourceType.flutter);
    expect(source.manifestBacked, isTrue);
    expect(source.suites.single.commandPreview, 'flutter analyze');
    expect(source.suites.single.requiresDevice, isTrue);
    expect(source.suites.single.requiresAppium, isTrue);
    expect(source.suites.single.selected, isFalse);
  });

  test('reads the apps QA Desk operates itself', () async {
    final config = Directory(
      '${sandbox.path}${Platform.pathSeparator}.fiza-qa',
    );
    await config.create();
    await File(
      '${config.path}${Platform.pathSeparator}project.yaml',
    ).writeAsString('''
schemaVersion: 1
id: shop
name: Shop
type: flutter
apps:
  - id: shop
    name: Shop app
    login: flows/login.yaml
    cleanup: flows/cleanup.yaml
    productionGuard: [Xoá, Thanh toán]
    environments:
      staging:
        appId: vn.example.shop.staging
        build: build/app-staging.apk
      production:
        appId: vn.example.shop
  - id: admin
    platform: web
    environments:
      uat:
        url: https://uat.example.vn
        production: true
''');

    final source = await const SourceDiscoveryService().discover(sandbox.path);

    expect(source.suites, isEmpty);
    final shop = source.app('shop')!;
    expect(shop.name, 'Shop app');
    expect(shop.platform, QaAppPlatform.android);
    expect(shop.loginFlow, 'flows/login.yaml');
    expect(shop.cleanupFlow, 'flows/cleanup.yaml');
    expect(shop.productionGuard, ['Xoá', 'Thanh toán']);
    expect(shop.environment('staging')?.build, 'build/app-staging.apk');
    expect(shop.environment('staging')?.isProduction, isFalse);
    expect(shop.environment('production')?.isProduction, isTrue);
    final admin = source.app('admin')!;
    expect(admin.name, 'admin');
    expect(admin.platform, QaAppPlatform.web);
    expect(admin.environment('uat')?.isProduction, isTrue);
  });

  test('an app environment needs where to find the app', () async {
    final config = Directory(
      '${sandbox.path}${Platform.pathSeparator}.fiza-qa',
    );
    await config.create();
    await File(
      '${config.path}${Platform.pathSeparator}project.yaml',
    ).writeAsString('''
id: shop
name: Shop
apps:
  - id: shop
    environments:
      staging:
        build: app.apk
''');

    expect(
      () => const SourceDiscoveryService().discover(sandbox.path),
      throwsA(
        isA<SourceDiscoveryException>().having(
          (error) => error.message,
          'message',
          contains('thiếu "appId"'),
        ),
      ),
    );
  });

  test('infers default Flutter suites without a manifest', () async {
    await File(
      '${sandbox.path}${Platform.pathSeparator}pubspec.yaml',
    ).writeAsString('name: sample_app\n');

    final source = await const SourceDiscoveryService().discover(sandbox.path);

    expect(source.type, SourceType.flutter);
    expect(source.suites.map((suite) => suite.id), ['analyze', 'unit-widget']);
    expect(source.manifestBacked, isFalse);
  });

  test('rejects an executable outside the allowlist', () async {
    final config = Directory(
      '${sandbox.path}${Platform.pathSeparator}.fiza-qa',
    );
    await config.create();
    await File(
      '${config.path}${Platform.pathSeparator}project.yaml',
    ).writeAsString('''
id: unsafe
name: Unsafe
type: node
suites:
  - id: delete
    name: Delete
    executable: powershell
    arguments: [-Command, Remove-Item]
''');

    expect(
      () => const SourceDiscoveryService().discover(sandbox.path),
      throwsA(isA<SourceDiscoveryException>()),
    );
  });
}
