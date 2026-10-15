import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:path/path.dart' as p;

/// Runs git for real and stands in for Xcode, Flutter and Fastlane, so a Mac
/// build host can be driven end to end on any machine. What the host does
/// with source — clone, fetch, checkout, hash — is the real thing.
class FakeMacRunner extends ReleaseRunnerService {
  final appleActions = <String>[];
  String bundleId = 'com.example.demo';
  String processingState = 'VALID';
  String buildName = '';
  String buildNumber = '';
  bool uploaded = false;
  int buildCalls = 0;

  @override
  String resolveFlutterExecutable() => 'flutter';
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
    if (executable == 'git') {
      return super.runCommandWithOutput(
        workingDirectory: workingDirectory,
        statusLabel: statusLabel,
        activePath: activePath,
        executable: executable,
        arguments: arguments,
        displayArguments: displayArguments,
        environment: environment,
        clearLog: clearLog,
        projectName: projectName,
        allowDuringWorkflow: allowDuringWorkflow,
        trackWorkflowStep: trackWorkflowStep,
      );
    }
    appendSystemLog('\$ $executable ${arguments.join(' ')}');
    var output = '';
    switch (executable) {
      case '/usr/bin/security':
        output = '1) ABC "Apple Distribution: Demo (TEAM)"\n1 valid identities';
      case '/usr/bin/xcodebuild' when arguments.contains('-showBuildSettings'):
        output = jsonEncode([
          {
            'target': 'Runner',
            'buildSettings': {
              'PRODUCT_TYPE': 'com.apple.product-type.application',
              'PRODUCT_BUNDLE_IDENTIFIER': bundleId,
              'DEVELOPMENT_TEAM': 'TEAM',
            },
          },
        ]);
      case 'flutter' when arguments.take(2).join(' ') == 'build ipa':
        buildCalls++;
        buildName = _flag(arguments, '--build-name');
        buildNumber = _flag(arguments, '--build-number');
        final directory = await Directory(
          p.join(workingDirectory, 'build', 'ios', 'ipa'),
        ).create(recursive: true);
        await File(p.join(directory.path, 'demo.ipa')).writeAsString('IPA');
      case '/usr/bin/unzip' when arguments.first == '-Z1':
        output = 'Payload/Runner.app/Info.plist\n';
      case '/usr/bin/plutil':
        output = jsonEncode({
          'CFBundleIdentifier': bundleId,
          'CFBundleShortVersionString': buildName,
          'CFBundleVersion': buildNumber,
        });
      case 'fastlane' || 'bundle':
        final input =
            jsonDecode(
                  await File(
                    arguments.last.substring('input:'.length),
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        final action = input['action'] as String;
        appleActions.add(action);
        if (action == 'upload') uploaded = true;
        output =
            'AMC_IOS_RESULT:${jsonEncode({
              'builds': [
                {'id': 'old', 'version': '1.2.3', 'number': '10', 'state': 'VALID'},
                if (uploaded) {'id': 'new', 'version': buildName, 'number': buildNumber, 'state': processingState},
              ],
              'versions': const [],
            })}\n';
    }
    return CommandRunResult(exitCode: 0, output: output);
  }

  static String _flag(List<String> arguments, String name) => arguments
      .firstWhere((argument) => argument.startsWith('$name='))
      .substring(name.length + 1);
}

class MemorySecureStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async =>
      values[key] = value;

  @override
  Future<void> delete({required String key}) async => values.remove(key);
}

/// An origin repository and a working clone of it, the way a Flutter project
/// sits on the desktop that sends the build.
class TestRepository {
  TestRepository._(this.origin, this.clone, this.commit);

  final String origin;
  final String clone;
  final String commit;

  static Future<TestRepository> create(Directory parent) async {
    final seed = await Directory(p.join(parent.path, 'seed')).create();
    await git(['init', '-q', '-b', 'main'], seed.path);
    await _identity(seed.path);
    final files = {
      'pubspec.yaml': 'name: demo\nversion: 1.2.3+10\n',
      'lib/main.dart': 'void main() {}\n',
      '.gitignore': '.env\n/build/\n',
      'ios/Runner.xcworkspace/contents.xcworkspacedata': '<Workspace/>\n',
    };
    for (final entry in files.entries) {
      final file = File(p.join(seed.path, entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
    await git(['add', '-A'], seed.path);
    await git(['commit', '-q', '-m', 'init'], seed.path);
    final origin = p.join(parent.path, 'origin.git');
    await git(['clone', '-q', '--bare', seed.path, origin], parent.path);
    final clone = p.join(parent.path, 'desktop');
    await git(['clone', '-q', origin, clone], parent.path);
    await _identity(clone);
    await File(p.join(clone, '.env')).writeAsString('API=production\n');
    return TestRepository._(
      origin,
      clone,
      await git(['rev-parse', 'HEAD'], clone),
    );
  }

  static Future<void> _identity(String directory) async {
    await git(['config', 'user.email', 'test@example.com'], directory);
    await git(['config', 'user.name', 'Test'], directory);
  }
}

Future<String> git(List<String> arguments, String directory) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')}: ${result.stderr}');
  }
  return result.stdout.toString().trim();
}
