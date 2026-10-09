import '../services/android_manifest.dart';
import '../services/signing_certificate.dart';

enum CheckStatus { pass, info, warn, fail, skip }

extension CheckStatusLabel on CheckStatus {
  String get label => switch (this) {
    CheckStatus.pass => 'Đạt',
    CheckStatus.info => 'Thông tin',
    CheckStatus.warn => 'Cảnh báo',
    CheckStatus.fail => 'Lỗi',
    CheckStatus.skip => 'Bỏ qua',
  };
}

enum CheckGroup { build, env, run }

extension CheckGroupLabel on CheckGroup {
  String get label => switch (this) {
    CheckGroup.build => 'Build đúng không',
    CheckGroup.env => 'Đủ env không',
    CheckGroup.run => 'Chạy được không',
  };
}

/// The verdict of one check. [skip] always carries the reason in [detail], so
/// nobody reads a skipped check as a passed one.
class CheckResult {
  const CheckResult({
    required this.id,
    required this.group,
    required this.status,
    required this.title,
    this.detail = '',
    this.hint = '',
    this.items = const [],
  });

  final String id;
  final CheckGroup group;
  final CheckStatus status;
  final String title;
  final String detail;
  final String hint;

  /// Specifics too long for [detail]: offending libraries, missing keys.
  final List<String> items;

  Map<String, Object?> toJson() => {
    'id': id,
    'group': group.name,
    'status': status.name,
    'title': title,
    'detail': detail,
    'hint': hint,
    'items': items,
  };

  factory CheckResult.fromJson(Map<String, Object?> json) {
    return CheckResult(
      id: json['id'] as String? ?? '',
      group: CheckGroup.values.asNameMap()[json['group']] ?? CheckGroup.build,
      status:
          CheckStatus.values.asNameMap()[json['status']] ?? CheckStatus.info,
      title: json['title'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      hint: json['hint'] as String? ?? '',
      items: [for (final item in (json['items'] as List?) ?? const []) '$item'],
    );
  }
}

class NativeLibrary {
  const NativeLibrary({
    required this.path,
    required this.abi,
    this.minLoadAlignment,
  });

  final String path;
  final String abi;

  /// Smallest `p_align` over the `PT_LOAD` segments; null when unreadable.
  final int? minLoadAlignment;

  String get fileName => path.split('/').last;

  bool get is64BitAbi => abi == 'arm64-v8a' || abi == 'x86_64';
}

/// An env file shipped inside the bundle. [values] are the real values; they
/// stay in memory and are masked before anything is shown or saved.
class BundledEnvFile {
  const BundledEnvFile({required this.assetPath, required this.values});

  /// Path relative to `flutter_assets/`, e.g. `.env`.
  final String assetPath;
  final Map<String, String> values;
}

/// Everything read out of the bundle, once, before any check runs.
class BundleFacts {
  const BundleFacts({
    required this.filePath,
    required this.fileSize,
    required this.sha256,
    required this.entryCount,
    required this.modules,
    required this.hasBundleConfig,
    required this.manifest,
    required this.signer,
    required this.signatureError,
    required this.nativeLibraries,
    required this.hasLibFlutter,
    required this.libAppAbis,
    required this.hasKernelBlob,
    required this.flutterPackages,
    required this.envFiles,
    required this.stringResources,
    required this.secretAssets,
    required this.nativeStringHits,
    required this.hasR8Mapping,
    required this.hasNativeDebugSymbols,
    required this.estimatedArm64DownloadBytes,
  });

  final String filePath;
  final int fileSize;
  final String sha256;
  final int entryCount;

  /// Feature modules, `base` first.
  final List<String> modules;
  final bool hasBundleConfig;
  final ManifestInfo manifest;
  final SigningCertificate? signer;
  final String? signatureError;
  final List<NativeLibrary> nativeLibraries;
  final bool hasLibFlutter;
  final Set<String> libAppAbis;
  final bool hasKernelBlob;

  /// Dart/Flutter packages named in `NOTICES.Z`; null when it is absent.
  final Set<String>? flutterPackages;
  final List<BundledEnvFile> envFiles;

