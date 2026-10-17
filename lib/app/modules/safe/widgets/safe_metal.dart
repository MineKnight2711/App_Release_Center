import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Steel tones for the safe.
///
/// The safe should look like a safe in every app theme, so it does not borrow
/// the palette's surfaces; only how light the steel is follows the theme's
/// brightness, so text the theme colours stays readable on it.
class SafeSteel {
  const SafeSteel({required this.dark});

  factory SafeSteel.of(BuildContext context) =>
      SafeSteel(dark: Theme.of(context).brightness == Brightness.dark);

  final bool dark;

  Color get body => dark ? const Color(0xFF1A1E23) : const Color(0xFF4C545C);
  Color get bodyEdge =>
      dark ? const Color(0xFF353C44) : const Color(0xFF79828B);

  List<Color> get door => dark
      ? const [
          Color(0xFF6F7882),
          Color(0xFF424951),
          Color(0xFF59616A),
          Color(0xFF30363D),
        ]
      : const [
          Color(0xFFE6EAEE),
          Color(0xFFB7BEC6),
          Color(0xFFD0D6DC),
          Color(0xFF9EA6AF),
        ];

  Color get highlight => dark ? const Color(0xFFB4BDC7) : Colors.white;
  Color get shadow => dark ? const Color(0xFF0A0C0F) : const Color(0xFF59616A);

  /// Lettering cut into the door.
  Color get engraving =>
      dark ? const Color(0xFF171B1F) : const Color(0xFF353C43);
  Color get engravingLip =>
      dark ? const Color(0x40FFFFFF) : const Color(0xB3FFFFFF);

  /// The inside of the safe, where the boxes sit.
  List<Color> get interior => dark
      ? const [Color(0xFF12161A), Color(0xFF1B2026)]
      : const [Color(0xFFCDD3D9), Color(0xFFBCC3CA)];

  /// Faces of the drawers and deposit boxes inside.
  List<Color> get boxFace => dark
      ? const [Color(0xFF353C44), Color(0xFF262B31)]
      : const [Color(0xFFF8F9FA), Color(0xFFE2E6EA)];
  Color get boxEdge => dark ? const Color(0xFF4A525B) : const Color(0xFFAEB6BE);

  static const brass = [
    Color(0xFFF0D88F),
    Color(0xFFBF9A41),
    Color(0xFFE0C06A),
    Color(0xFF8F6C24),
  ];
  static const brassInk = Color(0xFF4A3608);

  static const lcd = [Color(0xFF07110D), Color(0xFF0E1C16)];
  static const lcdInk = Color(0xFF7CF5B0);
  static const lcdDim = Color(0xFF2F6B4C);

  static const ledRed = Color(0xFFFF4D4F);
  static const ledAmber = Color(0xFFFFB020);
  static const ledGreen = Color(0xFF3DDC84);
}

void _paintRivet(Canvas canvas, Offset center, double radius, SafeSteel steel) {
  canvas.drawCircle(
    center.translate(radius * 0.2, radius * 0.35),
    radius,
    Paint()
      ..color = Colors.black.withValues(alpha: steel.dark ? 0.55 : 0.3)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.4),
  );
  final rect = Rect.fromCircle(center: center, radius: radius);
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.45, -0.5),
        radius: 1.1,
        colors: [steel.highlight, steel.door[1], steel.shadow],
        stops: const [0, 0.55, 1],
      ).createShader(rect),
  );
}

/// The door slab: brushed steel, a recessed panel ringed with rivets, two
/// hinges on the left and three bolts on the right that slide out when the
/// safe is locked.
class SafeDoorPainter extends CustomPainter {
  const SafeDoorPainter({required this.steel, required this.boltsOut});

  final SafeSteel steel;

  /// 1 with the bolts thrown into the frame, 0 with them drawn back.
  final double boltsOut;

  /// Room left of the slab for the hinges, and right of it for the bolts.
  static const hingeRoom = 16.0;
  static const boltRoom = 26.0;
  static const radius = 22.0;

  static Rect slabRect(Size size) =>
      Rect.fromLTRB(hingeRoom, 0, size.width - boltRoom, size.height);

