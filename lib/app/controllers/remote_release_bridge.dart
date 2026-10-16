import 'dart:io';

import 'package:app_management_center/app/controllers/home_controller.dart';
import 'package:app_management_center/app/models/app_store_project.dart';
import 'package:app_management_center/app/models/ios_release.dart';
import 'package:app_management_center/app/services/ios_release_backend.dart';
import 'package:app_management_center/app/services/remote_release_handler.dart';
import 'package:path/path.dart' as p;

/// Runs the phone's release commands through the same calls the desktop's
/// release dialogs make, so a release started from the phone is the release
/// the desktop would have run: same preflight, steps and post-processing.
///
/// CH Play runs on this machine. iOS runs here on a Mac, or on the paired Mac
/// build host when this machine cannot build iOS itself.
class RemoteReleaseBridge implements RemoteReleaseHandler {
  RemoteReleaseBridge(this.home);

  final HomeController home;

  String? _platform;
  String? _iosProjectId;
  String _iosAction = '';
  DateTime? _since;

  IosReleaseBackend get _ios =>
      home.iosRelease.canBuildHere ? home.iosRelease : home.remoteIosRelease;

  /// Where iOS releases from here are built, as the phone should say it.
  String get _iosHost {
    if (home.iosRelease.canBuildHere) return Platform.localHostname;
    final link = home.remoteIosRelease.link.value;
    return link.isLinked ? link.displayName : '';
  }

  @override
  Future<Map<String, Object?>> overview() async {
    final workflow = home.releaseWorkflow;
    final ios = _ios;
    final current = ios.current.value;
    final log = ios.busy.value && !ios.usesLocalRunner
        ? ios.liveLog
        : home.runner.logLines;
    return {
      'android': [
        for (final project in home.chPlayProjects)
          {
            'path': project.path,
            'name': project.name,
            'applicationId': project.applicationId,
            'track': project.track.toLowerCase(),
          },
      ],
      'ios': [
        for (final project in home.appStoreProjects)
          {
            'id': project.id,
            'path': project.path,
            'name': project.name,
            'bundleId': project.bundleId,
          },
      ],
      'androidRun': workflow.currentRun.value?.toJson(),
      'androidBusy': workflow.isRunning || workflow.isPreparing.value,
      'iosHost': _iosHost,
      'iosBusy': ios.busy.value,
      'iosCurrent': current == null ? null : iosRunToWire(current),
      'logTail': log.length > 80 ? log.sublist(log.length - 80) : log.toList(),
    };
  }

