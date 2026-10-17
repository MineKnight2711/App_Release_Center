import 'dart:convert';
import 'dart:typed_data';

import 'package:app_management_center/app/modules/bundle_check/services/env_file.dart';

/// What one deposit box in the safe holds.
///
/// Every kind keeps its payload in [SafeItem.secret]; the kind decides how
/// that string is read (a password, a whole `.env`, a JSON document, a file as
/// base64) and which of the other fields the editor shows.
enum SafeItemKind {
  password('Mật khẩu', 'Tài khoản và mật khẩu đăng nhập'),
  apiKey('API key', 'Key, token, secret của dịch vụ'),
  env('Env', 'Cả file .env, KEY=VALUE mỗi dòng'),
  jsonKey('JSON key', 'Service account, google-services, cấu hình JSON'),
  note('Ghi chú', 'Văn bản bí mật bất kỳ'),
  file('Tệp', 'Keystore, .p8, .pem, chứng chỉ…');

  const SafeItemKind(this.label, this.description);

  final String label;
  final String description;

  static SafeItemKind parse(Object? value) => SafeItemKind.values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => SafeItemKind.note,
  );
}

/// One secret in the safe. Lives decrypted only while the safe is open.
class SafeItem {
  const SafeItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.username = '',
    this.secret = '',
    this.url = '',
    this.notes = '',
    this.fileName = '',
    this.project = '',
    this.source = '',
    this.favorite = false,
  });

  final String id;
  final SafeItemKind kind;
  final String title;

  /// The login of a password item.
  final String username;

  /// The payload: password, key, `.env` text, JSON text, note text, or the
  /// file's bytes as base64.
  final String secret;
  final String url;
  final String notes;

  /// The original file name, used again when exporting. Always set for a
  /// [SafeItemKind.file]; set for other kinds when they came from a file.
  final String fileName;

  /// The project the secret belongs to, so a safe holding keys from many
  /// projects can be read one project at a time. Empty for loose secrets.
  final String project;

  /// Where the secret was found on disk (`path` or `path:line`), when it was
  /// gathered by a folder scan.
  final String source;
  final bool favorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  SafeItem copyWith({
    SafeItemKind? kind,
    String? title,
    String? username,
    String? secret,
    String? url,
    String? notes,
    String? fileName,
    String? project,
    String? source,
    bool? favorite,
    DateTime? updatedAt,
  }) => SafeItem(
    id: id,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    username: username ?? this.username,
    secret: secret ?? this.secret,
    url: url ?? this.url,
    notes: notes ?? this.notes,
    fileName: fileName ?? this.fileName,
    project: project ?? this.project,
    source: source ?? this.source,
    favorite: favorite ?? this.favorite,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Parsed `KEY=VALUE` pairs of an env item, in file order.
  Map<String, String> get envEntries =>
      kind == SafeItemKind.env ? parseEnvFile(secret) : const {};

  /// The decoded JSON of a JSON key, or null when it no longer parses.
  Object? get jsonValue {
    if (kind != SafeItemKind.jsonKey) return null;
    try {
      return jsonDecode(secret);
    } on FormatException {
      return null;
    }
  }

  Uint8List get fileBytes {
    if (kind != SafeItemKind.file || secret.isEmpty) return Uint8List(0);
    try {
      return base64Decode(secret);
    } on FormatException {
      return Uint8List(0);
    }
  }

  /// Size of a file item without decoding it: four base64 characters carry
  /// three bytes, less the padding.
  int get fileSize {
    if (kind != SafeItemKind.file || secret.isEmpty) return 0;
    final padding = secret.endsWith('==')
        ? 2
        : secret.endsWith('=')
        ? 1
        : 0;
    return secret.length * 3 ~/ 4 - padding;
  }

  /// One line under the title on the box's label plate. Never the secret.
  String get summary {
    switch (kind) {
      case SafeItemKind.password:
        if (username.isNotEmpty) return username;
        return url;
      case SafeItemKind.apiKey:
        if (url.isNotEmpty) return url;
        return secret.isEmpty ? '' : '${secret.length} ký tự';
      case SafeItemKind.env:
        final count = envEntries.length;
        return count == 0 ? 'Chưa có biến nào' : '$count biến';
      case SafeItemKind.jsonKey:
        final value = jsonValue;
        if (value is Map) {
          for (final key in const [
            'client_email',
            'project_id',
            'key_id',
            'issuer_id',
            'type',
          ]) {
            final field = value[key];
            if (field is String && field.isNotEmpty) return field;
          }
          return '${value.length} trường';
        }
        return value == null ? 'JSON không hợp lệ' : 'JSON';
      case SafeItemKind.note:
        if (secret.isEmpty) return 'Trống';
        final lines = '\n'.allMatches(secret.trimRight()).length + 1;
        return lines == 1 ? '${secret.length} ký tự' : '$lines dòng';
      case SafeItemKind.file:
        if (fileName.isEmpty) return formatByteSize(fileSize);
        return '$fileName · ${formatByteSize(fileSize)}';
    }
  }

  /// What a search is matched against. Secrets are deliberately left out so
  /// typing near someone does not reveal which value matched.
  String get searchText => [
    title,
    username,
    url,
    fileName,
    project,
    kind.label,
    if (kind == SafeItemKind.env) ...envEntries.keys,
  ].join(' ').toLowerCase();

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    if (username.isNotEmpty) 'username': username,
    if (secret.isNotEmpty) 'secret': secret,
    if (url.isNotEmpty) 'url': url,
    if (notes.isNotEmpty) 'notes': notes,
    if (fileName.isNotEmpty) 'fileName': fileName,
    if (project.isNotEmpty) 'project': project,
    if (source.isNotEmpty) 'source': source,
    if (favorite) 'favorite': true,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory SafeItem.fromJson(Map<String, dynamic> json) {
    final created =
        DateTime.tryParse('${json['createdAt']}')?.toLocal() ?? DateTime.now();
    return SafeItem(
      id: '${json['id']}',
      kind: SafeItemKind.parse(json['kind']),
      title: '${json['title'] ?? ''}',
      username: '${json['username'] ?? ''}',
      secret: '${json['secret'] ?? ''}',
      url: '${json['url'] ?? ''}',
      notes: '${json['notes'] ?? ''}',
      fileName: '${json['fileName'] ?? ''}',
      project: '${json['project'] ?? ''}',
      source: '${json['source'] ?? ''}',
      favorite: json['favorite'] == true,
      createdAt: created,
      updatedAt:
          DateTime.tryParse('${json['updatedAt']}')?.toLocal() ?? created,
    );
  }
}

