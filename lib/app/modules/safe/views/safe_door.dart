import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/safe_controller.dart';
import '../services/safe_password_tools.dart';
import '../services/safe_sounds.dart';
import '../widgets/safe_metal.dart';
import 'safe_dialogs.dart';

/// How far each part of the opening has got, read off one 0→1 animation so
/// the handle, bolts, door and zoom always stay in step.
class SafeOpening {
  SafeOpening(double t)
    : handle = Curves.easeInOut.transform(_span(t, 0, 0.22)),
      boltsOut = 1 - Curves.easeInOut.transform(_span(t, 0.12, 0.34)),
      swing = Curves.easeInOutCubic.transform(_span(t, 0.3, 0.78)),
      zoom = Curves.easeInCubic.transform(_span(t, 0.7, 1));

  final double handle;
  final double boltsOut;
  final double swing;
  final double zoom;

  static double _span(double t, double begin, double end) =>
      ((t - begin) / (end - begin)).clamp(0.0, 1.0);
}

/// The safe seen from outside: the body, the door with its dial, handle and
/// keypad, and a glimpse of the inside as the door swings.
///
/// Drawn at one design size and scaled to fit, so it keeps its proportions in
/// any window.
class SafeDoorScene extends StatefulWidget {
  const SafeDoorScene({
    super.key,
    required this.controller,
    required this.reveal,
    required this.sounds,
  });

  final SafeController controller;

  /// Clicks as the code is typed, a buzz when it is refused.
  final SafeSounds sounds;

  /// 0 shut, 1 open and zoomed into; owned by the page.
  final Animation<double> reveal;

  static const designSize = Size(560, 840);

  @override
  State<SafeDoorScene> createState() => _SafeDoorSceneState();
}

