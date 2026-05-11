part of '../home_view.dart';

class _MainPanel extends StatelessWidget {
  const _MainPanel();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Expanded(child: _FlowPanel()),
        SizedBox(height: 16),
        SizedBox(height: 280, child: _LogPanel()),
      ],
    );
  }
}
