import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:app_release_center/app/models/resource_collection.dart';
import 'package:app_release_center/app/services/resource_discovery_service.dart';
import 'package:app_release_center/app/services/resource_export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory target;
  late ResourceDiscoveryService discovery;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('arc_resource_export_source_');
    target = await Directory.systemTemp.createTemp(
      'arc_resource_export_target_',
    );
    discovery = ResourceDiscoveryService();

    await File(p.join(root.path, '.env')).writeAsString(
      'API_URL=https://api.example.com\nSECRET_TOKEN=super-secret-token\n',
    );
    await Directory(p.join(root.path, 'android')).create();
    await File(
      p.join(root.path, 'android', 'env.properties'),
    ).writeAsString('KEY_ALIAS=release\nSTORE_PASSWORD=store-secret\n');
  });

  tearDown(() async {
    for (final directory in [root, target]) {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    }
  });

  test('exports a simple source-name rooted zip', () async {
    final findings = await _findings(discovery, root);
    final service = ResourceExportService();

    final result = await service.export(
      sourceRoot: root.path,
      targetRoot: target.path,
      findings: findings,
    );

    final sourceName = p.basename(root.path);
    expect(File(result.archivePath).existsSync(), isTrue);
    expect(p.basename(result.archivePath), '$sourceName.zip');
    expect(result.fileCount, 2);
    expect(result.signingCredentialCount, 0);

    final archive = await _readZip(result.archivePath);
    expect(_archiveHas(archive, '$sourceName/.env'), isTrue);
    expect(_archiveHas(archive, '$sourceName/android/env.properties'), isTrue);
    expect(_archiveHas(archive, '$sourceName/files/.env'), isFalse);
    expect(_archiveHas(archive, '$sourceName/manifest.json'), isFalse);
    expect(_archiveHas(archive, '$sourceName/.gitignore'), isFalse);
  });

  test('adds simple signing credentials text when requested', () async {
    final keyDirectory = await Directory(
      p.join(root.path, 'android', 'fastlane', 'keys'),
    ).create(recursive: true);
    await File(p.join(keyDirectory.path, 'release.jks')).writeAsBytes([0, 1]);
    final scan = await discovery.scan(
      sourceRoot: root.path,
      preset: ResourceCollectionPreset.custom,
      customKinds: const {
        ResourceTargetKind.envFile,
        ResourceTargetKind.signingKey,
      },
    );
    final service = ResourceExportService();
    const signingCredential = SigningCredentialBundleEntry(
      relativePath: 'android/fastlane/keys/release.jks',
      source: SigningCredentialSource.manual,
      keyAlias: 'release',
      storePassword: 'store-sidecar-secret',
      keyPassword: 'key-sidecar-secret',
    );

    final result = await service.export(
      sourceRoot: root.path,
      targetRoot: target.path,
      findings: scan.findings,
      signingCredentials: const [signingCredential],
    );

    final sourceName = p.basename(root.path);
    final archive = await _readZip(result.archivePath);
    final sidecar = _archiveText(
      archive,
      '$sourceName/signing_credentials.txt',
    );
    expect(result.signingCredentialCount, 1);
    expect(sidecar, contains('[android/fastlane/keys/release.jks]'));
    expect(sidecar, contains('keyAlias=release'));
    expect(sidecar, contains('storePassword=store-sidecar-secret'));
    expect(sidecar, contains('keyPassword=key-sidecar-secret'));
    expect(
      _archiveHas(archive, '$sourceName/credentials.secret.json'),
      isFalse,
    );
  });

  test('blocks export targets inside source and git worktrees', () async {
    final findings = await _findings(discovery, root);
    final service = ResourceExportService();

    await expectLater(
      service.export(
        sourceRoot: root.path,
        targetRoot: p.join(root.path, 'exports'),
        findings: findings,
      ),
      throwsA(isA<ResourceExportException>()),
    );

    final gitRoot = await Directory.systemTemp.createTemp('arc_resource_git_');
    addTearDown(() async {
      if (gitRoot.existsSync()) {
        await gitRoot.delete(recursive: true);
      }
    });
    await Directory(p.join(gitRoot.path, '.git')).create();

    await expectLater(
      service.export(
        sourceRoot: root.path,
        targetRoot: p.join(gitRoot.path, 'exports'),
        findings: findings,
      ),
      throwsA(isA<ResourceExportException>()),
    );
  });
}

Future<Archive> _readZip(String path) async {
  return ZipDecoder().decodeBytes(await File(path).readAsBytes());
}

bool _archiveHas(Archive archive, String path) {
  return archive.findFile(path) != null;
}

String _archiveText(Archive archive, String path) {
  final file = archive.findFile(path);
  if (file == null) {
    throw StateError('Archive file not found: $path');
  }
  return utf8.decode(file.content);
}

Future<List<ResourceFinding>> _findings(
  ResourceDiscoveryService discovery,
  Directory root,
) async {
  final result = await discovery.scan(
    sourceRoot: root.path,
    preset: ResourceCollectionPreset.allRecommended,
    customKinds: resourceRecommendedTargetKinds,
  );
  return result.findings;
}
