import 'dart:io';

/// Sends the Wake-on-LAN magic packet from the phone.
///
/// It has to come from the phone rather than the relay: a magic packet is a
/// broadcast inside the home network and does not route across the internet,
/// so the only device in a position to send one is a device already on that
/// network. Which is also why this only works while the phone is home.
class WakeOnLanService {
  const WakeOnLanService();

  /// Ports 9 (discard) and 7 (echo) are both conventional for this; adapters
  /// listen for the payload rather than the port, and some home routers drop
  /// one or the other.
  static const defaultPorts = [9, 7];

  /// Builds the 102-byte magic packet: six 0xFF bytes, then the MAC sixteen
  /// times over.
  ///
  /// Throws [FormatException] when [mac] is not six hex octets.
  static List<int> buildMagicPacket(String mac) {
    final hex = mac.replaceAll(RegExp('[^0-9a-fA-F]'), '');
    if (hex.length != 12) {
      throw FormatException('Địa chỉ MAC không hợp lệ: $mac');
    }

    final address = [
      for (var index = 0; index < 12; index += 2)
        int.parse(hex.substring(index, index + 2), radix: 16),
    ];

    return [
      ...List.filled(6, 0xFF),
      for (var repeat = 0; repeat < 16; repeat++) ...address,
    ];
  }

  /// Sends the packet to the limited broadcast address and, when known, to the
  /// machine's own subnet broadcast.
  ///
  /// Returns how many datagrams went out. Aiming at both is deliberate: some
  /// access points drop 255.255.255.255 while still forwarding a directed
  /// subnet broadcast, and others do the reverse.
  Future<int> sendMagicPacket(
    String mac, {
    String broadcastAddress = '',
    String hostAddress = '',
    List<int> ports = defaultPorts,
    int repeatCount = 1,
    Duration repeatInterval = const Duration(milliseconds: 250),
  }) async {
    final packet = buildMagicPacket(mac);
    final targets = <String>{
      '255.255.255.255',
      if (broadcastAddress.trim().isNotEmpty) broadcastAddress.trim(),
      if (hostAddress.trim().isNotEmpty) hostAddress.trim(),
    };

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.broadcastEnabled = true;
      var sent = 0;
      final bursts = repeatCount < 1 ? 1 : repeatCount;
      for (var burst = 0; burst < bursts; burst++) {
        for (final target in targets) {
          final address = InternetAddress.tryParse(target);
          if (address == null) continue;
          for (final port in ports) {
            if (await _sendOne(socket, packet, address, port)) sent++;
          }
        }
        if (burst < bursts - 1) {
          await Future<void>.delayed(repeatInterval);
        }
      }
      return sent;
    } finally {
      socket.close();
    }
  }

  /// Sends one datagram, retrying while the socket is not yet writable.
  ///
  /// `send` returns 0 rather than throwing when the send buffer would block,
  /// and a freshly bound socket routinely does that on the first call. Taking
  /// that 0 at face value would silently drop the packet and then report the
  /// machine as unreachable for a reason that has nothing to do with it.
  Future<bool> _sendOne(
    RawDatagramSocket socket,
    List<int> packet,
    InternetAddress address,
    int port,
  ) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (socket.send(packet, address, port) > 0) return true;
      } catch (_) {
        // A refused target must not stop the others; sending to several
        // addresses is the whole point.
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return false;
  }
}
