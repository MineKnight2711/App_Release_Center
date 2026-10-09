import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../bundle_check/services/android_toolchain.dart';
import '../../bundle_check/services/bundle_check_store.dart';

import '../controllers/qa_workspace_controller.dart';
import 'account_vault.dart';
import 'app_installer.dart';
import 'appium_server_service.dart';
import 'artifact_store.dart';
import 'automation_runner.dart';
import 'device_discovery_service.dart';
import 'firestore_vault_backend.dart';
import 'git_metadata_service.dart';
import 'maestro_manager.dart';
import 'mobile_device_service.dart';
import 'qa_desk_host.dart';
import 'qa_desk_storage.dart';
import 'run_history_store.dart';
import 'safe_process_runner.dart';
import 'source_discovery_service.dart';
import 'source_registry.dart';
import 'vault_cipher.dart';

/// Holds the one QA workspace the whole app shares.
///
/// Mail Cleaner and the AAB checker build their controller per page. QA Desk
/// cannot: an integration suite runs for minutes, and Appium and the
/// weak-network proxy must keep serving while the user is back on the release
/// screen. So the controller belongs to the app. It is opened on first use
/// rather than at startup, which keeps AMC's launch cost unchanged.
class QaDeskRuntime {
  QaDeskRuntime._(
    this.storage,
    this.controller,
    this.importResult,
    this._history,
  ) {
    _exitListener = AppLifecycleListener(onExitRequested: _onExitRequested);
  }

  static Future<QaDeskRuntime>? _opening;

  /// The open runtime, or null while QA Desk has not been used this session.
  /// The shell's status chip listens here to appear once QA Desk is in use.
  static final currentNotifier = ValueNotifier<QaDeskRuntime?>(null);

  static QaDeskRuntime? get current => currentNotifier.value;

  /// What QA Desk knows about the rest of AMC; set by AMC at startup.
  static QaDeskHost host = const StandaloneQaDeskHost();

  static Future<QaDeskRuntime> open() =>
      _opening ??= _openFor(QaDeskStorage.forApp(), _appAutomation);

  /// Opens a runtime on [storage]; the tests point it at a sandbox and leave
  /// automation out unless they pass [automation].
  @visibleForTesting
  static Future<QaDeskRuntime> openFor(
    QaDeskStorage storage, {
    AppiumServerService? appium,
    Future<AutomationParts> Function(QaDeskStorage storage)? automation,
  }) =>
      _opening ??= _openFor(Future.value(storage), automation, appium: appium);

  /// The vault, Maestro and installer for the real app: the team's vault when
  /// AMC is signed in to a team, this machine's otherwise.
  static Future<AutomationParts> _appAutomation(QaDeskStorage storage) async {
    final maestro = await MaestroManager.forApp();
    final team = host.team;
    const secrets = SecureSecretStore();
    final AccountVault vault = team == null
        ? LocalAccountVault(store: secrets)
        : TeamAccountVault(
            backend: FirestoreVaultBackend(teamId: team.teamId),
            store: secrets,
            team: team,
          );
    final installer = AppInstaller(
      recordFile: File(p.join(storage.root, 'installed_builds.json')),
      bundletoolJar: () async {
        final store = await BundleCheckStore.forApp();
        return BundletoolManager(
          toolsDirectory: await store.toolsDirectory,
        ).find();
      },
    );
    return AutomationParts(
      maestro: maestro,
      vault: vault,
      installer: installer,
    );
  }

  static Future<QaDeskRuntime> _openFor(
    Future<QaDeskStorage> resolveStorage,
    Future<AutomationParts> Function(QaDeskStorage storage)? automation, {
    AppiumServerService? appium,
  }) async {
    try {
      final storage = await resolveStorage;
      // Before any store touches the folder: the import only runs into an
      // empty one.
      final imported = await storage.importLegacyIfNeeded();
      final history = SqliteRunHistoryStore(databasePath: storage.databasePath);
      final parts = automation == null ? null : await automation(storage);
      AutomationRunner? runner;
      final processRunner = SafeProcessRunner(
        managedTool: (name) => name == 'maestro' ? runner?.command : null,
      );
      final controller = QaWorkspaceController(
        FileSourceRegistry(path: storage.sourcesPath),
        const SourceDiscoveryService(),
        processRunner,
        history,
        ArtifactStore(rootOverride: storage.root),
        const GitMetadataService(),
        const DeviceDiscoveryService(),
        const MobileDeviceService(),
        appium,
      );
      // Read through [host] on every call, so a host set after this runtime
      // opened still counts.
      controller.busyProjectPaths = () => host.busyProjectPaths;
      if (parts != null) {
        runner = AutomationRunner(
          vault: parts.vault,
          maestro: parts.maestro,
          installer: parts.installer,
          processRunner: processRunner,
        );
        controller.attachAutomation(runner);
        // Firestore may be slow or offline; QA Desk opens without waiting.
        unawaited(parts.vault.load());
      }
      try {
        await controller.initialize();
      } catch (_) {
        await history.close();
        rethrow;
      }
      final runtime = QaDeskRuntime._(storage, controller, imported, history);
      currentNotifier.value = runtime;
      return runtime;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  final QaDeskStorage storage;
  final QaWorkspaceController controller;
  final QaDeskImportResult importResult;
  final SqliteRunHistoryStore _history;
  late final AppLifecycleListener _exitListener;
  bool _importNoticeShown = false;

  /// The batch whose result the user has seen in QA Desk; the shell's chip
  /// stays up for any later one.
  final seenBatch = ValueNotifier<String?>(null);

  /// Marks the finished run as seen. A run still going is not.
  void acknowledgeResult() {
    if (controller.isRunning || controller.runs.isEmpty) return;
    seenBatch.value = controller.runs.first.batchId;
  }

  /// Hands out the import outcome once per session, for the page to announce.
  QaDeskImportResult? takeImportNotice() {
    if (_importNoticeShown ||
        importResult.outcome == QaDeskImportOutcome.skipped) {
      return null;
    }
    _importNoticeShown = true;
    return importResult;
  }

  Future<AppExitResponse> _onExitRequested() async {
    await controller.shutdown();
    return AppExitResponse.exit;
  }

  /// Stops everything and forgets this runtime, for tests.
  @visibleForTesting
  Future<void> close() async {
    _exitListener.dispose();
    await controller.shutdown();
    controller.dispose();
    await _history.close();
    currentNotifier.value = null;
    _opening = null;
  }
}

/// What automation needs from the machine, built once with the runtime.
class AutomationParts {
  const AutomationParts({
    required this.maestro,
    required this.vault,
    this.installer,
  });

  final MaestroManager maestro;
  final AccountVault vault;
  final AppInstaller? installer;
}