  @override
  void paint(Canvas canvas, Size size) {
    final slab = slabRect(size);
    final slabShape = RRect.fromRectAndRadius(
      slab,
      const Radius.circular(radius),
    );

    _paintBolts(canvas, slab);
    _paintHinges(canvas, slab);

    canvas.drawRRect(
      slabShape.shift(const Offset(0, 10)),
      Paint()
        ..color = Colors.black.withValues(alpha: steel.dark ? 0.5 : 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawRRect(
      slabShape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: steel.door,
          stops: const [0, 0.45, 0.7, 1],
        ).createShader(slab),
    );

    canvas.save();
    canvas.clipRRect(slabShape);
    // Brushing: alternate faint light and dark lines across the slab.
    final light = Paint()
      ..color = Colors.white.withValues(alpha: steel.dark ? 0.03 : 0.22)
      ..strokeWidth = 1;
    final dark = Paint()
      ..color = Colors.black.withValues(alpha: steel.dark ? 0.06 : 0.04)
      ..strokeWidth = 1;
    var row = 0;
    for (var y = slab.top + 1; y < slab.bottom; y += 2.5) {
      canvas.drawLine(
        Offset(slab.left, y),
        Offset(slab.right, y),
        row.isEven ? light : dark,
      );
      row++;
    }
    canvas.drawRect(
      slab,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-1, -1),
          end: const Alignment(1, 1),
          colors: [
            Colors.white.withValues(alpha: steel.dark ? 0.12 : 0.35),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: steel.dark ? 0.06 : 0.18),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.32, 0.52, 0.78],
        ).createShader(slab),
    );
    canvas.restore();

    // Bevel: lit from the top left.
    canvas.drawRRect(
      slabShape.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            steel.highlight.withValues(alpha: 0.9),
            steel.shadow.withValues(alpha: 0.7),
          ],
        ).createShader(slab),
    );

    // The recessed panel: a groove, dark above and lit below.
    final panel = slabShape.deflate(30);
    canvas.drawRRect(
      panel.shift(const Offset(-0.8, -0.8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = steel.shadow.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      panel.shift(const Offset(0.8, 0.8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = steel.highlight.withValues(alpha: steel.dark ? 0.25 : 0.8),
    );

    // Rivets ringing the panel.
    final ring = panel.outerRect.inflate(15);
    const spacing = 46.0;
    final across = math.max(2, (ring.width / spacing).round());
    final down = math.max(2, (ring.height / spacing).round());
    for (var i = 0; i <= across; i++) {
      final x = ring.left + ring.width * i / across;
      _paintRivet(canvas, Offset(x, ring.top), 4.2, steel);
      _paintRivet(canvas, Offset(x, ring.bottom), 4.2, steel);
    }
    for (var i = 1; i < down; i++) {
      final y = ring.top + ring.height * i / down;
      _paintRivet(canvas, Offset(ring.left, y), 4.2, steel);
      _paintRivet(canvas, Offset(ring.right, y), 4.2, steel);
    }
  }

  void _paintBolts(Canvas canvas, Rect slab) {
    final out = boltRoom * boltsOut.clamp(0.0, 1.0);
    for (final at in const [0.24, 0.5, 0.76]) {
      final cy = slab.top + slab.height * at;
      final rod = Rect.fromLTRB(
        slab.right - 44,
        cy - 10,
        slab.right + out,
        cy + 10,
      );
      final shape = RRect.fromRectAndRadius(rod, const Radius.circular(5));
      canvas.drawRRect(
        shape,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              steel.highlight,
              steel.door[1],
              steel.shadow,
              steel.door[2],
            ],
            stops: const [0, 0.35, 0.8, 1],
          ).createShader(rod),
      );
      canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = steel.shadow.withValues(alpha: 0.8),
      );
    }
  }

  void _paintHinges(Canvas canvas, Rect slab) {
    for (final at in const [0.2, 0.8]) {
      final cy = slab.top + slab.height * at;
      final barrel = Rect.fromLTRB(0, cy - 46, slab.left + 24, cy + 46);
      final shape = RRect.fromRectAndRadius(barrel, const Radius.circular(9));
      canvas.drawRRect(
        shape,
        Paint()
          ..shader = LinearGradient(
            colors: [
              steel.shadow,
              steel.highlight,
              steel.door[1],
              steel.shadow,
            ],
            stops: const [0, 0.3, 0.6, 1],
          ).createShader(barrel),
      );
      // Knuckle seams.
      final seam = Paint()
        ..color = steel.shadow.withValues(alpha: 0.8)
        ..strokeWidth = 1.2;
      for (final y in [cy - 15, cy + 15]) {
        canvas.drawLine(
          Offset(barrel.left + 2, y),
          Offset(barrel.right - 2, y),
          seam,
        );
      }
    }
  }

  @override
  bool shouldRepaint(SafeDoorPainter oldDelegate) =>
      oldDelegate.boltsOut != boltsOut || oldDelegate.steel.dark != steel.dark;
}

