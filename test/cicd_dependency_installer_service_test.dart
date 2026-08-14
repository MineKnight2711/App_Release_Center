import 'package:app_release_center/app/models/cicd_dependency.dart';
import 'package:app_release_center/app/services/cicd_dependency_installer_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds Windows install plan with winget when available', () {
    const service = CiCdDependencyInstallerService();
    final snapshot = _snapshot(
      platform: CiCdSetupPlatform.windows,
      checks: [
        _installed('winget', 'Windows Package Manager', CiCdSetupGroup.core),
        _missing('git', 'Git', CiCdSetupGroup.core),
        _missing('git-bash', 'Git Bash', CiCdSetupGroup.core),
        _missing('jdk', 'JDK 17', CiCdSetupGroup.android),
        _installed(
          'android-sdkmanager',
          'Android SDK cmdline-tools',
          CiCdSetupGroup.android,
        ),
        _missing(
          'android-build-tools',
          'Android build-tools',
          CiCdSetupGroup.android,
        ),
        _missing('fastlane', 'Fastlane', CiCdSetupGroup.rubyFastlane),
      ],
    );

    final plan = service.buildInstallPlan(
      snapshot: snapshot,
      selectedGroups: const {
        CiCdSetupGroup.core,
        CiCdSetupGroup.android,
        CiCdSetupGroup.rubyFastlane,
      },
      projectPath: r'C:\demo',
    );

    expect(
      plan.map((step) => step.id),
      containsAll([
        'install-git',
        'install-jdk17',
        'install-android-build-tools',
        'install-fastlane',
      ]),
    );
    expect(
      plan.firstWhere((step) => step.id == 'install-git').commandPreview,
      contains('winget install --id Git.Git'),
    );
    expect(
      plan.firstWhere((step) => step.id == 'install-fastlane').commandPreview,
      'gem install fastlane --user-install',
    );
    expect(
      plan
          .firstWhere((step) => step.id == 'install-android-build-tools')
          .commandPreview,
      contains('sdkmanager'),
    );
  });

  test('filters install plan by selected dependency ids', () {
    const service = CiCdDependencyInstallerService();
    final snapshot = _snapshot(
      platform: CiCdSetupPlatform.windows,
      checks: [
        _installed('winget', 'Windows Package Manager', CiCdSetupGroup.core),
        _missing('git', 'Git', CiCdSetupGroup.core),
        _missing('flutter', 'Flutter SDK', CiCdSetupGroup.core),
        _missing('fastlane', 'Fastlane', CiCdSetupGroup.rubyFastlane),
      ],
    );

    final plan = service.buildInstallPlan(
      snapshot: snapshot,
      selectedGroups: const {CiCdSetupGroup.core, CiCdSetupGroup.rubyFastlane},
      selectedCheckIds: const {'fastlane'},
    );

    expect(plan.map((step) => step.id), ['install-fastlane']);
  });

  test('builds macOS manual fallback steps when Homebrew is missing', () {
    const service = CiCdDependencyInstallerService();
    final snapshot = _snapshot(
      platform: CiCdSetupPlatform.macos,
      checks: [
        _missing(
          'homebrew',
          'Homebrew',
          CiCdSetupGroup.core,
          fallbackUrl: 'https://brew.sh/',
        ),
        _missing('git', 'Git', CiCdSetupGroup.core),
      ],
    );

    final plan = service.buildInstallPlan(
      snapshot: snapshot,
      selectedGroups: const {CiCdSetupGroup.core},
    );

    expect(plan, hasLength(2));
    expect(plan.every((step) => step.isManual), isTrue);
    expect(
      plan.map((step) => step.fallbackUrl),
      everyElement('https://brew.sh/'),
    );
  });

  test('excludes optional tools until optional group is selected', () {
    const service = CiCdDependencyInstallerService();
    final snapshot = _snapshot(
      platform: CiCdSetupPlatform.windows,
      checks: [
        _installed('winget', 'Windows Package Manager', CiCdSetupGroup.core),
        _missing('firebase-cli', 'Firebase CLI', CiCdSetupGroup.optionalTools),
      ],
    );

    final withoutOptional = service.buildInstallPlan(
      snapshot: snapshot,
      selectedGroups: const {CiCdSetupGroup.core},
    );
    final withOptional = service.buildInstallPlan(
      snapshot: snapshot,
      selectedGroups: const {CiCdSetupGroup.optionalTools},
    );

    expect(withoutOptional, isEmpty);
    expect(
      withOptional.map((step) => step.id),
      contains('install-firebase-cli'),
    );
  });

  test('runs install step through ReleaseRunnerService', () async {
    const service = CiCdDependencyInstallerService();
    final runner = _FakeRunner();
    const step = CiCdInstallStep(
      id: 'install-fastlane',
      label: 'Install Fastlane',
      group: CiCdSetupGroup.rubyFastlane,
      platform: CiCdSetupPlatform.windows,
      executable: 'gem',
      arguments: ['install', 'fastlane', '--user-install'],
      workingDirectory: r'C:\project\android',
      expectedCheckId: 'fastlane',
    );

    final exitCode = await service.runInstallStep(step: step, runner: runner);

    expect(exitCode, 0);
    expect(runner.calls, hasLength(1));
    expect(runner.calls.single.workingDirectory, r'C:\project\android');
    expect(runner.calls.single.executable, 'gem');
    expect(runner.calls.single.arguments, [
      'install',
      'fastlane',
      '--user-install',
    ]);
    expect(runner.calls.single.activePath, 'setup:install-fastlane');
  });
}

CiCdDependencySnapshot _snapshot({
  required CiCdSetupPlatform platform,
  required List<CiCdDependencyCheck> checks,
}) {
  return CiCdDependencySnapshot(
    platform: platform,
    checkedAt: DateTime(2026, 8, 10),
    checks: checks,
  );
}

CiCdDependencyCheck _installed(String id, String label, CiCdSetupGroup group) {
  return CiCdDependencyCheck(
    id: id,
    label: label,
    group: group,
    status: CiCdDependencyStatus.installed,
  );
}

CiCdDependencyCheck _missing(
  String id,
  String label,
  CiCdSetupGroup group, {
  String fallbackUrl = '',
}) {
  return CiCdDependencyCheck(
    id: id,
    label: label,
    group: group,
    status: CiCdDependencyStatus.missing,
    fallbackUrl: fallbackUrl,
  );
}

class _FakeRunner extends ReleaseRunnerService {
  _FakeRunner();

  final calls = <_RunnerCall>[];

  @override
  Future<int> runCommand({
    required String workingDirectory,
    required String statusLabel,
    required String activePath,
    required String executable,
    List<String> arguments = const [],
    List<String>? displayArguments,
    Map<String, String> environment = const {},
    bool clearLog = false,
    String? projectName,
    bool allowDuringWorkflow = false,
    bool trackWorkflowStep = true,
  }) async {
    calls.add(
      _RunnerCall(
        workingDirectory: workingDirectory,
        statusLabel: statusLabel,
        activePath: activePath,
        executable: executable,
        arguments: arguments,
        environment: environment,
      ),
    );
    return 0;
  }
}

class _RunnerCall {
  const _RunnerCall({
    required this.workingDirectory,
    required this.statusLabel,
    required this.activePath,
    required this.executable,
    required this.arguments,
    required this.environment,
  });

  final String workingDirectory;
  final String statusLabel;
  final String activePath;
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
}
