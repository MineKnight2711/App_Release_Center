import 'package:flutter/widgets.dart';

/// Reports reduce-motion to everything below while the window is not active.
///
/// Looping decorations (card pulses, workflow scans, the charge wave) redraw
/// every vsync. Left running while AMC sat behind other windows, they kept a
/// 240 Hz laptop's discrete GPU busy for nothing. They already honour
/// [MediaQueryData.disableAnimations], so this sets it whenever the app is not
/// resumed. Progress values still update; only the decoration stops.
class PauseMotionWhenInactive extends StatefulWidget {
  const PauseMotionWhenInactive({super.key, required this.child});

  final Widget child;

  @override
  State<PauseMotionWhenInactive> createState() =>
      _PauseMotionWhenInactiveState();
}

class _PauseMotionWhenInactiveState extends State<PauseMotionWhenInactive> {
  late final AppLifecycleListener _lifecycle;
  bool _active = _isActive(WidgetsBinding.instance.lifecycleState);

  static bool _isActive(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        final active = _isActive(state);
        if (active != _active) setState(() => _active = active);
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Always wrapped, so a focus change never remounts the app below it.
    return MediaQuery(
      data: media.copyWith(
        disableAnimations: media.disableAnimations || !_active,
      ),
      child: widget.child,
    );
  }
}
