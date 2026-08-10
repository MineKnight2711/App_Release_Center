import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_release_center/app/models/cicd_dependency.dart';
import 'package:path/path.dart' as p;

abstract class CiCdCommandProbe {
  Future<CiCdCommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}

class ProcessCiCdCommandProbe implements CiCdCommandProbe {
  const ProcessCiCdCommandProbe();

  @override
  Future<CiCdCommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 15));
      return CiCdCommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout?.toString() ?? '',
        stderr: result.stderr?.toString() ?? '',
      );
    } on ProcessException catch (error) {
      return CiCdCommandResult(
        exitCode: -1,
        stderr: error.message,
        missingExecutable: true,
      );
    } on TimeoutException {
      return const CiCdCommandResult(
        exitCode: -1,
        stderr: 'Command timed out.',
      );
    }
  }
}

class CiCdCommandResult {
  const CiCdCommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.missingExecutable = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool missingExecutable;

  String get combinedOutput => [
    stdout,
    stderr,
  ].where((value) => value.trim().isNotEmpty).join('\n').trim();
}

class CiCdDependencyDoctorService {
  CiCdDependencyDoctorService({
    CiCdCommandProbe? probe,
    DateTime Function()? now,
    CiCdSetupPlatform? platform,
  }) : _probe = probe ?? const ProcessCiCdCommandProbe(),
       _now = now ?? DateTime.now,
       _platform = platform;

  final CiCdCommandProbe _probe;
  final DateTime Function() _now;
  final CiCdSetupPlatform? _platform;

  Future<CiCdDependencySnapshot> checkAll({String? projectPath}) async {
    final platform = _platform ?? hostPlatform();
    final normalizedProjectPath = (projectPath ?? '').trim();
    final checks = <CiCdDependencyCheck>[];

    checks.add(await _packageManagerCheck(platform));
    checks.addAll(await _coreChecks(platform));
    checks.addAll(await _androidChecks());
    checks.addAll(await _rubyFastlaneChecks(normalizedProjectPath));
    checks.addAll(await _optionalChecks(normalizedProjectPath));

    return CiCdDependencySnapshot(
      platform: platform,
      checkedAt: _now(),
      projectPath: normalizedProjectPath,
      checks: checks,
    );
  }

  static CiCdSetupPlatform hostPlatform() {
    if (Platform.isWindows) return CiCdSetupPlatform.windows;
    if (Platform.isMacOS) return CiCdSetupPlatform.macos;
    return CiCdSetupPlatform.other;
  }

  Future<CiCdDependencyCheck> _packageManagerCheck(
    CiCdSetupPlatform platform,
  ) async {
    return switch (platform) {
      CiCdSetupPlatform.windows => _commandCheck(
        id: 'winget',
        label: 'Windows Package Manager',
        group: CiCdSetupGroup.core,
        executable: 'winget',
        arguments: const ['--version'],
        fallbackUrl: 'https://learn.microsoft.com/windows/package-manager/',
      ),
      CiCdSetupPlatform.macos => _commandCheck(
        id: 'homebrew',
        label: 'Homebrew',
        group: CiCdSetupGroup.core,
        executable: 'brew',
        arguments: const ['--version'],
        fallbackUrl: 'https://brew.sh/',
      ),
      CiCdSetupPlatform.other => const CiCdDependencyCheck(
        id: 'package-manager',
        label: 'Package manager',
        group: CiCdSetupGroup.core,
        status: CiCdDependencyStatus.unsupported,
        detail: 'Automatic install planning supports Windows and macOS first.',
      ),
    };
  }

  Future<List<CiCdDependencyCheck>> _coreChecks(
    CiCdSetupPlatform platform,
  ) async {
    return [
      await _commandCheck(
        id: 'git',
        label: 'Git',
        group: CiCdSetupGroup.core,
        executable: 'git',
        arguments: const ['--version'],
        fallbackUrl: 'https://git-scm.com/downloads',
      ),
      await _commandCheck(
        id: 'flutter',
        label: 'Flutter SDK',
        group: CiCdSetupGroup.core,
        executable: 'flutter',
        arguments: const ['--version'],
        fallbackUrl: 'https://docs.flutter.dev/get-started/install',
      ),
      await _commandCheck(
        id: 'dart',
        label: 'Dart',
        group: CiCdSetupGroup.core,
        executable: 'dart',
        arguments: const ['--version'],
        fallbackUrl: 'https://dart.dev/get-dart',
      ),
      if (platform == CiCdSetupPlatform.windows)
        await _commandCheck(
          id: 'git-bash',
          label: 'Git Bash',
          group: CiCdSetupGroup.core,
          executable: _gitBashExecutable(),
          arguments: const ['--version'],
          fallbackUrl: 'https://git-scm.com/download/win',
        ),
    ];
  }

