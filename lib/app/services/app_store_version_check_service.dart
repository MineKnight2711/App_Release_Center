import 'dart:io';

import 'package:app_release_center/app/models/app_store_credentials.dart';
import 'package:app_release_center/app/models/app_store_project.dart';
import 'package:app_release_center/app/models/app_store_version_snapshot.dart';
import 'package:app_release_center/app/services/app_store_project_inspector_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

class AppStoreVersionCheckService extends GetxService {
  AppStoreVersionCheckService({required this.inspector, required this.runner});

  final AppStoreProjectInspectorService inspector;
  final ReleaseRunnerService runner;

  Future<AppStoreVersionSnapshot> readLocalSnapshot(
    AppStoreProject project,
  ) async {
    final localVersion = await inspector.readLocalVersion(project.path);
    if (localVersion == null) {
      return const AppStoreVersionSnapshot(
        status: AppStoreComparisonStatus.missingLocalVersion,
        message: 'pubspec.yaml version must use name+build format.',
      );
    }

    return AppStoreVersionSnapshot(localVersion: localVersion);
  }

  Future<AppStoreVersionSnapshot> refreshProject({
    required AppStoreProject project,
    required AppStoreCredentials credentials,
  }) async {
    final localVersion = await inspector.readLocalVersion(project.path);
    final checkedAt = DateTime.now();

    if (localVersion == null) {
      return AppStoreVersionSnapshot(
        status: AppStoreComparisonStatus.missingLocalVersion,
        message: 'pubspec.yaml version must use name+build format.',
        lastCheckedAt: checkedAt,
      );
    }

    if (project.bundleId.trim().isEmpty) {
      return AppStoreVersionSnapshot(
        localVersion: localVersion,
        status: AppStoreComparisonStatus.missingBundleId,
        message: 'Bundle ID is required.',
        lastCheckedAt: checkedAt,
      );
    }

    if (!credentials.hasRequiredCredentials) {
      return AppStoreVersionSnapshot(
        localVersion: localVersion,
        status: AppStoreComparisonStatus.missingCredentials,
        message: 'Import a .p8 key and enter Key ID and Issuer ID.',
        lastCheckedAt: checkedAt,
      );
    }

    final iosDirectory = Directory(p.join(project.path, 'ios'));
    if (!iosDirectory.existsSync()) {
      return AppStoreVersionSnapshot(
        localVersion: localVersion,
        status: AppStoreComparisonStatus.failed,
        message: 'Project does not contain an ios folder.',
        lastCheckedAt: checkedAt,
      );
    }

    final tempDirectory = await Directory.systemTemp.createTemp(
      'app_release_center_appstore_',
    );
    try {
      final keyFileName = credentials.hasKeyId
          ? 'AuthKey_${credentials.keyId!.trim()}.p8'
          : 'AuthKey.p8';
      final keyFile = File(p.join(tempDirectory.path, keyFileName));
      await keyFile.writeAsString(credentials.p8PrivateKey!.trim());

      final fastfile = File(p.join(tempDirectory.path, 'Fastfile'));
      await fastfile.writeAsString(_fallbackFastfileSource);

      final bundleExecutable = _bundleExecutable(iosDirectory);
      final environment = <String, String>{
        'FASTLANE_SKIP_SCREEN': '1',
        'TTY_SCREEN_WIDTH': '120',
        'TTY_SCREEN_HEIGHT': '40',
        if (bundleExecutable != null)
          'BUNDLE_GEMFILE': _bundleGemfile(iosDirectory)!.path,
      };

      final target = [
        'ios',
        'arc_fetch_testflight_build',
        'app_identifier:${project.bundleId.trim()}',
        'version:${localVersion.name}',
        'key_id:${credentials.keyId!.trim()}',
        'issuer_id:${credentials.issuerId!.trim()}',
        'key_filepath:${keyFile.path}',
        if (credentials.hasTeamId) 'team_id:${credentials.teamId!.trim()}',
        'in_house:${credentials.inHouse}',
      ];

      final result = await runner.runCommandWithOutput(
        workingDirectory: tempDirectory.path,
        statusLabel: 'App Store ${project.name}',
        activePath: 'app-store:${project.id}',
        executable: bundleExecutable ?? runner.resolveFastlaneExecutable(),
        arguments: bundleExecutable == null
            ? target
            : ['exec', 'fastlane', ...target],
        environment: environment,
        clearLog: true,
      );

      if (result.exitCode != 0) {
        return AppStoreVersionSnapshot(
          localVersion: localVersion,
          status: AppStoreComparisonStatus.failed,
          message: 'Fastlane failed with exit code ${result.exitCode}.',
          lastCheckedAt: checkedAt,
        );
      }

      final testFlightBuild = parseTestFlightBuildNumber(result.output);
      if (testFlightBuild == null) {
        return AppStoreVersionSnapshot(
          localVersion: localVersion,
          status: AppStoreComparisonStatus.failed,
          message: 'Fastlane output did not include APPSTORE_BUILD_ONLY.',
          lastCheckedAt: checkedAt,
        );
      }

      return AppStoreVersionSnapshot(
        localVersion: localVersion,
        testFlightBuildNumber: testFlightBuild,
        status: compare(localVersion.buildNumber, testFlightBuild),
        message: 'Checked TestFlight ${localVersion.name}.',
        lastCheckedAt: checkedAt,
      );
    } finally {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  }

  String? _bundleExecutable(Directory iosDirectory) {
    final gemfile = _bundleGemfile(iosDirectory);
    if (gemfile == null) return null;
    return runner.resolveBundleExecutable();
  }

  File? _bundleGemfile(Directory iosDirectory) {
    final candidates = [
      File(p.join(iosDirectory.path, 'fastlane', 'Gemfile')),
      File(p.join(iosDirectory.path, 'Gemfile')),
    ];

    for (final candidate in candidates) {
      if (candidate.existsSync()) return candidate;
    }

    return null;
  }

  static int? parseTestFlightBuildNumber(String output) {
    final marker = RegExp(
      r'APPSTORE_BUILD_ONLY\s*:\s*(\d+)',
      caseSensitive: false,
    );
    final matches = marker.allMatches(output);
    if (matches.isEmpty) return null;

    return int.tryParse(matches.last.group(1)!);
  }

  static AppStoreComparisonStatus compare(int localBuild, int testFlightBuild) {
    if (localBuild < testFlightBuild) {
      return AppStoreComparisonStatus.localBehind;
    }
    if (localBuild > testFlightBuild) {
      return AppStoreComparisonStatus.localAhead;
    }
    return AppStoreComparisonStatus.upToDate;
  }
}

const _fallbackFastfileSource = '''
default_platform(:ios)

platform :ios do
  lane :arc_fetch_testflight_build do |options|
    key_id = options[:key_id].to_s
    issuer_id = options[:issuer_id].to_s
    key_filepath = options[:key_filepath].to_s
    app_identifier = options[:app_identifier].to_s
    version = options[:version].to_s
    team_id = options[:team_id].to_s
    in_house = options[:in_house].to_s.downcase == "true"

    api_key = app_store_connect_api_key(
      key_id: key_id,
      issuer_id: issuer_id,
      key_filepath: key_filepath,
      in_house: in_house
    )

    latest_options = {
      app_identifier: app_identifier,
      version: version,
      api_key: api_key
    }
    latest_options[:team_id] = team_id unless team_id.empty?

    latest = latest_testflight_build_number(**latest_options).to_i
    puts "APPSTORE_BUILD_ONLY:#{latest}"
    latest
  end
end
''';
