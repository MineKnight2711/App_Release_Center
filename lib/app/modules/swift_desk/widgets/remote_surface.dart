import 'dart:async';
import 'dart:io';
import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/swift_desk_runtime.dart';

/// The listener sits inside the fitted video rectangle: letterboxes never
/// generate remote coordinates. Flutter transforms localPosition through the
/// fit/scroll transforms, including when the remote screen is HiDPI.
class RemoteSurface extends StatefulWidget {
  const RemoteSurface({
    super.key,
    required this.runtime,
    required this.renderer,
    this.nativeScale = false,
    this.mapCtrlToCmd = true,
  });
  final SwiftDeskRuntime runtime;
  final RTCVideoRenderer renderer;
  final bool nativeScale, mapCtrlToCmd;
  @override
  State<RemoteSurface> createState() => _RemoteSurfaceState();
}

class _RemoteSurfaceState extends State<RemoteSurface> {
  final focus = FocusNode();
  final _vertical = ScrollController(), _horizontal = ScrollController();
  final heldButtons = <String>{};
  RemotePointer? _pending;
  Timer? _pointerTimer;
  Future<void> _keyTail = Future.value();
  int _inputEpoch = 0;
  late final AppLifecycleListener _lifecycle;
  SwiftDeskRuntime get runtime => widget.runtime;
  void _clearPointer() {
    _pointerTimer?.cancel();
    _pointerTimer = null;
    _pending = null;
  }

