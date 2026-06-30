import 'package:app_release_center/app/models/app_store_credentials.dart';
import 'package:app_release_center/app/models/app_store_project.dart';
import 'package:app_release_center/app/models/app_store_version_snapshot.dart';
import 'package:app_release_center/app/services/app_store_project_inspector_service.dart';
import 'package:app_release_center/app/services/app_store_version_check_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppStoreVersionCheckService', () {
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
