import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/bundle_check_models.dart';
import '../services/android_device.dart';
import '../services/android_toolchain.dart';
import '../services/app_bundle_project_source.dart';
import '../services/bundle_check_service.dart';
import '../services/bundle_check_store.dart';
import '../services/bundle_inspector.dart';
import '../services/device_smoke_runner.dart';

enum BundleCheckStage { idle, checking, done, failed }

enum BundletoolState { unknown, missing, downloading, ready }

/// Owns the checker page: the run in progress, the report on screen, the
/// history beside it, and the bundletool jar.
///
/// A [ChangeNotifier] like the other modules: everything here belongs to the
/// open page and goes when it closes.
class BundleCheckController extends ChangeNotifier {
  BundleCheckController({BundleCheckService? service})
    : service =
          service ??
          BundleCheckService(
            store: BundleCheckStore(),
            projects: AppBundleProjectSource(),
          );

  final BundleCheckService service;

  BundleCheckStage stage = BundleCheckStage.idle;
  String progress = '';
  String? error;

  /// The run behind [report], when it was checked in this session. A report
  /// opened from history has no run: nothing to export or re-sign with.
  BundleCheckRun? run;
  BundleCheckReport? report;
  List<BundleCheckReport> history = const [];

  BundletoolState bundletool = BundletoolState.unknown;
  double downloadProgress = 0;
  String? bundletoolError;

  bool exporting = false;
  File? exportedApk;
  String? exportError;

  List<DeviceTarget> targets = const [];
  DeviceTarget? target;
  bool loadingTargets = false;
  String? targetsError;
  DeviceRunPreferences devicePreferences = const DeviceRunPreferences();
  bool deviceRunning = false;
  String? deviceError;

  /// Set when a physical device holds a copy that must be uninstalled first.
  bool needsUninstallConfirm = false;

  bool _disposed = false;
  bool _lastDetached = false;

  bool get busy =>
      stage == BundleCheckStage.checking || exporting || deviceRunning;

  Future<void>? _initialized;

  /// Loads history and looks for bundletool, once per controller.
  Future<void> init() => _initialized ??= _init();

  Future<void> _init() async {
    await _loadHistory();
    devicePreferences = await service.store.readDevicePreferences();
    final jar = await (await service.bundletool()).find();
    bundletool = jar == null ? BundletoolState.missing : BundletoolState.ready;
    _notify();
    await loadTargets();
  }

  /// Asks adb and the emulator which devices are there, keeping the last
  /// choice selected when it is still available.
  Future<void> loadTargets() async {
    if (loadingTargets) return;
    loadingTargets = true;
    targetsError = null;
    _notify();
    try {
      targets = await service.listTargets();
      final wanted = target?.key ?? devicePreferences.targetKey;
      // Without a remembered choice, an emulator comes first: installing on
      // someone's own phone is never the default.
      target =
          targets.where((t) => t.key == wanted).firstOrNull ??
          targets
              .where((t) => t.isEmulator && (t.device?.isReady ?? false))
              .firstOrNull ??
          targets.where((t) => t.avdName != null).firstOrNull ??
          targets.where((t) => t.device?.isReady ?? false).firstOrNull ??
          targets.firstOrNull;
    } on BundleToolException catch (e) {
      targets = const [];
      target = null;
      targetsError = e.message;
    } finally {
      loadingTargets = false;
    }
    _notify();
  }

  void selectTarget(DeviceTarget value) {
    target = value;
    needsUninstallConfirm = false;
    _saveDevicePreferences(devicePreferences.copyWith(targetKey: value.key));
  }

  void setWatchSeconds(int seconds) {
    _saveDevicePreferences(devicePreferences.copyWith(watchSeconds: seconds));
  }

  void setUninstallAfter(bool value) {
    _saveDevicePreferences(devicePreferences.copyWith(uninstallAfter: value));
  }

  void _saveDevicePreferences(DeviceRunPreferences value) {
    devicePreferences = value;
    _notify();
    service.store.saveDevicePreferences(value);
  }

  /// Installs the current bundle on [target], opens it and watches it.
  ///
  /// [allowUninstall] is the user's go-ahead to remove a conflicting copy
  /// from a physical device, which wipes that app's data there.
  Future<void> runOnDevice({bool allowUninstall = false}) async {
    final current = run;
    final device = target;
    if (current == null || device == null || busy) return;
    deviceRunning = true;
    deviceError = null;
    needsUninstallConfirm = false;
    progress = 'Chuẩn bị thiết bị';
    _notify();
    try {
      final (updated, outcome) = await service.runOnDevice(
        current,
        device,
        options: DeviceRunOptions(
          watchSeconds: devicePreferences.watchSeconds,
          uninstallAfter: devicePreferences.uninstallAfter,
          allowUninstall: allowUninstall,
        ),
        onProgress: (step) {
          progress = step;
          _notify();
        },
      );
      run = updated;
      report = updated.report;
      needsUninstallConfirm = outcome.needsUninstallConfirm;
      await _loadHistory();
    } on BundleToolException catch (e) {
      deviceError = e.message;
    } on FileSystemException catch (e) {
      deviceError = 'Lỗi file khi chạy thử: ${e.message}';
    } finally {
      deviceRunning = false;
    }
    _notify();
    // A switched-off AVD is now running; show it as such.
    if (device.avdName != null) await loadTargets();
  }