/// How the open safe behaves. Kept inside the encrypted payload: nothing
/// about the safe's habits is readable without the code.
class SafeSettings {
  const SafeSettings({
    this.autoLockMinutes = 5,
    this.lockOnClose = false,
    this.clipboardSeconds = 30,
  });

  static const autoLockChoices = [1, 5, 15, 30, 60];
  static const clipboardChoices = [15, 30, 60, 120];

  /// Idle minutes before the door shuts by itself.
  final int autoLockMinutes;

  /// Shut the door as soon as the safe's page is closed, idle or not.
  final bool lockOnClose;

  /// Seconds before a copied secret is wiped from the clipboard.
  final int clipboardSeconds;

  Duration get autoLock => Duration(minutes: autoLockMinutes);
  Duration get clipboardClear => Duration(seconds: clipboardSeconds);

  SafeSettings copyWith({
    int? autoLockMinutes,
    bool? lockOnClose,
    int? clipboardSeconds,
  }) => SafeSettings(
    autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
    lockOnClose: lockOnClose ?? this.lockOnClose,
    clipboardSeconds: clipboardSeconds ?? this.clipboardSeconds,
  );

  Map<String, dynamic> toJson() => {
    'autoLockMinutes': autoLockMinutes,
    'lockOnClose': lockOnClose,
    'clipboardSeconds': clipboardSeconds,
  };

  factory SafeSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SafeSettings();
    int clamp(Object? value, int fallback, int min, int max) {
      final number = value is num ? value.toInt() : fallback;
      return number.clamp(min, max);
    }

    return SafeSettings(
      autoLockMinutes: clamp(json['autoLockMinutes'], 5, 1, 240),
      lockOnClose: json['lockOnClose'] == true,
      clipboardSeconds: clamp(json['clipboardSeconds'], 30, 5, 600),
    );
  }
}

/// Everything sealed inside the safe.
class SafeContents {
  const SafeContents({
    this.items = const [],
    this.settings = const SafeSettings(),
  });

  final List<SafeItem> items;
  final SafeSettings settings;

  SafeContents copyWith({List<SafeItem>? items, SafeSettings? settings}) =>
      SafeContents(
        items: items ?? this.items,
        settings: settings ?? this.settings,
      );

  Map<String, dynamic> toJson() => {
    'items': [for (final item in items) item.toJson()],
    'settings': settings.toJson(),
  };

  factory SafeContents.fromJson(Map<String, dynamic> json) => SafeContents(
    items: [
      for (final item in (json['items'] as List<dynamic>? ?? const []))
        if (item is Map) SafeItem.fromJson(Map<String, dynamic>.from(item)),
    ],
    settings: SafeSettings.fromJson(
      json['settings'] is Map
          ? Map<String, dynamic>.from(json['settings'] as Map)
          : null,
    ),
  );
}

String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