  Future<List<CiCdDependencyCheck>> _androidChecks() async {
    final java = await _commandCheck(
      id: 'jdk',
      label: 'JDK 17',
      group: CiCdSetupGroup.android,
      executable: 'java',
      arguments: const ['-version'],
      fallbackUrl: 'https://adoptium.net/temurin/releases/?version=17',
      versionResolver: parseJavaVersionLabel,
      statusResolver: (result) {
        final major = parseJavaMajorVersion(result.combinedOutput);
        if (major == null) return CiCdDependencyStatus.error;
        return major >= 17
            ? CiCdDependencyStatus.installed
            : CiCdDependencyStatus.outdated;
      },
      detailResolver: (result) {
        final major = parseJavaMajorVersion(result.combinedOutput);
        if (major == null) {
          return 'Java is present but the version was unclear.';
        }
        if (major < 17) return 'JDK 17 or newer is required.';
        return 'Java runtime is ready for Android builds.';
      },
    );
    final sdkmanager = await _commandCheck(
      id: 'android-sdkmanager',
      label: 'Android SDK cmdline-tools',
      group: CiCdSetupGroup.android,
      executable: 'sdkmanager',
      arguments: const ['--version'],
      fallbackUrl: 'https://developer.android.com/tools',
    );
    final adb = await _commandCheck(
      id: 'android-platform-tools',
      label: 'Android platform-tools',
      group: CiCdSetupGroup.android,
      executable: 'adb',
      arguments: const ['version'],
      fallbackUrl: 'https://developer.android.com/tools',
    );
    final packageChecks = await _androidInstalledPackageChecks(sdkmanager);

    return [
      java,
      sdkmanager,
      adb,
      ...packageChecks,
      CiCdDependencyCheck(
        id: 'android-licenses',
        label: 'Android SDK licenses',
        group: CiCdSetupGroup.android,
        status: sdkmanager.status == CiCdDependencyStatus.installed
            ? CiCdDependencyStatus.manual
            : CiCdDependencyStatus.missing,
        detail: sdkmanager.status == CiCdDependencyStatus.installed
            ? 'Run sdkmanager --licenses once after SDK setup.'
            : 'Install Android cmdline-tools before accepting licenses.',
        command: 'sdkmanager --licenses',
        fallbackUrl: 'https://developer.android.com/studio/intro/update',
      ),
    ];
  }

  Future<List<CiCdDependencyCheck>> _androidInstalledPackageChecks(
    CiCdDependencyCheck sdkmanager,
  ) async {
    const command = 'sdkmanager --list_installed';
    if (sdkmanager.status != CiCdDependencyStatus.installed) {
      final status = sdkmanager.status == CiCdDependencyStatus.error
          ? CiCdDependencyStatus.error
          : CiCdDependencyStatus.missing;
      return [
        CiCdDependencyCheck(
          id: 'android-build-tools',
          label: 'Android build-tools',
          group: CiCdSetupGroup.android,
          status: status,
          detail: 'Install Android cmdline-tools before SDK packages.',
          command: command,
          fallbackUrl: 'https://developer.android.com/tools',
        ),
        CiCdDependencyCheck(
          id: 'android-platforms',
          label: 'Android SDK platforms',
          group: CiCdSetupGroup.android,
          status: status,
          detail: 'Install Android cmdline-tools before SDK packages.',
          command: command,
          fallbackUrl: 'https://developer.android.com/tools',
        ),
      ];
    }

    final result = await _probe.run('sdkmanager', const ['--list_installed']);
    if (result.missingExecutable) {
      return const [
        CiCdDependencyCheck(
          id: 'android-build-tools',
          label: 'Android build-tools',
          group: CiCdSetupGroup.android,
          status: CiCdDependencyStatus.missing,
          detail: 'sdkmanager was not found on PATH.',
          command: command,
          fallbackUrl: 'https://developer.android.com/tools',
        ),
        CiCdDependencyCheck(
          id: 'android-platforms',
          label: 'Android SDK platforms',
          group: CiCdSetupGroup.android,
          status: CiCdDependencyStatus.missing,
          detail: 'sdkmanager was not found on PATH.',
          command: command,
          fallbackUrl: 'https://developer.android.com/tools',
        ),
      ];
    }
    if (result.exitCode != 0) {
      final detail = result.combinedOutput.isEmpty
          ? 'sdkmanager exited with ${result.exitCode}.'
          : firstOutputLine(result.combinedOutput);
      return [
        CiCdDependencyCheck(
          id: 'android-build-tools',
          label: 'Android build-tools',
          group: CiCdSetupGroup.android,
          status: CiCdDependencyStatus.error,
          detail: detail,
          command: command,
          fallbackUrl: 'https://developer.android.com/tools',
        ),
        CiCdDependencyCheck(
          id: 'android-platforms',
          label: 'Android SDK platforms',
          group: CiCdSetupGroup.android,
          status: CiCdDependencyStatus.error,
          detail: detail,
          command: command,
          fallbackUrl: 'https://developer.android.com/tools',
        ),
      ];
    }

    final output = result.combinedOutput;
    final buildToolsPackage = firstInstalledSdkPackage(output, 'build-tools;');
    final platformPackage = firstInstalledSdkPackage(output, 'platforms;');
    return [
      CiCdDependencyCheck(
        id: 'android-build-tools',
        label: 'Android build-tools',
        group: CiCdSetupGroup.android,
        status: buildToolsPackage.isEmpty
            ? CiCdDependencyStatus.missing
            : CiCdDependencyStatus.installed,
        detail: buildToolsPackage.isEmpty
            ? 'Install an Android build-tools package.'
            : 'SDK build-tools package is installed.',
        version: buildToolsPackage,
        command: command,
        fallbackUrl: 'https://developer.android.com/tools',
      ),
      CiCdDependencyCheck(
        id: 'android-platforms',
        label: 'Android SDK platforms',
        group: CiCdSetupGroup.android,
        status: platformPackage.isEmpty
            ? CiCdDependencyStatus.missing
            : CiCdDependencyStatus.installed,
        detail: platformPackage.isEmpty
            ? 'Install at least one Android SDK platform.'
            : 'Android SDK platform package is installed.',
        version: platformPackage,
        command: command,
        fallbackUrl: 'https://developer.android.com/tools',
      ),
    ];
  }

