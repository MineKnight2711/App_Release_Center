import 'dart:io';

import 'package:app_release_center/app/data/release_center_connect.dart';
import 'package:app_release_center/app/models/app_store_credentials.dart';
import 'package:app_release_center/app/models/app_store_project.dart';
import 'package:app_release_center/app/models/app_store_version_snapshot.dart';
import 'package:app_release_center/app/models/ch_play_credentials.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/models/ch_play_version_snapshot.dart';
import 'package:app_release_center/app/models/google_drive_release_settings.dart';
import 'package:app_release_center/app/models/release_fastlane_lane.dart';
import 'package:app_release_center/app/models/release_notification.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/models/release_script.dart';
import 'package:app_release_center/app/models/telegram_release_settings.dart';
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
import 'package:app_release_center/app/services/google_drive_release_upload_service.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:app_release_center/app/services/release_apk_artifact_service.dart';
import 'package:app_release_center/app/services/release_note_generation_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:app_release_center/app/services/script_catalog_service.dart';
import 'package:app_release_center/app/services/telegram_release_notification_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

enum PlayUploadChoice { ask, upload, skip }

class HomeController extends GetxController {
  HomeController({
    required this.store,
    required this.catalog,
    required this.androidCicdCloner,
    required this.androidKeystores,
    required this.runner,
    required this.connect,
    required this.notifications,
    required this.geminiEnv,
    required this.releaseNotesGenerator,
    required this.releaseApkArtifacts,
    required this.telegramReleaseNotifications,
    required this.googleDriveReleaseUploads,
    required this.chPlayInspector,
    required this.chPlayCredentialStore,
    required this.chPlayVersionChecker,
    required this.appStoreInspector,
    required this.appStoreCredentialStore,
    required this.appStoreVersionChecker,
  });

  final ProjectStoreService store;
  final ScriptCatalogService catalog;
  final AndroidCicdCloneService androidCicdCloner;
  final AndroidKeystoreGenerationService androidKeystores;
  final ReleaseRunnerService runner;
  final ReleaseCenterConnect connect;
  final CommandNotificationService notifications;
  final GeminiEnvService geminiEnv;
  final ReleaseNoteGenerationService releaseNotesGenerator;
  final ReleaseApkArtifactService releaseApkArtifacts;
  final TelegramReleaseNotificationService telegramReleaseNotifications;
  final GoogleDriveReleaseUploadService googleDriveReleaseUploads;
  final ChPlayProjectInspectorService chPlayInspector;
  final ChPlayCredentialStoreService chPlayCredentialStore;
  final ChPlayVersionCheckService chPlayVersionChecker;
  final AppStoreProjectInspectorService appStoreInspector;
  final AppStoreCredentialStoreService appStoreCredentialStore;
  final AppStoreVersionCheckService appStoreVersionChecker;

  final project = Rxn<ReleaseProject>();
  final recentPaths = <String>[].obs;
  final chPlayProjects = <ChPlayProject>[].obs;
  final chPlaySnapshots = <String, ChPlayVersionSnapshot>{}.obs;
  final appStoreProjects = <AppStoreProject>[].obs;
  final appStoreSnapshots = <String, AppStoreVersionSnapshot>{}.obs;
  final isRefreshingChPlay = false.obs;
  final isRefreshingAppStore = false.obs;
  final isLoadingProject = false.obs;
  final projectError = ''.obs;
  final isGeneratingAndroidKeystore = false.obs;
  final includeFirebaseDeploy = true.obs;
  final playUploadChoice = PlayUploadChoice.ask.obs;
  final uploadPlayListingImages = false.obs;
  final validatePlayImages = true.obs;
  final notificationSettings = const ReleaseNotificationSettings().obs;
  final linkedNotificationDevices = <LinkedNotificationDevice>[].obs;
  final isLoadingNotificationDevices = false.obs;
  final notificationStatus = ''.obs;
  final isGeneratingReleaseNotes = false.obs;
  final hasGeminiApiKey = false.obs;
  final releaseNoteAiStatus = ''.obs;
  final telegramReleaseSettings = const TelegramReleaseSettings().obs;
  final isSendingTelegram = false.obs;
  final hasTelegramBotToken = false.obs;
  final hasTelegramChatId = false.obs;
  final hasReleaseNoteText = false.obs;
  final hasTelegramReleaseContext = false.obs;
  final telegramReleaseStatus = ''.obs;
  final googleDriveReleaseSettings = const GoogleDriveReleaseSettings().obs;
  final isConnectingGoogleDrive = false.obs;
  final isTestingGoogleDrive = false.obs;
  final isUploadingGoogleDriveApk = false.obs;
  final hasGoogleDriveOAuthClientId = false.obs;
  final hasGoogleDriveOAuthClientSecret = false.obs;
  final hasGoogleDriveCredentials = false.obs;
  final googleDriveReleaseStatus = ''.obs;

  final releaseNotesController = TextEditingController();
  final geminiApiKeyController = TextEditingController();
  final releaseNotePromptController = TextEditingController(
    text: defaultReleaseNotePrompt,
  );
  final telegramBotTokenController = TextEditingController();
  final telegramChatIdController = TextEditingController();
  final googleDriveOAuthClientIdController = TextEditingController();
  final googleDriveOAuthClientSecretController = TextEditingController();
  final customArgsController = TextEditingController();
  final stdinController = TextEditingController();
  final notificationEndpointController = TextEditingController();
  final notificationTokenController = TextEditingController();
  final _sessionChPlayCredentials = <String, ChPlayCredentials>{};
  final _sessionAppStoreCredentials = <String, AppStoreCredentials>{};
  _GeneratedReleaseContext? _generatedReleaseContext;

  bool get _isGoogleDriveBusy =>
      isConnectingGoogleDrive.value ||
      isTestingGoogleDrive.value ||
      isUploadingGoogleDriveApk.value ||
      isSendingTelegram.value ||
      isGeneratingReleaseNotes.value ||
      runner.isBusy;

  @override
  void onInit() {
    super.onInit();
    geminiApiKeyController.addListener(_syncGeminiKeyState);
    telegramBotTokenController.addListener(_syncTelegramFormState);
    telegramChatIdController.addListener(_syncTelegramFormState);
    googleDriveOAuthClientIdController.addListener(_syncGoogleDriveFormState);
    googleDriveOAuthClientSecretController.addListener(
      _syncGoogleDriveFormState,
    );
    releaseNotesController.addListener(_syncReleaseNoteState);
    recentPaths.assignAll(_initialProjectPaths());
    _loadGeminiApiKey();
    _loadTelegramReleaseState();
    _loadGoogleDriveReleaseState();
    _loadNotificationState();
    _loadManagedStoreProjects();
    final savedPath = store.lastProjectPath;
    if (savedPath != null && Directory(savedPath).existsSync()) {
      loadProject(savedPath);
    }
  }

  @override
  void onClose() {
    geminiApiKeyController.removeListener(_syncGeminiKeyState);
    telegramBotTokenController.removeListener(_syncTelegramFormState);
    telegramChatIdController.removeListener(_syncTelegramFormState);
    googleDriveOAuthClientIdController.removeListener(
      _syncGoogleDriveFormState,
    );
    googleDriveOAuthClientSecretController.removeListener(
      _syncGoogleDriveFormState,
    );
    releaseNotesController.removeListener(_syncReleaseNoteState);
    releaseNotesController.dispose();
    geminiApiKeyController.dispose();
    releaseNotePromptController.dispose();
    telegramBotTokenController.dispose();
    telegramChatIdController.dispose();
    googleDriveOAuthClientIdController.dispose();
    googleDriveOAuthClientSecretController.dispose();
    customArgsController.dispose();
    stdinController.dispose();
    notificationEndpointController.dispose();
    notificationTokenController.dispose();
    super.onClose();
  }

  Future<void> pickProjectDirectory() async {
    final selectedPath = await _pickDirectoryPath(
      dialogTitle: 'Select project directory',
      initialDirectory: _initialDirectory(),
    );

    if (selectedPath == null) return;
    await loadProject(selectedPath);
  }

  Future<ChPlayProject?> pickChPlayProjectDraft() async {
    final selectedPath = await _pickDirectoryPath(
      dialogTitle: 'Select CH Play project directory',
      initialDirectory: _initialDirectory(),
    );

    if (selectedPath == null) return null;

    final normalizedPath = p.normalize(selectedPath);
    final existingProject = _chPlayProjectByPath(normalizedPath);
    final inspection = await chPlayInspector.inspect(normalizedPath);

    return ChPlayProject(
      id: existingProject?.id ?? _newChPlayProjectId(),
      path: inspection.path,
      displayName: existingProject?.displayName ?? inspection.displayName,
      applicationId:
          existingProject?.applicationId ?? inspection.applicationId ?? '',
      track: existingProject?.track ?? 'production',
      hasSavedGooglePlayJson: existingProject?.hasSavedGooglePlayJson ?? false,
      hasSavedJksPath: existingProject?.hasSavedJksPath ?? false,
      hasSavedKeyAlias: existingProject?.hasSavedKeyAlias ?? false,
      hasSavedStorePassword: existingProject?.hasSavedStorePassword ?? false,
      hasSavedKeyPassword: existingProject?.hasSavedKeyPassword ?? false,
    );
  }

