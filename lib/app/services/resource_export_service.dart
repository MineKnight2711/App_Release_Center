import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:app_release_center/app/models/resource_collection.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

class ResourceExportService extends GetxService {
  Future<ResourceExportResult> export({
    required String sourceRoot,
    required String targetRoot,
    required List<ResourceFinding> findings,
    List<SigningCredentialBundleEntry> signingCredentials = const [],
  }) async {
    final source = Directory(p.normalize(sourceRoot));
    final target = Directory(p.normalize(targetRoot));
    if (!source.existsSync()) {
      throw FileSystemException(
        'Resource source directory does not exist.',
        source.path,
      );
    }
    await _validateTarget(source: source, target: target);
    if (findings.isEmpty) {
      throw const ResourceExportException('Select at least one resource file.');
    }

    await target.create(recursive: true);
    final sourceName = _safeSegment(p.basename(source.path));
    final zipFile = File(p.join(target.path, '$sourceName.zip'));
    if (zipFile.existsSync()) await zipFile.delete();

    final summary = await _zipResources(
      zipFile: zipFile,
      sourceName: sourceName,
      findings: findings,
      signingCredentials: signingCredentials,
    );
    if (summary.fileCount == 0) {
      throw const ResourceExportException(
        'Selected resource files no longer exist.',
      );
    }

    return ResourceExportResult(
      archivePath: zipFile.path,
      fileCount: summary.fileCount,
      signingCredentialCount: summary.signingCredentialCount,
    );
  }

  Future<_ZipSummary> _zipResources({
    required File zipFile,
    required String sourceName,
    required List<ResourceFinding> findings,
    required List<SigningCredentialBundleEntry> signingCredentials,
  }) async {
    final encoder = ZipFileEncoder()..create(zipFile.path);
    var fileCount = 0;
    var signingCredentialCount = 0;
    Directory? tempRoot;
    try {
      for (final finding in findings) {
        final relativePath = _validateRelativePath(finding.relativePath);
        final sourceFile = File(finding.sourcePath);
        if (!sourceFile.existsSync()) continue;
        encoder.addFileSync(sourceFile, p.posix.join(sourceName, relativePath));
        fileCount++;
      }

      final credentials = signingCredentials
          .where((entry) => entry.hasAnyCredential)
          .toList();
      if (credentials.isNotEmpty) {
        tempRoot = Directory.systemTemp.createTempSync(
          'arc_signing_credentials_',
        );
        final credentialsFile = File(
          p.join(tempRoot.path, 'signing_credentials.txt'),
        );
        await credentialsFile.writeAsString(_credentialsText(credentials));
        encoder.addFileSync(
          credentialsFile,
          p.posix.join(sourceName, 'signing_credentials.txt'),
        );
        signingCredentialCount = credentials.length;
      }
    } finally {
      encoder.closeSync();
      if (tempRoot != null && tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    }

    return _ZipSummary(
      fileCount: fileCount,
      signingCredentialCount: signingCredentialCount,
    );
  }

  Future<void> _validateTarget({
    required Directory source,
    required Directory target,
  }) async {
    final targetPath = p.normalize(target.path);
    final sourcePath = p.normalize(source.path);
    if (_isSameOrInside(childPath: targetPath, parentPath: sourcePath)) {
      throw const ResourceExportException(
        'Choose an export directory outside the source project.',
      );
    }
    if (_isInsideGitWorktree(targetPath)) {
      throw const ResourceExportException(
        'Choose an export directory outside any git worktree.',
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
      throw ResourceExportException('Unsafe resource path: $relativePath');
    }
    final segments = p.posix.split(relativePath);
    if (segments.any((segment) => segment == '..' || segment.isEmpty)) {
      throw ResourceExportException('Unsafe resource path: $relativePath');
    }
    return segments.join('/');
  }

  String _credentialsText(List<SigningCredentialBundleEntry> entries) {
    final buffer = StringBuffer()
      ..writeln('Signing credentials')
      ..writeln('Generated by App Release Center')
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
  });

  final int fileCount;
  final int signingCredentialCount;
}
