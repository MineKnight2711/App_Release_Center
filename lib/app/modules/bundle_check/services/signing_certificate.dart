import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// The certificate a bundle was signed with — who, and its fingerprints.
class SigningCertificate {
  const SigningCertificate({
    required this.subject,
    required this.sha256,
    required this.sha1,
    this.notBefore,
    this.notAfter,
  });

  factory SigningCertificate.fromDer(Uint8List der) {
    final certificate = _Der.read(der, 0);
    final tbs = certificate.children.first;
    final fields = tbs.children;
    // An explicit [0] version is optional; everything after shifts by one.
    final shift = fields.isNotEmpty && fields.first.tag == 0xa0 ? 1 : 0;
    if (fields.length < shift + 6) {
      throw const FormatException('Chứng chỉ thiếu trường bắt buộc.');
    }
    final validity = fields[shift + 3].children;
    return SigningCertificate(
      subject: _name(fields[shift + 4]),
      sha256: _fingerprint(SHA256Digest(), certificate.encoded),
      sha1: _fingerprint(SHA1Digest(), certificate.encoded),
      notBefore: validity.isNotEmpty ? _time(validity[0]) : null,
      notAfter: validity.length > 1 ? _time(validity[1]) : null,
    );
  }

  /// Relative distinguished names keyed by short name: `CN`, `O`, `C`, ...
  final Map<String, String> subject;

  /// Colon-separated upper-case hex, the way `keytool` prints it.
  final String sha256;
  final String sha1;
  final DateTime? notBefore;
  final DateTime? notAfter;

  String get commonName => subject['CN'] ?? '';

  String get subjectLine {
    const order = ['CN', 'OU', 'O', 'L', 'ST', 'C'];
    return [
      for (final key in order)
        if (subject[key] case final value? when value.isNotEmpty) '$key=$value',
    ].join(', ');
  }

  /// The key Gradle and Flutter fall back to when no release keystore is set.
  bool get isAndroidDebug => commonName == 'Android Debug';

  Map<String, Object?> toJson() => {
    'subject': subject,
    'sha256': sha256,
    'sha1': sha1,
    'notBefore': notBefore?.toIso8601String(),
    'notAfter': notAfter?.toIso8601String(),
  };

  factory SigningCertificate.fromJson(Map<String, Object?> json) {
    return SigningCertificate(
      subject: {
        for (final entry in ((json['subject'] as Map?) ?? const {}).entries)
          '${entry.key}': '${entry.value}',
      },
      sha256: json['sha256'] as String? ?? '',
      sha1: json['sha1'] as String? ?? '',
      notBefore: DateTime.tryParse(json['notBefore'] as String? ?? ''),
      notAfter: DateTime.tryParse(json['notAfter'] as String? ?? ''),
    );
  }

  /// Normalises a fingerprint typed or pasted in any common form.
  static String normalizeFingerprint(String value) {
    final hex = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    final pairs = <String>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      pairs.add(hex.substring(i, i + 2));
    }
    return pairs.join(':');
  }

  static String _fingerprint(Digest digest, Uint8List bytes) {
    return digest
        .process(bytes)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }

  static const _attributeNames = {
    '2.5.4.3': 'CN',
    '2.5.4.6': 'C',
    '2.5.4.7': 'L',
    '2.5.4.8': 'ST',
    '2.5.4.10': 'O',
    '2.5.4.11': 'OU',
  };

  static Map<String, String> _name(_Der name) {
    final result = <String, String>{};
    for (final set in name.children) {
      for (final pair in set.children) {
        final parts = pair.children;
        if (parts.length < 2 || parts[0].tag != 0x06) continue;
        final key = _attributeNames[_oid(parts[0].content)];
        if (key != null) result.putIfAbsent(key, () => _text(parts[1]));
      }
    }
    return result;
  }

  static String _oid(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    final parts = <int>[bytes[0] ~/ 40, bytes[0] % 40];
    var value = 0;
    for (final byte in bytes.skip(1)) {
      value = (value << 7) | (byte & 0x7f);
      if (byte < 0x80) {
        parts.add(value);
        value = 0;
      }
    }
    return parts.join('.');
  }

  static String _text(_Der value) {
    final bytes = value.content;
    return switch (value.tag) {
      0x1e => String.fromCharCodes([
        for (var i = 0; i + 1 < bytes.length; i += 2)
          bytes[i] << 8 | bytes[i + 1],
      ]),
      0x14 => latin1.decode(bytes),
      _ => utf8.decode(bytes, allowMalformed: true),
    };
  }

  static DateTime? _time(_Der value) {
    final text = ascii.decode(value.content, allowInvalid: true);
    final match = RegExp(
      r'^(\d{2,4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?Z$',
    ).firstMatch(text);
    if (match == null) return null;
    var year = int.parse(match.group(1)!);
    if (value.tag == 0x17) year += year >= 50 ? 1900 : 2000;
    return DateTime.utc(
      year,
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6) ?? '0'),
    );
  }
}

