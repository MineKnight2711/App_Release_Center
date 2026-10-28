import 'dart:io';
import 'package:amc_remote_core/amc_remote_core.dart';

extension RemoteConnectionModeLabel on RemoteConnectionMode {
  String get label => switch (this) {
    RemoteConnectionMode.automatic => 'Tự động · P2P IPv6/IPv4, TURN dự phòng',
    RemoteConnectionMode.directIpv6 => 'Chỉ P2P IPv6 · Không qua TURN',
    RemoteConnectionMode.relay => 'Bắt buộc TURN',
  };

  String get explanation => switch (this) {
    RemoteConnectionMode.automatic =>
      'WebRTC chọn đường khả dụng giữa hai máy, gồm P2P IPv6. TURN chỉ dùng khi máy chủ đã cấu hình.',
    RemoteConnectionMode.directIpv6 =>
      'Hai máy cần IPv6 liên lạc được. Nếu không có đường IPv6, phiên sẽ báo lỗi; không chuyển sang IPv4 hoặc TURN.',
    RemoteConnectionMode.relay =>
      'Mọi hình ảnh và điều khiển đi qua TURN. Cần máy chủ TURN đã cấu hình.',
  };
}

String remoteNetworkPathLabel(String path) => switch (path) {
  'direct-ipv6' => 'P2P IPv6',
  'direct-ipv4' => 'P2P IPv4',
  'direct' => 'P2P trực tiếp',
  'relay' => 'TURN relay',
  _ => 'Đang xác định đường truyền',
};

/// IPv4-mapped addresses are IPv4 paths, even though their text contains colons.
bool _mappedIpv4(InternetAddress address) {
  if (address.type != InternetAddressType.IPv6) return false;
  final bytes = address.rawAddress;
  return bytes.take(10).every((b) => b == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff;
}

bool _ipv6(String value) {
  final address = InternetAddress.tryParse(value);
  if (address == null || address.type != InternetAddressType.IPv6) return false;
  final bytes = address.rawAddress;
  if (bytes.every((b) => b == 0) || bytes.first == 0xff) return false;
  return !_mappedIpv4(address);
}

class RemoteIcePolicy {
  RemoteIcePolicy(
    List<Map<String, dynamic>> servers, {
    this.mode = RemoteConnectionMode.automatic,
  }) : iceServers = mode == RemoteConnectionMode.directIpv6
           ? const []
           : servers.map((v) => Map<String, dynamic>.of(v)).toList() {
    if (mode == RemoteConnectionMode.relay &&
        !iceServers.any((server) {
          final urls = server['urls'];
          final values = urls is String
              ? [urls]
              : urls is List
              ? urls
              : const [];
          return values.any(
            (v) => v is String && RegExp(r'^turns?:').hasMatch(v),
          );
        })) {
      throw StateError('Máy chủ chưa cấu hình TURN.');
    }
  }
  final RemoteConnectionMode mode;
  final List<Map<String, dynamic>> iceServers;
  Map<String, dynamic> get configuration => {
    'iceServers': iceServers,
    'iceTransportPolicy': mode == RemoteConnectionMode.relay ? 'relay' : 'all',
    // Supported by both the pinned Darwin and Windows flutter_webrtc plugins.
    // Leave room for public IPv6 when VPN/virtual adapters occupy the first slots.
    'maxIPv6Networks': 32,
    'sdpSemantics': 'unified-plan',
    'bundlePolicy': 'max-bundle',
  };

  /// Apply to outgoing AND incoming SDP: filtering only what we advertise
  /// would still let a peer's IPv4 candidates form a peer-reflexive IPv4 path.
  String description(String sdp) {
    if (mode != RemoteConnectionMode.directIpv6) return sdp;
    var candidates = 0;
    final lines = <String>[];
    for (var line in sdp.split(RegExp(r'\r?\n'))) {
      if (line.startsWith('a=candidate:')) {
        final fields = line.trim().split(RegExp(r'\s+'));
        if (fields.length < 8 ||
            fields[6] != 'typ' ||
            !{'host', 'srflx', 'prflx'}.contains(fields[7]) ||
            !_ipv6(fields[4])) {
          continue;
        }
        candidates++;
      } else if (line.startsWith('a=remote-candidates:')) {
        continue;
      } else if (line.startsWith('c=IN IP4 ')) {
        line = 'c=IN IP6 ::';
      }
      lines.add(line);
    }
    if (candidates == 0) {
      throw StateError(
        'Không có candidate P2P IPv6. Kiểm tra IPv6 trên hai máy hoặc chọn Tự động.',
      );
    }
    return lines.join('\r\n');
  }
}

/// Read only the selected pair. A TURN server reached over IPv6 is still relay.
/// Expose a family label, never raw peer addresses, to diagnostics and the UI.
String selectedRemoteNetworkPath(
  Map<dynamic, dynamic>? local,
  Map<dynamic, dynamic>? remote,
) {
  if (local == null || remote == null) return 'unknown';
  if (local['candidateType'] == 'relay' || remote['candidateType'] == 'relay') {
    return 'relay';
  }
  if (local['candidateType'] is! String || remote['candidateType'] is! String) {
    return 'unknown';
  }
  String? address(Map<dynamic, dynamic> candidate) {
    final value =
        candidate['address'] ?? candidate['ip'] ?? candidate['ipAddress'];
    return value is String ? value : null;
  }

  final a = address(local), b = address(remote);
  if (a != null && b != null) {
    if (_ipv6(a) && _ipv6(b)) return 'direct-ipv6';
    bool ipv4(String value) {
      final ip = InternetAddress.tryParse(value);
      return ip != null &&
          (ip.type == InternetAddressType.IPv4 || _mappedIpv4(ip));
    }

    if (ipv4(a) && ipv4(b)) return 'direct-ipv4';
  }
  return 'direct';
}
