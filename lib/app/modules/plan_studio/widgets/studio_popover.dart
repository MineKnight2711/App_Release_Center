import 'package:flutter/material.dart';
import '../theme/studio_tokens.dart';

/// Global rect of [context]'s render box, used to anchor a popover.
Rect? rectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// A light popover below [anchor] (above when there is no room), or centered
/// without one. Dismissed by clicking outside or Esc.
Future<T?> showStudioPopover<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Rect? anchor,
  double width = 320,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Đóng',
  barrierColor: Colors.black.withValues(alpha: 0.08),
  transitionDuration: const Duration(milliseconds: 140),
  pageBuilder: (context, _, _) {
    final scheme = Theme.of(context).colorScheme;
    return CustomSingleChildLayout(
      delegate: _PopoverLayout(anchor),
      child: SizedBox(
        width: width,
        child: Material(
          color: scheme.surfaceContainerHigh,
          elevation: 10,
          shadowColor: Colors.black54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(StudioTokens.panelRadius),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(child: Builder(builder: builder)),
        ),
      ),
    );
  },
  transitionBuilder: (_, animation, _, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween(begin: 0.97, end: 1.0).animate(curved),
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  },
);

class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout(this.anchor);
  final Rect? anchor;
  static const _margin = 8.0, _gap = 6.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: constraints.maxWidth - 2 * _margin,
        maxHeight: constraints.maxHeight - 2 * _margin,
      );

  @override
  Offset getPositionForChild(Size size, Size child) {
    final a = anchor;
    if (a == null) {
      return Offset(
        (size.width - child.width) / 2,
        (size.height - child.height) / 2,
      );
    }
    double clamp(double v, double max) =>
        v.clamp(_margin, (max).clamp(_margin, double.infinity)).toDouble();
    final x = clamp(a.left, size.width - child.width - _margin);
    final below = a.bottom + _gap;
    final above = a.top - _gap - child.height;
    final y = below + child.height <= size.height - _margin
        ? below
        : above >= _margin
        ? above
        : clamp(below, size.height - child.height - _margin);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopoverLayout old) => old.anchor != anchor;
}
