import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/qa_workspace_controller.dart';
import '../models/qa_models.dart';
import '../services/qa_desk_runtime.dart';
import '../theme/qa_tokens.dart';
import '../widgets/qa_widgets.dart';
import 'qa_desk_view.dart';

/// QA Desk's run, seen from the AMC shell.
///
/// Closing QA Desk does not stop a run; this keeps it in sight while the user
/// is back on the release screen, then holds the result until they open QA
/// Desk to read it. Nothing shows until QA Desk has been used.
class QaShellStatus extends StatelessWidget {
  const QaShellStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<QaDeskRuntime?>(
      valueListenable: QaDeskRuntime.currentNotifier,
      builder: (context, runtime, _) => runtime == null
          ? const SizedBox.shrink()
          : QaShellRunChip(
              controller: runtime.controller,
              seenBatch: runtime.seenBatch,
              onTap: () => showQaDesk(context),
            ),
    );
  }
}

/// The chip itself: progress while running, the result until it is seen.
class QaShellRunChip extends StatelessWidget {
  const QaShellRunChip({
    super.key,
    required this.controller,
    required this.seenBatch,
    required this.onTap,
  });

  final QaWorkspaceController controller;
  final ValueListenable<String?> seenBatch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, seenBatch]),
      builder: (context, _) {
        final runs = controller.runs;
        final running = controller.isRunning;
        if (runs.isEmpty ||
            (!running && seenBatch.value == runs.first.batchId)) {
          return const SizedBox.shrink();
        }
        final tokens = QaTokens.of(context);
        final failed = runs
            .where((run) => run.status == RunStatus.failed)
            .length;
        final passed = runs
            .where((run) => run.status == RunStatus.passed)
            .length;
        final done = runs
            .where(
              (run) =>
                  run.status != RunStatus.queued &&
                  run.status != RunStatus.running,
            )
            .length;
        final status = running
            ? RunStatus.running
            : failed > 0
            ? RunStatus.failed
            : passed < runs.length
            ? RunStatus.cancelled
            : RunStatus.passed;
        final color = tokens.status(status);
        final label = running
            ? 'QA $done/${runs.length}${failed > 0 ? ' · $failed lỗi' : ''}'
            : 'QA xong · $passed/${runs.length} qua';

        return Tooltip(
          message: running ? 'QA Desk đang chạy' : 'Mở kết quả QA Desk',
          child: Material(
            key: const Key('qa-shell-status'),
            color: color.withValues(alpha: 0.12),
            shape: StadiumBorder(
              side: BorderSide(color: color.withValues(alpha: 0.45)),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (running)
                      SizedBox.square(
                        dimension: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    else
                      QaStatusIcon(status: status, size: 15),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontFeatures: QaTokens.tabular,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