  /// String resources the checks asked for, e.g. `project_id`.
  final Map<String, String> stringResources;

  /// Asset paths that look like a private key or service-account JSON.
  final List<String> secretAssets;

  /// For each string the checks asked about: is it compiled into libapp.so?
  final Map<String, bool> nativeStringHits;
  final bool hasR8Mapping;
  final bool hasNativeDebugSymbols;
  final int estimatedArm64DownloadBytes;

  Set<String> get abis => {for (final library in nativeLibraries) library.abi};

  bool get isFlutter => hasLibFlutter || libAppAbis.isNotEmpty;
}

/// A project the bundle was matched to, with what it says the bundle should be.
class BundleProjectContext {
  const BundleProjectContext({
    required this.name,
    required this.path,
    this.applicationId,
    this.pubspecVersionName,
    this.pubspecVersionCode,
    this.storeVersionCode,
  });

  final String name;
  final String path;
  final String? applicationId;
  final String? pubspecVersionName;
  final int? pubspecVersionCode;

  /// Highest version code on CH Play, when checked in this session.
  final int? storeVersionCode;
}

/// Which key the bundle should be signed with, and how we know.
class SignerExpectation {
  const SignerExpectation({this.sha256, this.source = '', this.lookupError});

  final String? sha256;

  /// Where [sha256] came from, for the report to say.
  final String source;

  /// Why reading the keystore failed, when it did.
  final String? lookupError;
}

/// What the project says the bundle's env must contain.
class EnvContract {
  const EnvContract({
    this.projectLinked = false,
    this.usesDotenv = false,
    this.envFileNames = const [],
    this.requiredKeys = const [],
    this.optionalKeys = const [],
    this.keySources = const {},
    this.envValueFingerprints = const {},
    this.usesFirebase = false,
    this.firebaseCandidates = const {},
    this.expectedFirebaseProjectId,
    this.requiredStrings = const [],
    this.forbiddenStrings = const [],
    this.sources = const [],
  });

  /// Derived from a project's sources, rather than empty for lack of one.
  final bool projectLinked;
  final bool usesDotenv;

  /// Env assets the code loads, e.g. `.env`. Empty with [projectLinked]
  /// means the code never calls `dotenv.load`.
  final List<String> envFileNames;

  /// Missing, empty or placeholder → fail.
  final List<String> requiredKeys;

  /// Read by code that tolerates null, or only declared in the project's own
  /// `.env` → missing is a warning.
  final List<String> optionalKeys;

  /// Why each key is expected, e.g. `dotenv.get` or `.env.example`.
  final Map<String, String> keySources;

  /// In-memory comparison with the project's actual env; never serialized.
  final Map<String, String> envValueFingerprints;
  final bool usesFirebase;

  /// Every Firebase project id the project's config mentions, with where.
  final Map<String, String> firebaseCandidates;
  final String? expectedFirebaseProjectId;

  /// Must appear in libapp.so, e.g. the production API host.
  final List<String> requiredStrings;

  /// Must not appear anywhere, e.g. a staging host.
  final List<String> forbiddenStrings;

  /// How the contract was derived, one line per source.
  final List<String> sources;

  bool get isEmpty =>
      !usesDotenv &&
      requiredKeys.isEmpty &&
      optionalKeys.isEmpty &&
      !usesFirebase &&
      requiredStrings.isEmpty &&
      forbiddenStrings.isEmpty;

  /// Strings the inspector must look for inside libapp.so.
  Set<String> get nativeNeedles => {
    ...firebaseCandidates.keys,
    ?expectedFirebaseProjectId,
    ...requiredStrings,
    ...forbiddenStrings,
  };

