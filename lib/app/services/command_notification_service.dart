import 'dart:convert';

import 'package:app_release_center/app/data/release_center_connect.dart';
import 'package:app_release_center/app/models/release_notification.dart';
import 'package:app_release_center/app/services/notification_credential_store_service.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:get/get.dart';

abstract class CommandNotificationSender {
  Future<void> sendCommandEvent(CommandNotificationEvent event);
}

abstract class NotificationHttpClient {
  Future<NotificationHttpResponse> getJson(
    String url, {
    Map<String, String> headers = const {},
  });

  Future<NotificationHttpResponse> postJson(
    String url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
  });

  Future<NotificationHttpResponse> deleteJson(
    String url, {
    Map<String, String> headers = const {},
  });
}

class NotificationHttpResponse {
  const NotificationHttpResponse({required this.statusCode, this.body});

  final int statusCode;
  final Object? body;

  bool get isOk => statusCode >= 200 && statusCode < 300;
}

class ReleaseCenterNotificationHttpClient implements NotificationHttpClient {
  ReleaseCenterNotificationHttpClient(this.connect);

  final ReleaseCenterConnect connect;

  @override
  Future<NotificationHttpResponse> getJson(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final response = await connect.get(url, headers: headers);
    return NotificationHttpResponse(
      statusCode: response.statusCode ?? 0,
      body: response.body,
    );
  }

  @override
  Future<NotificationHttpResponse> postJson(
    String url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
  }) async {
    final response = await connect.post(url, body, headers: headers);
    return NotificationHttpResponse(
      statusCode: response.statusCode ?? 0,
      body: response.body,
    );
  }

  @override
  Future<NotificationHttpResponse> deleteJson(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final response = await connect.delete(url, headers: headers);
    return NotificationHttpResponse(
      statusCode: response.statusCode ?? 0,
      body: response.body,
    );
  }
}

