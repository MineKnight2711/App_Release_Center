import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/qa_desk_storage.dart';
import 'package:app_management_center/app/modules/qa_desk/services/run_history_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Builds what the standalone app left behind: its sources, a database with
/// one finished run whose artifacts sit in its own folder, and the artifacts.
Future<void> _seedLegacy(String legacy, {String? logPathPrefix}) async {
  await Directory(legacy).create(recursive: true);
  await File(p.join(legacy, 'sources.json')).writeAsString(
    encodeSources([
      const QaSource(
        id: 'fizahub-flutter',
        name: 'FizaHUB Flutter',
        path: r'C:\projects\fizahub_app',
        type: SourceType.flutter,
        suites: [
          QaSuite(
            id: 'analyze',
            name: 'Flutter Analyze',
            executable: 'flutter',
            arguments: ['analyze'],
          ),
        ],
      ),
    ]),
  );
  final artifact = p.join(legacy, 'artifacts', 'batch-1', 'fizahub', 'run.log');
  await Directory(p.dirname(artifact)).create(recursive: true);
  await File(artifact).writeAsString('log line\n');
  await File(
    p.join(p.dirname(artifact), 'failure.png'),
  ).writeAsBytes([1, 2, 3]);

  final store = SqliteRunHistoryStore(
    databasePath: p.join(legacy, QaDeskStorage.legacyDatabaseName),
  );
  await store.initialize();
  final startedAt = DateTime.utc(2026, 9, 30, 9);
  await store.startBatch(
    RunBatchSummary(
      id: 'batch-1',
      startedAt: startedAt,
      status: RunStatus.failed,
      total: 2,
      passed: 0,
      failed: 1,
      cancelled: 1,
    ),
  );
  final prefix = logPathPrefix ?? legacy;
  await store.saveSuiteRun(
    HistoricalSuiteRun(
      runId: 'run-1',
      batchId: 'batch-1',
      sourceId: 'fizahub-flutter',
      sourceName: 'FizaHUB Flutter',
      suiteId: 'analyze',
      suiteName: 'Flutter Analyze',
      status: RunStatus.failed,
      command: 'flutter analyze',
      startedAt: startedAt,
      logPath: p.join(prefix, 'artifacts', 'batch-1', 'fizahub', 'run.log'),
      screenshotPath: p.join(
        prefix,
        'artifacts',
        'batch-1',
        'fizahub',
        'failure.png',
      ),
    ),
  );
  // A run whose log lives somewhere else is not the import's to move.
  await store.saveSuiteRun(
    HistoricalSuiteRun(
      runId: 'run-2',
      batchId: 'batch-1',
      sourceId: 'fizahub-flutter',
      sourceName: 'FizaHUB Flutter',
      suiteId: 'test',
      suiteName: 'Unit tests',
      status: RunStatus.cancelled,
      command: 'flutter test',
      startedAt: startedAt,
      logPath: r'D:\elsewhere\run.log',
    ),
  );
  await store.close();
}

Future<List<String>> _files(String root) async => [
  await for (final entity in Directory(root).list(recursive: true))
    if (entity is File) p.relative(entity.path, from: root),
]..sort();

