part of '../home_view.dart';

class _MainPanel extends StatefulWidget {
  const _MainPanel();

  @override
  State<_MainPanel> createState() => _MainPanelState();
}

class _MainPanelState extends State<_MainPanel> {
  static const double _minFlowHeight = 280;
  static const double _minLogHeight = 200;
  static const double _defaultFlowRatio = 0.64;
  static const double _splitterThickness = 14;

  double _flowRatio = _defaultFlowRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final double splitHeight = (totalHeight - _splitterThickness).clamp(
          0,
          totalHeight,
        );
        final minRatio = (splitHeight <= 0)
            ? 0.5
            : (_minFlowHeight / splitHeight).clamp(0.2, 0.8).toDouble();
        final maxRatio = (splitHeight <= 0)
            ? 0.5
            : (1 - (_minLogHeight / splitHeight)).clamp(0.2, 0.8).toDouble();
        final boundedRatio = _flowRatio
            .clamp(
              minRatio < maxRatio ? minRatio : 0.5,
              minRatio < maxRatio ? maxRatio : 0.5,
            )
            .toDouble();
        final flowHeight = splitHeight * boundedRatio;
        final logHeight = splitHeight - flowHeight;

        return Column(
          children: [
            SizedBox(height: flowHeight, child: const _FlowPanel()),
            SizedBox(
              height: _splitterThickness,
              child: _PanelSplitter(
                axis: Axis.vertical,
                onDelta: (delta) => _onVerticalResize(
                  delta: delta,
                  splitHeight: splitHeight,
                  minRatio: minRatio,
                  maxRatio: maxRatio,
                ),
              ),
            ),
            SizedBox(height: logHeight, child: const _LogPanel()),
          ],
        );
      },
    );
  }

  void _onVerticalResize({
    required double delta,
    required double splitHeight,
    required double minRatio,
    required double maxRatio,
  }) {
    if (splitHeight <= 0) return;
    final ratioDelta = delta / splitHeight;
    final lower = minRatio < maxRatio ? minRatio : 0.5;
    final upper = minRatio < maxRatio ? maxRatio : 0.5;
    final next = (_flowRatio + ratioDelta).clamp(lower, upper).toDouble();
    if (next == _flowRatio) return;
    setState(() {
      _flowRatio = next;
    });
  }
}
