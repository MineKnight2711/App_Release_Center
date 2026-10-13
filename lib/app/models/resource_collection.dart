import 'package:app_management_center/app/models/app_store_credentials.dart';

/// [release] gathers everything a release machine needs, keys included.
enum ResourceCollectionPreset { release, allRecommended, envOnly, custom }

enum ResourceTargetKind {
  envFile,
  properties,
  fastlaneServiceAccount,
  signingKey,
  appStoreKey,
}

enum SigningCredentialSource { secureStore, projectFile, manual }

enum SigningCredentialStatus { resolved, partial, missing }

const resourceRecommendedTargetKinds = {
  ResourceTargetKind.envFile,
  ResourceTargetKind.properties,
  ResourceTargetKind.fastlaneServiceAccount,
};

class ResourceCollectionSettings {
  const ResourceCollectionSettings({
    this.sourcePath = '',
    this.targetPath = '',
    this.preset = ResourceCollectionPreset.allRecommended,
    this.customKinds = resourceRecommendedTargetKinds,
    this.includeSigningCredentials = true,
    this.includeStoredKeys = true,
  });

  final String sourcePath;
  final String targetPath;
  final ResourceCollectionPreset preset;
  final Set<ResourceTargetKind> customKinds;
  final bool includeSigningCredentials;

  /// Adds keys kept in AMC's secure store, such as the App Store .p8.
  final bool includeStoredKeys;

  Set<ResourceTargetKind> get activeKinds {
    return switch (preset) {
      ResourceCollectionPreset.release => ResourceTargetKind.values.toSet(),
      ResourceCollectionPreset.allRecommended => resourceRecommendedTargetKinds,
      ResourceCollectionPreset.envOnly => {ResourceTargetKind.envFile},
      ResourceCollectionPreset.custom => customKinds,
    };
  }

  ResourceCollectionSettings copyWith({
    String? sourcePath,
    String? targetPath,
    ResourceCollectionPreset? preset,
    Set<ResourceTargetKind>? customKinds,
    bool? includeSigningCredentials,
    bool? includeStoredKeys,
  }) {
    return ResourceCollectionSettings(
      sourcePath: sourcePath ?? this.sourcePath,
      targetPath: targetPath ?? this.targetPath,
      preset: preset ?? this.preset,
      customKinds: customKinds ?? this.customKinds,
      includeSigningCredentials:
          includeSigningCredentials ?? this.includeSigningCredentials,
      includeStoredKeys: includeStoredKeys ?? this.includeStoredKeys,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'sourcePath': sourcePath,
      'targetPath': targetPath,
      'preset': preset.name,
      'customKinds': customKinds.map((kind) => kind.name).toList(),
      'includeSigningCredentials': includeSigningCredentials,
      'includeStoredKeys': includeStoredKeys,
    };
  }

  factory ResourceCollectionSettings.fromJson(Map<String, Object?> json) {
    return ResourceCollectionSettings(
      sourcePath: json['sourcePath']?.toString() ?? '',
      targetPath: json['targetPath']?.toString() ?? '',
      preset: _enumByName(
        ResourceCollectionPreset.values,
        json['preset'],
        ResourceCollectionPreset.allRecommended,
      ),
      customKinds: _kindSet(json['customKinds']),
      includeSigningCredentials: json['includeSigningCredentials'] != false,
      includeStoredKeys: json['includeStoredKeys'] != false,
    );
  }
}

class ResourceFinding {
  const ResourceFinding({
    required this.sourcePath,
    required this.relativePath,
    required this.kind,
    required this.sizeBytes,
    required this.modifiedAt,
    this.detectedKeyNames = const [],
    this.maskedPreview = const [],
    this.isBinary = false,
    this.signingCredentialStatus,
    this.signingCredentialSource,
    this.signingCredentialMaskedPreview = const [],
  });

  final String sourcePath;
  final String relativePath;
  final ResourceTargetKind kind;
  final int sizeBytes;
  final DateTime modifiedAt;
  final List<String> detectedKeyNames;
  final List<String> maskedPreview;
  final bool isBinary;
  final SigningCredentialStatus? signingCredentialStatus;
  final SigningCredentialSource? signingCredentialSource;
  final List<String> signingCredentialMaskedPreview;

  String get id => sourcePath;

  ResourceFinding withSigningCredential(SigningCredentialBundleEntry? entry) {
    return ResourceFinding(
      sourcePath: sourcePath,
      relativePath: relativePath,
      kind: kind,
      sizeBytes: sizeBytes,
      modifiedAt: modifiedAt,
      detectedKeyNames: detectedKeyNames,
      maskedPreview: maskedPreview,
      isBinary: isBinary,
      signingCredentialStatus: entry?.status,
      signingCredentialSource: entry?.source,
      signingCredentialMaskedPreview: entry?.maskedPreview ?? const [],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'sourcePath': sourcePath,
      'relativePath': relativePath,
      'kind': kind.name,
      'sizeBytes': sizeBytes,
      'modifiedAt': modifiedAt.toUtc().toIso8601String(),
      'detectedKeyNames': detectedKeyNames,
      'isBinary': isBinary,
      if (signingCredentialStatus != null)
        'signingCredentialStatus': signingCredentialStatus!.name,
      if (signingCredentialSource != null)
        'signingCredentialSource': signingCredentialSource!.name,
    };
  }
}

class SigningCredentialBundleEntry {
  const SigningCredentialBundleEntry({
    required this.relativePath,
    required this.source,
    this.keyAlias,
    this.storePassword,
    this.keyPassword,
    this.maskedPreview = const [],
  });

