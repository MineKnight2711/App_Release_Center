import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/safe_controller.dart';
import '../services/safe_sounds.dart';
import '../widgets/safe_metal.dart';
import 'safe_dialogs.dart';
import 'safe_door.dart';
import 'safe_interior.dart';

/// Opens the safe as a full page over the shell.
Future<void> showSafe(BuildContext context, {SafeController? controller}) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SafeView(controller: controller)),
    );

/// The safe's page: the door while it is shut, the inside once it opens.
///
/// One animation runs the whole opening (handle, bolts, door, the move
/// inside) forwards when the safe opens and backwards when it locks, so
/// locking from anywhere, including the idle timer, plays the door shut.
class SafeView extends StatefulWidget {
  const SafeView({super.key, this.controller, this.sounds});

  /// Injected by the tests; left null the page uses the app-wide safe.
  final SafeController? controller;

  /// Injected by the tests; left null the page uses the app-wide sounds.
  final SafeSounds? sounds;

  @override
  State<SafeView> createState() => _SafeViewState();
}

class _SafeViewState extends State<SafeView>
    with SingleTickerProviderStateMixin {
  late final SafeController _safe = widget.controller ?? SafeController.shared;
  late final SafeSounds _sounds = widget.sounds ?? SafeSounds.shared;
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
    reverseDuration: const Duration(milliseconds: 900),
    // Coming back to a safe left open skips straight to the inside.
    value: _safe.isOpen ? 1 : 0,
  );
  late final Animation<double> _interiorFade = CurvedAnimation(
    parent: _reveal,
    curve: const Interval(0.72, 1, curve: Curves.easeOut),
  );
  late final Animation<double> _interiorScale = Tween(
    begin: 0.96,
    end: 1.0,
  ).animate(_interiorFade);
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _safe.addListener(_sync);
    _reveal.addStatusListener((_) {
      if (mounted) setState(() {});
    });
    unawaited(_safe.load());
    unawaited(_sounds.load());
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _safe.removeListener(_sync);
    unawaited(_safe.pageClosed());
    _reveal.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool get _reducedMotion => MediaQuery.of(context).disableAnimations;

  void _sync() {
    if (!mounted) return;
    final open = _safe.isOpen;
    if (open &&
        _reveal.value < 1 &&
        _reveal.status != AnimationStatus.forward) {
      // Timed to the opening: latch, handle, bolts, then the door.
      _sounds.play(SafeSound.unlock);
      if (_reducedMotion) {
        _reveal.value = 1;
      } else {
        _reveal.forward();
      }
    } else if (!open &&
        _reveal.value > 0 &&
        _reveal.status != AnimationStatus.reverse) {
      _sounds.play(SafeSound.lock);
      if (_reducedMotion) {
        _reveal.value = 0;
      } else {
        _reveal.reverse();
      }
    }
    setState(() {});
  }

  /// Any key counts as using the safe; Ctrl/⌘+L locks it, Ctrl/⌘+F searches.
  bool _onKey(KeyEvent event) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    _safe.touch();
    if (event is! KeyDownEvent || !_safe.isOpen) return false;
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isMetaPressed || keyboard.isControlPressed;
    if (!command) return false;
    if (event.logicalKey == LogicalKeyboardKey.keyL) {
      unawaited(_safe.lock());
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      _searchFocus.requestFocus();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steel = SafeSteel.of(context);
    final open = _safe.isOpen;
    final shut = _reveal.status == AnimationStatus.dismissed;
    final fullyOpen = open && _reveal.status == AnimationStatus.completed;
    final narrow = MediaQuery.sizeOf(context).width < 640;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              open ? Icons.lock_open_rounded : Icons.lock_rounded,
              size: 20,
              color: open
                  ? SafeSteel.ledGreen
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text('Két sắt', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          ListenableBuilder(
            listenable: _sounds,
            builder: (context, _) => IconButton(
              key: const Key('safe-sounds'),
              tooltip: _sounds.enabled
                  ? 'Tắt âm thanh két'
                  : 'Bật âm thanh két',
              onPressed: () => _sounds.setEnabled(!_sounds.enabled),
              icon: Icon(
                _sounds.enabled
                    ? Icons.volume_up_outlined
                    : Icons.volume_off_outlined,
              ),
            ),
          ),
          if (open) ...[
            if (_safe.isSaving)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            _Countdowns(safe: _safe, compact: narrow),
            IconButton(
              tooltip: 'Cài đặt két',
              onPressed: () => showSafeSettings(context, _safe),
              icon: const Icon(Icons.settings_outlined),
            ),
            const SizedBox(width: 4),
            if (narrow)
              IconButton.filledTonal(
                key: const Key('safe-lock'),
                tooltip: 'Khoá két',
                onPressed: () => _safe.lock(),
                icon: const Icon(Icons.lock_rounded, size: 18),
              )
            else
              FilledButton.tonalIcon(
                key: const Key('safe-lock'),
                onPressed: () => _safe.lock(),
                icon: const Icon(Icons.lock_rounded, size: 18),
                label: const Text('Khoá két'),
              ),
          ] else
            const Tooltip(
              message:
                  'Nội dung két được mã hoá AES-256-GCM bằng khoá sinh từ mã két '
                  '(Argon2id). Mã két không được lưu; quên mã là mất dữ liệu.',
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.shield_outlined),
              ),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _safe.touch(),
        onPointerHover: (_) => _safe.touch(),
        onPointerSignal: (_) => _safe.touch(),
        child: DecoratedBox(
          // The room the safe stands in.
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.2),
              radius: 1.1,
              colors: [
                steel.dark ? const Color(0xFF262C33) : const Color(0xFFF1F3F5),
                theme.scaffoldBackgroundColor,
              ],
            ),
          ),
          child: Stack(
            children: [
              if (!shut)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !fullyOpen,
                    child: FadeTransition(
                      opacity: _interiorFade,
                      child: ScaleTransition(
                        scale: _interiorScale,
                        child: SafeInterior(
                          safe: _safe,
                          searchFocus: _searchFocus,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_reveal.status != AnimationStatus.completed)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !shut,
                    child: RepaintBoundary(
                      child: SafeDoorScene(
                        controller: _safe,
                        reveal: _reveal,
                        sounds: _sounds,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two clocks that matter while the safe is open: when it locks itself
/// and when the clipboard is wiped.
class _Countdowns extends StatefulWidget {
  const _Countdowns({required this.safe, this.compact = false});

  final SafeController safe;

  /// Only the auto-lock clock, for a narrow window.
  final bool compact;

  @override
  State<_Countdowns> createState() => _CountdownsState();
}

class _CountdownsState extends State<_Countdowns> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _clock(Duration left) {
    final seconds = left.inSeconds.clamp(0, 359999);
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final lockAt = widget.safe.autoLockAt;
    final wipeAt = widget.safe.clipboardClearAt;

    Widget chip(IconData icon, String text, String tooltip, Color color) =>
        Tooltip(
          message: tooltip,
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.compact && wipeAt != null && wipeAt.isAfter(now))
          chip(
            Icons.content_paste_off_rounded,
            _clock(wipeAt.difference(now)),
            'Clipboard sẽ được xoá khi hết giờ',
            theme.colorScheme.tertiary,
          ),
        if (lockAt != null)
          chip(
            Icons.timer_outlined,
            _clock(lockAt.difference(now)),
            'Két tự khoá khi hết giờ không dùng · Ctrl/⌘+L để khoá ngay',
            lockAt.difference(now) < const Duration(seconds: 30)
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
      ],
    );
  }
}