  Future<void> saveChPlayProject(ChPlayProject project) async {
    final normalizedProject = project.copyWith(
      path: p.normalize(project.path),
      displayName: project.displayName.trim(),
      applicationId: project.applicationId.trim(),
      track: project.track.trim().isEmpty ? 'production' : project.track.trim(),
    );

    final projects =
        chPlayProjects
            .where(
              (existing) =>
                  existing.id != normalizedProject.id &&
                  existing.path.toLowerCase() !=
                      normalizedProject.path.toLowerCase(),
            )
            .toList()
          ..add(normalizedProject);
    projects.sort((a, b) => a.name.compareTo(b.name));

    await store.saveChPlayProjects(projects);
    chPlayProjects.assignAll(projects);
    await _loadChPlayLocalSnapshot(normalizedProject);
  }

  Future<void> deleteChPlayProject(ChPlayProject project) async {
    final projects = chPlayProjects
        .where((existing) => existing.id != project.id)
        .toList();
    await store.saveChPlayProjects(projects);
    await chPlayCredentialStore.delete(project.id);
    _sessionChPlayCredentials.remove(project.id);
    chPlayProjects.assignAll(projects);
    chPlaySnapshots.remove(project.id);
    chPlaySnapshots.refresh();
  }

  Future<AppStoreProject?> pickAppStoreProjectDraft() async {
    final selectedPath = await _pickDirectoryPath(
      dialogTitle: 'Select App Store project directory',
      initialDirectory: _initialDirectory(),
    );

    if (selectedPath == null) return null;

    final normalizedPath = p.normalize(selectedPath);
    final existingProject = _appStoreProjectByPath(normalizedPath);
    final inspection = await appStoreInspector.inspect(normalizedPath);

    return AppStoreProject(
      id: existingProject?.id ?? _newAppStoreProjectId(),
      path: inspection.path,
      displayName: existingProject?.displayName ?? inspection.displayName,
      bundleId: existingProject?.bundleId ?? inspection.bundleId ?? '',
      hasSavedP8PrivateKey: existingProject?.hasSavedP8PrivateKey ?? false,
      hasSavedKeyId: existingProject?.hasSavedKeyId ?? false,
      hasSavedIssuerId: existingProject?.hasSavedIssuerId ?? false,
      hasSavedTeamId: existingProject?.hasSavedTeamId ?? false,
      inHouse: existingProject?.inHouse ?? false,
    );
  }

  Future<void> saveAppStoreProject(AppStoreProject project) async {
    final normalizedProject = project.copyWith(
      path: p.normalize(project.path),
      displayName: project.displayName.trim(),
      bundleId: project.bundleId.trim(),
      platform: 'ios',
    );

    final projects =
        appStoreProjects
            .where(
              (existing) =>
                  existing.id != normalizedProject.id &&
                  existing.path.toLowerCase() !=
                      normalizedProject.path.toLowerCase(),
            )
            .toList()
          ..add(normalizedProject);
    projects.sort((a, b) => a.name.compareTo(b.name));

    await store.saveAppStoreProjects(projects);
    appStoreProjects.assignAll(projects);
    await _loadAppStoreLocalSnapshot(normalizedProject);
  }

  Future<void> deleteAppStoreProject(AppStoreProject project) async {
    final projects = appStoreProjects
        .where((existing) => existing.id != project.id)
        .toList();
    await store.saveAppStoreProjects(projects);
    await appStoreCredentialStore.delete(project.id);
    _sessionAppStoreCredentials.remove(project.id);
    appStoreProjects.assignAll(projects);
    appStoreSnapshots.remove(project.id);
    appStoreSnapshots.refresh();
  }

  Future<String?> pickGooglePlayJsonContent() async {
    final path = await _pickFilePath(
      dialogTitle: 'Select Google Play service-account JSON',
      extensions: const ['json'],
    );
    if (path == null) return null;

    return File(path).readAsString();
  }

  Future<String?> pickAppStoreP8Content() async {
    final path = await _pickFilePath(
      dialogTitle: 'Select App Store Connect .p8 key',
      extensions: const ['p8'],
    );
    if (path == null) return null;

    return File(path).readAsString();
  }

  Future<String?> pickJksPath() async {
    return _pickFilePath(
      dialogTitle: 'Select Android keystore',
      extensions: const ['jks', 'keystore'],
    );
  }

  Future<ChPlayCredentials> readChPlayCredentials(String projectId) async {
    return _sessionChPlayCredentials[projectId] ??
        await chPlayCredentialStore.read(projectId);
  }

  Future<void> saveChPlayCredentials({
    required ChPlayProject project,
    required ChPlayCredentials credentials,
    required bool saveSecurely,
  }) async {
    ChPlayProject updatedProject;
    if (saveSecurely) {
      await chPlayCredentialStore.save(project.id, credentials);
      _sessionChPlayCredentials.remove(project.id);
      final metadata = await chPlayCredentialStore.metadata(project.id);
      updatedProject = project.withCredentialMetadata(metadata);
    } else {
      await chPlayCredentialStore.delete(project.id);
      _sessionChPlayCredentials[project.id] = credentials;
      updatedProject = project.withCredentialMetadata(
        const ChPlayCredentialMetadata(),
      );
    }

    await saveChPlayProject(updatedProject);
  }

  Future<AppStoreCredentials> readAppStoreCredentials(String projectId) async {
    return _sessionAppStoreCredentials[projectId] ??
        await appStoreCredentialStore.read(projectId);
  }

  Future<void> saveAppStoreCredentials({
    required AppStoreProject project,
    required AppStoreCredentials credentials,
    required bool saveSecurely,
  }) async {
    AppStoreProject updatedProject;
    if (saveSecurely) {
      await appStoreCredentialStore.save(project.id, credentials);
      _sessionAppStoreCredentials.remove(project.id);
      final metadata = await appStoreCredentialStore.metadata(project.id);
      updatedProject = project.withCredentialMetadata(metadata);
    } else {
      await appStoreCredentialStore.delete(project.id);
      _sessionAppStoreCredentials[project.id] = credentials;
      updatedProject = project.withCredentialMetadata(
        AppStoreCredentialMetadata(inHouse: credentials.inHouse),
      );
    }

    await saveAppStoreProject(updatedProject);
  }

  Future<void> refreshAllChPlayProjects() async {
    if (runner.isBusy) {
      runner.appendSystemLog('Wait for the active command before refreshing.');
      return;
    }

    isRefreshingChPlay.value = true;
    try {
      for (final project in chPlayProjects.toList()) {
        await _refreshChPlayProject(project);
      }
    } finally {
      isRefreshingChPlay.value = false;
    }
  }

  Future<void> refreshAllStoreProjects() async {
    if (runner.isBusy) {
      runner.appendSystemLog('Wait for the active command before refreshing.');
      return;
    }

    isRefreshingChPlay.value = chPlayProjects.isNotEmpty;
    isRefreshingAppStore.value = appStoreProjects.isNotEmpty;
    try {
      for (final project in chPlayProjects.toList()) {
        await _refreshChPlayProject(project);
      }
      for (final project in appStoreProjects.toList()) {
        await _refreshAppStoreProject(project);
      }
    } finally {
      isRefreshingChPlay.value = false;
      isRefreshingAppStore.value = false;
    }
  }

  Future<void> refreshChPlayProject(ChPlayProject project) async {
    if (runner.isBusy) {
      runner.appendSystemLog('Wait for the active command before refreshing.');
      return;
    }

    await _refreshChPlayProject(project);
  }

  Future<void> refreshAppStoreProject(AppStoreProject project) async {
    if (runner.isBusy) {
      runner.appendSystemLog('Wait for the active command before refreshing.');
      return;
    }

    await _refreshAppStoreProject(project);
  }

  Future<void> loadProject(String path) async {
    isLoadingProject.value = true;
    projectError.value = '';

    try {
      final loadedProject = await catalog.inspect(path);
      if (_generatedReleaseContext != null &&
          !p.equals(
            _generatedReleaseContext!.projectPath,
            loadedProject.path,
          )) {
        _clearGeneratedReleaseContext();
      }
      project.value = loadedProject;
      includeFirebaseDeploy.value = loadedProject.hasFirebaseDeployTools;
      playUploadChoice.value = loadedProject.hasPlayReleaseTools
          ? PlayUploadChoice.ask
          : PlayUploadChoice.skip;
      uploadPlayListingImages.value = false;
      validatePlayImages.value = loadedProject.imageValidator != null;
      await store.saveProjectPath(loadedProject.path);
      recentPaths.assignAll(_initialProjectPaths());
    } on FileSystemException catch (error) {
      _clearGeneratedReleaseContext();
      project.value = null;
      projectError.value = error.message;
    } catch (error) {
      _clearGeneratedReleaseContext();
      project.value = null;
      projectError.value = error.toString();
    } finally {
      isLoadingProject.value = false;
    }
  }