/// Picks the signer's certificate out of a JAR signature block
/// (`META-INF/*.RSA`, `*.EC`, `*.DSA`), which is PKCS#7 SignedData.
SigningCertificate parsePkcs7SignerCertificate(Uint8List block) {
  final contentInfo = _Der.read(block, 0);
  final wrapped = contentInfo.children.where((c) => c.tag == 0xa0).firstOrNull;
  final signedData = wrapped?.children.firstOrNull;
  if (signedData == null) {
    throw const FormatException('Khối chữ ký không phải PKCS#7 SignedData.');
  }
  final certificateSet = signedData.children
      .where((child) => child.tag == 0xa0)
      .firstOrNull;
  final certificates = certificateSet?.children ?? const <_Der>[];
  if (certificates.isEmpty) {
    throw const FormatException('Khối chữ ký không mang chứng chỉ nào.');
  }

  // With a chain, the signer is the certificate whose serial the SignerInfo
  // names; alone, it is simply the one certificate.
  var signer = certificates.first;
  final signerInfos = signedData.children.lastOrNull;
  final signerSerial = signerInfos?.children.firstOrNull?.children
      .elementAtOrNull(1)
      ?.children
      .elementAtOrNull(1);
  if (certificates.length > 1 && signerSerial != null) {
    for (final certificate in certificates) {
      final fields = certificate.children.first.children;
      final shift = fields.first.tag == 0xa0 ? 1 : 0;
      final serial = fields.elementAtOrNull(shift);
      if (serial != null && _sameBytes(serial.content, signerSerial.content)) {
        signer = certificate;
        break;
      }
    }
  }
  return SigningCertificate.fromDer(signer.encoded);
}

/// Pulls the first signer's certificate out of an APK Signing Block (v3,
/// else v2). Returns null when the block holds neither scheme.
SigningCertificate? parseApkSigningBlockCertificate(Uint8List block) {
  final data = ByteData.sublistView(block);
  // Layout: u64 size, pairs of (u64 length, u32 id, value), u64 size, magic.
  var cursor = 8;
  final end = block.length - 24;
  final values = <int, Uint8List>{};
  while (cursor + 12 <= end) {
    final length = data.getUint64(cursor, Endian.little);
    if (length < 4 || cursor + 8 + length > end) break;
    final id = data.getUint32(cursor + 8, Endian.little);
    values[id] = Uint8List.sublistView(block, cursor + 12, cursor + 8 + length);
    cursor += 8 + length;
  }

  const v3 = 0xf05368c0;
  const v2 = 0x7109871a;
  final scheme = values[v3] ?? values[v2];
  if (scheme == null) return null;

  Uint8List prefixed(Uint8List bytes, int offset) {
    final view = ByteData.sublistView(bytes);
    final length = view.getUint32(offset, Endian.little);
    if (offset + 4 + length > bytes.length) {
      throw const FormatException('Khối chữ ký APK bị cắt dở.');
    }
    return Uint8List.sublistView(bytes, offset + 4, offset + 4 + length);
  }

  final signers = prefixed(scheme, 0);
  final signer = prefixed(signers, 0);
  final signedData = prefixed(signer, 0);
  final digests = prefixed(signedData, 0);
  final certificates = prefixed(signedData, 4 + digests.length);
  final certificate = prefixed(certificates, 0);
  return SigningCertificate.fromDer(certificate);
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _Der {
  _Der._(this.tag, this._source, this._offset, this._headerLength, this.length);

  static _Der read(Uint8List source, int offset) {
    if (offset + 2 > source.length) {
      throw const FormatException('DER bị cắt dở.');
    }
    final tag = source[offset];
    var cursor = offset + 1;
    var length = source[cursor++];
    if (length == 0x80) {
      throw const FormatException('DER độ dài không xác định, chưa hỗ trợ.');
    }
    if (length > 0x80) {
      final count = length & 0x7f;
      if (count > 4 || cursor + count > source.length) {
        throw const FormatException('Độ dài DER bất thường.');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | source[cursor++];
      }
    }
    if (cursor + length > source.length) {
      throw const FormatException('DER vượt buffer.');
    }
    return _Der._(tag, source, offset, cursor - offset, length);
  }

  final int tag;
  final Uint8List _source;
  final int _offset;
  final int _headerLength;
  final int length;

  Uint8List get content => Uint8List.sublistView(
    _source,
    _offset + _headerLength,
    _offset + _headerLength + length,
  );

  Uint8List get encoded =>
      Uint8List.sublistView(_source, _offset, _offset + _headerLength + length);

  late final List<_Der> children = () {
    final result = <_Der>[];
    final body = content;
    var cursor = 0;
    while (cursor < body.length) {
      final child = _Der.read(body, cursor);
      result.add(child);
      cursor += child._headerLength + child.length;
    }
    return result;
  }();
}
