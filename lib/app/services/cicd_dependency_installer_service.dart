import 'dart:io';

import 'package:app_release_center/app/models/cicd_dependency.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:path/path.dart' as p;

class CiCdDependencyInstallerService {
  const CiCdDependencyInstallerService();

  static const _androidSdkPackageIds = [
    'platform-tools',
    'build-tools;35.0.0',
    'platforms;android-35',
  ];

  List<CiCdInstallStep> buildInstallPlan({
    required CiCdDependencySnapshot snapshot,
    required Set<CiCdSetupGroup> selectedGroups,
    String projectPath = '',
  }) {
    final steps = <CiCdInstallStep>[];
    for (final group in CiCdSetupGroup.values) {
      if (!selectedGroups.contains(group)) continue;
      steps.addAll(_stepsForGroup(snapshot, group, projectPath));
    }
    return _dedupeSteps(steps);
  }

  Future<int> runInstallStep({
    required CiCdInstallStep step,
    required ReleaseRunnerService runner,
  }) {
    if (step.isManual) {
      runner.appendSystemLog(
        step.fallbackUrl.isEmpty
            ? '${step.label}: manual action required.'
            : '${step.label}: open ${step.fallbackUrl}',
      );
      return Future.value(0);
    }

    final workingDirectory = step.workingDirectory.trim().isEmpty
        ? Directory.current.path
        : step.workingDirectory;
    return runner.runCommand(
      workingDirectory: workingDirectory,
      statusLabel: step.label,
      activePath: 'setup:${step.id}',
      executable: step.executable,
      arguments: step.arguments,
      clearLog: false,
      allowDuringWorkflow: true,
      trackWorkflowStep: false,
    );
  }

  List<CiCdInstallStep> _stepsForGroup(
    CiCdDependencySnapshot snapshot,
    CiCdSetupGroup group,
    String projectPath,
  ) {
    final actionable = snapshot
        .checksForGroup(group)
        .where((check) => check.isActionable)
        .toList(growable: false);
    if (actionable.isEmpty) return const [];

    final platform = snapshot.platform;
    if (platform == CiCdSetupPlatform.windows) {
      return _windowsSteps(snapshot, group, actionable, projectPath);
    }
    if (platform == CiCdSetupPlatform.macos) {
      return _macosSteps(snapshot, group, actionable, projectPath);
    }
    return actionable.map((check) => _manualStep(check, platform)).toList();
  }

  List<CiCdInstallStep> _windowsSteps(
    CiCdDependencySnapshot snapshot,
    CiCdSetupGroup group,
    List<CiCdDependencyCheck> checks,
    String projectPath,
  ) {
    final hasWinget = snapshot.hasInstalled('winget');
    if (!hasWinget) {
      return checks
          .map(
            (check) => check.id == 'winget'
                ? _manualStep(check, snapshot.platform)
                : _manualStep(
                    check.copyWith(
                      detail:
                          'Install winget/App Installer first, then retry setup.',
                      fallbackUrl:
                          'https://learn.microsoft.com/windows/package-manager/',
                    ),
                    snapshot.platform,
                  ),
          )
          .toList();
    }

    return switch (group) {
      CiCdSetupGroup.core => [
        if (_needs(checks, 'git') || _needs(checks, 'git-bash'))
          _winget('install-git', 'Install Git', group, 'Git.Git'),
        if (_needs(checks, 'flutter'))
          _winget(
            'install-flutter',
            'Install Flutter SDK',
            group,
            'Google.Flutter',
          ),
      ],
      CiCdSetupGroup.android => [
        if (_needs(checks, 'jdk'))
          _winget(
            'install-jdk17',
            'Install JDK 17',
            group,
            'EclipseAdoptium.Temurin.17.JDK',
          ),
        if (_needs(checks, 'android-sdkmanager'))
          _winget(
            'install-android-studio',
            'Install Android Studio / SDK tools',
            group,
            'Google.AndroidStudio',
            fallbackUrl: 'https://developer.android.com/studio',
          ),
        if (snapshot.hasInstalled('android-sdkmanager') &&
            (_needs(checks, 'android-platform-tools') ||
                _needs(checks, 'android-build-tools') ||
                _needs(checks, 'android-platforms')))
          _windowsAndroidSdkPackages(group),
        if (_needs(checks, 'android-licenses'))
          CiCdInstallStep(
            id: 'accept-android-licenses',
            label: 'Accept Android SDK licenses',
            group: group,
            platform: CiCdSetupPlatform.windows,
            executable: 'cmd',
            arguments: const ['/c', 'sdkmanager --licenses'],
            requiresConfirmation: true,
            fallbackUrl: 'https://developer.android.com/studio/intro/update',
            expectedCheckId: 'android-licenses',
            description: 'Interactive license prompt may ask for confirmation.',
          ),
      ],
      CiCdSetupGroup.rubyFastlane => [
        if (_needs(checks, 'ruby') || _needs(checks, 'gem'))
          _winget(
            'install-ruby',
            'Install Ruby',
            group,
            'RubyInstallerTeam.Ruby.3.3',
            fallbackUrl: 'https://rubyinstaller.org/downloads/',
          ),
        if (_needs(checks, 'bundler'))
          _gem(
            'install-bundler',
            'Install Bundler',
            group,
            snapshot.platform,
            const ['install', 'bundler', '--user-install'],
          ),
        if (_needs(checks, 'fastlane'))
          _gem(
            'install-fastlane',
            'Install Fastlane',
            group,
            snapshot.platform,
            const ['install', 'fastlane', '--user-install'],
          ),
        if (_needs(checks, 'project-bundle'))
          _bundleInstall(projectPath, snapshot.platform),
      ],
      CiCdSetupGroup.optionalTools => [
        if (_needs(checks, 'firebase-cli'))
          _winget(
            'install-firebase-cli',
            'Install Firebase CLI',
            group,
            'Google.FirebaseCLI',
            fallbackUrl: 'https://firebase.google.com/docs/cli',
          ),
        if (_needs(checks, 'github-cli'))
          _winget(
            'install-github-cli',
            'Install GitHub CLI',
            group,
            'GitHub.cli',
          ),
        for (final check in checks)
          if (check.id == 'google-play-service-account')
            _manualStep(check, snapshot.platform),
      ],
    };
  }

