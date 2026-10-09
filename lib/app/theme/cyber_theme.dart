import 'package:app_management_center/app/theme/app_palette.dart';
import 'package:app_management_center/app/theme/palettes/console.dart';
import 'package:app_management_center/app/theme/palettes/cyber.dart';
import 'package:app_management_center/app/theme/palettes/default.dart';
import 'package:flutter/material.dart';

enum AppThemeChoice { console, cyber, defaultTheme }

extension AppThemeChoiceLabel on AppThemeChoice {
  String get label {
    return switch (this) {
      AppThemeChoice.console => 'Console',
      AppThemeChoice.cyber => 'Cyber',
      AppThemeChoice.defaultTheme => 'Default',
    };
  }

  IconData get icon {
    return switch (this) {
      AppThemeChoice.console => Icons.space_dashboard_outlined,
      AppThemeChoice.cyber => Icons.bolt_outlined,
      AppThemeChoice.defaultTheme => Icons.light_mode_outlined,
    };
  }
}

class AppCyberTheme {
  const AppCyberTheme._();

  static AppThemeChoice _activeChoice = AppThemeChoice.console;
  static AppPalette _activePalette = consolePalette;

  static AppPalette get palette => _activePalette;
  static AppPalette get activePalette => _activePalette;
  static AppThemeChoice get activeChoice => _activeChoice;

  @Deprecated('Gỡ bỏ công tắc nhị phân. Dùng AppCyberTheme.palette.* hoặc AppCyberTheme.activePalette.*')
  static bool get isCyber => _activeChoice == AppThemeChoice.cyber;

  static Color get baseBackground => _activePalette.base;
  static Color get panelBackground => _activePalette.panel;
  static Color get panelBackgroundStrong => _activePalette.panelStrong;
  static Color get electricBlue => _activePalette.accent;
  static Color get neonGreen => _activePalette.accentAlt;
  static Color get lineBlue => _activePalette.line;
  static Color get textPrimary => _activePalette.textPrimary;
  static Color get textMuted => _activePalette.textMuted;
  static Color get textFaint => _activePalette.textFaint;

  // Semantic getters
  static Color get success => _activePalette.success;
  static Color get warning => _activePalette.warning;
  static Color get danger => _activePalette.danger;
  static Color get info => _activePalette.info;
  static Color get idle => _activePalette.idle;

  /// Carries a caution that is not a failure, so it must not read as an error.
  static Color get amber => _activePalette.warning;

  static List<Color> get backdropGradientColors => _activePalette.backdropGradient;

  static void activate(AppThemeChoice choice) {
    _activeChoice = choice;
    _activePalette = paletteFor(choice);
  }

  static AppPalette paletteFor(AppThemeChoice choice) {
    return switch (choice) {
      AppThemeChoice.console => consolePalette,
      AppThemeChoice.cyber => cyberPalette,
      AppThemeChoice.defaultTheme => defaultPalette,
    };
  }

