import 'dart:io';

import 'package:app_release_center/app/data/release_center_connect.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/models/release_script.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:app_release_center/app/services/script_catalog_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

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
  final includePlayUpload = false.obs;
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
      includePlayUpload.value = false;
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
    if (value.trim().isEmpty) return;

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
    final shouldUpload = includePlayUpload.value;
    final args = <String>[
      shouldUpload ? 'yes' : 'no',
      if (shouldUpload && releaseNotesController.text.trim().isNotEmpty)
        releaseNotesController.text.trim(),
    ];

    if (shouldUpload &&
        validatePlayImages.value &&
        currentProject.imageValidator != null) {
      final validationCode = await runner.run(
        project: currentProject,
        script: currentProject.imageValidator!,
        environment: environment,
        clearLog: true,
      );
      if (validationCode != 0) return;

      await runner.run(
        project: currentProject,
        script: script,
        args: args,
        environment: environment,
      );
      return;
    }

    await runner.run(
      project: currentProject,
      script: script,
      args: args,
      environment: environment,
      clearLog: true,
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
