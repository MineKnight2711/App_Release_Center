import 'dart:io';

import 'package:app_release_center/app/data/release_center_connect.dart';
import 'package:app_release_center/app/models/app_store_credentials.dart';
import 'package:app_release_center/app/models/app_store_project.dart';
import 'package:app_release_center/app/models/app_store_version_snapshot.dart';
import 'package:app_release_center/app/models/ch_play_credentials.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/models/ch_play_version_snapshot.dart';
import 'package:app_release_center/app/models/release_fastlane_lane.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/models/release_script.dart';
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
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

enum PlayUploadChoice { ask, upload, skip }

class HomeController extends GetxController {
  HomeController({
    required this.store,
    required this.catalog,
    required this.androidCicdCloner,
    required this.runner,
    required this.connect,
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
  final ReleaseRunnerService runner;
  final ReleaseCenterConnect connect;
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
  final includeFirebaseDeploy = true.obs;
  final playUploadChoice = PlayUploadChoice.ask.obs;
  final uploadPlayListingImages = true.obs;
  final validatePlayImages = true.obs;

  final releaseNotesController = TextEditingController();
  final customArgsController = TextEditingController();
  final stdinController = TextEditingController();
  final _sessionChPlayCredentials = <String, ChPlayCredentials>{};
  final _sessionAppStoreCredentials = <String, AppStoreCredentials>{};

  @override
  void onInit() {
    super.onInit();
    recentPaths.assignAll(_initialProjectPaths());
    _loadManagedStoreProjects();
    final savedPath = store.lastProjectPath;
    if (savedPath != null && Directory(savedPath).existsSync()) {
      loadProject(savedPath);
    }
  }

  @override
  void onClose() {
    releaseNotesController.dispose();
    customArgsController.dispose();
    stdinController.dispose();
    super.onClose();
  }

  Future<void> pickProjectDirectory() async {
    final selectedPath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select project directory',
      initialDirectory: _initialDirectory(),
    );

    if (selectedPath == null) return;
    await loadProject(selectedPath);
  }

  Future<ChPlayProject?> pickChPlayProjectDraft() async {
    final selectedPath = await FilePicker.getDirectoryPath(
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
    final selectedPath = await FilePicker.getDirectoryPath(
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
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select Google Play service-account JSON',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return null;

    return File(path).readAsString();
  }

  Future<String?> pickAppStoreP8Content() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select App Store Connect .p8 key',
      type: FileType.custom,
      allowedExtensions: const ['p8'],
    );
    final path = result?.files.single.path;
    if (path == null) return null;

    return File(path).readAsString();
  }

  Future<String?> pickJksPath() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select Android keystore',
      type: FileType.custom,
      allowedExtensions: const ['jks', 'keystore'],
    );
    return result?.files.single.path;
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
    if (runner.isRunning.value) {
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
    if (runner.isRunning.value) {
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
    if (runner.isRunning.value) {
      runner.appendSystemLog('Wait for the active command before refreshing.');
      return;
    }

    await _refreshChPlayProject(project);
  }

  Future<void> refreshAppStoreProject(AppStoreProject project) async {
    if (runner.isRunning.value) {
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
      project.value = loadedProject;
      includeFirebaseDeploy.value = loadedProject.hasFirebaseDeployTools;
      playUploadChoice.value = loadedProject.hasPlayReleaseTools
          ? PlayUploadChoice.ask
          : PlayUploadChoice.skip;
      uploadPlayListingImages.value = loadedProject.hasPlayReleaseTools;
      validatePlayImages.value = loadedProject.imageValidator != null;
      await store.saveProjectPath(loadedProject.path);
      recentPaths.assignAll(_initialProjectPaths());
    } on FileSystemException catch (error) {
      project.value = null;
      projectError.value = error.message;
    } catch (error) {
      project.value = null;
      projectError.value = error.toString();
    } finally {
      isLoadingProject.value = false;
    }
  }

  Future<void> runScript(ReleaseScript script) async {
    final currentProject = project.value;
    if (currentProject == null || runner.isRunning.value) return;

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
    if (currentProject == null || runner.isRunning.value) return;

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
    if (runner.isRunning.value) return;

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
    if (runner.isRunning.value) return;

    final workingDirectory = currentProject.androidDirectory.existsSync()
        ? currentProject.androidDirectory.path
        : currentProject.path;

    final versionExitCode = await runner.runCommand(
      workingDirectory: workingDirectory,
      statusLabel: 'fastlane --version',
      activePath: 'extended:fastlane-version',
      executable: runner.resolveFastlaneExecutable(),
      arguments: const ['--version'],
      clearLog: true,
    );
    if (versionExitCode != 0) return;

    final updateArguments = _fastlaneGemUpdateArguments();
    await runner.runCommand(
      workingDirectory: workingDirectory,
      statusLabel: 'gem update fastlane --user-install',
      activePath: 'extended:fastlane-update',
      executable: runner.resolveGemExecutable(),
      arguments: updateArguments,
      clearLog: false,
    );

    await _refreshProjectSnapshot(currentProject.path);
  }

  Future<AndroidCicdClonePreview?> previewAndroidCicdClone({
    AndroidCicdCloneMode mode = AndroidCicdCloneMode.adaptive,
  }) async {
    final currentProject = project.value;
    if (currentProject == null) {
      runner.appendSystemLog('Select a project before cloning Android CI/CD.');
      return null;
    }
    if (runner.isRunning.value) return null;

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
    if (runner.isRunning.value) return;

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

  Future<void> validateImages() async {
    final currentProject = project.value;
    final validator = currentProject?.imageValidator;
    if (currentProject == null || validator == null || runner.isRunning.value) {
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

  Future<void> stopRun() async {
    await runner.stop();
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
    final args = _deployArgs(currentProject, playChoice);
    final deployEnvironment = Map<String, String>.from(environment);
    if (currentProject.hasPlayReleaseTools) {
      deployEnvironment['UPLOAD_PLAY_IMAGES'] = uploadPlayListingImages.value
          ? '1'
          : '0';
    }

    if (shouldUpload &&
        uploadPlayListingImages.value &&
        validatePlayImages.value &&
        currentProject.imageValidator != null) {
      final validationCode = await runner.run(
        project: currentProject,
        script: currentProject.imageValidator!,
        environment: deployEnvironment,
        clearLog: true,
      );
      if (validationCode != 0) return;

      await runner.run(
        project: currentProject,
        script: script,
        args: args,
        environment: deployEnvironment,
      );
      await _refreshProjectSnapshot(currentProject.path);
      return;
    }

    await runner.run(
      project: currentProject,
      script: script,
      args: args,
      environment: deployEnvironment,
      clearLog: true,
    );
    await _refreshProjectSnapshot(currentProject.path);
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

  List<String> _initialProjectPaths() {
    final paths = <String>[
      ...store.recentProjectPaths,
      ..._sampleProjectPaths(),
    ];
    final seen = <String>{};
    return paths
        .map(p.normalize)
        .where((path) => Directory(path).existsSync())
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

  Future<void> _loadManagedStoreProjects() async {
    await _loadManagedChPlayProjects(refreshAfterLoad: false);
    await _loadManagedAppStoreProjects(refreshAfterLoad: false);

    if (chPlayProjects.isNotEmpty || appStoreProjects.isNotEmpty) {
      await refreshAllStoreProjects();
    }
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
