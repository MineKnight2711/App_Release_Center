/// Vietnamese subject normalisation, which every match in this module rests on.
///
/// Email Pro's IMAP server hands subjects over encoded as `=?UTF-8?B?...?=`
/// and its own SEARCH cannot find an accented keyword, so all matching has to
/// happen on this machine once the header has been decoded.
library;

const Map<String, String> _accents = {
  'à': 'a',
  'á': 'a',
  'ạ': 'a',
  'ả': 'a',
  'ã': 'a',
  'â': 'a',
  'ầ': 'a',
  'ấ': 'a',
  'ậ': 'a',
  'ẩ': 'a',
  'ẫ': 'a',
  'ă': 'a',
  'ằ': 'a',
  'ắ': 'a',
  'ặ': 'a',
  'ẳ': 'a',
  'ẵ': 'a',
  'è': 'e',
  'é': 'e',
  'ẹ': 'e',
  'ẻ': 'e',
  'ẽ': 'e',
  'ê': 'e',
  'ề': 'e',
  'ế': 'e',
  'ệ': 'e',
  'ể': 'e',
  'ễ': 'e',
  'ì': 'i',
  'í': 'i',
  'ị': 'i',
  'ỉ': 'i',
  'ĩ': 'i',
  'ò': 'o',
  'ó': 'o',
  'ọ': 'o',
  'ỏ': 'o',
  'õ': 'o',
  'ô': 'o',
  'ồ': 'o',
  'ố': 'o',
  'ộ': 'o',
  'ổ': 'o',
  'ỗ': 'o',
  'ơ': 'o',
  'ờ': 'o',
  'ớ': 'o',
  'ợ': 'o',
  'ở': 'o',
  'ỡ': 'o',
  'ù': 'u',
  'ú': 'u',
  'ụ': 'u',
  'ủ': 'u',
  'ũ': 'u',
  'ư': 'u',
  'ừ': 'u',
  'ứ': 'u',
  'ự': 'u',
  'ử': 'u',
  'ữ': 'u',
  'ỳ': 'y',
  'ý': 'y',
  'ỵ': 'y',
  'ỷ': 'y',
  'ỹ': 'y',
  'đ': 'd',
};

final RegExp _whitespace = RegExp(r'\s+');

/// Drops accents, collapses whitespace and upper-cases.
///
/// `'[YÊU CẦU MỞ]  TÀI  KHOẢN'` becomes `'[YEU CAU MO] TAI KHOAN'`.
String normalizeSubject(String subject) {
  final buffer = StringBuffer();
  for (final character in subject.toLowerCase().split('')) {
    buffer.write(_accents[character] ?? character);
  }
  return buffer.toString().replaceAll(_whitespace, ' ').trim().toUpperCase();
}

/// Reply and forward prefixes, which may repeat (`'Re: Trả lời: ...'`).
final RegExp replyPrefix = RegExp(r'^((RE|FW|FWD|TRA LOI)\s*:\s*)+');

/// Whether this subject belongs to a reply or a forward.
bool isReplySubject(String subject) =>
    replyPrefix.hasMatch(normalizeSubject(subject));

/// Drops every `Re:` / `Fwd:` prefix from an already normalised subject.
String stripReplyPrefix(String normalizedSubject) =>
    normalizedSubject.replaceFirst(replyPrefix, '');

final RegExp _bracketLabel = RegExp(r'^\[([^\]]{1,40})\]');

/// Extracts the "group signature" of a subject, used to pile like with like.
///
/// A bracketed label wins (`[GTEL-VOICE]`, `[YÊU CẦU MỞ]`); failing that, the
/// first three words stand in for one.
String groupSignature(String subject) {
  final normalized = stripReplyPrefix(normalizeSubject(subject));

  final label = _bracketLabel.firstMatch(normalized);
  if (label != null) return '[${label.group(1)!.trim()}]';

  final words = normalized
      .split(' ')
      .where((word) => word.isNotEmpty)
      .take(3)
      .toList();
  if (words.isEmpty) return '(không tiêu đề)';
  return words.join(' ');
}
