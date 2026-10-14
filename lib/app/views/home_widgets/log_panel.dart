part of '../home_view.dart';

class _LogPanel extends StatelessWidget {
  const _LogPanel();

  HomeController get controller => Get.find<HomeController>();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Expanded(
                  child: _PanelTitle(
                    icon: Icons.receipt_long_outlined,
                    title: 'Log',
                  ),
                ),
                Obx(() {
                  final code = controller.runner.exitCode.value;
                  if (code == null) return const SizedBox.shrink();

                  return _MetaChip(
                    icon: code == 0
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    label: 'Thoát $code',
                  );
                }),
                // Selection only reaches the rows on screen now that the log
                // is a lazy list, so copying all of it gets its own button.
                Obx(
                  () => IconButton(
                    key: const Key('copy-home-log'),
                    tooltip: 'Sao chép log',
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.runner.logLines.isEmpty
                        ? null
                        : () => Clipboard.setData(
                            ClipboardData(
                              text: controller.runner.logLines.join('\n'),
                            ),
                          ),
                    icon: const Icon(Icons.copy_all_outlined, size: 17),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _HudCardShell(
                  padding: const EdgeInsets.all(12),
                  child: Obx(
                    () => _LogLines(
                      lines: controller.runner.logLines.toList(),
                      emptyLabel: 'Chưa có output',
                      emptyStyle: AppCyberTheme.dataTextStyle(
                        color: AppCyberTheme.textMuted,
                      ),
                      style: AppCyberTheme.dataTextStyle(
                        size: 12,
                        color: AppCyberTheme.palette.hasGlow
                            ? const Color(0xFFD9EBFF)
                            : AppCyberTheme.textPrimary,
                      ).copyWith(height: 1.35),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
