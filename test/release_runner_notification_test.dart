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
}

class _FailingSender implements CommandNotificationSender {
  @override
  Future<void> sendCommandEvent(CommandNotificationEvent event) async {
    throw Exception('offline');
  }
}