  List<CiCdInstallStep> _macosSteps(
    CiCdDependencySnapshot snapshot,
    CiCdSetupGroup group,
    List<CiCdDependencyCheck> checks,
    String projectPath,
  ) {
    final hasBrew = snapshot.hasInstalled('homebrew');
    if (!hasBrew) {
      return checks
          .map(
            (check) => check.id == 'homebrew'
                ? _manualStep(check, snapshot.platform)
                : _manualStep(
                    check.copyWith(
                      detail: 'Install Homebrew first, then retry setup.',
                      fallbackUrl: 'https://brew.sh/',
                    ),
                    snapshot.platform,
                  ),
          )
          .toList();
    }

    return switch (group) {
      CiCdSetupGroup.core => [
        if (_needs(checks, 'git'))
          _brew('install-git', 'Install Git', group, 'git'),
        if (_needs(checks, 'flutter'))
          _brew(
            'install-flutter',
            'Install Flutter SDK',
            group,
            'flutter',
            arguments: const ['install', '--cask', 'flutter'],
          ),
      ],
      CiCdSetupGroup.android => [
        if (_needs(checks, 'jdk'))
          _brew('install-jdk17', 'Install JDK 17', group, 'openjdk@17'),
        if (_needs(checks, 'android-sdkmanager'))
          _brew(
            'install-android-tools',
            'Install Android command line tools',
            group,
            'android-commandlinetools',
          ),
        if (snapshot.hasInstalled('android-sdkmanager') &&
            (_needs(checks, 'android-platform-tools') ||
                _needs(checks, 'android-build-tools') ||
                _needs(checks, 'android-platforms')))
          _macosAndroidSdkPackages(group),
        if (_needs(checks, 'android-licenses'))
          CiCdInstallStep(
            id: 'accept-android-licenses',
            label: 'Accept Android SDK licenses',
            group: group,
            platform: CiCdSetupPlatform.macos,
            executable: 'sdkmanager',
            arguments: const ['--licenses'],
            requiresConfirmation: true,
            fallbackUrl: 'https://developer.android.com/studio/intro/update',
            expectedCheckId: 'android-licenses',
            description: 'Interactive license prompt may ask for confirmation.',
          ),
      ],
      CiCdSetupGroup.rubyFastlane => [
        if (_needs(checks, 'ruby') || _needs(checks, 'gem'))
          _brew('install-ruby', 'Install Ruby', group, 'ruby'),
        if (_needs(checks, 'bundler'))
          _gem(
            'install-bundler',
            'Install Bundler',
            group,
            snapshot.platform,
            const ['install', 'bundler', '--user-install'],
          ),
        if (_needs(checks, 'fastlane'))
          _gem(
            'install-fastlane',
            'Install Fastlane',
            group,
            snapshot.platform,
            const ['install', 'fastlane', '--user-install'],
          ),
        if (_needs(checks, 'project-bundle'))
          _bundleInstall(projectPath, snapshot.platform),
      ],
      CiCdSetupGroup.optionalTools => [
        if (_needs(checks, 'firebase-cli'))
          _brew(
            'install-firebase-cli',
            'Install Firebase CLI',
            group,
            'firebase-cli',
          ),
        if (_needs(checks, 'github-cli'))
          _brew('install-github-cli', 'Install GitHub CLI', group, 'gh'),
        for (final check in checks)
          if (check.id == 'google-play-service-account')
            _manualStep(check, snapshot.platform),
      ],
    };
  }

