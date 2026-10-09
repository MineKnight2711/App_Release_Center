import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../shared/device_run_lock.dart';
import '../models/automation_models.dart';
import '../models/preflight.dart';
import '../models/qa_models.dart';
import '../models/report_models.dart';
import '../models/scenario_models.dart';
import '../services/appium_server_service.dart';
import '../services/artifact_store.dart';
import '../services/automation_runner.dart';
import '../services/device_discovery_service.dart';
import '../services/git_metadata_service.dart';
import '../services/issue_report_service.dart';
import '../services/mobile_device_service.dart';
import '../services/run_history_store.dart';
import '../services/report_analytics_service.dart';
import '../services/report_export_service.dart';
import '../services/scenario_catalog_store.dart';
import '../services/secret_redactor.dart';
import '../services/safe_process_runner.dart';
import '../services/source_discovery_service.dart';
import '../services/source_registry.dart';
import 'network_test_controller.dart';

class QaWorkspaceController extends ChangeNotifier {
  final network = NetworkTestController();
  QaWorkspaceController(
    this._registry, [
    this._discovery = const SourceDiscoveryService(),
    this._processRunner = const SafeProcessRunner(),
    RunHistoryStore? historyStore,
    this._artifactStore = const ArtifactStore(),
    this._gitMetadataService = const GitMetadataService(),
    this._deviceDiscoveryService = const DeviceDiscoveryService(),
    this._mobileDeviceService = const MobileDeviceService(),
    AppiumServerService? appiumServerService,
    this._scenarioCatalogStore = const ScenarioCatalogStore(),
    this._reportAnalyticsService = const ReportAnalyticsService(),
    this._reportExportService = const ReportExportService(),
  ]) : _historyStore = historyStore ?? MemoryRunHistoryStore(),
       _appiumServerService = appiumServerService ?? AppiumServerService();

  final SourceRegistry _registry;
  final SourceDiscoveryService _discovery;
  final SafeProcessRunner _processRunner;
  final RunHistoryStore _historyStore;
  final ArtifactStore _artifactStore;
  final GitMetadataService _gitMetadataService;
  final DeviceDiscoveryService _deviceDiscoveryService;
  final MobileDeviceService _mobileDeviceService;
  final AppiumServerService _appiumServerService;
  final ScenarioCatalogStore _scenarioCatalogStore;
  final ReportAnalyticsService _reportAnalyticsService;
  final ReportExportService _reportExportService;

  final List<QaSource> _sources = [];
  final List<SuiteRun> _runs = [];
  final List<RunBatchSummary> _historyBatches = [];
  final List<HistoricalSuiteRun> _historyRuns = [];
  final List<DeviceInfo> _devices = [];
  final List<HistoricalSuiteRun> _reportRuns = [];
  final Map<String, RunningProcess> _activeProcesses = {};
  final Map<String, SourceScenarioCatalog> _catalogs = {};
  final Map<String, String> _selectedEnvironments = {};
  final Map<String, Map<String, String>> _sessionSecrets = {};
  final Map<String, String> _catalogErrors = {};

  bool _isInitializing = true;
  bool _isRunning = false;
  bool _isLoadingHistory = false;
  bool _isDiscoveringDevices = false;
  bool _isLoadingReports = false;
  String? _selectedBatchId;
  String? _deviceError;
  String? _selectedDeviceId;
  AppiumStatus _appiumStatus = AppiumStatus.stopped;
  String? _appiumError;
  final List<String> _appiumLogs = [];
  final int _appiumPort = 4723;

  List<QaSource> get sources => List.unmodifiable(_sources);
  List<SuiteRun> get runs => List.unmodifiable(_runs);
  List<RunBatchSummary> get historyBatches =>
      List.unmodifiable(_historyBatches);
  List<HistoricalSuiteRun> get historyRuns => List.unmodifiable(_historyRuns);
  List<DeviceInfo> get devices => List.unmodifiable(_devices);
  List<HistoricalSuiteRun> get reportRuns => List.unmodifiable(_reportRuns);
  bool get isInitializing => _isInitializing;
  bool get isRunning => _isRunning;
  bool get isLoadingHistory => _isLoadingHistory;
  bool get isDiscoveringDevices => _isDiscoveringDevices;
  bool get isLoadingReports => _isLoadingReports;
  String? get selectedBatchId => _selectedBatchId;
  String? get deviceError => _deviceError;
  String? get selectedDeviceId => _selectedDeviceId;
  DeviceInfo? get selectedDevice {
    for (final device in _devices) {
      if (device.id == _selectedDeviceId) return device;
    }
    return null;
  }

  AppiumStatus get appiumStatus => _appiumStatus;
  String? get appiumError => _appiumError;
  List<String> get appiumLogs => List.unmodifiable(_appiumLogs);
  int get appiumPort => _appiumPort;
  Map<String, String> get catalogErrors => Map.unmodifiable(_catalogErrors);
  ReportSnapshot get reportSnapshot =>
      _reportAnalyticsService.build(_reportRuns);
  int get selectedSourceCount =>
      _sources.where((source) => source.selected).length;
  int get selectedSuiteCount => _sources
      .where((source) => source.selected)
      .expand((source) => source.suites)
      .where((suite) => suite.selected)
      .length;

  /// Runs QA Desk operates itself; null until the runtime wires the vault
  /// and Maestro in, which tests may leave out.
  AutomationRunner? automation;

  /// Wires [runner] in; the vault's changes then rebuild whatever listens
  /// here, since they change what a run would do.
  void attachAutomation(AutomationRunner runner) {
    automation?.vault.removeListener(notifyListeners);
    automation = runner;
    runner.vault.addListener(notifyListeners);
  }

  String? _appEnvironment;

  /// Automated scenarios ticked for the next run.
  int get selectedAutomationCount => _sources.fold(
    0,
    (sum, source) => sum + _selectedAutomated(source).length,
  );

