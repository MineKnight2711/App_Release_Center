import 'package:flutter/material.dart';
import '../theme/studio_tokens.dart';

/// Read-only Markdown for plan bodies: headings, lists, task lists, quotes,
/// rules, fenced code and inline bold/italic/code/links. Anything else renders
/// as plain text, so nothing the user wrote is hidden.
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.source, {super.key});
  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = StudioTokens.of(context);
    final base = theme.textTheme.bodyMedium?.copyWith(height: 1.55);
    final mono = base?.copyWith(fontFamily: 'Consolas', fontSize: 12.5);
    final blocks = <Widget>[];
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final paragraph = <String>[];
    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(_gap(Text.rich(_inline(paragraph.join(' '), base, theme))));
      paragraph.clear();
    }

    for (var n = 0; n < lines.length; n++) {
      final raw = lines[n];
      final line = raw.trimRight();
      final trimmed = line.trimLeft();
      final indent = (line.length - trimmed.length) ~/ 2;
      if (trimmed.startsWith('```')) {
        flush();
        final code = <String>[];
        for (
          n++;
          n < lines.length && !lines[n].trimLeft().startsWith('```');
          n++
        ) {
          code.add(lines[n]);
        }
        blocks.add(
          _gap(
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.column,
                borderRadius: BorderRadius.circular(StudioTokens.chipRadius),
                border: Border.all(color: tokens.line),
              ),
              child: Text(code.join('\n'), style: mono),
            ),
          ),
        );
        continue;
      }
      if (trimmed.isEmpty) {
        flush();
        continue;
      }
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        flush();
        final level = heading.group(1)!.length;
        final style = switch (level) {
          1 => theme.textTheme.titleLarge,
          2 => theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          _ => theme.textTheme.titleSmall,
        };
        blocks.add(
          Padding(
            padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 10, bottom: 4),
            child: Text.rich(_inline(heading.group(2)!, style, theme)),
          ),
        );
        continue;
      }
      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
        flush();
        blocks.add(Divider(height: 20, color: tokens.line));
        continue;
      }
      if (trimmed.startsWith('>')) {
        flush();
        blocks.add(
          _gap(
            Container(
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: tokens.line, width: 3)),
              ),
              child: Text.rich(
                _inline(
                  trimmed.replaceFirst(RegExp(r'^>\s?'), ''),
                  base?.copyWith(color: tokens.muted),
                  theme,
                ),
              ),
            ),
          ),
        );
        continue;
      }
      final task = RegExp(r'^[-*+]\s+\[([ xX])\]\s+(.*)$').firstMatch(trimmed);
      final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
      final number = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(trimmed);
      if (task != null || bullet != null || number != null) {
        flush();
        final done = task != null && task.group(1)!.toLowerCase() == 'x';
        final Widget marker = task != null
            ? Icon(
                done ? Icons.check_box : Icons.check_box_outline_blank,
                size: 16,
                color: done ? tokens.palette.success : tokens.muted,
              )
            : number != null
            ? Text(
                '${number.group(1)}.',
                style: base?.copyWith(color: tokens.muted),
              )
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Icon(Icons.circle, size: 5, color: tokens.muted),
              );
        final text = task?.group(2) ?? number?.group(2) ?? bullet!.group(1)!;
        blocks.add(
          Padding(
            padding: EdgeInsets.only(left: 4 + indent * 18.0, bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: marker,
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    _inline(
                      text,
                      done
                          ? base?.copyWith(
                              color: tokens.muted,
                              decoration: TextDecoration.lineThrough,
                            )
                          : base,
                      theme,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }
      paragraph.add(trimmed);
    }
    flush();
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks,
      ),
    );
  }

  Widget _gap(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: child);
}

final _inlinePattern = RegExp(
  r'(\*\*[^*]+\*\*|__[^_]+__|`[^`]+`|\*[^*\s][^*]*\*|\[[^\]]+\]\([^)]+\))',
);

TextSpan _inline(String text, TextStyle? style, ThemeData theme) {
  final spans = <InlineSpan>[];
  var at = 0;
  for (final m in _inlinePattern.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    final t = m.group(0)!;
    if (t.startsWith('**') || t.startsWith('__')) {
      spans.add(
        TextSpan(
          text: t.substring(2, t.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    } else if (t.startsWith('`')) {
      spans.add(
        TextSpan(
          text: t.substring(1, t.length - 1),
          style: TextStyle(
            fontFamily: 'Consolas',
            backgroundColor: theme.colorScheme.onSurface.withValues(
              alpha: 0.08,
            ),
          ),
        ),
      );
    } else if (t.startsWith('[')) {
      spans.add(
        TextSpan(
          text: t.substring(1, t.indexOf(']')),
          style: TextStyle(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: t.substring(1, t.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    }
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: style, children: spans);
}
