import 'dart:convert';
import 'package:app_management_center/app/services/app_background_service.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/remote_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('amc/test_background');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'disabling reminders leaves remote host alive; quit drains all owners before native termination',
    () async {
      final service = AppBackgroundService(channel: channel);
      final drained = <String>[];
      service.register(
        'reminders',
        shutdown: () async => drained.add('reminders'),
      );
      service.register(
        'remoteHost',
        shutdown: () async => drained.add('remote'),
      );
      await service.reason('reminders', true);
      await service.reason('remoteHost', true);
      await service.reason('reminders', false);
      expect(service.enabled, isTrue);
      expect((calls.last.arguments as Map)['enabled'], isTrue);
      expect((calls.last.arguments as Map)['remote'], isTrue);
      await service.quit();
      expect(drained, ['remote', 'reminders']);
      expect(calls.last.method, 'quitNow');
    },
  );
  test(
    'failed tray update rolls back the reason and later updates remain usable',
    () async {
      var fail = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            if (fail) throw PlatformException(code: 'tray');
            return null;
          });
      final service = AppBackgroundService(channel: channel);
      await expectLater(
        service.reason('remoteHost', true),
        throwsA(isA<PlatformException>()),
      );
      expect(service.enabled, isFalse);
      fail = false;
      await service.reason('remoteHost', true);
      expect(service.enabled, isTrue);
    },
  );
  test(
    'legacy import allowlists metadata, requires re-pairing, is idempotent and preserves existing aliases',
    () async {
      final source = jsonEncode({
        'password': 'DO-NOT-IMPORT',
        'hostSecret': 'SECRET',
        'trustedControllers': [
          {'token': 'SECRET'},
        ],
        'savedDevices': [
          {
            'name': 'Old Mac',
            'ip': '192.168.1.8',
            'port': 9876,
            'platform': 'darwin',
            'trustToken': 'SECRET',
            'savedPassword': 'SECRET',
          },
        ],
      });
      final preview = LegacyRemoteImport.preview(source);
      expect(jsonEncode(preview), isNot(contains('SECRET')));
      expect(preview.single['needsPairing'], isTrue);
      final settings = SwiftDeskSettings();
      expect(await LegacyRemoteImport.apply(settings, preview), 1);
      preview.single['name'] = 'Changed source';
      expect(await LegacyRemoteImport.apply(settings, preview), 0);
      expect(settings.metadata('legacyDevices').single['name'], 'Old Mac');
      expect(settings.flag('restoreHost'), isFalse);
      expect(settings.flag('restoreInternet'), isFalse);
    },
  );
}