  CiCdInstallStep _winget(
    String id,
    String label,
    CiCdSetupGroup group,
    String packageId, {
    String fallbackUrl = '',
  }) {
    return CiCdInstallStep(
      id: id,
      label: label,
      group: group,
      platform: CiCdSetupPlatform.windows,
      executable: 'winget',
      arguments: [
        'install',
        '--id',
        packageId,
        '--exact',
        '--accept-package-agreements',
        '--accept-source-agreements',
      ],
      fallbackUrl: fallbackUrl,
      expectedCheckId: id.replaceFirst('install-', ''),
      description: 'Uses winget. Windows may ask for confirmation.',
    );
  }

  CiCdInstallStep _brew(
    String id,
    String label,
    CiCdSetupGroup group,
    String formula, {
    List<String>? arguments,
  }) {
    return CiCdInstallStep(
      id: id,
      label: label,
      group: group,
      platform: CiCdSetupPlatform.macos,
      executable: 'brew',
      arguments: arguments ?? ['install', formula],
      fallbackUrl: 'https://brew.sh/',
      expectedCheckId: id.replaceFirst('install-', ''),
      description: 'Uses Homebrew. The command is shown before running.',
    );
  }

  CiCdInstallStep _windowsAndroidSdkPackages(CiCdSetupGroup group) {
    return CiCdInstallStep(
      id: 'install-android-sdk-packages',
      label: 'Install Android SDK packages',
      group: group,
      platform: CiCdSetupPlatform.windows,
      executable: 'cmd',
      arguments: [
        '/c',
        [
          'sdkmanager',
          ..._androidSdkPackageIds.map((packageId) => '"$packageId"'),
        ].join(' '),
      ],
      fallbackUrl: 'https://developer.android.com/tools',
      expectedCheckId: 'android-build-tools',
      description: 'Installs platform-tools, build-tools and SDK platforms.',
    );
  }

  CiCdInstallStep _macosAndroidSdkPackages(CiCdSetupGroup group) {
    return CiCdInstallStep(
      id: 'install-android-sdk-packages',
      label: 'Install Android SDK packages',
      group: group,
      platform: CiCdSetupPlatform.macos,
      executable: 'sdkmanager',
      arguments: _androidSdkPackageIds,
      fallbackUrl: 'https://developer.android.com/tools',
      expectedCheckId: 'android-build-tools',
      description: 'Installs platform-tools, build-tools and SDK platforms.',
    );
  }

  CiCdInstallStep _gem(
    String id,
    String label,
    CiCdSetupGroup group,
    CiCdSetupPlatform platform,
    List<String> arguments,
  ) {
    return CiCdInstallStep(
      id: id,
      label: label,
      group: group,
      platform: platform,
      executable: 'gem',
      arguments: arguments,
      fallbackUrl: 'https://docs.fastlane.tools/getting-started/android/setup/',
      expectedCheckId: id.replaceFirst('install-', ''),
    );
  }

  CiCdInstallStep _bundleInstall(
    String projectPath,
    CiCdSetupPlatform platform,
  ) {
    return CiCdInstallStep(
      id: 'bundle-install-project',
      label: 'Install project gems',
      group: CiCdSetupGroup.rubyFastlane,
      platform: platform,
      executable: 'bundle',
      arguments: const ['install'],
      workingDirectory: p.join(projectPath, 'android'),
      fallbackUrl: 'https://bundler.io/man/bundle-install.1.html',
      expectedCheckId: 'project-bundle',
    );
  }

  CiCdInstallStep _manualStep(
    CiCdDependencyCheck check,
    CiCdSetupPlatform platform,
  ) {
    return CiCdInstallStep(
      id: 'manual-${check.id}',
      label: check.label,
      group: check.group,
      platform: platform,
      fallbackUrl: check.fallbackUrl,
      expectedCheckId: check.id,
      description: check.detail,
    );
  }

  bool _needs(List<CiCdDependencyCheck> checks, String id) {
    return checks.any((check) => check.id == id && check.isActionable);
  }

  List<CiCdInstallStep> _dedupeSteps(List<CiCdInstallStep> steps) {
    final byId = <String, CiCdInstallStep>{};
    for (final step in steps) {
      byId[step.id] = step;
    }
    return byId.values.toList(growable: false);
  }
}
