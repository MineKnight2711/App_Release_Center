import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'feature_analytics_service.dart';

/// Observe input without consuming it; background/tray timers do not count.
class AnalyticsActivity extends StatefulWidget {
  const AnalyticsActivity({super.key, required this.child});
  final Widget child;
  @override
  State<AnalyticsActivity> createState() => _AnalyticsActivityState();
}

class _AnalyticsActivityState extends State<AnalyticsActivity>
    with WidgetsBindingObserver {
  bool _foreground = true;
  void _active() {
    if (_foreground && Get.isRegistered<FeatureAnalyticsService>()) {
      Get.find<FeatureAnalyticsService>().active();
    }
  }

  bool _key(KeyEvent event) {
    if (event is KeyDownEvent) _active();
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _foreground = state == AppLifecycleState.resumed;
  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Listener(onPointerDown: (_) => _active(), child: widget.child);
}
