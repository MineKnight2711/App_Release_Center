import 'dart:io';

import 'package:app_management_center/app/models/app_store_credentials.dart';
import 'package:app_management_center/app/models/app_store_project.dart';
import 'package:app_management_center/app/models/app_store_version_snapshot.dart';
import 'package:app_management_center/app/services/app_store_project_inspector_service.dart';
import 'package:app_management_center/app/services/app_store_version_check_service.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AppStoreVersionCheckService', () {
    test(
      'parses live, editable and review state independently from TestFlight',
      () {
        final info = AppStoreVersionCheckService.parseStoreInfo(
          '[19:28:44]: APPSTORE_VERSION_INFO:{"live":"1.0.0","edit":"1.1.0","state":"PREPARE_FOR_SUBMISSION"}\u001b[0m\nAPPSTORE_BUILD_ONLY:12\n',
        );
        expect(info['live'], '1.0.0');
        expect(info['edit'], '1.1.0');
        expect(info['state'], 'PREPARE_FOR_SUBMISSION');
      },
    );
    for (final useBundler in [false, true]) {
      test('provides discoverable Fastfile (Bundler: $useBundler)', () async {
        final root = await Directory.systemTemp.createTemp('appstore_test_');
        addTearDown(() => root.delete(recursive: true));
        final ios = await Directory(p.join(root.path, 'ios')).create();
        final gemfile = File(p.join(ios.path, 'Gemfile'));
        if (useBundler) await gemfile.writeAsString('gem "fastlane"');
        final runner = _InspectingRunner();
        final service = AppStoreVersionCheckService(
          inspector: _FakeAppStoreInspector(_localVersion),
          runner: runner,
        );

        final snapshot = await service.refreshProject(
          project: AppStoreProject(
            id: 'ios-test',
            path: root.path,
            displayName: 'iOS Demo',
            bundleId: 'com.example.app',
          ),
          credentials: _validCredentials,
        );

        expect(snapshot.testFlightBuildNumber, 12);
        expect(snapshot.status, AppStoreComparisonStatus.localBehind);
        expect(runner.executable, useBundler ? 'bundle' : 'fastlane');
        expect(runner.arguments.take(useBundler ? 4 : 2), [
          if (useBundler) ...['exec', 'fastlane'],
          'ios',
          'arc_fetch_testflight_build',
        ]);
        expect(
          runner.environment['BUNDLE_GEMFILE'],
          useBundler ? gemfile.path : isNull,
        );
        expect(Directory(runner.workingDirectory).existsSync(), isFalse);
      });
    }

    test('parses latest APPSTORE_BUILD_ONLY marker from Fastlane output', () {
      final build = AppStoreVersionCheckService.parseTestFlightBuildNumber('''
Fetching TestFlight build
APPSTORE_BUILD_ONLY:41
APPSTORE_BUILD_ONLY:42
''');

      expect(build, 42);
    });

    test('returns null when output has no clean marker', () {
      final build = AppStoreVersionCheckService.parseTestFlightBuildNumber(
        'Latest TestFlight build is 42',
      );

      expect(build, isNull);
    });

    test('compares local and TestFlight build numbers', () {
      expect(
        AppStoreVersionCheckService.compare(10, 12),
        AppStoreComparisonStatus.localBehind,
      );
      expect(
        AppStoreVersionCheckService.compare(12, 10),
        AppStoreComparisonStatus.localAhead,
      );
      expect(
        AppStoreVersionCheckService.compare(12, 12),
        AppStoreComparisonStatus.upToDate,
      );
    });

    test('reports missing local version', () async {
      final service = _serviceWithLocalVersion(null);

      final snapshot = await service.refreshProject(
        project: _project(bundleId: 'com.example.app'),
        credentials: _validCredentials,
      );

      expect(snapshot.status, AppStoreComparisonStatus.missingLocalVersion);
    });

    test('reports missing bundle ID before querying Fastlane', () async {
      final service = _serviceWithLocalVersion(_localVersion);

      final snapshot = await service.refreshProject(
        project: _project(bundleId: ''),
        credentials: _validCredentials,
      );

      expect(snapshot.status, AppStoreComparisonStatus.missingBundleId);
    });

    test('reports missing credentials before querying Fastlane', () async {
      final service = _serviceWithLocalVersion(_localVersion);

      final snapshot = await service.refreshProject(
        project: _project(bundleId: 'com.example.app'),
        credentials: const AppStoreCredentials(),
      );

      expect(snapshot.status, AppStoreComparisonStatus.missingCredentials);
    });
  });
}

AppStoreVersionCheckService _serviceWithLocalVersion(
  AppStoreLocalVersion? localVersion,
) {
  return AppStoreVersionCheckService(
    inspector: _FakeAppStoreInspector(localVersion),
    runner: ReleaseRunnerService(),
  );
}

AppStoreProject _project({required String bundleId}) {
  return AppStoreProject(
    id: 'ios-1',
    path: '.',
    displayName: 'iOS Demo',
    bundleId: bundleId,
  );
}

const _localVersion = AppStoreLocalVersion(
  name: '1.0.0',
  buildNumber: 10,
  raw: '1.0.0+10',
);

const _validCredentials = AppStoreCredentials(
  p8PrivateKey: '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----',
  keyId: 'KEY1234567',
  issuerId: 'issuer-id',
);

class _FakeAppStoreInspector extends AppStoreProjectInspectorService {
  _FakeAppStoreInspector(this.localVersion);

  final AppStoreLocalVersion? localVersion;

  @override
  Future<AppStoreLocalVersion?> readLocalVersion(String projectPath) async {
    return localVersion;
  }
}

class _InspectingRunner extends ReleaseRunnerService {
  late String workingDirectory;
  late String executable;
  late List<String> arguments;
  late Map<String, String> environment;

  @override
  String resolveFastlaneExecutable() => 'fastlane';

  @override
  String? resolveBundleExecutable() => 'bundle';

  @override
  Future<CommandRunResult> runCommandWithOutput({
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
    this.workingDirectory = workingDirectory;
    this.executable = executable;
    this.arguments = arguments;
    this.environment = environment;
    final fastfile = File(p.join(workingDirectory, 'fastlane', 'Fastfile'));
    expect(fastfile.existsSync(), isTrue);
    expect(
      await fastfile.readAsString(),
      contains('lane :arc_fetch_testflight_build'),
    );
    final keyArgument = arguments.singleWhere(
      (argument) => argument.startsWith('key_filepath:'),
    );
    final key = File(keyArgument.substring('key_filepath:'.length));
    expect(await key.readAsString(), _validCredentials.p8PrivateKey);
    return const CommandRunResult(
      exitCode: 0,
      output: 'APPSTORE_BUILD_ONLY:12',
    );
  }
}