class CommandNotificationService extends GetxService
    implements CommandNotificationSender {
  CommandNotificationService({
    required ProjectStoreService store,
    required NotificationCredentialStoreService credentialStore,
    required NotificationHttpClient httpClient,
  }) : _store = store,
       _credentialStore = credentialStore,
       _httpClient = httpClient;

  final ProjectStoreService _store;
  final NotificationCredentialStoreService _credentialStore;
  final NotificationHttpClient _httpClient;

  ReleaseNotificationSettings get settings => _store.notificationSettings;

  List<LinkedNotificationDevice> get linkedDevices =>
      _store.linkedNotificationDevices;

  Future<void> saveSettings(ReleaseNotificationSettings settings) {
    return _store.saveNotificationSettings(settings);
  }

  Future<String?> readApiToken() {
    return _credentialStore.readApiToken();
  }

  Future<void> saveApiToken(String? token) {
    return _credentialStore.saveApiToken(token);
  }

  Future<NotificationPairingSession> createPairingSession() async {
    final currentSettings = _requireConfiguredSettings();
    final response = await _httpClient.postJson(
      _endpoint(currentSettings, 'pairings'),
      {'source': 'desktop', 'app': 'app_release_center'},
      headers: await _headers(),
    );
    _ensureOk(response, 'create pairing');
    return NotificationPairingSession.fromJson(_bodyMap(response.body));
  }

  Future<NotificationPairingPollResult> pollPairing(String pairingId) async {
    final currentSettings = _requireConfiguredSettings();
    final response = await _httpClient.getJson(
      _endpoint(currentSettings, 'pairings/$pairingId'),
      headers: await _headers(),
    );
    _ensureOk(response, 'poll pairing');
    return NotificationPairingPollResult.fromJson(_bodyMap(response.body));
  }

  Future<List<LinkedNotificationDevice>> fetchDevices() async {
    final currentSettings = _requireConfiguredSettings();
    final response = await _httpClient.getJson(
      _endpoint(currentSettings, 'devices'),
      headers: await _headers(),
    );
    _ensureOk(response, 'load devices');
    final devices = _bodyList(response.body, key: 'devices')
        .whereType<Map<String, Object?>>()
        .map(LinkedNotificationDevice.fromJson)
        .toList();
    await _store.saveLinkedNotificationDevices(devices);
    await _pruneSelectedDevices(devices);
    return devices;
  }

  Future<void> saveLinkedDevice(LinkedNotificationDevice device) async {
    final devices = [
      ..._store.linkedNotificationDevices.where(
        (existing) => existing.id != device.id,
      ),
      device,
    ]..sort((a, b) => a.label.compareTo(b.label));
    await _store.saveLinkedNotificationDevices(devices);

    final selected = <String>{
      ..._store.notificationSettings.selectedDeviceIds,
      device.id,
    }.toList();
    await _store.saveNotificationSettings(
      _store.notificationSettings.copyWith(selectedDeviceIds: selected),
    );
  }

  Future<void> unlinkDevice(String deviceId) async {
    final currentSettings = _requireConfiguredSettings();
    final response = await _httpClient.deleteJson(
      _endpoint(currentSettings, 'devices/$deviceId'),
      headers: await _headers(),
    );
    _ensureOk(response, 'unlink device');
    await removeLocalDevice(deviceId);
  }

  Future<void> removeLocalDevice(String deviceId) async {
    final devices = _store.linkedNotificationDevices
        .where((device) => device.id != deviceId)
        .toList();
    await _store.saveLinkedNotificationDevices(devices);
    final selected = _store.notificationSettings.selectedDeviceIds
        .where((id) => id != deviceId)
        .toList();
    await _store.saveNotificationSettings(
      _store.notificationSettings.copyWith(selectedDeviceIds: selected),
    );
  }

  Future<void> sendTestNotification() async {
    final currentSettings = _requireReadySettings();
    final response = await _httpClient.postJson(
      _endpoint(currentSettings, 'test-notifications'),
      {'targetDeviceIds': currentSettings.selectedDeviceIds},
      headers: await _headers(),
    );
    _ensureOk(response, 'send test notification');
  }

  @override
  Future<void> sendCommandEvent(CommandNotificationEvent event) async {
    final currentSettings = settings;
    if (!currentSettings.enabled ||
        !currentSettings.hasEndpoint ||
        !currentSettings.hasSelectedDevices) {
      return;
    }

    final response = await _httpClient.postJson(
      _endpoint(currentSettings, 'command-events'),
      event
          .copyWith(targetDeviceIds: currentSettings.selectedDeviceIds)
          .toJson(),
      headers: await _headers(),
    );
    _ensureOk(response, 'send command notification');
  }

  ReleaseNotificationSettings _requireConfiguredSettings() {
    final currentSettings = settings;
    if (!currentSettings.hasEndpoint) {
      throw const NotificationConfigurationException(
        'Notification endpoint is required.',
      );
    }
    return currentSettings;
  }

  ReleaseNotificationSettings _requireReadySettings() {
    final currentSettings = _requireConfiguredSettings();
    if (!currentSettings.hasSelectedDevices) {
      throw const NotificationConfigurationException(
        'Select at least one linked phone.',
      );
    }
    return currentSettings;
  }

  Future<void> _pruneSelectedDevices(
    List<LinkedNotificationDevice> devices,
  ) async {
    final ids = devices.map((device) => device.id).toSet();
    final selected = settings.selectedDeviceIds
        .where((id) => ids.contains(id))
        .toList();
    if (selected.length == settings.selectedDeviceIds.length) return;
    await _store.saveNotificationSettings(
      settings.copyWith(selectedDeviceIds: selected),
    );
  }

  Future<Map<String, String>> _headers() async {
    final token = (await _credentialStore.readApiToken())?.trim();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  String _endpoint(ReleaseNotificationSettings settings, String path) {
    final base = settings.endpointBaseUrl.trim().replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    return '$base/${path.replaceFirst(RegExp(r'^/+'), '')}';
  }

  Map<String, Object?> _bodyMap(Object? body) {
    final decoded = _decodeBody(body);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
    throw const NotificationProtocolException('Expected a JSON object.');
  }

  List<Object?> _bodyList(Object? body, {required String key}) {
    final decoded = _decodeBody(body);
    if (decoded is List) return decoded;
    if (decoded is Map && decoded[key] is List) {
      return List<Object?>.from(decoded[key] as List);
    }
    throw const NotificationProtocolException('Expected a JSON list.');
  }

  Object? _decodeBody(Object? body) {
    if (body is String) return jsonDecode(body);
    return body;
  }

  void _ensureOk(NotificationHttpResponse response, String action) {
    if (response.isOk) return;
    throw NotificationRequestException(
      action,
      response.statusCode,
      _errorMessage(response.body),
    );
  }

  String? _errorMessage(Object? body) {
    final decoded = _decodeBody(body);
    if (decoded is Map && decoded['error'] != null) {
      return decoded['error'].toString();
    }
    if (decoded is String && decoded.trim().isNotEmpty) {
      return decoded.trim();
    }
    return null;
  }
}

class NotificationConfigurationException implements Exception {
  const NotificationConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NotificationProtocolException implements Exception {
  const NotificationProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NotificationRequestException implements Exception {
  const NotificationRequestException(
    this.action,
    this.statusCode, [
    this.message,
  ]);

  final String action;
  final int statusCode;
  final String? message;

  @override
  String toString() {
    final detail = message?.trim();
    if (detail != null && detail.isNotEmpty) {
      return 'Failed to $action (HTTP $statusCode): $detail';
    }
    return 'Failed to $action (HTTP $statusCode).';
  }
}
