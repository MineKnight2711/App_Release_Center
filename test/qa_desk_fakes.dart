import 'dart:async';
import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/controllers/qa_workspace_controller.dart';
import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/models/scenario_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/appium_server_service.dart';
import 'package:app_management_center/app/modules/qa_desk/services/artifact_store.dart';
import 'package:app_management_center/app/modules/qa_desk/services/device_discovery_service.dart';
import 'package:app_management_center/app/modules/qa_desk/services/git_metadata_service.dart';
import 'package:app_management_center/app/modules/qa_desk/services/maestro_manager.dart';
import 'package:app_management_center/app/modules/qa_desk/services/mobile_device_service.dart';
import 'package:app_management_center/app/modules/qa_desk/services/qa_desk_host.dart';
import 'package:app_management_center/app/modules/qa_desk/services/run_history_store.dart';
import 'package:app_management_center/app/modules/qa_desk/services/safe_process_runner.dart';
import 'package:app_management_center/app/modules/qa_desk/services/scenario_catalog_store.dart';
import 'package:app_management_center/app/modules/qa_desk/services/source_discovery_service.dart';
import 'package:app_management_center/app/modules/qa_desk/services/source_registry.dart';
import 'package:flutter/foundation.dart';

/// Never touched: [FakeRunning.stop] is what the controller calls.
class _NoProcess implements Process {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRunning extends RunningProcess {
  FakeRunning(this._output, this._exit)
    : super(
        process: _NoProcess(),
        output: _output.stream,
        exitCode: _exit.future,
      );

  final StreamController<String> _output;
  final Completer<int> _exit;
  bool stopped = false;

  void emit(String line) => _output.add(line);

  void finish(int code) {
    _output.close();
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Future<void> stop() async {
    stopped = true;
    finish(-1);
  }
}

/// Plays a scripted exit code per suite; a suite without one runs until it is
/// stopped or [FakeRunning.finish]ed by the test.
class FakeRunner extends SafeProcessRunner {
  FakeRunner([Map<String, int>? exitCodes]) : exitCodes = exitCodes ?? {};

  final Map<String, int> exitCodes;
  final started = <String>[];
  final environments = <String, Map<String, String>>{};
  final processes = <String, FakeRunning>{};

  @override
  Future<RunningProcess> start({
    required QaSuite suite,
    required String workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    started.add(suite.id);
    environments[suite.id] = environment;
    final process = FakeRunning(StreamController<String>(), Completer<int>());
    processes[suite.id] = process;
    process.emit('output of ${suite.id}');
    final code = exitCodes[suite.id];
    if (code != null) {
      if (code != 0) process.emit('Expected: true  Actual: false');
      process.finish(code);
    }
    return process;
  }
}

/// Maestro and Java present, without looking at the machine.
class ReadyMaestro extends MaestroManager {
  ReadyMaestro({this.ready = true})
    : super(toolsDirectory: Directory('unused-maestro'));

  final bool ready;

  @override
  Future<MaestroStatus> status() async => MaestroStatus(
    installed: ready,
    javaVersion: 21,
    java: 'C:/java/bin/java.exe',
  );
}

class FixedGit extends GitMetadataService {
  const FixedGit();

  @override
  Future<GitMetadata> read(String workingDirectory) async =>
      const GitMetadata(branch: 'develop', commit: 'abc1234');
}

/// Finds the sources it was given by path; any other folder is not a
/// project. Stored sources are then kept as they are on start-up.
class MapDiscovery extends SourceDiscoveryService {
  const MapDiscovery(this.sources);

  final Map<String, QaSource> sources;

  @override
  Future<QaSource> discover(String rawPath) async =>
      sources[rawPath] ??
      (throw const SourceDiscoveryException('Không nhận ra loại dự án.'));
}

/// What AMC tells QA Desk, set by the test.
class FakeHost extends ChangeNotifier implements QaDeskHost {
  FakeHost({this.currentProjectPath, this.recentProjectPaths = const []});

  @override
  String? currentProjectPath;

  @override
  List<String> recentProjectPaths;

  final _busy = <String>[];

  @override
  Iterable<String> get busyProjectPaths => _busy;

  @override
  Listenable get changes => this;

  @override
  QaTeamContext? team;

