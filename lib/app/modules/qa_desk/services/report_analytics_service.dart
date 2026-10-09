import '../models/qa_models.dart';
import '../models/report_models.dart';

class ReportAnalyticsService {
  const ReportAnalyticsService();

  ReportSnapshot build(List<HistoricalSuiteRun> runs) {
    final completed = runs.where(
      (run) =>
          run.status == RunStatus.passed ||
          run.status == RunStatus.failed ||
          run.status == RunStatus.cancelled,
    );
    final passed = completed
        .where((run) => run.status == RunStatus.passed)
        .length;
    final failed = completed
        .where((run) => run.status == RunStatus.failed)
        .length;
    final cancelled = completed
        .where((run) => run.status == RunStatus.cancelled)
        .length;
    final durations = completed
        .map((run) => run.duration)
        .whereType<Duration>()
        .toList();
    final average = durations.isEmpty
        ? Duration.zero
        : Duration(
            microseconds:
                durations.fold<int>(
                  0,
                  (sum, item) => sum + item.inMicroseconds,
                ) ~/
                durations.length,
          );

    final groups = <String, List<HistoricalSuiteRun>>{};
    for (final run in completed) {
      groups.putIfAbsent('${run.sourceId}:${run.suiteId}', () => []).add(run);
    }
    final flaky = <FlakySuiteSummary>[];
    for (final group in groups.values) {
      final suitePassed = group
          .where((run) => run.status == RunStatus.passed)
          .length;
      final suiteFailed = group
          .where((run) => run.status == RunStatus.failed)
          .length;
      if (suitePassed > 0 && suiteFailed > 0) {
        final sample = group.first;
        flaky.add(
          FlakySuiteSummary(
            sourceId: sample.sourceId,
            sourceName: sample.sourceName,
            suiteId: sample.suiteId,
            suiteName: sample.suiteName,
            passed: suitePassed,
            failed: suiteFailed,
            total: group.length,
          ),
        );
      }
    }
    flaky.sort((a, b) => b.failureRate.compareTo(a.failureRate));
    final slowest = completed.where((run) => run.duration != null).toList()
      ..sort((a, b) => b.duration!.compareTo(a.duration!));
    return ReportSnapshot(
      totalRuns: completed.length,
      passed: passed,
      failed: failed,
      cancelled: cancelled,
      averageDuration: average,
      flakySuites: flaky.take(10).toList(growable: false),
      slowestSuites: slowest.take(10).toList(growable: false),
    );
  }

  List<BatchSuiteComparison> compare(
    String beforeBatchId,
    String afterBatchId,
    List<HistoricalSuiteRun> runs,
  ) {
    final before = {
      for (final run in runs.where((run) => run.batchId == beforeBatchId))
        '${run.sourceId}:${run.suiteId}': run,
    };
    final after = {
      for (final run in runs.where((run) => run.batchId == afterBatchId))
        '${run.sourceId}:${run.suiteId}': run,
    };
    final keys = {...before.keys, ...after.keys}.toList()..sort();
    return keys
        .map((key) {
          final previous = before[key];
          final current = after[key];
          return BatchSuiteComparison(
            sourceName: current?.sourceName ?? previous!.sourceName,
            suiteName: current?.suiteName ?? previous!.suiteName,
            before: previous?.status,
            after: current?.status,
          );
        })
        .toList(growable: false);
  }
}
