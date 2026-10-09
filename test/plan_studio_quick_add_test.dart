import 'package:flutter_test/flutter_test.dart';
import 'package:app_management_center/app/modules/plan_studio/services/quick_add_parser.dart';

void main() {
  // Tuesday 29/09/2026.
  final now = DateTime(2026, 9, 29, 10);

  test('plain title has no properties', () {
    final r = parseQuickAdd('  Sửa lỗi   thanh toán ', now);
    expect(r.title, 'Sửa lỗi thanh toán');
    expect(r.hasProperties, isFalse);
  });

  test('priority, labels and due with time', () {
    final r = parseQuickAdd('Sửa lỗi !p1 #mobile #ux ^mai 17h', now);
    expect(r.title, 'Sửa lỗi');
    expect(r.priority, 'P1');
    expect(r.labels, ['mobile', 'ux']);
    expect(r.due, DateTime(2026, 9, 30, 17));
    expect(r.allDay, isFalse);
    expect(r.tokens.map((t) => t.kind), [
      QuickTokenKind.priority,
      QuickTokenKind.label,
      QuickTokenKind.label,
      QuickTokenKind.due,
    ]);
  });

  test('day words with and without diacritics', () {
    DateTime? due(String s) => parseQuickAdd('x $s', now).due;
    expect(due('^hôm nay'), DateTime(2026, 9, 29));
    expect(due('^hn'), DateTime(2026, 9, 29));
    expect(due('^ngày mai'), DateTime(2026, 9, 30));
    expect(due('^mốt'), DateTime(2026, 10, 1));
    expect(due('^t6'), DateTime(2026, 10, 2));
    expect(due('^thứ 3'), DateTime(2026, 9, 29));
    expect(due('^t2'), DateTime(2026, 10, 5));
    expect(due('^cn'), DateTime(2026, 10, 4));
    expect(due('^cuối tuần'), DateTime(2026, 10, 3));
    expect(due('^tuần sau'), DateTime(2026, 10, 5));
    expect(parseQuickAdd('x ^hôm nay', now).allDay, isTrue);
  });

  test('dates and times', () {
    DateTime? due(String s) => parseQuickAdd('x $s', now).due;
    expect(due('^25/10'), DateTime(2026, 10, 25));
    expect(due('^5/1'), DateTime(2027, 1, 5));
    expect(due('^20/9'), DateTime(2026, 9, 20));
    expect(due('^1/2/2027 9:30'), DateTime(2027, 2, 1, 9, 30));
    expect(due('^t6 8h45'), DateTime(2026, 10, 2, 8, 45));
    expect(due('^17h'), DateTime(2026, 9, 29, 17));
    expect(due('^14:05'), DateTime(2026, 9, 29, 14, 5));
  });

  test('malformed tokens stay in the title', () {
    final r = parseQuickAdd('Họp ^31/2 !p9 ^25h ^abc a#b', now);
    expect(r.due, isNull);
    expect(r.priority, isNull);
    expect(r.title, 'Họp ^31/2 !p9 ^25h ^abc a#b');
  });

  test('token ranges point into the original text', () {
    const input = 'Đặt lịch họp #đội ^thứ 6';
    final r = parseQuickAdd(input, now);
    final label = r.tokens.firstWhere((t) => t.kind == QuickTokenKind.label);
    final due = r.tokens.firstWhere((t) => t.kind == QuickTokenKind.due);
    expect(label.range.textInside(input), '#đội');
    expect(due.range.textInside(input), '^thứ 6');
    expect(r.labels, ['đội']);
    expect(r.title, 'Đặt lịch họp');
  });

  test('fold keeps length', () {
    const s = 'Tiếng Việt ĐƯỢC';
    expect(foldVietnamese(s), 'tieng viet duoc');
    expect(foldVietnamese(s).length, s.length);
  });
}
