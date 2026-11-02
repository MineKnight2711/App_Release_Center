import 'dart:io';

import 'package:app_management_center/app/models/release_project.dart';
import 'package:app_management_center/app/models/release_script.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'macOS Bash preserves script paths across prompts and nested scripts',
    () async {
      final root = Directory.systemTemp.createTempSync('amc_shell_paths_');
      addTearDown(() => root.deleteSync(recursive: true));
      final auto = Directory(p.join(root.path, 'auto with spaces'))
        ..createSync();
      // ReleaseProject expects scripts in auto/.
      final projectRoot = Directory(p.join(auto.path, 'project'))..createSync();
      final scripts = Directory(p.join(projectRoot.path, 'auto'))..createSync();
      final originalStartup = File(p.join(root.path, 'original env.sh'))
        ..writeAsStringSync('export AMC_SHELL_TEST_ENV=preserved\n');
      final parent = File(p.join(scripts.path, 'parent.sh'))
        ..writeAsStringSync(r'''
set -euo pipefail
[[ "$0" == parent.sh && "$1" == "argument with spaces" ]]
read -r -p 'Parent continue? [Y/n] ' answer
echo "PARENT_SOURCE:${BASH_SOURCE[0]}"
IFS=. read -ra parts <<< '3.5.24'
echo "VERSION_PART:${parts[2]}"
read <<< '  bare read preserves spaces  '
echo "BARE_READ:$REPLY"
source './helper.sh'
"$BASH" './child with spaces.sh' 'child argument'
echo "ORIGINAL_ENV:$AMC_SHELL_TEST_ENV"
echo "STARTUP_FILE:$BASH_ENV"
''');
      File(p.join(scripts.path, 'helper.sh')).writeAsStringSync(r'''
read -r -p 'Helper input: ' helper
echo "HELPER_SOURCE:${BASH_SOURCE[0]}:$helper"
''');
      File(p.join(scripts.path, 'child with spaces.sh')).writeAsStringSync(r'''
set -euo pipefail
[[ "$1" == 'child argument' ]]
read -r -p 'Child choice (1/2/3): ' choice
echo "CHILD_SOURCE:${BASH_SOURCE[0]}:$choice"
''');
      final project = ReleaseProject(
        path: projectRoot.path,
        scripts: const [],
        fastlaneLanes: const [],
        hasLegacyDistributionPrompt: false,
        hasPlayReleaseTools: false,
      );
      final runner = ReleaseRunnerService();
      final running = runner.runWithOutput(
        project: project,
        script: ReleaseScript(path: parent.path, kind: ReleaseScriptKind.shell),
        args: const ['argument with spaces'],
        environment: {'BASH_ENV': originalStartup.path},
      );
      addTearDown(() async {
        if (runner.isRunning.value) await runner.stop();
        await running.timeout(const Duration(seconds: 5));
      });
      await _waitForPrompt(runner, 'Parent continue?');
      runner.sendInput('y');
      await _waitForPrompt(runner, 'Helper input:');
      runner.sendInput('helper value');
      await _waitForPrompt(runner, 'Child choice');
      runner.sendInput('1');
      final result = await running.timeout(const Duration(seconds: 5));

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('PARENT_SOURCE:parent.sh'));
      expect(result.output, contains('VERSION_PART:24'));
      expect(
        result.output,
        contains('BARE_READ:  bare read preserves spaces  '),
      );
      expect(result.output, contains('HELPER_SOURCE:./helper.sh:helper value'));
      expect(result.output, contains('CHILD_SOURCE:./child with spaces.sh:1'));
      expect(result.output, contains('ORIGINAL_ENV:preserved'));
      final startupPath = RegExp(
        r'STARTUP_FILE:([^\r\n]+)',
      ).firstMatch(result.output)!.group(1)!;
      expect(File(startupPath).existsSync(), isFalse);
      expect(originalStartup.existsSync(), isTrue);
    },
    skip: !Platform.isMacOS,
  );
}

Future<void> _waitForPrompt(ReleaseRunnerService runner, String prompt) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (runner.logLines.any((line) => line.contains(prompt))) return;
    if (runner.exitCode.value != null) break;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Missing prompt "$prompt": ${runner.logLines.join('\n')}');
}
