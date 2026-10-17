import 'package:flutter/material.dart';

import '../models/safe_item.dart';

extension SafeItemKindLook on SafeItemKind {
  IconData get icon => switch (this) {
    SafeItemKind.password => Icons.password_rounded,
    SafeItemKind.apiKey => Icons.vpn_key_rounded,
    SafeItemKind.env => Icons.tune_rounded,
    SafeItemKind.jsonKey => Icons.data_object_rounded,
    SafeItemKind.note => Icons.sticky_note_2_outlined,
    SafeItemKind.file => Icons.insert_drive_file_outlined,
  };

  Color get tint => switch (this) {
    SafeItemKind.password => const Color(0xFF5B8DEF),
    SafeItemKind.apiKey => const Color(0xFFE0A526),
    SafeItemKind.env => const Color(0xFF3DBE7A),
    SafeItemKind.jsonKey => const Color(0xFF9B7BEA),
    SafeItemKind.note => const Color(0xFF2BB3B1),
    SafeItemKind.file => const Color(0xFFE07B4F),
  };

  /// The field a box's quick-copy button copies, or null when there is
  /// nothing sensible to put on the clipboard.
  String? quickCopy(SafeItem item) => switch (this) {
    SafeItemKind.file => null,
    _ => item.secret.isEmpty ? null : item.secret,
  };

  String get quickCopyLabel => switch (this) {
    SafeItemKind.password => 'Sao chép mật khẩu',
    SafeItemKind.apiKey => 'Sao chép key',
    SafeItemKind.env => 'Sao chép cả file env',
    SafeItemKind.jsonKey => 'Sao chép JSON',
    SafeItemKind.note => 'Sao chép ghi chú',
    SafeItemKind.file => '',
  };
}

String formatSafeDate(DateTime value, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(value);
  if (diff.inSeconds < 60) return 'vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  if (diff.inHours < 24) return '${diff.inHours} giờ trước';
  if (diff.inDays == 1) return 'hôm qua';
  if (diff.inDays < 7) return '${diff.inDays} ngày trước';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year}';
}

String formatSafeTimestamp(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)} '
      '${two(value.day)}/${two(value.month)}/${value.year}';
}

/// A file name for exporting [item], from its title when it has no original.
String suggestedExportName(SafeItem item) {
  // A secret that came from a file goes back out under the same name.
  if (item.fileName.isNotEmpty) return item.fileName;
  final title = item.title.trim();
  final slug = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '-')
      .replaceAll(RegExp('-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  switch (item.kind) {
    case SafeItemKind.env:
      if (slug.startsWith('.env') || slug.endsWith('.env')) return slug;
      return slug.isEmpty ? '.env' : '$slug.env';
    case SafeItemKind.jsonKey:
      if (slug.toLowerCase().endsWith('.json')) return slug;
      return '${slug.isEmpty ? 'key' : slug}.json';
    default:
      return slug.isEmpty ? 'secret.txt' : '$slug.txt';
  }
}
