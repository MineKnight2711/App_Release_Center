import 'dart:math' as math;
import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _relativeLuminance(Color color) {
  double channel(double value) {
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  // Flutter Color provides r, g, b as doubles in [0..1]
  final r = channel(color.r);
  final g = channel(color.g);
  final b = channel(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrastRatio(Color c1, Color c2) {
  final l1 = _relativeLuminance(c1);
  final l2 = _relativeLuminance(c2);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('AppPalette & Theme Token Tests', () {
    test('mọi AppThemeChoice đều có palette hợp lệ với đầy đủ tokens', () {
      expect(AppThemeChoice.values, contains(AppThemeChoice.console));
      expect(AppThemeChoice.values, contains(AppThemeChoice.cyber));
      expect(AppThemeChoice.values, contains(AppThemeChoice.defaultTheme));

      for (final choice in AppThemeChoice.values) {
        final palette = AppCyberTheme.paletteFor(choice);
        expect(palette, isNotNull);
        expect(choice.label.isNotEmpty, isTrue);
        expect(choice.icon, isNotNull);

        // Surfaces
        expect(palette.base.a, greaterThan(0));
        expect(palette.panel.a, greaterThan(0));
        expect(palette.panelStrong.a, greaterThan(0));
        expect(palette.surfaceHighest.a, greaterThan(0));
        expect(palette.backdropGradient, isNotEmpty);

        // Lines & borders
        expect(palette.line.a, greaterThan(0));
        expect(palette.lineStrong.a, greaterThan(0));
        expect(palette.focusRing.a, greaterThan(0));
        expect(palette.cardBorder.a, greaterThan(0));
        expect(palette.dialogBorder.a, greaterThan(0));

        // Accents
        expect(palette.accent.a, greaterThan(0));
        expect(palette.accentSoft.a, greaterThan(0));
        expect(palette.accentBorder.a, greaterThan(0));
        expect(palette.accentAlt.a, greaterThan(0));

        // Semantics
        expect(palette.success.a, greaterThan(0));
        expect(palette.successSoft.a, greaterThan(0));
        expect(palette.successBorder.a, greaterThan(0));
        expect(palette.warning.a, greaterThan(0));
        expect(palette.danger.a, greaterThan(0));
        expect(palette.info.a, greaterThan(0));
        expect(palette.idle.a, greaterThan(0));

        // Typography
        expect(palette.textPrimary.a, greaterThan(0));
        expect(palette.textMuted.a, greaterThan(0));
        expect(palette.textFaint.a, greaterThan(0));

        // Capabilities
        expect(palette.backdropBlurSigma, greaterThanOrEqualTo(0));
        expect(palette.scrimAlpha, inInclusiveRange(0.0, 1.0));
      }
    });

    test(
      'độ tương phản textPrimary và textMuted trên base đạt chuẩn WCAG AA >= 4.5:1',
      () {
        // Console theme mới phải đạt chuẩn nghiêm ngặt >= 4.5:1
        final console = AppCyberTheme.paletteFor(AppThemeChoice.console);
        final consolePrimary = _contrastRatio(
          console.textPrimary,
          console.base,
        );
        final consoleMuted = _contrastRatio(console.textMuted, console.base);
        expect(
          consolePrimary,
          greaterThanOrEqualTo(4.5),
          reason: 'Console textPrimary >= 4.5:1',
        );
        expect(
          consoleMuted,
          greaterThanOrEqualTo(4.5),
          reason: 'Console textMuted >= 4.5:1',
        );

        // Cyber
        final cyber = AppCyberTheme.paletteFor(AppThemeChoice.cyber);
        expect(
          _contrastRatio(cyber.textPrimary, cyber.base),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrastRatio(cyber.textMuted, cyber.base),
          greaterThanOrEqualTo(4.5),
        );

        // Default (legacy)
        final def = AppCyberTheme.paletteFor(AppThemeChoice.defaultTheme);
        expect(
          _contrastRatio(def.textPrimary, def.base),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrastRatio(def.textMuted, def.base),
          greaterThanOrEqualTo(4.4),
        );
      },
    );

    test(
      'kích hoạt theme cập nhật chính xác activePalette và các static getters',
      () {
        AppCyberTheme.activate(AppThemeChoice.console);
        expect(AppCyberTheme.activeChoice, AppThemeChoice.console);
        expect(AppCyberTheme.palette.base, const Color(0xFF12151C));
        expect(AppCyberTheme.baseBackground, const Color(0xFF12151C));
        expect(AppCyberTheme.electricBlue, const Color(0xFF5B8DEF));
        expect(AppCyberTheme.palette.hasGlow, isFalse);

        AppCyberTheme.activate(AppThemeChoice.cyber);
        expect(AppCyberTheme.activeChoice, AppThemeChoice.cyber);
        expect(AppCyberTheme.palette.base, const Color(0xFF0B0E14));
        expect(AppCyberTheme.baseBackground, const Color(0xFF0B0E14));
        expect(AppCyberTheme.electricBlue, const Color(0xFF00F3FF));
        expect(AppCyberTheme.palette.hasGlow, isTrue);

        AppCyberTheme.activate(AppThemeChoice.defaultTheme);
        expect(AppCyberTheme.activeChoice, AppThemeChoice.defaultTheme);
        expect(AppCyberTheme.palette.base, const Color(0xFFF6F7F9));
        expect(AppCyberTheme.baseBackground, const Color(0xFFF6F7F9));
        expect(AppCyberTheme.palette.hasGlow, isFalse);

        // Trả về mặc định Console
        AppCyberTheme.activate(AppThemeChoice.console);
      },
    );

    test('ThemeData được tạo hợp lệ cho cả 3 themes', () {
      for (final choice in AppThemeChoice.values) {
        final theme = AppCyberTheme.themeData(choice);
        expect(theme, isNotNull);
        expect(theme.useMaterial3, isTrue);
        expect(
          theme.scaffoldBackgroundColor,
          AppCyberTheme.paletteFor(choice).base,
        );
        expect(theme.colorScheme.primary, isNotNull);
        expect(theme.colorScheme.surface, isNotNull);
        expect(theme.colorScheme.error, isNotNull);
      }
      AppCyberTheme.activate(AppThemeChoice.console);
    });
  });
}
