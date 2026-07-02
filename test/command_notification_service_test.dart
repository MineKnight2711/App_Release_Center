import 'package:app_release_center/app/models/release_notification.dart';
import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_release_center/app/services/command_notification_service.dart';
import 'package:app_release_center/app/services/notification_credential_store_service.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('creates and polls pairing sessions', () async {
    final harness = await _ServiceHarness.create();
    harness.client.postResponses.add(
      const NotificationHttpResponse(
        statusCode: 201,
        body: {
          'pairingId': 'pair-1',
          'pairingCode': 'ABC123',
          'pairingUrl': 'https://example.com/?pairing=pair-1',
          'expiresAt': '2026-07-01T00:10:00Z',
        },
      ),
    );
    harness.client.getResponses.add(
      const NotificationHttpResponse(
        statusCode: 200,
        body: {
          'status': 'linked',
          'device': {
            'id': 'phone-1',
            'displayName': 'Pixel',
            'platform': 'Android',
            'browser': 'Chrome',
            'linkedAt': '2026-07-01T00:01:00Z',
          },
        },
      ),
    );

    final session = await harness.service.createPairingSession();
    final poll = await harness.service.pollPairing(session.pairingId);

    expect(session.pairingCode, 'ABC123');
    expect(harness.client.posts.single.url, 'https://example.com/api/pairings');
    expect(poll.status, NotificationPairingStatus.linked);
    expect(poll.device?.id, 'phone-1');
  });

  test('sends command event to selected devices with auth header', () async {
    final harness = await _ServiceHarness.create();
    await harness.credentials.saveApiToken('secret-token');
    harness.client.postResponses.add(
      const NotificationHttpResponse(statusCode: 200, body: {'sent': 1}),
    );

    await harness.service.sendCommandEvent(
      CommandNotificationEvent(
        runId: 'run-1',
        event: CommandNotificationEventType.completed,
        command: 'fastlane android deploy',
        statusLabel: 'deploy',
        activePath: 'fastlane:android:deploy',
        startedAt: DateTime.utc(2026, 7, 1),
        targetDeviceIds: const [],
      ),
    );

    final request = harness.client.posts.single;
    expect(request.url, 'https://example.com/api/command-events');
    expect(request.headers['Authorization'], 'Bearer secret-token');
    expect(request.body['targetDeviceIds'], ['phone-1']);
    expect(request.body['event'], 'completed');
  });

  test('saves linked devices and selects them by default', () async {
    final harness = await _ServiceHarness.create();
    await harness.service.saveLinkedDevice(
      LinkedNotificationDevice(
        id: 'phone-2',
        displayName: 'iPhone',
        platform: 'iOS',
        browser: 'Safari',
        linkedAt: DateTime.utc(2026, 7, 1),
      ),
    );

    expect(harness.store.linkedNotificationDevices.map((device) => device.id), [
      'phone-2',
    ]);
    expect(
      harness.store.notificationSettings.selectedDeviceIds,
      contains('phone-2'),
    );
  });
}

class _ServiceHarness {
  const _ServiceHarness({
    required this.store,
    required this.credentials,
    required this.client,
    required this.service,
  });

  final ProjectStoreService store;
  final NotificationCredentialStoreService credentials;
  final _FakeNotificationHttpClient client;
  final CommandNotificationService service;

  static Future<_ServiceHarness> create() async {
    SharedPreferences.setMockInitialValues({});
    final store = await ProjectStoreService().init();
    await store.saveNotificationSettings(
      const ReleaseNotificationSettings(
        enabled: true,
        endpointBaseUrl: 'https://example.com/api/',
        selectedDeviceIds: ['phone-1'],
      ),
    );
    final credentials = NotificationCredentialStoreService(
      secureStore: _MemorySecureKeyValueStore(),
    );
    final client = _FakeNotificationHttpClient();
    final service = CommandNotificationService(
      store: store,
      credentialStore: credentials,
      httpClient: client,
    );

    return _ServiceHarness(
      store: store,
      credentials: credentials,
      client: client,
      service: service,
    );
  }
}

class _Request {
  const _Request(this.url, this.body, this.headers);

  final String url;
  final Map<String, Object?> body;
  final Map<String, String> headers;
}

class _FakeNotificationHttpClient implements NotificationHttpClient {
  final posts = <_Request>[];
  final gets = <String>[];
  final deletes = <String>[];
  final postResponses = <NotificationHttpResponse>[];
  final getResponses = <NotificationHttpResponse>[];
  final deleteResponses = <NotificationHttpResponse>[];

  @override
  Future<NotificationHttpResponse> getJson(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    gets.add(url);
    return getResponses.removeAt(0);
  }

  @override
  Future<NotificationHttpResponse> postJson(
    String url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
  }) async {
    posts.add(_Request(url, body, headers));
    return postResponses.removeAt(0);
  }

  @override
  Future<NotificationHttpResponse> deleteJson(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    deletes.add(url);
    return deleteResponses.removeAt(0);
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
