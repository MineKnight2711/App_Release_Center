import 'package:app_management_center/app/modules/qa_desk/services/device_discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses flutter devices machine output', () {
    const raw = '''
[
  {
    "name": "Pixel 8 API 35",
    "id": "emulator-5554",
    "isSupported": true,
    "targetPlatform": "android-arm64",
    "emulator": true,
    "category": "mobile",
    "sdk": "Android 15"
  }
]
''';

    final devices = const DeviceDiscoveryService().parseDevices(raw);

    expect(devices, hasLength(1));
    expect(devices.single.id, 'emulator-5554');
    expect(devices.single.isEmulator, isTrue);
    expect(devices.single.platform, 'android-arm64');
  });
}
