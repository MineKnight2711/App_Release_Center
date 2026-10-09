import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/mobile_device_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = MobileDeviceService();
  const emulator = DeviceInfo(
    id: 'emulator-5554',
    name: 'Pixel 8',
    platform: 'android-arm64',
    category: 'mobile',
    isEmulator: true,
  );

  test('binds device and Appium placeholders without invoking a shell', () {
    const suite = QaSuite(
      id: 'mobile-smoke',
      name: 'Mobile smoke',
      executable: 'flutter',
      arguments: [
        'test',
        '-d',
        '{deviceId}',
        '--dart-define=PORT={appiumPort}',
      ],
      requiresDevice: true,
    );

    final bound = service.bindRuntime(
      suite,
      device: emulator,
      appiumPort: 4723,
    );

    expect(bound.arguments, [
      'test',
      '-d',
      'emulator-5554',
      '--dart-define=PORT=4723',
    ]);
  });

  test('rejects an emulator for a physical-device suite', () {
    const suite = QaSuite(
      id: 'nfc',
      name: 'NFC',
      executable: 'flutter',
      arguments: ['test'],
      requiresPhysicalDevice: true,
    );

    expect(service.validateSuite(suite, emulator), contains('điện thoại thật'));
  });

  test('requires a selected device for mobile suites', () {
    const suite = QaSuite(
      id: 'mobile',
      name: 'Mobile',
      executable: 'adb',
      arguments: ['get-state'],
      requiresDevice: true,
    );

    expect(service.validateSuite(suite, null), contains('chưa chọn'));
  });
}
