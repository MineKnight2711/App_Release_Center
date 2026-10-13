import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:app_management_center/app/models/resource_collection.dart';
import 'package:app_management_center/app/services/release_kit_readme.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

const resourceArchiveMinPasswordLength = 8;

/// Why [password] cannot lock a resource zip, or null when it can. Both empty
/// means no password.
///
/// Only printable ASCII is allowed: the archive package derives the AES key
/// from the password's UTF-16 code units cut to one byte each, while 7-Zip,
/// Keka and bsdtar use UTF-8, so a password with Vietnamese diacritics would
/// lock a zip that only AMC can open.
String? validateResourceArchivePassword(String password, String confirmation) {
  if (password.isEmpty && confirmation.isEmpty) return null;
  if (password.isNotEmpty &&
      password.length < resourceArchiveMinPasswordLength) {
    return 'Mật khẩu zip cần ít nhất $resourceArchiveMinPasswordLength ký tự.';
  }
  if (password.codeUnits.any((unit) => unit < 0x20 || unit > 0x7E)) {
    return 'Mật khẩu zip chỉ dùng chữ không dấu, số và ký hiệu ASCII.';
  }
  if (password != confirmation) return 'Mật khẩu xác nhận không khớp.';
  return null;
}

class ResourceExportService extends GetxService {
  /// With [password], every entry is encrypted with WinZip AES-256 and a
  /// plain `<name>.README.md` next to the zip says how to open it.
  Future<ResourceExportResult> export({
    required String sourceRoot,
    required String targetRoot,
    required List<ResourceFinding> findings,
    List<SigningCredentialBundleEntry> signingCredentials = const [],
    StoredReleaseKeys storedKeys = const StoredReleaseKeys(),
    String? password,
    DateTime? createdAt,
  }) async {
    final source = Directory(p.normalize(sourceRoot));
    final target = Directory(p.normalize(targetRoot));
    if (!source.existsSync()) {
      throw FileSystemException(
        'Thư mục nguồn tài nguyên không tồn tại.',
        source.path,
      );
    }
    await _validateTarget(source: source, target: target);
    if (findings.isEmpty && storedKeys.isEmpty) {
      throw const ResourceExportException('Chọn ít nhất một file tài nguyên.');
    }
    final archivePassword = password == null || password.isEmpty
        ? null
        : password;
    if (archivePassword != null) {
      final problem = validateResourceArchivePassword(
        archivePassword,
        archivePassword,
      );
      if (problem != null) throw ResourceExportException(problem);
    }

    await target.create(recursive: true);
    final sourceName = _safeSegment(p.basename(source.path));
    final zipFile = File(p.join(target.path, '$sourceName.zip'));
    final guideFile = File(p.join(target.path, '$sourceName.README.md'));
    if (zipFile.existsSync()) await zipFile.delete();
    // A guide left by an earlier locked export would describe the wrong zip.
    if (guideFile.existsSync()) await guideFile.delete();

    final timestamp = createdAt ?? DateTime.now();
    final summary = await _zipResources(
      zipFile: zipFile,
      sourceName: sourceName,
      findings: findings,
      signingCredentials: signingCredentials,
      storedKeys: storedKeys,
      password: archivePassword,
      createdAt: timestamp,
      sourceRoot: source.path,
    );
    if (summary.fileCount == 0 && summary.storedKeyCount == 0) {
      throw const ResourceExportException(
        'Các file tài nguyên đã chọn không còn.',
      );
    }
    if (archivePassword != null) {
      await guideFile.writeAsString(
        buildLockedKitGuide(
          projectName: sourceName,
          archiveName: p.basename(zipFile.path),
          createdAt: timestamp,
        ),
      );
    }

    return ResourceExportResult(
      archivePath: zipFile.path,
      fileCount: summary.fileCount,
      signingCredentialCount: summary.signingCredentialCount,
      storedKeyCount: summary.storedKeyCount,
      guidePath: archivePassword == null ? null : guideFile.path,
    );
  }

