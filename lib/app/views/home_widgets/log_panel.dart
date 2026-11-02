part of '../home_view.dart';

class _LogPanel extends StatefulWidget {
  const _LogPanel({this.isExpanded = false, this.onToggleExpand});

  final bool isExpanded;
  final VoidCallback? onToggleExpand;

  @override
  State<_LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<_LogPanel> {
  final _filterController = TextEditingController();
  bool _showFilter = false;
  String _filterQuery = '';

  HomeController get controller => Get.find<HomeController>();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
            child: Row(
              children: [
                const _PanelTitle(
                  icon: Icons.receipt_long_outlined,
                  title: 'Log',
                ),
                const SizedBox(width: 8),
                Obx(() {
                  final count = controller.runner.logLines.length;
                  if (count == 0) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppCyberTheme.palette.surfaceHighest.withValues(
                        alpha: 0.7,
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppCyberTheme.palette.line),
                    ),
                    child: Text(
                      '$count dòng',
                      style: AppCyberTheme.dataTextStyle(
                        size: 10,
                        color: AppCyberTheme.textMuted,
                        weight: FontWeight.w700,
                      ),
                    ),
                  );
                }),
                const Spacer(),
                Obx(() {
                  final code = controller.runner.exitCode.value;
                  if (code == null) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _MetaChip(
                      icon: code == 0
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      label: 'Thoát $code',
                      highlighted: code != 0,
                    ),
                  );
                }),
                IconButton(
                  tooltip: _showFilter ? 'Đóng lọc log' : 'Lọc log',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      _showFilter = !_showFilter;
                      if (!_showFilter) {
                        _filterController.clear();
                        _filterQuery = '';
                      }
                    });
                  },
                  icon: Icon(
                    _showFilter
                        ? Icons.filter_alt_off_outlined
                        : Icons.filter_alt_outlined,
                    size: 17,
                    color: _showFilter ? AppCyberTheme.palette.accent : null,
                  ),
                ),
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
                if (widget.onToggleExpand != null)
                  IconButton(
                    tooltip: widget.isExpanded
                        ? 'Thu gọn khung log'
                        : 'Mở rộng khung log',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onToggleExpand,
                    icon: Icon(
                      widget.isExpanded
                          ? Icons.close_fullscreen_outlined
                          : Icons.open_in_full_outlined,
                      size: 16,
                    ),
                  ),
              ],
            ),
          ),
          if (_showFilter)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                controller: _filterController,
                onChanged: (value) => setState(() => _filterQuery = value),
                decoration: InputDecoration(
                  hintText: 'Tìm trong log (vd: error, warning, step)\u2026',
                  prefixIcon: const Icon(Icons.search_outlined, size: 16),
                  suffixIcon: _filterQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Xoá từ khoá',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _filterController.clear();
                            setState(() => _filterQuery = '');
                          },
                          icon: const Icon(Icons.close, size: 15),
                        ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                ),
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
                      filterQuery: _filterQuery,
                      emptyLabel: 'Chưa có output',
                      emptyStyle: AppCyberTheme.dataTextStyle(
                        color: AppCyberTheme.textMuted,
                      ),
                      style: AppCyberTheme.dataTextStyle(
                        size: 12,
                        color: AppCyberTheme.palette.hasGlow
                            ? const Color(0xFFD9EBFF)
                            : AppCyberTheme.textPrimary,
                      ).copyWith(height: 1.38),
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