  @override
  Future<Map<String, Object?>> iosProject(String projectId) async {
    final project = _iosProjectFor(projectId);
    final settings = await home.iosRelease.readSettings(project);
    final local = await home.appStoreInspector.readLocalVersion(project.path);
    final ios = _ios;
    if (_iosHost.isNotEmpty) await ios.load(project);
    return {
      'projectId': project.id,
      'version': local?.name ?? '',
      'buildNumber': local?.buildNumber,
      'notes': settings.notes,
      'groups': settings.groups,
      'host': _iosHost,
      'busy': ios.busy.value,
      'runs': [
        for (final run
            in ios.history.where((run) => run.project.id == project.id).take(5))
          iosRunToWire(run),
      ],
    };
  }

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> payload) async {
    _platform = payload['platform']?.toString();
    _since = DateTime.now().subtract(const Duration(seconds: 1));
    return _platform == 'android' ? _android(payload) : _iosStep(payload);
  }

  @override
  Map<String, Object?>? get live {
    if (_platform == 'android') {
      final run = home.releaseWorkflow.currentRun.value;
      return run == null ? null : {'androidRun': run.toJson()};
    }
    if (_platform == 'ios') {
      final run = _ios.current.value;
      final since = _since;
      if (run == null || run.project.id != _iosProjectId || since == null) {
        return null;
      }
      // While preparing, the run being created; never the one before it.
      if (_iosAction == 'prepare' && run.createdAt.isBefore(since)) return null;
      return {'iosRun': iosRunToWire(run)};
    }
    return null;
  }

  @override
  List<String>? get liveLog => _platform == 'ios' && !_ios.usesLocalRunner
      ? _ios.liveLog.toList()
      : null;

  @override
  Future<void> cancel(String platform) async {
    if (platform == 'android') {
      await home.cancelAutomatedRelease();
    } else if (platform == 'ios') {
      await _ios.cancel();
    }
  }

  Future<Map<String, Object?>> _android(Map<String, Object?> payload) async {
    switch (payload['action']) {
      case 'prepare':
        final path = payload['projectPath']?.toString() ?? '';
        final known = home.chPlayProjects.any(
          (project) => p.equals(p.normalize(project.path), p.normalize(path)),
        );
        if (!known) {
          throw StateError('Dự án không có trong mục CH Play của máy tính.');
        }
        // The desktop releases the project it has open, as its own dialog
        // does; open the one the phone picked.
        final open = home.project.value;
        if (open == null || !p.equals(open.path, path)) {
          await home.loadProject(path);
        }
        if (home.project.value == null) {
          throw StateError(
            home.projectError.value.isEmpty
                ? 'Máy tính không mở được dự án.'
                : home.projectError.value,
          );
        }
        final run = await home.prepareAutomatedRelease(
          payload['track']?.toString() ?? 'internal',
        );
        return {'androidRun': run.toJson()};
      case 'start':
        final prepared = home.releaseWorkflow.currentRun.value;
        if (prepared == null) {
          throw StateError('Chưa có release nào được xem lại trên máy tính.');
        }
        if (prepared.track == 'production' &&
            payload['confirmProduction'] != true) {
          throw StateError(
            'Bản này lên thẳng production: xác nhận trên điện thoại rồi bấm '
            'lại.',
          );
        }
        return {'androidRun': (await home.startAutomatedRelease()).toJson()};
      case 'retry':
        return {'androidRun': (await home.retryAutomatedRelease()).toJson()};
      default:
        throw StateError('Bước release Android không hỗ trợ.');
    }
  }

  Future<Map<String, Object?>> _iosStep(Map<String, Object?> payload) async {
    final project = _iosProjectFor(payload['projectId']?.toString() ?? '');
    _iosProjectId = project.id;
    _iosAction = payload['action']?.toString() ?? '';
    if (_iosHost.isEmpty) {
      throw StateError(
        'Máy tính này không build iOS được và chưa ghép Mac build.',
      );
    }
    final ios = _ios;
    final settings = await home.iosRelease.readSettings(project);
    switch (_iosAction) {
      case 'prepare':
        final notes = payload['notes']?.toString() ?? '';
        final existing = payload['existingBuild'];
        await ios.load(project);
        final run = await ios.prepare(
          project: project,
          settings: notes.isEmpty
              ? settings
              : IosReleaseSettings.fromJson({
                  ...settings.toJson(),
                  'notes': notes,
                }),
          version: payload['version']?.toString(),
          existingBuild: existing is Map
              ? IosStoreBuild.fromJson(Map<String, dynamic>.from(existing))
              : null,
        );
        return {'iosRun': iosRunToWire(run)};
      case 'inspect':
        final state = await ios.inspect(
          project,
          settings,
          payload['version']?.toString() ?? '',
        );
        return {
          'builds': [for (final build in state.builds) build.toJson()],
        };
    }
    await ios.load(project);
    final runId = payload['runId']?.toString() ?? '';
    final run = _iosRun(runId, project);
    switch (_iosAction) {
      case 'continue':
        await ios.continueToTestFlight(run);
      case 'refresh':
        await ios.refresh(run);
      case 'wait':
        await ios.waitForProcessing(run);
      case 'retryUpload':
        await ios.upload(run, retryAfterVerification: true);
      case 'draft' || 'submit' || 'release' || 'distribute':
        await ios.storeAction(run, _iosAction);
      default:
        throw StateError('Bước release iOS không hỗ trợ: $_iosAction.');
    }
    // A Mac build host reports each change as a new copy of the run.
    return {'iosRun': iosRunToWire(_iosRun(runId, project))};
  }

  IosReleaseRun _iosRun(String runId, AppStoreProject project) {
    final run = _ios.history
        .where((entry) => entry.id == runId && entry.project.id == project.id)
        .firstOrNull;
    if (run == null) {
      throw StateError('Không thấy run $runId của ${project.name}.');
    }
    return run;
  }

  AppStoreProject _iosProjectFor(String projectId) {
    final project = home.appStoreProjects
        .where((entry) => entry.id == projectId)
        .firstOrNull;
    if (project == null) {
      throw StateError('Dự án không có trong mục App Store của máy tính.');
    }
    return project;
  }
}
