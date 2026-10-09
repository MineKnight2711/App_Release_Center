import 'package:app_management_center/app/theme/app_palette.dart';
import 'package:flutter/material.dart';

const defaultPalette = AppPalette(
  // Surfaces
  base: Color(0xFFF6F7F9),
  panel: Color(0xFFFFFFFF),
  panelStrong: Color(0xFFFFFFFF),
  surfaceHighest: Color(0xFFF1F3F6),
  backdropGradient: [Color(0xFFF6F7F9), Color(0xFFF6F7F9)],

  // Lines & borders
  line: Color(0xFFE1E6EE),
  lineStrong: Color(0xFFCBD5E1),
  focusRing: Color(0xFF475467),
  cardBorder: Color(0xFFE1E6EE),
  dialogBorder: Color(0xFFE1E6EE),

  // Accents
  accent: Color(0xFF475467),
  accentSoft: Color(0xFFEFF8FF),
  accentBorder: Color(0xFF1570EF),
  accentAlt: Color(0xFF3F6B5F),

  // Semantics
  success: Color(0xFF039855),
  successSoft: Color(0xFFEFF8F0),
  successBorder: Color(0xFFB7D7C2),
  warning: Color(0xFFB45309),
  warningSoft: Color(0xFFFFFBEB),
  warningBorder: Color(0xFFFDE68A),
  danger: Color(0xFFB42342),
  dangerSoft: Color(0xFFFEF3F2),
  dangerBorder: Color(0xFFFECDCA),
  info: Color(0xFF1570EF),
  infoSoft: Color(0xFFEFF6FF),
  infoBorder: Color(0xFFBFD7F5),
  idle: Color(0xFF64748B),

  // Typography
  textPrimary: Color(0xFF111827),
  textMuted: Color(0xFF64748B),
  textFaint: Color(0xFF94A3B8),

  // Visual capabilities
  hasGlow: false,
  hasScanlines: false,
  hasCornerBrackets: false,
  pulseOnActive: false,
  backdropBlurSigma: 0.0,
  scrimAlpha: 0.3,
  brightness: Brightness.light,

  // Overlays
  panelAlphaMuted: 0.82,
  dialogGlowColor: Color(0x14000000),
);