/// The combination dial: a chrome bezel, a black face numbered 0–99 and a
/// fluted knob. Only [turns] changes while it spins; the face is painted once
/// and rotated as a layer.
class SafeDial extends StatelessWidget {
  const SafeDial({
    super.key,
    required this.size,
    required this.turns,
    this.lit = false,
  });

  final double size;

  /// Rotation of the face in full turns.
  final double turns;

  /// Lights the pointer, while the code is being checked.
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final steel = SafeSteel.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _DialBezelPainter(steel),
        foregroundPainter: _DialPointerPainter(lit: lit),
        child: Transform.rotate(
          angle: turns * 2 * math.pi,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _DialFacePainter(steel),
              size: Size.square(size),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialBezelPainter extends CustomPainter {
  const _DialBezelPainter(this.steel);

  final SafeSteel steel;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(
      center.translate(0, r * 0.06),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.08),
    );
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = SweepGradient(
          colors: [
            steel.highlight,
            steel.shadow,
            steel.highlight,
            steel.door[1],
            steel.highlight,
            steel.shadow,
            steel.highlight,
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      r * 0.86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.025
        ..color = steel.shadow,
    );
  }

  @override
  bool shouldRepaint(_DialBezelPainter oldDelegate) =>
      oldDelegate.steel.dark != steel.dark;
}

class _DialFacePainter extends CustomPainter {
  const _DialFacePainter(this.steel);

  final SafeSteel steel;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final faceRect = Rect.fromCircle(center: center, radius: r * 0.85);
    canvas.drawCircle(
      center,
      r * 0.85,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF2A3036), Color(0xFF0C0E11)],
        ).createShader(faceRect),
    );

    final major = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = r * 0.022
      ..strokeCap = StrokeCap.round;
    final minor = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = r * 0.011;
    for (var i = 0; i < 100; i++) {
      final angle = i * 2 * math.pi / 100 - math.pi / 2;
      final inner = i % 10 == 0
          ? 0.69
          : i % 5 == 0
          ? 0.74
          : 0.775;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * r * inner,
        center + direction * r * 0.82,
        i % 5 == 0 ? major : minor,
      );
    }

    for (var n = 0; n < 100; n += 10) {
      final angle = n * 2 * math.pi / 100;
      final painter = TextPainter(
        text: TextSpan(
          text: '$n',
          style: TextStyle(
            fontSize: r * 0.105,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.82),
            fontFamily: 'JetBrains Mono',
            fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      painter.paint(canvas, Offset(-painter.width / 2, -r * 0.66));
      canvas.restore();
    }

    // The knob, fluted round its edge.
    final knob = r * 0.5;
    final knobRect = Rect.fromCircle(center: center, radius: knob);
    canvas.drawCircle(
      center.translate(0, r * 0.03),
      knob,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.05),
    );
    canvas.drawCircle(
      center,
      knob,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: [steel.highlight, steel.door[1], steel.shadow],
          stops: const [0, 0.6, 1],
        ).createShader(knobRect),
    );
    final groove = Paint()
      ..color = steel.shadow.withValues(alpha: 0.75)
      ..strokeWidth = r * 0.018
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 32; i++) {
      final angle = i * 2 * math.pi / 32;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * knob * 0.82,
        center + direction * knob * 0.98,
        groove,
      );
    }
    final cap = knob * 0.62;
    canvas.drawCircle(
      center,
      cap,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [steel.highlight, steel.door[3]],
        ).createShader(Rect.fromCircle(center: center, radius: cap)),
    );
    // The knob's index mark, so a turn reads as a turn.
    canvas.drawLine(
      center.translate(0, -cap * 0.25),
      center.translate(0, -cap * 0.85),
      Paint()
        ..color = SafeSteel.ledRed.withValues(alpha: 0.9)
        ..strokeWidth = r * 0.03
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DialFacePainter oldDelegate) =>
      oldDelegate.steel.dark != steel.dark;
}

