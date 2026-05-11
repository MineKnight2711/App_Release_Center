part of '../home_view.dart';

class _LogPanel extends StatefulWidget {
  const _LogPanel();

  @override
  State<_LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<_LogPanel> {
  final _scrollController = ScrollController();

  HomeController get controller => Get.find<HomeController>();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Expanded(
                  child: _PanelTitle(icon: Icons.receipt_long, title: 'Log'),
                ),
                Obx(() {
                  final code = controller.runner.exitCode.value;
                  if (code == null) return const SizedBox.shrink();

                  return _MetaChip(
                    icon: code == 0 ? Icons.check_circle : Icons.error,
                    label: 'Exit $code',
                  );
                }),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF101418),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Obx(() {
                final lines = controller.runner.logLines.toList();
                final isRunning = controller.runner.isRunning.value;

                if (isRunning) {
                  _scheduleScrollToBottom();
                }

                if (lines.isEmpty) {
                  return Text(
                    'No output',
                    style: TextStyle(color: colorScheme.outlineVariant),
                  );
                }

                return SingleChildScrollView(
                  controller: _scrollController,
                  child: SelectableText(
                    lines.join('\n'),
                    style: const TextStyle(
                      color: Color(0xFFE6EDF3),
                      fontFamily: 'Consolas',
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      );
    });
  }
}
