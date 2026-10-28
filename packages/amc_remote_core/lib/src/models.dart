import 'dart:convert';

enum RemoteScope { view, input, clipboard }

enum RemoteRole { host, viewer }

enum RemoteConnectionMode { automatic, directIpv6, relay }

RemoteConnectionMode parseRemoteConnectionMode(Object? value) {
  if (value == null) return RemoteConnectionMode.automatic;
  for (final mode in RemoteConnectionMode.values) {
    if (value == mode.name) return mode;
  }
  throw const FormatException('Chế độ kết nối không hợp lệ.');
}

RemoteConnectionMode resolveRemoteConnectionMode(
  RemoteConnectionMode local,
  RemoteConnectionMode remote,
) {
  if (local == RemoteConnectionMode.automatic) return remote;
  if (remote == RemoteConnectionMode.automatic || local == remote) return local;
  throw StateError(
    'Hai máy chọn P2P IPv6 và TURN khác nhau. Đổi một máy sang Tự động.',
  );
}

enum RemoteSessionState {
  idle,
  requesting,
  awaitingApproval,
  negotiating,
  connected,
  reconnecting,
  ended,
  failed,
}

enum RemoteQuality { low, balanced, high }

String remoteName(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 80 ||
      RegExp(r'[\x00-\x1f]').hasMatch(value)) {
    throw const FormatException('Tên thiết bị không hợp lệ.');
  }
  return value;
}

bool isRemoteId(String value) =>
    RegExp(r'^[a-zA-Z0-9-]{16,64}$').hasMatch(value);
Set<RemoteScope> parseScopes(Object? value) {
  if (value is! List ||
      value.length > 3 ||
      value.any((v) => !RemoteScope.values.any((s) => s.name == v))) {
    throw const FormatException('Quyền truy cập không hợp lệ.');
  }
  final scopes = value
      .map((v) => RemoteScope.values.byName(v as String))
      .toSet();
  if (!scopes.contains(RemoteScope.view)) {
    throw const FormatException('Thiếu quyền xem màn hình.');
  }
  return scopes;
}

/// Phase 2 deliberately limits listeners and destinations to private IPv4 LAN.
bool isLanAddress(String address) {
  final parts = address.split('.');
  if (parts.length != 4 ||
      parts.any((p) => !RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(p))) {
    return false;
  }
  final bytes = parts.map(int.parse).toList();
  if (bytes.any((n) => n > 255)) return false;
  return bytes[0] == 10 ||
      bytes[0] == 127 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168) ||
      (bytes[0] == 169 && bytes[1] == 254);
}

final class RemoteEndpoint {
  RemoteEndpoint({
    required this.address,
    required this.port,
    required this.fingerprint,
    required this.deviceId,
    required this.name,
  }) {
    if (!isLanAddress(address) ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint) ||
        !isRemoteId(deviceId)) {
      throw const FormatException(
        'Địa chỉ LAN hoặc danh tính máy không hợp lệ.',
      );
    }
    remoteName(name);
  }
  final String address, fingerprint, deviceId, name;
  final int port;
  Map<String, Object> toJson() => {
    'address': address,
    'port': port,
    'fingerprint': fingerprint,
    'deviceId': deviceId,
    'name': name,
  };
  factory RemoteEndpoint.fromJson(Map<String, dynamic> data) => RemoteEndpoint(
    address: data['address'] as String,
    port: data['port'] as int,
    fingerprint: data['fingerprint'] as String,
    deviceId: data['deviceId'] as String,
    name: data['name'] as String,
  );
}

final class RemoteInvitation {
  RemoteInvitation({
    required this.endpoint,
    required this.token,
    required this.expiresAt,
  }) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw const FormatException('Mã ghép nối không hợp lệ.');
    }
  }
  final RemoteEndpoint endpoint;
  final String token;
  final DateTime expiresAt;
  String encode() =>
      'amc-lan:1:${base64Url.encode(utf8.encode(jsonEncode({'endpoint': endpoint.toJson(), 'token': token, 'expiresAt': expiresAt.toUtc().toIso8601String()})))}';
  static RemoteInvitation decode(String value, DateTime now) {
    try {
      if (!value.startsWith('amc-lan:1:') || value.length > 4096) {
        throw const FormatException();
      }
      final data =
          jsonDecode(utf8.decode(base64Url.decode(value.substring(10))))
              as Map<String, dynamic>;
      final expiry = DateTime.parse(data['expiresAt'] as String);
      if (!expiry.isAfter(now) ||
          expiry.isAfter(now.add(const Duration(minutes: 6)))) {
        throw const FormatException();
      }
      return RemoteInvitation(
        endpoint: RemoteEndpoint.fromJson(
          data['endpoint'] as Map<String, dynamic>,
        ),
        token: data['token'] as String,
        expiresAt: expiry,
      );
    } catch (_) {
      throw const FormatException(
        'Mã ghép nối sai hoặc đã hết hạn. Tạo mã mới trên máy đích.',
      );
    }
  }
}