class _DialPointerPainter extends CustomPainter {
  const _DialPointerPainter({required this.lit});

  final bool lit;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final cx = size.width / 2;
    final path = Path()
      ..moveTo(cx - r * 0.07, r * 0.01)
      ..lineTo(cx + r * 0.07, r * 0.01)
      ..lineTo(cx, r * 0.17)
      ..close();
    final color = lit ? SafeSteel.ledAmber : SafeSteel.ledRed;
    if (lit) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.7)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06),
      );
    }
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(_DialPointerPainter oldDelegate) => oldDelegate.lit != lit;
}

/// The three-spoke handle that throws the bolts.
class SafeHandle extends StatelessWidget {
  const SafeHandle({super.key, required this.size, required this.angle});

  final double size;

  /// Rotation in radians; a quarter turn opens the safe.
  final double angle;

  @override
  Widget build(BuildContext context) {
    final steel = SafeSteel.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _HandleBasePainter(steel),
        child: Transform.rotate(
          angle: angle,
          child: CustomPaint(
            painter: _HandleSpokesPainter(steel),
            size: Size.square(size),
          ),
        ),
      ),
    );
  }
}

class _HandleBasePainter extends CustomPainter {
  const _HandleBasePainter(this.steel);

  final SafeSteel steel;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final plate = r * 0.36;
    canvas.drawCircle(
      center.translate(0, 3),
      plate,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      center,
      plate,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomRight,
          end: Alignment.topLeft,
          colors: [steel.highlight, steel.shadow],
        ).createShader(Rect.fromCircle(center: center, radius: plate)),
    );
  }

  @override
  bool shouldRepaint(_HandleBasePainter oldDelegate) =>
      oldDelegate.steel.dark != steel.dark;
}

class _HandleSpokesPainter extends CustomPainter {
  const _HandleSpokesPainter(this.steel);

  final SafeSteel steel;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    for (var i = 0; i < 3; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / 3;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final end = center + direction * r * 0.8;
      canvas.drawLine(
        center.translate(1.5, 3),
        end.translate(1.5, 3),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..strokeWidth = r * 0.17
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawLine(
        center,
        end,
        Paint()
          ..shader = LinearGradient(
            colors: [
              steel.shadow,
              steel.highlight,
              steel.door[1],
              steel.shadow,
            ],
            stops: const [0, 0.35, 0.65, 1],
          ).createShader(Rect.fromPoints(center, end).inflate(r * 0.1))
          ..strokeWidth = r * 0.16
          ..strokeCap = StrokeCap.round,
      );
      final ball = r * 0.17;
      canvas.drawCircle(
        end,
        ball,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.5),
            colors: [steel.highlight, steel.door[1], steel.shadow],
            stops: const [0, 0.55, 1],
          ).createShader(Rect.fromCircle(center: end, radius: ball)),
      );
    }
    final hub = r * 0.3;
    final hubRect = Rect.fromCircle(center: center, radius: hub);
    canvas.drawCircle(
      center,
      hub,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: [steel.highlight, steel.door[1], steel.shadow],
          stops: const [0, 0.6, 1],
        ).createShader(hubRect),
    );
    canvas.drawCircle(
      center,
      hub * 0.45,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = steel.shadow.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(_HandleSpokesPainter oldDelegate) =>
      oldDelegate.steel.dark != steel.dark;
}

/// The status lamp on the door.
class SafeLed extends StatelessWidget {
  const SafeLed({super.key, required this.color, this.size = 12});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [Color.lerp(color, Colors.white, 0.6)!, color],
        ),
        border: Border.all(color: Colors.black.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.7),
            blurRadius: size,
            spreadRadius: size * 0.1,
          ),
        ],
      ),
    );
  }
}

