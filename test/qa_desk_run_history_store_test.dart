import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/run_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists a batch and suite result in SQLite', () async {
    final sandbox = await Directory.systemTemp.createTemp('fiza_history_');
    final store = SqliteRunHistoryStore(
      databasePath: '${sandbox.path}${Platform.pathSeparator}history.db',
    );
    addTearDown(() async {
      await store.close();
      await sandbox.delete(recursive: true);
    });
    await store.initialize();
    final startedAt = DateTime.utc(2026, 9, 28, 10);
    await store.startBatch(
      RunBatchSummary(
        id: 'batch-1',
        startedAt: startedAt,
        status: RunStatus.running,
        total: 1,
        passed: 0,
        failed: 0,
        cancelled: 0,
      ),
    );
    await store.saveSuiteRun(
      HistoricalSuiteRun(
        runId: 'run-1',
        batchId: 'batch-1',
        sourceId: 'mobile',
        sourceName: 'Mobile App',
        suiteId: 'analyze',
        suiteName: 'Analyze',
        status: RunStatus.passed,
        command: 'flutter analyze',
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(seconds: 4)),
        exitCode: 0,
        logPath: r'C:\artifacts\run-1.log',
        gitBranch: 'main',
        gitCommit: 'abcdef1',
        gitDirty: true,
        deviceId: 'emulator-5554',
        deviceName: 'Pixel 8',
        appiumPort: 4723,
        screenshotPath: r'C:\artifacts\failure.png',
        environmentId: 'staging',
        environmentName: 'Staging',
      ),
    );
    await store.finishBatch(
      RunBatchSummary(
        id: 'batch-1',
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(seconds: 4)),
        status: RunStatus.passed,
        total: 1,
        passed: 1,
        failed: 0,
        cancelled: 0,
      ),
    );

    final batches = await store.listBatches();
    final runs = await store.listSuiteRuns('batch-1');

    expect(batches.single.passed, 1);
    expect(runs.single.gitCommit, 'abcdef1');
    expect(runs.single.gitDirty, isTrue);
    expect(runs.single.logPath, endsWith('run-1.log'));
    expect(runs.single.deviceId, 'emulator-5554');
    expect(runs.single.appiumPort, 4723);
    expect(runs.single.screenshotPath, endsWith('failure.png'));
    expect(runs.single.environmentName, 'Staging');
  });
}
