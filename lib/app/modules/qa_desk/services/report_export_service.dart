import 'dart:convert';
import 'dart:io';

import '../models/qa_models.dart';

enum ReportFormat { html, junit, json }

class ReportExportService {
  const ReportExportService();

  Future<void> export({
    required RunBatchSummary batch,
    required List<HistoricalSuiteRun> runs,
    required ReportFormat format,
    required String outputPath,
  }) async {
    final content = format == ReportFormat.junit
        ? await _junit(batch, runs)
        : switch (format) {
            ReportFormat.html => _html(batch, runs),
            ReportFormat.json => _json(batch, runs),
            ReportFormat.junit => throw StateError('Handled above'),
          };
    await File(outputPath).writeAsString(content, flush: true);
  }

  Future<String> readLog(String? logPath, {int maxCharacters = 300000}) async {
    if (logPath == null || logPath.isEmpty) return 'Không có raw log.';
    final file = File(logPath);
    if (!await file.exists()) return 'Raw log không còn tồn tại: $logPath';
    final value = await file.readAsString();
    if (value.length <= maxCharacters) return value;
    return '${value.substring(0, maxCharacters)}\n\n[Log đã được cắt bớt]';
  }

  String _json(RunBatchSummary batch, List<HistoricalSuiteRun> runs) {
    return '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 1, 'batch': _batchJson(batch), 'runs': runs.map(_runJson).toList()})}\n';
  }

  Future<String> _junit(
    RunBatchSummary batch,
    List<HistoricalSuiteRun> runs,
  ) async {
    final duration = runs.fold<double>(
      0,
      (sum, run) => sum + (run.duration?.inMilliseconds ?? 0) / 1000,
    );
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<testsuite name="Fiza QA Desk ${_xml(batch.id)}" '
        'tests="${runs.length}" failures="${batch.failed}" '
        'skipped="${batch.cancelled}" time="${duration.toStringAsFixed(3)}">',
      );
    for (final run in runs) {
      buffer.writeln(
        '  <testcase classname="${_xml(run.sourceName)}" '
        'name="${_xml(run.suiteName)}" '
        'time="${((run.duration?.inMilliseconds ?? 0) / 1000).toStringAsFixed(3)}">',
      );
      if (run.status == RunStatus.failed) {
        buffer.writeln(
          '    <failure message="Exit code ${run.exitCode ?? 'unknown'}">'
          '${_xml(run.command)}</failure>',
        );
      } else if (run.status == RunStatus.cancelled) {
        buffer.writeln('    <skipped message="Cancelled" />');
      }
      final log = await readLog(run.logPath, maxCharacters: 100000);
      buffer.writeln('    <system-out>${_xml(log)}</system-out>');
      buffer.writeln('  </testcase>');
    }
    buffer.writeln('</testsuite>');
    return buffer.toString();
  }

  String _html(RunBatchSummary batch, List<HistoricalSuiteRun> runs) {
    final rows = runs.map((run) {
      final color = switch (run.status) {
        RunStatus.passed => '#15803d',
        RunStatus.failed => '#b91c1c',
        RunStatus.cancelled => '#b45309',
        _ => '#475569',
      };
      return '''
<tr>
  <td>${_htmlEscape(run.sourceName)}</td>
  <td>${_htmlEscape(run.suiteName)}</td>
  <td style="color:$color;font-weight:700">${run.status.name}</td>
  <td>${_duration(run.duration)}</td>
  <td>${_htmlEscape(run.environmentName ?? '--')}</td>
  <td><code>${_htmlEscape(run.gitCommit ?? '--')}</code></td>
  <td><code>${_htmlEscape(run.logPath ?? '--')}</code></td>
</tr>''';
    }).join();
    return '''<!doctype html>
<html lang="vi"><head><meta charset="utf-8"><title>Fiza QA Report</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:32px;color:#0f172a;background:#f8fafc}
.summary{display:flex;gap:12px;margin:20px 0}.metric{background:white;border:1px solid #e2e8f0;border-radius:12px;padding:14px 20px}
table{width:100%;border-collapse:collapse;background:white}th,td{text-align:left;padding:10px;border-bottom:1px solid #e2e8f0;font-size:13px}th{background:#f1f5f9}code{font-size:11px}
</style></head><body>
<h1>Fiza QA Desk Report</h1><p>Batch ${_htmlEscape(batch.id)} • ${_htmlEscape(batch.startedAt.toIso8601String())}</p>
<div class="summary"><div class="metric">Total <b>${batch.total}</b></div><div class="metric">Passed <b>${batch.passed}</b></div><div class="metric">Failed <b>${batch.failed}</b></div><div class="metric">Cancelled <b>${batch.cancelled}</b></div></div>
<table><thead><tr><th>Source</th><th>Suite</th><th>Status</th><th>Duration</th><th>Environment</th><th>Commit</th><th>Raw log</th></tr></thead><tbody>$rows</tbody></table>
</body></html>''';
  }
}

Map<String, Object?> _batchJson(RunBatchSummary batch) => {
  'id': batch.id,
  'startedAt': batch.startedAt.toIso8601String(),
  'finishedAt': batch.finishedAt?.toIso8601String(),
  'status': batch.status.name,
  'total': batch.total,
  'passed': batch.passed,
  'failed': batch.failed,
  'cancelled': batch.cancelled,
};

Map<String, Object?> _runJson(HistoricalSuiteRun run) => {
  'id': run.runId,
  'sourceId': run.sourceId,
  'sourceName': run.sourceName,
  'suiteId': run.suiteId,
  'suiteName': run.suiteName,
  'status': run.status.name,
  'command': run.command,
  'startedAt': run.startedAt.toIso8601String(),
  'finishedAt': run.finishedAt?.toIso8601String(),
  'durationMs': run.duration?.inMilliseconds,
  'exitCode': run.exitCode,
  'environment': run.environmentName,
  'deviceId': run.deviceId,
  'gitBranch': run.gitBranch,
  'gitCommit': run.gitCommit,
  'gitDirty': run.gitDirty,
  'logPath': run.logPath,
  'screenshotPath': run.screenshotPath,
};

String _duration(Duration? value) {
  if (value == null) return '--';
  return '${(value.inMilliseconds / 1000).toStringAsFixed(2)}s';
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _htmlEscape(String value) => const HtmlEscape().convert(value);
