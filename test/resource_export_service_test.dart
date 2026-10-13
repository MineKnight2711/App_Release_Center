import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:app_management_center/app/models/app_store_credentials.dart';
import 'package:app_management_center/app/models/resource_collection.dart';
import 'package:app_management_center/app/services/resource_discovery_service.dart';
import 'package:app_management_center/app/services/resource_export_service.dart';
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

  test('ships a setup README for Android and iOS with every export', () async {
    final findings = await _findings(discovery, root);
    final result = await ResourceExportService().export(
      sourceRoot: root.path,
      targetRoot: target.path,
      findings: findings,
      createdAt: DateTime(2026, 10, 13, 9, 30),
    );

    final sourceName = p.basename(root.path);
    final readme = _archiveText(
      await _readZip(result.archivePath),
      '$sourceName/README.md',
    );
    expect(readme, contains('# Bộ key release · $sourceName'));
    expect(readme, contains('2026-10-13 09:30'));
    expect(readme, contains('| `.env` | File env |'));
    expect(readme, contains('| `android/env.properties` | File properties |'));
    expect(readme, contains('## Android · CH Play'));
    expect(readme, contains('## iOS · TestFlight / App Store'));
    // Missing keys are named so the reader knows what to ask for.
    expect(readme, contains('✗ keystore'));
    expect(readme, contains('✗ key App Store Connect (.p8)'));
    expect(readme, contains('Chưa có key thì tạo ở App Store Connect'));
    expect(readme, isNot(contains('super-secret-token')));
    expect(result.storedKeyCount, 0);
  });

  test('adds keys kept in AMC without temporary copies', () async {
    final outside = await Directory.systemTemp.createTemp('arc_keystore_');
    addTearDown(() => outside.delete(recursive: true));
    final keystore = File(p.join(outside.path, 'upload.jks'));
    await keystore.writeAsBytes([1, 2, 3]);
    final storedKeys = StoredReleaseKeys(
      appStore: const AppStoreCredentials(
        p8PrivateKey:
            '-----BEGIN PRIVATE KEY-----\nAQID\n-----END PRIVATE KEY-----',
        keyId: 'ABC123',
        issuerId: 'issuer-1',
        teamId: 'TEAM42',
      ),
      bundleId: 'com.example.app',
      playServiceAccountJson: '{"type": "service_account"}',
      keystorePath: keystore.path,
      keystoreCredential: const SigningCredentialBundleEntry(
        relativePath: 'upload.jks',
        source: SigningCredentialSource.secureStore,
        keyAlias: 'upload',
        storePassword: 'store-pass',
        keyPassword: 'key-pass',
      ),
    );

    final result = await ResourceExportService().export(
      sourceRoot: root.path,
      targetRoot: target.path,
      findings: const [],
      storedKeys: storedKeys,
    );

    final sourceName = p.basename(root.path);
    final archive = await _readZip(result.archivePath);
    expect(result.fileCount, 0);
    // The IDs file is not a secret, so it is not counted.
    expect(result.storedKeyCount, 3);
    expect(
      _archiveText(archive, '$sourceName/amc_keys/ios/AuthKey_ABC123.p8'),
      contains('BEGIN PRIVATE KEY'),
    );
    final config = _archiveText(
      archive,
      '$sourceName/amc_keys/ios/app_store_connect.env',
    );
    expect(config, contains('AMC_KEY_ID=ABC123'));
    expect(config, contains('AMC_ISSUER_ID=issuer-1'));
    expect(config, contains('AMC_KEY_FILE=AuthKey_ABC123.p8'));
    expect(config, contains('APP_STORE_TEAM_ID=TEAM42'));
    expect(config, contains('APP_STORE_BUNDLE_ID=com.example.app'));
    expect(
      _archiveText(
        archive,
        '$sourceName/amc_keys/android/google-play-service-account.json',
      ),
      contains('service_account'),
    );
    expect(
      archive.findFile('$sourceName/amc_keys/android/upload.jks')!.content,
      [1, 2, 3],
    );
    final credentials = _archiveText(
      archive,
      '$sourceName/signing_credentials.txt',
    );
    expect(credentials, contains('[amc_keys/android/upload.jks]'));
    expect(credentials, contains('storePassword=store-pass'));
    final readme = _archiveText(archive, '$sourceName/README.md');
    expect(readme, contains('✓ keystore'));
    expect(readme, contains('✓ key App Store Connect (.p8)'));
    expect(readme, contains('key_id: "ABC123"'));
    expect(readme, contains('issuer_id: "issuer-1"'));
    expect(readme, isNot(contains('Chưa có key thì tạo')));
    expect(readme, isNot(contains('AQID')));
    expect(readme, isNot(contains('store-pass')));
  });

  test('locks every entry with AES-256 when a password is set', () async {
    final findings = await _findings(discovery, root);
    final result = await ResourceExportService().export(
      sourceRoot: root.path,
      targetRoot: target.path,
      findings: findings,
      signingCredentials: const [
        SigningCredentialBundleEntry(
          relativePath: 'android/app/upload.jks',
          source: SigningCredentialSource.manual,
          storePassword: 'store-pass',
        ),
      ],
      storedKeys: const StoredReleaseKeys(
        playServiceAccountJson: '{"type": "service_account"}',
      ),
      password: _zipPassword,
      createdAt: DateTime(2026, 10, 13, 9, 30),
    );

    final sourceName = p.basename(root.path);
    final bytes = await File(result.archivePath).readAsBytes();
    expect(result.isLocked, isTrue);
    // WinZip AES extra field: id 0x9901, AE-1, vendor "AE", strength 3 (256).
    expect(
      _containsBytes(bytes, [
        0x01,
        0x99,
        0x07,
        0x00,
        0x01,
        0x00,
        0x41,
        0x45,
        3,
      ]),
      isTrue,
    );

    final archive = ZipDecoder().decodeBytes(bytes, password: _zipPassword);
    expect(
      _archiveText(archive, '$sourceName/.env'),
      contains('super-secret-token'),
    );
    expect(
      _archiveText(archive, '$sourceName/signing_credentials.txt'),
      contains('storePassword=store-pass'),
    );
    expect(
      _archiveText(
        archive,
        '$sourceName/amc_keys/android/google-play-service-account.json',
      ),
      contains('service_account'),
    );
    expect(
      _archiveText(archive, '$sourceName/README.md'),
      contains('# Bộ key release · $sourceName'),
    );

    final guidePath = result.guidePath!;
    expect(p.dirname(guidePath), p.dirname(result.archivePath));
    expect(p.basename(guidePath), '$sourceName.README.md');
    final guide = await File(guidePath).readAsString();
    expect(guide, contains('AES-256'));
    expect(guide, contains('tar -xf $sourceName.zip'));
    expect(guide, contains('7z x $sourceName.zip'));
    expect(guide, contains('`$sourceName/README.md`'));
    for (final secret in [
      _zipPassword,
      'super-secret-token',
      'store-pass',
      'android/env.properties',
    ]) {
      expect(guide, isNot(contains(secret)));
    }
  });

  test(
    'refuses to open a locked zip with a wrong or missing password',
    () async {
      final result = await ResourceExportService().export(
        sourceRoot: root.path,
        targetRoot: target.path,
        findings: await _findings(discovery, root),
        password: _zipPassword,
      );

      final sourceName = p.basename(root.path);
      final bytes = await File(result.archivePath).readAsBytes();
      expect(
        () => _archiveText(
          ZipDecoder().decodeBytes(bytes, password: 'wrong-password'),
          '$sourceName/.env',
        ),
        throwsException,
      );
      expect(
        () => _archiveText(ZipDecoder().decodeBytes(bytes), '$sourceName/.env'),
        throwsA(anything),
      );
    },
  );

  test('accepts only zip passwords that other unzip tools can open', () async {
    expect(validateResourceArchivePassword('', ''), isNull);
    expect(validateResourceArchivePassword(_zipPassword, _zipPassword), isNull);
    expect(
      validateResourceArchivePassword('short', 'short'),
      'Mật khẩu zip cần ít nhất 8 ký tự.',
    );
    expect(
      validateResourceArchivePassword('mậtkhẩu-2026', 'mậtkhẩu-2026'),
      'Mật khẩu zip chỉ dùng chữ không dấu, số và ký hiệu ASCII.',
    );
    expect(
      validateResourceArchivePassword(_zipPassword, 'kit-Pass-2025'),
      'Mật khẩu xác nhận không khớp.',
    );
    expect(
      validateResourceArchivePassword('', _zipPassword),
      'Mật khẩu xác nhận không khớp.',
    );

    await expectLater(
      ResourceExportService().export(
        sourceRoot: root.path,
        targetRoot: target.path,
        findings: await _findings(discovery, root),
        password: 'mậtkhẩu-2026',
      ),
      throwsA(isA<ResourceExportException>()),
    );
    expect(target.listSync(), isEmpty);
  });

  test(
    'drops the open guide when exporting again without a password',
    () async {
      final findings = await _findings(discovery, root);
      final service = ResourceExportService();
      final locked = await service.export(
        sourceRoot: root.path,
        targetRoot: target.path,
        findings: findings,
        password: _zipPassword,
      );
      expect(File(locked.guidePath!).existsSync(), isTrue);

      final plain = await service.export(
        sourceRoot: root.path,
        targetRoot: target.path,
        findings: findings,
        password: '',
      );

      final sourceName = p.basename(root.path);
      expect(plain.isLocked, isFalse);
      expect(File(locked.guidePath!).existsSync(), isFalse);
      expect(
        _archiveText(await _readZip(plain.archivePath), '$sourceName/.env'),
        contains('super-secret-token'),
      );
    },
  );

  test('release preset gathers signing and App Store keys too', () async {
    await Directory(p.join(root.path, 'android', 'app')).create();
    await File(
      p.join(root.path, 'android', 'app', 'upload.jks'),
    ).writeAsBytes([0, 1]);
    await File(
      p.join(root.path, 'ios', 'AuthKey_X.p8'),
    ).create(recursive: true);
    final scan = await discovery.scan(
      sourceRoot: root.path,
      preset: ResourceCollectionPreset.release,
      customKinds: const {},
    );
    expect(
      scan.findings.map((finding) => finding.kind).toSet(),
      containsAll([
        ResourceTargetKind.envFile,
        ResourceTargetKind.properties,
        ResourceTargetKind.signingKey,
        ResourceTargetKind.appStoreKey,
      ]),
    );
  });

  test(
    'finds a key saved as .p8.txt, not notes, public keys or examples',
    () async {
      await Directory(p.join(root.path, 'keystore')).create();
      await File(
        p.join(root.path, 'keystore', 'AuthKey_K973PPK6L9.p8.txt'),
      ).writeAsString(
        '-----BEGIN PRIVATE KEY-----\nAQID\n-----END PRIVATE KEY-----\n',
      );
      await File(
        p.join(root.path, 'keystore', 'AuthKey_notes.txt'),
      ).writeAsString('Key ID K973PPK6L9, see App Store Connect\n');
      // An SDK's public key and an example env file are not release keys.
      await File(p.join(root.path, 'keystore', 'public.pem')).writeAsString(
        '-----BEGIN PUBLIC KEY-----\nAQID\n-----END PUBLIC KEY-----\n',
      );
      await File(
        p.join(root.path, 'android', 'env.properties.example'),
      ).writeAsString('KEY_ALIAS=\n');

      final scan = await discovery.scan(
        sourceRoot: root.path,
        preset: ResourceCollectionPreset.release,
        customKinds: const {},
      );
      expect(
        scan.findings
            .where((finding) => finding.kind == ResourceTargetKind.appStoreKey)
            .map((finding) => finding.relativePath),
        ['keystore/AuthKey_K973PPK6L9.p8.txt'],
      );
      expect(
        scan.findings.map((finding) => finding.relativePath),
        isNot(contains('android/env.properties.example')),
      );
    },
  );

  test(
    'writes App Store IDs for a project .p8 and a filled key.properties',
    () async {
      await Directory(p.join(root.path, 'keystore')).create();
      await File(
        p.join(root.path, 'keystore', 'AuthKey_K973PPK6L9.p8.txt'),
      ).writeAsString(
        '-----BEGIN PRIVATE KEY-----\nAQID\n-----END PRIVATE KEY-----\n',
      );
      await File(
        p.join(root.path, 'keystore', 'keystore.jks'),
      ).writeAsBytes([1, 2]);
      final scan = await discovery.scan(
        sourceRoot: root.path,
        preset: ResourceCollectionPreset.release,
        customKinds: const {},
      );

      final result = await ResourceExportService().export(
        sourceRoot: root.path,
        targetRoot: target.path,
        findings: scan.findings,
        signingCredentials: const [
          SigningCredentialBundleEntry(
            relativePath: 'keystore/keystore.jks',
            source: SigningCredentialSource.secureStore,
            keyAlias: 'upload',
            storePassword: 'store-pass',
            keyPassword: 'key-pass',
          ),
        ],
        storedKeys: const StoredReleaseKeys(
          appStore: AppStoreCredentials(
            keyId: 'K973PPK6L9',
            issuerId: 'issuer-1',
            teamId: '9KXDDLUB3Y',
          ),
          bundleId: 'com.emed.globerdr',
          projectAppStoreKeyPath: 'keystore/AuthKey_K973PPK6L9.p8.txt',
        ),
      );

      final sourceName = p.basename(root.path);
      final archive = await _readZip(result.archivePath);
      expect(result.storedKeyCount, 0);
      expect(
        _archiveHas(archive, '$sourceName/keystore/AuthKey_K973PPK6L9.p8.txt'),
        isTrue,
      );
      // The project already holds the key, so no second copy is written.
      expect(
        archive.files.where(
          (file) => file.name.contains('amc_keys/ios/AuthKey'),
        ),
        isEmpty,
      );
      final config = _archiveText(
        archive,
        '$sourceName/amc_keys/ios/app_store_connect.env',
      );
      expect(config, contains('AMC_KEY_ID=K973PPK6L9'));
      expect(config, contains('AMC_ISSUER_ID=issuer-1'));
      expect(config, contains('APP_STORE_TEAM_ID=9KXDDLUB3Y'));
      expect(
        config,
        contains('AMC_KEY_FILE=keystore/AuthKey_K973PPK6L9.p8.txt'),
      );
      expect(config, contains('đuôi .txt thừa'));

      final keyProperties = _archiveText(
        archive,
        '$sourceName/amc_keys/android/key.properties',
      );
      expect(keyProperties, contains('keyAlias=upload'));
      expect(keyProperties, contains('storePassword=store-pass'));
      expect(keyProperties, contains('keyPassword=key-pass'));
      expect(keyProperties, contains('storeFile=../../keystore/keystore.jks'));

      final readme = _archiveText(archive, '$sourceName/README.md');
      expect(readme, contains('Key ID `K973PPK6L9`'));
      expect(readme, contains('Issuer ID `issuer-1`'));
      expect(readme, contains('Team ID `9KXDDLUB3Y`'));
      expect(readme, contains('đuôi `.txt` thừa'));
      expect(readme, contains('Đã điền sẵn alias, mật khẩu và `storeFile`'));
      expect(readme, isNot(contains('store-pass')));
    },
  );

  test('fills storeFile from android/ when Gradle uses rootProject', () async {
    await Directory(p.join(root.path, 'keystore')).create();
    await File(
      p.join(root.path, 'keystore', 'keystore.jks'),
    ).writeAsBytes([1, 2]);
    await Directory(p.join(root.path, 'android', 'app')).create();
    // The way emed_plus_new resolves its keystore.
    await File(
      p.join(root.path, 'android', 'app', 'build.gradle'),
    ).writeAsString(
      'def keystorePath = keyProperties.getProperty("storeFile")\n'
      'candidate.isAbsolute() ? candidate : rootProject.file(path)\n',
    );
    final scan = await discovery.scan(
      sourceRoot: root.path,
      preset: ResourceCollectionPreset.release,
      customKinds: const {},
    );

    final result = await ResourceExportService().export(
      sourceRoot: root.path,
      targetRoot: target.path,
      findings: scan.findings,
      signingCredentials: const [
        SigningCredentialBundleEntry(
          relativePath: 'keystore/keystore.jks',
          source: SigningCredentialSource.secureStore,
          keyAlias: 'upload',
          storePassword: 'a',
          keyPassword: 'b',
        ),
      ],
    );

    final keyProperties = _archiveText(
      await _readZip(result.archivePath),
      '${p.basename(root.path)}/amc_keys/android/key.properties',
    );
    expect(keyProperties, contains('storeFile=../keystore/keystore.jks'));
    expect(keyProperties, contains('storeFile tính từ android/.'));
  });

  test('does not replace a key.properties the project already has', () async {
    final keyDirectory = await Directory(
      p.join(root.path, 'android', 'app'),
    ).create(recursive: true);
    await File(p.join(keyDirectory.path, 'upload.jks')).writeAsBytes([1]);
    await File(
      p.join(root.path, 'android', 'key.properties'),
    ).writeAsString('storeFile=upload.jks\n');
    final scan = await discovery.scan(
      sourceRoot: root.path,
      preset: ResourceCollectionPreset.release,
      customKinds: const {},
    );

    final result = await ResourceExportService().export(
      sourceRoot: root.path,
      targetRoot: target.path,
      findings: scan.findings,
      signingCredentials: const [
        SigningCredentialBundleEntry(
          relativePath: 'android/app/upload.jks',
          source: SigningCredentialSource.projectFile,
          keyAlias: 'upload',
          storePassword: 'a',
          keyPassword: 'b',
        ),
      ],
    );

    final archive = await _readZip(result.archivePath);
    expect(
      archive.files.where(
        (file) => file.name.endsWith('amc_keys/android/key.properties'),
      ),
      isEmpty,
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

const _zipPassword = 'kit-Pass-2026';

bool _containsBytes(List<int> bytes, List<int> pattern) {
  for (var start = 0; start <= bytes.length - pattern.length; start++) {
    var index = 0;
    while (index < pattern.length && bytes[start + index] == pattern[index]) {
      index++;
    }
    if (index == pattern.length) return true;
  }
  return false;
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
