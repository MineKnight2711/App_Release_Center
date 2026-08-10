enum CiCdDependencyStatus {
  installed,
  missing,
  outdated,
  manual,
  unsupported,
  error,
}

extension CiCdDependencyStatusLabel on CiCdDependencyStatus {
  String get label {
    return switch (this) {
      CiCdDependencyStatus.installed => 'Installed',
      CiCdDependencyStatus.missing => 'Missing',
      CiCdDependencyStatus.outdated => 'Needs update',
      CiCdDependencyStatus.manual => 'Manual',
      CiCdDependencyStatus.unsupported => 'Unsupported',
      CiCdDependencyStatus.error => 'Error',
    };
  }
}

enum CiCdSetupGroup { core, android, rubyFastlane, optionalTools }

extension CiCdSetupGroupLabel on CiCdSetupGroup {
  String get label {
    return switch (this) {
      CiCdSetupGroup.core => 'Core',
      CiCdSetupGroup.android => 'Android',
      CiCdSetupGroup.rubyFastlane => 'Ruby / Fastlane',
      CiCdSetupGroup.optionalTools => 'Optional tools',
    };
  }

  String get description {
    return switch (this) {
      CiCdSetupGroup.core => 'Git, Flutter, Dart and shell tools.',
      CiCdSetupGroup.android => 'JDK 17, Android SDK tools and licenses.',
      CiCdSetupGroup.rubyFastlane => 'Ruby, RubyGems, Bundler and Fastlane.',
      CiCdSetupGroup.optionalTools => 'Firebase CLI, GitHub CLI and Play key.',
    };
  }
}

enum CiCdSetupPlatform { windows, macos, other }

extension CiCdSetupPlatformLabel on CiCdSetupPlatform {
  String get label {
    return switch (this) {
      CiCdSetupPlatform.windows => 'Windows',
      CiCdSetupPlatform.macos => 'macOS',
      CiCdSetupPlatform.other => 'Other',
    };
  }
}

class CiCdDependencyCheck {
  const CiCdDependencyCheck({
    required this.id,
    required this.label,
    required this.group,
    required this.status,
    this.detail = '',
    this.version = '',
    this.command = '',
    this.fallbackUrl = '',
  });

  final String id;
  final String label;
  final CiCdSetupGroup group;
  final CiCdDependencyStatus status;
  final String detail;
  final String version;
  final String command;
  final String fallbackUrl;

  bool get isActionable =>
      status == CiCdDependencyStatus.missing ||
      status == CiCdDependencyStatus.outdated ||
      status == CiCdDependencyStatus.manual ||
      status == CiCdDependencyStatus.error;

  CiCdDependencyCheck copyWith({
    String? id,
    String? label,
    CiCdSetupGroup? group,
    CiCdDependencyStatus? status,
    String? detail,
    String? version,
    String? command,
    String? fallbackUrl,
  }) {
    return CiCdDependencyCheck(
      id: id ?? this.id,
      label: label ?? this.label,
      group: group ?? this.group,
      status: status ?? this.status,
      detail: detail ?? this.detail,
      version: version ?? this.version,
      command: command ?? this.command,
      fallbackUrl: fallbackUrl ?? this.fallbackUrl,
    );
  }
}

class CiCdDependencySnapshot {
  const CiCdDependencySnapshot({
    required this.platform,
    required this.checkedAt,
    this.projectPath = '',
    this.checks = const [],
  });

  final CiCdSetupPlatform platform;
  final DateTime checkedAt;
  final String projectPath;
  final List<CiCdDependencyCheck> checks;

  CiCdDependencyCheck? checkById(String id) {
    for (final check in checks) {
      if (check.id == id) return check;
    }
    return null;
  }

  List<CiCdDependencyCheck> checksForGroup(CiCdSetupGroup group) {
    return checks
        .where((check) => check.group == group)
        .toList(growable: false);
  }

  bool hasInstalled(String id) {
    return checkById(id)?.status == CiCdDependencyStatus.installed;
  }

  bool get hasAnyPackageManager {
    return hasInstalled('winget') || hasInstalled('homebrew');
  }
}

class CiCdInstallStep {
  const CiCdInstallStep({
    required this.id,
    required this.label,
    required this.group,
    required this.platform,
    this.executable = '',
    this.arguments = const [],
    this.workingDirectory = '',
    this.requiresConfirmation = true,
    this.fallbackUrl = '',
    this.expectedCheckId = '',
    this.description = '',
  });

  final String id;
  final String label;
  final CiCdSetupGroup group;
  final CiCdSetupPlatform platform;
  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final bool requiresConfirmation;
  final String fallbackUrl;
  final String expectedCheckId;
  final String description;

  bool get isManual => executable.trim().isEmpty;

  String get commandPreview {
    if (isManual) return fallbackUrl.isEmpty ? 'Manual step' : fallbackUrl;
    return [executable, ...arguments].map(_quoteCommandPart).join(' ');
  }
}

String _quoteCommandPart(String value) {
  if (value.isEmpty) return '""';
  if (!value.contains(RegExp(r'[\s;"]'))) return value;
  return '"${value.replaceAll('"', r'\"')}"';
}
