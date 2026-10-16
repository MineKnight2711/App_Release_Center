import 'package:app_management_center/app/data/release_center_connect.dart';
import 'package:app_management_center/app/models/release_notification.dart';
import 'package:app_management_center/app/models/remote_control.dart';
import 'package:app_management_center/app/services/mobile_control_credential_store_service.dart';
import 'package:app_management_center/app/services/notification_credential_store_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:app_management_center/app/services/release_push_device.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:app_management_center/app/services/remote_control_service.dart';
import 'package:app_management_center/app/services/script_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ios_build_host_fakes.dart';

void main() {
  late ProjectStoreService store;
  late _Relay relay;
  late _Device device;

  Future<RemoteControlService> phone() async {
    final tokens = MobileControlCredentialStoreService(
      secureStore: MemorySecureStore(),
    );
    await tokens.saveControlToken('phone-token');
    return RemoteControlService(
      store: store,
      catalog: ScriptCatalogService(),
      runner: ReleaseRunnerService(),
      connect: relay,
      credentialStore: NotificationCredentialStoreService(
        secureStore: MemorySecureStore(),
      ),
      mobileCredentialStore: tokens,
      releasePushDevice: device,
    ).init();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await ProjectStoreService().init();
    await store.saveMobileControlSettings(
      const MobileControlSettings(
        endpointBaseUrl: 'https://relay.test/api',
        deviceId: 'phone-1',
      ),
    );
    relay = _Relay();
    device = _Device();
  });

  test('turning it on hands the relay this phone\'s FCM token', () async {
    final remote = await phone();
    await remote.setReleasePushEnabled(true);

    expect(device.permissionRequests, 1);
    expect(relay.tokens, ['fcm-1']);
    expect(relay.headers.single['Authorization'], 'Bearer phone-token');
    expect(remote.mobileSettings.value.releasePushEnabled, isTrue);
    expect(store.mobileControlSettings.releasePushToken, 'fcm-1');
  });

  test('a token that rotated while closed is handed over at launch', () async {
    await store.saveMobileControlSettings(
      const MobileControlSettings(
        endpointBaseUrl: 'https://relay.test/api',
        releasePushEnabled: true,
        releasePushToken: 'fcm-old',
      ),
    );
    device.currentToken = 'fcm-new';
    await phone();
    await Future<void>.delayed(Duration.zero);

    expect(relay.tokens, ['fcm-new']);
    expect(store.mobileControlSettings.releasePushToken, 'fcm-new');
  });

  test('without notification permission nothing is registered', () async {
    device.granted = false;
    final remote = await phone();

    await expectLater(
      remote.setReleasePushEnabled(true),
      throwsA(isA<RemoteControlException>()),
    );
    expect(relay.tokens, isEmpty);
    expect(remote.mobileSettings.value.releasePushEnabled, isFalse);
    expect(remote.releasePushStatus.value, contains('quyền thông báo'));
  });

  test('turning it off or unlinking takes the token back', () async {
    final remote = await phone();
    await remote.setReleasePushEnabled(true);
    await remote.setReleasePushEnabled(false);
    expect(relay.tokens, ['fcm-1', '']);
    expect(device.deleted, 1);
    expect(remote.mobileSettings.value.releasePushEnabled, isFalse);

    await remote.setReleasePushEnabled(true);
    await remote.clearMobileLink();
    expect(
      relay.tokens.last,
      '',
      reason: 'an unlinked phone must stop buzzing',
    );
  });

  test('the test buttons play the real channel locally', () async {
    final remote = await phone();
    await remote.testReleasePush(ReleasePushOutcome.failed);
    expect(device.tests, [ReleasePushOutcome.failed]);
  });

  tearDown(Get.reset);
}

class _Device extends ReleasePushDevice {
  _Device() : super(supported: true);

  bool granted = true;
  String currentToken = 'fcm-1';
  int permissionRequests = 0;
  int deleted = 0;
  final tests = <ReleasePushOutcome>[];

  @override
  Future<ReleasePushDeviceStatus> status() async =>
      ReleasePushDeviceStatus(available: true, canPost: granted);

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<String> token() async => currentToken;

  @override
  Future<void> deleteToken() async => deleted++;

  @override
  Future<bool> test(ReleasePushOutcome outcome) async {
    tests.add(outcome);
    return true;
  }
}

class _Relay extends ReleaseCenterConnect {
  final tokens = <String>[];
  final headers = <Map<String, String>>[];

  @override
  Future<Response<T>> post<T>(
    String? url,
    dynamic body, {
    String? contentType,
    Map<String, String>? headers,
    Map<String, dynamic>? query,
    Decoder<T>? decoder,
    Progress? uploadProgress,
  }) async {
    expect(url, 'https://relay.test/api/mobile/push-token');
    tokens.add((body as Map)['token'] as String);
    this.headers.add(headers ?? const {});
    return Response<T>(
      statusCode: 200,
      body: <String, Object?>{'releasePush': tokens.last.isNotEmpty} as T,
    );
  }
}