void main() {
  late Directory sandbox;
  late String legacy;
  late String root;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('qa_desk_storage_');
    legacy = p.join(sandbox.path, 'vn.fizahub.qa', 'Fiza QA Desk');
    root = p.join(sandbox.path, 'App Management Center', 'qa_desk');
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('copies the standalone data in and points history at it', () async {
    await _seedLegacy(legacy);
    final legacyFiles = await _files(legacy);
    final storage = QaDeskStorage(root: root, legacyRoot: legacy);

    final result = await storage.importLegacyIfNeeded();

    expect(result.outcome, QaDeskImportOutcome.imported);
    expect(result.copiedFiles, 4);
    expect(result.relinkedPaths, 2);
    expect(await _files(root), [
      p.join('artifacts', 'batch-1', 'fizahub', 'failure.png'),
      p.join('artifacts', 'batch-1', 'fizahub', 'run.log'),
      QaDeskStorage.importMarkerName,
      QaDeskStorage.databaseName,
      QaDeskStorage.sourcesName,
    ]);
    expect(Directory('$root.importing').existsSync(), isFalse);
    // The standalone folder is only ever read.
    expect(await _files(legacy), legacyFiles);

    final store = SqliteRunHistoryStore(databasePath: storage.databasePath);
    addTearDown(store.close);
    await store.initialize();
    final runs = {
      for (final run in await store.listSuiteRuns('batch-1')) run.runId: run,
    };
    expect(
      runs['run-1']!.logPath,
      p.join(root, 'artifacts', 'batch-1', 'fizahub', 'run.log'),
    );
    expect(File(runs['run-1']!.logPath!).readAsStringSync(), 'log line\n');
    expect(
      runs['run-1']!.screenshotPath,
      p.join(root, 'artifacts', 'batch-1', 'fizahub', 'failure.png'),
    );
    expect(runs['run-2']!.logPath, r'D:\elsewhere\run.log');

    final sources = decodeSources(
      await File(storage.sourcesPath).readAsString(),
    );
    expect(sources.single.name, 'FizaHUB Flutter');
  });

  test('matches the old folder regardless of letter case', () async {
    await _seedLegacy(legacy, logPathPrefix: legacy.toUpperCase());

    final result = await QaDeskStorage(
      root: root,
      legacyRoot: legacy,
    ).importLegacyIfNeeded();

    expect(result.relinkedPaths, 2);
  }, skip: !Platform.isWindows);

  test('does nothing without a standalone install', () async {
    final noLegacy = await QaDeskStorage(
      root: root,
      legacyRoot: legacy,
    ).importLegacyIfNeeded();
    final otherPlatform = await QaDeskStorage(
      root: root,
    ).importLegacyIfNeeded();

    expect(noLegacy.outcome, QaDeskImportOutcome.skipped);
    expect(otherPlatform.outcome, QaDeskImportOutcome.skipped);
    expect(Directory(root).existsSync(), isFalse);
  });

  test('never overwrites a QA Desk folder that is already in use', () async {
    await _seedLegacy(legacy);
    await Directory(root).create(recursive: true);
    await File(p.join(root, QaDeskStorage.sourcesName)).writeAsString('[]');

    final result = await QaDeskStorage(
      root: root,
      legacyRoot: legacy,
    ).importLegacyIfNeeded();

    expect(result.outcome, QaDeskImportOutcome.skipped);
    expect(await _files(root), [QaDeskStorage.sourcesName]);
    expect(
      File(p.join(root, QaDeskStorage.sourcesName)).readAsStringSync(),
      '[]',
    );
  });

  test('imports into an empty folder left by an earlier start', () async {
    await _seedLegacy(legacy);
    await Directory(root).create(recursive: true);

    final result = await QaDeskStorage(
      root: root,
      legacyRoot: legacy,
    ).importLegacyIfNeeded();

    expect(result.outcome, QaDeskImportOutcome.imported);
    expect(File(p.join(root, QaDeskStorage.databaseName)).existsSync(), isTrue);
  });

  test('replaces a staging folder abandoned mid-import', () async {
    await _seedLegacy(legacy);
    final stale = File(p.join('$root.importing', 'half-copied.log'));
    await stale.parent.create(recursive: true);
    await stale.writeAsString('stale');

    final result = await QaDeskStorage(
      root: root,
      legacyRoot: legacy,
    ).importLegacyIfNeeded();

    expect(result.outcome, QaDeskImportOutcome.imported);
    expect(File(p.join(root, 'half-copied.log')).existsSync(), isFalse);
  });

  test(
    'a failed import leaves no half workspace and the old data intact',
    () async {
      await _seedLegacy(legacy);
      final database = File(p.join(legacy, QaDeskStorage.legacyDatabaseName));
      await database.writeAsString('not a database');
      final legacyFiles = await _files(legacy);

      final result = await QaDeskStorage(
        root: root,
        legacyRoot: legacy,
      ).importLegacyIfNeeded();

      expect(result.outcome, QaDeskImportOutcome.failed);
      expect(result.error, isNotEmpty);
      expect(Directory(root).existsSync(), isFalse);
      expect(Directory('$root.importing').existsSync(), isFalse);
      expect(await _files(legacy), legacyFiles);
      expect(database.readAsStringSync(), 'not a database');
    },
  );

  test('imports a schema v1 history that has no screenshot column', () async {
    await _seedLegacy(legacy);
    final v1 = p.join(legacy, QaDeskStorage.legacyDatabaseName);
    await File(v1).delete();
    final store = SqliteRunHistoryStore(databasePath: '$v1.tmp');
    await store.initialize();
    await store.close();
    // Rebuild suite_runs without the columns added in v2 and v3.
    await _execute('$v1.tmp', [
      'DROP TABLE suite_runs',
      'CREATE TABLE suite_runs (id TEXT PRIMARY KEY, batch_id TEXT NOT NULL, '
          'source_id TEXT NOT NULL, source_name TEXT NOT NULL, '
          'suite_id TEXT NOT NULL, suite_name TEXT NOT NULL, '
          'status TEXT NOT NULL, command TEXT NOT NULL, '
          'started_at TEXT NOT NULL, finished_at TEXT, exit_code INTEGER, '
          'log_path TEXT, git_branch TEXT, git_commit TEXT, '
          'git_dirty INTEGER NOT NULL)',
      "INSERT INTO suite_runs VALUES ('r', 'b', 's', 'S', 't', 'T', 'passed', "
          "'flutter test', '2026-09-01T00:00:00.000Z', NULL, 0, "
          "'${p.join(legacy, 'artifacts', 'r.log').replaceAll("'", "''")}', "
          'NULL, NULL, 0)',
      'PRAGMA user_version = 1',
    ]);
    await File('$v1.tmp').rename(v1);

    final result = await QaDeskStorage(
      root: root,
      legacyRoot: legacy,
    ).importLegacyIfNeeded();

    expect(result.outcome, QaDeskImportOutcome.imported);
    expect(result.relinkedPaths, 1);
  });
}

Future<void> _execute(String databasePath, List<String> statements) async {
  final database = await databaseFactoryFfi.openDatabase(databasePath);
  try {
    for (final statement in statements) {
      await database.execute(statement);
    }
  } finally {
    await database.close();
  }
}
