import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

String envValueFingerprint(String value) => SHA256Digest()
    .process(Uint8List.fromList(utf8.encode(value.trim())))
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

/// Parses a `.env` the way flutter_dotenv reads it: `KEY=VALUE` per line,
/// `#` comments, an optional `export ` prefix, matching quotes stripped.
///
/// A later duplicate wins, as it does in flutter_dotenv.
Map<String, String> parseEnvFile(String source) {
  final values = <String, String>{};
  for (var line in const LineSplitter().convert(source)) {
    line = line.replaceFirst('﻿', '').trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('export ')) line = line.substring(7).trimLeft();
    final equals = line.indexOf('=');
    if (equals <= 0) continue;
    final key = line.substring(0, equals).trim();
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_.\-]*$').hasMatch(key)) continue;
    var value = line.substring(equals + 1).trim();
    final quote = value.isNotEmpty ? value[0] : '';
    if ((quote == '"' || quote == "'") &&
        value.length >= 2 &&
        value.endsWith(quote)) {
      value = value.substring(1, value.length - 1);
    } else {
      // An unquoted value ends at ` #`, which starts an inline comment.
      final comment = value.indexOf(' #');
      if (comment >= 0) value = value.substring(0, comment).trimRight();
    }
    values[key] = value;
  }
  return values;
}

/// Only the keys, for places that must never see a value.
List<String> envFileKeys(String source) => parseEnvFile(source).keys.toList();

final _placeholderPattern = RegExp(
  r'^(?:change[-_ ]?me|replace[-_ ]?me|x{3,}|todo|tbd|placeholder|dummy|'
  r'example|sample|null|none|undefined|your[-_ ].*|<[^>]*>|\$\{[^}]*\}|'
  r'\.\.\.|-+|\*+)$',
  caseSensitive: false,
);

/// Whether an env value is a stand-in nobody replaced before building.
bool isPlaceholderValue(String value) {
  return _placeholderPattern.hasMatch(value.trim());
}

/// Hosts that only make sense on a developer's machine.
bool pointsAtLocalMachine(String value) {
  final lower = value.toLowerCase();
  return RegExp(
        r'(?:^|[/@:\s])(?:localhost|127\.0\.0\.1|0\.0\.0\.0|10\.0\.2\.2|'
        r'10\.0\.3\.2|192\.168\.\d{1,3}\.\d{1,3})(?:[:/\s]|$)',
      ).hasMatch(lower) ||
      RegExp(r'\.ngrok(?:-free)?\.(?:io|app|dev)').hasMatch(lower);
}

/// Key names that suggest the value is a secret rather than a public key.
bool looksLikeSecretKeyName(String key) {
  return RegExp(
    r'SECRET|PRIVATE|PASSWORD|PASSWD|SERVICE_ACCOUNT',
    caseSensitive: false,
  ).hasMatch(key);
}