  EnvContract withOverride(EnvContractOverride? override) {
    if (override == null) return this;
    final ignored = override.ignoredKeys.toSet();
    final required = {
      ...requiredKeys,
      ...override.extraRequiredKeys,
    }.where((key) => !ignored.contains(key)).toList();
    return EnvContract(
      projectLinked: projectLinked,
      usesDotenv: usesDotenv,
      envFileNames: envFileNames,
      requiredKeys: required,
      optionalKeys: optionalKeys
          .where((key) => !ignored.contains(key) && !required.contains(key))
          .toList(),
      keySources: {
        ...keySources,
        for (final key in override.extraRequiredKeys) key: 'chỉnh tay',
      },
      envValueFingerprints: envValueFingerprints,
      usesFirebase: usesFirebase,
      firebaseCandidates: firebaseCandidates,
      expectedFirebaseProjectId:
          override.expectedFirebaseProjectId?.trim().isNotEmpty == true
          ? override.expectedFirebaseProjectId!.trim()
          : expectedFirebaseProjectId,
      requiredStrings: {
        ...requiredStrings,
        ...override.requiredStrings,
      }.toList(),
      forbiddenStrings: {
        ...forbiddenStrings,
        ...override.forbiddenStrings,
      }.toList(),
      sources: [...sources, if (!override.isEmpty) 'Chỉnh tay trong AMC'],
    );
  }
}

/// What the user changed on top of the derived contract, per package.
class EnvContractOverride {
  const EnvContractOverride({
    this.extraRequiredKeys = const [],
    this.ignoredKeys = const [],
    this.expectedFirebaseProjectId,
    this.requiredStrings = const [],
    this.forbiddenStrings = const [],
    this.pinnedSignerSha256,
  });

  final List<String> extraRequiredKeys;
  final List<String> ignoredKeys;
  final String? expectedFirebaseProjectId;
  final List<String> requiredStrings;
  final List<String> forbiddenStrings;

  /// Accepted as the right upload key, via "Ghim chữ ký này".
  final String? pinnedSignerSha256;

  bool get isEmpty =>
      extraRequiredKeys.isEmpty &&
      ignoredKeys.isEmpty &&
      (expectedFirebaseProjectId?.trim().isEmpty ?? true) &&
      requiredStrings.isEmpty &&
      forbiddenStrings.isEmpty;

  EnvContractOverride copyWith({
    List<String>? extraRequiredKeys,
    List<String>? ignoredKeys,
    String? expectedFirebaseProjectId,
    List<String>? requiredStrings,
    List<String>? forbiddenStrings,
    String? pinnedSignerSha256,
    bool clearPinnedSigner = false,
  }) {
    return EnvContractOverride(
      extraRequiredKeys: extraRequiredKeys ?? this.extraRequiredKeys,
      ignoredKeys: ignoredKeys ?? this.ignoredKeys,
      expectedFirebaseProjectId:
          expectedFirebaseProjectId ?? this.expectedFirebaseProjectId,
      requiredStrings: requiredStrings ?? this.requiredStrings,
      forbiddenStrings: forbiddenStrings ?? this.forbiddenStrings,
      pinnedSignerSha256: clearPinnedSigner
          ? null
          : pinnedSignerSha256 ?? this.pinnedSignerSha256,
    );
  }

  Map<String, Object?> toJson() => {
    'extraRequiredKeys': extraRequiredKeys,
    'ignoredKeys': ignoredKeys,
    'expectedFirebaseProjectId': expectedFirebaseProjectId,
    'requiredStrings': requiredStrings,
    'forbiddenStrings': forbiddenStrings,
    'pinnedSignerSha256': pinnedSignerSha256,
  };

  factory EnvContractOverride.fromJson(Map<String, Object?> json) {
    List<String> strings(String key) => [
      for (final value in (json[key] as List?) ?? const [])
        if ('$value'.trim().isNotEmpty) '$value'.trim(),
    ];
    return EnvContractOverride(
      extraRequiredKeys: strings('extraRequiredKeys'),
      ignoredKeys: strings('ignoredKeys'),
      expectedFirebaseProjectId: json['expectedFirebaseProjectId'] as String?,
      requiredStrings: strings('requiredStrings'),
      forbiddenStrings: strings('forbiddenStrings'),
      pinnedSignerSha256: json['pinnedSignerSha256'] as String?,
    );
  }
}

/// One finished check, as shown in the history and saved to `report.json`.
///
/// Holds no env values: whatever needs one shows it masked in [results].
class BundleCheckReport {
  const BundleCheckReport({
    required this.id,
    required this.createdAt,
    required this.sourcePath,
    required this.fileName,
    required this.fileSize,
    required this.sha256,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.minSdk,
    required this.targetSdk,
    required this.permissions,
    required this.abis,
    required this.estimatedArm64DownloadBytes,
    required this.results,
    this.signer,
    this.projectName,
    this.projectPath,
    this.durationMs = 0,
    this.launcherActivity,
    this.deviceRun,
  });

