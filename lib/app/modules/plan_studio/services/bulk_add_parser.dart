import 'package:flutter/painting.dart';
import 'quick_add_parser.dart';

/// Most tasks one bulk create may add, so a stray paste cannot flood the board.
const bulkAddLimit = 200;

/// Blocked reason of a line marked `⏳` or `Chờ phản hồi`.
const bulkWaitingReason = 'Chờ phản hồi';

/// One task line of the bulk composer.
class BulkLine {
  const BulkLine(
    this.offset,
    this.parsed, {
    this.duplicate = false,
    this.waiting = false,
  });

  /// Where [parsed]'s token ranges start in the whole text.
  final int offset;
  final QuickAdd parsed;

  /// Same title as an earlier line; it is not created.
  final bool duplicate;

  /// Marked `⏳` / `Chờ phản hồi`: created blocked, waiting on someone else.
  final bool waiting;
}

// `- `, `* `, `+ `, `• `, `➡️ `, `1. `, `1) ` and Markdown checkboxes, as
// pasted from notes, a report or an AI answer. Every part is optional, so this
// always matches.
final _marker = RegExp(
  '\\s*(?:(?:[-*+•→➜➔►▸]|➡\uFE0F?|▶\uFE0F?)\\s+|\\d{1,3}[.)]\\s+)?'
  r'(?:\[[ xX]\]\s+)?',
);
final _heading = RegExp(r'^\s*#{1,6}\s');

// The report style `🔴 Cao – Tiêu đề`: a colored dot, a priority word, or both,
// read on folded text. A word only counts when a dash or colon follows it, so
// `Cao tốc Đà Nẵng` stays a title.
final _dot = RegExp('(🔴|🟠|🟡|🟢|⏳)\uFE0F?\\s*');
final _word = RegExp(
  r'\*{0,2}(khan cap|khan|gap|rat cao|cao|trung binh|binh thuong|thap|'
  r'cho phan hoi)\*{0,2}\s*[-–—:]\s+',
);
const _levels = {
  '🔴': 'P1',
  '🟠': 'P1',
  '🟡': 'P2',
  '🟢': 'P3',
  'khan cap': 'P0',
  'khan': 'P0',
  'gap': 'P0',
  'rat cao': 'P0',
  'cao': 'P1',
  'trung binh': 'P2',
  'binh thuong': 'P2',
  'thap': 'P3',
};
const _waiting = {'⏳', 'cho phan hoi'};

/// Reads one task per line with the quick-add syntax, plus a leading
/// `🔴 Cao –` style priority. Blank lines, Markdown headings and lines that are
/// only tokens are dropped; a repeated title is kept but marked
/// [BulkLine.duplicate].
List<BulkLine> parseBulkAdd(String input, DateTime now) {
  final lines = <BulkLine>[];
  final seen = <String>{};
  var start = 0;
  for (final raw in input.split('\n')) {
    final at = start;
    start += raw.length + 1;
    if (_heading.hasMatch(raw)) continue;
    final marker = _marker.matchAsPrefix(raw)!.end;
    final body = raw.substring(marker);
    final folded = foldVietnamese(body);
    var prefix = 0;
    String? level;
    var waiting = false;
    for (final pattern in [_dot, _word]) {
      final m = pattern.matchAsPrefix(folded, prefix);
      if (m == null) continue;
      prefix = m.end;
      level = _levels[m[1]];
      waiting = _waiting.contains(m[1]);
    }
    final rest = parseQuickAdd(body.substring(prefix), now);
    if (rest.title.isEmpty) continue;
    final parsed = QuickAdd(
      title: rest.title,
      // An inline `!p0` is the more deliberate choice.
      priority: rest.priority ?? level,
      labels: rest.labels,
      due: rest.due,
      allDay: rest.allDay,
      tokens: [
        if (prefix > 0)
          QuickToken(
            QuickTokenKind.priority,
            TextRange(
              start: 0,
              end: body.substring(0, prefix).trimRight().length,
            ),
            priority: level,
          ),
        for (final t in rest.tokens)
          QuickToken(
            t.kind,
            TextRange(start: prefix + t.range.start, end: prefix + t.range.end),
            priority: t.priority,
          ),
      ],
    );
    lines.add(
      BulkLine(
        at + marker,
        parsed,
        duplicate: !seen.add(parsed.title.toLowerCase()),
        waiting: waiting,
      ),
    );
  }
  return lines;
}
