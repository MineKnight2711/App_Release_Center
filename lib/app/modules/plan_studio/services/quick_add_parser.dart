import 'package:flutter/painting.dart';

enum QuickTokenKind { priority, label, due }

class QuickToken {
  const QuickToken(this.kind, this.range, {this.priority});
  final QuickTokenKind kind;
  final TextRange range;

  /// What a priority token resolves to, e.g. `P1`.
  final String? priority;
}

/// Result of reading `Sửa lỗi !p1 #mobile ^mai 17h`.
class QuickAdd {
  const QuickAdd({
    required this.title,
    this.priority,
    this.labels = const [],
    this.due,
    this.allDay = true,
    this.tokens = const [],
  });
  final String title;
  final String? priority;
  final List<String> labels;

  /// Local day (all-day) or local moment.
  final DateTime? due;
  final bool allDay;
  final List<QuickToken> tokens;
  bool get hasProperties =>
      priority != null || labels.isNotEmpty || due != null;
}

const _fold = {
  'àáảãạăằắẳẵặâầấẩẫậ': 'a',
  'èéẻẽẹêềếểễệ': 'e',
  'ìíỉĩị': 'i',
  'òóỏõọôồốổỗộơờớởỡợ': 'o',
  'ùúủũụưừứửữự': 'u',
  'ỳýỷỹỵ': 'y',
  'đ': 'd',
};

/// Lowercases and strips Vietnamese diacritics one character for one, so
/// indexes in the folded text still point into the original.
String foldVietnamese(String value) {
  final out = StringBuffer();
  for (final ch in value.toLowerCase().split('')) {
    var mapped = ch;
    for (final e in _fold.entries) {
      if (e.key.contains(ch)) {
        mapped = e.value;
        break;
      }
    }
    out.write(mapped);
  }
  return out.toString();
}

final _priority = RegExp(r'(?<=^|\s)!p([0-3])(?=\s|$)');
final _label = RegExp(r'(?<=^|\s)#([^\s#!^]+)');
const _time = r'(\d{1,2})(?:h(\d{2})?|:(\d{2}))';
final _due = RegExp(
  r'(?<=^|\s)\^(?:'
  r'(hom nay|homnay|hn|ngay mai|mai|mot|tuan sau|tuansau|cuoi tuan|'
  r'chu nhat|cn|thu [2-7]|t[2-7]|\d{1,2}/\d{1,2}(?:/\d{4})?)'
  '(?:\\s+$_time)?|$_time)'
  r'(?=\s|$)',
);

/// Parses the inline syntax. Unknown or malformed tokens stay in the title, so
/// the user never loses what they typed.
QuickAdd parseQuickAdd(String input, DateTime now) {
  final folded = foldVietnamese(input);
  final tokens = <QuickToken>[];
  bool free(int start, int end) =>
      tokens.every((t) => end <= t.range.start || start >= t.range.end);

  String? priority;
  for (final m in _priority.allMatches(folded)) {
    priority = 'P${m.group(1)}';
    tokens.add(
      QuickToken(
        QuickTokenKind.priority,
        TextRange(start: m.start, end: m.end),
        priority: priority,
      ),
    );
  }

  DateTime? due;
  var allDay = true;
  for (final m in _due.allMatches(folded)) {
    if (!free(m.start, m.end)) continue;
    final day = m.group(1) == null ? _today(now) : _day(m.group(1)!, now);
    if (day == null) continue;
    final hour = m.group(2) ?? m.group(5);
    final minute = m.group(3) ?? m.group(4) ?? m.group(6) ?? m.group(7);
    if (hour != null) {
      final h = int.parse(hour), mm = int.tryParse(minute ?? '0') ?? 0;
      if (h > 23 || mm > 59) continue;
      due = DateTime(day.year, day.month, day.day, h, mm);
      allDay = false;
    } else {
      due = day;
      allDay = true;
    }
    tokens.add(
      QuickToken(QuickTokenKind.due, TextRange(start: m.start, end: m.end)),
    );
  }

  final labels = <String>[];
  for (final m in _label.allMatches(input)) {
    if (!free(m.start, m.end)) continue;
    final name = m.group(1)!;
    if (!labels.contains(name)) labels.add(name);
    tokens.add(
      QuickToken(QuickTokenKind.label, TextRange(start: m.start, end: m.end)),
    );
  }

  tokens.sort((a, b) => a.range.start.compareTo(b.range.start));
  final title = StringBuffer();
  var at = 0;
  for (final t in tokens) {
    title.write(input.substring(at, t.range.start));
    at = t.range.end;
  }
  title.write(input.substring(at));
  return QuickAdd(
    title: title.toString().replaceAll(RegExp(r'\s+'), ' ').trim(),
    priority: priority,
    labels: labels,
    due: due,
    allDay: allDay,
    tokens: tokens,
  );
}

DateTime _today(DateTime now) => DateTime(now.year, now.month, now.day);

DateTime? _day(String word, DateTime now) {
  final today = _today(now);
  DateTime plus(int n) => DateTime(today.year, today.month, today.day + n);
  DateTime weekday(int target) => plus((target - today.weekday) % 7);
  switch (word) {
    case 'hom nay' || 'homnay' || 'hn':
      return today;
    case 'mai' || 'ngay mai':
      return plus(1);
    case 'mot':
      return plus(2);
    case 'tuan sau' || 'tuansau':
      final toMonday = (DateTime.monday - today.weekday) % 7;
      return plus(toMonday == 0 ? 7 : toMonday);
    case 'cuoi tuan':
      return weekday(DateTime.saturday);
    case 'cn' || 'chu nhat':
      return weekday(DateTime.sunday);
  }
  final thu = RegExp(r'^(?:thu |t)([2-7])$').firstMatch(word);
  if (thu != null) return weekday(int.parse(thu.group(1)!) - 1);
  final date = RegExp(r'^(\d{1,2})/(\d{1,2})(?:/(\d{4}))?$').firstMatch(word);
  if (date == null) return null;
  final d = int.parse(date.group(1)!), m = int.parse(date.group(2)!);
  var y = date.group(3) == null ? today.year : int.parse(date.group(3)!);
  if (m < 1 || m > 12 || d < 1 || d > DateTime(y, m + 1, 0).day) return null;
  // Without a year, a date well in the past means next year's.
  if (date.group(3) == null &&
      DateTime(y, m, d).isBefore(today.subtract(const Duration(days: 30)))) {
    y++;
  }
  return DateTime(y, m, d);
}
