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

class CiCdSetupOption {
  const CiCdSetupOption({
    required this.id,
    required this.label,
    required this.group,
    required this.description,
    this.checkIds = const [],
    this.defaultSelected = true,
  });

  final String id;
  final String label;
  final CiCdSetupGroup group;
  final String description;
  final List<String> checkIds;
  final bool defaultSelected;

  List<String> get coveredCheckIds => checkIds.isEmpty ? [id] : checkIds;

  bool coversCheck(String checkId) => coveredCheckIds.contains(checkId);
}

class CiCdSetupCatalog {
  const CiCdSetupCatalog._();

  static const all = [
    CiCdSetupOption(
      id: 'package-manager',
      label: 'Package manager',
      group: CiCdSetupGroup.core,
      description: 'winget on Windows, Homebrew on macOS.',
      checkIds: ['winget', 'homebrew', 'package-manager'],
    ),
    CiCdSetupOption(
      id: 'git',
      label: 'Git CLI',
      group: CiCdSetupGroup.core,
      description: 'Required for clone, pull, CI scripts and version control.',
    ),
    CiCdSetupOption(
      id: 'git-bash',
      label: 'Git Bash',
      group: CiCdSetupGroup.core,
      description: 'Windows shell used by many Flutter/Fastlane scripts.',
    ),
    CiCdSetupOption(
      id: 'flutter',
      label: 'Flutter SDK',
      group: CiCdSetupGroup.core,
      description: 'Flutter toolchain for build, test and release commands.',
    ),
    CiCdSetupOption(
      id: 'dart',
      label: 'Dart CLI',
      group: CiCdSetupGroup.core,
      description: 'Dart command availability for Flutter tooling.',
    ),
    CiCdSetupOption(
      id: 'jdk',
      label: 'JDK 17',
      group: CiCdSetupGroup.android,
      description: 'Java runtime required by Android Gradle builds.',
    ),
    CiCdSetupOption(
      id: 'android-sdkmanager',
      label: 'Android SDK cmdline-tools',
      group: CiCdSetupGroup.android,
      description: 'Provides sdkmanager for Android SDK package setup.',
    ),
    CiCdSetupOption(
      id: 'android-platform-tools',
      label: 'Android platform-tools',
      group: CiCdSetupGroup.android,
      description: 'Provides adb and platform tools used by Android builds.',
    ),
    CiCdSetupOption(
      id: 'android-build-tools',
      label: 'Android build-tools',
      group: CiCdSetupGroup.android,
      description: 'Build-tools package installed through sdkmanager.',
    ),
    CiCdSetupOption(
      id: 'android-platforms',
      label: 'Android SDK platform',
      group: CiCdSetupGroup.android,
      description: 'Android API platform package installed through sdkmanager.',
    ),
    CiCdSetupOption(
      id: 'android-licenses',
      label: 'Android licenses',
      group: CiCdSetupGroup.android,
      description: 'Interactive sdkmanager --licenses confirmation step.',
    ),
    CiCdSetupOption(
      id: 'ruby',
      label: 'Ruby language',
      group: CiCdSetupGroup.rubyFastlane,
      description: 'Ruby runtime used by Fastlane and project gems.',
    ),
    CiCdSetupOption(
      id: 'gem',
      label: 'RubyGems',
      group: CiCdSetupGroup.rubyFastlane,
      description: 'Ruby package manager used to install Bundler/Fastlane.',
    ),
    CiCdSetupOption(
      id: 'bundler',
      label: 'Bundler',
      group: CiCdSetupGroup.rubyFastlane,
      description: 'Installs project-local gems from Gemfile.',
    ),
    CiCdSetupOption(
      id: 'fastlane',
      label: 'Fastlane',
      group: CiCdSetupGroup.rubyFastlane,
      description: 'Release automation CLI for Android deploy workflows.',
    ),
    CiCdSetupOption(
      id: 'project-bundle',
      label: 'Project bundle install',
      group: CiCdSetupGroup.rubyFastlane,
      description: 'Runs bundle install when android/fastlane/Gemfile exists.',
    ),
    CiCdSetupOption(
      id: 'firebase-cli',
      label: 'Firebase CLI',
      group: CiCdSetupGroup.optionalTools,
      description: 'Optional CLI for Firebase App Distribution workflows.',
      defaultSelected: false,
    ),
    CiCdSetupOption(
      id: 'github-cli',
      label: 'GitHub CLI',
      group: CiCdSetupGroup.optionalTools,
      description: 'Optional CLI for repository and release automation.',
      defaultSelected: false,
    ),
    CiCdSetupOption(
      id: 'google-play-service-account',
      label: 'Google Play service account',
      group: CiCdSetupGroup.optionalTools,
      description: 'Manual JSON key check for Play Store upload.',
      defaultSelected: false,
    ),
  ];

  static Set<String> get defaultSelectedIds {
    return all
        .where((option) => option.defaultSelected)
        .map((option) => option.id)
        .toSet();
  }

  static List<CiCdSetupOption> optionsForGroup(CiCdSetupGroup group) {
    return all.where((option) => option.group == group).toList(growable: false);
  }

  static CiCdSetupOption? optionForId(String id) {
    for (final option in all) {
      if (option.id == id) return option;
    }
    return null;
  }

  static Set<String> checkIdsForOptionIds(Set<String> optionIds) {
    final checkIds = <String>{};
    for (final option in all) {
      if (optionIds.contains(option.id)) {
        checkIds.addAll(option.coveredCheckIds);
      }
    }
    return checkIds;
  }

  static Set<CiCdSetupGroup> groupsForOptionIds(Set<String> optionIds) {
    return all
        .where((option) => optionIds.contains(option.id))
        .map((option) => option.group)
        .toSet();
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