  Future<void> removeRecentProject(String path) async {
    await store.removeRecentProjectPath(path);
    recentPaths.assignAll(_initialProjectPaths());
    runner.appendSystemLog('Removed ${p.basename(path)} from recent projects.');
  }

  Future<void> runScript(ReleaseScript script) async {
    final currentProject = project.value;
    if (currentProject == null || runner.isBusy) return;

    final environment = {
      'FASTLANE_SKIP_SCREEN': '1',
      'TTY_SCREEN_WIDTH': '120',
      'TTY_SCREEN_HEIGHT': '40',
    };

    if (script.kind == ReleaseScriptKind.deploy) {
      await _runDeploy(currentProject, script, environment);
      return;
    }

    await runner.run(
      project: currentProject,
      script: script,
      args: _customArgs(),
      environment: environment,
      clearLog: true,
    );

    await _refreshProjectSnapshot(currentProject.path);
  }

  Future<void> runFastlaneLane(ReleaseFastlaneLane lane) async {
    final currentProject = project.value;
    if (currentProject == null || runner.isBusy) return;

    await runner.runFastlaneLane(
      project: currentProject,
      lane: lane,
      args: _customArgs(),
      environment: const {
        'FASTLANE_SKIP_SCREEN': '1',
        'TTY_SCREEN_WIDTH': '120',
        'TTY_SCREEN_HEIGHT': '40',
      },
      clearLog: true,
    );

    await _refreshProjectSnapshot(currentProject.path);
  }

  Future<void> pullBranchFromRemote({
    required String remote,
    required String branch,
  }) async {
    final currentProject = project.value;
    if (currentProject == null) {
      runner.appendSystemLog('Select a project before pulling from remote.');
      return;
    }
    if (runner.isBusy) return;

    final remoteName = remote.trim();
    final branchName = branch.trim();
    if (remoteName.isEmpty || branchName.isEmpty) {
      runner.appendSystemLog('Remote and branch are required for pull.');
      return;
    }

    await runner.runCommand(
      workingDirectory: currentProject.path,
      statusLabel: 'git pull $remoteName/$branchName',
      activePath: 'extended:git-pull',
      executable: 'git',
      arguments: ['pull', remoteName, branchName],
      clearLog: true,
    );

    await _refreshProjectSnapshot(currentProject.path);
  }

  Future<void> checkFastlaneVersionAndUpdate() async {
    final currentProject = project.value;
    if (currentProject == null) {
      runner.appendSystemLog('Select a project before updating Fastlane.');
      return;
    }
    if (runner.isBusy) return;

    final workingDirectory = currentProject.androidDirectory.existsSync()
        ? currentProject.androidDirectory.path
        : currentProject.path;

    runner.beginWorkflow(totalSteps: 2, label: 'Update Fastlane');
    var succeeded = false;
    try {
      final versionExitCode = await runner.runCommand(
        workingDirectory: workingDirectory,
        statusLabel: 'fastlane --version',
        activePath: 'extended:fastlane-version',
        executable: runner.resolveFastlaneExecutable(),
        arguments: const ['--version'],
        clearLog: true,
        allowDuringWorkflow: true,
      );
      if (versionExitCode != 0) return;

      final updateArguments = _fastlaneGemUpdateArguments();
      final updateExitCode = await runner.runCommand(
        workingDirectory: workingDirectory,
        statusLabel: 'gem update fastlane --user-install',
        activePath: 'extended:fastlane-update',
        executable: runner.resolveGemExecutable(),
        arguments: updateArguments,
        clearLog: false,
        allowDuringWorkflow: true,
      );
      succeeded = updateExitCode == 0;
    } finally {
      runner.finishWorkflow(success: succeeded);
      await _refreshProjectSnapshot(currentProject.path);
    }
  }

  Future<void> runFlutterClean() async {
    await _runFlutterCommand(
      statusLabel: 'flutter clean',
      activePath: 'extended:flutter-clean',
      arguments: const ['clean'],
    );
  }

  Future<void> runFlutterPubGet() async {
    await _runFlutterCommand(
      statusLabel: 'flutter pub get',
      activePath: 'extended:flutter-pub-get',
      arguments: const ['pub', 'get'],
    );
  }

  Future<AndroidCicdClonePreview?> previewAndroidCicdClone({
    AndroidCicdCloneMode mode = AndroidCicdCloneMode.adaptive,
  }) async {
    final currentProject = project.value;
    if (currentProject == null) {
      runner.appendSystemLog('Select a project before cloning Android CI/CD.');
      return null;
    }
    if (runner.isBusy) return null;

    try {
      return await androidCicdCloner.preview(currentProject.path, mode: mode);
    } on FileSystemException catch (error) {
      runner.appendSystemLog(error.message);
      return null;
    } catch (error) {
      runner.appendSystemLog('Failed to prepare Android CI/CD clone: $error');
      return null;
    }
  }

  Future<void> applyAndroidCicdClone(AndroidCicdClonePreview preview) async {
    if (runner.isBusy) return;

    try {
      runner.clearLog();
      runner.appendSystemLog(
        'Cloning Android CI/CD into ${preview.projectPath}',
      );
      final result = await androidCicdCloner.apply(preview);

      runner.appendSystemLog(
        'Android CI/CD clone completed: ${result.writtenFiles.length} written, '
        '${result.skippedFiles.length} skipped.',
      );
      for (final file in result.writtenFiles) {
        runner.appendSystemLog('Wrote $file');
      }
      for (final file in result.skippedFiles) {
        runner.appendSystemLog('Skipped $file');
      }
      for (final warning in preview.warnings) {
        runner.appendSystemLog('Warning: $warning');
      }

      await _refreshProjectSnapshot(preview.projectPath);
    } on FileSystemException catch (error) {
      runner.appendSystemLog(error.message);
    } catch (error) {
      runner.appendSystemLog('Failed to clone Android CI/CD: $error');
    }
  }

  Future<AndroidKeystoreGenerationResult?> generateAndroidKeystore({
    String? projectPath,
    String keyAlias = defaultAndroidKeyAlias,
    bool forceRecreate = false,
  }) async {
    if (runner.isBusy || isGeneratingAndroidKeystore.value) return null;

    final targetPath = projectPath ?? project.value?.path;
    if (targetPath == null || targetPath.trim().isEmpty) {
      runner.appendSystemLog('Select a project before generating Android JKS.');
      return null;
    }

    isGeneratingAndroidKeystore.value = true;
    runner.status.value = 'Generating Android JKS';
    runner.clearLog();
    runner.appendSystemLog(
      'Generating Android upload keystore for ${p.basename(targetPath)}...',
    );

    try {
      final result = await androidKeystores.generate(
        projectPath: targetPath,
        keyAlias: keyAlias,
        forceRecreate: forceRecreate,
      );
      runner.appendSystemLog('Android upload keystore created.');
      runner.appendSystemLog('Keystore: ${result.keystorePath}');
      runner.appendSystemLog('Updated android/env.properties.');
      runner.appendSystemLog('Updated android/key.properties.');
      runner.status.value = 'Completed';

      final currentProject = project.value;
      if (currentProject != null && p.equals(currentProject.path, targetPath)) {
        await _refreshProjectSnapshot(targetPath);
      }
      return result;
    } on FileSystemException catch (error) {
      runner.appendSystemLog(error.message);
      runner.status.value = 'Failed';
      return null;
    } catch (error) {
      runner.appendSystemLog('Failed to generate Android JKS: $error');
      runner.status.value = 'Failed';
      return null;
    } finally {
      isGeneratingAndroidKeystore.value = false;
    }
  }

  Future<void> validateImages() async {
    final currentProject = project.value;
    final validator = currentProject?.imageValidator;
    if (currentProject == null || validator == null || runner.isBusy) {
      return;
    }

    await runner.run(
      project: currentProject,
      script: validator,
      clearLog: true,
    );
  }

  void sendInput() {
    if (runner.yesNoPrompt.value != null) return;

    final value = stdinController.text;

    runner.sendInput(value);
    stdinController.clear();
  }

  void sendYesNoInput(bool yes) {
    if (!runner.isRunning.value || runner.yesNoPrompt.value == null) return;

    runner.sendInput(yes ? 'y' : 'n');
  }

  void clearLog() {
    runner.clearLog();
  }

  Future<void> saveGeminiApiKey() async {
    final apiKey = geminiApiKeyController.text.trim();
    if (apiKey.isEmpty) {
      releaseNoteAiStatus.value = 'Gemini API key is required.';
      return;
    }

    try {
      await geminiEnv.saveApiKey(apiKey);
      releaseNoteAiStatus.value = 'Gemini API key saved to .env.';
    } catch (error) {
      releaseNoteAiStatus.value = 'Failed to save Gemini API key: $error';
      runner.appendSystemLog('Failed to save Gemini API key: $error');
    }
  }