  Future<void> checkFile(
    String path, {
    BundleProjectCandidate? project,
    bool detachProject = false,
  }) async {
    if (busy) return;
    _lastDetached = detachProject;
    stage = BundleCheckStage.checking;
    error = null;
    deviceError = null;
    needsUninstallConfirm = false;
    exportedApk = null;
    exportError = null;
    progress = 'Bắt đầu';
    _notify();
    try {
      final result = await service.check(
        path,
        project: project,
        detachProject: detachProject,
        onProgress: (step) {
          progress = step;
          _notify();
        },
      );
      run = result;
      report = result.report;
      stage = BundleCheckStage.done;
      await _loadHistory();
    } on BundleInspectionException catch (e) {
      _fail(e.message);
    } on BundleToolException catch (e) {
      _fail(e.message);
    } on FileSystemException catch (e) {
      _fail('Không đọc được file: ${e.message}');
    }
    _notify();
  }

  /// Runs the current file again, optionally against another project.
  Future<void> recheck({
    BundleProjectCandidate? project,
    bool detachProject = false,
  }) async {
    final current = report;
    if (current == null) return;
    if (!File(current.sourcePath).existsSync()) {
      _fail('File ${current.sourcePath} không còn ở đó để kiểm lại.');
      _notify();
      return;
    }
    // With no explicit choice, keep whatever the last check was attached to
    // — including "no project" — rather than snapping back to the default.
    final keepDetached = project == null && _lastDetached && run != null;
    await checkFile(
      current.sourcePath,
      project: project ?? (detachProject ? null : run?.project),
      detachProject: detachProject || keepDetached,
    );
  }

  void showReport(BundleCheckReport value) {
    if (busy) return;
    needsUninstallConfirm = false;
    deviceError = null;
    report = value;
    run = run?.report.id == value.id ? run : null;
    stage = BundleCheckStage.done;
    error = null;
    exportedApk = null;
    exportError = null;
    _notify();
  }

  Future<EnvContractOverride> overrideForCurrent() async {
    final current = report;
    if (current == null) return const EnvContractOverride();
    return await service.store.overrideFor(current.packageName) ??
        const EnvContractOverride();
  }

  Future<void> saveOverride(EnvContractOverride value) async {
    final current = report;
    if (current == null) return;
    await service.store.saveOverride(current.packageName, value);
    await recheck();
  }

  Future<void> pinSigner() async {
    final current = report;
    if (current == null) return;
    await service.pinSigner(current);
    await recheck();
  }

  Future<void> downloadBundletool() async {
    if (bundletool == BundletoolState.downloading) return;
    bundletool = BundletoolState.downloading;
    bundletoolError = null;
    downloadProgress = 0;
    _notify();
    try {
      await (await service.bundletool()).download(
        onProgress: (received, total) {
          downloadProgress = total == 0 ? 0 : received / total;
          _notify();
        },
      );
      bundletool = BundletoolState.ready;
    } on BundleToolException catch (e) {
      bundletool = BundletoolState.missing;
      bundletoolError = e.message;
    } on FileSystemException catch (e) {
      bundletool = BundletoolState.missing;
      bundletoolError = 'Không ghi được file: ${e.message}';
    }
    _notify();
  }

  Future<void> exportUniversalApk() async {
    final current = run;
    if (current == null || busy) return;
    exporting = true;
    exportError = null;
    exportedApk = null;
    _notify();
    try {
      exportedApk = await service.exportUniversalApk(
        current,
        onProgress: (step) {
          progress = step;
          _notify();
        },
      );
    } on BundleToolException catch (e) {
      exportError = e.message;
    } on FileSystemException catch (e) {
      exportError = 'Không ghi được APK: ${e.message}';
    } finally {
      exporting = false;
    }
    _notify();
  }

  Future<String> jobDirectory() async {
    final current = report;
    if (current == null) return '';
    return (await service.store.jobDirectory(current.id)).path;
  }

  Future<void> _loadHistory() async {
    history = await service.store.history();
  }

  void _fail(String message) {
    stage = BundleCheckStage.failed;
    error = message;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
