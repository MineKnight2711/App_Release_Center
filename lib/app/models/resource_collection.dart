enum ResourceCollectionPreset { allRecommended, envOnly, custom }

enum ResourceTargetKind {
  envFile,
  properties,
  fastlaneServiceAccount,
  firebaseConfig,
  signingKey,
  appStoreKey,
}

enum SigningCredentialSource { secureStore, projectFile, manual }

enum SigningCredentialStatus { resolved, partial, missing }

const resourceRecommendedTargetKinds = {
  ResourceTargetKind.envFile,
  ResourceTargetKind.properties,
  ResourceTargetKind.fastlaneServiceAccount,
  ResourceTargetKind.firebaseConfig,
};

class ResourceCollectionSettings {
  const ResourceCollectionSettings({
    this.sourcePath = '',
    this.targetPath = '',
    this.preset = ResourceCollectionPreset.allRecommended,
    this.customKinds = resourceRecommendedTargetKinds,
    this.includeSigningCredentials = true,
  });

  final String sourcePath;
  final String targetPath;
  final ResourceCollectionPreset preset;
  final Set<ResourceTargetKind> customKinds;
  final bool includeSigningCredentials;

  Set<ResourceTargetKind> get activeKinds {
    return switch (preset) {
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
  }) {
    return ResourceCollectionSettings(
      sourcePath: sourcePath ?? this.sourcePath,
      targetPath: targetPath ?? this.targetPath,
      preset: preset ?? this.preset,
      customKinds: customKinds ?? this.customKinds,
      includeSigningCredentials:
          includeSigningCredentials ?? this.includeSigningCredentials,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'sourcePath': sourcePath,
      'targetPath': targetPath,
      'preset': preset.name,
      'customKinds': customKinds.map((kind) => kind.name).toList(),
      'includeSigningCredentials': includeSigningCredentials,
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

class ResourceExportResult {
  const ResourceExportResult({
    required this.archivePath,
    required this.fileCount,
    required this.signingCredentialCount,
  });

  final String archivePath;
  final int fileCount;
  final int signingCredentialCount;
}

extension ResourceCollectionPresetText on ResourceCollectionPreset {
  String get label {
    return switch (this) {
      ResourceCollectionPreset.allRecommended => 'All',
      ResourceCollectionPreset.envOnly => '.env',
      ResourceCollectionPreset.custom => 'Custom',
    };
  }
}

extension ResourceTargetKindText on ResourceTargetKind {
  String get label {
    return switch (this) {
      ResourceTargetKind.envFile => 'Env files',
      ResourceTargetKind.properties => 'Properties',
      ResourceTargetKind.fastlaneServiceAccount => 'Service account',
      ResourceTargetKind.firebaseConfig => 'Firebase config',
      ResourceTargetKind.signingKey => 'Signing keys',
      ResourceTargetKind.appStoreKey => 'App Store keys',
    };
  }
}

extension SigningCredentialSourceText on SigningCredentialSource {
  String get label {
    return switch (this) {
      SigningCredentialSource.secureStore => 'Secure store',
      SigningCredentialSource.projectFile => 'Project file',
      SigningCredentialSource.manual => 'Manual',
    };
  }
}

extension SigningCredentialStatusText on SigningCredentialStatus {
  String get label {
    return switch (this) {
      SigningCredentialStatus.resolved => 'Resolved',
      SigningCredentialStatus.partial => 'Partial',
      SigningCredentialStatus.missing => 'Missing',
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