  Future<_ZipSummary> _zipResources({
    required File zipFile,
    required String sourceName,
    required List<ResourceFinding> findings,
    required List<SigningCredentialBundleEntry> signingCredentials,
    required StoredReleaseKeys storedKeys,
    required String? password,
    required DateTime createdAt,
    required String sourceRoot,
  }) async {
    final encoder = ZipFileEncoder(password: password)..create(zipFile.path);
    final kitFiles = <ReleaseKitFile>[];
    var fileCount = 0;
    var signingCredentialCount = 0;
    var storedKeyCount = 0;
    try {
      for (final finding in findings) {
        final relativePath = _validateRelativePath(finding.relativePath);
        final sourceFile = File(finding.sourcePath);
        if (!sourceFile.existsSync()) continue;
        encoder.addFileSync(sourceFile, p.posix.join(sourceName, relativePath));
        kitFiles.add(ReleaseKitFile.finding(finding));
        fileCount++;
      }

      // Secrets from the secure store go straight into the archive, never
      // through a temporary file.
      void addStored(String path, ReleaseKitFileKind kind, String content) {
        encoder.addArchiveFile(
          ArchiveFile.string(p.posix.join(sourceName, path), content),
        );
        kitFiles.add(ReleaseKitFile(path, kind, fromStore: true));
        storedKeyCount++;
      }

      final appStore = storedKeys.appStore;
      final keyId = _trimmedOrNull(appStore?.keyId);
      final storedKeyName = 'AuthKey_${_safeSegment(keyId ?? 'AppStore')}.p8';
      if (storedKeys.hasAppStoreKey) {
        addStored(
          '$releaseKitStoreFolder/ios/$storedKeyName',
          ReleaseKitFileKind.appStoreKey,
          '${appStore!.p8PrivateKey!.trim()}\n',
        );
      }
      final projectKeyPath = _trimmedOrNull(storedKeys.projectAppStoreKeyPath);
      final projectKeyIncluded =
          projectKeyPath != null &&
          kitFiles.any((file) => file.path == projectKeyPath);
      if (storedKeys.hasAppStoreIds || storedKeys.hasAppStoreKey) {
        // IDs are not secrets, so the file is counted apart from stored keys.
        encoder.addArchiveFile(
          ArchiveFile.string(
            p.posix.join(
              sourceName,
              '$releaseKitStoreFolder/ios/app_store_connect.env',
            ),
            _appStoreConfigText(
              storedKeys,
              keyFile: storedKeys.hasAppStoreKey
                  ? storedKeyName
                  : projectKeyIncluded
                  ? projectKeyPath
                  : null,
              keyName: storedKeyName,
            ),
          ),
        );
        kitFiles.add(
          const ReleaseKitFile(
            '$releaseKitStoreFolder/ios/app_store_connect.env',
            ReleaseKitFileKind.appStoreConfig,
            fromStore: true,
          ),
        );
      }
      if (storedKeys.hasPlayServiceAccount) {
        addStored(
          '$releaseKitStoreFolder/android/google-play-service-account.json',
          ReleaseKitFileKind.playServiceAccount,
          '${storedKeys.playServiceAccountJson!.trim()}\n',
        );
      }
      final keystore = storedKeys.hasKeystore
          ? File(storedKeys.keystorePath!)
          : null;
      if (keystore != null && keystore.existsSync()) {
        final path =
            '$releaseKitStoreFolder/android/${_safeSegment(p.basename(keystore.path))}';
        encoder.addFileSync(keystore, p.posix.join(sourceName, path));
        kitFiles.add(
          ReleaseKitFile(path, ReleaseKitFileKind.keystore, fromStore: true),
        );
        storedKeyCount++;
        final credential = storedKeys.keystoreCredential;
        if (credential != null && credential.hasAnyCredential) {
          signingCredentials = [
            ...signingCredentials,
            SigningCredentialBundleEntry(
              relativePath: path,
              source: credential.source,
              keyAlias: credential.keyAlias,
              storePassword: credential.storePassword,
              keyPassword: credential.keyPassword,
            ),
          ];
        }
      }

      final credentials = signingCredentials
          .where((entry) => entry.hasAnyCredential)
          .toList();
      if (credentials.isNotEmpty) {
        encoder.addArchiveFile(
          ArchiveFile.string(
            p.posix.join(sourceName, 'signing_credentials.txt'),
            _credentialsText(credentials),
          ),
        );
        kitFiles.add(
          const ReleaseKitFile(
            'signing_credentials.txt',
            ReleaseKitFileKind.signingCredentials,
          ),
        );
        signingCredentialCount = credentials.length;
      }

      // Without a key.properties of its own, the kit gets one filled from
      // the first keystore whose alias and passwords are all known.
      final hasKeyProperties = kitFiles.any(
        (file) => p.posix.basename(file.path).toLowerCase() == 'key.properties',
      );
      final signing = credentials
          .where((entry) => entry.status == SigningCredentialStatus.resolved)
          .firstOrNull;
      if (!hasKeyProperties && signing != null) {
        const path = '$releaseKitStoreFolder/android/key.properties';
        encoder.addArchiveFile(
          ArchiveFile.string(
            p.posix.join(sourceName, path),
            _keyPropertiesText(signing, _storeFileBase(sourceRoot)),
          ),
        );
        kitFiles.add(
          const ReleaseKitFile(
            path,
            ReleaseKitFileKind.properties,
            fromStore: true,
          ),
        );
      }

      encoder.addArchiveFile(
        ArchiveFile.string(
          p.posix.join(sourceName, 'README.md'),
          buildReleaseKitReadme(
            projectName: sourceName,
            createdAt: createdAt,
            files: kitFiles,
            appStoreKeyId: keyId,
            appStoreIssuerId: _trimmedOrNull(appStore?.issuerId),
            appStoreTeamId: _trimmedOrNull(appStore?.teamId),
          ),
        ),
      );
    } finally {
      encoder.closeSync();
    }

    return _ZipSummary(
      fileCount: fileCount,
      signingCredentialCount: signingCredentialCount,
      storedKeyCount: storedKeyCount,
    );
  }

