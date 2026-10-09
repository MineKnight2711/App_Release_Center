import 'package:app_management_center/app/theme/cyber_theme.dart';
import 'package:flutter/material.dart';

import '../models/bundle_check_models.dart';

Color checkStatusColor(BuildContext context, CheckStatus status) {
  return switch (status) {
    CheckStatus.pass => AppCyberTheme.success,
    CheckStatus.info => AppCyberTheme.info,
    CheckStatus.warn => AppCyberTheme.warning,
    CheckStatus.fail => AppCyberTheme.danger,
    CheckStatus.skip => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

IconData checkStatusIcon(CheckStatus status) {
  return switch (status) {
    CheckStatus.pass => Icons.check_circle_outline,
    CheckStatus.info => Icons.info_outline,
    CheckStatus.warn => Icons.warning_amber_rounded,
    CheckStatus.fail => Icons.cancel_outlined,
    CheckStatus.skip => Icons.remove_circle_outline,
  };
}

/// One check: status, title, the sentence that explains it, and — for the
/// ones that need attention — the specifics and a way to fix it.
class CheckResultTile extends StatefulWidget {
  const CheckResultTile({super.key, required this.result});

  final CheckResult result;

  @override
  State<CheckResultTile> createState() => _CheckResultTileState();
}

class _CheckResultTileState extends State<CheckResultTile> {
  static const _collapsedItems = 6;

  // Problems open with their specifics showing; everything else keeps them
  // one click away so a clean report stays short.
  late bool _expanded =
      widget.result.status == CheckStatus.fail ||
      widget.result.status == CheckStatus.warn;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;
    final color = checkStatusColor(context, result.status);
    final hasMore = result.items.isNotEmpty || result.hint.isNotEmpty;
    final items = _showAll
        ? result.items
        : result.items.take(_collapsedItems).toList();

    return InkWell(
      key: Key('bundle-check-result-${result.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: hasMore ? () => setState(() => _expanded = !_expanded) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: result.status.label,
              child: Icon(
                checkStatusIcon(result.status),
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${result.id}  ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        TextSpan(
                          text: result.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (result.detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    SelectableText(
                      result.detail,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ],
                  if (_expanded && result.items.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: SelectableText(
                          '• $item',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'Consolas',
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (result.items.length > _collapsedItems)
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => setState(() => _showAll = !_showAll),
                        child: Text(
                          _showAll
                              ? 'Thu gọn'
                              : 'Xem thêm ${result.items.length - _collapsedItems}',
                        ),
                      ),
                  ],
                  if (_expanded && result.hint.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            result.hint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (hasMore)
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

/// A count of results in one status, e.g. "3 lỗi".
class StatusCount extends StatelessWidget {
  const StatusCount({super.key, required this.status, required this.count});

  final CheckStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = checkStatusColor(context, status);
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(checkStatusIcon(status), size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          '$count ${status.label.toLowerCase()}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: count == 0 ? theme.colorScheme.onSurfaceVariant : color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
