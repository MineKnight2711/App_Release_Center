import 'package:flutter/material.dart';
import '../services/bulk_add_parser.dart';
import '../services/deadline.dart';
import '../services/quick_add_parser.dart';
import '../theme/studio_tokens.dart';
import 'studio_chip.dart';

/// Highlights `!p1`, `#nhãn` and `^mai 17h` as they are typed.
class QuickAddController extends TextEditingController {
  QuickAddController({super.text});
  DateTime Function() clock = DateTime.now;
  QuickAdd get parsed => parseQuickAdd(text, clock());

  /// Token ranges to color, relative to [text].
  List<QuickToken> get highlights => parsed.tokens;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Leave IME composition (Telex/VNI) to the default rendering.
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final found = highlights;
    if (found.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final tokens = StudioTokens.of(context);
    final spans = <TextSpan>[];
    var at = 0;
    for (final t in found) {
      if (t.range.start > at) {
        spans.add(TextSpan(text: text.substring(at, t.range.start)));
      }
      final color = switch (t.kind) {
        QuickTokenKind.due => tokens.palette.warning,
        // Per token, so lines of different priority keep their own color.
        QuickTokenKind.priority =>
          tokens.priority(t.priority ?? '') ?? tokens.muted,
        QuickTokenKind.label => tokens.palette.info,
      };
      spans.add(
        TextSpan(
          text: t.range.textInside(text),
          style: TextStyle(
            color: color,
            backgroundColor: color.withValues(alpha: 0.14),
          ),
        ),
      );
      at = t.range.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
  }
}

/// The bulk composer: every line is read on its own, as [parseBulkAdd] does.
class BulkAddController extends QuickAddController {
  BulkAddController({super.text});
  List<BulkLine> get lines => parseBulkAdd(text, clock());

  @override
  List<QuickToken> get highlights => [
    for (final line in lines)
      for (final t in line.parsed.tokens)
        QuickToken(
          t.kind,
          TextRange(
            start: line.offset + t.range.start,
            end: line.offset + t.range.end,
          ),
          priority: t.priority,
        ),
  ];
}

/// What the inline syntax resolved to, shown under the field.
class QuickAddSummary extends StatelessWidget {
  const QuickAddSummary(this.parsed, {super.key});
  final QuickAdd parsed;

  @override
  Widget build(BuildContext context) {
    if (!parsed.hasProperties) return const SizedBox.shrink();
    final tokens = StudioTokens.of(context);
    final neutral = ToneColors(tokens.muted, Colors.transparent, tokens.line);
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        if (parsed.due != null)
          StudioChip(
            icon: Icons.flag_outlined,
            label: dueFullAt(parsed.due!, allDay: parsed.allDay),
            tone: tokens.tone(tokens.palette.warning),
          ),
        if (parsed.priority != null)
          StudioChip(
            icon: Icons.flag,
            label: parsed.priority!,
            tone: tokens.priority(parsed.priority!) == null
                ? neutral
                : tokens.tone(tokens.priority(parsed.priority!)!),
          ),
        for (final l in parsed.labels)
          StudioChip(label: '#$l', tone: tokens.tone(tokens.palette.info)),
      ],
    );
  }
}

const quickAddHint = '!p1  #nhãn  ^mai 17h';