final class RemoteDevice {
  const RemoteDevice({
    required this.endpoint,
    required this.platform,
    required this.lastConnectedAt,
  });
  final RemoteEndpoint endpoint;
  final String platform;
  final DateTime lastConnectedAt;
  Map<String, Object> toJson() => {
    'endpoint': endpoint.toJson(),
    'platform': platform,
    'lastConnectedAt': lastConnectedAt.toUtc().toIso8601String(),
  };
  factory RemoteDevice.fromJson(Map<String, dynamic> json) => RemoteDevice(
    endpoint: RemoteEndpoint.fromJson(json['endpoint'] as Map<String, dynamic>),
    platform: json['platform'] as String,
    lastConnectedAt: DateTime.parse(json['lastConnectedAt'] as String),
  );
}

final class TrustedRemoteController {
  TrustedRemoteController({
    required this.id,
    required this.name,
    required this.tokenHash,
    required Set<RemoteScope> scopes,
  }) : scopes = Set.unmodifiable(scopes) {
    if (!isRemoteId(id) || !RegExp(r'^[a-f0-9]{64}$').hasMatch(tokenHash)) {
      throw const FormatException('Thiết bị tin cậy không hợp lệ.');
    }
    remoteName(name);
  }
  final String id, name, tokenHash;
  final Set<RemoteScope> scopes;
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'tokenHash': tokenHash,
    'scopes': scopes.map((s) => s.name).toList(),
  };
  factory TrustedRemoteController.fromJson(Map<String, dynamic> json) =>
      TrustedRemoteController(
        id: json['id'] as String,
        name: json['name'] as String,
        tokenHash: json['tokenHash'] as String,
        scopes: parseScopes(json['scopes']),
      );
}

final class DisplayDescriptor {
  const DisplayDescriptor({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    this.scaleFactor = 1,
  });
  final String id, name;
  final int width, height;
  final double scaleFactor;
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'width': width,
    'height': height,
    'scaleFactor': scaleFactor,
  };
  factory DisplayDescriptor.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final width = json['width'];
    final height = json['height'];
    final scale = json['scaleFactor'] ?? 1;
    if (id is! String ||
        id.isEmpty ||
        id.length > 128 ||
        RegExp(r'[\x00-\x1f]').hasMatch(id) ||
        width is! int ||
        width < 1 ||
        width > 32768 ||
        height is! int ||
        height < 1 ||
        height > 32768 ||
        scale is! num ||
        !scale.isFinite ||
        scale < .25 ||
        scale > 8) {
      throw const FormatException('Thông tin màn hình không hợp lệ.');
    }
    return DisplayDescriptor(
      id: id,
      name: remoteName(json['name']),
      width: width,
      height: height,
      scaleFactor: scale.toDouble(),
    );
  }
}

final class RemoteSignal {
  RemoteSignal({
    required this.sessionId,
    required this.sequence,
    required this.kind,
    this.data = const {},
  }) {
    if (!isRemoteId(sessionId) || sequence < 0 || !kinds.contains(kind)) {
      throw const FormatException('Signaling không hợp lệ.');
    }
  }
  static const maxBytes = 262144;
  static const kinds = {
    'hello',
    'request',
    'pending',
    'approved',
    'rejected',
    'offer',
    'answer',
    'ready',
    'disconnect',
    'error',
    'ping',
    'pong',
  };
  final String sessionId, kind;
  final int sequence;
  final Map<String, dynamic> data;
  String encode() => jsonEncode({
    'v': 1,
    'sessionId': sessionId,
    'seq': sequence,
    'kind': kind,
    'data': data,
  });
  static RemoteSignal decode(String value) {
    if (value.length > maxBytes) {
      throw const FormatException('Signaling quá lớn.');
    }
    final data = jsonDecode(value);
    if (data is! Map<String, dynamic> ||
        data['v'] != 1 ||
        data['sessionId'] is! String ||
        data['seq'] is! int ||
        data['kind'] is! String ||
        data['data'] is! Map<String, dynamic>) {
      throw const FormatException('Sai phiên bản hoặc nội dung signaling.');
    }
    return RemoteSignal(
      sessionId: data['sessionId'] as String,
      sequence: data['seq'] as int,
      kind: data['kind'] as String,
      data: data['data'] as Map<String, dynamic>,
    );
  }
}

final class RemoteSessionRecord {
  const RemoteSessionRecord({
    required this.sessionId,
    required this.peerName,
    required this.role,
    required this.endedAt,
    required this.failed,
    required this.frames,
  });
  final String sessionId, peerName;
  final RemoteRole role;
  final DateTime endedAt;
  final bool failed;
  final int frames;
  Map<String, Object> toJson() => {
    'sessionId': sessionId,
    'peerName': peerName,
    'role': role.name,
    'endedAt': endedAt.toUtc().toIso8601String(),
    'failed': failed,
    'frames': frames,
  };
  factory RemoteSessionRecord.fromJson(Map<String, dynamic> data) =>
      RemoteSessionRecord(
        sessionId: data['sessionId'] as String,
        peerName: remoteName(data['peerName']),
        role: RemoteRole.values.byName(data['role'] as String),
        endedAt: DateTime.parse(data['endedAt'] as String),
        failed: data['failed'] as bool,
        frames: data['frames'] as int,
      );
}