  final String id;
  final DateTime createdAt;
  final String sourcePath;
  final String fileName;
  final int fileSize;
  final String sha256;
  final String packageName;
  final String? versionName;
  final int? versionCode;
  final int? minSdk;
  final int? targetSdk;
  final List<String> permissions;
  final List<String> abis;
  final int estimatedArm64DownloadBytes;
  final List<CheckResult> results;
  final SigningCertificate? signer;
  final String? projectName;
  final String? projectPath;
  final int durationMs;

  /// From the manifest; the device run launches it directly.
  final String? launcherActivity;

  /// The last time this bundle was installed and opened on a device.
  final DeviceRunSummary? deviceRun;

  /// The same report with the "runs" group replaced by [runResults].
  BundleCheckReport withDeviceRun(
    List<CheckResult> runResults,
    DeviceRunSummary summary,
  ) {
    return BundleCheckReport(
      id: id,
      createdAt: createdAt,
      sourcePath: sourcePath,
      fileName: fileName,
      fileSize: fileSize,
      sha256: sha256,
      packageName: packageName,
      versionName: versionName,
      versionCode: versionCode,
      minSdk: minSdk,
      targetSdk: targetSdk,
      permissions: permissions,
      abis: abis,
      estimatedArm64DownloadBytes: estimatedArm64DownloadBytes,
      results: [
        ...results.where((result) => result.group != CheckGroup.run),
        ...runResults,
      ],
      signer: signer,
      projectName: projectName,
      projectPath: projectPath,
      durationMs: durationMs,
      launcherActivity: launcherActivity,
      deviceRun: summary,
    );
  }

  int count(CheckStatus status) =>
      results.where((result) => result.status == status).length;

  CheckStatus get overall {
    if (count(CheckStatus.fail) > 0) return CheckStatus.fail;
    if (count(CheckStatus.warn) > 0) return CheckStatus.warn;
    return CheckStatus.pass;
  }

  String get versionLabel => '${versionName ?? '?'}+${versionCode ?? '?'}';

  Iterable<CheckResult> inGroup(CheckGroup group) =>
      results.where((result) => result.group == group);

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'sourcePath': sourcePath,
    'fileName': fileName,
    'fileSize': fileSize,
    'sha256': sha256,
    'packageName': packageName,
    'versionName': versionName,
    'versionCode': versionCode,
    'minSdk': minSdk,
    'targetSdk': targetSdk,
    'permissions': permissions,
    'abis': abis,
    'estimatedArm64DownloadBytes': estimatedArm64DownloadBytes,
    'results': [for (final result in results) result.toJson()],
    'signer': signer?.toJson(),
    'projectName': projectName,
    'projectPath': projectPath,
    'durationMs': durationMs,
    'launcherActivity': launcherActivity,
    'deviceRun': deviceRun?.toJson(),
  };