  Future<void> generateReleaseNotes() async {
    final currentProject = project.value;
    if (currentProject == null) {
      releaseNoteAiStatus.value = 'Select a project before generating notes.';
      return;
    }
    if (runner.isBusy ||
        isGeneratingReleaseNotes.value ||
        isSendingTelegram.value) {
      return;
    }

    final apiKey = geminiApiKeyController.text.trim();
    if (apiKey.isEmpty) {
      releaseNoteAiStatus.value = 'Gemini API key is required.';
      return;
    }

    isGeneratingReleaseNotes.value = true;
    _clearGeneratedReleaseContext();
    releaseNoteAiStatus.value = 'Generating release notes from git history...';

    try {
      await geminiEnv.saveApiKey(apiKey);
      final result = await releaseNotesGenerator.generate(
        project: currentProject,
        apiKey: apiKey,
        customPrompt: releaseNotePromptController.text,
      );
      releaseNotesController.text = result.notes;
      _generatedReleaseContext = _GeneratedReleaseContext(
        projectPath: currentProject.path,
        appDisplayName: result.appDisplayName,
        version: result.version,
      );
      hasTelegramReleaseContext.value = true;

      final noteLength = result.notes.runes.length;
      final fallbackLabel = result.usedFallbackRange
          ? ' using fallback range'
          : '';
      releaseNoteAiStatus.value = noteLength > _playReleaseNoteCharacterLimit
          ? 'Generated $noteLength characters$fallbackLabel. Review before upload.'
          : 'Generated from ${result.gitRangeLabel} (${result.commitCount} commits).';
      runner.appendSystemLog(
        'Generated release notes from ${result.gitRangeLabel} '
        '(${result.commitCount} commits).',
      );
      if (noteLength > _playReleaseNoteCharacterLimit) {
        runner.appendSystemLog(
          'Release notes are $noteLength characters; Google Play allows '
          '$_playReleaseNoteCharacterLimit characters per language.',
        );
      }
      if (result.version == null) {
        runner.appendSystemLog(
          'Project version is unavailable; Telegram will use "không xác định".',
        );
      }
      if (telegramReleaseSettings.value.autoSendEnabled) {
        await _sendTelegramRelease(
          context: _generatedReleaseContext!,
          releaseNotes: result.notes,
          automatic: true,
        );
      }
    } catch (error) {
      releaseNoteAiStatus.value = 'Release note generation failed: $error';
      runner.appendSystemLog('Release note generation failed: $error');
    } finally {
      isGeneratingReleaseNotes.value = false;
    }
  }

  Future<void> saveTelegramConfiguration() async {
    final saved = await _persistTelegramConfiguration(requireComplete: false);
    if (saved) {
      telegramReleaseStatus.value = 'Telegram settings saved.';
    }
  }

  Future<void> setTelegramAutoSendEnabled(bool enabled) async {
    final saved = await _persistTelegramConfiguration(
      requireComplete: enabled,
      autoSendEnabled: enabled,
    );
    if (saved) {
      telegramReleaseStatus.value = enabled
          ? 'Telegram auto send enabled.'
          : 'Telegram auto send disabled.';
    }
  }

  Future<void> testTelegramConfiguration() async {
    if (isSendingTelegram.value || isGeneratingReleaseNotes.value) return;
    isSendingTelegram.value = true;
    telegramReleaseStatus.value = 'Sending Telegram test message...';
    try {
      final saved = await _persistTelegramConfiguration(requireComplete: true);
      if (!saved) return;
      await telegramReleaseNotifications.sendTestMessage();
      telegramReleaseStatus.value = 'Telegram test message sent.';
      runner.appendSystemLog('Telegram test message sent.');
    } catch (error) {
      telegramReleaseStatus.value = 'Telegram test failed: $error';
      runner.appendSystemLog('Telegram test failed: $error');
    } finally {
      isSendingTelegram.value = false;
    }
  }

  Future<void> sendCurrentReleaseNoteToTelegram() async {
    if (isSendingTelegram.value || isGeneratingReleaseNotes.value) return;
    final context = _generatedReleaseContext;
    final currentProject = project.value;
    if (context == null ||
        currentProject == null ||
        !p.equals(context.projectPath, currentProject.path)) {
      telegramReleaseStatus.value =
          'Generate release notes for the selected project before sending.';
      return;
    }

    final notes = releaseNotesController.text.trim();
    if (notes.isEmpty) {
      telegramReleaseStatus.value = 'Release notes are required.';
      return;
    }

    await _sendTelegramRelease(
      context: context,
      releaseNotes: notes,
      automatic: false,
    );
  }

  Future<bool> _sendTelegramRelease({
    required _GeneratedReleaseContext context,
    required String releaseNotes,
    required bool automatic,
  }) async {
    if (isSendingTelegram.value) return false;
    isSendingTelegram.value = true;
    telegramReleaseStatus.value = automatic
        ? 'Sending generated release notes to Telegram...'
        : 'Sending release notes to Telegram...';
    try {
      final saved = await _persistTelegramConfiguration(requireComplete: true);
      if (!saved) return false;
      await telegramReleaseNotifications.sendReleaseNote(
        appDisplayName: context.appDisplayName,
        version: context.version,
        releaseNotes: releaseNotes,
      );
      telegramReleaseStatus.value = 'Release notes sent to Telegram.';
      runner.appendSystemLog(
        'Release notes sent to Telegram for ${context.appDisplayName} '
        '${context.version ?? 'không xác định'}.',
      );
      return true;
    } catch (error) {
      telegramReleaseStatus.value =
          'Release notes generated, but Telegram send failed: $error';
      runner.appendSystemLog('Telegram release note send failed: $error');
      return false;
    } finally {
      isSendingTelegram.value = false;
    }
  }

  Future<bool> _persistTelegramConfiguration({
    required bool requireComplete,
    bool? autoSendEnabled,
  }) async {
    final token = telegramBotTokenController.text.trim();
    final chatId = telegramChatIdController.text.trim();
    final targetAutoSend =
        autoSendEnabled ?? telegramReleaseSettings.value.autoSendEnabled;
    if ((requireComplete || targetAutoSend) && token.isEmpty) {
      telegramReleaseStatus.value = 'Telegram bot token is required.';
      return false;
    }
    if ((requireComplete || targetAutoSend) && chatId.isEmpty) {
      telegramReleaseStatus.value = 'Telegram chat ID is required.';
      return false;
    }

    try {
      await telegramReleaseNotifications.saveBotToken(token);
      await telegramReleaseNotifications.saveSettings(
        TelegramReleaseSettings(
          autoSendEnabled: targetAutoSend,
          chatId: chatId,
        ),
      );
      _syncTelegramStateFromStore();
      return true;
    } catch (error) {
      telegramReleaseStatus.value = 'Failed to save Telegram settings: $error';
      runner.appendSystemLog('Failed to save Telegram settings: $error');
      return false;
    }
  }

  Future<void> saveGoogleDriveConfiguration() async {
    final saved = await _persistGoogleDriveConfiguration(
      requireClientId: false,
    );
    if (saved) {
      googleDriveReleaseStatus.value = 'Google Drive settings saved.';
    }
  }

  Future<void> connectGoogleDrive() async {
    if (_isGoogleDriveBusy) return;
    isConnectingGoogleDrive.value = true;
    googleDriveReleaseStatus.value = 'Opening Google Drive authorization...';
    try {
      final clientId = googleDriveOAuthClientIdController.text.trim();
      if (clientId.isEmpty) {
        googleDriveReleaseStatus.value = 'Google OAuth Client ID is required.';
        return;
      }

      await googleDriveReleaseUploads.connect(
        oauthClientId: clientId,
        oauthClientSecret: googleDriveOAuthClientSecretController.text,
      );
      await _loadGoogleDriveReleaseState();
      googleDriveReleaseStatus.value = 'Google Drive connected.';
      runner.appendSystemLog('Google Drive connected for APK fallback.');
    } catch (error) {
      googleDriveReleaseStatus.value = 'Google Drive connect failed: $error';
      runner.appendSystemLog('Google Drive connect failed: $error');
    } finally {
      isConnectingGoogleDrive.value = false;
    }
  }

  Future<void> disconnectGoogleDrive() async {
    if (_isGoogleDriveBusy) return;
    isConnectingGoogleDrive.value = true;
    try {
      await googleDriveReleaseUploads.disconnect();
      await _loadGoogleDriveReleaseState();
      googleDriveReleaseStatus.value = 'Google Drive disconnected.';
      runner.appendSystemLog('Google Drive disconnected.');
    } catch (error) {
      googleDriveReleaseStatus.value = 'Google Drive disconnect failed: $error';
      runner.appendSystemLog('Google Drive disconnect failed: $error');
    } finally {
      isConnectingGoogleDrive.value = false;
    }
  }

