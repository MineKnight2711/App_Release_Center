import 'package:app_management_center/app/theme/app_palette.dart';
import 'package:flutter/material.dart';

const cyberPalette = AppPalette(
  // Surfaces
  base: Color(0xFF0B0E14),
  panel: Color(0xB3182230),
  panelStrong: Color(0xD61D2938),
  surfaceHighest: Color(0xB0212D3C),
  backdropGradient: [Color(0xFF172739), Color(0xFF0B0E14)],

  // Lines & borders
  line: Color(0x8038F6FF),
  lineStrong: Color(0xFF38F6FF),
  focusRing: Color(0xFF00F3FF),
  cardBorder: Color(0x6600F3FF), // 0xFF00F3FF with alpha 0.4
  dialogBorder: Color(0x9400F3FF), // 0xFF00F3FF with alpha 0.58

  // Accents
  accent: Color(0xFF00F3FF),
  accentSoft: Color(0x2400F3FF), // alpha 0.14
  accentBorder: Color(0x6B00F3FF), // alpha 0.42
  accentAlt: Color(0xFF39FF14),

  // Semantics
  success: Color(0xFF39FF14),
  successSoft: Color(0x2439FF14), // alpha 0.14
  successBorder: Color(0x8C39FF14), // alpha 0.55
  warning: Color(0xFFFFC24B),
  warningSoft: Color(0x24FFC24B),
  warningBorder: Color(0x6BFFC24B),
  danger: Color(0xFFFF6B87),
  dangerSoft: Color(0x24FF6B87),
  dangerBorder: Color(0x6BFF6B87),
  info: Color(0xFF00F3FF),
  infoSoft: Color(0x2400F3FF),
  infoBorder: Color(0x8C00F3FF),
  idle: Color(0xFF9CAFC5),

  // Typography
  textPrimary: Color(0xFFE7F4FF),
  textMuted: Color(0xFF9CAFC5),
  textFaint: Color(0xFF5C6E8C),

  // Visual capabilities
  hasGlow: true,
  hasScanlines: true,
  hasCornerBrackets: true,
  pulseOnActive: true,
  backdropBlurSigma: 18.0,
  scrimAlpha: 0.7,
  brightness: Brightness.dark,

  // Overlays
  panelAlphaMuted: 0.34,
  dialogGlowColor: Color(0x3800F3FF), // 0xFF00F3FF with alpha 0.22
);
