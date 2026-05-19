import 'package:flutter/material.dart';

enum AppThemeChoice { defaultTheme, cyber }

extension AppThemeChoiceLabel on AppThemeChoice {
  String get label {
    return switch (this) {
      AppThemeChoice.defaultTheme => 'Default',
      AppThemeChoice.cyber => 'Cyber',
    };
  }

  IconData get icon {
    return switch (this) {
      AppThemeChoice.defaultTheme => Icons.light_mode_outlined,
      AppThemeChoice.cyber => Icons.bolt_outlined,
    };
  }
}

class AppCyberTheme {
  const AppCyberTheme._();

  static AppThemeChoice _activeChoice = AppThemeChoice.cyber;

  static const Color _cyberBaseBackground = Color(0xFF0B0E14);
  static const Color _cyberPanelBackground = Color(0xB3182230);
  static const Color _cyberPanelBackgroundStrong = Color(0xD61D2938);
  static const Color _cyberElectricBlue = Color(0xFF00F3FF);
  static const Color _cyberNeonGreen = Color(0xFF39FF14);
  static const Color _cyberLineBlue = Color(0x8038F6FF);
  static const Color _cyberTextPrimary = Color(0xFFE7F4FF);
  static const Color _cyberTextMuted = Color(0xFF9CAFC5);

  static const Color _defaultBaseBackground = Color(0xFFF6F7F9);
  static const Color _defaultPanelBackground = Color(0xFFFFFFFF);
  static const Color _defaultPanelBackgroundStrong = Color(0xFFFFFFFF);
  static const Color _defaultElectricBlue = Color(0xFF475467);
  static const Color _defaultNeonGreen = Color(0xFF3F6B5F);
  static const Color _defaultLineBlue = Color(0xFFE1E6EE);
  static const Color _defaultTextPrimary = Color(0xFF111827);
  static const Color _defaultTextMuted = Color(0xFF64748B);

  static bool get isCyber => _activeChoice == AppThemeChoice.cyber;

  static Color get baseBackground =>
      isCyber ? _cyberBaseBackground : _defaultBaseBackground;
  static Color get panelBackground =>
      isCyber ? _cyberPanelBackground : _defaultPanelBackground;
  static Color get panelBackgroundStrong =>
      isCyber ? _cyberPanelBackgroundStrong : _defaultPanelBackgroundStrong;
  static Color get electricBlue =>
      isCyber ? _cyberElectricBlue : _defaultElectricBlue;
  static Color get neonGreen => isCyber ? _cyberNeonGreen : _defaultNeonGreen;
  static Color get lineBlue => isCyber ? _cyberLineBlue : _defaultLineBlue;
  static Color get textPrimary =>
      isCyber ? _cyberTextPrimary : _defaultTextPrimary;
  static Color get textMuted => isCyber ? _cyberTextMuted : _defaultTextMuted;

  static List<Color> get backdropGradientColors {
    return isCyber
        ? const [Color(0xFF172739), _cyberBaseBackground]
        : const [_defaultBaseBackground, _defaultBaseBackground];
  }

  static void activate(AppThemeChoice choice) {
    _activeChoice = choice;
  }

  static ThemeData themeData([AppThemeChoice choice = AppThemeChoice.cyber]) {
    activate(choice);
    final scheme = choice == AppThemeChoice.cyber
        ? const ColorScheme.dark(
            brightness: Brightness.dark,
            primary: _cyberElectricBlue,
            onPrimary: Color(0xFF00141A),
            secondary: _cyberNeonGreen,
            onSecondary: Color(0xFF061700),
            surface: _cyberPanelBackground,
            onSurface: _cyberTextPrimary,
            onSurfaceVariant: _cyberTextMuted,
            error: Color(0xFFFF6B87),
            onError: Colors.black,
            outline: _cyberLineBlue,
            outlineVariant: Color(0x5C6E8CA8),
            tertiary: Color(0xFF4D7DFF),
            onTertiary: Color(0xFF000F2B),
            surfaceContainerHighest: Color(0xB0212D3C),
            secondaryContainer: Color(0xB0193D26),
            tertiaryContainer: Color(0xA61D314B),
          )
        : const ColorScheme.light(
            brightness: Brightness.light,
            primary: _defaultElectricBlue,
            onPrimary: Colors.white,
            secondary: Color(0xFF667085),
            onSecondary: Colors.white,
            surface: _defaultPanelBackgroundStrong,
            onSurface: _defaultTextPrimary,
            onSurfaceVariant: _defaultTextMuted,
            error: Color(0xFFB42342),
            onError: Colors.white,
            outline: _defaultLineBlue,
            outlineVariant: _defaultLineBlue,
            tertiary: Color(0xFF667085),
            onTertiary: Colors.white,
            surfaceContainerHighest: Color(0xFFF1F3F6),
            secondaryContainer: Color(0xFFE9EDF2),
            tertiaryContainer: Color(0xFFE9EDF2),
          );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: baseBackground,
      fontFamily: 'Segoe UI Variable',
    );