  static ThemeData themeData([AppThemeChoice choice = AppThemeChoice.console]) {
    activate(choice);
    final palette = _activePalette;
    final scheme = switch (choice) {
      AppThemeChoice.console => ColorScheme.dark(
        brightness: Brightness.dark,
        primary: palette.accent,
        onPrimary: const Color(0xFF0C1017),
        secondary: palette.accentAlt,
        onSecondary: const Color(0xFF04140D),
        surface: palette.panel,
        onSurface: palette.textPrimary,
        onSurfaceVariant: palette.textMuted,
        error: palette.danger,
        onError: Colors.white,
        outline: palette.line,
        outlineVariant: palette.lineStrong,
        tertiary: palette.info,
        onTertiary: const Color(0xFF001433),
        surfaceContainerHighest: palette.surfaceHighest,
        secondaryContainer: const Color(0xFF1B332A),
        tertiaryContainer: const Color(0xFF1E2D44),
      ),
      AppThemeChoice.cyber => ColorScheme.dark(
        brightness: Brightness.dark,
        primary: cyberPalette.accent,
        onPrimary: const Color(0xFF00141A),
        secondary: cyberPalette.accentAlt,
        onSecondary: const Color(0xFF061700),
        surface: cyberPalette.panel,
        onSurface: cyberPalette.textPrimary,
        onSurfaceVariant: cyberPalette.textMuted,
        error: const Color(0xFFFF6B87),
        onError: Colors.black,
        outline: cyberPalette.line,
        outlineVariant: const Color(0x5C6E8CA8),
        tertiary: const Color(0xFF4D7DFF),
        onTertiary: const Color(0xFF000F2B),
        surfaceContainerHighest: cyberPalette.surfaceHighest,
        secondaryContainer: const Color(0xB0193D26),
        tertiaryContainer: const Color(0xA61D314B),
      ),
      AppThemeChoice.defaultTheme => ColorScheme.light(
        brightness: Brightness.light,
        primary: defaultPalette.accent,
        onPrimary: Colors.white,
        secondary: const Color(0xFF667085),
        onSecondary: Colors.white,
        surface: defaultPalette.panelStrong,
        onSurface: defaultPalette.textPrimary,
        onSurfaceVariant: defaultPalette.textMuted,
        error: const Color(0xFFB42342),
        onError: Colors.white,
        outline: defaultPalette.line,
        outlineVariant: defaultPalette.line,
        tertiary: const Color(0xFF667085),
        onTertiary: Colors.white,
        surfaceContainerHighest: defaultPalette.surfaceHighest,
        secondaryContainer: const Color(0xFFE9EDF2),
        tertiaryContainer: const Color(0xFFE9EDF2),
      ),
    };

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.base,
      fontFamily: 'Segoe UI Variable',
    );