class _SafeDoorSceneState extends State<SafeDoorScene>
    with TickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );
  final _code = TextEditingController();
  final _confirm = TextEditingController();
  final _codeFocus = FocusNode();
  final _random = math.Random.secure();

  bool _showCode = false;
  double _dialTurns = 0;
  int _typedLength = 0;
  int _confirmLength = 0;
  late int _seenRefusals = widget.controller.refusals;
  Timer? _cooldownTicker;

  SafeController get _safe => widget.controller;

  bool get _reducedMotion => MediaQuery.of(context).disableAnimations;

  @override
  void initState() {
    super.initState();
    _safe.addListener(_onSafeChanged);
    _code.addListener(_onTyped);
    _confirm.addListener(_onConfirmTyped);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_safe.isOpen) _codeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _safe.removeListener(_onSafeChanged);
    _cooldownTicker?.cancel();
    _shake.dispose();
    _spin.dispose();
    _code.dispose();
    _confirm.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _onSafeChanged() {
    if (!mounted) return;
    if (_safe.refusals != _seenRefusals) {
      _seenRefusals = _safe.refusals;
      if (!_reducedMotion) _shake.forward(from: 0);
      widget.sounds.play(SafeSound.denied);
      if (_safe.stage == SafeStage.locked) {
        // Cleared quietly: the buzz says enough.
        _typedLength = 0;
        _code.clear();
        _codeFocus.requestFocus();
      }
    }

    final checking = _safe.stage == SafeStage.unlocking;
    if (checking && !_spin.isAnimating && !_reducedMotion) {
      _spin.repeat();
    } else if (!checking && _spin.isAnimating) {
      // Finish the turn in progress, then rest where a full turn lands.
      _spin.forward().whenComplete(() {
        if (mounted) _spin.value = 0;
      });
    }

    if (_safe.isOpen) {
      // The code has done its job; it does not stay in a text field.
      _typedLength = 0;
      _confirmLength = 0;
      _code.clear();
      _confirm.clear();
      _showCode = false;
    } else if (_safe.stage == SafeStage.locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_safe.isOpen) _codeFocus.requestFocus();
      });
    }

    _cooldownTicker?.cancel();
    if (_safe.cooldownRemaining > Duration.zero) {
      _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _safe.cooldownRemaining == Duration.zero) {
          timer.cancel();
        }
        if (mounted) setState(() {});
      });
    }
    setState(() {});
  }

  /// Every keystroke turns the dial a little, alternating direction like a
  /// combination being dialled. The amount is random so the dial says
  /// nothing about which character was typed.
  void _onTyped() {
    final length = _code.text.length;
    if (length == _typedLength) return;
    final added = length > _typedLength;
    _typedLength = length;
    widget.sounds.play(SafeSound.tick);
    setState(() {
      final step = 0.035 + _random.nextDouble() * 0.11;
      _dialTurns += (length.isEven ? 1 : -1) * (added ? step : step * 0.5);
    });
  }

  void _onConfirmTyped() {
    final length = _confirm.text.length;
    if (length == _confirmLength) return;
    _confirmLength = length;
    widget.sounds.play(SafeSound.tick);
  }

  Future<void> _submit() async {
    if (_safe.stage == SafeStage.unlocking) return;
    if (_safe.stage == SafeStage.uncreated) {
      await _safe.create(_code.text, _confirm.text);
    } else {
      await _safe.unlock(_code.text);
    }
  }

  Future<void> _restore() async {
    final message = await restoreSafeBackup(context, _safe);
    if (message != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final steel = SafeSteel.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 880),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FittedBox(
                child: SizedBox.fromSize(
                  size: SafeDoorScene.designSize,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([widget.reveal, _shake]),
                    builder: (context, door) {
                      final opening = SafeOpening(widget.reveal.value);
                      final shake = _shake.isAnimating
                          ? math.sin(_shake.value * math.pi * 7) *
                                14 *
                                (1 - _shake.value)
                          : 0.0;
                      return Opacity(
                        opacity: 1 - opening.zoom,
                        child: Transform.translate(
                          offset: Offset(shake, 0),
                          child: Transform.scale(
                            scale: 1 + opening.zoom * 0.55,
                            child: _scene(steel, opening),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _scene(SafeSteel steel, SafeOpening opening) {
    const inset = 22.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Shadow on the floor.
        Positioned(
          left: 40,
          right: 40,
          bottom: 4,
          height: 26,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: steel.dark ? 0.6 : 0.3),
                  blurRadius: 24,
                ),
              ],
            ),
          ),
        ),
        // Feet.
        for (final left in [46.0, 470.0])
          Positioned(
            left: left,
            bottom: 14,
            width: 44,
            height: 22,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: steel.body,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(6),
                ),
                border: Border.all(color: steel.bodyEdge),
              ),
            ),
          ),
        // The body, and the dark opening the door closes.
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          bottom: 34,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [steel.bodyEdge, steel.body, steel.body, steel.shadow],
                stops: const [0, 0.25, 0.75, 1],
              ),
              border: Border.all(color: steel.shadow, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            padding: const EdgeInsets.all(inset),
            child: _InteriorGlimpse(light: opening.swing),
          ),
        ),
        // The door, hinged on the left edge of the opening.
        Positioned(
          left: inset - SafeDoorPainter.hingeRoom,
          top: inset,
          right: inset - SafeDoorPainter.boltRoom,
          bottom: 34 + inset,
          child: Transform(
            alignment: Alignment.centerLeft,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0011)
              ..rotateY(-opening.swing * math.pi * 0.47),
            child: IgnorePointer(
              ignoring: opening.swing > 0,
              child: _doorFace(steel, opening),
            ),
          ),
        ),
      ],
    );
  }

  Widget _doorFace(SafeSteel steel, SafeOpening opening) {
    final stage = _safe.stage;
    final creating = stage == SafeStage.uncreated;
    final checking = stage == SafeStage.unlocking;
    final cooldown = _safe.cooldownRemaining;

    final (ledColor, status) = switch (stage) {
      SafeStage.loading => (steel.shadow, 'ĐANG KIỂM TRA…'),
      SafeStage.uncreated => (SafeSteel.ledAmber, 'CHƯA CÓ KÉT · HÃY ĐẶT MÃ'),
      SafeStage.locked when cooldown > Duration.zero => (
        SafeSteel.ledRed,
        'TẠM KHOÁ · ${cooldown.inSeconds + 1}s',
      ),
      SafeStage.locked => (SafeSteel.ledRed, 'ĐÃ KHOÁ'),
      SafeStage.unlocking => (
        SafeSteel.ledAmber,
        creating ? 'ĐANG ĐÚC KHOÁ…' : 'ĐANG DÒ MÃ…',
      ),
      SafeStage.open => (SafeSteel.ledGreen, 'ĐÃ MỞ'),
    };

    return CustomPaint(
      painter: SafeDoorPainter(steel: steel, boltsOut: opening.boltsOut),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SafeDoorPainter.hingeRoom + 46,
          42,
          SafeDoorPainter.boltRoom + 46,
          40,
        ),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: _dialTurns),
                          duration: _reducedMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 260),
                          curve: Curves.easeOutBack,
                          builder: (context, typed, _) => AnimatedBuilder(
                            animation: _spin,
                            builder: (context, _) => SafeDial(
                              size: 188,
                              turns: typed + _spin.value,
                              lit: checking,
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        SafeHandle(
                          size: 108,
                          angle: -opening.handle * math.pi / 2,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const BrassPlate(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          EngravedText(
                            'AMC',
                            size: 18,
                            spacing: 6,
                            color: SafeSteel.brassInk,
                            lip: Color(0x99FFF6D5),
                          ),
                          EngravedText(
                            'KÉT SẮT CÁ NHÂN',
                            size: 9.5,
                            spacing: 3,
                            color: SafeSteel.brassInk,
                            lip: Color(0x99FFF6D5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SafeLed(color: ledColor),
                        const SizedBox(width: 10),
                        Flexible(
                          child: EngravedText(
                            status,
                            size: 11.5,
                            spacing: 2.2,
                            mono: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (stage != SafeStage.loading) ...[
                      _codeField(
                        key: const Key('safe-code'),
                        controller: _code,
                        focusNode: _codeFocus,
                        hint: creating ? 'ĐẶT MÃ KÉT' : 'NHẬP MÃ KÉT',
                        enabled: !checking,
                        onSubmitted: creating
                            ? (_) => FocusScope.of(context).nextFocus()
                            : (_) => _submit(),
                        trailing: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            side: BorderSide.none,
                            shadowColor: Colors.transparent,
                          ),
                          tooltip: _showCode ? 'Ẩn mã' : 'Hiện mã',
                          onPressed: () =>
                              setState(() => _showCode = !_showCode),
                          icon: Icon(
                            _showCode
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 18,
                            color: SafeSteel.lcdDim,
                          ),
                        ),
                      ),
                      if (creating) ...[
                        const SizedBox(height: 8),
                        _codeField(
                          key: const Key('safe-code-confirm'),
                          controller: _confirm,
                          hint: 'NHẬP LẠI MÃ',
                          enabled: !checking,
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 10),
                        ListenableBuilder(
                          listenable: _code,
                          builder: (context, _) => _StrengthGauge(
                            strength: ratePassword(_code.text),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SafeMetalButton(
                        key: const Key('safe-submit'),
                        label: creating ? 'TẠO KÉT' : 'MỞ KÉT',
                        icon: creating
                            ? Icons.lock_reset_rounded
                            : Icons.lock_open_rounded,
                        width: 210,
                        busy: checking,
                        onPressed: cooldown > Duration.zero ? null : _submit,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 30,
                        child: _safe.doorMessage.isEmpty
                            ? null
                            : Text(
                                _safe.doorMessage,
                                key: const Key('safe-door-message'),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: steel.dark
                                      ? const Color(0xFFFF8A8C)
                                      : const Color(0xFFB4232A),
                                  shadows: [
                                    Shadow(
                                      offset: const Offset(0, 1),
                                      color: steel.engravingLip,
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (creating) ...[
              const EngravedText(
                'Mã két không được lưu ở đâu cả.\nQuên mã = mất toàn bộ nội dung két.',
                size: 10.5,
                spacing: 0.4,
                weight: FontWeight.w700,
                textAlign: TextAlign.center,
              ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: checking ? null : _restore,
                child: EngravedText(
                  'KHÔI PHỤC TỪ BẢN SAO LƯU…',
                  size: 10,
                  spacing: 1.6,
                  color: steel.dark
                      ? const Color(0xFF0E2236)
                      : const Color(0xFF1F3B5C),
                ),
              ),
            ] else
              const EngravedText(
                'AES-256-GCM · ARGON2ID · CHỈ LƯU TRÊN MÁY NÀY',
                size: 9,
                spacing: 1.6,
                mono: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _codeField({
    required Key key,
    required TextEditingController controller,
    required String hint,
    required bool enabled,
    required ValueChanged<String> onSubmitted,
    FocusNode? focusNode,
    Widget? trailing,
  }) {
    return SizedBox(
      width: 330,
      child: LcdPanel(
        glow: enabled,
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: [
            const Icon(Icons.key_rounded, size: 16, color: SafeSteel.lcdDim),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: key,
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                obscureText: !_showCode,
                obscuringCharacter: '●',
                autocorrect: false,
                enableSuggestions: false,
                cursorColor: SafeSteel.lcdInk,
                onSubmitted: onSubmitted,
                style: const TextStyle(
                  color: SafeSteel.lcdInk,
                  fontSize: 17,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'JetBrains Mono',
                  fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New'],
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: hint,
                  hintStyle: const TextStyle(
                    color: SafeSteel.lcdDim,
                    fontSize: 13,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'JetBrains Mono',
                    fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New'],
                  ),
                ),
              ),
            ),
            if (trailing != null) trailing else const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

/// Four lamps for how hard the new code is to guess.
class _StrengthGauge extends StatelessWidget {
  const _StrengthGauge({required this.strength});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final color = switch (strength.level) {
      0 => SafeSteel.lcdDim,
      1 => SafeSteel.ledRed,
      2 => SafeSteel.ledAmber,
      _ => SafeSteel.ledGreen,
    };
    return SizedBox(
      width: 330,
      child: Row(
        children: [
          for (var i = 1; i <= 4; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i <= strength.level
                      ? color
                      : Colors.black.withValues(alpha: 0.3),
                  boxShadow: i <= strength.level
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
            if (i < 4) const SizedBox(width: 6),
          ],
          const SizedBox(width: 12),
          SizedBox(
            width: 70,
            child: EngravedText(
              strength.label.toUpperCase(),
              size: 10,
              spacing: 1.4,
              mono: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// What shows inside the opening while the door swings: a lit cavity with
/// shelves and boxes, before the view moves in to the real contents.
class _InteriorGlimpse extends StatelessWidget {
  const _InteriorGlimpse({required this.light});

  final double light;

  @override
  Widget build(BuildContext context) {
    final steel = SafeSteel.of(context);
    Widget box(double width, double height) => Container(
      width: width,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [steel.boxFace.first, steel.boxFace.last],
        ),
        border: Border.all(color: steel.boxEdge),
      ),
      alignment: Alignment.center,
      child: KeyholeIcon(size: 12, color: steel.boxEdge),
    );
    Widget shelf(List<Widget> boxes) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: boxes,
        ),
        Container(
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: steel.boxEdge,
            borderRadius: BorderRadius.circular(2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
      ],
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(SafeDoorPainter.radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [steel.interior.first, steel.interior.last],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: light,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -1.1),
                      radius: 1.2,
                      colors: [Color(0x55FFE7B0), Color(0x00FFE7B0)],
                    ),
                  ),
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                shelf([box(110, 70), box(80, 90), box(130, 60)]),
                shelf([box(70, 70), box(70, 70), box(70, 70), box(70, 70)]),
                shelf([box(160, 100), box(160, 100)]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
