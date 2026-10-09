import 'package:app_management_center/app/data/release_center_connect.dart';
import 'package:app_management_center/app/models/remote_control.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/mobile_control_credential_store_service.dart';
import 'package:app_management_center/app/services/notification_credential_store_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:app_management_center/app/services/remote_control_service.dart';
import 'package:app_management_center/app/services/script_catalog_service.dart';
import 'package:app_management_center/app/views/mobile_control_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A power button that quietly does nothing is indistinguishable from a broken
/// one. These tests exist because the outcome used to be written only to the
/// pairing screen, which a linked phone never shows again.
void main() {
  tearDown(Get.reset);

  Future<RemoteControlService> pumpLinkedConsole(WidgetTester tester) async {
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

    // Mounted unlinked on purpose: initState kicks off a refresh, and a
    // linked one would reach for the network and overwrite the very status
    // these tests are about.
    await tester.pumpWidget(const GetMaterialApp(home: MobileControlView()));

    remote.mobileSettings.value = const MobileControlSettings(
      endpointBaseUrl: 'https://relay.example.com/api',
      deviceControlToken: 'token',
      deviceId: 'device-1',
    );
    remote.desktopState.value = _desktopState();
    await tester.pump();
    return remote;
  }

  group('build stamp', () {
    // The first version of this line only rendered when the desktop reported a
    // build date — which a stale desktop never does, so the staleness warning
    // vanished in exactly the case it was written for.
    testWidgets('an online desktop that reports no build is called out', (
      tester,
    ) async {
      final remote = await pumpLinkedConsole(tester);
      remote.desktopState.value = _desktopState();
      await tester.pump();

      expect(find.textContaining('Không rõ bản build'), findsOneWidget);
    });

    testWidgets('an offline desktop is not nagged about its build', (
      tester,
    ) async {
      final remote = await pumpLinkedConsole(tester);
      remote.desktopState.value = _desktopState(online: false);
      await tester.pump();

      expect(find.textContaining('Không rõ bản build'), findsNothing);
    });

    testWidgets('a fresh build is shown plainly', (tester) async {
      final remote = await pumpLinkedConsole(tester);
      remote.desktopState.value = _desktopState(
        buildStamp: DateTime.now().subtract(const Duration(minutes: 20)),
      );
      await tester.pump();

      expect(find.textContaining('Bản build'), findsOneWidget);
      expect(find.textContaining('đang chạy bản build'), findsNothing);
    });

    testWidgets('a build from days ago says how old it is', (tester) async {
      final remote = await pumpLinkedConsole(tester);
      remote.desktopState.value = _desktopState(
        buildStamp: DateTime.now().subtract(const Duration(days: 3)),
      );
      await tester.pump();

      expect(find.textContaining('đã 3 ngày'), findsOneWidget);
    });
  });

  testWidgets('a relay refusal is shown, not swallowed', (tester) async {
    final remote = await pumpLinkedConsole(tester);

    remote.mobileStatus.value =
        'enqueue command lỗi: This device is not allowed to send power '
        'commands.';
    await tester.pump();

    expect(find.text('Không gửi được lệnh'), findsOneWidget);
    expect(
      find.textContaining('not allowed to send power commands'),
      findsOneWidget,
    );
  });

  testWidgets('an already-explained refusal renders in full', (tester) async {
    final remote = await pumpLinkedConsole(tester);

    remote.mobileStatus.value = explainRemoteControlError(
      'enqueue command lỗi: This device is not allowed to send power commands.',
    );
    await tester.pump();

    expect(find.text('Không gửi được lệnh'), findsOneWidget);
    expect(find.textContaining('ghép lại điện thoại'), findsOneWidget);
  });

  testWidgets('a desktop refusal is shown with its reason', (tester) async {
    final remote = await pumpLinkedConsole(tester);

    remote.activeMobileCommand.value = _powerCommand(
      status: 'failed',
      error: 'Đang chạy: Đang build Demo. Lệnh shutdown bị bỏ qua.',
    );
    await tester.pump();

    expect(find.text('Máy tính từ chối lệnh'), findsOneWidget);
    expect(find.textContaining('Đang build Demo'), findsOneWidget);
  });

  testWidgets('a queued command says it is still waiting', (tester) async {
    final remote = await pumpLinkedConsole(tester);

    remote.activeMobileCommand.value = _powerCommand(status: 'queued');
    await tester.pump();

    expect(find.textContaining('Đang chờ máy tính'), findsOneWidget);
  });

  testWidgets('a completed command is acknowledged', (tester) async {
    final remote = await pumpLinkedConsole(tester);

    remote.activeMobileCommand.value = _powerCommand(
      status: 'completed',
      logLines: const ['Lệnh nguồn từ điện thoại: lock.'],
    );
    await tester.pump();

    expect(find.text('Máy tính đã nhận lệnh'), findsOneWidget);
    expect(find.textContaining('lock'), findsOneWidget);
  });

  testWidgets('a release command does not report itself as power', (
    tester,
  ) async {
    final remote = await pumpLinkedConsole(tester);

    remote.activeMobileCommand.value = const RemoteCommand(
      commandId: 'c1',
      type: 'shell',
      status: 'failed',
      payload: {},
      logLines: [],
      error: 'something about a script',
    );
    await tester.pump();

    expect(find.text('Máy tính từ chối lệnh'), findsNothing);
  });

  testWidgets('sleep and hibernate are separate controls', (tester) async {
    await pumpLinkedConsole(tester);

    expect(find.text('Ngủ'), findsOneWidget);
    expect(find.text('Ngủ đông'), findsOneWidget);
  });
}

RemoteCommand _powerCommand({
  required String status,
  String? error,
  List<String> logLines = const [],
}) {
  return RemoteCommand(
    commandId: 'command-1',
    type: 'power',
    status: status,
    payload: const {'action': 'lock'},
    logLines: logLines,
    error: error,
  );
}

RemoteDesktopState _desktopState({bool online = true, DateTime? buildStamp}) {
  return RemoteDesktopState(
    online: online,
    buildStamp: buildStamp,
    desktopId: 'default',
    displayName: 'Windows PC',
    remoteControlEnabled: true,
    projects: [],
    isRunning: false,
    status: 'Idle',
    logLines: [],
    powerControlEnabled: true,
    sleepSupported: true,
    hibernateSupported: true,
  );
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