  Future<List<CiCdDependencyCheck>> _rubyFastlaneChecks(
    String projectPath,
  ) async {
    final checks = [
      await _commandCheck(
        id: 'ruby',
        label: 'Ruby',
        group: CiCdSetupGroup.rubyFastlane,
        executable: 'ruby',
        arguments: const ['-v'],
        fallbackUrl: 'https://www.ruby-lang.org/en/documentation/installation/',
      ),
      await _commandCheck(
        id: 'gem',
        label: 'RubyGems',
        group: CiCdSetupGroup.rubyFastlane,
        executable: 'gem',
        arguments: const ['-v'],
        fallbackUrl: 'https://rubygems.org/pages/download',
      ),
      await _commandCheck(
        id: 'bundler',
        label: 'Bundler',
        group: CiCdSetupGroup.rubyFastlane,
        executable: 'bundle',
        arguments: const ['-v'],
        fallbackUrl: 'https://bundler.io/',
      ),
      await _commandCheck(
        id: 'fastlane',
        label: 'Fastlane',
        group: CiCdSetupGroup.rubyFastlane,
        executable: 'fastlane',
        arguments: const ['--version'],
        fallbackUrl:
            'https://docs.fastlane.tools/getting-started/android/setup/',
      ),
    ];

    final androidDirectory = Directory(p.join(projectPath, 'android'));
    final gemfile = File(p.join(androidDirectory.path, 'fastlane', 'Gemfile'));
    if (projectPath.isNotEmpty && gemfile.existsSync()) {
      checks.add(
        await _commandCheck(
          id: 'project-bundle',
          label: 'Project bundle',
          group: CiCdSetupGroup.rubyFastlane,
          executable: 'bundle',
          arguments: const ['check'],
          workingDirectory: androidDirectory.path,
          fallbackUrl: 'https://bundler.io/man/bundle-install.1.html',
          detailResolver: (result) => result.exitCode == 0
              ? 'Project gems are installed for android/fastlane/Gemfile.'
              : 'Run bundle install inside the Android project.',
        ),
      );
    }

    return checks;
  }

  Future<List<CiCdDependencyCheck>> _optionalChecks(String projectPath) async {
    return [
      await _commandCheck(
        id: 'firebase-cli',
        label: 'Firebase CLI',
        group: CiCdSetupGroup.optionalTools,
        executable: 'firebase',
        arguments: const ['--version'],
        fallbackUrl: 'https://firebase.google.com/docs/cli',
      ),
      await _commandCheck(
        id: 'github-cli',
        label: 'GitHub CLI',
        group: CiCdSetupGroup.optionalTools,
        executable: 'gh',
        arguments: const ['--version'],
        fallbackUrl: 'https://cli.github.com/',
      ),
      _playServiceAccountCheck(projectPath),
    ];
  }

