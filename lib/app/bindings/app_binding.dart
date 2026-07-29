import 'package:app_release_center/app/controllers/home_controller.dart';
import 'package:app_release_center/app/data/release_center_connect.dart';
import 'package:app_release_center/app/services/android_cicd_clone_service.dart';
import 'package:app_release_center/app/services/android_keystore_generation_service.dart';
import 'package:app_release_center/app/services/app_store_credential_store_service.dart';
import 'package:app_release_center/app/services/app_store_project_inspector_service.dart';
import 'package:app_release_center/app/services/app_store_version_check_service.dart';
import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_release_center/app/services/ch_play_project_inspector_service.dart';
import 'package:app_release_center/app/services/ch_play_version_check_service.dart';
import 'package:app_release_center/app/services/command_notification_service.dart';
import 'package:app_release_center/app/services/gemini_env_service.dart';
import 'package:app_release_center/app/services/google_drive_credential_store_service.dart';
import 'package:app_release_center/app/services/google_drive_release_upload_service.dart';
import 'package:app_release_center/app/services/notification_credential_store_service.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:app_release_center/app/services/release_apk_artifact_service.dart';
import 'package:app_release_center/app/services/release_note_generation_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:app_release_center/app/services/release_workflow_service.dart';
import 'package:app_release_center/app/services/remote_control_service.dart';
import 'package:app_release_center/app/services/script_catalog_service.dart';
import 'package:app_release_center/app/services/theme_service.dart';
import 'package:app_release_center/app/services/telegram_credential_store_service.dart';
import 'package:app_release_center/app/services/telegram_release_notification_service.dart';
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
    Get.put<AndroidKeystoreGenerationService>(
      AndroidKeystoreGenerationService(),
      permanent: true,
    );
    Get.put<ReleaseCenterConnect>(ReleaseCenterConnect(), permanent: true);
    Get.put<GeminiEnvService>(GeminiEnvService(), permanent: true);
    Get.put<ReleaseNoteGenerationService>(
      ReleaseNoteGenerationService(),
      permanent: true,
    );
    Get.put<TelegramCredentialStoreService>(
      TelegramCredentialStoreService(),
      permanent: true,
    );
    Get.put<TelegramReleaseNotificationService>(
      TelegramReleaseNotificationService(
        store: Get.find<ProjectStoreService>(),
        credentialStore: Get.find<TelegramCredentialStoreService>(),
        httpClient: DartTelegramHttpClient(),
      ),
      permanent: true,
    );
    Get.put<GoogleDriveCredentialStoreService>(
      GoogleDriveCredentialStoreService(),
      permanent: true,
    );
    Get.put<GoogleDriveReleaseUploadService>(
      GoogleDriveReleaseUploadService(
        store: Get.find<ProjectStoreService>(),
        credentialStore: Get.find<GoogleDriveCredentialStoreService>(),
      ),
      permanent: true,
    );
    Get.put<NotificationCredentialStoreService>(
      NotificationCredentialStoreService(),
      permanent: true,
    );
    Get.put<CommandNotificationService>(
      CommandNotificationService(
        store: Get.find<ProjectStoreService>(),
        credentialStore: Get.find<NotificationCredentialStoreService>(),
        httpClient: ReleaseCenterNotificationHttpClient(
          Get.find<ReleaseCenterConnect>(),
        ),
      ),
      permanent: true,
    );
    Get.put<ReleaseRunnerService>(
      ReleaseRunnerService(
        notificationService: Get.find<CommandNotificationService>(),
      ),
      permanent: true,
    );
    Get.put<ReleaseApkArtifactService>(
      ReleaseApkArtifactService(
        buildExecutor: RunnerReleaseApkBuildExecutor(
          Get.find<ReleaseRunnerService>(),
        ),
      ),
      permanent: true,
    );
    Get.put<RemoteControlService>(
      RemoteControlService(
        store: Get.find<ProjectStoreService>(),
        catalog: Get.find<ScriptCatalogService>(),
        runner: Get.find<ReleaseRunnerService>(),
        connect: Get.find<ReleaseCenterConnect>(),
        credentialStore: Get.find<NotificationCredentialStoreService>(),
      ),
      permanent: true,
    );
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
    Get.put<ReleaseWorkflowService>(
      ReleaseWorkflowService(
        runner: Get.find<ReleaseRunnerService>(),
        catalog: Get.find<ScriptCatalogService>(),
        chPlayInspector: Get.find<ChPlayProjectInspectorService>(),
        chPlayVersionChecker: Get.find<ChPlayVersionCheckService>(),
        releaseNotesGenerator: Get.find<ReleaseNoteGenerationService>(),
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
  }

  @override
  void dependencies() {
    Get.lazyPut<HomeController>(
      () => HomeController(
        store: Get.find<ProjectStoreService>(),
        catalog: Get.find<ScriptCatalogService>(),
        androidCicdCloner: Get.find<AndroidCicdCloneService>(),
        androidKeystores: Get.find<AndroidKeystoreGenerationService>(),
        runner: Get.find<ReleaseRunnerService>(),
        connect: Get.find<ReleaseCenterConnect>(),
        notifications: Get.find<CommandNotificationService>(),
        geminiEnv: Get.find<GeminiEnvService>(),
        releaseNotesGenerator: Get.find<ReleaseNoteGenerationService>(),
        releaseApkArtifacts: Get.find<ReleaseApkArtifactService>(),
        telegramReleaseNotifications:
            Get.find<TelegramReleaseNotificationService>(),
        googleDriveReleaseUploads: Get.find<GoogleDriveReleaseUploadService>(),
        chPlayInspector: Get.find<ChPlayProjectInspectorService>(),
        chPlayCredentialStore: Get.find<ChPlayCredentialStoreService>(),
        chPlayVersionChecker: Get.find<ChPlayVersionCheckService>(),
        releaseWorkflow: Get.find<ReleaseWorkflowService>(),
        appStoreInspector: Get.find<AppStoreProjectInspectorService>(),
        appStoreCredentialStore: Get.find<AppStoreCredentialStoreService>(),
        appStoreVersionChecker: Get.find<AppStoreVersionCheckService>(),
      ),
    );
  }
}
