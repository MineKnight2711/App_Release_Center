import 'dart:async';
import 'dart:io';

import 'package:app_management_center/app/config/backend_config.dart';
import 'package:app_management_center/app/controllers/app_shell_controller.dart';
import 'package:app_management_center/app/controllers/flowfin_controller.dart';
import 'package:app_management_center/app/controllers/home_controller.dart';
import 'package:app_management_center/app/data/amc_api_client.dart';
import 'package:app_management_center/app/data/release_center_connect.dart';
import 'package:app_management_center/app/modules/bundle_check/services/app_bundle_project_source.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_check_service.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_check_store.dart';
import 'package:app_management_center/app/modules/bundle_check/telegram/telegram_intake_service.dart';
import 'package:app_management_center/app/modules/bundle_check/telegram/telegram_intake_store.dart';
import 'package:app_management_center/app/modules/qa_desk/services/qa_desk_runtime.dart';
import 'package:app_management_center/app/services/android_cicd_clone_service.dart';
import 'package:app_management_center/app/services/android_keystore_generation_service.dart';
import 'package:app_management_center/app/services/api_monitor_service.dart';
import 'package:app_management_center/app/services/api_tool_repository_service.dart';
import 'package:app_management_center/app/services/api_tool_service.dart';
import 'package:app_management_center/app/services/app_store_credential_store_service.dart';
import 'package:app_management_center/app/services/app_store_project_inspector_service.dart';
import 'package:app_management_center/app/services/app_store_version_check_service.dart';
import 'package:app_management_center/app/services/app_lock_service.dart';
import 'package:app_management_center/app/services/remote_unlock_session_service.dart';
import 'package:app_management_center/app/services/auth_service.dart';
import 'package:app_management_center/app/services/auth_token_store_service.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/ch_play_project_inspector_service.dart';
import 'package:app_management_center/app/services/ch_play_version_check_service.dart';
import 'package:app_management_center/app/services/cicd_dependency_doctor_service.dart';
import 'package:app_management_center/app/services/cicd_dependency_installer_service.dart';
import 'package:app_management_center/app/services/command_notification_service.dart';
import 'package:app_management_center/app/services/flowfin_api_client.dart';
import 'package:app_management_center/app/services/flowfin_credential_store_service.dart';
import 'package:app_management_center/app/services/gemini_env_service.dart';
import 'package:app_management_center/app/services/git_inspector_service.dart';
import 'package:app_management_center/app/services/google_drive_credential_store_service.dart';
import 'package:app_management_center/app/services/google_drive_release_upload_service.dart';
import 'package:app_management_center/app/services/machine_power_service.dart';
import 'package:app_management_center/app/services/mobile_control_credential_store_service.dart';
import 'package:app_management_center/app/services/notification_credential_store_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:app_management_center/app/services/release_apk_artifact_service.dart';
import 'package:app_management_center/app/services/release_installer_artifact_service.dart';
import 'package:app_management_center/app/services/release_note_generation_service.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:app_management_center/app/services/release_workflow_service.dart';
import 'package:app_management_center/app/services/resource_catalog_crypto_service.dart';
import 'package:app_management_center/app/services/resource_catalog_excel_service.dart';
import 'package:app_management_center/app/services/resource_catalog_password_store_service.dart';
import 'package:app_management_center/app/services/resource_credential_resolver.dart';
import 'package:app_management_center/app/services/resource_discovery_service.dart';
import 'package:app_management_center/app/services/resource_export_service.dart';
import 'package:app_management_center/app/services/remote_control_service.dart';
import 'package:app_management_center/app/services/script_catalog_service.dart';
import 'package:app_management_center/app/services/theme_service.dart';
import 'package:app_management_center/app/services/telegram_credential_store_service.dart';
import 'package:app_management_center/app/services/telegram_release_notification_service.dart';
import 'package:app_management_center/app/services/qa_desk_host_service.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