  Future<void> testGoogleDriveConnection() async {
    if (_isGoogleDriveBusy) return;
    isTestingGoogleDrive.value = true;
    googleDriveReleaseStatus.value = 'Testing Google Drive upload folder...';
    try {
      final saved = await _persistGoogleDriveConfiguration(
        requireClientId: true,
        requireCredentials: true,
      );
      if (!saved) return;

      final folder = await googleDriveReleaseUploads.testConnection();
      await _loadGoogleDriveReleaseState();
      googleDriveReleaseStatus.value =
          'Google Drive ready: ${folder.name.isEmpty ? folder.id : folder.name}.';
      runner.appendSystemLog('Google Drive APK folder ready: ${folder.id}');
    } catch (error) {
      googleDriveReleaseStatus.value = 'Google Drive test failed: $error';
      runner.appendSystemLog('Google Drive test failed: $error');
    } finally {
      isTestingGoogleDrive.value = false;
    }
  }

  Future<void> buildOrUploadReleaseApkToGoogleDrive() async {
    if (_isGoogleDriveBusy) return;

    final currentProject = project.value;
    if (currentProject == null) {
      googleDriveReleaseStatus.value =
          'Select a project before uploading an APK to Google Drive.';
      return;
    }

    isUploadingGoogleDriveApk.value = true;
    googleDriveReleaseStatus.value =
        'Preparing release APK for Google Drive...';
    var workflowStarted = false;
    try {
      final saved = await _persistGoogleDriveConfiguration(
        requireClientId: true,
        requireCredentials: true,
      );
      if (!saved) return;

      final sendDriveLinkToTelegram =
          googleDriveReleaseSettings.value.sendApkLinkToTelegramEnabled;
      final appDisplayName = await _deployAppDisplayName(currentProject);
      final existingArtifact = await releaseApkArtifacts.findExistingAndRename(
        project: currentProject,
        appDisplayName: appDisplayName,
      );
      final needsBuild = existingArtifact == null;
      runner.beginWorkflow(
        totalSteps: (needsBuild ? 2 : 1) + (sendDriveLinkToTelegram ? 1 : 0),
        label: needsBuild
            ? 'Build and upload APK to Drive'
            : 'Upload APK to Drive',
      );
      workflowStarted = true;

      final artifact =
          existingArtifact ??
          await _buildReleaseApkArtifactForDrive(
            project: currentProject,
            appDisplayName: appDisplayName,
          );
      if (existingArtifact == null) {
        runner.appendSystemLog('Release APK built: ${artifact.file.path}');
      } else {
        runner.appendSystemLog(
          'Existing release APK found: ${artifact.file.path}',
        );
      }

      final upload = await _uploadReleaseApkToGoogleDrive(artifact);
      if (sendDriveLinkToTelegram) {
        await _sendGoogleDriveApkLinkToTelegram(
          artifact: artifact,
          upload: upload,
          oversized: false,
          trackWorkflowStep: true,
        );
      }
      runner.finishWorkflow(success: true);
    } catch (error) {
      googleDriveReleaseStatus.value =
          'Google Drive APK workflow failed: $error';
      runner.appendSystemLog('Google Drive APK workflow failed: $error');
      if (workflowStarted) {
        runner.finishWorkflow(success: false);
      }
    } finally {
      isUploadingGoogleDriveApk.value = false;
      await _refreshProjectSnapshot(currentProject.path);
    }
  }

  Future<void> setGoogleDriveFallbackEnabled(bool enabled) async {
    if (enabled) {
      final telegramSaved = await _persistTelegramConfiguration(
        requireComplete: true,
      );
      if (!telegramSaved) {
        googleDriveReleaseStatus.value = telegramReleaseStatus.value;
        return;
      }
    }

    final saved = await _persistGoogleDriveConfiguration(
      requireClientId: enabled,
      requireCredentials: enabled,
      useDriveFallbackEnabled: enabled,
    );
    if (saved) {
      googleDriveReleaseStatus.value = enabled
          ? 'Google Drive APK fallback enabled.'
          : 'Google Drive APK fallback disabled.';
    }
  }

  Future<void> setGoogleDriveApkLinkTelegramEnabled(bool enabled) async {
    if (enabled) {
      final telegramSaved = await _persistTelegramConfiguration(
        requireComplete: true,
      );
      if (!telegramSaved) {
        googleDriveReleaseStatus.value = telegramReleaseStatus.value;
        return;
      }
    }

    final saved = await _persistGoogleDriveConfiguration(
      requireClientId: enabled,
      requireCredentials: enabled,
      sendApkLinkToTelegramEnabled: enabled,
    );
    if (saved) {
      googleDriveReleaseStatus.value = enabled
          ? 'Drive APK link auto-send enabled.'
          : 'Drive APK link auto-send disabled.';
    }
  }

  Future<void> setGoogleDriveLinkReleaseNotesIncluded(bool enabled) async {
    final saved = await _persistGoogleDriveConfiguration(
      requireClientId: false,
      includeReleaseNotesInTelegramLink: enabled,
    );
    if (saved) {
      googleDriveReleaseStatus.value = enabled
          ? 'Release notes will be included with Drive links.'
          : 'Release notes will not be included with Drive links.';
    }
  }

  Future<bool> _persistGoogleDriveConfiguration({
    required bool requireClientId,
    bool requireCredentials = false,
    bool? useDriveFallbackEnabled,
    bool? sendApkLinkToTelegramEnabled,
    bool? includeReleaseNotesInTelegramLink,
  }) async {
    final clientId = googleDriveOAuthClientIdController.text.trim();
    final clientSecret = googleDriveOAuthClientSecretController.text.trim();
    final currentSettings = googleDriveReleaseSettings.value;
    final targetFallback =
        useDriveFallbackEnabled ?? currentSettings.useDriveFallbackEnabled;
    final targetSendLink =
        sendApkLinkToTelegramEnabled ??
        currentSettings.sendApkLinkToTelegramEnabled;
    final targetIncludeReleaseNotes =
        includeReleaseNotesInTelegramLink ??
        currentSettings.includeReleaseNotesInTelegramLink;
    final requiresTelegram = targetFallback || targetSendLink;
    final requiresDrive = requireClientId || targetFallback || targetSendLink;
    final requiresStoredCredentials =
        requireCredentials || targetFallback || targetSendLink;

    if (requiresDrive && clientId.isEmpty) {
      googleDriveReleaseStatus.value = 'Google OAuth Client ID is required.';
      return false;
    }
    if (requiresTelegram &&
        (!hasTelegramBotToken.value || !hasTelegramChatId.value)) {
      googleDriveReleaseStatus.value =
          'Telegram bot token and chat ID are required before enabling Drive Telegram delivery.';
      return false;
    }

    final hasCredentials = await googleDriveReleaseUploads.hasCredentials();
    hasGoogleDriveCredentials.value = hasCredentials;
    if (requiresStoredCredentials && !hasCredentials) {
      googleDriveReleaseStatus.value =
          'Connect Google Drive before enabling APK link delivery.';
      return false;
    }

    try {
      await googleDriveReleaseUploads.saveOAuthClientSecret(clientSecret);
      await googleDriveReleaseUploads.saveSettings(
        GoogleDriveReleaseSettings(
          useDriveFallbackEnabled: targetFallback,
          sendApkLinkToTelegramEnabled: targetSendLink,
          includeReleaseNotesInTelegramLink: targetIncludeReleaseNotes,
          oauthClientId: clientId,
          folderId: currentSettings.folderId,
        ),
      );
      _syncGoogleDriveStateFromStore();
      return true;
    } catch (error) {
      googleDriveReleaseStatus.value =
          'Failed to save Google Drive settings: $error';
      runner.appendSystemLog('Failed to save Google Drive settings: $error');
      return false;
    }
  }

  Future<void> saveNotificationConfiguration() async {
    final updated = notificationSettings.value.copyWith(
      endpointBaseUrl: notificationEndpointController.text.trim(),
    );
    await notifications.saveSettings(updated);
    await notifications.saveApiToken(notificationTokenController.text);
    _syncNotificationStateFromStore();
    notificationStatus.value = 'Notification settings saved.';
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final updated = notificationSettings.value.copyWith(enabled: enabled);
    await notifications.saveSettings(updated);
    _syncNotificationStateFromStore();
  }