/// Text cut into steel: dark letters with a lit lower lip.
class EngravedText extends StatelessWidget {
  const EngravedText(
    this.text, {
    super.key,
    this.size = 12,
    this.weight = FontWeight.w800,
    this.spacing = 2,
    this.color,
    this.lip,
    this.mono = false,
    this.textAlign,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final double spacing;
  final Color? color;
  final Color? lip;
  final bool mono;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final steel = SafeSteel.of(context);
    return Text(
      text,
      textAlign: textAlign,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color ?? steel.engraving,
        fontFamily: mono ? 'JetBrains Mono' : null,
        fontFamilyFallback: mono
            ? const ['Menlo', 'Consolas', 'Courier New']
            : null,
        shadows: [
          Shadow(offset: const Offset(0, 1), color: lip ?? steel.engravingLip),
        ],
      ),
    );
  }
}

/// A brass plate held by two screws.
class BrassPlate extends StatelessWidget {
  const BrassPlate({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    Widget screw() => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.4, -0.4),
          colors: [Color(0xFFFFF1C2), Color(0xFF7A5A1A)],
        ),
        border: Border.all(color: const Color(0xFF5C430F), width: 0.6),
      ),
      alignment: Alignment.center,
      child: Container(width: 5, height: 1, color: const Color(0xFF5C430F)),
    );

    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: SafeSteel.brass,
          stops: [0, 0.4, 0.65, 1],
        ),
        border: Border.all(color: const Color(0xFF6E5216)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          screw(),
          const SizedBox(width: 12),
          Flexible(child: child),
          const SizedBox(width: 12),
          screw(),
        ],
      ),
    );
  }
}

/// A recessed dark-glass display, the safe's keypad screen.
class LcdPanel extends StatelessWidget {
  const LcdPanel({
    super.key,
    required this.child,
    this.padding,
    this.glow = false,
  });

  final Widget child;
  final EdgeInsets? padding;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final steel = SafeSteel.of(context);
    // A rounded box only takes a uniform border, so the recess is a dark rim
    // plus a lit lip below it (a hard shadow) and shade inside the top edge.
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: SafeSteel.lcd,
        ),
        border: Border.all(color: steel.shadow, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: steel.highlight.withValues(alpha: steel.dark ? 0.35 : 0.9),
            offset: const Offset(0, 1.5),
          ),
          if (glow)
            BoxShadow(
              color: SafeSteel.lcdInk.withValues(alpha: 0.25),
              blurRadius: 14,
              spreadRadius: -2,
            ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.45),
            Colors.black.withValues(alpha: 0),
          ],
          stops: const [0, 0.25],
        ),
      ),
      child: child,
    );
  }
}

/// A heavy steel push button.
class SafeMetalButton extends StatelessWidget {
  const SafeMetalButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.width,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final steel = SafeSteel.of(context);
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.6,
      child: Container(
        width: width,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [steel.highlight, steel.door[1], steel.door[3]],
          ),
          border: Border.all(color: steel.shadow.withValues(alpha: 0.9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: steel.engraving,
                      ),
                    )
                  else
                    Icon(icon, size: 18, color: steel.engraving),
                  const SizedBox(width: 10),
                  EngravedText(label, size: 13, spacing: 2.4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tiny keyhole, the mark of a deposit box.
class KeyholeIcon extends StatelessWidget {
  const KeyholeIcon({super.key, this.size = 16, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _KeyholePainter(color));
}

class _KeyholePainter extends CustomPainter {
  const _KeyholePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final plate = Paint()..color = color.withValues(alpha: 0.18);
    canvas.drawCircle(size.center(Offset.zero), w / 2, plate);
    final hole = Paint()..color = color;
    canvas.drawCircle(Offset(w / 2, h * 0.4), w * 0.15, hole);
    final slot = Path()
      ..moveTo(w * 0.44, h * 0.45)
      ..lineTo(w * 0.56, h * 0.45)
      ..lineTo(w * 0.6, h * 0.76)
      ..lineTo(w * 0.4, h * 0.76)
      ..close();
    canvas.drawPath(slot, hole);
  }

  @override
  bool shouldRepaint(_KeyholePainter oldDelegate) => oldDelegate.color != color;
}
