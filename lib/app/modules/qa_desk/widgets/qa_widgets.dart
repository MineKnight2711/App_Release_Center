import 'package:flutter/material.dart';

import '../models/qa_models.dart';
import '../theme/qa_tokens.dart';

class QaStatusIcon extends StatelessWidget {
  const QaStatusIcon({super.key, required this.status, this.size = 18});

  final RunStatus? status;
  final double size;

  @override
  Widget build(BuildContext context) => Icon(
    statusIcon(status),
    size: size,
    color: QaTokens.of(context).status(status),
    semanticLabel: statusLabel(status),
  );
}

/// A small capsule: a tag on a suite, a count on a run.
class QaTag extends StatelessWidget {
  const QaTag({super.key, required this.label, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = QaTokens.of(context);
    final tint = color ?? tokens.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: tint),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tint,
              fontWeight: FontWeight.w700,
              fontFeatures: QaTokens.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// A run status as a fixed-width capsule, for columns that line up.
class QaStatusPill extends StatelessWidget {
  const QaStatusPill({super.key, required this.status});

  final RunStatus? status;

  @override
  Widget build(BuildContext context) {
    final color = QaTokens.of(context).status(status);
    return Container(
      width: 78,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        statusLabel(status),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// The title row of a panel: what it is, a quiet line on what it holds, and
/// room for actions on the right.
class QaPanelHeader extends StatelessWidget {
  const QaPanelHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.muted,
                  ),
                ),
            ],
          ),
        ),
        ...trailing,
      ],
    );
  }
}

/// What a panel shows while it has nothing yet, and what to do about it.
class QaEmptyState extends StatelessWidget {
  const QaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 34, color: tokens.faint),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
              ),
              if (action != null) ...[const SizedBox(height: 14), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// One `label  value` line of run metadata.
class QaMetaLine extends StatelessWidget {
  const QaMetaLine({
    super.key,
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final tokens = QaTokens.of(context);
    final style = tokens.mono(size: 11.5);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.muted),
            ),
          ),
          Expanded(
            child: selectable
                ? SelectableText(value, style: style)
                : Text(value, style: style),
          ),
        ],
      ),
    );
  }
}

/// A list row that can be selected: highlighted fill and border when it is.
class QaSelectableRow extends StatelessWidget {
  const QaSelectableRow({
    super.key,
    required this.selected,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(10),
  });

  final bool selected;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final tokens = QaTokens.of(context);
    return Material(
      color: selected ? tokens.selectedFill : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QaTokens.radius),
        side: BorderSide(color: selected ? tokens.selectedBorder : tokens.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(QaTokens.radius),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Two panes stacked with a handle between them to share the height.
class QaVerticalSplit extends StatefulWidget {
  const QaVerticalSplit({
    super.key,
    required this.top,
    required this.bottom,
    this.initialTopFraction = 0.36,
    this.minTop = 90,
    this.minBottom = 140,
  });

  final Widget top;
  final Widget bottom;
  final double initialTopFraction;
  final double minTop;
  final double minBottom;

  @override
  State<QaVerticalSplit> createState() => _QaVerticalSplitState();
}

class _QaVerticalSplitState extends State<QaVerticalSplit> {
  static const _handle = 12.0;
  late double _fraction = widget.initialTopFraction;

  @override
  Widget build(BuildContext context) {
    final tokens = QaTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final usable = (constraints.maxHeight - _handle).clamp(0.0, 1e9);
        final minFraction = usable == 0 ? 0.0 : widget.minTop / usable;
        final maxFraction = usable == 0 ? 1.0 : 1 - widget.minBottom / usable;
        final fraction = minFraction <= maxFraction
            ? _fraction.clamp(minFraction, maxFraction)
            : 0.5;
        final top = usable * fraction;
        return Column(
          children: [
            SizedBox(height: top, child: widget.top),
            MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: usable == 0
                    ? null
                    : (details) => setState(
                        () => _fraction = (top + details.delta.dy) / usable,
                      ),
                child: SizedBox(
                  height: _handle,
                  child: Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: tokens.line,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: widget.bottom),
          ],
        );
      },
    );
  }
}

/// Opens [builder] in a sheet sliding in from the right edge.
///
/// Editors and side tools use this instead of a centred dialog, so the list
/// they belong to stays in view beside them.
Future<T?> showQaSideSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  double width = 480,
  String? subtitle,
  Key? key,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: SafeArea(
        child: SizedBox(
          key: key,
          width: width.clamp(0, MediaQuery.sizeOf(context).width - 24),
          height: double.infinity,
          child: DecoratedBox(
            // Opaque even in Cyber, whose panels are see-through, and a soft
            // shadow rather than Material elevation's hard edge.
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                QaTokens.of(context).palette.panelStrong,
                QaTokens.of(context).palette.base,
              ),
              border: Border(
                left: BorderSide(color: QaTokens.of(context).palette.line),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                    child: QaPanelHeader(
                      title: title,
                      subtitle: subtitle,
                      trailing: [
                        IconButton(
                          tooltip: 'Đóng',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: Builder(builder: builder)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(0.12, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Shows [message] in the page's snack bar.
void showQaMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Asks before something that cannot be taken back.
Future<bool> confirmQa(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

/// Segmented buttons in the palette's terms. The shell sets no segmented
/// theme, and Material's fallback paints the selected segment's label in a
/// colour too close to its fill in every AMC theme.
ButtonStyle qaSegmentedStyle(BuildContext context) {
  final tokens = QaTokens.of(context);
  final palette = tokens.palette;
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? palette.accentSoft
          : Colors.transparent,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? palette.textPrimary
          : palette.textMuted,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? palette.accent
          : palette.textMuted,
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.selected)
            ? palette.accentBorder
            : palette.line,
      ),
    ),
    textStyle: WidgetStatePropertyAll(
      Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

/// A single-choice chip in the palette's terms; Material's selected chip has
/// the same contrast problem as its segmented button under the AMC themes.
class QaChoiceChip extends StatelessWidget {
  const QaChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = QaTokens.of(context).palette;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: true,
      checkmarkColor: palette.accent,
      selectedColor: palette.accentSoft,
      backgroundColor: Colors.transparent,
      side: BorderSide(color: selected ? palette.accentBorder : palette.line),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: selected ? palette.textPrimary : palette.textMuted,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}
