import 'package:flutter/material.dart';

import '../../../theme/app_palette.dart';
import '../../../theme/cyber_theme.dart';
import '../models/qa_models.dart';

/// QA Desk's visual vocabulary, derived from the active AMC palette so every
/// screen follows Console, Cyber and Default without per-theme branches.
///
/// The standalone app hard-coded a light palette; nothing in the module names
/// a colour of its own any more.
class QaTokens {
  QaTokens._(this.palette, this.scheme);

  /// Reading [Theme] ties rebuilds to theme switches; the palette itself is the
  /// one [AppCyberTheme.themeData] activated for that theme.
  factory QaTokens.of(BuildContext context) =>
      QaTokens._(AppCyberTheme.activePalette, Theme.of(context).colorScheme);

  final AppPalette palette;
  final ColorScheme scheme;

  static const radius = 8.0;
  static const tabular = [FontFeature.tabularFigures()];

  Color get text => palette.textPrimary;
  Color get muted => palette.textMuted;
  Color get faint => palette.textFaint;
  Color get line => palette.line;
  Color get accent => scheme.primary;

  /// Row highlight for the selected item of a list.
  Color get selectedFill => palette.accentSoft;
  Color get selectedBorder => palette.accentBorder;

  /// A quiet well behind nested content, one step off the panel.
  Color get well => palette.isDark
      ? palette.surfaceHighest.withValues(alpha: 0.55)
      : palette.surfaceHighest;

  Color status(RunStatus? status) => switch (status) {
    RunStatus.queued || null => palette.idle,
    RunStatus.running => palette.info,
    RunStatus.passed => palette.success,
    RunStatus.failed => palette.danger,
    RunStatus.cancelled => palette.warning,
  };

  // Logs read best light-on-dark in every theme, like a terminal: the light
  // theme borrows its own text colour as the console background.
  Color get consoleBackground =>
      palette.isDark ? palette.base : palette.textPrimary;
  Color get consoleText => palette.isDark ? palette.textPrimary : palette.base;
  Color get consoleMuted =>
      palette.isDark ? palette.textMuted : palette.base.withValues(alpha: 0.62);

  /// The colour of one log line: the echoed command, stderr, or plain output.
  Color consoleLine(String line) {
    if (line.startsWith('> ')) return palette.info;
    if (line.startsWith('[stderr]')) return palette.warning;
    return consoleText;
  }

  TextStyle mono({double size = 12, Color? color, FontWeight? weight}) =>
      AppCyberTheme.dataTextStyle(
        size: size,
        color: color ?? text,
        weight: weight ?? FontWeight.w500,
      );
}

IconData statusIcon(RunStatus? status) => switch (status) {
  RunStatus.queued || null => Icons.schedule,
  RunStatus.running => Icons.sync,
  RunStatus.passed => Icons.check_circle,
  RunStatus.failed => Icons.cancel,
  RunStatus.cancelled => Icons.stop_circle,
};

String statusLabel(RunStatus? status) => switch (status) {
  null => 'không có',
  RunStatus.queued => 'chờ',
  RunStatus.running => 'đang chạy',
  RunStatus.passed => 'qua',
  RunStatus.failed => 'lỗi',
  RunStatus.cancelled => 'đã dừng',
};

IconData sourceIcon(SourceType type) => switch (type) {
  SourceType.flutter => Icons.flutter_dash,
  SourceType.playwright => Icons.language,
  SourceType.node => Icons.javascript,
  SourceType.unknown => Icons.folder_outlined,
};

/// `41s`, `2m 13s`: for lists, where width is short.
String shortDuration(Duration? duration) {
  if (duration == null) return '--';
  if (duration.inMinutes > 0) {
    return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
  }
  return '${duration.inSeconds}s';
}

/// `41 giây`, `2 phút 13 giây`: for sentences.
String longDuration(Duration? duration) {
  if (duration == null) return '--';
  final seconds = duration.inSeconds.remainder(60);
  if (duration.inMinutes == 0) return '$seconds giây';
  return seconds == 0
      ? '${duration.inMinutes} phút'
      : '${duration.inMinutes} phút $seconds giây';
}

String _two(int number) => number.toString().padLeft(2, '0');

/// `01/10 14:32`.
String shortDateTime(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.day)}/${_two(local.month)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

/// `01/10/2026 14:32`.
String fullDateTime(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.day)}/${_two(local.month)}/${local.year} '
      '${_two(local.hour)}:${_two(local.minute)}';
}
