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
      CiCdDependencyStatus.installed => 'Đã cài',
      CiCdDependencyStatus.missing => 'Chưa cài',
      CiCdDependencyStatus.outdated => 'Cần cập nhật',
      CiCdDependencyStatus.manual => 'Làm thủ công',
      CiCdDependencyStatus.unsupported => 'Không hỗ trợ',
      CiCdDependencyStatus.error => 'Lỗi',
    };
  }
}

enum CiCdSetupGroup { core, android, rubyFastlane, optionalTools }

extension CiCdSetupGroupLabel on CiCdSetupGroup {
  String get label {
    return switch (this) {
      CiCdSetupGroup.core => 'Cốt lõi',
      CiCdSetupGroup.android => 'Android',
      CiCdSetupGroup.rubyFastlane => 'Ruby / Fastlane',
      CiCdSetupGroup.optionalTools => 'Công cụ tuỳ chọn',
    };
  }

  String get description {
    return switch (this) {
      CiCdSetupGroup.core => 'Git, Flutter, Dart và các công cụ shell.',
      CiCdSetupGroup.android => 'JDK 17, công cụ Android SDK và license.',
      CiCdSetupGroup.rubyFastlane => 'Ruby, RubyGems, Bundler và Fastlane.',
      CiCdSetupGroup.optionalTools => 'GitHub CLI và key của Play.',
    };
  }
}

enum CiCdSetupPlatform { windows, macos, other }

extension CiCdSetupPlatformLabel on CiCdSetupPlatform {
  String get label {
    return switch (this) {
      CiCdSetupPlatform.windows => 'Windows',
      CiCdSetupPlatform.macos => 'macOS',
      CiCdSetupPlatform.other => 'Khác',
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
      label: 'Trình quản lý package',
      group: CiCdSetupGroup.core,
      description: 'winget trên Windows, Homebrew trên macOS.',
      checkIds: ['winget', 'homebrew', 'package-manager'],
    ),
    CiCdSetupOption(
      id: 'git',
      label: 'Git CLI',
      group: CiCdSetupGroup.core,
      description: 'Cần cho clone, pull, script CI và quản lý version.',
    ),
    CiCdSetupOption(
      id: 'git-bash',
      label: 'Git Bash',
      group: CiCdSetupGroup.core,
      description: 'Shell trên Windows mà nhiều script Flutter/Fastlane dùng.',
    ),
    CiCdSetupOption(
      id: 'flutter',
      label: 'Flutter SDK',
      group: CiCdSetupGroup.core,
      description: 'Bộ công cụ Flutter cho lệnh build, test và release.',
    ),
    CiCdSetupOption(
      id: 'dart',
      label: 'Dart CLI',
      group: CiCdSetupGroup.core,
      description: 'Kiểm tra lệnh dart có sẵn cho bộ công cụ Flutter.',
    ),
    CiCdSetupOption(
      id: 'jdk',
      label: 'JDK 17',
      group: CiCdSetupGroup.android,
      description: 'Java runtime mà bản build Gradle của Android cần.',
    ),
    CiCdSetupOption(
      id: 'android-sdkmanager',
      label: 'Android SDK cmdline-tools',
      group: CiCdSetupGroup.android,
      description: 'Cung cấp sdkmanager để cài package Android SDK.',
    ),
    CiCdSetupOption(
      id: 'android-platform-tools',
      label: 'Android platform-tools',
      group: CiCdSetupGroup.android,
      description: 'Cung cấp adb và các platform tool cho bản build Android.',
    ),
    CiCdSetupOption(
      id: 'android-build-tools',
      label: 'Android build-tools',
      group: CiCdSetupGroup.android,
      description: 'Package build-tools cài qua sdkmanager.',
    ),
    CiCdSetupOption(
      id: 'android-platforms',
      label: 'Android SDK platform',
      group: CiCdSetupGroup.android,
      description: 'Package platform theo Android API, cài qua sdkmanager.',
    ),
    CiCdSetupOption(
      id: 'android-licenses',
      label: 'Android licenses',
      group: CiCdSetupGroup.android,
      description: 'Bước xác nhận sdkmanager --licenses, phải trả lời tay.',
    ),
    CiCdSetupOption(
      id: 'ruby',
      label: 'Ngôn ngữ Ruby',
      group: CiCdSetupGroup.rubyFastlane,
      description: 'Ruby runtime mà Fastlane và các gem của dự án dùng.',
    ),
    CiCdSetupOption(
      id: 'gem',
      label: 'RubyGems',
      group: CiCdSetupGroup.rubyFastlane,
      description:
          'Trình quản lý package của Ruby, dùng để cài Bundler/Fastlane.',
    ),
    CiCdSetupOption(
      id: 'bundler',
      label: 'Bundler',
      group: CiCdSetupGroup.rubyFastlane,
      description: 'Cài các gem riêng của dự án từ Gemfile.',
    ),
    CiCdSetupOption(
      id: 'fastlane',
      label: 'Fastlane',
      group: CiCdSetupGroup.rubyFastlane,
      description: 'CLI tự động hoá release cho luồng deploy Android.',
    ),
    CiCdSetupOption(
      id: 'project-bundle',
      label: 'Chạy bundle install cho dự án',
      group: CiCdSetupGroup.rubyFastlane,
      description: 'Chạy bundle install khi có android/fastlane/Gemfile.',
    ),
    CiCdSetupOption(
      id: 'github-cli',
      label: 'GitHub CLI',
      group: CiCdSetupGroup.optionalTools,
      description: 'CLI tuỳ chọn để tự động hoá repository và release.',
      defaultSelected: false,
    ),
    CiCdSetupOption(
      id: 'google-play-service-account',
      label: 'Service account Google Play',
      group: CiCdSetupGroup.optionalTools,
      description: 'Tự kiểm tra file JSON key để upload lên Play Store.',
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
    if (isManual) return fallbackUrl.isEmpty ? 'Bước thủ công' : fallbackUrl;
    return [executable, ...arguments].map(_quoteCommandPart).join(' ');
  }
}

String _quoteCommandPart(String value) {
  if (value.isEmpty) return '""';
  if (!value.contains(RegExp(r'[\s;"]'))) return value;
  return '"${value.replaceAll('"', r'\"')}"';
}
