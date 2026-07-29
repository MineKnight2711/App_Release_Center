import 'dart:io';

import 'package:app_release_center/app/models/ch_play_credentials.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/models/ch_play_version_snapshot.dart';
import 'package:app_release_center/app/services/ch_play_project_inspector_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

class ChPlayVersionCheckService extends GetxService {
  ChPlayVersionCheckService({required this.inspector, required this.runner});

  final ChPlayProjectInspectorService inspector;
  final ReleaseRunnerService runner;

  Future<ChPlayVersionSnapshot> readLocalSnapshot(ChPlayProject project) async {
    final localVersion = await inspector.readLocalVersion(project.path);
    if (localVersion == null) {
      return const ChPlayVersionSnapshot(
        status: ChPlayComparisonStatus.missingLocalVersion,
        message: 'pubspec.yaml version must use name+code format.',
      );
    }

    return ChPlayVersionSnapshot(localVersion: localVersion);
  }

  Future<ChPlayVersionSnapshot> refreshProject({
    required ChPlayProject project,
    required ChPlayCredentials credentials,
    bool clearLog = true,
    bool allowDuringWorkflow = false,
    bool trackWorkflowStep = true,
  }) async {
    final localVersion = await inspector.readLocalVersion(project.path);
    final checkedAt = DateTime.now();

    if (localVersion == null) {
      return ChPlayVersionSnapshot(
        status: ChPlayComparisonStatus.missingLocalVersion,
        message: 'pubspec.yaml version must use name+code format.',
        lastCheckedAt: checkedAt,
      );
    }

    if (!credentials.hasGooglePlayJson) {
      return ChPlayVersionSnapshot(
        localVersion: localVersion,
        status: ChPlayComparisonStatus.missingCredentials,
        message: 'Import a Google Play service-account JSON key.',
        lastCheckedAt: checkedAt,
      );
    }

    if (project.applicationId.trim().isEmpty) {
      return ChPlayVersionSnapshot(
        localVersion: localVersion,
        status: ChPlayComparisonStatus.failed,
        message: 'Application ID is required.',
        lastCheckedAt: checkedAt,
      );
    }

    final androidDirectory = Directory(p.join(project.path, 'android'));
    if (!androidDirectory.existsSync()) {
      return ChPlayVersionSnapshot(
        localVersion: localVersion,
        status: ChPlayComparisonStatus.failed,
        message: 'Project does not contain an android folder.',
        lastCheckedAt: checkedAt,
      );
    }

    final tempDirectory = await Directory.systemTemp.createTemp(
      'app_release_center_play_',
    );
    try {
      final jsonFile = File(p.join(tempDirectory.path, 'google-play-key.json'));
      await jsonFile.writeAsString(credentials.googlePlayJson!.trim());

      final invocation = await _buildInvocation(
        project: project,
        androidDirectory: androidDirectory,
        tempDirectory: tempDirectory,
        jsonKeyPath: jsonFile.path,
      );

      final result = await runner.runCommandWithOutput(
        workingDirectory: invocation.workingDirectory,
        statusLabel: invocation.statusLabel,
        activePath: 'ch-play:${project.id}',
        executable: invocation.executable,
        arguments: invocation.arguments,
        environment: invocation.environment,
        clearLog: clearLog,
        allowDuringWorkflow: allowDuringWorkflow,
        trackWorkflowStep: trackWorkflowStep,
      );

      if (result.exitCode != 0) {
        return ChPlayVersionSnapshot(
          localVersion: localVersion,
          status: ChPlayComparisonStatus.failed,
          message: 'Fastlane failed with exit code ${result.exitCode}.',
          lastCheckedAt: checkedAt,
        );
      }

      final storeCode = parseStoreVersionCode(result.output);
      if (storeCode == null) {
        return ChPlayVersionSnapshot(
          localVersion: localVersion,
          status: ChPlayComparisonStatus.failed,
          message: 'Fastlane output did not include STORE_CODE_ONLY.',
          lastCheckedAt: checkedAt,
        );
      }

      return ChPlayVersionSnapshot(
        localVersion: localVersion,
        storeVersionCode: storeCode,
        status: compare(localVersion.code, storeCode),
        message: 'Checked ${project.track}.',
        lastCheckedAt: checkedAt,
      );
    } finally {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  }

  Future<_FastlaneInvocation> _buildInvocation({
    required ChPlayProject project,
    required Directory androidDirectory,
    required Directory tempDirectory,
    required String jsonKeyPath,
  }) async {
    final bundleExecutable = _bundleExecutable(androidDirectory);
    final baseEnvironment = <String, String>{
      'FASTLANE_SKIP_SCREEN': '1',
      'TTY_SCREEN_WIDTH': '120',
      'TTY_SCREEN_HEIGHT': '40',
      'FASTLANE_KEY_PATH': jsonKeyPath,
      'ANDROID_PACKAGE_NAME': project.applicationId.trim(),
      'PLAY_TRACK': project.track.trim().isEmpty
          ? 'production'
          : project.track.trim(),
      if (bundleExecutable != null)
        'BUNDLE_GEMFILE': _bundleGemfile(androidDirectory)!.path,
    };

    final existingLane = _findFetchVersionLane(project.path);
    if (existingLane != null) {
      final target = [
        if (existingLane.platform != null) existingLane.platform!,
        _fetchVersionLaneName,
        'track:${baseEnvironment['PLAY_TRACK']}',
      ];
      return _FastlaneInvocation(
        workingDirectory: androidDirectory.path,
        statusLabel: 'CH Play ${project.name}',
        executable: bundleExecutable ?? runner.resolveFastlaneExecutable(),
        arguments: bundleExecutable == null
            ? target
            : ['exec', 'fastlane', ...target],
        environment: baseEnvironment,
      );
    }

    final fastfile = File(p.join(tempDirectory.path, 'Fastfile'));
    await fastfile.writeAsString(_fallbackFastfileSource);

    final target = [
      'android',
      'arc_fetch_store_code',
      'package_name:${project.applicationId.trim()}',
      'track:${baseEnvironment['PLAY_TRACK']}',
      'json_key:$jsonKeyPath',
    ];
    return _FastlaneInvocation(
      workingDirectory: tempDirectory.path,
      statusLabel: 'CH Play ${project.name}',
      executable: bundleExecutable ?? runner.resolveFastlaneExecutable(),
      arguments: bundleExecutable == null
          ? target
          : ['exec', 'fastlane', ...target],
      environment: baseEnvironment,
    );
  }

  String? _bundleExecutable(Directory androidDirectory) {
    final gemfile = _bundleGemfile(androidDirectory);
    if (gemfile == null) return null;
    return runner.resolveBundleExecutable();
  }

  File? _bundleGemfile(Directory androidDirectory) {
    final candidates = [
      File(p.join(androidDirectory.path, 'fastlane', 'Gemfile')),
      File(p.join(androidDirectory.path, 'Gemfile')),
    ];

    for (final candidate in candidates) {
      if (candidate.existsSync()) return candidate;
    }

    return null;
  }

  _FastlaneLaneTarget? _findFetchVersionLane(String projectPath) {
    final fastfile = File(
      p.join(projectPath, 'android', 'fastlane', 'Fastfile'),
    );
    if (!fastfile.existsSync()) return null;

    final lanePattern = RegExp(r'^\s*lane\s+:([A-Za-z0-9_]+)\s+do\b');
    final platformPattern = RegExp(r'^\s*platform\s+:([A-Za-z0-9_]+)\s+do\b');
    final defaultPlatformPattern = RegExp(
      r'^\s*default_platform\(\s*:([A-Za-z0-9_]+)\s*\)',
    );

    String? currentPlatform;
    String? defaultPlatform;
    for (final line in fastfile.readAsLinesSync()) {
      final defaultMatch = defaultPlatformPattern.firstMatch(line);
      if (defaultMatch != null) {
        defaultPlatform = defaultMatch.group(1);
        continue;
      }

      final platformMatch = platformPattern.firstMatch(line);
      if (platformMatch != null) {
        currentPlatform = platformMatch.group(1);
        continue;
      }

      final laneMatch = lanePattern.firstMatch(line);
      if (laneMatch?.group(1) == _fetchVersionLaneName) {
        return _FastlaneLaneTarget(
          platform: currentPlatform ?? defaultPlatform,
        );
      }
    }

    return null;
  }

  static int? parseStoreVersionCode(String output) {
    final patterns = [
      RegExp(r'STORE_CODE_ONLY\s*:\s*(\d+)', caseSensitive: false),
      RegExp(r'Current\s+version\s+code[^:\d]*:\s*(\d+)', caseSensitive: false),
      RegExp(r'version\s+code\s+on[^:\d]*:\s*(\d+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final matches = pattern.allMatches(output);
      if (matches.isEmpty) continue;

      return int.tryParse(matches.last.group(1)!);
    }

    return null;
  }

  static ChPlayComparisonStatus compare(int localCode, int storeCode) {
    if (localCode < storeCode) return ChPlayComparisonStatus.localBehind;
    if (localCode > storeCode) return ChPlayComparisonStatus.localAhead;
    return ChPlayComparisonStatus.upToDate;
  }
}

class _FastlaneInvocation {
  const _FastlaneInvocation({
    required this.workingDirectory,
    required this.statusLabel,
    required this.executable,
    required this.arguments,
    required this.environment,
  });

  final String workingDirectory;
  final String statusLabel;
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
}

class _FastlaneLaneTarget {
  const _FastlaneLaneTarget({this.platform});

  final String? platform;
}

const _fetchVersionLaneName = 'fetch_version_code_from_play_store';

const _fallbackFastfileSource = '''
default_platform(:android)

platform :android do
  lane :arc_fetch_store_code do |options|
    package_name = options[:package_name].to_s
    track = options[:track].to_s.empty? ? "production" : options[:track].to_s
    json_key = options[:json_key].to_s

    codes = google_play_track_version_codes(
      package_name: package_name,
      track: track,
      json_key: json_key
    )

    latest = codes.map(&:to_i).max || 0
    puts "STORE_CODE_ONLY:#{latest}"
    latest
  end
end
''';
