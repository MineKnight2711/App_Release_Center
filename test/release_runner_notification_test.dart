import 'dart:io';

import 'package:app_release_center/app/models/release_notification.dart';
import 'package:app_release_center/app/services/command_notification_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('command still succeeds when notification delivery fails', () async {
    final runner = ReleaseRunnerService(notificationService: _FailingSender());
    final tempDir = Directory.systemTemp.createTempSync('arc_notify_runner_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final code = await runner.runCommand(
      workingDirectory: tempDir.path,
      statusLabel: 'noop',
      activePath: 'test:noop',
      executable: Platform.isWindows ? 'cmd' : 'sh',
      arguments: Platform.isWindows
          ? const ['/c', 'exit', '0']
          : const ['-c', 'exit 0'],
      clearLog: true,
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(code, 0);
    expect(runner.status.value, 'Completed');
    expect(
      runner.logLines.any((line) => line.startsWith('Notification failed:')),
      isTrue,
    );
  });

  test(
    'final command notification includes bounded redacted log tail',
    () async {
      final sender = _RecordingSender();
      final runner = ReleaseRunnerService(notificationService: sender);
      final tempDir = Directory.systemTemp.createTempSync('arc_notify_runner_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final code = await runner.runCommand(
        workingDirectory: tempDir.path,
        statusLabel: 'secrets',
        activePath: 'test:secrets',
        executable: Platform.isWindows ? 'cmd' : 'sh',
        arguments: Platform.isWindows
            ? const [
                '/c',
                'echo token=abc123 && echo bearer abc123 && echo done',
              ]
            : const ['-c', 'printf "token=abc123\nbearer abc123\ndone\n"'],
        clearLog: true,
      );

      await _waitForEvents(sender, 2);

      expect(code, 0);
      expect(sender.events.first.event, CommandNotificationEventType.started);
      expect(sender.events.first.logTail, isEmpty);

      final finalEvent = sender.events.last;
      final joinedTail = finalEvent.logTail.join('\n');
      expect(finalEvent.event, CommandNotificationEventType.completed);
      expect(finalEvent.logTail.length, lessThanOrEqualTo(20));
      expect(joinedTail, contains('token=[redacted]'));
      expect(joinedTail, contains('bearer [redacted]'));
      expect(joinedTail, isNot(contains('abc123')));
    },
  );

  test('publishes completed progress for every standalone command', () async {
    final runner = ReleaseRunnerService();
    final tempDir = Directory.systemTemp.createTempSync('arc_progress_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final code = await _runNoop(runner, tempDir, label: 'standalone');

    expect(code, 0);
    expect(runner.workflowStep.value, 1);
    expect(runner.workflowTotalSteps.value, 1);
    expect(runner.overallProgress.value, 1);
    expect(runner.overallProgressLabel.value, contains('completed'));
    expect(runner.isWorkflowRunning.value, isFalse);
  });

  test('aggregates progress across a multi-command workflow', () async {
    final runner = ReleaseRunnerService();
    final tempDir = Directory.systemTemp.createTempSync('arc_progress_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    runner.beginWorkflow(totalSteps: 2, label: 'Deploy Demo');

    expect(
      await _runNoop(
        runner,
        tempDir,
        label: 'deploy',
        allowDuringWorkflow: true,
      ),
      0,
    );
    expect(runner.workflowStep.value, 1);
    expect(runner.overallProgress.value, 0.5);
    expect(runner.isBusy, isTrue);

    expect(
      await _runNoop(
        runner,
        tempDir,
        label: 'build apk',
        allowDuringWorkflow: true,
      ),
      0,
    );
    runner.finishWorkflow(success: true);

    expect(runner.workflowStep.value, 2);
    expect(runner.workflowTotalSteps.value, 2);
    expect(runner.overallProgress.value, 1);
    expect(runner.overallProgressLabel.value, 'Deploy Demo — completed');
    expect(runner.isBusy, isFalse);
  });
}

Future<int> _runNoop(
  ReleaseRunnerService runner,
  Directory workingDirectory, {
  required String label,
  bool allowDuringWorkflow = false,
}) {
  return runner.runCommand(
    workingDirectory: workingDirectory.path,
    statusLabel: label,
    activePath: 'test:$label',
    executable: Platform.isWindows ? 'cmd' : 'sh',
    arguments: Platform.isWindows
        ? const ['/c', 'exit', '0']
        : const ['-c', 'exit 0'],
    allowDuringWorkflow: allowDuringWorkflow,
  );
}

class _FailingSender implements CommandNotificationSender {
  @override
  Future<void> sendCommandEvent(CommandNotificationEvent event) async {
    throw Exception('offline');
  }
}

class _RecordingSender implements CommandNotificationSender {
  final events = <CommandNotificationEvent>[];

  @override
  Future<void> sendCommandEvent(CommandNotificationEvent event) async {
    events.add(event);
  }
}

Future<void> _waitForEvents(_RecordingSender sender, int count) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (sender.events.length >= count) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
