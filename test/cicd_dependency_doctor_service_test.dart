import 'package:app_release_center/app/models/cicd_dependency.dart';
import 'package:app_release_center/app/services/cicd_dependency_doctor_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses common dependency version outputs', () {
    expect(
      CiCdDependencyDoctorService.parseFirstVersion('git version 2.48.1'),
      '2.48.1',
    );
    expect(
      CiCdDependencyDoctorService.parseJavaMajorVersion(
        'openjdk version "17.0.11" 2024-04-16',
      ),
      17,
    );
    expect(
      CiCdDependencyDoctorService.parseJavaMajorVersion(
        'java version "1.8.0_401"',
      ),
      8,
    );
    expect(
      CiCdDependencyDoctorService.firstInstalledSdkPackage(
        'build-tools;35.0.0 | 35.0.0 | Android SDK Build-Tools 35\n'
            'platforms;android-35 | 1 | Android SDK Platform 35',
        'platforms;',
      ),
      'platforms;android-35',
    );
  });

  test('reports missing command when executable is not found', () async {
    final service = CiCdDependencyDoctorService(
      platform: CiCdSetupPlatform.windows,
      now: () => DateTime(2026, 8, 10, 9, 30),
      probe: _FakeProbe({
        _FakeProbe.key('winget', const ['--version']): const CiCdCommandResult(
          exitCode: 0,
          stdout: 'v1.9.0',
        ),
      }),
    );

    final snapshot = await service.checkAll();

    expect(snapshot.platform, CiCdSetupPlatform.windows);
    expect(snapshot.checkedAt, DateTime(2026, 8, 10, 9, 30));
    expect(
      snapshot.checkById('winget')?.status,
      CiCdDependencyStatus.installed,
    );
    expect(snapshot.checkById('git')?.status, CiCdDependencyStatus.missing);
    expect(snapshot.checkById('git')?.detail, contains('not found'));
  });

  test('marks Java below 17 as outdated', () async {
    final service = CiCdDependencyDoctorService(
      platform: CiCdSetupPlatform.macos,
      probe: _FakeProbe({
        _FakeProbe.key('brew', const ['--version']): const CiCdCommandResult(
          exitCode: 0,
          stdout: 'Homebrew 4.6.0',
        ),
        _FakeProbe.key('java', const ['-version']): const CiCdCommandResult(
          exitCode: 0,
          stderr: 'openjdk version "11.0.22" 2024-01-16',
        ),
      }),
    );

    final snapshot = await service.checkAll();
    final java = snapshot.checkById('jdk');

    expect(java?.status, CiCdDependencyStatus.outdated);
    expect(java?.version, '11.0.22');
    expect(java?.detail, contains('JDK 17'));
  });

  test('reports command errors separately from missing commands', () async {
    final service = CiCdDependencyDoctorService(
      platform: CiCdSetupPlatform.macos,
      probe: _FakeProbe({
        _FakeProbe.key('fastlane', const ['--version']):
            const CiCdCommandResult(exitCode: 2, stderr: 'broken ruby env'),
      }),
    );

    final snapshot = await service.checkAll();
    final fastlane = snapshot.checkById('fastlane');

    expect(fastlane?.status, CiCdDependencyStatus.error);
    expect(fastlane?.detail, 'broken ruby env');
  });
}

class _FakeProbe implements CiCdCommandProbe {
  _FakeProbe(this.responses);

  final Map<String, CiCdCommandResult> responses;

  static String key(String executable, List<String> arguments) {
    return [executable, ...arguments].join('\u0000');
  }

  @override
  Future<CiCdCommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    return responses[key(executable, arguments)] ??
        const CiCdCommandResult(
          exitCode: -1,
          stderr: 'missing',
          missingExecutable: true,
        );
  }
}
