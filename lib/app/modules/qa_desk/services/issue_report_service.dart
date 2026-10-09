import '../models/qa_models.dart';

class IssueDraft {
  const IssueDraft({
    required this.run,
    required this.summary,
    required this.evidence,
    this.network,
  });

  final HistoricalSuiteRun run;
  final String summary;
  final String evidence;
  final String? network;

  String get title => '[${run.sourceName}] ${run.suiteName} thất bại';

  String get taskText => [
    title,
    '',
    'Vấn đề: $summary',
    'Tái hiện: Trong QA Desk, chọn suite "${run.suiteName}" của nguồn "${run.sourceName}" và chạy lại.',
    'Lệnh: ${run.command}',
    'Mong đợi: Suite hoàn tất thành công (exit code 0).',
    'Thực tế: Thất bại${run.exitCode == null ? '' : ' (exit code ${run.exitCode})'}.',
    'Môi trường: ${run.environmentName ?? 'Mặc định'}',
    if (network != null) 'Mạng giả lập: $network',
    if (run.deviceId != null)
      'Thiết bị: ${run.deviceName ?? run.deviceId} (${run.deviceId})',
    if (run.gitCommit != null || run.gitBranch != null)
      'Git: ${run.gitBranch ?? 'không rõ branch'} / ${run.gitCommit ?? 'không rõ commit'}${run.gitDirty ? ' (có thay đổi chưa commit)' : ''}',
    'Lượt chạy: ${run.batchId} • ${run.startedAt.toLocal()}',
    '',
    'Bằng chứng (trích log):',
    evidence,
    if (run.logPath != null) '\nLog đầy đủ: ${run.logPath}',
    if (run.screenshotPath != null) 'Screenshot: ${run.screenshotPath}',
  ].join('\n');
}

class IssueReport {
  IssueReport({
    required List<HistoricalSuiteRun> runs,
    required List<IssueDraft> issues,
  }) : runs = List.unmodifiable(runs),
       issues = List.unmodifiable(issues);

  final List<HistoricalSuiteRun> runs;
  final List<IssueDraft> issues;

  int count(RunStatus status) =>
      runs.where((run) => run.status == status).length;
  String get summary =>
      '${count(RunStatus.passed)} đạt • ${count(RunStatus.failed)} lỗi • ${count(RunStatus.cancelled)} đã dừng';
  String get note {
    if (runs.isEmpty) return 'Chưa có kết quả cho lượt chạy này.';
    if (runs.any(
      (run) =>
          run.status == RunStatus.queued || run.status == RunStatus.running,
    )) {
      return 'Lượt chạy chưa hoàn tất. Báo cáo chỉ phản ánh kết quả hiện có.';
    }
    if (count(RunStatus.cancelled) > 0) {
      return 'Có suite đã dừng, cần chạy lại để có kết luận đầy đủ.';
    }
    if (issues.isEmpty) return 'Không phát hiện lỗi trong các suite đã chạy.';
    return 'Mỗi mục gom lỗi của một suite. Diễn giải dựa trên log, cần xác minh nguyên nhân khi xử lý.';
  }

  String get copyText => [
    'Báo cáo test${runs.isEmpty ? '' : ' • ${runs.first.batchId}'}',
    summary,
    note,
    ...issues.map((issue) => '\n---\n${issue.taskText}'),
  ].join('\n');
}

class IssueReportService {
  const IssueReportService();

  Future<IssueReport> build(
    List<HistoricalSuiteRun> runs,
    Future<String> Function(HistoricalSuiteRun) readLog,
  ) async {
    final issues = <IssueDraft>[];
    for (final run in runs.where((run) => run.status == RunStatus.failed)) {
      String log;
      try {
        log = await readLog(run);
      } on Object {
        log =
            'Không đọc được log. Xem lượt này trong Kết quả hoặc chạy lại suite.';
      }
      final clean = log.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
      final lines = clean
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final signal = RegExp(
        r'error|exception|failed|failure|expected:|actual:|timeout|timed out|không thể|chưa|thiếu|lỗi|\[E\]',
        caseSensitive: false,
      );
      final index = lines.indexWhere(
        (line) =>
            signal.hasMatch(line) && !line.startsWith('Failure screenshot:'),
      );
      final start = index < 0
          ? (lines.length > 8 ? lines.length - 8 : 0)
          : index;
      var evidence = lines.skip(start).take(10).join('\n');
      if (evidence.isEmpty) {
        evidence = 'Log trống. Chạy lại suite để thu thập bằng chứng.';
      }
      if (evidence.length > 1800) {
        evidence = '${evidence.substring(0, 1800)}\n…';
      }
      issues.add(
        IssueDraft(
          run: run,
          summary: _explain(clean),
          evidence: evidence,
          network: lines
              .where((line) => line.startsWith('Network simulation: '))
              .firstOrNull
              ?.substring('Network simulation: '.length),
        ),
      );
    }
    return IssueReport(runs: runs, issues: issues);
  }

  String _explain(String log) {
    final text = log.toLowerCase();
    if (text.contains('chưa chọn') && text.contains('thiết bị')) {
      return 'Chưa chọn thiết bị để chạy test. Bấm chip Thiết bị, chọn thiết bị rồi chạy lại.';
    }
    if (text.contains('appium') &&
        (text.contains('chưa') || text.contains('không thể'))) {
      return 'Suite chưa chạy được với Appium. Kiểm tra Appium trong bảng Thiết bị & Appium.';
    }
    if (text.contains('timeoutexception') ||
        text.contains('timed out') ||
        RegExp(r'timeout.*exceeded').hasMatch(text)) {
      return 'Một thao tác chờ quá thời gian cho phép. Kiểm tra bước test và phản hồi của ứng dụng.';
    }
    if (text.contains('expected:') && text.contains('actual:')) {
      return 'Kết quả thực tế khác mong đợi của test. Đối chiếu Expected / Actual trong log.';
    }
    if (text.contains('enoent') ||
        text.contains('not recognized') ||
        text.contains('cannot find module') ||
        text.contains('command not found')) {
      return 'Log cho thấy thiếu lệnh, file hoặc thư viện. Kiểm tra công cụ và dependency của nguồn.';
    }
    if (text.contains('error •') ||
        text.contains('warning •') ||
        text.contains('info •')) {
      return 'Kiểm tra mã nguồn phát hiện vấn đề. Xem file và dòng được ghi trong log.';
    }
    return 'Suite báo thất bại. Chưa đủ dữ liệu để kết luận nguyên nhân; kiểm tra trích log và chạy lại.';
  }
}
