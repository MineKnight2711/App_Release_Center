import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/qa_models.dart';
import 'qa_desk_storage.dart';

abstract interface class RunHistoryStore {
  Future<void> initialize();
  Future<void> startBatch(RunBatchSummary batch);
  Future<void> saveSuiteRun(HistoricalSuiteRun run);
  Future<void> finishBatch(RunBatchSummary batch);
  Future<List<RunBatchSummary>> listBatches({int limit = 100});
  Future<List<HistoricalSuiteRun>> listSuiteRuns(String batchId);
  Future<List<HistoricalSuiteRun>> listRecentSuiteRuns({int limit = 2000});

  /// Closes batches still marked running, which only happens when the app
  /// went away mid-run. Returns how many were closed.
  Future<int> recoverInterruptedBatches();
}

/// The summary an interrupted [batch] is closed with: suites that finished
/// keep their result, and every suite that never reported counts as stopped.
RunBatchSummary interruptedBatchSummary(
  RunBatchSummary batch,
  List<HistoricalSuiteRun> runs,
) {
  final passed = runs.where((run) => run.status == RunStatus.passed).length;
  final failed = runs.where((run) => run.status == RunStatus.failed).length;
  var finishedAt = batch.startedAt;
  for (final run in runs) {
    final end = run.finishedAt ?? run.startedAt;
    if (end.isAfter(finishedAt)) finishedAt = end;
  }
  final cancelled = batch.total - passed - failed;
  return RunBatchSummary(
    id: batch.id,
    startedAt: batch.startedAt,
    finishedAt: finishedAt,
    status: failed > 0 ? RunStatus.failed : RunStatus.cancelled,
    total: batch.total,
    passed: passed,
    failed: failed,
    cancelled: cancelled < 0 ? 0 : cancelled,
  );
}

class SqliteRunHistoryStore implements RunHistoryStore {
  SqliteRunHistoryStore({this.databasePath});

  final String? databasePath;
  Database? _database;

