import 'subject_text.dart';

/// One message in the mailbox, carrying only what cleaning it up needs.
class MailItem {
  MailItem({required this.uid, required this.subject, required this.size})
    : normalized = normalizeSubject(subject),
      group = groupSignature(subject),
      isReply = isReplySubject(subject);

  final int uid;
  final String subject;

  /// Message size in bytes, from `RFC822.SIZE`.
  final int size;

  /// The subject with accents dropped and upper-cased, used for matching.
  final String normalized;

  /// The group label pulled out of the subject, `[GTEL-VOICE]` for instance.
  final String group;

  /// A `Re:` / `Fwd:` message, which is kept by default.
  final bool isReply;
}

/// How a rule matches a subject.
enum MatchKind {
  startsWith('Bắt đầu bằng'),
  contains('Có chứa'),
  regex('Biểu thức (regex)');

  const MatchKind(this.label);

  final String label;
}

/// One rule picking messages out for deletion.
class SubjectRule {
  SubjectRule({
    required this.pattern,
    this.kind = MatchKind.startsWith,
    this.enabled = true,
    this.autoDetected = false,
  });

  /// The pattern as typed, `[YÊU CẦU MỞ]` for instance.
  final String pattern;
  final MatchKind kind;

  /// Whether this rule is currently being applied.
  bool enabled;

  /// `true` when the rule came out of the automatic analysis step, `false`
  /// when the user typed it.
  final bool autoDetected;

  /// The normalised pattern used for matching; regex patterns skip this.
  late final String _normalizedPattern = normalizeSubject(pattern);

  RegExp? _regex;
  String? _regexError;

  /// The message explaining why the regex will not compile, `null` when it is
  /// valid.
  String? get regexError {
    if (kind != MatchKind.regex) return null;
    _compileRegex();
    return _regexError;
  }

  void _compileRegex() {
    if (_regex != null || _regexError != null) return;
    try {
      _regex = RegExp(pattern, caseSensitive: false);
    } on FormatException catch (e) {
      _regexError = e.message;
    }
  }

  bool matches(MailItem mail) {
    switch (kind) {
      case MatchKind.startsWith:
        // Both the original and the reply-stripped form are tried, so that a
        // "[YÊU CẦU MỞ]" rule still recognises "Re: [YÊU CẦU MỞ] …".
        return mail.normalized.startsWith(_normalizedPattern) ||
            stripReplyPrefix(mail.normalized).startsWith(_normalizedPattern);
      case MatchKind.contains:
        return mail.normalized.contains(_normalizedPattern);
      case MatchKind.regex:
        _compileRegex();
        return _regex?.hasMatch(mail.subject) ?? false;
    }
  }

  SubjectRule copyWith({String? pattern, MatchKind? kind, bool? enabled}) =>
      SubjectRule(
        pattern: pattern ?? this.pattern,
        kind: kind ?? this.kind,
        enabled: enabled ?? this.enabled,
        autoDetected: autoDetected,
      );
}

/// One pile of like messages, the result of scanning the mailbox.
class SubjectGroup {
  SubjectGroup(this.name);

  final String name;
  final List<MailItem> mail = [];

  int get count => mail.length;

  int get totalBytes => mail.fold(0, (sum, item) => sum + item.size);

  int get averageBytes => mail.isEmpty ? 0 : totalBytes ~/ mail.length;

  int get replyCount => mail.where((item) => item.isReply).length;
}

/// Piles messages into groups, heaviest group first.
List<SubjectGroup> groupMail(List<MailItem> mail) {
  final groups = <String, SubjectGroup>{};
  for (final item in mail) {
    (groups[item.group] ??= SubjectGroup(item.group)).mail.add(item);
  }
  return groups.values.toList()
    ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
}

/// Renders a byte count the way a person reads it.
String formatBytes(int bytes) {
  if (bytes >= 1073741824) {
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// Groups thousands with a dot, the Vietnamese convention: `48451` → `48.451`.
String formatCount(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
