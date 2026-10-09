import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../models/bundle_check_models.dart';
import 'android_manifest.dart';
import 'bundle_zip.dart';
import 'elf_header.dart';
import 'env_file.dart';
import 'resource_table.dart';
import 'signing_certificate.dart';

class BundleInspectionException implements Exception {
  const BundleInspectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Firebase values the google-services Gradle plugin writes into resources.
const firebaseResourceNames = {
  'google_app_id',
  'project_id',
  'gcm_defaultSenderId',
  'google_api_key',
  'default_web_client_id',
  'google_storage_bucket',
};

/// Reads an AAB into [BundleFacts] — once, so every check works off the same
/// snapshot and none of them touches the file again.
class BundleInspector {
  const BundleInspector();

  static const _maxManifestBytes = 16 * 1024 * 1024;
  static const _maxResourcesBytes = 128 * 1024 * 1024;
  static const _maxLibAppBytes = 256 * 1024 * 1024;
  static const _maxNoticesBytes = 64 * 1024 * 1024;
  static const _maxSmallAssetBytes = 1024 * 1024;
  static const _maxScannedAssets = 600;
  static const _elfPrefixBytes = 16 * 1024;

  /// Just the manifest — enough to learn the package and pick a project before
  /// the full inspection, which needs that project's contract.
  Future<ManifestInfo> readManifest(String path) async {
    final BundleZip zip;
    try {
      zip = await BundleZip.open(path);
    } on BundleZipException catch (error) {
      throw BundleInspectionException(error.message);
    } on FileSystemException catch (error) {
      throw BundleInspectionException('Không mở được file: ${error.message}');
    }
    try {
      final entry = zip.entry('base/manifest/AndroidManifest.xml');
      if (entry == null) {
        throw BundleInspectionException(
          zip.contains('AndroidManifest.xml')
              ? 'Đây là APK, không phải AAB. Bản này mới kiểm AAB.'
              : 'Không có base/manifest/AndroidManifest.xml — không phải AAB.',
        );
      }
      return ManifestInfo.parse(
        await zip.read(entry, maxBytes: _maxManifestBytes),
      );
    } on BundleZipException catch (error) {
      throw BundleInspectionException(error.message);
    } on FormatException catch (error) {
      throw BundleInspectionException('Manifest hỏng: ${error.message}');
    } finally {
      await zip.close();
    }
  }

  /// Runs [inspect] on a background isolate: hashing 170 MB and scanning
  /// libapp.so would otherwise stall the UI for seconds.
  Future<BundleFacts> inspectInBackground(
    String path, {
    Set<String> nativeNeedles = const {},
  }) {
    return Isolate.run(() => inspect(path, nativeNeedles: nativeNeedles));
  }

  Future<BundleFacts> inspect(
    String path, {
    Set<String> nativeNeedles = const {},
  }) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw BundleInspectionException('Không tìm thấy file $path.');
    }

    final BundleZip zip;
    try {
      zip = await BundleZip.open(path);
    } on BundleZipException catch (error) {
      throw BundleInspectionException(error.message);
    } on FileSystemException catch (error) {
      throw BundleInspectionException('Không mở được file: ${error.message}');
    }