  CiCdDependencyCheck _playServiceAccountCheck(String projectPath) {
    if (projectPath.trim().isEmpty) {
      return const CiCdDependencyCheck(
        id: 'google-play-service-account',
        label: 'Google Play service account',
        group: CiCdSetupGroup.optionalTools,
        status: CiCdDependencyStatus.manual,
        detail: 'Select a project to check android/fastlane keys.',
      );
    }
    final androidDirectory = Directory(p.join(projectPath, 'android'));
    final candidates = [
      File(
        p.join(
          androidDirectory.path,
          'fastlane',
          'keys',
          'google-play-service-account.json',
        ),
      ),
      File(p.join(androidDirectory.path, 'fastlane-service-account.json')),
    ];
    final fromEnvProperties = _serviceAccountFromEnvProperties(
      androidDirectory.path,
    );
    if (fromEnvProperties != null) candidates.add(fromEnvProperties);

    final found = candidates.any((file) => file.existsSync());
    return CiCdDependencyCheck(
      id: 'google-play-service-account',
      label: 'Google Play service account',
      group: CiCdSetupGroup.optionalTools,
      status: found
          ? CiCdDependencyStatus.installed
          : CiCdDependencyStatus.manual,
      detail: found
          ? 'Google Play service account file was found.'
          : 'Add the JSON key used by FASTLANE_KEY_PATH.',
      fallbackUrl:
          'https://docs.fastlane.tools/actions/upload_to_play_store/#setup',
    );
  }

  File? _serviceAccountFromEnvProperties(String androidPath) {
    final file = File(p.join(androidPath, 'env.properties'));
    if (!file.existsSync()) return null;
    try {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.startsWith('#') || !trimmed.contains('=')) continue;
        final parts = trimmed.split('=');
        final key = parts.first.trim();
        if (key != 'FASTLANE_KEY_PATH') continue;
        final value = parts.skip(1).join('=').trim();
        if (value.isEmpty) return null;
        final normalized = value.replaceAll('"', '');
        final direct = File(normalized);
        return direct.isAbsolute
            ? direct
            : File(p.join(androidPath, normalized));
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  Future<CiCdDependencyCheck> _commandCheck({
    required String id,
    required String label,
    required CiCdSetupGroup group,
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
    String fallbackUrl = '',
    String Function(CiCdCommandResult result)? versionResolver,
    CiCdDependencyStatus Function(CiCdCommandResult result)? statusResolver,
    String Function(CiCdCommandResult result)? detailResolver,
  }) async {
    final result = await _probe.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    if (result.missingExecutable) {
      return CiCdDependencyCheck(
        id: id,
        label: label,
        group: group,
        status: CiCdDependencyStatus.missing,
        detail: '$executable was not found on PATH.',
        command: [executable, ...arguments].join(' '),
        fallbackUrl: fallbackUrl,
      );
    }
    final status =
        statusResolver?.call(result) ??
        (result.exitCode == 0
            ? CiCdDependencyStatus.installed
            : CiCdDependencyStatus.error);
    final output = result.combinedOutput;
    return CiCdDependencyCheck(
      id: id,
      label: label,
      group: group,
      status: status,
      detail:
          detailResolver?.call(result) ??
          (status == CiCdDependencyStatus.installed
              ? 'Command is available.'
              : output.isEmpty
              ? 'Command exited with ${result.exitCode}.'
              : firstOutputLine(output)),
      version: versionResolver?.call(result) ?? parseFirstVersion(output),
      command: [executable, ...arguments].join(' '),
      fallbackUrl: fallbackUrl,
    );
  }

  String _gitBashExecutable() {
    if (!Platform.isWindows) return 'bash';
    const candidates = [
      r'C:\Program Files\Git\bin\bash.exe',
      r'C:\Program Files\Git\usr\bin\bash.exe',
      r'C:\Program Files (x86)\Git\bin\bash.exe',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return 'bash';
  }

  static String firstOutputLine(String output) {
    return output
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  }

  static String parseFirstVersion(String output) {
    final match = RegExp(
      r'\d+(?:\.\d+)+(?:[+._-][A-Za-z0-9.-]+)?',
    ).firstMatch(output);
    return match?.group(0) ?? '';
  }

  static String parseJavaVersionLabel(CiCdCommandResult result) {
    return parseFirstVersion(result.combinedOutput);
  }

  static int? parseJavaMajorVersion(String output) {
    final quoted = RegExp(r'version\s+"([^"]+)"').firstMatch(output);
    final raw = quoted?.group(1) ?? parseFirstVersion(output);
    if (raw.isEmpty) return null;
    final parts = raw.split(RegExp(r'[.+_-]'));
    if (parts.isEmpty) return null;
    if (parts.first == '1' && parts.length > 1) {
      return int.tryParse(parts[1]);
    }
    return int.tryParse(parts.first);
  }

  static String firstInstalledSdkPackage(String output, String prefix) {
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final cells = line.split('|').map((cell) => cell.trim()).toList();
      for (final cell in cells) {
        if (cell.startsWith(prefix)) return cell;
      }
    }
    return '';
  }
}