  /// Variable names match what the iOS scripts exported by AMC read.
  /// [keyFile] is where the .p8 sits in the kit, when it is there at all.
  String _appStoreConfigText(
    StoredReleaseKeys keys, {
    required String? keyFile,
    required String keyName,
  }) {
    final appStore = keys.appStore;
    final buffer = StringBuffer()
      ..writeln(
        '# App Store Connect API key${_hasValue(keys.bundleId) ? ' cho ${keys.bundleId!.trim()}' : ''}.',
      )
      ..writeln(
        '# AMC: card App Store -> Thông tin đăng nhập -> nhập .p8 và các ID dưới đây.',
      )
      ..writeln(
        '# Script iOS xuất từ AMC: đổi AMC_KEY_FILE thành đường dẫn tuyệt đối tới file .p8.',
      );
    if (keyFile == null) {
      buffer.writeln('# Gói không kèm file .p8; lấy từ người giữ key.');
    } else if (!keyFile.toLowerCase().endsWith('.p8')) {
      buffer.writeln(
        '# $keyFile có đuôi .txt thừa: vẫn dùng được, nên đổi tên thành $keyName.',
      );
    }
    for (final (name, value) in [
      ('AMC_KEY_ID', appStore?.keyId),
      ('AMC_ISSUER_ID', appStore?.issuerId),
    ]) {
      if (!_hasValue(value)) buffer.writeln('# Chưa có $name: điền tay.');
      buffer.writeln('$name=${_trimmedOrNull(value) ?? ''}');
    }
    buffer
      ..writeln('AMC_KEY_FILE=${keyFile ?? keyName}')
      ..writeln('APP_STORE_TEAM_ID=${_trimmedOrNull(appStore?.teamId) ?? ''}');
    if (_hasValue(keys.bundleId)) {
      buffer.writeln('APP_STORE_BUNDLE_ID=${keys.bundleId!.trim()}');
    }
    if (appStore?.inHouse ?? false) {
      buffer
        ..writeln(
          '# Key in-house (Enterprise): không dùng được cho TestFlight/App Store.',
        )
        ..writeln('APP_STORE_IN_HOUSE=true');
    }
    return buffer.toString();
  }

  /// Where Gradle resolves a relative storeFile: `android/app` in Flutter's
  /// template, `android` when the project reads it through rootProject.file.
  String _storeFileBase(String sourceRoot) {
    for (final name in const ['build.gradle', 'build.gradle.kts']) {
      final file = File(p.join(sourceRoot, 'android', 'app', name));
      if (!file.existsSync()) continue;
      final gradle = file.readAsStringSync();
      if (RegExp(r'file\(\s*keystoreProperties\[').hasMatch(gradle)) {
        return 'android/app';
      }
      if (gradle.contains('rootProject.file(') &&
          RegExp(r"""getProperty\(\s*["']storeFile""").hasMatch(gradle)) {
        return 'android';
      }
    }
    return 'android/app';
  }

