import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Decides how long a frame nobody is interacting with has to wait.
///
/// Kept apart from [PacedFramesBinding] so the rule can be tested without
/// replacing the test binding.
class FramePacer {
  FramePacer({
    this.unattendedInterval = const Duration(microseconds: 33334),
    this.inputGrace = const Duration(seconds: 1),
  });

  /// Spacing between frames that only serve a running animation.
  final Duration unattendedInterval;

  /// How long after input frames stay at the display's own rate. Long enough
  /// to cover the fling that follows a scroll gesture.
  final Duration inputGrace;

  Duration? _lastFrameAt;
  Duration? _lastInputAt;

  void frameStarted(Duration now) => _lastFrameAt = now;

  void inputReceived(Duration now) => _lastInputAt = now;

  /// How long a frame requested at [now] should be held; zero draws it now.
  Duration delayFor(Duration now) {
    final lastInput = _lastInputAt;
    if (lastInput != null && now - lastInput < inputGrace) {
      return Duration.zero;
    }
    final lastFrame = _lastFrameAt;
    if (lastFrame == null) return Duration.zero;
    final wait = unattendedInterval - (now - lastFrame);
    return wait.isNegative ? Duration.zero : wait;
  }
}

/// Holds frames that only feed an animation to about 30 per second.
///
/// The desktop embedders redraw the whole window for every frame, so a single
/// spinner on a 240 Hz panel re-rasterised every panel 240 times a second. On
/// a laptop's integrated GPU that was enough to keep it saturated through a
/// release run, until the machine throttled and the whole app lagged.
/// Frames that answer the pointer or keyboard are never held, so scrolling,
/// dragging and typing keep the display's full rate.
class PacedFramesBinding extends WidgetsFlutterBinding {
  PacedFramesBinding._();

  static bool _created = false;

  /// Use in place of [WidgetsFlutterBinding.ensureInitialized].
  static WidgetsBinding ensureInitialized() {
    if (!_created) {
      _created = true;
      PacedFramesBinding._();
    }
    return WidgetsBinding.instance;
  }

  final _clock = Stopwatch()..start();
  final _pacer = FramePacer();
  Timer? _held;

  @override
  void initInstances() {
    super.initInstances();
    HardwareKeyboard.instance.addHandler(_noteKey);
  }

  @override
  void handlePointerEvent(PointerEvent event) {
    _noteInput();
    super.handlePointerEvent(event);
  }

  bool _noteKey(KeyEvent event) {
    _noteInput();
    return false;
  }

  void _noteInput() {
    _pacer.inputReceived(_clock.elapsed);
    final held = _held;
    if (held == null) return;
    // Whatever answers this input should not wait out an animation's slot.
    held.cancel();
    _held = null;
    super.scheduleFrame();
  }

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    // This frame serves anything that was being held for it.
    _held?.cancel();
    _held = null;
    _pacer.frameStarted(_clock.elapsed);
    super.handleBeginFrame(rawTimeStamp);
  }

  @override
  void scheduleFrame() {
    if (_held != null || hasScheduledFrame) return;
    final delay = _pacer.delayFor(_clock.elapsed);
    if (delay == Duration.zero) {
      super.scheduleFrame();
      return;
    }
    _held = Timer(delay, () {
      _held = null;
      super.scheduleFrame();
    });
  }
}
