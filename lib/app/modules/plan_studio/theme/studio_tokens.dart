import 'package:flutter/material.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/cyber_theme.dart';
import '../models/work_item.dart';
import '../services/deadline.dart';

class ToneColors {
  const ToneColors(this.fg, this.bg, this.border);
  final Color fg, bg, border;
}

/// Plan Studio's visual vocabulary, derived from the active AMC palette so the
/// board follows Console, Cyber and Default without per-theme branches.
class StudioTokens {
  StudioTokens._(this.palette, this.scheme);

  /// Reading [Theme] ties rebuilds to theme switches; the palette itself is the
  /// one [AppCyberTheme.themeData] activated for that theme.
  factory StudioTokens.of(BuildContext context) => StudioTokens._(
    AppCyberTheme.activePalette,
    Theme.of(context).colorScheme,
  );

  final AppPalette palette;
  final ColorScheme scheme;

  static const chipRadius = 6.0, cardRadius = 10.0, panelRadius = 14.0;
  static const columnWidth = 292.0, railWidth = 44.0;
  static const tabular = [FontFeature.tabularFigures()];

  Color get muted => palette.textMuted;
  Color get faint => palette.textFaint;
  Color get line => scheme.outlineVariant.withValues(alpha: 0.55);

  /// Column well: one step below cards so they lift off it in light themes.
  Color get column =>
      palette.isDark ? scheme.surfaceContainerLow : palette.surfaceHighest;

  /// Borderless compact icon button for dense headers.
  ButtonStyle get quietIcon => IconButton.styleFrom(
    side: BorderSide.none,
    backgroundColor: Colors.transparent,
    foregroundColor: palette.textMuted,
    minimumSize: const Size(30, 30),
    fixedSize: const Size(30, 30),
    padding: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  // The palette has no violet; rotate info's hue so it stays in the theme's
  // saturation and lightness band, lifted a little on dark backgrounds.
  Color get _violet {
    final hsl = HSLColor.fromColor(palette.info);
    return hsl
        .withHue(265)
        .withLightness(
          palette.isDark ? hsl.lightness.clamp(0.66, 0.8) : hsl.lightness,
        )
        .toColor();
  }

  Color status(WorkStatus status) => switch (status) {
    WorkStatus.backlog => palette.idle,
    WorkStatus.ready => palette.info,
    WorkStatus.inProgress => _violet,
    // Orange: distinct from overdue red while still reading as a problem.
    WorkStatus.blocked => Color.lerp(palette.danger, palette.warning, 0.45)!,
    WorkStatus.review => palette.warning,
    WorkStatus.done => palette.success,
  };

  /// Accent for P0/P1 only; lower priorities stay unmarked.
  Color? priority(String priority) => switch (priority) {
    'P0' => palette.danger,
    'P1' => palette.warning,
    _ => null,
  };

  ToneColors due(DueState state) => switch (state) {
    DueState.overdue => ToneColors(
      palette.danger,
      palette.dangerSoft,
      palette.dangerBorder,
    ),
    DueState.today => ToneColors(
      palette.warning,
      palette.warningSoft,
      palette.warningBorder,
    ),
    DueState.soon => ToneColors(
      palette.warning,
      Colors.transparent,
      palette.warningBorder,
    ),
    DueState.thisWeek => ToneColors(
      palette.textPrimary,
      Colors.transparent,
      palette.lineStrong,
    ),
    DueState.later || DueState.none => ToneColors(
      palette.textMuted,
      Colors.transparent,
      palette.line,
    ),
    DueState.doneOnTime => ToneColors(
      palette.success,
      palette.successSoft,
      palette.successBorder,
    ),
    DueState.doneLate => ToneColors(
      palette.textFaint,
      Colors.transparent,
      palette.line,
    ),
  };

  ToneColors tone(Color color) => ToneColors(
    color,
    color.withValues(alpha: 0.14),
    color.withValues(alpha: 0.42),
  );
}

const workTypeLabels = {
  WorkType.plan: 'Plan',
  WorkType.task: 'Task',
  WorkType.note: 'Note',
};

IconData workTypeIcon(WorkType type) => switch (type) {
  WorkType.plan => Icons.layers_outlined,
  WorkType.task => Icons.check_box_outline_blank,
  WorkType.note => Icons.sticky_note_2_outlined,
};
