import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../shared/module_widgets.dart';
import '../controllers/qa_workspace_controller.dart';
import '../services/maestro_results.dart';
import '../theme/qa_tokens.dart';
import '../widgets/qa_widgets.dart';

/// Asks before automated scenarios run against production; true when the
/// run may go ahead, which it always may when nothing runs there.
///
/// [count] is how many automated scenarios will run; the ticked ones unless
/// given.
Future<bool> confirmProductionRun(
  BuildContext context,
  QaWorkspaceController controller, {
  int? count,
}) async {
  final environment = controller.appEnvironment;
  count ??= controller.selectedAutomationCount;
  if (count == 0 || !controller.isProductionEnvironment(environment)) {
    return true;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final palette = QaTokens.of(context).palette;
      return AlertDialog(
        key: const Key('qa-production-confirm'),
        icon: Icon(Icons.warning_amber_rounded, color: palette.danger),
        title: Text('Chạy $count kịch bản trên $environment?'),
        content: const SizedBox(
          width: 460,
          child: Text(
            'Đây là môi trường production, dữ liệu thật của khách hàng. QA '
            'Desk chỉ chạy kịch bản chỉ đọc với tài khoản chỉ đọc và chặn các '
            'nút app đã khai cấm, nhưng không nhìn được mọi thứ app sẽ làm. '
            'Chỉ chạy khi bạn chắc kịch bản không thay đổi dữ liệu.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            key: const Key('qa-production-confirm-run'),
            style: FilledButton.styleFrom(backgroundColor: palette.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Chạy trên $environment'),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// The steps an automated scenario went through, beside the screen it
/// failed on.
Future<void> showAutomationSteps(
  BuildContext context, {
  required String title,
  required String detailsPath,
  String? screenshotPath,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      key: const Key('qa-automation-steps'),
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 1000,
        height: 720,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              QaPanelHeader(
                title: title,
                subtitle: 'Các bước QA Desk đã làm',
                trailing: [
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _StepsView(
                  detailsPath: detailsPath,
                  screenshotPath: screenshotPath,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// What `steps.json` holds.
class AutomationDetails {
  const AutomationDetails({required this.steps, this.loginFailed = false});

  final List<FlowStepResult> steps;
  final bool loginFailed;

  static Future<AutomationDetails> read(String path) async {
    final json = jsonDecode(await File(path).readAsString());
    if (json is! Map) return const AutomationDetails(steps: []);
    return AutomationDetails(
      loginFailed: json['loginFailed'] == true,
      steps: [
        for (final item in json['steps'] as List<dynamic>? ?? const [])
          if (item is Map)
            FlowStepResult.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }
}

class _StepsView extends StatefulWidget {
  const _StepsView({required this.detailsPath, this.screenshotPath});

  final String detailsPath;
  final String? screenshotPath;

  @override
  State<_StepsView> createState() => _StepsViewState();
}

class _StepsViewState extends State<_StepsView> {
  late final Future<AutomationDetails> _details = AutomationDetails.read(
    widget.detailsPath,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final palette = tokens.palette;
    final screenshotPath = widget.screenshotPath;
    final screenshot = screenshotPath == null ? null : File(screenshotPath);

    final list = FutureBuilder<AutomationDetails>(
      future: _details,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return NoticeBox(
            text: 'Không đọc được các bước: ${snapshot.error}',
            tone: NoticeTone.danger,
          );
        }
        final details = snapshot.data;
        if (details == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (details.steps.isEmpty) {
          return const QaEmptyState(
            icon: Icons.list_alt,
            title: 'Không có bước nào',
            message:
                'Maestro dừng trước khi chạy bước đầu tiên: xem log để biết '
                'lý do (thường là thiết bị hoặc cài app).',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (details.loginFailed)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: NoticeBox(
                  text:
                      'Lỗi trước khi qua bước đăng nhập: kiểm tra tài khoản '
                      'demo (mật khẩu, bị khoá) hoặc flow đăng nhập trước khi '
                      'nghi app.',
                  tone: NoticeTone.warning,
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: details.steps.length,
                itemBuilder: (context, index) {
                  final step = details.steps[index];
                  final (icon, color) = switch (step.status) {
                    'COMPLETED' => (Icons.check_circle, palette.success),
                    'FAILED' => (Icons.cancel, palette.danger),
                    'SKIPPED' => (Icons.skip_next, tokens.muted),
                    _ => (Icons.radio_button_unchecked, tokens.muted),
                  };
                  return Padding(
                    key: Key('qa-step-result-$index'),
                    padding: EdgeInsets.fromLTRB(step.depth * 22.0, 4, 0, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 17, color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                step.label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: step.failed
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: step.failed ? palette.danger : null,
                                ),
                              ),
                              if (step.error.isNotEmpty)
                                SelectableText(
                                  step.error,
                                  style: tokens.mono(
                                    size: 11.5,
                                    color: palette.danger,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          shortDuration(
                            Duration(milliseconds: step.durationMs),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.muted,
                            fontFeatures: QaTokens.tabular,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );

    if (screenshot == null || !screenshot.existsSync()) return list;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: list),
        const SizedBox(width: 14),
        SizedBox(
          width: 300,
          child: Container(
            decoration: BoxDecoration(
              color: tokens.well,
              borderRadius: BorderRadius.circular(QaTokens.radius),
            ),
            padding: const EdgeInsets.all(8),
            child: Image.file(screenshot, fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }
}
