import 'package:app_management_center/app/services/api_monitor_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiMonitorService', () {
    late ApiMonitorService service;

    setUp(() {
      service = ApiMonitorService();
    });

    test('initializes with correct default dashboard URL', () {
      expect(
        service.dashboardUrl.value,
        'https://flow-api.hieupham101097.workers.dev/admin/dashboard',
      );
      expect(service.isWindowOpen, isFalse);
    });

    test('copyDashboardUrl copies the target URL to clipboard', () async {
      final log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        log.add(call);
        if (call.method == 'Clipboard.setData') {
          return null;
        }
        return null;
      });

      await service.copyDashboardUrl();

      expect(
        log.any(
          (call) =>
              call.method == 'Clipboard.setData' &&
              (call.arguments as Map)['text'] ==
                  'https://flow-api.hieupham101097.workers.dev/admin/dashboard',
        ),
        isTrue,
      );
    });
  });
}
