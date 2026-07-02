import 'package:app_release_center/app/models/release_notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes linked notification devices', () {
    final linkedAt = DateTime.utc(2026, 7, 1, 4, 5);
    final lastSeenAt = DateTime.utc(2026, 7, 1, 4, 6);
    final device = LinkedNotificationDevice(
      id: 'phone-1',
      displayName: 'Pixel',
      platform: 'Android',
      browser: 'Chrome',
      linkedAt: linkedAt,
      lastSeenAt: lastSeenAt,
    );

    final loaded = LinkedNotificationDevice.fromJson(device.toJson());

    expect(loaded.id, 'phone-1');
    expect(loaded.label, 'Pixel');
    expect(loaded.detail, 'Android / Chrome');
    expect(loaded.linkedAt.toUtc(), linkedAt);
    expect(loaded.lastSeenAt?.toUtc(), lastSeenAt);
  });

  test('serializes notification settings', () {
    const settings = ReleaseNotificationSettings(
      enabled: true,
      endpointBaseUrl: 'https://example.com/api',
      selectedDeviceIds: ['phone-1', 'phone-2'],
    );

    final loaded = ReleaseNotificationSettings.fromJson(settings.toJson());

    expect(loaded.enabled, isTrue);
    expect(loaded.endpointBaseUrl, 'https://example.com/api');
    expect(loaded.selectedDeviceIds, ['phone-1', 'phone-2']);
  });

  test('serializes command notification events', () {
    final startedAt = DateTime.utc(2026, 7, 1, 4, 5);
    final finishedAt = DateTime.utc(2026, 7, 1, 4, 6);
    final event = CommandNotificationEvent(
      runId: 'run-1',
      event: CommandNotificationEventType.completed,
      command: 'fastlane android deploy',
      statusLabel: 'deploy',
      activePath: 'fastlane:android:deploy',
      projectName: 'Demo',
      startedAt: startedAt,
      finishedAt: finishedAt,
      durationMs: 60000,
      exitCode: 0,
      targetDeviceIds: const ['phone-1'],
    );

    final loaded = CommandNotificationEvent.fromJson(event.toJson());

    expect(loaded.runId, 'run-1');
    expect(loaded.event, CommandNotificationEventType.completed);
    expect(loaded.command, 'fastlane android deploy');
    expect(loaded.projectName, 'Demo');
    expect(loaded.startedAt.toUtc(), startedAt);
    expect(loaded.finishedAt?.toUtc(), finishedAt);
    expect(loaded.durationMs, 60000);
    expect(loaded.exitCode, 0);
    expect(loaded.targetDeviceIds, ['phone-1']);
  });
}
