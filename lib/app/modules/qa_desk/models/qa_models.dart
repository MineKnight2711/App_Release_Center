import 'dart:convert';

import 'automation_models.dart';

enum SourceType {
  flutter('Flutter', 'flutter'),
  playwright('Playwright', 'playwright'),
  node('Node / Web', 'node'),
  unknown('Unknown', 'unknown');

  const SourceType(this.label, this.value);

  final String label;
  final String value;

  static SourceType parse(String? value) {
    return SourceType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => SourceType.unknown,
    );
  }
}

class QaSuite {
  const QaSuite({
    required this.id,
    required this.name,
    required this.executable,
    required this.arguments,
    this.description = '',
    this.tags = const [],
    this.requiresDevice = false,
    this.requiresPhysicalDevice = false,
    this.requiresAppium = false,
    this.captureScreenshotOnFailure = true,
    this.selected = true,
  });

  final String id;
  final String name;
  final String executable;
  final List<String> arguments;
  final String description;
  final List<String> tags;
  final bool requiresDevice;
  final bool requiresPhysicalDevice;
  final bool requiresAppium;
  final bool captureScreenshotOnFailure;
  final bool selected;

  String get commandPreview => [executable, ...arguments].join(' ');

  QaSuite copyWith({bool? selected, List<String>? arguments}) {
    return QaSuite(
      id: id,
      name: name,
      executable: executable,
      arguments: arguments ?? this.arguments,
      description: description,
      tags: tags,
      requiresDevice: requiresDevice,
      requiresPhysicalDevice: requiresPhysicalDevice,
      requiresAppium: requiresAppium,
      captureScreenshotOnFailure: captureScreenshotOnFailure,
      selected: selected ?? this.selected,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'executable': executable,
    'arguments': arguments,
    'description': description,
    'tags': tags,
    'requiresDevice': requiresDevice,
    'requiresPhysicalDevice': requiresPhysicalDevice,
    'requiresAppium': requiresAppium,
    'captureScreenshotOnFailure': captureScreenshotOnFailure,
    'selected': selected,
  };

  factory QaSuite.fromJson(Map<String, dynamic> json) {
    return QaSuite(
      id: json['id'] as String,
      name: json['name'] as String,
      executable: json['executable'] as String,
      arguments: _stringList(json['arguments']),
      description: json['description'] as String? ?? '',
      tags: _stringList(json['tags']),
      requiresDevice: json['requiresDevice'] as bool? ?? false,
      requiresPhysicalDevice: json['requiresPhysicalDevice'] as bool? ?? false,
      requiresAppium: json['requiresAppium'] as bool? ?? false,
      captureScreenshotOnFailure:
          json['captureScreenshotOnFailure'] as bool? ?? true,
      selected: json['selected'] as bool? ?? true,
    );
  }
}

class QaSource {
  const QaSource({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.suites,
    this.selected = true,
    this.manifestBacked = false,
    this.apps = const [],
    this.automationSelection = const [],
  });

  final String id;
  final String name;
  final String path;
  final SourceType type;
  final List<QaSuite> suites;
  final bool selected;
  final bool manifestBacked;

  /// Apps the manifest declares for QA Desk to operate itself.
  final List<QaApp> apps;

  /// Ids of the automated scenarios ticked for the next run.
  final List<String> automationSelection;

  QaApp? app(String id) {
    for (final item in apps) {
      if (item.id == id) return item;
    }
    return null;
  }

  QaSource copyWith({
    bool? selected,
    List<QaSuite>? suites,
    List<String>? automationSelection,
    List<QaApp>? apps,
  }) {
    return QaSource(
      id: id,
      name: name,
      path: path,
      type: type,
      suites: suites ?? this.suites,
      selected: selected ?? this.selected,
      manifestBacked: manifestBacked,
      apps: apps ?? this.apps,
      automationSelection: automationSelection ?? this.automationSelection,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'type': type.value,
    'suites': suites.map((suite) => suite.toJson()).toList(),
    'manifestBacked': manifestBacked,
    if (apps.isNotEmpty) 'apps': apps.map((app) => app.toJson()).toList(),
    if (automationSelection.isNotEmpty)
      'automationSelection': automationSelection,
  };

  factory QaSource.fromJson(Map<String, dynamic> json) {
    return QaSource(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      type: SourceType.parse(json['type'] as String?),
      suites: (json['suites'] as List<dynamic>? ?? const [])
          .map(
            (item) => QaSuite.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      manifestBacked: json['manifestBacked'] as bool? ?? false,
      apps: [
        for (final item in json['apps'] as List<dynamic>? ?? const [])
          QaApp.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      automationSelection: _stringList(json['automationSelection']),
    );
  }
}

enum RunStatus { queued, running, passed, failed, cancelled }

RunStatus parseRunStatus(String value) => RunStatus.values.firstWhere(
  (status) => status.name == value,
  orElse: () => RunStatus.failed,
);

class GitMetadata {
  const GitMetadata({this.branch, this.commit, this.isDirty = false});

  final String? branch;
  final String? commit;
  final bool isDirty;
}

class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.category,
    required this.isEmulator,
    this.platformVersion,
    this.ephemeral = false,
  });

