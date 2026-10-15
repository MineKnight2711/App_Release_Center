import 'dart:io';

import 'package:app_management_center/app/models/release_notification.dart';
import 'package:flutter/services.dart';

/// The phone's side of release notifications: permission, FCM token, and the
/// notification channels that carry their own sound and vibration.
///
/// Lives in the Android runner (MainActivity, ReleaseNotifications.kt) rather
/// than a Firebase plugin, so the desktop builds carry no Firebase at all.
class ReleasePushDevice {
  ReleasePushDevice({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('amc/release_push'),
      supported = supported ?? Platform.isAndroid;

  final MethodChannel _channel;
  final bool supported;

  Future<ReleasePushDeviceStatus> status() async {
    if (!supported) return const ReleasePushDeviceStatus();
    final result = await _channel.invokeMapMethod<String, Object?>('status');
    return ReleasePushDeviceStatus(
      available: result?['available'] == true,
      canPost: result?['canPost'] == true,
    );
  }

  /// Asks for the notification permission where Android needs it (13+).
  /// Returns whether notifications can be shown afterwards.
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  Future<String> token() async =>
      await _channel.invokeMethod<String>('token') ?? '';

  Future<void> deleteToken() => _channel.invokeMethod<void>('deleteToken');

  /// Shows a local notification on the outcome's channel: the real sound and
  /// buzz, without the relay or the desktop.
  Future<bool> test(ReleasePushOutcome outcome) async =>
      await _channel.invokeMethod<bool>('test', {
        'outcome': outcome.name,
        'title': outcome == ReleasePushOutcome.succeeded
            ? 'Thử: release xong'
            : 'Thử: release lỗi',
        'body': outcome == ReleasePushOutcome.succeeded
            ? 'Đây là âm thanh và nhịp rung khi một release chạy xong.'
            : 'Đây là âm thanh và nhịp rung khi một release dừng vì lỗi.',
      }) ??
      false;

  /// The system screen where the sound or vibration of one outcome can be
  /// changed. Android owns those settings once the channel exists.
  Future<void> openSettings([ReleasePushOutcome? outcome]) =>
      _channel.invokeMethod<void>('openSettings', {'outcome': outcome?.name});
}

class ReleasePushDeviceStatus {
  const ReleasePushDeviceStatus({this.available = false, this.canPost = false});

  /// Firebase is configured in this build of the app.
  final bool available;

  /// The system will show our notifications (permission granted, not blocked).
  final bool canPost;
}