  String _keyPropertiesText(SigningCredentialBundleEntry entry, String base) {
    final inStore = entry.relativePath.startsWith('$releaseKitStoreFolder/');
    final storeFile = inStore
        ? p.posix.basename(entry.relativePath)
        : p.posix.relative(entry.relativePath, from: base);
    final buffer = StringBuffer()
      ..writeln('# Tạo bởi AMC từ thông tin ký của ${entry.relativePath}.')
      ..writeln('# Chép vào android/key.properties. storeFile tính từ $base/.');
    if (inStore) {
      buffer.writeln(
        '# Chép keystore ${p.posix.basename(entry.relativePath)} vào $base/.',
      );
    }
    return (buffer
          ..writeln('storePassword=${entry.storePassword!.trim()}')
          ..writeln('keyPassword=${entry.keyPassword!.trim()}')
          ..writeln('keyAlias=${entry.keyAlias!.trim()}')
          ..writeln('storeFile=$storeFile'))
        .toString();
  }

  bool _hasValue(String? value) => _trimmedOrNull(value) != null;

  Future<void> _validateTarget({
    required Directory source,
    required Directory target,
  }) async {
    final targetPath = p.normalize(target.path);
    final sourcePath = p.normalize(source.path);
    if (_isSameOrInside(childPath: targetPath, parentPath: sourcePath)) {
      throw const ResourceExportException(
        'Chọn thư mục xuất nằm ngoài dự án nguồn.',
      );
    }
    if (_isInsideGitWorktree(targetPath)) {
      throw const ResourceExportException(
        'Chọn thư mục xuất nằm ngoài mọi git worktree.',
      );
    }
  }

  bool _isSameOrInside({
    required String childPath,
    required String parentPath,
  }) {
    final child = p.normalize(p.absolute(childPath));
    final parent = p.normalize(p.absolute(parentPath));
    if (child.toLowerCase() == parent.toLowerCase()) return true;
    return p.isWithin(parent, child);
  }

  bool _isInsideGitWorktree(String path) {
    var current = Directory(p.normalize(p.absolute(path)));
    while (true) {
      if (Directory(p.join(current.path, '.git')).existsSync() ||
          File(p.join(current.path, '.git')).existsSync()) {
        return true;
      }
      final parent = current.parent;
      if (parent.path == current.path) return false;
      current = parent;
    }
  }

  String _validateRelativePath(String relativePath) {
    if (relativePath.trim().isEmpty || p.isAbsolute(relativePath)) {
      throw ResourceExportException(
        'Đường dẫn tài nguyên không an toàn: $relativePath',
      );
    }
    final segments = p.posix.split(relativePath);
    if (segments.any((segment) => segment == '..' || segment.isEmpty)) {
      throw ResourceExportException(
        'Đường dẫn tài nguyên không an toàn: $relativePath',
      );
    }
    return segments.join('/');
  }

  String _credentialsText(List<SigningCredentialBundleEntry> entries) {
    final buffer = StringBuffer()
      ..writeln('Thông tin ký')
      ..writeln('Generated by App Management Center')
      ..writeln();
    for (final entry in entries) {
      buffer
        ..writeln('[${entry.relativePath}]')
        ..writeln('source=${entry.source.name}');
      final keyAlias = _trimmedOrNull(entry.keyAlias);
      final storePassword = _trimmedOrNull(entry.storePassword);
      final keyPassword = _trimmedOrNull(entry.keyPassword);
      if (keyAlias != null) buffer.writeln('keyAlias=$keyAlias');
      if (storePassword != null) buffer.writeln('storePassword=$storePassword');
      if (keyPassword != null) buffer.writeln('keyPassword=$keyPassword');
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _safeSegment(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    return sanitized.isEmpty ? 'resources' : sanitized;
  }

  String? _trimmedOrNull(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class ResourceExportException implements Exception {
  const ResourceExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ZipSummary {
  const _ZipSummary({
    required this.fileCount,
    required this.signingCredentialCount,
    required this.storedKeyCount,
  });

  final int fileCount;
  final int signingCredentialCount;
  final int storedKeyCount;
}