  /// Everything the run button would start.
  int get selectedRunCount => selectedSuiteCount + selectedAutomationCount;

  /// Environment names the apps of all sources declare, staging first.
  List<String> get appEnvironments {
    final names = <String>{
      for (final source in _sources)
        for (final app in source.apps)
          for (final environment in app.environments) environment.name,
    }.toList();
    int rank(String name) => switch (name.toLowerCase()) {
      'staging' => 0,
      'production' || 'prod' => 2,
      _ => 1,
    };
    names.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank == 0 ? a.compareTo(b) : byRank;
    });
    return names;
  }

  /// The environment automated scenarios run against: chosen once for the
  /// run, staging unless the user picks otherwise.
  String get appEnvironment {
    final names = appEnvironments;
    final chosen = _appEnvironment;
    if (chosen != null && names.contains(chosen)) return chosen;
    return names.isEmpty ? 'staging' : names.first;
  }

  void selectAppEnvironment(String name) {
    _appEnvironment = name;
    notifyListeners();
  }

  /// Whether [name] is a production environment in any app that declares it.
  bool isProductionEnvironment(String name) => _sources.any(
    (source) =>
        source.apps.any((app) => app.environment(name)?.isProduction ?? false),
  );

  /// The automated scenarios of [source], from its catalog.
  List<TestScenario> automatedScenarios(QaSource source) => [
    for (final scenario
        in _catalogs[source.id]?.scenarios ?? const <TestScenario>[])
      if (scenario.isAutomated) scenario,
  ];

  List<TestScenario> _selectedAutomated(QaSource source) => [
    for (final scenario in automatedScenarios(source))
      if (scenario.enabled && source.automationSelection.contains(scenario.id))
        scenario,
  ];

  bool isAutomationSelected(QaSource source, TestScenario scenario) =>
      source.automationSelection.contains(scenario.id);

  Future<void> setAutomationSelected(
    String sourceId,
    String scenarioId,
    bool selected,
  ) async {
    final index = _sources.indexWhere((source) => source.id == sourceId);
    if (index < 0) return;
    final source = _sources[index];
    final ids = {...source.automationSelection};
    selected ? ids.add(scenarioId) : ids.remove(scenarioId);
    _sources[index] = source.copyWith(automationSelection: ids.toList());
    await _save();
    notifyListeners();
  }

  /// Checks Maestro and Java again, after installing either.
  Future<void> refreshAutomationStatus() async {
    await automation?.refreshStatus();
    notifyListeners();
  }

  Future<void> initialize() async {
    await _historyStore.initialize();
    // A batch still marked running is from a session that ended mid-run.
    await _historyStore.recoverInterruptedBatches();
    final stored = await _registry.load();
    for (final source in stored) {
      try {
        final refreshed = await _discovery.discover(source.path);
        final selections = {
          for (final suite in source.suites) suite.id: suite.selected,
        };
        _sources.add(
          refreshed.copyWith(
            selected: source.selected,
            automationSelection: source.automationSelection,
            suites: refreshed.suites
                .map(
                  (suite) => suite.copyWith(
                    selected: selections[suite.id] ?? suite.selected,
                  ),
                )
                .toList(),
          ),
        );
      } on Object {
        _sources.add(source);
      }
    }
    await Future.wait(_sources.map(_loadCatalog));
    await refreshHistory(notify: false);
    await refreshReports(notify: false);
    _appiumStatus = await _appiumServerService.isInstalled()
        ? AppiumStatus.stopped
        : AppiumStatus.unavailable;
    await automation?.refreshStatus();
    _isInitializing = false;
    notifyListeners();
  }

  Future<void> refreshReports({bool notify = true}) async {
    _isLoadingReports = true;
    if (notify) notifyListeners();
    _reportRuns
      ..clear()
      ..addAll(await _historyStore.listRecentSuiteRuns());
    _isLoadingReports = false;
    if (notify) notifyListeners();
  }

  List<BatchSuiteComparison> compareBatches(
    String beforeBatchId,
    String afterBatchId,
  ) =>
      _reportAnalyticsService.compare(beforeBatchId, afterBatchId, _reportRuns);

  Future<String> readHistoricalLog(HistoricalSuiteRun run) =>
      _reportExportService.readLog(run.logPath);

  Future<IssueReport> currentIssueReport() {
    final current = List<SuiteRun>.of(_runs);
    final logs = {for (final run in current) run.runId: run.logs.join('\n')};
    return const IssueReportService().build(
      current.map((run) => run.toHistory()).toList(),
      (run) async => logs[run.runId] ?? '',
    );
  }

  Future<IssueReport> batchIssueReport(String batchId) async =>
      const IssueReportService().build(
        await _historyStore.listSuiteRuns(batchId),
        readHistoricalLog,
      );

  Future<String?> exportBatch(
    String batchId,
    ReportFormat format,
    String outputPath,
  ) async {
    RunBatchSummary? batch;
    for (final item in _historyBatches) {
      if (item.id == batchId) batch = item;
    }
    if (batch == null) return 'Không tìm thấy lượt chạy.';
    try {
      final runs = await _historyStore.listSuiteRuns(batchId);
      await _reportExportService.export(
        batch: batch,
        runs: runs,
        format: format,
        outputPath: outputPath,
      );
      return null;
    } on Object catch (error) {
      return 'Không xuất được báo cáo: $error';
    }
  }

  Future<String?> rerunFailures(String batchId) async {
    if (_isRunning) return 'Một lượt test khác đang chạy.';
    final failedRuns = await _historyStore
        .listSuiteRuns(batchId)
        .then(
          (runs) =>
              runs.where((run) => run.status == RunStatus.failed).toList(),
        );
    if (failedRuns.isEmpty) return 'Lượt này không có suite lỗi.';
    final failedKeys = {
      for (final run in failedRuns) '${run.sourceId}:${run.suiteId}',
    };
    final availableKeys = <String>{};
    final snapshot = [..._sources];
    for (var index = 0; index < _sources.length; index++) {
      final source = _sources[index];
      final suites = source.suites.map((suite) {
        final selected = failedKeys.contains('${source.id}:${suite.id}');
        if (selected) availableKeys.add('${source.id}:${suite.id}');
        return suite.copyWith(selected: selected);
      }).toList();
      // Failed automated scenarios come back too, under their own ids.
      final automated = [
        for (final scenario in automatedScenarios(source))
          if (failedKeys.contains(
            '${source.id}:$_automationPrefix${scenario.id}',
          ))
            scenario.id,
      ];
      for (final id in automated) {
        availableKeys.add('${source.id}:$_automationPrefix$id');
      }
      _sources[index] = source.copyWith(
        selected: suites.any((suite) => suite.selected),
        suites: suites,
        automationSelection: automated,
      );
    }
    if (availableKeys.isEmpty) {
      _sources
        ..clear()
        ..addAll(snapshot);
      return 'Các suite lỗi không còn trong danh sách nguồn.';
    }
    notifyListeners();
    try {
      await runSelected();
    } finally {
      _sources
        ..clear()
        ..addAll(snapshot);
      notifyListeners();
    }
    final missing = failedKeys.length - availableKeys.length;
    return missing == 0
        ? null
        : 'Đã bỏ qua $missing suite không còn trong nguồn.';
  }

  SourceScenarioCatalog? catalogFor(String sourceId) => _catalogs[sourceId];

  String? selectedEnvironmentId(String sourceId) =>
      _selectedEnvironments[sourceId];

  void selectEnvironment(String sourceId, String environmentId) {
    final catalog = _catalogs[sourceId];
    if (catalog == null ||
        !catalog.environments.any((item) => item.id == environmentId)) {
      return;
    }
    _selectedEnvironments[sourceId] = environmentId;
    notifyListeners();
  }

  bool sessionSecretIsSet(String sourceId, String environmentId, String key) =>
      _sessionSecrets['$sourceId:$environmentId']?[key]?.isNotEmpty == true;

  void setSessionSecrets(
    String sourceId,
    String environmentId,
    Map<String, String> values,
  ) {
    _sessionSecrets['$sourceId:$environmentId'] = Map.of(values);
    notifyListeners();
  }

  /// Sets the secrets given non-empty values and keeps the rest, so a form
  /// that cannot show stored secrets back does not wipe them when left blank.
  void updateSessionSecrets(
    String sourceId,
    String environmentId,
    Map<String, String> values,
  ) {
    final key = '$sourceId:$environmentId';
    _sessionSecrets[key] = {
      ...?_sessionSecrets[key],
      for (final entry in values.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
    notifyListeners();
  }

  Future<String?> saveScenario(String sourceId, TestScenario scenario) async {
    final source = _sourceById(sourceId);
    final catalog = _catalogs[sourceId];
    if (source == null || catalog == null) return 'Không tìm thấy nguồn.';
    final spec = scenario.automation;
    if (scenario.title.trim().isEmpty) return 'Cần tên test case.';
    if (spec == null && scenario.suiteId.trim().isEmpty) {
      return 'Cần suite liên kết.';
    }
    if (spec != null) {
      if (spec.app.isEmpty) return 'Chọn app cho test case tự thao tác.';
      if (spec.role.trim().isEmpty) return 'Cần vai trò tài khoản demo.';
      if (spec.steps.isEmpty) return 'Thêm ít nhất một bước.';
      final runner = automation;
      if (runner == null) return 'QA Desk chưa sẵn sàng tự thao tác.';
      try {
        final flow = await runner.writeFlow(source, scenario);
        scenario = scenario.copyWith(automation: spec.copyWith(flow: flow));
      } on Object catch (error) {
        return 'Không ghi được flow: $error';
      }
    }
    final scenarios = [...catalog.scenarios];
    final index = scenarios.indexWhere((item) => item.id == scenario.id);
    if (index < 0) {
      scenarios.add(scenario);
    } else {
      scenarios[index] = scenario;
    }
    final updated = catalog.copyWith(scenarios: scenarios);
    await _scenarioCatalogStore.save(source, updated);
    _catalogs[sourceId] = updated;
    notifyListeners();
    return null;
  }

  Future<void> deleteScenario(String sourceId, String scenarioId) async {
    final source = _sourceById(sourceId);
    final catalog = _catalogs[sourceId];
    if (source == null || catalog == null) return;
    final updated = catalog.copyWith(
      scenarios: catalog.scenarios
          .where((item) => item.id != scenarioId)
          .toList(),
    );
    await _scenarioCatalogStore.save(source, updated);
    _catalogs[sourceId] = updated;
    notifyListeners();
  }

  Future<String?> saveEnvironment(
    String sourceId,
    EnvironmentProfile environment,
  ) async {
    final source = _sourceById(sourceId);
    final catalog = _catalogs[sourceId];
    if (source == null || catalog == null) return 'Không tìm thấy nguồn.';
    if (environment.name.trim().isEmpty) return 'Cần tên môi trường.';
    final invalidKey = [
      ...environment.variables.keys,
      ...environment.secretKeys,
    ].where((key) => !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key));
    if (invalidKey.isNotEmpty) {
      return 'Tên biến không hợp lệ: ${invalidKey.first}';
    }
    final persistedSecret = environment.secretKeys.where(
      environment.variables.containsKey,
    );
    if (persistedSecret.isNotEmpty) {
      return '${persistedSecret.first} là secret, không được đặt trong phần Biến.';
    }
    final environments = [...catalog.environments];
    final index = environments.indexWhere((item) => item.id == environment.id);
    if (index < 0) {
      environments.add(environment);
    } else {
      environments[index] = environment;
    }
    final updated = catalog.copyWith(environments: environments);
    await _scenarioCatalogStore.save(source, updated);
    _catalogs[sourceId] = updated;
    _selectedEnvironments.putIfAbsent(sourceId, () => environment.id);
    notifyListeners();
    return null;
  }

  Future<void> deleteEnvironment(String sourceId, String environmentId) async {
    final source = _sourceById(sourceId);
    final catalog = _catalogs[sourceId];
    if (source == null || catalog == null || catalog.environments.length <= 1) {
      return;
    }
    final environments = catalog.environments
        .where((item) => item.id != environmentId)
        .toList();
    final updated = catalog.copyWith(environments: environments);
    await _scenarioCatalogStore.save(source, updated);
    _catalogs[sourceId] = updated;
    if (_selectedEnvironments[sourceId] == environmentId) {
      _selectedEnvironments[sourceId] = environments.first.id;
    }
    _sessionSecrets.remove('$sourceId:$environmentId');
    notifyListeners();
  }

  Future<String?> importCatalog(String sourceId, String inputPath) async {
    final source = _sourceById(sourceId);
    if (source == null) return 'Không tìm thấy nguồn.';
    try {
      final catalog = await _scenarioCatalogStore.importFrom(source, inputPath);
      _catalogs[sourceId] = catalog;
      _selectedEnvironments[sourceId] = catalog.environments.isEmpty
          ? ''
          : catalog.environments.first.id;
      notifyListeners();
      return null;
    } on ScenarioCatalogException catch (error) {
      return error.message;
    }
  }

  Future<String?> exportCatalog(String sourceId, String outputPath) async {
    final catalog = _catalogs[sourceId];
    if (catalog == null) return 'Không tìm thấy catalog.';
    try {
      await _scenarioCatalogStore.exportTo(catalog, outputPath);
      return null;
    } on Object catch (error) {
      return 'Không xuất được catalog: $error';
    }
  }

  /// Runs one automated scenario now, leaving the saved selection as it was.
  Future<void> runAutomation(String sourceId, String scenarioId) async {
    if (_isRunning) return;
    final snapshot = [..._sources];
    for (var index = 0; index < _sources.length; index++) {
      final source = _sources[index];
      _sources[index] = source.copyWith(
        selected: false,
        automationSelection: source.id == sourceId ? [scenarioId] : const [],
      );
    }
    notifyListeners();
    try {
      await runSelected();
    } finally {
      _sources
        ..clear()
        ..addAll(snapshot);
      notifyListeners();
    }
  }

  /// Logs [account] in on its own, from the vault sheet.
  Future<LoginCheckResult> checkAccountLogin(
    String sourceId,
    String appId,
    DemoAccount account,
  ) async {
    final runner = automation;
    final source = _sourceById(sourceId);
    final app = source?.app(appId);
    if (runner == null || source == null || app == null) {
      return const LoginCheckResult(
        ok: false,
        message: 'Không tìm thấy app trong project.yaml.',
      );
    }
    final device = selectedDevice;
    final folder = Directory(
      p.join(
        Directory.systemTemp.path,
        'qa_desk_login_check',
        '${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    Future<LoginCheckResult> check() => runner.checkLogin(
      source: source,
      app: app,
      account: account,
      device: device,
      outputDirectory: folder,
      log: (_) {},
    );
    return app.platform == QaAppPlatform.android
        ? DeviceRunLock.run(check)
        : check();
  }

  /// Why [scenario] cannot run on its own right now, or null when it can.
  String? automationBlocker(String sourceId, TestScenario scenario) {
    final source = _sourceById(sourceId);
    final runner = automation;
    if (source == null) return 'Không tìm thấy nguồn.';
    if (runner == null) return 'QA Desk chưa sẵn sàng tự thao tác.';
    for (final problem in runner.problems(source, scenario, appEnvironment)) {
      if (problem.blocking) return problem.message;
    }
    return null;
  }

  Future<void> runScenario(String sourceId, String scenarioId) async {
    if (_isRunning) return;
    final catalog = _catalogs[sourceId];
    if (catalog == null) return;
    final scenario = catalog.scenarios.firstWhere(
      (item) => item.id == scenarioId,
    );
    if (!scenario.enabled) return;
    if (scenario.isAutomated) return runAutomation(sourceId, scenarioId);
    final snapshot = [..._sources];
    for (var index = 0; index < _sources.length; index++) {
      final source = _sources[index];
      _sources[index] = source.copyWith(
        selected: source.id == sourceId,
        suites: source.suites
            .map(
              (suite) => suite.copyWith(selected: suite.id == scenario.suiteId),
            )
            .toList(),
        automationSelection: const [],
      );
    }
    notifyListeners();
    try {
      await runSelected();
    } finally {
      _sources
        ..clear()
        ..addAll(snapshot);
      notifyListeners();
    }
  }

  Future<void> refreshHistory({bool notify = true}) async {
    _isLoadingHistory = true;
    if (notify) notifyListeners();
    _historyBatches
      ..clear()
      ..addAll(await _historyStore.listBatches());
    final selectedId = _selectedBatchId;
    if (selectedId != null &&
        !_historyBatches.any((batch) => batch.id == selectedId)) {
      _selectedBatchId = null;
      _historyRuns.clear();
    }
    _isLoadingHistory = false;
    if (notify) notifyListeners();
  }

  Future<void> selectHistoryBatch(String batchId) async {
    _selectedBatchId = batchId;
    _isLoadingHistory = true;
    notifyListeners();
    _historyRuns
      ..clear()
      ..addAll(await _historyStore.listSuiteRuns(batchId));
    _isLoadingHistory = false;
    notifyListeners();
  }

  Future<void> refreshDevices() async {
    if (_isDiscoveringDevices) return;
    _isDiscoveringDevices = true;
    _deviceError = null;
    notifyListeners();
    try {
      final discovered = await _deviceDiscoveryService.discover();
      _devices
        ..clear()
        ..addAll(discovered);
      if (!_devices.any((device) => device.id == _selectedDeviceId)) {
        _selectedDeviceId = _devices.isEmpty ? null : _devices.first.id;
      }
    } on Object catch (error) {
      _deviceError = 'Không thể đọc danh sách thiết bị: $error';
    } finally {
      _isDiscoveringDevices = false;
      notifyListeners();
    }
  }

  void selectDevice(String deviceId) {
    if (_devices.any((device) => device.id == deviceId)) {
      _selectedDeviceId = deviceId;
      notifyListeners();
    }
  }

  Future<void> startAppium() async {
    if (_appiumStatus == AppiumStatus.starting ||
        _appiumStatus == AppiumStatus.running) {
      return;
    }
    _appiumStatus = AppiumStatus.starting;
    _appiumError = null;
    notifyListeners();
    final workingDirectory = _sources.isEmpty
        ? Directory.current.path
        : _sources.first.path;
    final error = await _appiumServerService.start(
      port: _appiumPort,
      workingDirectory: workingDirectory,
      onLog: _onAppiumLog,
    );
    if (error == null) {
      _appiumStatus = AppiumStatus.running;
    } else {
      _appiumStatus = error.contains('PATH')
          ? AppiumStatus.unavailable
          : AppiumStatus.error;
      _appiumError = error;
    }
    notifyListeners();
  }

  Future<void> stopAppium() async {
    await _appiumServerService.stop();
    _appiumStatus = await _appiumServerService.isInstalled()
        ? AppiumStatus.stopped
        : AppiumStatus.unavailable;
    notifyListeners();
  }

  void _onAppiumLog(String line) {
    _appiumLogs.add(line);
    if (_appiumLogs.length > 500) _appiumLogs.removeAt(0);
    if (line.startsWith('Appium exited')) {
      _appiumStatus = AppiumStatus.error;
      _appiumError = line;
    }
    notifyListeners();
  }

  Future<String?> addSource(String path) async {
    try {
      final discovered = await _discovery.discover(path);
      final alreadyAdded = _sources.any(
        (source) => source.path.toLowerCase() == discovered.path.toLowerCase(),
      );
      if (alreadyAdded) return 'Nguồn này đã có trong danh sách.';

      var source = discovered;
      if (_sources.any((item) => item.id == source.id)) {
        source = QaSource(
          id: '${source.id}-${source.path.hashCode.abs()}',
          name: source.name,
          path: source.path,
          type: source.type,
          suites: source.suites,
          manifestBacked: source.manifestBacked,
          apps: source.apps,
        );
      }
      _sources.add(source);
      await _loadCatalog(source);
      await _save();
      notifyListeners();
      return null;
    } on SourceDiscoveryException catch (error) {
      return error.message;
    } on Object catch (error) {
      return 'Không thêm được nguồn: $error';
    }
  }

  Future<void> removeSource(String sourceId) async {
    _sources.removeWhere((source) => source.id == sourceId);
    _catalogs.remove(sourceId);
    _selectedEnvironments.remove(sourceId);
    _catalogErrors.remove(sourceId);
    _sessionSecrets.removeWhere((key, _) => key.startsWith('$sourceId:'));
    await _save();
    notifyListeners();
  }

  /// Whether [suite] of [source] is part of the next run: a suite only runs
  /// while its source is selected too.
  bool isSuiteSelected(QaSource source, QaSuite suite) =>
      source.selected && suite.selected;

  /// The parent checkbox of the suite tree: ticks or clears every suite of
  /// the source.
  Future<void> setSourceSelected(String sourceId, bool selected) async {
    final index = _sources.indexWhere((source) => source.id == sourceId);
    if (index < 0) return;
    final source = _sources[index];
    _sources[index] = source.copyWith(
      selected: selected,
      suites: source.suites
          .map((suite) => suite.copyWith(selected: selected))
          .toList(),
      automationSelection: selected
          ? [
              for (final scenario in automatedScenarios(source))
                if (scenario.enabled) scenario.id,
            ]
          : const [],
    );
    await _save();
    notifyListeners();
  }

  /// Ticks or clears one suite in the suite tree.
  ///
  /// Ticking a suite in an unselected source selects that source with this
  /// suite alone, rather than reviving whatever its other suites were last
  /// set to; clearing the last ticked suite clears the source.
  Future<void> setSuiteSelected(
    String sourceId,
    String suiteId,
    bool selected,
  ) async {
    final index = _sources.indexWhere((source) => source.id == sourceId);
    if (index < 0) return;
    final source = _sources[index];
    final suites = source.suites.map((suite) {
      if (suite.id == suiteId) return suite.copyWith(selected: selected);
      return source.selected ? suite : suite.copyWith(selected: false);
    }).toList();
    _sources[index] = source.copyWith(
      selected: suites.any((suite) => suite.selected),
      suites: suites,
    );
    await _save();
    notifyListeners();
  }

  /// Project folders the rest of AMC is running something in; the runtime
  /// wires this to the host.
  Iterable<String> Function() busyProjectPaths = _nothingBusy;

  static Iterable<String> _nothingBusy() => const [];

  /// What would make the current selection fail or mislead, checked before
  /// the run instead of surfacing as a failed suite after it.
  List<PreflightIssue> preflight() {
    final selected = [
      for (final source in _sources.where((source) => source.selected))
        for (final suite in source.suites.where((suite) => suite.selected))
          (source: source, suite: suite),
    ];
    final automated = [
      for (final source in _sources)
        for (final scenario in _selectedAutomated(source))
          (source: source, scenario: scenario),
    ];
    if (selected.isEmpty && automated.isEmpty) {
      return const [
        PreflightIssue(
          kind: PreflightKind.noSuites,
          message: 'Chưa chọn suite nào.',
        ),
      ];
    }

    final issues = <PreflightIssue>[];
    final device = selectedDevice;
    final needDevice =
        selected
            .where(
              (item) =>
                  item.suite.requiresDevice ||
                  item.suite.requiresPhysicalDevice,
            )
            .length +
        automated
            .where(
              (item) =>
                  item.source.app(item.scenario.automation!.app)?.platform ==
                  QaAppPlatform.android,
            )
            .length;
    if (needDevice > 0 && device == null) {
      issues.add(
        PreflightIssue(
          kind: PreflightKind.deviceMissing,
          message: '$needDevice suite cần thiết bị nhưng chưa chọn thiết bị.',
        ),
      );
    }
    if (device != null && !device.isPhysical) {
      final physical = selected
          .where((item) => item.suite.requiresPhysicalDevice)
          .toList();
      if (physical.isNotEmpty) {
        issues.add(
          PreflightIssue(
            kind: PreflightKind.physicalDeviceRequired,
            message:
                '${physical.first.suite.name} cần điện thoại thật; '
                '${device.name} là máy ảo.',
          ),
        );
      }
    }
    if (_appiumStatus == AppiumStatus.unavailable &&
        selected.any((item) => item.suite.requiresAppium)) {
      issues.add(
        const PreflightIssue(
          kind: PreflightKind.appiumMissing,
          message:
              'Không tìm thấy Appium trong PATH. Cài bằng: '
              'npm install -g appium',
        ),
      );
    }
    for (final source in {for (final item in selected) item.source}) {
      final profile = _environmentProfileFor(source.id);
      if (profile == null) continue;
      final missing = profile.secretKeys
          .where((key) => !sessionSecretIsSet(source.id, profile.id, key))
          .toList();
      if (missing.isEmpty) continue;
      issues.add(
        PreflightIssue(
          kind: PreflightKind.secretsMissing,
          message:
              'Môi trường ${profile.name} của ${source.name} thiếu secret: '
              '${missing.join(', ')}.',
          sourceId: source.id,
          environmentId: profile.id,
        ),
      );
    }
    final runner = automation;
    final seen = <String>{};
    for (final item in automated) {
      final problems = runner == null
          ? const [
              AutomationProblem(
                AutomationProblemKind.setup,
                'QA Desk chưa sẵn sàng tự thao tác.',
              ),
            ]
          : runner.problems(item.source, item.scenario, appEnvironment);
      for (final problem in problems) {
        // Setup and vault problems are the same for every scenario.
        if (!seen.add('${problem.kind.name}:${problem.message}')) continue;
        issues.add(
          PreflightIssue(
            kind: switch (problem.kind) {
              AutomationProblemKind.setup => PreflightKind.automationSetup,
              AutomationProblemKind.vault => PreflightKind.vaultNotReady,
              AutomationProblemKind.config => PreflightKind.automationConfig,
              AutomationProblemKind.account => PreflightKind.accountMissing,
              AutomationProblemKind.writesOnProduction =>
                PreflightKind.writesOnProduction,
              AutomationProblemKind.productionGuard =>
                PreflightKind.productionGuard,
              AutomationProblemKind.production => PreflightKind.productionRun,
            },
            message: problem.message,
            blocking: problem.blocking,
          ),
        );
      }
    }
    final busy = busyProjectPaths().toList();
    for (final source in {
      for (final item in selected) item.source,
      for (final item in automated) item.source,
    }) {
      if (!busy.any((path) => p.equals(path, source.path))) continue;
      issues.add(
        PreflightIssue(
          kind: PreflightKind.projectBusy,
          message:
              'AMC đang chạy release trong ${source.name}: test và build sẽ '
              'tranh thư mục build/ của dự án.',
          blocking: false,
          sourceId: source.id,
        ),
      );
    }
    if (network.busy) {
      issues.add(
        const PreflightIssue(
          kind: PreflightKind.networkBusy,
          message: 'Đang bật hoặc tắt giả lập mạng.',
        ),
      );
    } else if (network.enabled) {
      issues.add(
        PreflightIssue(
          kind: PreflightKind.networkSimulated,
          message:
              'Đang giả lập mạng ${network.profile.name}: suite đi qua proxy '
              'sẽ chậm.',
          blocking: false,
        ),
      );
    }
    return issues;
  }

  Future<void> runSelected() async {
    if (_isRunning || network.busy || selectedRunCount == 0) return;
    automation?.beginBatch();

    _runs.clear();
    _isRunning = true;
    final batchId = 'batch-${DateTime.now().microsecondsSinceEpoch}';
    final batchStartedAt = DateTime.now();
    final selectedSources = _sources
        .where((source) => _plannedSuites(source).isNotEmpty)
        .toList();
    for (final source in selectedSources) {
      for (final suite in _plannedSuites(source)) {
        _runs.add(
          SuiteRun(
            runId:
                '${source.id}:${suite.id}:${DateTime.now().microsecondsSinceEpoch}',
            batchId: batchId,
            sourceId: source.id,
            sourceName: source.name,
            suiteId: suite.id,
            suiteName: suite.name,
            command: suite.commandPreview,
          ),
        );
      }
    }
    await _historyStore.startBatch(
      RunBatchSummary(
        id: batchId,
        startedAt: batchStartedAt,
        status: RunStatus.running,
        total: _runs.length,
        passed: 0,
        failed: 0,
        cancelled: 0,
      ),
    );
    notifyListeners();

    await Future.wait(selectedSources.map(_runSource));
    final passed = _runs.where((run) => run.status == RunStatus.passed).length;
    final failed = _runs.where((run) => run.status == RunStatus.failed).length;
    final cancelled = _runs
        .where((run) => run.status == RunStatus.cancelled)
        .length;
    final status = failed > 0
        ? RunStatus.failed
        : cancelled > 0
        ? RunStatus.cancelled
        : RunStatus.passed;
    await _historyStore.finishBatch(
      RunBatchSummary(
        id: batchId,
        startedAt: batchStartedAt,
        finishedAt: DateTime.now(),
        status: status,
        total: _runs.length,
        passed: passed,
        failed: failed,
        cancelled: cancelled,
      ),
    );
    await refreshHistory(notify: false);
    await refreshReports(notify: false);
    _isRunning = false;
    notifyListeners();
  }

  /// The suites a run of [source] executes: its ticked suites, then its
  /// ticked automated scenarios as suites of their own.
  List<QaSuite> _plannedSuites(QaSource source) => [
    if (source.selected) ...source.suites.where((suite) => suite.selected),
    for (final scenario in _selectedAutomated(source))
      QaSuite(
        id: '$_automationPrefix${scenario.id}',
        name: scenario.title,
        executable: 'maestro',
        arguments: [
          'test',
          '.fiza-qa/${scenario.automation!.flow.isEmpty ? 'flows/${scenario.id}.yaml' : scenario.automation!.flow}',
        ],
        tags: const ['automation'],
        requiresDevice:
            source.app(scenario.automation!.app)?.platform != QaAppPlatform.web,
        captureScreenshotOnFailure: false,
      ),
  ];

  static const _automationPrefix = 'flow:';

  Future<void> _runSource(QaSource source) async {
    final git = await _gitMetadataService.read(source.path);
    final selectedSuites = _plannedSuites(source);
    for (final suite in selectedSuites) {
      final run = _runs.firstWhere(
        (item) => item.sourceId == source.id && item.suiteId == suite.id,
      );
      run.gitBranch = git.branch;
      run.gitCommit = git.commit;
      run.gitDirty = git.isDirty;
      if (run.status == RunStatus.cancelled) {
        await _persistRun(run);
        continue;
      }

      if (suite.requiresDevice || suite.requiresPhysicalDevice) {
        // Queued with every other device job in the app, the AAB checker's
        // included, and with this batch's other sources running in parallel.
        await DeviceRunLock.run(() async {
          if (run.status == RunStatus.cancelled) {
            await _persistRun(run);
          } else {
            await _executeSuite(source, suite, run);
          }
        });
      } else {
        await _executeSuite(source, suite, run);
      }
    }
  }

  Future<void> _executeSuite(
    QaSource source,
    QaSuite suite,
    SuiteRun run,
  ) async {
    if (suite.id.startsWith(_automationPrefix)) {
      return _executeAutomation(source, suite, run);
    }
    run.status = RunStatus.running;
    run.startedAt = DateTime.now();
    final environment = _environmentProfileFor(source.id);
    run.environmentId = environment?.id;
    run.environmentName = environment?.name;
    final device = selectedDevice;
    final validationError = _mobileDeviceService.validateSuite(suite, device);
    if (validationError != null) {
      run.status = RunStatus.failed;
      run.logs.add(validationError);
      run.finishedAt = DateTime.now();
      await _persistRun(run);
      notifyListeners();
      return;
    }

    var effectiveSuite = suite;
    if (suite.requiresDevice || suite.requiresPhysicalDevice) {
      run.deviceId = device!.id;
      run.deviceName = device.name;
      run.appiumPort = suite.requiresAppium ? _appiumPort : null;
      effectiveSuite = _mobileDeviceService.bindRuntime(
        suite,
        device: device,
        appiumPort: _appiumPort,
      );
      if (suite.requiresAppium) {
        await startAppium();
        if (_appiumStatus != AppiumStatus.running) {
          run.status = RunStatus.failed;
          run.logs.add(_appiumError ?? 'Appium chưa sẵn sàng.');
          run.finishedAt = DateTime.now();
          await _persistRun(run);
          notifyListeners();
          return;
        }
      }
    }

    run.command = effectiveSuite.commandPreview;
    run.logs.add('> ${effectiveSuite.commandPreview}');
    if (environment != null) {
      run.logs.add('Môi trường: ${environment.name}');
    }
    if (network.enabled) {
      run.logs.add(
        'Network simulation: ${network.profile.description}; proxy ${network.proxyUrl}; chỉ áp dụng client dùng proxy.',
      );
    }
    if (device != null && suite.requiresDevice) {
      run.logs.add('Device: ${device.name} (${device.id})');
    }
    notifyListeners();

    // A suite that prints a session secret must not leave it in the log.
    final redactor = SecretRedactor(_sessionSecretValues(source.id));
    try {
      final process = await _processRunner.start(
        suite: effectiveSuite,
        workingDirectory: source.path,
        environment: {..._environmentFor(source.id), ...network.environment},
      );
      _activeProcesses[run.runId] = process;
      await for (final line in process.output) {
        run.logs.add(redactor.redact(line));
        if (run.logs.length > 3000) run.logs.removeAt(1);
        notifyListeners();
      }
      final exitCode = await process.exitCode;
      run.exitCode = exitCode;
      if (run.status != RunStatus.cancelled) {
        run.status = exitCode == 0 ? RunStatus.passed : RunStatus.failed;
        run.logs.add('Process exited with code $exitCode.');
      }
    } on Object catch (error) {
      if (run.status != RunStatus.cancelled) {
        run.status = RunStatus.failed;
        run.logs.add('Không thể chạy suite: $error');
      }
    } finally {
      _activeProcesses.remove(run.runId);
      run.finishedAt = DateTime.now();
      // Only a suite that ran on the phone has anything on its screen; a
      // failed analyze or unit run must not attach whatever the phone shows.
      if (run.status == RunStatus.failed &&
          suite.captureScreenshotOnFailure &&
          (suite.requiresDevice || suite.requiresPhysicalDevice) &&
          device != null &&
          device.platform.toLowerCase().startsWith('android')) {
        await _captureFailureScreenshot(run, device);
      }
      await _persistRun(run);
      notifyListeners();
    }
  }

  Future<void> _executeAutomation(
    QaSource source,
    QaSuite suite,
    SuiteRun run,
  ) async {
    run.status = RunStatus.running;
    run.startedAt = DateTime.now();
    run.environmentName = 'App: $appEnvironment';
    final scenarioId = suite.id.substring(_automationPrefix.length);
    TestScenario? scenario;
    for (final item in automatedScenarios(source)) {
      if (item.id == scenarioId) scenario = item;
    }
    final runner = automation;
    final device = selectedDevice;
    if (device != null && suite.requiresDevice) {
      run.deviceId = device.id;
      run.deviceName = device.name;
    }
    run.command = 'maestro ${suite.arguments.join(' ')}';
    void log(String line) {
      run.logs.add(line);
      if (run.logs.length > 3000) run.logs.removeAt(1);
      notifyListeners();
    }

    notifyListeners();
    try {
      if (scenario == null || runner == null) {
        log(
          scenario == null
              ? 'Không còn test case này trong catalog.'
              : 'QA Desk chưa sẵn sàng tự thao tác.',
        );
        run.status = RunStatus.failed;
        return;
      }
      if (network.enabled) {
        log(
          'Network simulation: ${network.profile.description}; proxy '
          '${network.proxyUrl}; app trên thiết bị chỉ đi qua proxy khi được '
          'nối riêng.',
        );
      }
      final logFile = await _artifactStore.artifactPath(run, 'maestro.txt');
      final outcome = await runner.execute(
        source: source,
        scenario: scenario,
        environmentName: appEnvironment,
        runId: run.runId,
        device: suite.requiresDevice ? device : null,
        outputDirectory: Directory(p.join(p.dirname(logFile), 'maestro')),
        log: log,
        started: (process) => _activeProcesses[run.runId] = process,
        cancelled: () => run.status == RunStatus.cancelled,
        extraSecrets: _sessionSecretValues(source.id),
      );
      run.exitCode = outcome.exitCode;
      run.detailsPath = outcome.detailsPath;
      run.screenshotPath = outcome.screenshotPath;
      if (run.status != RunStatus.cancelled) run.status = outcome.status;
    } on Object catch (error) {
      if (run.status != RunStatus.cancelled) {
        run.status = RunStatus.failed;
        log('Không chạy được kịch bản: $error');
      }
    } finally {
      _activeProcesses.remove(run.runId);
      run.finishedAt = DateTime.now();
      await _persistRun(run);
      notifyListeners();
    }
  }

  /// Values entered as session secrets for [sourceId]'s environment.
  List<String> _sessionSecretValues(String sourceId) {
    final profile = _environmentProfileFor(sourceId);
    if (profile == null) return const [];
    return [...?_sessionSecrets['$sourceId:${profile.id}']?.values];
  }

  Future<void> _captureFailureScreenshot(
    SuiteRun run,
    DeviceInfo device,
  ) async {
    try {
      final bytes = await _mobileDeviceService.captureScreenshot(device.id);
      run.screenshotPath = await _artifactStore.saveBytes(
        run,
        'failure.png',
        bytes,
      );
      run.logs.add('Failure screenshot: ${run.screenshotPath}');
    } on Object catch (error) {
      run.logs.add('Không thể chụp screenshot: $error');
    }
  }

  Future<void> _persistRun(SuiteRun run) async {
    try {
      run.logPath = await _artifactStore.saveLog(run);
      await _historyStore.saveSuiteRun(run.toHistory());
    } on Object catch (error) {
      run.logs.add('Không thể lưu artifact/lịch sử: $error');
    }
  }

  Future<void> cancelAll() async {
    final active = Map.of(_activeProcesses);
    for (final run in _runs.where(
      (run) =>
          run.status == RunStatus.running || run.status == RunStatus.queued,
    )) {
      run.status = RunStatus.cancelled;
      run.finishedAt = DateTime.now();
      run.logs.add('Đã dừng theo yêu cầu người dùng.');
    }
    notifyListeners();
    await Future.wait(active.values.map((process) => process.stop()));
  }

  /// Stops every child process this workspace started, for app exit: suite
  /// process trees and the Appium server. Windows does not take children down
  /// with their parent. The weak-network proxy lives in-process.
  Future<void> shutdown() async {
    await cancelAll();
    await _appiumServerService.stop();
  }

  Future<void> _loadCatalog(QaSource source) async {
    try {
      final catalog = await _scenarioCatalogStore.load(source);
      _catalogs[source.id] = catalog;
      _catalogErrors.remove(source.id);
      if (catalog.environments.isNotEmpty) {
        _selectedEnvironments.putIfAbsent(
          source.id,
          () => catalog.environments.first.id,
        );
      }
    } on ScenarioCatalogException catch (error) {
      _catalogErrors[source.id] = error.message;
      _catalogs[source.id] = SourceScenarioCatalog(sourceId: source.id);
    }
  }

  QaSource? _sourceById(String sourceId) {
    for (final source in _sources) {
      if (source.id == sourceId) return source;
    }
    return null;
  }

  Map<String, String> _environmentFor(String sourceId) {
    final profile = _environmentProfileFor(sourceId);
    if (profile == null) return const {};
    final result = Map<String, String>.of(profile.variables);
    final secretValues = _sessionSecrets['$sourceId:${profile.id}'];
    for (final key in profile.secretKeys) {
      final value = secretValues?[key];
      if (value != null && value.isNotEmpty) result[key] = value;
    }
    return result;
  }

  EnvironmentProfile? _environmentProfileFor(String sourceId) {
    final catalog = _catalogs[sourceId];
    final environmentId = _selectedEnvironments[sourceId];
    if (catalog == null || environmentId == null) return null;
    for (final item in catalog.environments) {
      if (item.id == environmentId) return item;
    }
    return null;
  }

  Future<void> _save() => _registry.save(_sources);

  @override
  void dispose() {
    automation?.vault.removeListener(notifyListeners);
    network.dispose();
    super.dispose();
  }
}
