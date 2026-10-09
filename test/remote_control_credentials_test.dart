import 'dart:convert';

import 'package:app_management_center/app/data/release_center_connect.dart';
import 'package:app_management_center/app/models/remote_control.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/mobile_control_credential_store_service.dart';
import 'package:app_management_center/app/services/notification_credential_store_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:app_management_center/app/services/remote_control_service.dart';
import 'package:app_management_center/app/services/script_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<_Harness> _buildHarness({
  Map<String, Object> preferences = const {},
}) async {
  SharedPreferences.setMockInitialValues(Map<String, Object>.from(preferences));
  final store = await ProjectStoreService().init();
  final secureStore = _MemorySecureKeyValueStore();
  final mobileCredentials = MobileControlCredentialStoreService(
    secureStore: secureStore,
  );
  final desktopCredentials = NotificationCredentialStoreService(
    secureStore: _MemorySecureKeyValueStore(),
  );
  final service = RemoteControlService(
    store: store,
    catalog: ScriptCatalogService(),
    runner: ReleaseRunnerService(),
    connect: ReleaseCenterConnect(),
    credentialStore: desktopCredentials,
    mobileCredentialStore: mobileCredentials,
  );
  return _Harness(
    store: store,
    secureStore: secureStore,
    credentials: mobileCredentials,
    desktopCredentials: desktopCredentials,
    service: service,
  );
}

