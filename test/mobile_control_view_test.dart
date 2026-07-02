import 'package:app_release_center/app/data/release_center_connect.dart';
import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_release_center/app/services/notification_credential_store_service.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:app_release_center/app/services/remote_control_service.dart';
import 'package:app_release_center/app/services/script_catalog_service.dart';
import 'package:app_release_center/app/views/mobile_control_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() {
    Get.reset();
  });

  testWidgets('mobile control shows pairing form before link', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await ProjectStoreService().init();
    final catalog = ScriptCatalogService();
    final runner = ReleaseRunnerService();
    final connect = ReleaseCenterConnect();
    final credentials = NotificationCredentialStoreService(
      secureStore: _MemorySecureKeyValueStore(),
    );

    Get.put<ProjectStoreService>(store);
    Get.put<ScriptCatalogService>(catalog);
    Get.put<ReleaseRunnerService>(runner);
    Get.put<ReleaseCenterConnect>(connect);
    Get.put<NotificationCredentialStoreService>(credentials);
    Get.put<RemoteControlService>(
      RemoteControlService(
        store: store,
        catalog: catalog,
        runner: runner,
        connect: connect,
        credentialStore: credentials,
      ),
    );

    await tester.pumpWidget(const GetMaterialApp(home: MobileControlView()));

    expect(find.text('Pair Phone'), findsOneWidget);
    expect(find.text('Relay endpoint'), findsOneWidget);
    expect(find.text('Pairing code'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget);
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
