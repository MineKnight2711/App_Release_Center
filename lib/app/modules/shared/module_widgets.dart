import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';

/// A block of the module's own content, wearing the shell's panel treatment.
///
/// The bare Material `Card` disappears into the background in the Default
/// theme, where both are white; going through the shell's own decoration keeps
/// the module looking like the rest of the app in either theme.
class ModuleCard extends StatelessWidget {
  const ModuleCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: AppCyberTheme.panelDecoration(),
      // The decoration paints over the Material behind it, which would swallow
      // the ink of any list tile inside; a transparent Material gives those
      // splashes a surface of their own.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// The heading of one block in the side panel.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
      ),
    );

    // With no action this returns the text alone. That matters: this widget is
    // often placed as a plain child of another Row, where the width constraint
    // is unbounded and a Spacer would collapse the layout.
    final trailing = action;
    if (trailing == null) return label;

    return Row(children: [label, const Spacer(), trailing]);
  }
}

/// How loudly a notice speaks.
enum NoticeTone { info, warning, danger }

/// A boxed notice, from a plain remark to a warning about losing mail.
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.text,
    this.tone = NoticeTone.info,
    this.icon,
  });

  final String text;
  final NoticeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground, toneIcon) = switch (tone) {
      NoticeTone.info => (
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        theme.colorScheme.onSurface,
        Icons.info_outline,
      ),
      NoticeTone.warning => (
        AppCyberTheme.amber.withValues(alpha: 0.16),
        AppCyberTheme.amber,
        Icons.warning_amber_rounded,
      ),
      NoticeTone.danger => (
        theme.colorScheme.error.withValues(alpha: 0.16),
        theme.colorScheme.error,
        Icons.dangerous_outlined,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: foreground.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? toneIcon, size: 17, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tone == NoticeTone.info
                    ? theme.colorScheme.onSurface
                    : foreground,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A capsule for a piece of connection status: SSL, Gmail, flagged mail.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tint),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: tint,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    final message = tooltip;
    return message == null ? chip : Tooltip(message: message, child: chip);
  }
}