class AppBinding extends Bindings {
  static Future<void> initServices({BackendConfig? backendConfig}) async {
    await Get.putAsync<ProjectStoreService>(
      () => ProjectStoreService().init(),
      permanent: true,
    );
    await Get.putAsync<ThemeService>(
      () => ThemeService().init(),
      permanent: true,
    );
    final tokenStore = Get.put<AuthTokenStoreService>(
      AuthTokenStoreService(),
      permanent: true,
    );
    final api = backendConfig == null
        ? null
        : Get.put<AmcApiClient>(
            AmcApiClient(
              baseUrl: backendConfig.apiBaseUrl,
              readToken: tokenStore.readToken,
            ),
            permanent: true,
          );
    final auth = await Get.putAsync<AuthService>(
      () => AuthService(
        sessionStore: Get.find<ProjectStoreService>(),
        backend: api == null
            ? null
            : AmcAuthBackend(api: api, tokenStore: tokenStore),
        teamDataSource: api == null ? null : AmcTeamDataSource(api),
      ).init(backendConfigured: api != null),
      permanent: true,
    );
    api?.onUnauthorized = () => unawaited(auth.handleSessionRejected());
    Get.put<ScriptCatalogService>(ScriptCatalogService(), permanent: true);
    Get.put<ApiToolService>(ApiToolService(), permanent: true);
    Get.put<ApiMonitorService>(ApiMonitorService(), permanent: true);
    await Get.putAsync<ApiToolRepositoryService>(
      () => ApiToolRepositoryService(
        localStore: Get.find<ProjectStoreService>(),
        auth: auth,
        teamDataSource: api == null ? null : AmcTeamApiToolDataSource(api),
      ).init(),
      permanent: true,
    );
    // FlowFin talks to its own Worker; it deliberately does not go through
    // this app's amc-api Worker or its notification relay.
    Get.put<FlowFinCredentialStoreService>(
      FlowFinCredentialStoreService(),
      permanent: true,
    );
    Get.put<FlowFinApiClient>(
      FlowFinApiClient(
        credentialStore: Get.find<FlowFinCredentialStoreService>(),
      )..settings = Get.find<ProjectStoreService>().flowFinSettings,
      permanent: true,
    );
    Get.put<AndroidCicdCloneService>(
      AndroidCicdCloneService(),
      permanent: true,
    );
    Get.put<AndroidKeystoreGenerationService>(
      AndroidKeystoreGenerationService(),
      permanent: true,
    );
    Get.put<GitInspectorService>(GitInspectorService(), permanent: true);
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
    Get.put<CiCdDependencyDoctorService>(
      CiCdDependencyDoctorService(),
      permanent: true,
    );
    Get.put<CiCdDependencyInstallerService>(
      const CiCdDependencyInstallerService(),
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
    Get.put<ReleaseInstallerArtifactService>(
      ReleaseInstallerArtifactService(
        buildExecutor: RunnerReleaseInstallerBuildExecutor(
          Get.find<ReleaseRunnerService>(),
        ),
      ),
      permanent: true,
    );
    Get.put<ResourceDiscoveryService>(
      ResourceDiscoveryService(),
      permanent: true,
    );
    Get.put<ResourceExportService>(ResourceExportService(), permanent: true);
    Get.put<ResourceCatalogPasswordStoreService>(
      ResourceCatalogPasswordStoreService(),
      permanent: true,
    );
    Get.put<ResourceCatalogCryptoService>(
      ResourceCatalogCryptoService(env: Get.find<GeminiEnvService>()),
      permanent: true,
    );
    Get.put<ResourceCatalogExcelService>(
      ResourceCatalogExcelService(
        crypto: Get.find<ResourceCatalogCryptoService>(),
        passwordStore: Get.find<ResourceCatalogPasswordStoreService>(),
      ),
      permanent: true,
    );
    Get.put<MachinePowerService>(MachinePowerService(), permanent: true);
    Get.put<MobileControlCredentialStoreService>(
      MobileControlCredentialStoreService(),
      permanent: true,
    );
    // Async because the control token now comes from secure storage, and the
    // phone decides between the pairing form and the console from it.
    await Get.putAsync<RemoteControlService>(
      () => RemoteControlService(
        store: Get.find<ProjectStoreService>(),
        catalog: Get.find<ScriptCatalogService>(),
        runner: Get.find<ReleaseRunnerService>(),
        connect: Get.find<ReleaseCenterConnect>(),
        credentialStore: Get.find<NotificationCredentialStoreService>(),
        mobileCredentialStore: Get.find<MobileControlCredentialStoreService>(),
        power: Get.find<MachinePowerService>(),
      ).init(),
      permanent: true,
    );
    // Phone only. The desktop sits behind the Windows sign-in and the team
    // sign-in gate already, so a second biometric prompt there would guard nothing
    // that is not guarded; the phone has no gate of its own at all.
    if (Platform.isAndroid || Platform.isIOS) {
      await Get.putAsync<AppLockService>(
        () => AppLockService(
          store: Get.find<ProjectStoreService>(),
          authenticator: LocalAuthBiometricAuthenticator(),
        ).init(),
        permanent: true,
      );
      await Get.putAsync<RemoteUnlockSessionService>(
        () => RemoteUnlockSessionService(
          store: Get.find<ProjectStoreService>(),
          lock: Get.find<AppLockService>(),
        ).init(),
        permanent: true,
      );
    }
    Get.put<ChPlayProjectInspectorService>(
      ChPlayProjectInspectorService(),
      permanent: true,
    );
    Get.put<ChPlayCredentialStoreService>(
      ChPlayCredentialStoreService(),
      permanent: true,
    );
    Get.put<ResourceCredentialResolver>(
      ResourceCredentialResolver(
        store: Get.find<ChPlayCredentialStoreService>(),
      ),
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
    if (!Platform.isAndroid && !Platform.isIOS) {
      await _registerAabBot();
    }
  }

  /// The Telegram AAB bot lives for the whole app, not the checker page: it
  /// answers the group whether or not that page is open.
  static Future<void> _registerAabBot() async {
    final bundleStore = await BundleCheckStore.forApp();
    final root = await bundleStore.root;
    final telegram = Get.find<TelegramReleaseNotificationService>();
    final credentials = Get.find<TelegramCredentialStoreService>();
    final intake = TelegramIntakeService(
      store: TelegramIntakeStore(
        root: Directory(p.join(root.path, 'telegram')),
      ),
      checker: BundleCheckService(
        store: bundleStore,
        projects: AppBundleProjectSource(),
      ),
      readToken: telegram.readBotToken,
      releaseSettings: () => telegram.settings,
      saveReleaseSettings: telegram.saveSettings,
      readServerCredentials: credentials.readLocalServerCredentials,
    );
    Get.put<TelegramIntakeService>(intake, permanent: true);
    // Not awaited: starting a local server can take seconds, and nothing at
    // startup waits on the bot.
    unawaited(intake.init());
  }

  @override
  void dependencies() {
    Get.put<AppShellController>(
      AppShellController(store: Get.find<ProjectStoreService>()),
      permanent: true,
    );
    Get.lazyPut<FlowFinController>(
      () => FlowFinController(
        client: Get.find<FlowFinApiClient>(),
        store: Get.find<ProjectStoreService>(),
      ),
      fenix: true,
    );
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
        releaseInstallerArtifacts: Get.find<ReleaseInstallerArtifactService>(),
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
        resourceDiscovery: Get.find<ResourceDiscoveryService>(),
        resourceExports: Get.find<ResourceExportService>(),
        resourceCredentials: Get.find<ResourceCredentialResolver>(),
        resourceCatalogPasswords:
            Get.find<ResourceCatalogPasswordStoreService>(),
        resourceCatalogExcel: Get.find<ResourceCatalogExcelService>(),
        cicdDoctor: Get.find<CiCdDependencyDoctorService>(),
        cicdInstaller: Get.find<CiCdDependencyInstallerService>(),
        machineShutdown: Get.find<MachinePowerService>(),
      ),
    );
    QaDeskRuntime.host = AmcQaDeskHost(
      runner: Get.find<ReleaseRunnerService>(),
      home: () => Get.find<HomeController>(),
      api: Get.isRegistered<AmcApiClient>() ? Get.find<AmcApiClient>() : null,
    );
  }
}