void main() {
  tearDown(Get.reset);

  test('moves a token left in preferences into secure storage', () async {
    final harness = await _buildHarness(
      preferences: {
        'mobile_control_settings': jsonEncode({
          'endpointBaseUrl': 'https://relay.example.com/api',
          'deviceControlToken': 'legacy-token',
          'deviceId': 'device-1',
        }),
      },
    );

    await harness.service.init();

    expect(
      await harness.credentials.readControlToken(),
      'legacy-token',
      reason: 'the token should end up in secure storage',
    );
    expect(
      await harness.storedPreferencesEntry(),
      isNot(contains('legacy-token')),
      reason: 'preferences should no longer hold a copy',
    );
    // The link itself survives the move.
    final settings = harness.service.mobileSettings.value;
    expect(settings.deviceControlToken, 'legacy-token');
    expect(settings.endpointBaseUrl, 'https://relay.example.com/api');
    expect(settings.deviceId, 'device-1');
    expect(settings.isLinked, isTrue);
  });

  test(
    'prefers the secure token and still scrubs a stale preference copy',
    () async {
      final harness = await _buildHarness(
        preferences: {
          'mobile_control_settings': jsonEncode({
            'endpointBaseUrl': 'https://relay.example.com/api',
            'deviceControlToken': 'stale-token',
            'deviceId': 'device-1',
          }),
        },
      );
      await harness.credentials.saveControlToken('current-token');

      await harness.service.init();

      expect(
        harness.service.mobileSettings.value.deviceControlToken,
        'current-token',
      );
      expect(await harness.credentials.readControlToken(), 'current-token');
      expect(
        await harness.storedPreferencesEntry(),
        isNot(contains('stale-token')),
      );
    },
  );

  test('reads a link that only exists in secure storage', () async {
    final harness = await _buildHarness(
      preferences: {
        'mobile_control_settings': jsonEncode({
          'endpointBaseUrl': 'https://relay.example.com/api',
          'deviceId': 'device-1',
        }),
      },
    );
    await harness.credentials.saveControlToken('secure-token');

    await harness.service.init();

    expect(
      harness.service.mobileSettings.value.deviceControlToken,
      'secure-token',
    );
    expect(harness.service.mobileSettings.value.isLinked, isTrue);
  });

  test('stays unlinked when there is nothing stored', () async {
    final harness = await _buildHarness();

    await harness.service.init();

    expect(harness.service.mobileSettings.value.isLinked, isFalse);
    expect(await harness.credentials.readControlToken(), isNull);
  });

  test(
    'migrates the retired Render relay and requires a fresh pairing',
    () async {
      final harness = await _buildHarness(
        preferences: {
          'release_notification_settings': jsonEncode({
            'enabled': true,
            'endpointBaseUrl':
                'https://app-release-center-notifications.onrender.com/api',
            'selectedDeviceIds': <String>['old-device'],
          }),
          'mobile_control_settings': jsonEncode({
            'endpointBaseUrl':
                'https://app-release-center-notifications.onrender.com/api',
            'deviceId': 'old-device',
          }),
        },
      );
      await harness.credentials.saveControlToken('old-relay-token');
      await harness.desktopCredentials.saveApiToken('old-desktop-token');

      await harness.service.init();

      expect(
        harness.store.notificationSettings.endpointBaseUrl,
        RemoteControlService.relayEndpoint,
      );
      expect(harness.store.notificationSettings.selectedDeviceIds, isEmpty);
      expect(
        harness.service.mobileSettings.value.endpointBaseUrl,
        RemoteControlService.relayEndpoint,
      );
      expect(harness.service.mobileSettings.value.isLinked, isFalse);
      expect(await harness.credentials.readControlToken(), isNull);
      expect(
        await harness.desktopCredentials.readApiToken(),
        isNull,
        reason:
            'the Render token cannot authenticate against the Worker, and '
            'keeping it only turns pairing into an unexplained 401',
      );
      expect(harness.store.linkedNotificationDevices, isEmpty);
    },
  );

  test(
    'leaves a token alone when the endpoint is already the Worker',
    () async {
      final harness = await _buildHarness(
        preferences: {
          'release_notification_settings': jsonEncode({
            'enabled': true,
            'endpointBaseUrl': RemoteControlService.relayEndpoint,
            'selectedDeviceIds': <String>['device-1'],
          }),
        },
      );
      await harness.desktopCredentials.saveApiToken('worker-token');

      await harness.service.init();

      expect(await harness.desktopCredentials.readApiToken(), 'worker-token');
      expect(harness.store.notificationSettings.selectedDeviceIds, [
        'device-1',
      ]);
    },
  );

  test('clearing the link deletes the secure token', () async {
    final harness = await _buildHarness();
    await harness.credentials.saveControlToken('secure-token');
    await harness.service.init();

    await harness.service.clearMobileLink();

    expect(await harness.credentials.readControlToken(), isNull);
    expect(harness.service.mobileSettings.value.isLinked, isFalse);
  });

  test('never writes the token to preferences when saving a link', () async {
    final harness = await _buildHarness();

    await harness.store.saveMobileControlSettings(
      const MobileControlSettings(
        endpointBaseUrl: 'https://relay.example.com/api',
        deviceControlToken: 'should-not-be-persisted',
        deviceId: 'device-1',
      ),
    );

    expect(
      await harness.storedPreferencesEntry(),
      isNot(contains('should-not-be-persisted')),
    );
    expect(await harness.storedPreferencesEntry(), contains('device-1'));
  });

  group('permission gates', () {
    test('default to closed and survive a round trip', () async {
      final harness = await _buildHarness();
      await harness.service.init();

      expect(harness.service.settings.value.allowPowerControl, isFalse);
      expect(harness.service.settings.value.allowWindowControl, isFalse);
      expect(harness.service.settings.value.allowRemoteUnlock, isFalse);

      await harness.service.setAllowPowerControl(true);
      await harness.service.setAllowWindowControl(true);
      await harness.service.setAllowRemoteUnlock(true);

      final reloaded = harness.store.remoteControlSettings;
      expect(reloaded.allowPowerControl, isTrue);
      expect(reloaded.allowWindowControl, isTrue);
      expect(reloaded.allowRemoteUnlock, isTrue);
    });

    test('stay closed for settings written before the gates existed', () async {
      final harness = await _buildHarness(
        preferences: {
          'remote_control_settings': jsonEncode({
            'enabled': true,
            'desktopId': 'default',
            'allowedRoots': <String>['C:\\Demo'],
          }),
        },
      );

      await harness.service.init();

      expect(harness.service.settings.value.enabled, isTrue);
      expect(harness.service.settings.value.allowPowerControl, isFalse);
      expect(harness.service.settings.value.allowWindowControl, isFalse);
      expect(harness.service.settings.value.allowRemoteUnlock, isFalse);
    });

    test('allowed apps are trimmed and de-duplicated', () async {
      final harness = await _buildHarness();
      await harness.service.init();

      await harness.service.saveAllowedApps([
        r'C:\Apps\one.exe',
        '  ',
        r'C:\Apps\one.exe',
        r'  C:\Apps\two.exe  ',
      ]);

      expect(harness.service.settings.value.allowedApps, [
        r'C:\Apps\one.exe',
        r'C:\Apps\two.exe',
      ]);
    });
  });
}

class _Harness {
  _Harness({
    required this.store,
    required this.secureStore,
    required this.credentials,
    required this.desktopCredentials,
    required this.service,
  });

  final ProjectStoreService store;
  final _MemorySecureKeyValueStore secureStore;
  final MobileControlCredentialStoreService credentials;
  final NotificationCredentialStoreService desktopCredentials;
  final RemoteControlService service;

  /// The raw JSON preferences hold for the phone link, or '' when absent.
  ///
  /// Read straight from SharedPreferences on purpose: going back through
  /// [MobileControlSettings.toJson] would drop the token itself and make every
  /// assertion about scrubbing pass for the wrong reason.
  Future<String> storedPreferencesEntry() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString('mobile_control_settings') ?? '';
  }
}

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}
