import 'package:app_release_center/app/controllers/home_controller.dart';
import 'package:app_release_center/app/data/release_center_connect.dart';
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
    Get.put<ReleaseRunnerService>(ReleaseRunnerService(), permanent: true);
    Get.put<ReleaseCenterConnect>(ReleaseCenterConnect(), permanent: true);
  }

  @override
  void dependencies() {
    Get.lazyPut<HomeController>(
      () => HomeController(
        store: Get.find<ProjectStoreService>(),
        catalog: Get.find<ScriptCatalogService>(),
        runner: Get.find<ReleaseRunnerService>(),
        connect: Get.find<ReleaseCenterConnect>(),
      ),
    );
  }
}
