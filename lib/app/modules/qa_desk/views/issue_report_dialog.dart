import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/module_widgets.dart';
import '../models/qa_models.dart';
import '../services/issue_report_service.dart';
import '../theme/qa_tokens.dart';
import '../widgets/qa_widgets.dart';

/// One suggested task per failed suite, ready to paste into a tracker.
Future<void> showIssueReport(
  BuildContext context,
  Future<IssueReport> report,
) => showDialog<void>(
  context: context,
  builder: (_) => IssueReportDialog(report: report),
);

class IssueReportDialog extends StatelessWidget {
  const IssueReportDialog({super.key, required this.report});

  final Future<IssueReport> report;

  Future<void> _copy(BuildContext context, String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        showQaMessage(context, 'Đã copy. Dán vào task để dùng.');
      }
    } on Object {
      if (context.mounted) {
        showQaMessage(
          context,
          'Không copy được. Bạn có thể chọn và copy nội dung bên dưới.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<IssueReport>(
    future: report,
    builder: (context, snapshot) {
      final theme = Theme.of(context);
      final tokens = QaTokens.of(context);
      final data = snapshot.data;
      return AlertDialog(
        key: const Key('qa-issue-report'),
        title: const Text('Báo cáo issue'),
        content: SizedBox(
          width: 700,
          child: snapshot.hasError
              ? const NoticeBox(
                  text: 'Không tải được báo cáo. Đóng và mở lại từ Kết quả.',
                  tone: NoticeTone.danger,
                )
              : data == null
              ? const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          QaTag(
                            label: '${data.count(RunStatus.passed)} qua',
                            color: tokens.status(RunStatus.passed),
                          ),
                          QaTag(
                            label: '${data.count(RunStatus.failed)} lỗi',
                            color: tokens.status(RunStatus.failed),
                          ),
                          QaTag(
                            label: '${data.count(RunStatus.cancelled)} đã dừng',
                            color: tokens.status(RunStatus.cancelled),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(data.note, style: theme.textTheme.bodyMedium),
                      if (data.runs.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        SelectableText(
                          'Lượt chạy: ${data.runs.first.batchId}',
                          style: tokens.mono(size: 11, color: tokens.muted),
                        ),
                      ],
                      for (final issue in data.issues) ...[
                        const SizedBox(height: 14),
                        ModuleCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const QaStatusIcon(status: RunStatus.failed),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      issue.title,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _copy(context, issue.taskText),
                                    icon: const Icon(Icons.copy, size: 15),
                                    label: const Text('Copy task'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(issue.summary),
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: Text(
                                  'Nội dung task & bằng chứng',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: tokens.muted,
                                  ),
                                ),
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: tokens.well,
                                      borderRadius: BorderRadius.circular(
                                        QaTokens.radius,
                                      ),
                                    ),
                                    child: SelectableText(
                                      issue.taskText,
                                      style: tokens.mono(size: 11.5),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          if (data != null && data.runs.isNotEmpty)
            FilledButton.icon(
              key: const Key('qa-copy-report'),
              onPressed: () => _copy(context, data.copyText),
              icon: const Icon(Icons.copy, size: 17),
              label: const Text('Copy báo cáo'),
            ),
        ],
      );
    },
  );
}