  factory BundleCheckReport.fromJson(Map<String, Object?> json) {
    final signer = json['signer'];
    return BundleCheckReport(
      id: json['id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourcePath: json['sourcePath'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String? ?? '',
      packageName: json['packageName'] as String? ?? '',
      versionName: json['versionName'] as String?,
      versionCode: (json['versionCode'] as num?)?.toInt(),
      minSdk: (json['minSdk'] as num?)?.toInt(),
      targetSdk: (json['targetSdk'] as num?)?.toInt(),
      permissions: [
        for (final value in (json['permissions'] as List?) ?? const [])
          '$value',
      ],
      abis: [for (final value in (json['abis'] as List?) ?? const []) '$value'],
      estimatedArm64DownloadBytes:
          (json['estimatedArm64DownloadBytes'] as num?)?.toInt() ?? 0,
      results: [
        for (final value in (json['results'] as List?) ?? const [])
          if (value is Map)
            CheckResult.fromJson(Map<String, Object?>.from(value)),
      ],
      signer: signer is Map
          ? SigningCertificate.fromJson(Map<String, Object?>.from(signer))
          : null,
      projectName: json['projectName'] as String?,
      projectPath: json['projectPath'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      launcherActivity: json['launcherActivity'] as String?,
      deviceRun: json['deviceRun'] is Map
          ? DeviceRunSummary.fromJson(
              Map<String, Object?>.from(json['deviceRun'] as Map),
            )
          : null,
    );
  }
}

/// The device-run choices remembered between sessions.
class DeviceRunPreferences {
  const DeviceRunPreferences({
    this.targetKey,
    this.watchSeconds = 20,
    this.uninstallAfter = false,
  });

  /// AVD name or device serial.
  final String? targetKey;
  final int watchSeconds;
  final bool uninstallAfter;

  DeviceRunPreferences copyWith({
    String? targetKey,
    int? watchSeconds,
    bool? uninstallAfter,
  }) {
    return DeviceRunPreferences(
      targetKey: targetKey ?? this.targetKey,
      watchSeconds: watchSeconds ?? this.watchSeconds,
      uninstallAfter: uninstallAfter ?? this.uninstallAfter,
    );
  }

  Map<String, Object?> toJson() => {
    'targetKey': targetKey,
    'watchSeconds': watchSeconds,
    'uninstallAfter': uninstallAfter,
  };

  factory DeviceRunPreferences.fromJson(Map<String, Object?> json) {
    final seconds = (json['watchSeconds'] as num?)?.toInt() ?? 20;
    return DeviceRunPreferences(
      targetKey: json['targetKey'] as String?,
      watchSeconds: seconds.clamp(5, 300),
      uninstallAfter: json['uninstallAfter'] as bool? ?? false,
    );
  }
}

/// Where and how a bundle was last run, and what the run left behind in the
/// job folder.
class DeviceRunSummary {
  const DeviceRunSummary({
    required this.deviceLabel,
    required this.serial,
    required this.startedAt,
    required this.durationMs,
    this.coldStartMs,
    this.screenshots = const [],
    this.logcatFile,
    this.signedWith = '',
  });

  final String deviceLabel;
  final String serial;
  final DateTime startedAt;
  final int durationMs;
  final int? coldStartMs;

  /// File names inside the job folder, oldest first.
  final List<String> screenshots;
  final String? logcatFile;

  /// Which key the installed APKs were signed with.
  final String signedWith;

  Map<String, Object?> toJson() => {
    'deviceLabel': deviceLabel,
    'serial': serial,
    'startedAt': startedAt.toIso8601String(),
    'durationMs': durationMs,
    'coldStartMs': coldStartMs,
    'screenshots': screenshots,
    'logcatFile': logcatFile,
    'signedWith': signedWith,
  };

  factory DeviceRunSummary.fromJson(Map<String, Object?> json) {
    return DeviceRunSummary(
      deviceLabel: json['deviceLabel'] as String? ?? '',
      serial: json['serial'] as String? ?? '',
      startedAt:
          DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      coldStartMs: (json['coldStartMs'] as num?)?.toInt(),
      screenshots: [
        for (final value in (json['screenshots'] as List?) ?? const [])
          '$value',
      ],
      logcatFile: json['logcatFile'] as String?,
      signedWith: json['signedWith'] as String? ?? '',
    );
  }
}

/// Shows enough of a value to recognise it, never enough to reuse it.
///
/// URLs keep their scheme and host — those identify the environment and are
/// not secret — and lose the path and query, where tokens tend to live.
String maskValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '(rỗng)';
  final uri = Uri.tryParse(trimmed);
  if (uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    final rest = uri.path.length > 1 || uri.hasQuery ? '/…' : '';
    return '${uri.scheme}://${uri.host}$port$rest';
  }
  if (trimmed.length <= 6) return '•' * trimmed.length;
  return '${trimmed.substring(0, 2)}••••${trimmed.substring(trimmed.length - 2)}';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