  @override
  Future<void> initialize() async {
    sqfliteFfiInit();
    final dbPath =
        databasePath ??
        path.join(await qaDeskRoot(), QaDeskStorage.databaseName);
    await Directory(path.dirname(dbPath)).create(recursive: true);
    _database = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (database, _) async {
          await database.execute('''
CREATE TABLE run_batches (
  id TEXT PRIMARY KEY,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  status TEXT NOT NULL,
  total INTEGER NOT NULL,
  passed INTEGER NOT NULL,
  failed INTEGER NOT NULL,
  cancelled INTEGER NOT NULL
)
''');
          await database.execute('''
CREATE TABLE suite_runs (
  id TEXT PRIMARY KEY,
  batch_id TEXT NOT NULL,
  source_id TEXT NOT NULL,
  source_name TEXT NOT NULL,
  suite_id TEXT NOT NULL,
  suite_name TEXT NOT NULL,
  status TEXT NOT NULL,
  command TEXT NOT NULL,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  exit_code INTEGER,
  log_path TEXT,
  git_branch TEXT,
  git_commit TEXT,
  git_dirty INTEGER NOT NULL,
  device_id TEXT,
  device_name TEXT,
  appium_port INTEGER,
  screenshot_path TEXT,
  environment_id TEXT,
  environment_name TEXT,
  details_path TEXT,
  FOREIGN KEY (batch_id) REFERENCES run_batches(id)
)
''');
          await database.execute(
            'CREATE INDEX idx_suite_runs_batch ON suite_runs(batch_id)',
          );
        },
        onUpgrade: (database, oldVersion, _) async {
          if (oldVersion < 2) {
            await database.execute('ALTER TABLE suite_runs ADD device_id TEXT');
            await database.execute(
              'ALTER TABLE suite_runs ADD device_name TEXT',
            );
            await database.execute(
              'ALTER TABLE suite_runs ADD appium_port INTEGER',
            );
            await database.execute(
              'ALTER TABLE suite_runs ADD screenshot_path TEXT',
            );
          }
          if (oldVersion < 3) {
            await database.execute(
              'ALTER TABLE suite_runs ADD environment_id TEXT',
            );
            await database.execute(
              'ALTER TABLE suite_runs ADD environment_name TEXT',
            );
          }
          if (oldVersion < 4) {
            await database.execute(
              'ALTER TABLE suite_runs ADD details_path TEXT',
            );
          }
        },
      ),
    );
  }

  Database get _db {
    final database = _database;
    if (database == null) throw StateError('History store is not initialized');
    return database;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  @override
  Future<void> startBatch(RunBatchSummary batch) async {
    await _db.insert(
      'run_batches',
      _batchMap(batch),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> finishBatch(RunBatchSummary batch) async {
    await _db.update(
      'run_batches',
      _batchMap(batch),
      where: 'id = ?',
      whereArgs: [batch.id],
    );
  }

  @override
  Future<void> saveSuiteRun(HistoricalSuiteRun run) async {
    await _db.insert(
      'suite_runs',
      _runMap(run),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<RunBatchSummary>> listBatches({int limit = 100}) async {
    final rows = await _db.query(
      'run_batches',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(_batchFromMap).toList(growable: false);
  }

  @override
  Future<List<HistoricalSuiteRun>> listSuiteRuns(String batchId) async {
    final rows = await _db.query(
      'suite_runs',
      where: 'batch_id = ?',
      whereArgs: [batchId],
      orderBy: 'started_at ASC',
    );
    return rows.map(_runFromMap).toList(growable: false);
  }

  @override
  Future<List<HistoricalSuiteRun>> listRecentSuiteRuns({
    int limit = 2000,
  }) async {
    final rows = await _db.query(
      'suite_runs',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(_runFromMap).toList(growable: false);
  }

  @override
  Future<int> recoverInterruptedBatches() async {
    final rows = await _db.query(
      'run_batches',
      where: 'status = ?',
      whereArgs: [RunStatus.running.name],
    );
    for (final row in rows) {
      final batch = _batchFromMap(row);
      await finishBatch(
        interruptedBatchSummary(batch, await listSuiteRuns(batch.id)),
      );
    }
    return rows.length;
  }
}

class MemoryRunHistoryStore implements RunHistoryStore {
  final Map<String, RunBatchSummary> _batches = {};
  final Map<String, HistoricalSuiteRun> _runs = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> startBatch(RunBatchSummary batch) async {
    _batches[batch.id] = batch;
  }

  @override
  Future<void> finishBatch(RunBatchSummary batch) async {
    _batches[batch.id] = batch;
  }

  @override
  Future<void> saveSuiteRun(HistoricalSuiteRun run) async {
    _runs[run.runId] = run;
  }

  @override
  Future<List<RunBatchSummary>> listBatches({int limit = 100}) async {
    final items = _batches.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return items.take(limit).toList(growable: false);
  }

  @override
  Future<List<HistoricalSuiteRun>> listSuiteRuns(String batchId) async {
    final items = _runs.values.where((run) => run.batchId == batchId).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return items;
  }

  @override
  Future<List<HistoricalSuiteRun>> listRecentSuiteRuns({
    int limit = 2000,
  }) async {
    final items = _runs.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return items.take(limit).toList(growable: false);
  }

  @override
  Future<int> recoverInterruptedBatches() async {
    final interrupted = _batches.values
        .where((batch) => batch.status == RunStatus.running)
        .toList();
    for (final batch in interrupted) {
      _batches[batch.id] = interruptedBatchSummary(
        batch,
        await listSuiteRuns(batch.id),
      );
    }
    return interrupted.length;
  }
}

Map<String, Object?> _batchMap(RunBatchSummary batch) => {
  'id': batch.id,
  'started_at': batch.startedAt.toIso8601String(),
  'finished_at': batch.finishedAt?.toIso8601String(),
  'status': batch.status.name,
  'total': batch.total,
  'passed': batch.passed,
  'failed': batch.failed,
  'cancelled': batch.cancelled,
};

RunBatchSummary _batchFromMap(Map<String, Object?> map) => RunBatchSummary(
  id: map['id']! as String,
  startedAt: DateTime.parse(map['started_at']! as String),
  finishedAt: map['finished_at'] == null
      ? null
      : DateTime.parse(map['finished_at']! as String),
  status: parseRunStatus(map['status']! as String),
  total: map['total']! as int,
  passed: map['passed']! as int,
  failed: map['failed']! as int,
  cancelled: map['cancelled']! as int,
);

Map<String, Object?> _runMap(HistoricalSuiteRun run) => {
  'id': run.runId,
  'batch_id': run.batchId,
  'source_id': run.sourceId,
  'source_name': run.sourceName,
  'suite_id': run.suiteId,
  'suite_name': run.suiteName,
  'status': run.status.name,
  'command': run.command,
  'started_at': run.startedAt.toIso8601String(),
  'finished_at': run.finishedAt?.toIso8601String(),
  'exit_code': run.exitCode,
  'log_path': run.logPath,
  'git_branch': run.gitBranch,
  'git_commit': run.gitCommit,
  'git_dirty': run.gitDirty ? 1 : 0,
  'device_id': run.deviceId,
  'device_name': run.deviceName,
  'appium_port': run.appiumPort,
  'screenshot_path': run.screenshotPath,
  'environment_id': run.environmentId,
  'environment_name': run.environmentName,
  'details_path': run.detailsPath,
};

HistoricalSuiteRun _runFromMap(Map<String, Object?> map) => HistoricalSuiteRun(
  runId: map['id']! as String,
  batchId: map['batch_id']! as String,
  sourceId: map['source_id']! as String,
  sourceName: map['source_name']! as String,
  suiteId: map['suite_id']! as String,
  suiteName: map['suite_name']! as String,
  status: parseRunStatus(map['status']! as String),
  command: map['command']! as String,
  startedAt: DateTime.parse(map['started_at']! as String),
  finishedAt: map['finished_at'] == null
      ? null
      : DateTime.parse(map['finished_at']! as String),
  exitCode: map['exit_code'] as int?,
  logPath: map['log_path'] as String?,
  gitBranch: map['git_branch'] as String?,
  gitCommit: map['git_commit'] as String?,
  gitDirty: map['git_dirty'] == 1,
  deviceId: map['device_id'] as String?,
  deviceName: map['device_name'] as String?,
  appiumPort: map['appium_port'] as int?,
  screenshotPath: map['screenshot_path'] as String?,
  environmentId: map['environment_id'] as String?,
  environmentName: map['environment_name'] as String?,
  detailsPath: map['details_path'] as String?,
);