  final String id;
  final String name;
  final String platform;
  final String category;
  final bool isEmulator;
  final String? platformVersion;
  final bool ephemeral;

  bool get isPhysical => !isEmulator;
}

class RunBatchSummary {
  const RunBatchSummary({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.total,
    required this.passed,
    required this.failed,
    required this.cancelled,
    this.finishedAt,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final RunStatus status;
  final int total;
  final int passed;
  final int failed;
  final int cancelled;

  Duration? get duration => finishedAt?.difference(startedAt);
}

class HistoricalSuiteRun {
  const HistoricalSuiteRun({
    required this.runId,
    required this.batchId,
    required this.sourceId,
    required this.sourceName,
    required this.suiteId,
    required this.suiteName,
    required this.status,
    required this.command,
    required this.startedAt,
    this.finishedAt,
    this.exitCode,
    this.logPath,
    this.gitBranch,
    this.gitCommit,
    this.gitDirty = false,
    this.deviceId,
    this.deviceName,
    this.appiumPort,
    this.screenshotPath,
    this.environmentId,
    this.environmentName,
    this.detailsPath,
  });

  final String runId;
  final String batchId;
  final String sourceId;
  final String sourceName;
  final String suiteId;
  final String suiteName;
  final RunStatus status;
  final String command;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int? exitCode;
  final String? logPath;
  final String? gitBranch;
  final String? gitCommit;
  final bool gitDirty;
  final String? deviceId;
  final String? deviceName;
  final int? appiumPort;
  final String? screenshotPath;
  final String? environmentId;
  final String? environmentName;

  /// `steps.json` of an automated scenario: what it did, step by step.
  final String? detailsPath;

  Duration? get duration => finishedAt?.difference(startedAt);
}

class SuiteRun {
  SuiteRun({
    required this.runId,
    required this.batchId,
    required this.sourceId,
    required this.sourceName,
    required this.suiteId,
    required this.suiteName,
    required this.command,
    this.status = RunStatus.queued,
    this.startedAt,
    this.finishedAt,
    this.exitCode,
    this.logPath,
    this.gitBranch,
    this.gitCommit,
    this.gitDirty = false,
    this.deviceId,
    this.deviceName,
    this.appiumPort,
    this.screenshotPath,
    this.environmentId,
    this.environmentName,
    this.detailsPath,
    List<String>? logs,
  }) : logs = logs ?? [];

  final String runId;
  final String batchId;
  final String sourceId;
  final String sourceName;
  final String suiteId;
  final String suiteName;
  String command;
  RunStatus status;
  DateTime? startedAt;
  DateTime? finishedAt;
  int? exitCode;
  String? logPath;
  String? gitBranch;
  String? gitCommit;
  bool gitDirty;
  String? deviceId;
  String? deviceName;
  int? appiumPort;
  String? screenshotPath;
  String? environmentId;
  String? environmentName;
  String? detailsPath;
  final List<String> logs;

  Duration? get duration {
    final start = startedAt;
    if (start == null) return null;
    return (finishedAt ?? DateTime.now()).difference(start);
  }

  HistoricalSuiteRun toHistory() {
    return HistoricalSuiteRun(
      runId: runId,
      batchId: batchId,
      sourceId: sourceId,
      sourceName: sourceName,
      suiteId: suiteId,
      suiteName: suiteName,
      status: status,
      command: command,
      startedAt: startedAt ?? DateTime.now(),
      finishedAt: finishedAt,
      exitCode: exitCode,
      logPath: logPath,
      gitBranch: gitBranch,
      gitCommit: gitCommit,
      gitDirty: gitDirty,
      deviceId: deviceId,
      deviceName: deviceName,
      appiumPort: appiumPort,
      screenshotPath: screenshotPath,
      environmentId: environmentId,
      environmentName: environmentName,
      detailsPath: detailsPath,
    );
  }
}

String encodeSources(List<QaSource> sources) =>
    jsonEncode(sources.map((source) => source.toJson()).toList());

List<QaSource> decodeSources(String raw) {
  final decoded = jsonDecode(raw) as List<dynamic>;
  return decoded
      .map((item) => QaSource.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList();
}

List<String> _stringList(dynamic value) {
  return (value as List<dynamic>? ?? const [])
      .map((item) => item.toString())
      .toList(growable: false);
}
