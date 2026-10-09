import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';

import '../models/mail_item.dart';
import '../services/mail_imap_service.dart';

/// A small figure: quiet label over a large value.
class MailStat extends StatelessWidget {
  const MailStat({
    super.key,
    required this.label,
    required this.value,
    this.suffix,
    this.valueColor,
    this.icon,
  });

  final String label;
  final String value;
  final String? suffix;
  final Color? valueColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Text.rich rather than a Row: these stats sit both in a narrow panel
    // column, where a long label has to wrap, and in a horizontally scrolling
    // action bar, where the width is unbounded and a flexible child would trip
    // RenderFlex. One text span behaves correctly under both.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              if (icon != null)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Icon(
                      icon,
                      size: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              TextSpan(text: label.toUpperCase()),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
              if (suffix != null)
                TextSpan(
                  text: ' ${suffix!}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// How full the mailbox is, as a bar plus the figures behind it.
class QuotaBar extends StatelessWidget {
  const QuotaBar({super.key, required this.quota});

  final MailboxQuota quota;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = quota.ratio >= 0.95
        ? theme.colorScheme.error
        : quota.ratio >= 0.8
        ? AppCyberTheme.amber
        : theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.pie_chart_outline_rounded, size: 15, color: color),
            const SizedBox(width: 8),
            // Expanded, not Flexible beside a Spacer: two flexible children
            // would split the free space and truncate a label that fits.
            Expanded(
              child: Text(
                'Dung lượng hộp thư',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(quota.ratio * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: quota.ratio.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Đã dùng ${formatBytes(quota.used)} / ${formatBytes(quota.limit)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// How much of the heaviest group's size this group accounts for.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.ratio, required this.highlighted});

  final double ratio;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: ratio.clamp(0.0, 1.0),
        minHeight: 6,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation(
          highlighted ? theme.colorScheme.primary : theme.colorScheme.outline,
        ),
      ),
    );
  }
}