    final textTheme = base.textTheme.copyWith(
      headlineSmall: _uiText(scheme, size: 22, weight: FontWeight.w700),
      titleLarge: _uiText(scheme, size: 17, weight: FontWeight.w700),
      titleMedium: _uiText(scheme, size: 15, weight: FontWeight.w600),
      titleSmall: _uiText(scheme, size: 13, weight: FontWeight.w700),
      bodyLarge: _uiText(scheme, size: 14),
      bodyMedium: _uiText(scheme, size: 13),
      bodySmall: _uiText(scheme, size: 12, color: textMuted),
      labelLarge: _uiText(scheme, size: 13, weight: FontWeight.w600),
      labelMedium: _uiText(scheme, size: 12, weight: FontWeight.w600),
      labelSmall: _monoText(size: 11, color: textMuted),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: isCyber
            ? baseBackground.withValues(alpha: 0.7)
            : Colors.white,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: _uiText(scheme, size: 15, weight: FontWeight.w700),
      ),
      dividerTheme: DividerThemeData(
        color: isCyber
            ? electricBlue.withValues(alpha: 0.18)
            : _defaultLineBlue,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: panelBackgroundStrong,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      iconTheme: IconThemeData(
        color: isCyber ? electricBlue : _defaultTextMuted,
        size: 18,
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: _uiText(scheme, size: 12, weight: FontWeight.w700),
        unselectedLabelStyle: _uiText(scheme, size: 12, color: textMuted),
        labelColor: isCyber ? electricBlue : _defaultTextPrimary,
        unselectedLabelColor: textMuted,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: isCyber
              ? electricBlue.withValues(alpha: 0.14)
              : const Color(0xFFF1F3F6),
          border: Border.all(
            color: isCyber
                ? electricBlue.withValues(alpha: 0.45)
                : _defaultLineBlue,
          ),
          boxShadow: isCyber
              ? [
                  BoxShadow(
                    color: electricBlue.withValues(alpha: 0.2),
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
        labelStyle: _uiText(scheme, size: 12, color: textMuted),
        filled: true,
        fillColor: isCyber
            ? panelBackgroundStrong.withValues(alpha: 0.66)
            : const Color(0xFFFAFBFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        prefixIconColor: textMuted,
        border: _inputBorder(
          isCyber ? electricBlue.withValues(alpha: 0.18) : _defaultLineBlue,
        ),
        enabledBorder: _inputBorder(
          isCyber ? electricBlue.withValues(alpha: 0.22) : _defaultLineBlue,
        ),
        focusedBorder: _inputBorder(
          isCyber
              ? electricBlue.withValues(alpha: 0.88)
              : _defaultElectricBlue.withValues(alpha: 0.45),
        ),
        disabledBorder: _inputBorder(
          isCyber
              ? electricBlue.withValues(alpha: 0.1)
              : _defaultLineBlue.withValues(alpha: 0.7),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        side: BorderSide(
          color: isCyber
              ? electricBlue.withValues(alpha: 0.6)
              : _defaultTextMuted,
          width: 1.1,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: isCyber ? electricBlue : _defaultTextMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _baseButtonStyle(
          background: isCyber
              ? electricBlue.withValues(alpha: 0.88)
              : _defaultTextPrimary,
          foreground: isCyber ? const Color(0xFF021318) : Colors.white,
          borderColor: isCyber
              ? electricBlue.withValues(alpha: 0.88)
              : _defaultTextPrimary,
          glowColor: isCyber
              ? electricBlue.withValues(alpha: 0.36)
              : Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _baseButtonStyle(
          background: isCyber
              ? electricBlue.withValues(alpha: 0.06)
              : Colors.white,
          foreground: textPrimary,
          borderColor: isCyber
              ? electricBlue.withValues(alpha: 0.44)
              : _defaultLineBlue,
          glowColor: isCyber
              ? electricBlue.withValues(alpha: 0.24)
              : Colors.transparent,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: _baseButtonStyle(
          background: isCyber
              ? electricBlue.withValues(alpha: 0.15)
              : const Color(0xFFF1F3F6),
          foreground: isCyber ? electricBlue : _defaultTextPrimary,
          borderColor: isCyber
              ? electricBlue.withValues(alpha: 0.4)
              : _defaultLineBlue,
          glowColor: isCyber
              ? electricBlue.withValues(alpha: 0.28)
              : Colors.transparent,
          minSize: const Size(40, 38),
          padding: const EdgeInsets.all(8),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: neonGreen,
        linearTrackColor: electricBlue.withValues(alpha: 0.2),
      ),
    );
  }

  static BoxDecoration panelDecoration({bool active = false}) {
    final borderColor = isCyber
        ? electricBlue.withValues(alpha: active ? 0.82 : 0.32)
        : _defaultLineBlue;

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isCyber
            ? const [Color(0xCC192130), Color(0xCC121B28), Color(0xB70E1622)]
            : const [Colors.white, Colors.white],
      ),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: borderColor, width: 1),
      boxShadow: isCyber
          ? [
              BoxShadow(
                color: electricBlue.withValues(alpha: active ? 0.24 : 0.12),
                blurRadius: active ? 28 : 18,
                spreadRadius: active ? -4 : -8,
              ),
            ]
          : const [],
    );
  }

  static BoxDecoration gridShellDecoration({bool active = false}) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isCyber
            ? [
                const Color(0xCC1C2837),
                if (active)
                  const Color(0xB3243952)
                else
                  const Color(0xB3172433),
              ]
            : [Colors.white, Colors.white],
      ),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: active
            ? electricBlue.withValues(alpha: isCyber ? 0.88 : 0.55)
            : isCyber
            ? electricBlue.withValues(alpha: 0.3)
            : _defaultLineBlue,
      ),
      boxShadow: [
        if (isCyber)
          BoxShadow(
            color: electricBlue.withValues(alpha: active ? 0.24 : 0.1),
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
    return _monoText(size: size, color: color ?? textPrimary, weight: weight);
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
        if (!isCyber) return Colors.transparent;
        if (states.contains(WidgetState.hovered)) return glowColor;
        return glowColor.withValues(alpha: glowColor.a * 0.6);
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return isCyber
              ? electricBlue.withValues(alpha: 0.1)
              : const Color(0xFFE9EDF2);
        }
        if (states.contains(WidgetState.pressed)) {
          return isCyber
              ? neonGreen.withValues(alpha: 0.16)
              : const Color(0xFFDDE3EA);
        }
        return null;
      }),
    );
  }
}