  Future<void> refreshLinkedNotificationDevices() async {
    isLoadingNotificationDevices.value = true;
    notificationStatus.value = 'Loading linked phones...';
    final previousSelectedIds = notificationSettings.value.selectedDeviceIds
        .toSet();
    try {
      final devices = await notifications.fetchDevices();
      linkedNotificationDevices.assignAll(devices);
      _syncNotificationStateFromStore();
      final currentSelectedIds = notificationSettings.value.selectedDeviceIds
          .toSet();
      final removedSelectedCount = previousSelectedIds
          .difference(currentSelectedIds)
          .length;
      notificationStatus.value = devices.isEmpty
          ? 'No linked phones found.'
          : removedSelectedCount > 0
          ? 'Linked phones refreshed. Removed $removedSelectedCount unavailable selection(s).'
          : 'Linked phones refreshed.';
    } catch (error) {
      notificationStatus.value = error.toString();
      runner.appendSystemLog('Notification devices refresh failed: $error');
    } finally {
      isLoadingNotificationDevices.value = false;
    }
  }

  Future<void> toggleNotificationDevice(String deviceId, bool selected) async {
    final ids = notificationSettings.value.selectedDeviceIds.toSet();
    if (selected) {
      ids.add(deviceId);
    } else {
      ids.remove(deviceId);
    }

    await notifications.saveSettings(
      notificationSettings.value.copyWith(selectedDeviceIds: ids.toList()),
    );
    _syncNotificationStateFromStore();
  }

  Future<NotificationPairingSession?> createPhonePairing() async {
    await saveNotificationConfiguration();
    try {
      final session = await notifications.createPairingSession();
      notificationStatus.value = 'Pairing code ready.';
      return session;
    } catch (error) {
      notificationStatus.value = error.toString();
      runner.appendSystemLog('Phone pairing failed: $error');
      return null;
    }
  }

  Future<NotificationPairingPollResult?> pollPhonePairing(
    String pairingId,
  ) async {
    try {
      final result = await notifications.pollPairing(pairingId);
      final device = result.device;
      if (result.status == NotificationPairingStatus.linked && device != null) {
        await notifications.saveLinkedDevice(device);
        _syncNotificationStateFromStore();
        notificationStatus.value = 'Linked ${device.label}.';
      } else if (result.status == NotificationPairingStatus.expired) {
        notificationStatus.value = 'Pairing code expired.';
      }
      return result;
    } catch (error) {
      notificationStatus.value = error.toString();
      runner.appendSystemLog('Phone pairing poll failed: $error');
      return null;
    }
  }

  Future<void> unlinkNotificationDevice(LinkedNotificationDevice device) async {
    try {
      await notifications.unlinkDevice(device.id);
      _syncNotificationStateFromStore();
      notificationStatus.value = 'Unlinked ${device.label}.';
    } catch (error) {
      notificationStatus.value = error.toString();
      runner.appendSystemLog('Unlink phone failed: $error');
    }
  }

  Future<void> sendTestNotification() async {
    await saveNotificationConfiguration();
    try {
      await notifications.sendTestNotification();
      notificationStatus.value = 'Test notification sent.';
    } catch (error) {
      notificationStatus.value = error.toString();
      runner.appendSystemLog('Test notification failed: $error');
    }
  }

  List<String> _fastlaneGemUpdateArguments() {
    final arguments = <String>[
      'update',
      'fastlane',
      '--user-install',
      '--no-document',
      '--conservative',
      '--minimal-deps',
    ];

    final localAppData = Platform.environment['LOCALAPPDATA']?.trim();
    if (Platform.isWindows && localAppData != null && localAppData.isNotEmpty) {
      arguments.addAll([
        '--bindir',
        p.join(localAppData, 'Microsoft', 'WindowsApps'),
      ]);
    }

    return arguments;
  }

