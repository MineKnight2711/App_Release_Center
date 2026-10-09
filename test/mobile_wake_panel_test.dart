import 'package:app_management_center/app/data/release_center_connect.dart';
import 'package:app_management_center/app/models/remote_control.dart';
import 'package:app_management_center/app/models/wake_diagnostics.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/mobile_control_credential_store_service.dart';
import 'package:app_management_center/app/services/notification_credential_store_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:app_management_center/app/services/remote_control_service.dart';
import 'package:app_management_center/app/services/script_catalog_service.dart';
import 'package:app_management_center/app/views/mobile_control_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The wake panel used to hide its button whenever the machine was online,
/// which put the only useful diagnostic out of reach: sending while the machine
/// is on is the one way to learn whether the packet can reach it, because
/// nothing inside a sleeping machine can be observed.
void main() {
  tearDown(Get.reset);

  Future<RemoteControlService> pumpConsole(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await ProjectStoreService().init();
    final remote = RemoteControlService(
      store: store,
      catalog: ScriptCatalogService(),
      runner: ReleaseRunnerService(),
      connect: ReleaseCenterConnect(),
      credentialStore: NotificationCredentialStoreService(
        secureStore: _MemorySecureKeyValueStore(),
      ),
      mobileCredentialStore: MobileControlCredentialStoreService(
        secureStore: _MemorySecureKeyValueStore(),
      ),
    );
    Get.put<RemoteControlService>(remote);

    // Mounted unlinked so initState's refresh does not reach the network.
    await tester.pumpWidget(const GetMaterialApp(home: MobileControlView()));
    remote.mobileSettings.value = const MobileControlSettings(
      endpointBaseUrl: 'https://relay.example.com/api',
      deviceControlToken: 'token',
      deviceId: 'device-1',
    );
    return remote;
  }

  Future<void> showState(
    WidgetTester tester,
    RemoteControlService remote, {
    required bool online,
    WakeDiagnostics wake = const WakeDiagnostics(
      adapterName: 'Wi-Fi',
      macAddress: '84:9E:56:EA:B7:F1',
      broadcastAddress: '192.168.1.255',
    ),
  }) async {
    remote.desktopState.value = RemoteDesktopState(
      desktopId: 'default',
      displayName: 'Windows PC',
      online: online,
      remoteControlEnabled: true,
      projects: const [],
      isRunning: false,
      status: 'Idle',
      logLines: const [],
      powerControlEnabled: true,
      wake: wake,
    );
    await tester.pump();
    // The panel sits below the fold on a test-sized viewport. The section
    // title is the one anchor present in every state this test drives.
    await tester.scrollUntilVisible(
      find.text('Đánh thức / bật máy'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets('offers a reachability test while the machine is on', (
    tester,
  ) async {
    final remote = await pumpConsole(tester);
    await showState(tester, remote, online: true);

    expect(find.text('Gửi thử gói đánh thức'), findsOneWidget);
    expect(find.text('Đánh thức'), findsNothing);
  });

  testWidgets('offers the real wake while the machine is off', (tester) async {
    final remote = await pumpConsole(tester);
    await showState(tester, remote, online: false);

    expect(find.text('Đánh thức'), findsOneWidget);
    expect(find.text('Gửi thử gói đánh thức'), findsNothing);
  });

  testWidgets('says nothing has been observed before any attempt', (
    tester,
  ) async {
    final remote = await pumpConsole(tester);
    // Listening but nothing heard yet is a different state from not listening,
    // which the stale-build case below covers.
    await showState(
      tester,
      remote,
      online: true,
      wake: const WakeDiagnostics(
        adapterName: 'Wi-Fi',
        macAddress: '84:9E:56:EA:B7:F1',
        broadcastAddress: '192.168.1.255',
        probeListening: true,
      ),
    );

    expect(find.textContaining('Chưa ghi nhận gói'), findsOneWidget);
    // Windows Firewall blocks the probe without a rule, so silence here does
    // not prove the packet failed to arrive. Claiming it did sent the last
    // round of debugging after the wrong thing.
    expect(find.textContaining('Firewall'), findsOneWidget);
  });

  testWidgets('confirms the path once a packet has arrived', (tester) async {
    final remote = await pumpConsole(tester);
    await showState(
      tester,
      remote,
      online: true,
      wake: WakeDiagnostics(
        adapterName: 'Wi-Fi',
        macAddress: '84:9E:56:EA:B7:F1',
        broadcastAddress: '192.168.1.255',
        probeListening: true,
        lastPacketAt: DateTime.now(),
        lastPacketFrom: '192.168.1.50',
      ),
    );

    expect(find.textContaining('Gói đánh thức tới được máy'), findsOneWidget);
    expect(find.textContaining('192.168.1.50'), findsOneWidget);
  });

  testWidgets('a packet from the machine itself is not counted as proof', (
    tester,
  ) async {
    final remote = await pumpConsole(tester);
    // Loopback traffic never passes the firewall, so it says nothing about
    // whether the phone can reach this machine. Reading one as success is
    // what made a blocked path look like a slow one.
    await showState(
      tester,
      remote,
      online: true,
      wake: WakeDiagnostics(
        adapterName: 'Wi-Fi',
        macAddress: '84:9E:56:EA:B7:F1',
        ipAddress: '192.168.1.225',
        broadcastAddress: '192.168.1.255',
        probeListening: true,
        lastPacketAt: DateTime.now(),
        lastPacketFrom: '192.168.1.225',
      ),
    );

    expect(find.textContaining('đến từ chính máy tính'), findsOneWidget);
    expect(find.textContaining('Gói đánh thức tới được máy'), findsNothing);
  });

  testWidgets('a packet from the phone is counted as proof', (tester) async {
    final remote = await pumpConsole(tester);
    await showState(
      tester,
      remote,
      online: true,
      wake: WakeDiagnostics(
        adapterName: 'Wi-Fi',
        macAddress: '84:9E:56:EA:B7:F1',
        ipAddress: '192.168.1.225',
        broadcastAddress: '192.168.1.255',
        probeListening: true,
        lastPacketAt: DateTime.now(),
        lastPacketFrom: '192.168.1.5',
      ),
    );

    expect(find.textContaining('Gói đánh thức tới được máy'), findsOneWidget);
  });

  testWidgets('blames a stale build when the listener is not running', (
    tester,
  ) async {
    final remote = await pumpConsole(tester);
    await showState(tester, remote, online: true);

    expect(find.textContaining('bản build cũ'), findsOneWidget);
  });

  testWidgets('a machine with no known MAC cannot be asked', (tester) async {
    final remote = await pumpConsole(tester);
    await showState(
      tester,
      remote,
      online: false,
      wake: const WakeDiagnostics(adapterName: 'Wi-Fi'),
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Đánh thức'),
    );
    expect(button.onPressed, isNull);
  });
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
