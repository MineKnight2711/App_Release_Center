import 'package:flutter/material.dart';

/// Immutable design tokens representing a complete visual theme for the
/// App Management Center dashboard.
class AppPalette {
  const AppPalette({
    // Surfaces
    required this.base,
    required this.panel,
    required this.panelStrong,
    required this.surfaceHighest,
    required this.backdropGradient,

    // Lines & borders
    required this.line,
    required this.lineStrong,
    required this.focusRing,
    required this.cardBorder,
    required this.dialogBorder,

    // Accents
    required this.accent,
    required this.accentSoft,
    required this.accentBorder,
    required this.accentAlt,

    // Semantics
    required this.success,
    required this.successSoft,
    required this.successBorder,
    required this.warning,
    required this.warningSoft,
    required this.warningBorder,
    required this.danger,
    required this.dangerSoft,
    required this.dangerBorder,
    required this.info,
    required this.infoSoft,
    required this.infoBorder,
    required this.idle,

    // Typography
    required this.textPrimary,
    required this.textMuted,
    required this.textFaint,

    // Visual capabilities
    required this.hasGlow,
    required this.hasScanlines,
    required this.hasCornerBrackets,
    required this.pulseOnActive,
    required this.backdropBlurSigma,
    required this.scrimAlpha,
    required this.brightness,

    // Repeated alphas & overlay helpers
    required this.panelAlphaMuted,
    required this.dialogGlowColor,
  });

  // Surfaces
  final Color base;
  final Color panel;
  final Color panelStrong;
  final Color surfaceHighest;
  final List<Color> backdropGradient;

  // Lines & borders
  final Color line;
  final Color lineStrong;
  final Color focusRing;
  final Color cardBorder;
  final Color dialogBorder;

  // Accents
  final Color accent;
  final Color accentSoft;
  final Color accentBorder;
  final Color accentAlt;

  // Semantics
  final Color success;
  final Color successSoft;
  final Color successBorder;
  final Color warning;
  final Color warningSoft;
  final Color warningBorder;
  final Color danger;
  final Color dangerSoft;
  final Color dangerBorder;
  final Color info;
  final Color infoSoft;
  final Color infoBorder;
  final Color idle;

  // Typography
  final Color textPrimary;
  final Color textMuted;
  final Color textFaint;

  // Visual capabilities
  final bool hasGlow;
  final bool hasScanlines;
  final bool hasCornerBrackets;
  final bool pulseOnActive;
  final double backdropBlurSigma;
  final double scrimAlpha;
  final Brightness brightness;

  // Overlays
  final double panelAlphaMuted;
  final Color dialogGlowColor;

  bool get isDark => brightness == Brightness.dark;
}