  void setBusy(Iterable<String> paths) {
    _busy
      ..clear()
      ..addAll(paths);
    notifyListeners();
  }
}

/// Keeps the stored suites as they are instead of re-reading the folder.
class NoDiscovery extends SourceDiscoveryService {
  const NoDiscovery();

  @override
  Future<QaSource> discover(String rawPath) async =>
      throw const SourceDiscoveryException('not in tests');
}

class NoAppium extends AppiumServerService {
  int stops = 0;

  @override
  Future<bool> isInstalled() async => false;

  @override
  Future<void> stop() async {
    stops++;
    await super.stop();
  }
}

class FakeDevices extends DeviceDiscoveryService {
  FakeDevices([this.devices = const []]);

  final List<DeviceInfo> devices;

  @override
  Future<List<DeviceInfo>> discover() async => devices;
}

/// Artifacts that never reach the disk; widget tests run in fake async, where
/// real file IO does not complete.
class MemoryArtifacts extends ArtifactStore {
  const MemoryArtifacts();

  @override
  Future<String> saveLog(SuiteRun run) async => 'C:/qa/${run.runId}.log';

  @override
  Future<String> saveBytes(
    SuiteRun run,
    String fileName,
    Uint8List bytes,
  ) async => 'C:/qa/${run.runId}-$fileName';
}

/// Records screenshot requests instead of calling adb.
class FakeMobile extends MobileDeviceService {
  FakeMobile();

  final screenshots = <String>[];

  @override
  Future<Uint8List> captureScreenshot(String deviceId) async {
    screenshots.add(deviceId);
    return Uint8List.fromList(const [137, 80, 78, 71]);
  }
}

class MemoryCatalogs extends ScenarioCatalogStore {
  MemoryCatalogs([Map<String, SourceScenarioCatalog>? initial])
    : catalogs = initial ?? {};

  final Map<String, SourceScenarioCatalog> catalogs;

  @override
  Future<SourceScenarioCatalog> load(QaSource source) async =>
      catalogs[source.id] ??
      SourceScenarioCatalog(
        sourceId: source.id,
        environments: const [EnvironmentProfile(id: 'local', name: 'Local')],
      );

  @override
  Future<void> save(QaSource source, SourceScenarioCatalog catalog) async {
    catalogs[source.id] = catalog;
  }
}

const analyzeSuite = QaSuite(
  id: 'analyze',
  name: 'Flutter Analyze',
  executable: 'flutter',
  arguments: ['analyze'],
  tags: ['static'],
);

const unitSuite = QaSuite(
  id: 'unit',
  name: 'Unit tests',
  executable: 'flutter',
  arguments: ['test'],
  tags: ['smoke'],
);

const smokeSuite = QaSuite(
  id: 'smoke',
  name: 'Android smoke',
  executable: 'flutter',
  arguments: ['run', '-d', '{deviceId}'],
  requiresDevice: true,
  selected: false,
);

QaSource appSource({
  String path = r'C:\projects\fizahub_app',
  List<QaSuite> suites = const [analyzeSuite, unitSuite, smokeSuite],
  bool selected = true,
}) => QaSource(
  id: 'app',
  name: 'FizaHUB Flutter',
  path: path,
  type: SourceType.flutter,
  suites: suites,
  selected: selected,
  manifestBacked: true,
);

/// A workspace controller wired to fakes. Tests that check files pass a real
/// [ArtifactStore] rooted in their sandbox and a real [ScenarioCatalogStore].
QaWorkspaceController fakeController({
  required FakeRunner runner,
  List<QaSource>? sources,
  List<DeviceInfo> devices = const [],
  ArtifactStore artifacts = const MemoryArtifacts(),
  ScenarioCatalogStore? catalogs,
  RunHistoryStore? history,
  NoAppium? appium,
  MobileDeviceService? mobile,
  SourceDiscoveryService discovery = const NoDiscovery(),
}) => QaWorkspaceController(
  MemorySourceRegistry(sources ?? [appSource()]),
  discovery,
  runner,
  history ?? MemoryRunHistoryStore(),
  artifacts,
  const FixedGit(),
  FakeDevices(devices),
  mobile ?? FakeMobile(),
  appium ?? NoAppium(),
  catalogs ?? MemoryCatalogs(),
);
