import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/issue_report_service.dart';
import 'package:flutter_test/flutter_test.dart';

HistoricalSuiteRun sample(RunStatus status, {String id = 'test'}) =>
    HistoricalSuiteRun(
      runId: id,
      batchId: 'batch-1',
      sourceId: 'app',
      sourceName: 'App',
      suiteId: id,
      suiteName: id,
      status: status,
      command: 'flutter test',
      startedAt: DateTime(2026, 9, 30),
      exitCode: status == RunStatus.failed ? 1 : null,
      environmentName: 'Staging',
      gitBranch: 'main',
      gitCommit: 'abc123',
      logPath: 'test.log',
      screenshotPath: 'failure.png',
    );

void main() {
  const service = IssueReportService();
  test(
    'only failed suites become tasks, cancelled stays inconclusive',
    () async {
      final read = <String>[];
      final report = await service.build(
        [
          sample(RunStatus.passed, id: 'pass'),
          sample(RunStatus.failed),
          sample(RunStatus.cancelled, id: 'stop'),
        ],
        (run) async {
          read.add(run.runId);
          return 'Expected: true\nActual: false';
        },
      );
      expect(read, ['test']);
      expect(report.issues, hasLength(1));
      expect(report.summary, '1 đạt • 1 lỗi • 1 đã dừng');
      expect(report.note, contains('chạy lại'));
      expect(report.issues.single.summary, contains('khác mong đợi'));
      for (final value in [
        'flutter test',
        'Staging',
        'abc123',
        'test.log',
        'failure.png',
        'Expected: true',
        'Actual: false',
        'exit code 1',
      ]) {
        expect(report.copyText, contains(value));
      }
    },
  );
  test('missing log still yields a task without claiming a cause', () async {
    final report = await service.build([
      sample(RunStatus.failed),
    ], (_) async => throw StateError('unreadable'));
    expect(report.issues.single.summary, contains('Chưa đủ dữ liệu'));
    expect(report.issues.single.evidence, contains('Không đọc được log'));
  });
  test('strips terminal escapes and bounds evidence', () async {
    final report = await service.build([
      sample(RunStatus.failed),
    ], (_) async => '\x1b[31mError: ${'x' * 3000}\x1b[0m');
    expect(report.issues.single.evidence, startsWith('Error:'));
    expect(report.issues.single.evidence, isNot(contains('\x1b')));
    expect(report.issues.single.evidence.length, lessThan(1810));
  });
  test('explains device validation and timeout using log evidence', () async {
    final device = await service.build([
      sample(RunStatus.failed),
    ], (_) async => 'Suite cần thiết bị nhưng chưa chọn thiết bị.');
    expect(device.issues.single.summary, contains('chip Thiết bị'));
    final timeout = await service.build([
      sample(RunStatus.failed),
    ], (_) async => 'Timeout 30000ms exceeded');
    expect(timeout.issues.single.summary, contains('quá thời gian'));
  });
  test(
    'all pass, empty and incomplete runs have distinct conclusions',
    () async {
      final pass = await service.build([
        sample(RunStatus.passed),
      ], (_) async => '');
      expect(pass.issues, isEmpty);
      expect(pass.note, contains('Không phát hiện lỗi'));
      final empty = await service.build([], (_) async => '');
      expect(empty.note, contains('Chưa có kết quả'));
      final pending = await service.build([
        sample(RunStatus.running),
      ], (_) async => '');
      expect(pending.note, contains('chưa hoàn tất'));
    },
  );
}
