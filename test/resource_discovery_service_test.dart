import 'dart:io';

import 'package:app_release_center/app/models/resource_collection.dart';
import 'package:app_release_center/app/services/resource_discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late ResourceDiscoveryService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('arc_resource_scan_');
    service = ResourceDiscoveryService();

    await File(p.join(root.path, '.env')).writeAsString(
      'API_URL=https://api.example.com\n'
      'SECRET_TOKEN=super-secret-token\n',
    );
    await File(
      p.join(root.path, '.env.production'),
    ).writeAsString('PROD_TOKEN=production-secret\n');
    await File(
      p.join(root.path, '.env.example'),
    ).writeAsString('IGNORED_SECRET=should-not-appear\n');
    await Directory(
      p.join(root.path, 'android', 'fastlane'),
    ).create(recursive: true);
    await Directory(
      p.join(root.path, 'android', 'app'),
    ).create(recursive: true);
    await File(
      p.join(root.path, 'android', 'env.properties'),
    ).writeAsString('KEY_ALIAS=release\nSTORE_PASSWORD=store-secret\n');
    await File(
      p.join(root.path, 'android', 'local.properties'),
    ).writeAsString('sdk.dir=C:/Android\n');
    await File(
      p.join(root.path, 'android', 'fastlane', 'fastlane-service-account.json'),
    ).writeAsString(
      '{"client_email":"bot@example.com","private_key":"json-secret"}',
    );
    await File(
      p.join(root.path, 'android', 'app', 'google-services.json'),
    ).writeAsString('{"project_info":{"project_id":"firebase-demo"}}');
    await File(p.join(root.path, 'release.jks')).writeAsBytes([0, 1, 2, 3]);
    await Directory(p.join(root.path, 'build')).create();
    await File(
      p.join(root.path, 'build', '.env'),
    ).writeAsString('BUILD_SECRET=ignored\n');
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  test('all recommended finds env, properties and account resources', () async {
    final result = await service.scan(
      sourceRoot: root.path,
      preset: ResourceCollectionPreset.allRecommended,
      customKinds: resourceRecommendedTargetKinds,
    );

    final paths = result.findings.map((finding) => finding.relativePath);
    expect(paths, contains('.env'));
    expect(paths, contains('.env.production'));
    expect(paths, contains('android/env.properties'));
    expect(paths, contains('android/fastlane/fastlane-service-account.json'));
    expect(paths, contains('android/app/google-services.json'));
    expect(paths, isNot(contains('.env.example')));
    expect(paths, isNot(contains('android/local.properties')));
    expect(paths, isNot(contains('release.jks')));
    expect(result.excludedPaths, contains('build'));
  });

  test('env only preset limits findings to env files', () async {
    final result = await service.scan(
      sourceRoot: root.path,
      preset: ResourceCollectionPreset.envOnly,
      customKinds: resourceRecommendedTargetKinds,
    );

    expect(result.findings, hasLength(2));
    expect(
      result.findings.every(
        (finding) => finding.kind == ResourceTargetKind.envFile,
      ),
      isTrue,
    );
  });

  test('custom preset includes only selected target kinds', () async {
    final result = await service.scan(
      sourceRoot: root.path,
      preset: ResourceCollectionPreset.custom,
      customKinds: const {
        ResourceTargetKind.envFile,
        ResourceTargetKind.signingKey,
      },
    );

    final kinds = result.findings.map((finding) => finding.kind).toSet();
    expect(kinds, {ResourceTargetKind.envFile, ResourceTargetKind.signingKey});
    expect(
      result.findings
          .singleWhere(
            (finding) => finding.kind == ResourceTargetKind.signingKey,
          )
          .isBinary,
      isTrue,
    );
  });

  test('preview masks values and keeps raw secrets out of findings', () async {
    final result = await service.scan(
      sourceRoot: root.path,
      preset: ResourceCollectionPreset.allRecommended,
      customKinds: resourceRecommendedTargetKinds,
    );

    final env = result.findings.singleWhere(
      (finding) => finding.relativePath == '.env',
    );
    expect(env.detectedKeyNames, contains('SECRET_TOKEN'));
    final preview = env.maskedPreview.join('\n');
    expect(preview, contains('SECRET_TOKEN='));
    expect(preview, isNot(contains('super-secret-token')));
  });
}