    final textTheme = base.textTheme.copyWith(
      headlineSmall: _uiText(scheme, size: 22, weight: FontWeight.w700),
      titleLarge: _uiText(scheme, size: 17, weight: FontWeight.w700),
      titleMedium: _uiText(scheme, size: 15, weight: FontWeight.w600),
      titleSmall: _uiText(scheme, size: 13, weight: FontWeight.w700),
      bodyLarge: _uiText(scheme, size: 14),
      bodyMedium: _uiText(scheme, size: 13),
      bodySmall: _uiText(scheme, size: 12, color: palette.textMuted),
      labelLarge: _uiText(scheme, size: 13, weight: FontWeight.w600),
      labelMedium: _uiText(scheme, size: 12, weight: FontWeight.w600),
      labelSmall: _monoText(size: 11, color: palette.textMuted),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.hasGlow
            ? palette.base.withValues(alpha: 0.7)
            : (palette.isDark ? palette.panel : Colors.white),
        foregroundColor: palette.textPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: _uiText(scheme, size: 15, weight: FontWeight.w700),
      ),
      dividerTheme: DividerThemeData(
        color: palette.hasGlow
            ? palette.accent.withValues(alpha: 0.18)
            : palette.line,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: palette.panelStrong,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      iconTheme: IconThemeData(
        color: palette.hasGlow ? palette.accent : palette.textMuted,
        size: 18,
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: _uiText(scheme, size: 12, weight: FontWeight.w700),
        unselectedLabelStyle: _uiText(scheme, size: 12, color: palette.textMuted),
        labelColor: palette.isDark ? palette.accent : palette.textPrimary,
        unselectedLabelColor: palette.textMuted,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: palette.isDark
              ? palette.accent.withValues(alpha: 0.14)
              : const Color(0xFFF1F3F6),
          border: Border.all(
            color: palette.isDark
                ? palette.accent.withValues(alpha: 0.45)
                : palette.line,
          ),
          boxShadow: palette.hasGlow
              ? [
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.2),
                    blurRadius: 14,
                    spreadRadius: -3,
                  ),
                ]
              : const [],
        ),
        dividerColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        labelStyle: _uiText(scheme, size: 12, color: palette.textMuted),
        filled: true,
        fillColor: palette.hasGlow
            ? palette.panelStrong.withValues(alpha: 0.66)
            : (palette.isDark ? palette.panelStrong : const Color(0xFFFAFBFC)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        prefixIconColor: palette.textMuted,
        border: _inputBorder(
          palette.hasGlow
              ? palette.accent.withValues(alpha: 0.18)
              : palette.line,
        ),
        enabledBorder: _inputBorder(
          palette.hasGlow
              ? palette.accent.withValues(alpha: 0.22)
              : palette.line,
        ),
        focusedBorder: _inputBorder(
          palette.hasGlow
              ? palette.accent.withValues(alpha: 0.88)
              : (palette.isDark
                  ? palette.accent
                  : palette.accent.withValues(alpha: 0.45)),
        ),
        disabledBorder: _inputBorder(
          palette.hasGlow
              ? palette.accent.withValues(alpha: 0.1)
              : palette.line.withValues(alpha: 0.7),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        side: BorderSide(
          color: palette.hasGlow
              ? palette.accent.withValues(alpha: 0.6)
              : palette.textMuted,
          width: 1.1,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.hasGlow ? palette.accent : palette.textMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _baseButtonStyle(
          background: palette.isDark
              ? palette.accent.withValues(alpha: palette.hasGlow ? 0.88 : 0.95)
              : palette.textPrimary,
          foreground: palette.isDark ? const Color(0xFF021318) : Colors.white,
          borderColor: palette.isDark
              ? palette.accent.withValues(alpha: palette.hasGlow ? 0.88 : 0.95)
              : palette.textPrimary,
          glowColor: palette.hasGlow
              ? palette.accent.withValues(alpha: 0.36)
              : Colors.transparent,
          palette: palette,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _baseButtonStyle(
          background: palette.hasGlow
              ? palette.accent.withValues(alpha: 0.06)
              : (palette.isDark ? palette.panelStrong : Colors.white),
          foreground: palette.textPrimary,
          borderColor: palette.hasGlow
              ? palette.accent.withValues(alpha: 0.44)
              : palette.line,
          glowColor: palette.hasGlow
              ? palette.accent.withValues(alpha: 0.24)
              : Colors.transparent,
          palette: palette,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: _baseButtonStyle(
          background: palette.hasGlow
              ? palette.accent.withValues(alpha: 0.15)
              : (palette.isDark
                  ? palette.surfaceHighest.withValues(alpha: 0.5)
                  : const Color(0xFFF1F3F6)),
          foreground: palette.hasGlow ? palette.accent : palette.textPrimary,
          borderColor: palette.hasGlow
              ? palette.accent.withValues(alpha: 0.4)
              : palette.line,
          glowColor: palette.hasGlow
              ? palette.accent.withValues(alpha: 0.28)
              : Colors.transparent,
          minSize: const Size(40, 38),
          padding: const EdgeInsets.all(8),
          palette: palette,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accentAlt,
        linearTrackColor: palette.hasGlow
            ? palette.accent.withValues(alpha: 0.2)
            : palette.line.withValues(alpha: 0.4),
      ),
    );
  }

  static BoxDecoration panelDecoration({bool active = false}) {
    final palette = _activePalette;
    final borderColor = palette.hasGlow
        ? palette.accent.withValues(alpha: active ? 0.82 : 0.32)
        : (active ? palette.accent : palette.line);

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: switch (_activeChoice) {
          AppThemeChoice.cyber => const [
            Color(0xCC192130),
            Color(0xCC121B28),
            Color(0xB70E1622),
          ],
          AppThemeChoice.console => [
            palette.panel,
            palette.panelStrong,
          ],
          AppThemeChoice.defaultTheme => const [
            Colors.white,
            Colors.white,
          ],
        },
      ),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: borderColor, width: 1),
      boxShadow: palette.hasGlow
          ? [
              BoxShadow(
                color: palette.accent.withValues(alpha: active ? 0.24 : 0.12),
                blurRadius: active ? 28 : 18,
                spreadRadius: active ? -4 : -8,
              ),
            ]
          : const [],
    );
  }

  static BoxDecoration gridShellDecoration({bool active = false}) {
    final palette = _activePalette;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: switch (_activeChoice) {
          AppThemeChoice.cyber => [
            const Color(0xCC1C2837),
            if (active)
              const Color(0xB3243952)
            else
              const Color(0xB3172433),
          ],
          AppThemeChoice.console => [
            palette.panelStrong,
            active ? palette.surfaceHighest : palette.panel,
          ],
          AppThemeChoice.defaultTheme => const [
            Colors.white,
            Colors.white,
          ],
        },
      ),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: active
            ? (palette.hasGlow
                ? palette.accent.withValues(alpha: 0.88)
                : palette.accent)
            : (palette.hasGlow
                ? palette.accent.withValues(alpha: 0.3)
                : palette.line),
      ),
      boxShadow: [
        if (palette.hasGlow)
          BoxShadow(
            color: palette.accent.withValues(alpha: active ? 0.24 : 0.1),
            blurRadius: active ? 24 : 14,
            spreadRadius: active ? -3 : -8,
          ),
      ],
    );
  }

  static TextStyle dataTextStyle({
    double size = 12,
    Color? color,
    FontWeight weight = FontWeight.w500,
  }) {
    return _monoText(
      size: size,
      color: color ?? _activePalette.textPrimary,
      weight: weight,
    );
  }

  static TextStyle _uiText(
    ColorScheme scheme, {
    required double size,
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) {
    return TextStyle(
      fontSize: size,
      height: 1.25,
      letterSpacing: 0.2,
      fontWeight: weight,
      color: color ?? scheme.onSurface,
      fontFamily: 'Segoe UI Variable',
      fontFamilyFallback: const ['Inter', 'Segoe UI', 'Roboto'],
    );
  }

  static TextStyle _monoText({
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w500,
  }) {
    return TextStyle(
      fontSize: size,
      height: 1.3,
      letterSpacing: 0.15,
      fontWeight: weight,
      color: color,
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: const [
        'Fira Code',
        'Cascadia Mono',
        'Consolas',
        'Courier New',
      ],
    );
  }

  static OutlineInputBorder _inputBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: color, width: 1),
    );
  }

  static ButtonStyle _baseButtonStyle({
    required Color background,
    required Color foreground,
    required Color borderColor,
    required Color glowColor,
    required AppPalette palette,
    Size minSize = const Size(0, 38),
    EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 14,
      vertical: 8,
    ),
  }) {
    return ButtonStyle(
      minimumSize: WidgetStateProperty.all(minSize),
      padding: WidgetStateProperty.all(padding),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return foreground.withValues(alpha: 0.48);
        }
        return foreground;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return background.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return background.withValues(alpha: 0.95);
        }
        return background;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        final alpha = states.contains(WidgetState.disabled) ? 0.18 : 1.0;
        return BorderSide(
          color: borderColor.withValues(alpha: alpha),
          width: 1,
        );
      }),
      textStyle: WidgetStateProperty.all(
        const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.25,
          fontFamily: 'Segoe UI Variable',
          fontFamilyFallback: ['Inter', 'Segoe UI', 'Roboto'],
        ),
      ),
      elevation: WidgetStateProperty.all(0),
      shadowColor: WidgetStateProperty.resolveWith((states) {
        if (!palette.hasGlow) return Colors.transparent;
        if (states.contains(WidgetState.hovered)) return glowColor;
        return glowColor.withValues(alpha: glowColor.a * 0.6);
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return palette.hasGlow
              ? palette.accent.withValues(alpha: 0.1)
              : (palette.isDark
                  ? palette.accent.withValues(alpha: 0.12)
                  : const Color(0xFFE9EDF2));
        }
        if (states.contains(WidgetState.pressed)) {
          return palette.hasGlow
              ? palette.accentAlt.withValues(alpha: 0.16)
              : (palette.isDark
                  ? palette.accent.withValues(alpha: 0.2)
                  : const Color(0xFFDDE3EA));
        }
        return null;
      }),
    );
  }
}
