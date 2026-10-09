import 'dart:io';
import 'dart:typed_data';

import '../models/qa_models.dart';

class MobileDeviceService {
  const MobileDeviceService();

  String? validateSuite(QaSuite suite, DeviceInfo? device) {
    if (!suite.requiresDevice && !suite.requiresPhysicalDevice) return null;
    if (device == null) {
      return 'Suite cần thiết bị nhưng chưa chọn thiết bị.';
    }
    if (suite.requiresPhysicalDevice && !device.isPhysical) {
      return 'Suite cần điện thoại thật; ${device.name} là máy ảo.';
    }
    return null;
  }

  QaSuite bindRuntime(
    QaSuite suite, {
    required DeviceInfo device,
    required int appiumPort,
  }) {
    return suite.copyWith(
      arguments: suite.arguments
          .map(
            (argument) => argument
                .replaceAll('{deviceId}', device.id)
                .replaceAll('{deviceName}', device.name)
                .replaceAll('{appiumPort}', '$appiumPort'),
          )
          .toList(growable: false),
    );
  }

  Future<Uint8List> captureScreenshot(String deviceId) async {
    _validateDeviceId(deviceId);
    final result = await Process.run(
      'adb',
      ['-s', deviceId, 'exec-out', 'screencap', '-p'],
      runInShell: false,
      stdoutEncoding: null,
    );
    if (result.exitCode != 0) {
      throw StateError('adb screencap thất bại: ${result.stderr}');
    }
    final bytes = result.stdout;
    if (bytes is Uint8List) return bytes;
    return Uint8List.fromList(List<int>.from(bytes as List));
  }

  void _validateDeviceId(String value) {
    if (!RegExp(r'^[a-zA-Z0-9._:-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, 'deviceId', 'Device ID không hợp lệ');
    }
  }
}
