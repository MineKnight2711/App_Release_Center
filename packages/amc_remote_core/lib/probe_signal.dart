import 'dart:convert';

/// Manual signaling for the engine experiment, not a production pairing token.
/// Transfer only to the intended peer through a trusted channel: SDP contains
/// connection candidates and fingerprints. Never persist or log its contents.
final class ProbeSignal {
  ProbeSignal({
    required this.sessionId,
    required this.type,
    required this.sdp,
    required this.expiresAt,
  }) {
    if (!RegExp(r'^[a-zA-Z0-9-]{16,64}$').hasMatch(sessionId) ||
        !{'offer', 'answer'}.contains(type) ||
        !sdp.startsWith('v=0') ||
        sdp.length > 262144 ||
        !sdp.contains('a=fingerprint:sha-256 ')) {
      throw const FormatException('Mã phiên không hợp lệ');
    }
  }
  final String sessionId;
  final String type;
  final String sdp;
  final DateTime expiresAt;

  String encode() => jsonEncode({
    'version': 1,
    'sessionId': sessionId,
    'type': type,
    'sdp': sdp,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  });

  static ProbeSignal decode(String value, {required DateTime now}) {
    if (value.length > 300000) throw const FormatException('Mã phiên quá lớn');
    final Object? data;
    try {
      data = jsonDecode(value);
    } on FormatException {
      throw const FormatException(
        'Mã phiên không hợp lệ. Sao chép đủ mã từ máy kia.',
      );
    }
    if (data is! Map<String, dynamic> ||
        data['version'] != 1 ||
        data['sessionId'] is! String ||
        data['type'] is! String ||
        data['sdp'] is! String ||
        data['expiresAt'] is! String) {
      throw const FormatException('Mã phiên không hợp lệ');
    }
    final expiry = DateTime.tryParse(data['expiresAt'] as String);
    if (expiry == null ||
        !expiry.isAfter(now) ||
        expiry.isAfter(now.add(const Duration(minutes: 15)))) {
      throw const FormatException('Mã phiên hết hạn hoặc sai thời gian');
    }
    return ProbeSignal(
      sessionId: data['sessionId'] as String,
      type: data['type'] as String,
      sdp: data['sdp'] as String,
      expiresAt: expiry,
    );
  }
}
