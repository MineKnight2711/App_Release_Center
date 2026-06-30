import 'package:app_release_center/app/models/app_store_project.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('stores and loads managed CH Play projects', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await ProjectStoreService().init();

    const project = ChPlayProject(
      id: 'project-1',
      path: r'C:\apps\demo',
      displayName: 'Demo',
      applicationId: 'com.example.demo',
      hasSavedGooglePlayJson: true,
      hasSavedJksPath: true,
    );

    await service.saveChPlayProjects([project]);

    final loaded = service.chPlayProjects;
    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'project-1');
    expect(loaded.single.applicationId, 'com.example.demo');
    expect(loaded.single.hasSavedGooglePlayJson, isTrue);
    expect(loaded.single.hasSavedSigningCredentials, isTrue);
  });

  test('stores App Store projects separately from CH Play projects', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await ProjectStoreService().init();

    const chPlayProject = ChPlayProject(
      id: 'android-1',
      path: r'C:\apps\android-demo',
      displayName: 'Android Demo',
      applicationId: 'com.example.android',
    );
    const appStoreProject = AppStoreProject(
      id: 'ios-1',
      path: r'C:\apps\ios-demo',
      displayName: 'iOS Demo',
      bundleId: 'com.example.ios',
      hasSavedP8PrivateKey: true,
      hasSavedKeyId: true,
      hasSavedIssuerId: true,
    );

    await service.saveChPlayProjects([chPlayProject]);
    await service.saveAppStoreProjects([appStoreProject]);

    expect(service.chPlayProjects.single.applicationId, 'com.example.android');
    expect(service.appStoreProjects.single.bundleId, 'com.example.ios');
    expect(service.appStoreProjects.single.platform, 'ios');
    expect(service.appStoreProjects.single.hasSavedRequiredCredentials, isTrue);
  });
}
