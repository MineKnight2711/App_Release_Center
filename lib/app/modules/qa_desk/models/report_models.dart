import 'qa_models.dart';

class FlakySuiteSummary {
  const FlakySuiteSummary({
    required this.sourceId,
    required this.sourceName,
    required this.suiteId,
    required this.suiteName,
    required this.passed,
    required this.failed,
    required this.total,
  });

  final String sourceId;
  final String sourceName;
  final String suiteId;
  final String suiteName;
  final int passed;
  final int failed;
  final int total;

  double get failureRate => total == 0 ? 0 : failed / total;
}

class ReportSnapshot {
  const ReportSnapshot({
    required this.totalRuns,
    required this.passed,
    required this.failed,
    required this.cancelled,
    required this.averageDuration,
    required this.flakySuites,
    required this.slowestSuites,
  });

  final int totalRuns;
  final int passed;
  final int failed;
  final int cancelled;
  final Duration averageDuration;
  final List<FlakySuiteSummary> flakySuites;
  final List<HistoricalSuiteRun> slowestSuites;

  double get passRate => totalRuns == 0 ? 0 : passed / totalRuns;
}

class BatchSuiteComparison {
  const BatchSuiteComparison({
    required this.sourceName,
    required this.suiteName,
    required this.before,
    required this.after,
  });

  final String sourceName;
  final String suiteName;
  final RunStatus? before;
  final RunStatus? after;

  bool get changed => before != after;
}
