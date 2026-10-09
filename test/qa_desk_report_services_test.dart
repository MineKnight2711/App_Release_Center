import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/report_analytics_service.dart';
import 'package:app_management_center/app/modules/qa_desk/services/report_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final started = DateTime.utc(2026, 9, 28, 10);
  late List<HistoricalSuiteRun> runs;

  setUp(() {
    runs = [
      _run(
        id: 'old-auth',
        batch: 'old',
        suiteId: 'auth',
        suiteName: 'Auth',
        status: RunStatus.failed,
        started: started,
        duration: const Duration(seconds: 8),
      ),
      _run(
        id: 'new-auth',
        batch: 'new',
        suiteId: 'auth',
        suiteName: 'Auth',
        status: RunStatus.passed,
        started: started.add(const Duration(minutes: 5)),
        duration: const Duration(seconds: 4),
      ),
      _run(
        id: 'new-build',
        batch: 'new',
        suiteId: 'build',
        suiteName: 'Build',
        status: RunStatus.passed,
        started: started.add(const Duration(minutes: 5)),
        duration: const Duration(seconds: 12),
      ),
    ];
  });

  test('calculates pass rate, flaky suites, slowest and comparison', () {
    const service = ReportAnalyticsService();
    final report = service.build(runs);
    final comparison = service.compare('old', 'new', runs);

    expect(report.totalRuns, 3);
    expect(report.passRate, closeTo(2 / 3, 0.001));
    expect(report.flakySuites.single.suiteId, 'auth');
    expect(report.slowestSuites.first.suiteId, 'build');
    expect(
      comparison.firstWhere((item) => item.suiteName == 'Auth').changed,
      isTrue,
    );
  });

  test('exports HTML, JUnit and JSON reports', () async {
    final sandbox = await Directory.systemTemp.createTemp('fiza_reports_');
    addTearDown(() => sandbox.delete(recursive: true));
    final batch = RunBatchSummary(
      id: 'new',
      startedAt: started,
      finishedAt: started.add(const Duration(seconds: 12)),
      status: RunStatus.passed,
      total: 2,
      passed: 2,
      failed: 0,
      cancelled: 0,
    );
    const exporter = ReportExportService();

    for (final format in ReportFormat.values) {
      final path = '${sandbox.path}${Platform.pathSeparator}${format.name}.txt';
      await exporter.export(
        batch: batch,
        runs: runs.where((run) => run.batchId == 'new').toList(),
        format: format,
        outputPath: path,
      );
      final content = await File(path).readAsString();
      expect(content, contains('Auth'));
    }
  });
}

HistoricalSuiteRun _run({
  required String id,
  required String batch,
  required String suiteId,
  required String suiteName,
  required RunStatus status,
  required DateTime started,
  required Duration duration,
}) {
  return HistoricalSuiteRun(
    runId: id,
    batchId: batch,
    sourceId: 'source',
    sourceName: 'Source',
    suiteId: suiteId,
    suiteName: suiteName,
    status: status,
    command: 'dart test',
    startedAt: started,
    finishedAt: started.add(duration),
    exitCode: status == RunStatus.passed ? 0 : 1,
  );
}
