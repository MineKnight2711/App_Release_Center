import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/appium_server_service.dart';
import 'package:app_management_center/app/modules/qa_desk/services/qa_desk_runtime.dart';
import 'package:app_management_center/app/modules/qa_desk/services/qa_desk_storage.dart';
import 'package:app_management_center/app/modules/qa_desk/services/run_history_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Keeps the tests off the machine's PATH lookup for Appium.
class _NoAppium extends AppiumServerService {
  int stops = 0;

  @override
  Future<bool> isInstalled() async => false;

  @override
  Future<void> stop() async {
    stops++;
    await super.stop();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late QaDeskStorage storage;
  late String legacy;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('qa_desk_runtime_');
    legacy = p.join(sandbox.path, 'legacy');
    storage = QaDeskStorage(
      root: p.join(sandbox.path, 'qa_desk'),
      legacyRoot: legacy,
    );
  });

  tearDown(() async {
    await QaDeskRuntime.current?.close();
    await sandbox.delete(recursive: true);
  });

  test(
    'opens once, on the imported data, with interrupted runs closed',
    () async {
      await Directory(legacy).create(recursive: true);
      await File(p.join(legacy, QaDeskStorage.sourcesName)).writeAsString(
        encodeSources([
          QaSource(
            id: 'app',
            name: 'FizaHUB Flutter',
            // Missing on disk, so the stored suites are used as they are.
            path: p.join(sandbox.path, 'missing_project'),
            type: SourceType.flutter,
            suites: const [
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
      // The standalone app was closed while a three-suite batch ran: one suite
      // had finished and been saved, the batch row still says running.
      final legacyHistory = SqliteRunHistoryStore(
        databasePath: p.join(legacy, QaDeskStorage.legacyDatabaseName),
      );
      await legacyHistory.initialize();
      final startedAt = DateTime.utc(2026, 9, 30, 9);
      await legacyHistory.startBatch(
        RunBatchSummary(
          id: 'batch-1',
          startedAt: startedAt,
          status: RunStatus.running,
          total: 3,
          passed: 0,
          failed: 0,
          cancelled: 0,
        ),
      );
      await legacyHistory.saveSuiteRun(
        HistoricalSuiteRun(
          runId: 'run-1',
          batchId: 'batch-1',
          sourceId: 'app',
          sourceName: 'FizaHUB Flutter',
          suiteId: 'analyze',
          suiteName: 'Flutter Analyze',
          status: RunStatus.passed,
          command: 'flutter analyze',
          startedAt: startedAt,
          finishedAt: startedAt.add(const Duration(seconds: 12)),
        ),
      );
      await legacyHistory.close();

      final first = QaDeskRuntime.openFor(storage, appium: _NoAppium());
      final second = QaDeskRuntime.openFor(storage, appium: _NoAppium());
      expect(identical(first, second), isTrue);
      final runtime = await first;

      expect(QaDeskRuntime.current, same(runtime));
      expect(runtime.controller.isInitializing, isFalse);
      expect(runtime.controller.sources.single.name, 'FizaHUB Flutter');
      final batch = runtime.controller.historyBatches.single;
      expect(batch.status, RunStatus.cancelled);
      expect(batch.passed, 1);
      expect(batch.cancelled, 2);
      expect(batch.finishedAt, startedAt.add(const Duration(seconds: 12)));

      expect(runtime.takeImportNotice()?.outcome, QaDeskImportOutcome.imported);
      expect(runtime.takeImportNotice(), isNull);
    },
  );

  test('a fresh install opens empty and announces nothing', () async {
    final runtime = await QaDeskRuntime.openFor(storage, appium: _NoAppium());

    expect(runtime.controller.sources, isEmpty);
    expect(runtime.controller.historyBatches, isEmpty);
    expect(runtime.takeImportNotice(), isNull);
    expect(File(storage.databasePath).existsSync(), isTrue);
  });

  test('quitting the app stops what QA Desk started', () async {
    final appium = _NoAppium();
    await QaDeskRuntime.openFor(storage, appium: appium);

    final response = await WidgetsBinding.instance.handleRequestAppExit();

    expect(response, AppExitResponse.exit);
    expect(appium.stops, 1);
  });

  test('a failed open can be retried', () async {
    // A folder where the database belongs makes the history store fail.
    final blocker = Directory(storage.databasePath);
    await blocker.create(recursive: true);

    await expectLater(
      QaDeskRuntime.openFor(storage, appium: _NoAppium()),
      throwsA(anything),
    );
    expect(QaDeskRuntime.current, isNull);

    await blocker.delete();
    final runtime = await QaDeskRuntime.openFor(storage, appium: _NoAppium());
    expect(QaDeskRuntime.current, same(runtime));
  });
}