  void _release() {
    _inputEpoch++;
    _clearPointer();
    heldButtons.clear();
    unawaited(runtime.releaseViewerInput());
  }

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus) _release();
    });
    _lifecycle = AppLifecycleListener(onInactive: _release, onHide: _release);
  }

  @override
  void didUpdateWidget(RemoteSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mapCtrlToCmd != widget.mapCtrlToCmd ||
        oldWidget.nativeScale != widget.nativeScale) {
      _release();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _release();
    focus.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  RemotePointer _point(Offset value, Size size) => RemotePointer(
    (value.dx / size.width).clamp(0.0, 1.0),
    (value.dy / size.height).clamp(0.0, 1.0),
  );
  void _move(Offset local, Size size) {
    if (!runtime.viewerControl) return;
    _pending = _point(local, size);
    _pointerTimer ??= Timer(const Duration(milliseconds: 16), () {
      _pointerTimer = null;
      final pending = _pending;
      _pending = null;
      if (mounted && pending != null) unawaited(runtime.sendInput(pending));
    });
  }

  void _buttons(PointerEvent event, Size size) {
    if (!runtime.viewerControl) return;
    _clearPointer();
    focus.requestFocus();
    final next = <String>{
      if (event.buttons & kPrimaryMouseButton != 0) 'left',
      if (event.buttons & kSecondaryMouseButton != 0) 'right',
      if (event.buttons & kMiddleMouseButton != 0) 'middle',
    };
    final point = _point(event.localPosition, size);
    for (final button in {...heldButtons, ...next}) {
      if (heldButtons.contains(button) != next.contains(button)) {
        unawaited(
          runtime.sendInput(
            RemoteButton(
              button: button,
              down: next.contains(button),
              x: point.x,
              y: point.y,
            ),
          ),
        );
      }
    }
    heldButtons
      ..clear()
      ..addAll(next);
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (!runtime.viewerControl) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.f12) {
      focus.unfocus();
      _release();
      return KeyEventResult.handled;
    }
    var usage = event.physicalKey.usbHidUsage;
    if (widget.mapCtrlToCmd &&
        runtime.remotePlatform == 'macos' &&
        !Platform.isMacOS) {
      usage = switch (usage) {
        0x700e0 => 0x700e3,
        0x700e3 => 0x700e0,
        0x700e7 => 0x700e4,
        _ => usage,
      };
    }
    try {
      final key = RemoteKey(usage, down: event is! KeyUpEvent);
      final current = runtime.session;
      final epoch = _inputEpoch;
      final paste =
          event is KeyDownEvent &&
          event.physicalKey == PhysicalKeyboardKey.keyV &&
          (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed) &&
          runtime.clipboardEnabled &&
          runtime.settings.flag('clipboardBeforePaste');
      _keyTail = _keyTail.then((_) async {
        if (epoch != _inputEpoch ||
            !identical(current, runtime.session) ||
            !runtime.viewerControl) {
          return;
        }
        if (paste && !await runtime.syncClipboardForPaste()) return;
        if (mounted &&
            focus.hasFocus &&
            epoch == _inputEpoch &&
            identical(current, runtime.session)) {
          await runtime.sendInput(key);
        }
      });
    } on FormatException {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Wrap(
        spacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.tonalIcon(
            onPressed: runtime.allows(RemoteScope.input)
                ? () {
                    if (runtime.viewerControl) {
                      focus.unfocus();
                      _release();
                    } else {
                      focus.requestFocus();
                      runtime.takeControl();
                    }
                  }
                : null,
            icon: Icon(
              runtime.viewerControl
                  ? Icons.pan_tool_outlined
                  : Icons.mouse_outlined,
            ),
            label: Text(
              runtime.viewerControl
                  ? 'Trả điều khiển về AMC (F12)'
                  : 'Bắt đầu điều khiển',
            ),
          ),
          Text(
            runtime.allows(RemoteScope.input)
                ? 'Phím vật lý gửi tới máy đích · F12 để thoát'
                : 'Máy đích chỉ cấp quyền xem',
          ),
        ],
      ),
      const SizedBox(height: 8),
      Expanded(
        child: ColoredBox(
          color: const Color(0xff10191d),
          child: Focus(
            focusNode: focus,
            onKeyEvent: _key,
            child: ValueListenableBuilder<RTCVideoValue>(
              valueListenable: widget.renderer,
              builder: (context, value, _) {
                final width = value.width > 0 ? value.width : 1920.0;
                final height = value.height > 0 ? value.height : 1080.0;
                final ratio = widget.nativeScale
                    ? MediaQuery.devicePixelRatioOf(context)
                    : 1.0;
                final size = Size(width / ratio, height / ratio);
                final video = SizedBox(
                  width: size.width,
                  height: size.height,
                  child: Listener(
                    onPointerHover: (event) => _move(event.localPosition, size),
                    onPointerMove: (event) => _move(event.localPosition, size),
                    onPointerDown: (event) => _buttons(event, size),
                    onPointerUp: (event) => _buttons(event, size),
                    onPointerCancel: (_) => _release(),
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent &&
                          runtime.viewerControl) {
                        GestureBinding.instance.pointerSignalResolver.register(
                          event,
                          (_) {
                            unawaited(
                              runtime.sendInput(
                                RemoteWheel(
                                  event.scrollDelta.dx.clamp(-2400.0, 2400.0),
                                  event.scrollDelta.dy.clamp(-2400.0, 2400.0),
                                ),
                              ),
                            );
                          },
                        );
                      }
                    },
                    child: MouseRegion(
                      cursor: runtime.viewerControl
                          ? SystemMouseCursors.precise
                          : SystemMouseCursors.basic,
                      child: RTCVideoView(
                        widget.renderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      ),
                    ),
                  ),
                );
                if (widget.nativeScale) {
                  return Scrollbar(
                    controller: _vertical,
                    child: SingleChildScrollView(
                      controller: _vertical,
                      child: Scrollbar(
                        controller: _horizontal,
                        child: SingleChildScrollView(
                          controller: _horizontal,
                          scrollDirection: Axis.horizontal,
                          child: video,
                        ),
                      ),
                    ),
                  );
                }
                return Center(
                  child: FittedBox(fit: BoxFit.contain, child: video),
                );
              },
            ),
          ),
        ),
      ),
    ],
  );
}
