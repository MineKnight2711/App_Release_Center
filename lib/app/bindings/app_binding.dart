import 'package:app_release_center/app/controllers/home_controller.dart';
import 'package:app_release_center/app/data/release_center_connect.dart';
import 'package:app_release_center/app/services/android_cicd_clone_service.dart';
import 'package:app_release_center/app/services/app_store_credential_store_service.dart';
import 'package:app_release_center/app/services/app_store_project_inspector_service.dart';
import 'package:app_release_center/app/services/app_store_version_check_service.dart';
import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_release_center/app/services/ch_play_project_inspector_service.dart';
import 'package:app_release_center/app/services/ch_play_version_check_service.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:app_release_center/app/services/script_catalog_service.dart';
import 'package:app_release_center/app/services/theme_service.dart';
import 'package:get/get.dart';

class AppBinding extends Bindings {
  static Future<void> initServices() async {
    await Get.putAsync<ProjectStoreService>(
      () => ProjectStoreService().init(),
      permanent: true,
    );
    await Get.putAsync<ThemeService>(
      () => ThemeService().init(),
      permanent: true,
    );
    Get.put<ScriptCatalogService>(ScriptCatalogService(), permanent: true);
    Get.put<AndroidCicdCloneService>(
      AndroidCicdCloneService(),
      permanent: true,
    );
    Get.put<ReleaseRunnerService>(ReleaseRunnerService(), permanent: true);
    Get.put<ChPlayProjectInspectorService>(
      ChPlayProjectInspectorService(),
      permanent: true,
    );
    Get.put<ChPlayCredentialStoreService>(
      ChPlayCredentialStoreService(),
      permanent: true,
    );
    Get.put<ChPlayVersionCheckService>(
      ChPlayVersionCheckService(
        inspector: Get.find<ChPlayProjectInspectorService>(),
        runner: Get.find<ReleaseRunnerService>(),
      ),
      permanent: true,
    );
    Get.put<AppStoreProjectInspectorService>(
      AppStoreProjectInspectorService(),
      permanent: true,
    );
    Get.put<AppStoreCredentialStoreService>(
      AppStoreCredentialStoreService(),
      permanent: true,
    );
    Get.put<AppStoreVersionCheckService>(
      AppStoreVersionCheckService(
        inspector: Get.find<AppStoreProjectInspectorService>(),
        runner: Get.find<ReleaseRunnerService>(),
      ),
      permanent: true,
    );
    Get.put<ReleaseCenterConnect>(ReleaseCenterConnect(), permanent: true);
  }

  @override
  void dependencies() {
    Get.lazyPut<HomeController>(
      () => HomeController(
        store: Get.find<ProjectStoreService>(),
        catalog: Get.find<ScriptCatalogService>(),
        androidCicdCloner: Get.find<AndroidCicdCloneService>(),
        runner: Get.find<ReleaseRunnerService>(),
        connect: Get.find<ReleaseCenterConnect>(),
        chPlayInspector: Get.find<ChPlayProjectInspectorService>(),
        chPlayCredentialStore: Get.find<ChPlayCredentialStoreService>(),
        chPlayVersionChecker: Get.find<ChPlayVersionCheckService>(),
        appStoreInspector: Get.find<AppStoreProjectInspectorService>(),
        appStoreCredentialStore: Get.find<AppStoreCredentialStoreService>(),
        appStoreVersionChecker: Get.find<AppStoreVersionCheckService>(),
      ),
    );
  }
}
