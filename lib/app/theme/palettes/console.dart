import 'package:app_management_center/app/theme/app_palette.dart';
import 'package:flutter/material.dart';

const consolePalette = AppPalette(
  // Surfaces
  base: Color(0xFF12151C),
  panel: Color(0xFF1A1F29),
  panelStrong: Color(0xFF212836),
  surfaceHighest: Color(0xFF262E3D),
  backdropGradient: [Color(0xFF181D27), Color(0xFF12151C)],

  // Lines & borders
  line: Color(0xFF2C3441),
  lineStrong: Color(0xFF3A4553),
  focusRing: Color(0xFF5B8DEF),
  cardBorder: Color(0xFF2C3441),
  dialogBorder: Color(0xFF3A4553),

  // Accents
  accent: Color(0xFF5B8DEF),
  accentSoft: Color(0x245B8DEF), // alpha 0.14
  accentBorder: Color(0x6B5B8DEF), // alpha 0.42
  accentAlt: Color(0xFF3DBE8B),

  // Semantics
  success: Color(0xFF3DBE8B),
  successSoft: Color(0x243DBE8B),
  successBorder: Color(0x6B3DBE8B),
  warning: Color(0xFFE0A73B),
  warningSoft: Color(0x24E0A73B),
  warningBorder: Color(0x6BE0A73B),
  danger: Color(0xFFE5556E),
  dangerSoft: Color(0x24E5556E),
  dangerBorder: Color(0x6BE5556E),
  info: Color(0xFF6FA8FF),
  infoSoft: Color(0x246FA8FF),
  infoBorder: Color(0x6B6FA8FF),
  idle: Color(0xFF94A0B4),

  // Typography
  textPrimary: Color(0xFFE6EAF2),
  textMuted: Color(0xFF94A0B4),
  textFaint: Color(0xFF6B7688),

  // Visual capabilities
  hasGlow: false,
  hasScanlines: false,
  hasCornerBrackets: false,
  pulseOnActive: false,
  backdropBlurSigma: 8.0,
  scrimAlpha: 0.6,
  brightness: Brightness.dark,

  // Overlays
  panelAlphaMuted: 0.60,
  dialogGlowColor: Color(0x33000000),
);
