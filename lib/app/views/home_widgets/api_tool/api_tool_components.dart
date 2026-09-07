part of '../../home_view.dart';

class _ApiToolEnvTokenChip extends StatelessWidget {
  const _ApiToolEnvTokenChip({
    super.key,
    required this.token,
    this.onDragStarted,
  });

  final String token;
  final VoidCallback? onDragStarted;

  @override
  Widget build(BuildContext context) {
    return Draggable<String>(
      data: token,
      maxSimultaneousDrags: 1,
      onDragStarted: onDragStarted,
      feedback: Material(
        type: MaterialType.transparency,
        child: _buildChip(context, floating: true),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: _buildChip(context)),
      child: _buildChip(context),
    );
  }

  Widget _buildChip(BuildContext context, {bool floating = false}) {
    final color = floating
        ? AppCyberTheme.neonGreen
        : AppCyberTheme.electricBlue;
    return Tooltip(
      message: token,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppCyberTheme.baseBackground.withValues(
            alpha: floating ? 0.86 : 0.28,
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.66)),
          boxShadow: floating && AppCyberTheme.isCyber
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.24),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Text(
          token,
          overflow: TextOverflow.ellipsis,
          style: AppCyberTheme.dataTextStyle(
            size: 10.6,
            color: AppCyberTheme.textPrimary,
            weight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _CompactTabLabel extends StatelessWidget {
  const _CompactTabLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _ApiToolSidebarActionButton extends StatelessWidget {
  const _ApiToolSidebarActionButton({
    required this.buttonKey,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final Key buttonKey;
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 40,
        child: OutlinedButton(
          key: buttonKey,
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(40),
            fixedSize: const Size.square(40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: IconTheme.merge(
            data: const IconThemeData(size: 19),
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

class _ApiToolSearchCountBadge extends StatelessWidget {
  const _ApiToolSearchCountBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      widthFactor: 1,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        constraints: const BoxConstraints(minWidth: 28),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppCyberTheme.baseBackground.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppCyberTheme.electricBlue.withValues(alpha: 0.32),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppCyberTheme.dataTextStyle(
            size: 9.8,
            color: AppCyberTheme.textMuted,
            weight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ApiToolEnvDropTarget extends StatelessWidget {
  const _ApiToolEnvDropTarget({
    required this.enabled,
    required this.onAcceptToken,
    required this.child,
  });

  final bool enabled;
  final ValueChanged<String> onAcceptToken;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => _isEnvToken(details.data),
      onAcceptWithDetails: (details) => onAcceptToken(details.data),
      builder: (context, candidates, _) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? AppCyberTheme.neonGreen.withValues(alpha: 0.82)
                  : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: child,
        );
      },
    );
  }

  bool _isEnvToken(String value) {
    final trimmed = value.trim();
    return trimmed.startsWith('{{') && trimmed.endsWith('}}');
  }
}

class _ApiToolEnvTextEditingController extends TextEditingController {
  _ApiToolEnvTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final text = value.text;
    if (text.isEmpty) {
      return TextSpan(style: baseStyle, text: text);
    }

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in _apiToolEnvTokenPattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(
            color: AppCyberTheme.neonGreen,
            fontWeight: FontWeight.w800,
            backgroundColor: AppCyberTheme.neonGreen.withValues(alpha: 0.14),
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return TextSpan(style: baseStyle, children: spans);
  }
}

class _ApiToolHeaderEditor {
  _ApiToolHeaderEditor({
    required this.id,
    String name = '',
    String value = '',
    this.enabled = true,
  }) : nameController = _ApiToolEnvTextEditingController(text: name),
       valueController = _ApiToolEnvTextEditingController(text: value);

  final String id;
  final TextEditingController nameController;
  final TextEditingController valueController;
  bool enabled;

  ApiToolHeader toHeader() {
    return ApiToolHeader(
      id: id,
      name: nameController.text.trim(),
      value: valueController.text,
      enabled: enabled,
    );
  }

  void dispose() {
    nameController.dispose();
    valueController.dispose();
  }
}

class _ApiToolMultipartEditor {
  _ApiToolMultipartEditor({
    required this.id,
    this.kind = ApiToolMultipartKind.text,
    String name = '',
    String value = '',
    String contentType = '',
    this.enabled = true,
  }) : nameController = _ApiToolEnvTextEditingController(text: name),
       valueController = _ApiToolEnvTextEditingController(text: value),
       contentTypeController = _ApiToolEnvTextEditingController(
         text: contentType,
       );

  final String id;
  ApiToolMultipartKind kind;
  final TextEditingController nameController;
  final TextEditingController valueController;
  final TextEditingController contentTypeController;
  bool enabled;

  ApiToolMultipartEntry toEntry() {
    return ApiToolMultipartEntry(
      id: id,
      kind: kind,
      name: nameController.text.trim(),
      value: valueController.text,
      contentType: contentTypeController.text.trim(),
      enabled: enabled,
    );
  }

  void dispose() {
    nameController.dispose();
    valueController.dispose();
    contentTypeController.dispose();
  }
}

class _ApiToolEmptyTreeMessage extends StatelessWidget {
  const _ApiToolEmptyTreeMessage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppCyberTheme.dataTextStyle(
            size: 11.2,
            color: AppCyberTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

class _ApiToolFolderTile extends StatelessWidget {
  const _ApiToolFolderTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.depth,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final int depth;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: _HudCardShell(
            active: false,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  depth == 0
                      ? Icons.folder_copy_outlined
                      : Icons.folder_outlined,
                  size: 18,
                  color: selected
                      ? AppCyberTheme.neonGreen
                      : AppCyberTheme.electricBlue,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppCyberTheme.dataTextStyle(
                          size: 11.4,
                          color: AppCyberTheme.textPrimary,
                          weight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppCyberTheme.dataTextStyle(
                          size: 10.2,
                          color: AppCyberTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 18,
                  color: AppCyberTheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ApiToolRequestTile extends StatelessWidget {
  const _ApiToolRequestTile({
    super.key,
    required this.method,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.trailing,
    required this.onTap,
  });

  final ApiToolMethod method;
  final String title;
  final String subtitle;
  final bool selected;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: _HudCardShell(
          active: selected,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              _ApiMethodPill(method: method),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppCyberTheme.dataTextStyle(
                        size: 11.3,
                        color: AppCyberTheme.textPrimary,
                        weight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppCyberTheme.dataTextStyle(
                        size: 10.2,
                        color: AppCyberTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                style: AppCyberTheme.dataTextStyle(
                  size: 9.8,
                  color: AppCyberTheme.textMuted,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Industry-standard method colors shared by every API Tool surface.
Color _apiToolMethodColor(ApiToolMethod method) {
  return switch (method) {
    ApiToolMethod.get =>
      AppCyberTheme.isCyber ? const Color(0xFF00F3FF) : const Color(0xFF10B981),
    ApiToolMethod.post => const Color(0xFFF59E0B),
    ApiToolMethod.put => const Color(0xFF3B82F6),
    ApiToolMethod.patch => const Color(0xFF8B5CF6),
    ApiToolMethod.delete => const Color(0xFFEF4444),
  };
}

class _ApiMethodPill extends StatelessWidget {
  const _ApiMethodPill({required this.method});

  final ApiToolMethod method;

  @override
  Widget build(BuildContext context) {
    final color = _apiToolMethodColor(method);
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Text(
        method.label,
        textAlign: TextAlign.center,
        style: AppCyberTheme.dataTextStyle(
          size: 9.8,
          color: color,
          weight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ApiToolCodeBlock extends StatelessWidget {
  const _ApiToolCodeBlock({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppCyberTheme.baseBackground.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppCyberTheme.electricBlue.withValues(alpha: 0.2),
        ),
      ),
      child: SelectableText(
        text,
        style: AppCyberTheme.dataTextStyle(
          size: 11.2,
          color: AppCyberTheme.textPrimary,
        ).copyWith(height: 1.4),
      ),
    );
  }
}

class _ApiToolMessage extends StatelessWidget {
  const _ApiToolMessage({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              message,
              style: AppCyberTheme.dataTextStyle(
                size: 11.3,
                color: AppCyberTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle glass pill used by the omnibar meta bar for collection/environment
/// selectors. Keeps the dropdown chrome out of the way while staying tappable.
class _ApiToolMetaPill extends StatelessWidget {
  const _ApiToolMetaPill({
    required this.icon,
    required this.child,
    this.width,
    this.highlighted = false,
  });

  final IconData icon;
  final Widget child;
  final double? width;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final accent = highlighted
        ? AppCyberTheme.neonGreen
        : AppCyberTheme.electricBlue;
    return Container(
      width: width,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: highlighted ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 6),
          if (width == null) child else Expanded(child: child),
        ],
      ),
    );
  }
}

/// Tab label with an optional trailing count badge or configured-state dot.
class _ApiToolTabLabel extends StatelessWidget {
  const _ApiToolTabLabel({
    required this.icon,
    required this.label,
    this.count,
    this.tag,
    this.marked = false,
  });

  final IconData icon;
  final String label;
  final int? count;
  final String? tag;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final tagLabel = tag?.trim() ?? '';
    final badge = (count ?? 0) > 0
        ? count.toString()
        : tagLabel.isNotEmpty
        ? tagLabel
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showIcon = constraints.maxWidth >= 100;
        // A tab strip divides its width evenly, so a long label plus a badge can
        // outgrow its slot; scaling down beats an overflow stripe.
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showIcon) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppCyberTheme.electricBlue.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppCyberTheme.electricBlue.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    badge,
                    style: AppCyberTheme.dataTextStyle(
                      size: 8.8,
                      color: AppCyberTheme.electricBlue,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
              ] else if (marked) ...[
                const SizedBox(width: 5),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: AppCyberTheme.neonGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppCyberTheme.neonGreen.withValues(alpha: 0.55),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Compact text button used by the request/response mini toolbars
/// (Beautify, Clear, Copy as cURL...).
class _ApiToolInlineAction extends StatelessWidget {
  const _ApiToolInlineAction({
    required this.actionKey,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  final Key actionKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = TextButton.icon(
      key: actionKey,
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: AppCyberTheme.dataTextStyle(
          size: 10.6,
          color: AppCyberTheme.textPrimary,
          weight: FontWeight.w700,
        ),
      ),
    );
    final message = tooltip;
    return message == null ? button : Tooltip(message: message, child: button);
  }
}

/// Hero status banner for the response inspector: status code, reason phrase,
/// elapsed time and payload size.
class _ApiToolResponseHero extends StatelessWidget {
  const _ApiToolResponseHero({
    required this.statusCode,
    required this.reasonPhrase,
    required this.durationLabel,
    required this.sizeLabel,
    required this.truncated,
  });

  final int statusCode;
  final String reasonPhrase;
  final String durationLabel;
  final String sizeLabel;
  final bool truncated;

  Color get _statusColor {
    if (statusCode >= 500) return const Color(0xFFEF4444);
    if (statusCode >= 400) return const Color(0xFFF59E0B);
    if (statusCode >= 200 && statusCode < 300) {
      return AppCyberTheme.isCyber
          ? AppCyberTheme.neonGreen
          : const Color(0xFF10B981);
    }
    return AppCyberTheme.electricBlue;
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                statusCode.toString(),
                style: AppCyberTheme.dataTextStyle(
                  size: 21,
                  color: color,
                  weight: FontWeight.w900,
                ),
              ),
              if (reasonPhrase.trim().isNotEmpty) ...[
                const SizedBox(width: 7),
                Text(
                  reasonPhrase.trim(),
                  style: AppCyberTheme.dataTextStyle(
                    size: 11.6,
                    color: color,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          _MetaChip(icon: Icons.timer_outlined, label: durationLabel),
          _MetaChip(icon: Icons.inventory_2_outlined, label: sizeLabel),
          if (truncated)
            const _MetaChip(
              icon: Icons.content_cut_outlined,
              label: 'Body truncated',
              highlighted: true,
            ),
        ],
      ),
    );
  }
}

/// Key/value table used by the response Headers tab, with per-row copy.
class _ApiToolHeaderTable extends StatelessWidget {
  const _ApiToolHeaderTable({super.key, required this.entries});

  final List<MapEntry<String, String>> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _ApiToolMessage(
        icon: Icons.view_headline_outlined,
        color: AppCyberTheme.textMuted,
        message: 'This response did not return any header.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            decoration: BoxDecoration(
              color: AppCyberTheme.baseBackground.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppCyberTheme.electricBlue.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 132,
                  child: SelectableText(
                    entry.key,
                    style: AppCyberTheme.dataTextStyle(
                      size: 11,
                      color: AppCyberTheme.electricBlue,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SelectableText(
                    entry.value,
                    style: AppCyberTheme.dataTextStyle(
                      size: 11,
                      color: AppCyberTheme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  key: Key('api-tool-copy-response-header-${entry.key}'),
                  tooltip: 'Copy header',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => unawaited(
                    Clipboard.setData(
                      ClipboardData(text: '${entry.key}: ${entry.value}'),
                    ),
                  ),
                  icon: const Icon(Icons.copy_outlined, size: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
