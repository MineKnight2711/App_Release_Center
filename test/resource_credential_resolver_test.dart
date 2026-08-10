import 'dart:io';

import 'package:app_release_center/app/models/ch_play_credentials.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/models/resource_collection.dart';
import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_release_center/app/services/resource_credential_resolver.dart';
import 'package:app_release_center/app/services/resource_discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late ChPlayCredentialStoreService credentialStore;
  late ResourceCredentialResolver resolver;
  late ResourceDiscoveryService discovery;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('arc_resource_credentials_');
    credentialStore = ChPlayCredentialStoreService(
      secureStore: _MemorySecureKeyValueStore(),
    );
    resolver = ResourceCredentialResolver(store: credentialStore);
    discovery = ResourceDiscoveryService();
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  test('prefers secure store credentials over project files', () async {
    final jksFile = File(p.join(root.path, 'release.jks'));
    await jksFile.writeAsBytes([0, 1, 2]);
    await Directory(p.join(root.path, 'android')).create();
    await File(p.join(root.path, 'android', 'key.properties')).writeAsString(
      'keyAlias=file-release\n'
      'storeFile=../release.jks\n'
      'storePassword=file-store-secret\n'
      'keyPassword=file-key-secret\n',
    );
    await credentialStore.save(
      'chp-1',
      ChPlayCredentials(
        jksPath: jksFile.path,
        keyAlias: 'secure-release',
        storePassword: 'secure-store-secret',
        keyPassword: 'secure-key-secret',
      ),
    );

    final findings = await _scanSigningFindings(discovery, root);
    final resolved = await resolver.resolve(
      sourceRoot: root.path,
      findings: findings,
      chPlayProjects: [
        ChPlayProject(
          id: 'chp-1',
          path: root.path,
          displayName: 'Release App',
          applicationId: 'com.example.release',
        ),
      ],
    );

    final entry = resolved[findings.single.id]!;
    expect(entry.source, SigningCredentialSource.secureStore);
    expect(entry.status, SigningCredentialStatus.resolved);
    expect(entry.keyAlias, 'secure-release');
    expect(entry.storePassword, 'secure-store-secret');
    expect(entry.keyPassword, 'secure-key-secret');
    expect(
      entry.maskedPreview.join('\n'),
      isNot(contains('secure-store-secret')),
    );
  });

  test('falls back to android key.properties credentials', () async {
    final keyDirectory = await Directory(
      p.join(root.path, 'android', 'fastlane', 'keys'),
    ).create(recursive: true);
    await File(p.join(keyDirectory.path, 'release.jks')).writeAsBytes([0, 1]);
    await File(p.join(root.path, 'android', 'key.properties')).writeAsString(
      'keyAlias=release\n'
      'storeFile=../fastlane/keys/release.jks\n'
      'storePassword=project-store-secret\n'
      'keyPassword=project-key-secret\n',
    );

    final findings = await _scanSigningFindings(discovery, root);
    final resolved = await resolver.resolve(
      sourceRoot: root.path,
      findings: findings,
      chPlayProjects: const [],
    );

    final entry = resolved[findings.single.id]!;
    expect(entry.source, SigningCredentialSource.projectFile);
    expect(entry.status, SigningCredentialStatus.resolved);
    expect(entry.keyAlias, 'release');
    expect(entry.storePassword, 'project-store-secret');
    expect(entry.keyPassword, 'project-key-secret');
  });

  test('marks incomplete env.properties credentials as partial', () async {
    final keyDirectory = await Directory(
      p.join(root.path, 'android', 'fastlane', 'keys'),
    ).create(recursive: true);
    await File(p.join(keyDirectory.path, 'release.jks')).writeAsBytes([0, 1]);
    await File(p.join(root.path, 'android', 'env.properties')).writeAsString(
      'KEY_ALIAS=release\n'
      'ANDROID_JKS_PATH=fastlane/keys/release.jks\n',
    );

    final findings = await _scanSigningFindings(discovery, root);
    final resolved = await resolver.resolve(
      sourceRoot: root.path,
      findings: findings,
      chPlayProjects: const [],
    );

    final entry = resolved[findings.single.id]!;
    expect(entry.source, SigningCredentialSource.projectFile);
    expect(entry.status, SigningCredentialStatus.partial);
    expect(entry.keyAlias, 'release');
    expect(entry.storePassword, isNull);
    expect(entry.maskedPreview, ['alias=release']);
  });
}

Future<List<ResourceFinding>> _scanSigningFindings(
  ResourceDiscoveryService discovery,
  Directory root,
) async {
  final result = await discovery.scan(
    sourceRoot: root.path,
    preset: ResourceCollectionPreset.custom,
    customKinds: const {ResourceTargetKind.signingKey},
  );
  return result.findings;
}

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}