  Future<void> _runFlutterCommand({
    required String statusLabel,
    required String activePath,
    required List<String> arguments,
  }) async {
    final currentProject = project.value;
    if (currentProject == null) {
      runner.appendSystemLog('Select a project before running Flutter tools.');
      return;
    }
    if (runner.isBusy) return;

    final pubspec = File(p.join(currentProject.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      runner.appendSystemLog(
        'Selected project does not contain a pubspec.yaml file.',
      );
      return;
    }

    await runner.runCommand(
      workingDirectory: currentProject.path,
      statusLabel: statusLabel,
      activePath: activePath,
      executable: runner.resolveFlutterExecutable(),
      arguments: arguments,
      clearLog: true,
    );

    await _refreshProjectSnapshot(currentProject.path);
  }

  Future<void> stopRun() async {
    await runner.stop();
  }

  Future<ReleaseApkArtifact> _buildReleaseApkArtifactForDrive({
    required ReleaseProject project,
    required String appDisplayName,
  }) async {
    googleDriveReleaseStatus.value =
        'No release APK found; building a new APK...';
    return releaseApkArtifacts.buildAndRename(
      project: project,
      appDisplayName: appDisplayName,
    );
  }

  Future<GoogleDriveReleaseUploadResult> _uploadReleaseApkToGoogleDrive(
    ReleaseApkArtifact artifact,
  ) async {
    runner.beginWorkflowStep('Upload APK to Drive');
    googleDriveReleaseStatus.value = 'Uploading release APK to Google Drive...';
    var succeeded = false;
    try {
      final upload = await googleDriveReleaseUploads.uploadReleaseApk(
        apkFile: artifact.file,
        appDisplayName: artifact.appDisplayName,
        version: artifact.fullVersion,
        buildDate: artifact.buildDate,
      );
      succeeded = true;
      final sizeLabel = formatGoogleDriveReleaseMegabytes(upload.fileSizeBytes);
      googleDriveReleaseStatus.value =
          'Release APK uploaded to Google Drive: ${upload.downloadUrl}';
      runner.appendSystemLog(
        'Release APK uploaded to Google Drive '
        '(${upload.fileName}, $sizeLabel MB): ${upload.downloadUrl}',
      );
      return upload;
    } finally {
      runner.completeWorkflowStep(success: succeeded);
    }
  }

  Future<void> _sendGoogleDriveApkLinkToTelegram({
    required ReleaseApkArtifact artifact,
    required GoogleDriveReleaseUploadResult upload,
    required bool oversized,
    bool trackWorkflowStep = false,
  }) async {
    if (trackWorkflowStep) {
      runner.beginWorkflowStep('Send Drive link to Telegram');
    }
    isSendingTelegram.value = true;
    telegramReleaseStatus.value =
        'Sending Google Drive APK link to Telegram...';
    var succeeded = false;
    try {
      final driveSettings = googleDriveReleaseSettings.value;
      await telegramReleaseNotifications.sendReleaseApkLink(
        appDisplayName: artifact.appDisplayName,
        version: artifact.fullVersion,
        fileName: upload.fileName,
        fileSizeBytes: upload.fileSizeBytes,
        downloadUrl: upload.downloadUrl,
        releaseNotes: driveSettings.includeReleaseNotesInTelegramLink
            ? releaseNotesController.text
            : null,
        oversized: oversized,
      );
      succeeded = true;
      telegramReleaseStatus.value = 'Release APK Drive link sent to Telegram.';
      runner.appendSystemLog(
        'Release APK Drive link sent to Telegram: ${upload.downloadUrl}',
      );
    } catch (error) {
      telegramReleaseStatus.value =
          'Google Drive APK link Telegram send failed: $error';
      runner.appendSystemLog(
        'Google Drive APK link Telegram send failed: $error',
      );
      rethrow;
    } finally {
      if (trackWorkflowStep) {
        runner.completeWorkflowStep(success: succeeded);
      }
      isSendingTelegram.value = false;
    }
  }

  Future<void> _runDeploy(
    ReleaseProject currentProject,
    ReleaseScript script,
    Map<String, String> environment,
  ) async {
    var playChoice = currentProject.hasPlayReleaseTools
        ? playUploadChoice.value
        : PlayUploadChoice.skip;

    if (playChoice == PlayUploadChoice.ask) {
      final selectedChoice = await _confirmPlayUploadChoice();
      if (selectedChoice == null) {
        runner.appendSystemLog('Deployment cancelled before CH Play choice.');
        return;
      }
      playChoice = selectedChoice;
    }

    final shouldUpload = playChoice == PlayUploadChoice.upload;
    final shouldValidateImages =
        shouldUpload &&
        uploadPlayListingImages.value &&
        validatePlayImages.value &&
        currentProject.imageValidator != null;
    final shouldSendApk =
        shouldUpload &&
        (telegramReleaseSettings.value.autoSendEnabled ||
            googleDriveReleaseSettings.value.sendApkLinkToTelegramEnabled);
    final args = _deployArgs(currentProject, playChoice);
    final deployEnvironment = Map<String, String>.from(environment);
    if (currentProject.hasPlayReleaseTools) {
      deployEnvironment['UPLOAD_PLAY_IMAGES'] = uploadPlayListingImages.value
          ? '1'
          : '0';
    }

    final totalSteps =
        1 +
        (shouldValidateImages ? 1 : 0) +
        (shouldUpload ? 1 : 0) +
        (shouldSendApk ? 1 : 0);
    final appDisplayName = await _deployAppDisplayName(currentProject);
    runner.beginWorkflow(
      totalSteps: totalSteps,
      label: 'Deploy $appDisplayName',
    );
    var succeeded = false;
    try {
      if (shouldValidateImages) {
        final validationCode = await runner.run(
          project: currentProject,
          script: currentProject.imageValidator!,
          environment: deployEnvironment,
          clearLog: true,
          allowDuringWorkflow: true,
        );
        if (validationCode != 0) return;
      }

      final deployCode = await runner.run(
        project: currentProject,
        script: script,
        args: args,
        environment: deployEnvironment,
        clearLog: !shouldValidateImages,
        allowDuringWorkflow: true,
      );
      if (deployCode != 0) return;

      if (shouldUpload) {
        final artifact = await releaseApkArtifacts.buildAndRename(
          project: currentProject,
          appDisplayName: appDisplayName,
        );
        runner.appendSystemLog('Release APK ready: ${artifact.file.path}');

        if (shouldSendApk) {
          final sent = await _deliverReleaseApk(artifact);
          if (!sent) return;
        } else {
          runner.appendSystemLog(
            'Telegram auto send is disabled; APK was kept locally.',
          );
        }
      }
      succeeded = true;
    } catch (error) {
      runner.appendSystemLog('Post-deploy APK step failed: $error');
      if (shouldSendApk) {
        telegramReleaseStatus.value =
            'CH Play deploy completed, but APK delivery failed: $error';
      }
    } finally {
      runner.finishWorkflow(success: succeeded);
      await _refreshProjectSnapshot(currentProject.path);
    }
  }

  Future<bool> _deliverReleaseApk(ReleaseApkArtifact artifact) async {
    runner.beginWorkflowStep('Deliver APK');
    isSendingTelegram.value = true;
    telegramReleaseStatus.value = 'Delivering release APK...';
    var succeeded = false;
    var usingDriveLink = false;
    try {
      final fileSize = await artifact.file.length();
      final driveSettings = googleDriveReleaseSettings.value;
      final oversized = fileSize > telegramDocumentMaxBytes;
      usingDriveLink =
          driveSettings.sendApkLinkToTelegramEnabled ||
          (oversized && driveSettings.useDriveFallbackEnabled);

      if (usingDriveLink) {
        telegramReleaseStatus.value = oversized
            ? 'Uploading oversized APK to Google Drive...'
            : 'Uploading release APK to Google Drive...';
        final upload = await googleDriveReleaseUploads.uploadReleaseApk(
          apkFile: artifact.file,
          appDisplayName: artifact.appDisplayName,
          version: artifact.fullVersion,
          buildDate: artifact.buildDate,
        );
        await _sendGoogleDriveApkLinkToTelegram(
          artifact: artifact,
          upload: upload,
          oversized: oversized,
        );
        runner.appendSystemLog(
          'Release APK uploaded to Google Drive and link sent to Telegram: '
          '${upload.downloadUrl}',
        );
      } else {
        telegramReleaseStatus.value = 'Uploading release APK to Telegram...';
        await telegramReleaseNotifications.sendReleaseApk(
          apkFile: artifact.file,
          appDisplayName: artifact.appDisplayName,
          version: artifact.fullVersion,
          buildDate: artifact.buildDate,
        );
        runner.appendSystemLog(
          'Release APK sent to Telegram: ${artifact.file.path}',
        );
      }
      succeeded = true;
      telegramReleaseStatus.value = usingDriveLink
          ? 'Release APK Drive link sent to Telegram.'
          : 'Release APK sent to Telegram.';
      return true;
    } catch (error) {
      final channel = usingDriveLink
          ? 'Google Drive APK delivery'
          : 'Telegram APK upload';
      telegramReleaseStatus.value =
          'CH Play deploy completed, but $channel failed: $error';
      runner.appendSystemLog('$channel failed: $error');
      return false;
    } finally {
      runner.completeWorkflowStep(success: succeeded);
      isSendingTelegram.value = false;
    }
  }

  Future<String> _deployAppDisplayName(ReleaseProject currentProject) async {
    final managedProject = _chPlayProjectByPath(currentProject.path);
    if (managedProject != null) return managedProject.name;

    final generatedContext = _generatedReleaseContext;
    if (generatedContext != null &&
        p.equals(generatedContext.projectPath, currentProject.path) &&
        generatedContext.appDisplayName.trim().isNotEmpty) {
      return generatedContext.appDisplayName.trim();
    }
    return resolveReleaseNoteAppName(currentProject);
  }

  List<String> _deployArgs(
    ReleaseProject currentProject,
    PlayUploadChoice playChoice,
  ) {
    final releaseNotes = releaseNotesController.text.trim();
    final shouldUpload = playChoice == PlayUploadChoice.upload;

    return [
      if (currentProject.hasFirebaseDeployTools)
        includeFirebaseDeploy.value ? 'yes' : 'no',
      if (currentProject.hasPlayReleaseTools) shouldUpload ? 'yes' : 'no',
      if (shouldUpload && releaseNotes.isNotEmpty) releaseNotes,
    ];
  }

  Future<PlayUploadChoice?> _confirmPlayUploadChoice() {
    return Get.dialog<PlayUploadChoice>(
      AlertDialog(
        title: const Text('CH Play upload'),
        content: const Text(
          'Do you want to upload this deployment to CH Play?',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back<PlayUploadChoice>(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Get.back(result: PlayUploadChoice.skip),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: PlayUploadChoice.upload),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickDirectoryPath({
    required String dialogTitle,
    String? initialDirectory,
  }) async {
    if (Platform.isWindows) {
      return file_selector.getDirectoryPath(
        initialDirectory: _existingDirectoryOrNull(initialDirectory),
        confirmButtonText: 'Select',
      );
    }

    return FilePicker.platform.getDirectoryPath(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
    );
  }

  Future<String?> _pickFilePath({
    required String dialogTitle,
    required List<String> extensions,
  }) async {
    if (Platform.isWindows) {
      final file = await file_selector.openFile(
        acceptedTypeGroups: [file_selector.XTypeGroup(extensions: extensions)],
        initialDirectory: _existingDirectoryOrNull(_initialDirectory()),
        confirmButtonText: 'Open',
      );
      return file?.path;
    }

    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    return result?.files.single.path;
  }

  String? _existingDirectoryOrNull(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final normalizedPath = p.normalize(path);
    return Directory(normalizedPath).existsSync() ? normalizedPath : null;
  }

  List<String> _initialProjectPaths() {
    final dismissedPaths = store.dismissedRecentProjectPaths
        .map((path) => p.normalize(path).toLowerCase())
        .toSet();
    final paths = <String>[
      ...store.recentProjectPaths,
      ..._sampleProjectPaths(),
    ];
    final seen = <String>{};
    return paths
        .map(p.normalize)
        .where((path) => Directory(path).existsSync())
        .where((path) => !dismissedPaths.contains(path.toLowerCase()))
        .where((path) => seen.add(path.toLowerCase()))
        .toList();
  }

  List<String> _sampleProjectPaths() {
    final parent = Directory.current.parent;
    return ['VNetrip_4_0', 'vnetrip_shop']
        .map((name) => p.join(parent.path, name))
        .where((path) => Directory(path).existsSync())
        .toList();
  }

  String? _initialDirectory() {
    final currentProject = project.value;
    if (currentProject != null) return currentProject.path;
    if (recentPaths.isNotEmpty) return recentPaths.first;

    return Directory.current.parent.path;
  }

  List<String> _customArgs() {
    return _splitArguments(customArgsController.text.trim());
  }

  Future<void> _loadGeminiApiKey() async {
    try {
      final apiKey = await geminiEnv.readApiKey();
      if (apiKey == null || apiKey.isEmpty) return;
      geminiApiKeyController.text = apiKey;
      _syncGeminiKeyState();
    } catch (error) {
      releaseNoteAiStatus.value = 'Failed to load Gemini API key: $error';
    }
  }

  void _syncGeminiKeyState() {
    hasGeminiApiKey.value = geminiApiKeyController.text.trim().isNotEmpty;
  }

  Future<void> _loadTelegramReleaseState() async {
    try {
      _syncTelegramStateFromStore();
      telegramBotTokenController.text =
          await telegramReleaseNotifications.readBotToken() ?? '';
      _syncTelegramFormState();
    } catch (error) {
      telegramReleaseStatus.value = 'Failed to load Telegram settings: $error';
    }
  }

  void _syncTelegramStateFromStore() {
    final settings = telegramReleaseNotifications.settings;
    telegramReleaseSettings.value = settings;
    if (telegramChatIdController.text != settings.chatId) {
      telegramChatIdController.text = settings.chatId;
    }
    _syncTelegramFormState();
  }

  void _syncTelegramFormState() {
    hasTelegramBotToken.value = telegramBotTokenController.text
        .trim()
        .isNotEmpty;
    hasTelegramChatId.value = telegramChatIdController.text.trim().isNotEmpty;
  }

  Future<void> _loadGoogleDriveReleaseState() async {
    try {
      _syncGoogleDriveStateFromStore();
      googleDriveOAuthClientSecretController.text =
          await googleDriveReleaseUploads.readOAuthClientSecret() ?? '';
      hasGoogleDriveCredentials.value = await googleDriveReleaseUploads
          .hasCredentials();
      hasGoogleDriveOAuthClientSecret.value = await googleDriveReleaseUploads
          .hasOAuthClientSecret();
    } catch (error) {
      googleDriveReleaseStatus.value =
          'Failed to load Google Drive settings: $error';
    }
  }

  void _syncGoogleDriveStateFromStore() {
    final settings = googleDriveReleaseUploads.settings;
    googleDriveReleaseSettings.value = settings;
    if (googleDriveOAuthClientIdController.text != settings.oauthClientId) {
      googleDriveOAuthClientIdController.text = settings.oauthClientId;
    }
    _syncGoogleDriveFormState();
  }

  void _syncGoogleDriveFormState() {
    hasGoogleDriveOAuthClientId.value = googleDriveOAuthClientIdController.text
        .trim()
        .isNotEmpty;
    hasGoogleDriveOAuthClientSecret.value =
        googleDriveOAuthClientSecretController.text.trim().isNotEmpty;
  }

  void _syncReleaseNoteState() {
    hasReleaseNoteText.value = releaseNotesController.text.trim().isNotEmpty;
  }

  void _clearGeneratedReleaseContext() {
    _generatedReleaseContext = null;
    hasTelegramReleaseContext.value = false;
  }

  Future<void> _loadNotificationState() async {
    _syncNotificationStateFromStore();
    notificationTokenController.text = await notifications.readApiToken() ?? '';
    if (notificationSettings.value.hasEndpoint) {
      await refreshLinkedNotificationDevices();
    }
  }

  void _syncNotificationStateFromStore() {
    final settings = notifications.settings;
    notificationSettings.value = settings;
    linkedNotificationDevices.assignAll(notifications.linkedDevices);
    if (notificationEndpointController.text != settings.endpointBaseUrl) {
      notificationEndpointController.text = settings.endpointBaseUrl;
    }
  }

  Future<void> _loadManagedStoreProjects() async {
    await _loadManagedChPlayProjects(refreshAfterLoad: false);
    await _loadManagedAppStoreProjects(refreshAfterLoad: false);
  }

  Future<void> _loadManagedChPlayProjects({
    bool refreshAfterLoad = true,
  }) async {
    final projects = <ChPlayProject>[];
    for (final project in store.chPlayProjects) {
      final metadata = await chPlayCredentialStore.metadata(project.id);
      projects.add(project.withCredentialMetadata(metadata));
    }

    await store.saveChPlayProjects(projects);
    chPlayProjects.assignAll(projects);

    for (final project in projects) {
      await _loadChPlayLocalSnapshot(project);
    }

    if (refreshAfterLoad && projects.isNotEmpty) {
      await refreshAllChPlayProjects();
    }
  }

  Future<void> _loadManagedAppStoreProjects({
    bool refreshAfterLoad = true,
  }) async {
    final projects = <AppStoreProject>[];
    for (final project in store.appStoreProjects) {
      final metadata = await appStoreCredentialStore.metadata(project.id);
      projects.add(project.withCredentialMetadata(metadata));
    }

    await store.saveAppStoreProjects(projects);
    appStoreProjects.assignAll(projects);

    for (final project in projects) {
      await _loadAppStoreLocalSnapshot(project);
    }

    if (refreshAfterLoad && projects.isNotEmpty) {
      for (final project in projects) {
        await _refreshAppStoreProject(project);
      }
    }
  }

  Future<void> _loadChPlayLocalSnapshot(ChPlayProject project) async {
    try {
      _setChPlaySnapshot(
        project.id,
        await chPlayVersionChecker.readLocalSnapshot(project),
      );
    } catch (error) {
      _setChPlaySnapshot(
        project.id,
        ChPlayVersionSnapshot(
          status: ChPlayComparisonStatus.failed,
          message: error.toString(),
        ),
      );
    }
  }

  Future<void> _loadAppStoreLocalSnapshot(AppStoreProject project) async {
    try {
      _setAppStoreSnapshot(
        project.id,
        await appStoreVersionChecker.readLocalSnapshot(project),
      );
    } catch (error) {
      _setAppStoreSnapshot(
        project.id,
        AppStoreVersionSnapshot(
          status: AppStoreComparisonStatus.failed,
          message: error.toString(),
        ),
      );
    }
  }

  Future<void> _refreshChPlayProject(ChPlayProject project) async {
    final currentSnapshot =
        chPlaySnapshots[project.id] ?? const ChPlayVersionSnapshot();
    _setChPlaySnapshot(
      project.id,
      currentSnapshot.copyWith(isRefreshing: true),
    );

    try {
      final credentials = await readChPlayCredentials(project.id);
      final snapshot = await chPlayVersionChecker.refreshProject(
        project: project,
        credentials: credentials,
      );
      _setChPlaySnapshot(project.id, snapshot);
    } catch (error) {
      _setChPlaySnapshot(
        project.id,
        currentSnapshot.copyWith(
          status: ChPlayComparisonStatus.failed,
          message: error.toString(),
          lastCheckedAt: DateTime.now(),
          isRefreshing: false,
        ),
      );
    }
  }

  Future<void> _refreshAppStoreProject(AppStoreProject project) async {
    final currentSnapshot =
        appStoreSnapshots[project.id] ?? const AppStoreVersionSnapshot();
    _setAppStoreSnapshot(
      project.id,
      currentSnapshot.copyWith(isRefreshing: true),
    );

    try {
      final credentials = await readAppStoreCredentials(project.id);
      final snapshot = await appStoreVersionChecker.refreshProject(
        project: project,
        credentials: credentials,
      );
      _setAppStoreSnapshot(project.id, snapshot);
    } catch (error) {
      _setAppStoreSnapshot(
        project.id,
        currentSnapshot.copyWith(
          status: AppStoreComparisonStatus.failed,
          message: error.toString(),
          lastCheckedAt: DateTime.now(),
          isRefreshing: false,
        ),
      );
    }
  }

  void _setChPlaySnapshot(String projectId, ChPlayVersionSnapshot snapshot) {
    chPlaySnapshots[projectId] = snapshot;
    chPlaySnapshots.refresh();
  }

  void _setAppStoreSnapshot(
    String projectId,
    AppStoreVersionSnapshot snapshot,
  ) {
    appStoreSnapshots[projectId] = snapshot;
    appStoreSnapshots.refresh();
  }

  ChPlayProject? _chPlayProjectByPath(String path) {
    final lowerPath = p.normalize(path).toLowerCase();
    for (final project in chPlayProjects) {
      if (project.path.toLowerCase() == lowerPath) return project;
    }
    return null;
  }

  AppStoreProject? _appStoreProjectByPath(String path) {
    final lowerPath = p.normalize(path).toLowerCase();
    for (final project in appStoreProjects) {
      if (project.path.toLowerCase() == lowerPath) return project;
    }
    return null;
  }

  String _newChPlayProjectId() {
    return 'chp_${DateTime.now().microsecondsSinceEpoch}';
  }

  String _newAppStoreProjectId() {
    return 'aps_${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<void> _refreshProjectSnapshot(String path) async {
    try {
      final refreshedProject = await catalog.inspect(path);
      final keepFirebase = includeFirebaseDeploy.value;
      final keepPlayChoice = playUploadChoice.value;
      final keepUploadPlayListingImages = uploadPlayListingImages.value;
      final keepImageValidation = validatePlayImages.value;

      project.value = refreshedProject;
      projectError.value = '';

      includeFirebaseDeploy.value = refreshedProject.hasFirebaseDeployTools
          ? keepFirebase
          : false;
      playUploadChoice.value = refreshedProject.hasPlayReleaseTools
          ? keepPlayChoice
          : PlayUploadChoice.skip;
      uploadPlayListingImages.value = refreshedProject.hasPlayReleaseTools
          ? keepUploadPlayListingImages
          : false;
      validatePlayImages.value = refreshedProject.imageValidator != null
          ? keepImageValidation
          : false;
    } catch (error) {
      projectError.value = 'Failed to refresh project metadata: $error';
    }
  }

  List<String> _splitArguments(String input) {
    if (input.isEmpty) return const [];

    final args = <String>[];
    final buffer = StringBuffer();
    String? quote;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          buffer.write(char);
        }
        continue;
      }

      if (char == '"' || char == "'") {
        quote = char;
      } else if (char.trim().isEmpty) {
        if (buffer.isNotEmpty) {
          args.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(char);
      }
    }

    if (buffer.isNotEmpty) {
      args.add(buffer.toString());
    }

    return args;
  }
}

const _playReleaseNoteCharacterLimit = 500;

class _GeneratedReleaseContext {
  const _GeneratedReleaseContext({
    required this.projectPath,
    required this.appDisplayName,
    required this.version,
  });

  final String projectPath;
  final String appDisplayName;
  final String? version;
}
