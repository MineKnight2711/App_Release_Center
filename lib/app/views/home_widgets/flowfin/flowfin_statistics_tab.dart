part of '../../home_view.dart';

class _FlowFinStatisticsTab extends StatelessWidget {
  const _FlowFinStatisticsTab();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<FlowFinController>();

    return Obx(() {
      final timeline = controller.timeline.value;
      final breakdown = controller.breakdown.value;

      return _FlowFinTabScaffold(
        icon: Icons.insights_outlined,
        title: 'Statistics · this month',
        loading: controller.isLoadingStats.value,
        error: controller.statsError.value,
        actions: [
          _FlowFinDropdown<String>(
            label: 'Breakdown',
            value: controller.breakdownKind.value,
            width: 150,
            fieldKey: const Key('flowfin-breakdown-kind'),
            items: const [
              DropdownMenuItem(value: 'expense', child: Text('Expense')),
              DropdownMenuItem(value: 'income', child: Text('Income')),
            ],
            onChanged: (value) =>
                controller.setBreakdownKind(value ?? 'expense'),
          ),
          OutlinedButton.icon(
            key: const Key('flowfin-stats-refresh'),
            onPressed: controller.loadStats,
            icon: const Icon(Icons.refresh_outlined, size: 16),
            label: const Text('Refresh'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (timeline != null) _FlowFinTimelineChart(timeline: timeline),
            const SizedBox(height: 18),
            if (breakdown != null) _FlowFinBreakdownList(breakdown: breakdown),
            if (timeline == null && breakdown == null)
              const _FlowFinEmpty(
                icon: Icons.insights_outlined,
                message: 'No statistics loaded yet.',
              ),
          ],
        ),
      );
    });
  }
}

/// Daily income and expense as paired bars. Deliberately hand-drawn rather
/// than pulling in a charting package for one view.
class _FlowFinTimelineChart extends StatelessWidget {
  const _FlowFinTimelineChart({required this.timeline});

  final FlowFinTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final points = timeline.points;
    if (points.isEmpty) {
      return const _FlowFinEmpty(
        icon: Icons.show_chart_outlined,
        message: 'No activity in this period.',
      );
    }

    var peak = 0;
    for (final point in points) {
      peak = [peak, point.incomeMinor, point.expenseMinor].reduce(
        (a, b) => a > b ? a : b,
      );
    }
    if (peak <= 0) peak = 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _PanelTitle(
              icon: Icons.show_chart_outlined,
              title: 'Daily flow',
            ),
            const SizedBox(width: 12),
            _FlowFinLegendDot(
              color: AppCyberTheme.neonGreen,
              label: 'Income',
            ),
            const SizedBox(width: 10),
            const _FlowFinLegendDot(color: Colors.redAccent, label: 'Expense'),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 160,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: points
                  .map((point) => _FlowFinTimelineBar(point: point, peak: peak))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _FlowFinTimelineBar extends StatelessWidget {
  const _FlowFinTimelineBar({required this.point, required this.peak});

  final FlowFinTimelinePoint point;
  final int peak;

  @override
  Widget build(BuildContext context) {
    const maxHeight = 118.0;
    final incomeHeight = maxHeight * (point.incomeMinor / peak);
    final expenseHeight = maxHeight * (point.expenseMinor / peak);

    return Tooltip(
      message:
          '${point.key}\n'
          'Income ${FlowFinMoney.format(point.incomeMinor)}\n'
          'Expense ${FlowFinMoney.format(point.expenseMinor)}\n'
          'Net ${FlowFinMoney.format(point.netMinor, withSign: true)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _bar(incomeHeight, AppCyberTheme.neonGreen),
                const SizedBox(width: 2),
                _bar(expenseHeight, Colors.redAccent),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 26,
              child: Text(
                _shortLabel,
                textAlign: TextAlign.center,
                style: AppCyberTheme.dataTextStyle(
                  size: 8.5,
                  color: AppCyberTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(double height, Color color) {
    return Container(
      width: 10,
      height: height.isFinite && height > 0 ? height : 1,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
      ),
    );
  }

  /// `2026-09-07` reads as `07`; anything else is shown whole.
  String get _shortLabel {
    final parts = point.key.split('-');
    return parts.length == 3 ? parts.last : point.key;
  }
}

class _FlowFinLegendDot extends StatelessWidget {
  const _FlowFinLegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppCyberTheme.dataTextStyle(
            size: 10.5,
            color: AppCyberTheme.textMuted,
          ),
        ),
      ],
    );
  }
}

class _FlowFinBreakdownList extends StatelessWidget {
  const _FlowFinBreakdownList({required this.breakdown});

  final FlowFinBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    if (breakdown.items.isEmpty) {
      return const _FlowFinEmpty(
        icon: Icons.donut_small_outlined,
        message: 'Nothing to break down in this period.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _PanelTitle(
              icon: Icons.donut_small_outlined,
              title: 'By category',
            ),
            const Spacer(),
            Text(
              FlowFinMoney.format(breakdown.totalMinor),
              style: AppCyberTheme.dataTextStyle(
                size: 12,
                color: AppCyberTheme.textPrimary,
                weight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...breakdown.items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        overflow: TextOverflow.ellipsis,
                        style: AppCyberTheme.dataTextStyle(
                          size: 12,
                          color: AppCyberTheme.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${FlowFinMoney.format(item.amountMinor)}  ·  '
                      '${item.percent.toStringAsFixed(1)}%  ·  '
                      '${item.transactionCount}',
                      style: AppCyberTheme.dataTextStyle(
                        size: 11,
                        color: AppCyberTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (item.percent / 100).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: AppCyberTheme.lineBlue.withValues(
                      alpha: 0.35,
                    ),
                    valueColor: AlwaysStoppedAnimation(
                      _flowFinParseColor(item.color, AppCyberTheme.electricBlue),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