  final String relativePath;
  final SigningCredentialSource source;
  final String? keyAlias;
  final String? storePassword;
  final String? keyPassword;
  final List<String> maskedPreview;

  bool get hasKeyAlias => _hasText(keyAlias);
  bool get hasStorePassword => _hasText(storePassword);
  bool get hasKeyPassword => _hasText(keyPassword);

  bool get hasAnyCredential {
    return hasKeyAlias || hasStorePassword || hasKeyPassword;
  }

  SigningCredentialStatus get status {
    if (hasKeyAlias && hasStorePassword && hasKeyPassword) {
      return SigningCredentialStatus.resolved;
    }
    return hasAnyCredential
        ? SigningCredentialStatus.partial
        : SigningCredentialStatus.missing;
  }
}

/// Release keys AMC keeps in its secure store instead of the project folder.
class StoredReleaseKeys {
  const StoredReleaseKeys({
    this.appStore,
    this.bundleId,
    this.projectAppStoreKeyPath,
    this.playServiceAccountJson,
    this.keystorePath,
    this.keystoreCredential,
  });

  /// App Store Connect key IDs, with the .p8 only when the project does not
  /// already hold the same key.
  final AppStoreCredentials? appStore;
  final String? bundleId;

  /// The project's own .p8, relative to the project, when the scan found one.
  final String? projectAppStoreKeyPath;
  final String? playServiceAccountJson;

  /// A keystore configured for CH Play that lives outside the project.
  final String? keystorePath;
  final SigningCredentialBundleEntry? keystoreCredential;

  bool get hasAppStoreKey => appStore?.hasP8PrivateKey ?? false;
  bool get hasAppStoreIds =>
      (appStore?.hasKeyId ?? false) ||
      (appStore?.hasIssuerId ?? false) ||
      (appStore?.hasTeamId ?? false);
  bool get hasPlayServiceAccount => _hasText(playServiceAccountJson);
  bool get hasKeystore => _hasText(keystorePath);
  bool get isEmpty =>
      !hasAppStoreKey &&
      !hasAppStoreIds &&
      !hasPlayServiceAccount &&
      !hasKeystore;

  /// Secret files from the secure store, which the export option controls.
  bool get hasStoredSecrets =>
      hasAppStoreKey || hasPlayServiceAccount || hasKeystore;

  /// Short names of the secret files the export option would add.
  List<String> get labels => [
    if (hasAppStoreKey)
      '.p8 App Store${_hasText(appStore?.keyId) ? ' (${appStore!.keyId!.trim()})' : ''}',
    if (hasPlayServiceAccount) 'service account CH Play',
    if (hasKeystore) 'keystore ${keystorePath!.split(RegExp(r'[\\/]')).last}',
  ];

  /// Which App Store key IDs the kit carries, missing ones marked ✗.
  String get appStoreIdSummary {
    String part(String label, String? value, {bool show = true}) =>
        _hasText(value)
        ? (show ? '$label ${value!.trim()}' : '$label ✓')
        : '$label ✗';
    return [
      part('Key ID', appStore?.keyId),
      part('Issuer ID', appStore?.issuerId, show: false),
      part('Team ID', appStore?.teamId),
    ].join(' · ');
  }
}

class ResourceExportResult {
  const ResourceExportResult({
    required this.archivePath,
    required this.fileCount,
    required this.signingCredentialCount,
    this.storedKeyCount = 0,
    this.guidePath,
  });

  final String archivePath;
  final int fileCount;
  final int signingCredentialCount;

  /// Files written from AMC's secure store.
  final int storedKeyCount;

  /// Plain README next to a password-locked zip saying how to open it.
  final String? guidePath;

  bool get isLocked => guidePath != null;
}

extension ResourceCollectionPresetText on ResourceCollectionPreset {
  String get label {
    return switch (this) {
      ResourceCollectionPreset.release => 'Release',
      ResourceCollectionPreset.allRecommended => 'Tất cả',
      ResourceCollectionPreset.envOnly => '.env',
      ResourceCollectionPreset.custom => 'Tuỳ chọn',
    };
  }
}

extension ResourceTargetKindText on ResourceTargetKind {
  String get label {
    return switch (this) {
      ResourceTargetKind.envFile => 'File env',
      ResourceTargetKind.properties => 'File properties',
      ResourceTargetKind.fastlaneServiceAccount => 'Service account',
      ResourceTargetKind.signingKey => 'Key ký',
      ResourceTargetKind.appStoreKey => 'Key App Store',
    };
  }
}

extension SigningCredentialSourceText on SigningCredentialSource {
  String get label {
    return switch (this) {
      SigningCredentialSource.secureStore => 'Kho an toàn',
      SigningCredentialSource.projectFile => 'File trong dự án',
      SigningCredentialSource.manual => 'Nhập tay',
    };
  }
}

extension SigningCredentialStatusText on SigningCredentialStatus {
  String get label {
    return switch (this) {
      SigningCredentialStatus.resolved => 'Đủ',
      SigningCredentialStatus.partial => 'Thiếu một phần',
      SigningCredentialStatus.missing => 'Thiếu',
    };
  }
}

T _enumByName<T extends Enum>(List<T> values, Object? value, T fallback) {
  final name = value?.toString();
  for (final entry in values) {
    if (entry.name == name) return entry;
  }
  return fallback;
}

Set<ResourceTargetKind> _kindSet(Object? value) {
  final names = _stringList(value).toSet();
  final kinds = ResourceTargetKind.values
      .where((kind) => names.contains(kind.name))
      .toSet();
  return kinds.isEmpty ? resourceRecommendedTargetKinds : kinds;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((entry) => entry.toString()).toList();
}

bool _hasText(String? value) {
  return value != null && value.trim().isNotEmpty;
}
