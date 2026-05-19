import 'dart:io';

import 'package:app_release_center/app/data/release_center_connect.dart';
import 'package:app_release_center/app/models/release_fastlane_lane.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/models/release_script.dart';
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
    required this.runner,
    required this.connect,
  });

  final ProjectStoreService store;
  final ScriptCatalogService catalog;
  final ReleaseRunnerService runner;
  final ReleaseCenterConnect connect;

  final project = Rxn<ReleaseProject>();
  final recentPaths = <String>[].obs;
  final isLoadingProject = false.obs;
  final projectError = ''.obs;
  final includeFirebaseDeploy = true.obs;
  final playUploadChoice = PlayUploadChoice.ask.obs;
  final uploadPlayListingImages = true.obs;
  final validatePlayImages = true.obs;

  final releaseNotesController = TextEditingController();
  final customArgsController = TextEditingController();
  final stdinController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    recentPaths.assignAll(_initialProjectPaths());
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

    await runner.runCommand(
      workingDirectory: workingDirectory,
      statusLabel: 'gem update fastlane',
      activePath: 'extended:fastlane-update',
      executable: runner.resolveGemExecutable(),
      arguments: const ['update', 'fastlane'],
      clearLog: false,
    );

    await _refreshProjectSnapshot(currentProject.path);
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