    try {
      final baseManifest = zip.entry('base/manifest/AndroidManifest.xml');
      if (baseManifest == null) {
        throw BundleInspectionException(
          zip.contains('AndroidManifest.xml')
              ? 'Đây là APK, không phải AAB. Bản này mới kiểm AAB.'
              : 'Không có base/manifest/AndroidManifest.xml — không phải AAB.',
        );
      }

      final manifest = ManifestInfo.parse(
        await zip.read(baseManifest, maxBytes: _maxManifestBytes),
      );
      final modules = _modules(zip);
      final (signer, signatureError) = await _signer(zip);
      final nativeLibraries = await _nativeLibraries(zip);
      final envFiles = await _envFiles(zip);

      final resourceNames = {
        ...firebaseResourceNames,
        for (final meta in manifest.metaData)
          if (meta.referenceName case final ref? when ref.startsWith('string/'))
            ref.substring('string/'.length),
      };
      final resources = zip.entry('base/resources.pb');
      final stringResources = resources == null
          ? const <String, String>{}
          : readStringResources(
              await zip.read(resources, maxBytes: _maxResourcesBytes),
              names: resourceNames,
            );

      final libApp = _preferredLibApp(zip);
      final nativeStringHits = <String, bool>{};
      final needles = nativeNeedles.where((n) => n.trim().isNotEmpty).toSet();
      if (libApp != null && needles.isNotEmpty) {
        final bytes = await zip.read(libApp, maxBytes: _maxLibAppBytes);
        for (final needle in needles) {
          nativeStringHits[needle] = containsText(bytes, needle);
        }
      }

      return BundleFacts(
        filePath: path,
        fileSize: zip.length,
        sha256: await _sha256(file),
        entryCount: zip.entries.length,
        modules: modules,
        hasBundleConfig: zip.contains('BundleConfig.pb'),
        manifest: manifest,
        signer: signer,
        signatureError: signatureError,
        nativeLibraries: nativeLibraries,
        hasLibFlutter: nativeLibraries.any(
          (library) => library.fileName == 'libflutter.so',
        ),
        libAppAbis: {
          for (final library in nativeLibraries)
            if (library.fileName == 'libapp.so') library.abi,
        },
        hasKernelBlob: zip.entries.any(
          (entry) => entry.name.endsWith('/flutter_assets/kernel_blob.bin'),
        ),
        flutterPackages: await _flutterPackages(zip),
        envFiles: envFiles,
        stringResources: stringResources,
        secretAssets: await _secretAssets(zip),
        nativeStringHits: nativeStringHits,
        hasR8Mapping: zip.contains(
          'BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map',
        ),
        hasNativeDebugSymbols: zip.entries.any(
          (entry) => entry.name.startsWith(
            'BUNDLE-METADATA/com.android.tools.build.debugsymbols/',
          ),
        ),
        estimatedArm64DownloadBytes: _estimateArm64(zip, modules),
      );
    } on BundleZipException catch (error) {
      throw BundleInspectionException(error.message);
    } on FormatException catch (error) {
      throw BundleInspectionException('Bundle hỏng: ${error.message}');
    } finally {
      await zip.close();
    }
  }

  static List<String> _modules(BundleZip zip) {
    final modules = <String>{};
    for (final entry in zip.entries) {
      final parts = entry.name.split('/');
      if (parts.length == 3 &&
          parts[1] == 'manifest' &&
          parts[2] == 'AndroidManifest.xml') {
        modules.add(parts[0]);
      }
    }
    return [if (modules.remove('base')) 'base', ...(modules.toList()..sort())];
  }

  static Future<(SigningCertificate?, String?)> _signer(BundleZip zip) async {
    final block = zip.entries
        .where(
          (entry) =>
              RegExp(r'^META-INF/[^/]+\.(RSA|EC|DSA)$').hasMatch(entry.name),
        )
        .firstOrNull;
    if (block == null) return (null, null);
    try {
      final bytes = await zip.read(block, maxBytes: 1024 * 1024);
      return (parsePkcs7SignerCertificate(bytes), null);
    } on FormatException catch (error) {
      return (null, 'Không đọc được ${block.name}: ${error.message}');
    } on BundleZipException catch (error) {
      return (null, error.message);
    }
  }

  static Future<List<NativeLibrary>> _nativeLibraries(BundleZip zip) async {
    final pattern = RegExp(r'^[^/]+/lib/([^/]+)/[^/]+\.so$');
    final libraries = <NativeLibrary>[];
    for (final entry in zip.entries) {
      final match = pattern.firstMatch(entry.name);
      if (match == null) continue;
      int? alignment;
      try {
        alignment = parseElfHeader(
          await zip.readPrefix(entry, _elfPrefixBytes),
        )?.minLoadAlignment;
      } on BundleZipException {
        alignment = null;
      }
      libraries.add(
        NativeLibrary(
          path: entry.name,
          abi: match.group(1)!,
          minLoadAlignment: alignment,
        ),
      );
    }
    return libraries;
  }

  static Future<List<BundledEnvFile>> _envFiles(BundleZip zip) async {
    final files = <BundledEnvFile>[];
    for (final entry in zip.entries) {
      final assetPath = _flutterAssetPath(entry.name);
      if (assetPath == null || entry.isDirectory) continue;
      final name = assetPath.split('/').last.toLowerCase();
      if (!name.startsWith('.env') && !name.endsWith('.env')) continue;
      final bytes = await zip.read(entry, maxBytes: _maxSmallAssetBytes);
      files.add(
        BundledEnvFile(
          assetPath: assetPath,
          values: parseEnvFile(utf8.decode(bytes, allowMalformed: true)),
        ),
      );
    }
    return files;
  }

  static Future<Set<String>?> _flutterPackages(BundleZip zip) async {
    final entry =
        zip.entry('base/assets/flutter_assets/NOTICES.Z') ??
        zip.entry('base/assets/flutter_assets/NOTICES');
    if (entry == null) return null;
    try {
      var bytes = await zip.read(entry, maxBytes: _maxNoticesBytes);
      if (entry.name.endsWith('.Z')) {
        bytes = boundedInflate(bytes, maxBytes: _maxNoticesBytes);
      }
      return parseNoticesPackages(utf8.decode(bytes, allowMalformed: true));
    } on BundleZipException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Future<List<String>> _secretAssets(BundleZip zip) async {
    const textExtensions = {
      '',
      'env',
      'json',
      'pem',
      'key',
      'txt',
      'properties',
      'xml',
      'yaml',
      'yml',
      'cfg',
      'conf',
      'ini',
    };
    final found = <String>[];
    var scanned = 0;
    for (final entry in zip.entries) {
      if (scanned >= _maxScannedAssets) break;
      if (entry.isDirectory ||
          entry.uncompressedSize > _maxSmallAssetBytes ||
          !RegExp(r'^[^/]+/(assets|root)/').hasMatch(entry.name)) {
        continue;
      }
      final name = entry.name.split('/').last;
      final dot = name.lastIndexOf('.');
      final extension = dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
      if (!textExtensions.contains(extension) && !name.startsWith('.env')) {
        continue;
      }
      scanned++;
      try {
        final text = latin1.decode(
          await zip.read(entry, maxBytes: _maxSmallAssetBytes),
        );
        if (looksLikeSecretFile(text)) found.add(entry.name);
      } on BundleZipException {
        continue;
      }
    }
    return found;
  }

  static BundleZipEntry? _preferredLibApp(BundleZip zip) {
    for (final abi in const ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86']) {
      final entry = zip.entry('base/lib/$abi/libapp.so');
      if (entry != null) return entry;
    }
    return zip.entries
        .where((entry) => entry.name.endsWith('/libapp.so'))
        .firstOrNull;
  }

  static int _estimateArm64(BundleZip zip, List<String> modules) {
    final libPattern = RegExp(r'^[^/]+/lib/([^/]+)/');
    var total = 0;
    for (final entry in zip.entries) {
      final module = entry.name.split('/').first;
      if (!modules.contains(module)) continue;
      final abi = libPattern.firstMatch(entry.name)?.group(1);
      if (abi != null && abi != 'arm64-v8a') continue;
      total += entry.compressedSize;
    }
    return total;
  }

  static Future<String> _sha256(File file) async {
    final digest = SHA256Digest();
    await for (final chunk in file.openRead()) {
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      digest.update(bytes, 0, bytes.length);
    }
    final out = Uint8List(digest.digestSize);
    digest.doFinal(out, 0);
    return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String? _flutterAssetPath(String entryName) {
    const marker = '/assets/flutter_assets/';
    final index = entryName.indexOf(marker);
    if (index < 0 || entryName.substring(0, index).contains('/')) return null;
    return entryName.substring(index + marker.length);
  }
}

/// Package names from Flutter's `NOTICES`: each license block opens with the
/// packages it covers, one per line, and blocks are split by a dashed rule.
Set<String> parseNoticesPackages(String notices) {
  final packages = <String>{};
  var atBlockStart = true;
  for (final rawLine in const LineSplitter().convert(notices)) {
    final line = rawLine.trim();
    if (RegExp(r'^-{20,}$').hasMatch(line)) {
      atBlockStart = true;
      continue;
    }
    if (!atBlockStart) continue;
    if (line.isEmpty) {
      atBlockStart = false;
      continue;
    }
    if (RegExp(r'^[A-Za-z0-9_.\-]+$').hasMatch(line)) packages.add(line);
  }
  return packages;
}

/// A private key or a service-account JSON — never belongs in an app.
bool looksLikeSecretFile(String text) {
  if (RegExp(
    r'^\s*-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----\s*$',
    multiLine: true,
  ).hasMatch(text)) {
    return true;
  }
  try {
    final value = jsonDecode(text);
    return value is Map &&
        value['type'] == 'service_account' &&
        value['private_key'] is String &&
        (value['private_key'] as String).trim().isNotEmpty;
  } on FormatException {
    return false;
  }
}

/// Whether [needle] occurs in [haystack] as Latin-1 or UTF-16LE text — the two
/// encodings the Dart AOT snapshot stores string literals in.
bool containsText(Uint8List haystack, String needle) {
  if (needle.isEmpty) return false;
  final codes = needle.codeUnits;
  if (codes.every((code) => code < 0x100) &&
      _indexOf(haystack, Uint8List.fromList(codes)) >= 0) {
    return true;
  }
  final wide = Uint8List(codes.length * 2);
  for (var i = 0; i < codes.length; i++) {
    wide[i * 2] = codes[i] & 0xff;
    wide[i * 2 + 1] = codes[i] >> 8;
  }
  return _indexOf(haystack, wide) >= 0;
}

int _indexOf(Uint8List haystack, Uint8List needle) {
  if (needle.isEmpty || needle.length > haystack.length) return -1;
  final first = needle[0];
  final last = haystack.length - needle.length;
  outer:
  for (var i = 0; i <= last; i++) {
    if (haystack[i] != first) continue;
    for (var j = 1; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// Inflates zlib or gzip [data], refusing to grow past [maxBytes].
Uint8List boundedInflate(Uint8List data, {required int maxBytes}) {
  final filter = RawZLibFilter.inflateFilter();
  final output = BytesBuilder(copy: false);
  void drain({bool end = false}) {
    List<int>? chunk;
    while ((chunk = filter.processed(flush: false, end: end)) != null) {
      output.add(chunk!);
      if (output.length > maxBytes) {
        throw FormatException('Giải nén vượt ${maxBytes ~/ (1024 * 1024)} MB.');
      }
    }
  }

  const step = 64 * 1024;
  for (var offset = 0; offset < data.length; offset += step) {
    filter.process(data, offset, math.min(offset + step, data.length));
    drain();
  }
  drain(end: true);
  return output.takeBytes();
}
