import 'package:app_management_center/app/controllers/home_controller.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/ch_play_project_inspector_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import 'android_toolchain.dart';
import 'bundle_check_service.dart';

/// Projects the rest of AMC already knows: CH Play entries first (they carry
/// the store version and saved keystore), then recent project folders.
class AppBundleProjectSource implements BundleProjectSource {
  AppBundleProjectSource({ChPlayProjectInspectorService? inspector})
    : _inspector = inspector ?? ChPlayProjectInspectorService();

  final ChPlayProjectInspectorService _inspector;

  @override
  Future<List<BundleProjectCandidate>> candidates() async {
    final result = <BundleProjectCandidate>[];
    final seen = <String>{};

    final home = Get.isRegistered<HomeController>()
        ? Get.find<HomeController>()
        : null;
    final store = Get.isRegistered<ProjectStoreService>()
        ? Get.find<ProjectStoreService>()
        : null;

    final chPlay =
        home?.chPlayProjects.toList() ?? store?.chPlayProjects ?? const [];
    for (final project in chPlay) {
      final key = p.normalize(project.path).toLowerCase();
      if (!seen.add(key)) continue;
      result.add(
        BundleProjectCandidate(
          name: project.name,
          path: project.path,
          applicationId: project.applicationId.trim().isEmpty
              ? await _inspector.detectApplicationId(project.path)
              : project.applicationId.trim(),
          chPlayProjectId: project.id,
          storeVersionCode: home?.chPlaySnapshots[project.id]?.storeVersionCode,
        ),
      );
    }

    final recent = [?store?.lastProjectPath, ...?store?.recentProjectPaths];
    for (final path in recent) {
      final key = p.normalize(path).toLowerCase();
      if (!seen.add(key)) continue;
      final applicationId = await _inspector.detectApplicationId(path);
      if (applicationId == null) continue;
      result.add(
        BundleProjectCandidate(
          name: p.basename(path),
          path: path,
          applicationId: applicationId,
        ),
      );
    }
    return result;
  }

  @override
  Future<KeystoreRef?> savedKeystore(BundleProjectCandidate candidate) async {
    final id = candidate.chPlayProjectId;
    if (id == null || !Get.isRegistered<ChPlayCredentialStoreService>()) {
      return null;
    }
    final credentials = await Get.find<ChPlayCredentialStoreService>().read(id);
    if (!credentials.hasJksPath ||
        !credentials.hasKeyAlias ||
        !credentials.hasStorePassword) {
      return null;
    }
    return KeystoreRef(
      path: credentials.jksPath!.trim(),
      alias: credentials.keyAlias!.trim(),
      storePassword: credentials.storePassword!,
      keyPassword: credentials.hasKeyPassword
          ? credentials.keyPassword!
          : credentials.storePassword!,
      source: 'keystore đã lưu cho CH Play',
    );
  }
}
