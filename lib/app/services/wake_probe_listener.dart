import 'dart:async';
import 'dart:io';

/// Watches for this machine's own Wake-on-LAN packets while it is awake.
///
/// When the phone's wake button does nothing there are two very different
/// causes — the packet never reaches this machine, or it arrives and the
/// sleeping network card ignores it — and nothing inside a sleeping machine is
/// observable. Listening while awake settles which one it is: tap wake with
/// the machine on, and either a packet shows up here or it does not.
///
/// It deliberately records nothing about packets aimed at other machines.
class WakeProbeListener {
  WakeProbeListener({this.ports = const [9, 7]});

  /// The two ports conventional for Wake-on-LAN, matching what the phone sends.
  final List<int> ports;

  final _sockets = <RawDatagramSocket>[];

  DateTime? _lastPacketAt;
  String _lastPacketFrom = '';
  bool _listening = false;

  /// True once at least one port is bound. Port 9 can be taken by Simple
  /// TCP/IP Services, which is why a single failure is not fatal.
  bool get isListening => _listening;

  /// When a magic packet for this machine last arrived, or null for never.
  DateTime? get lastPacketAt => _lastPacketAt;

  /// Who sent it. Seeing the phone's own address here is the point.
  String get lastPacketFrom => _lastPacketFrom;

  /// Starts listening for packets addressed to [macAddress].
  ///
  /// Safe to call repeatedly; later calls are ignored while already bound.
  Future<void> start(String macAddress) async {
    if (_sockets.isNotEmpty) return;

    final expected = _normalizeMac(macAddress);
    if (expected.isEmpty) return;

    for (final port in ports) {
      try {
        final socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          port,
          reuseAddress: true,
        );
        socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          final datagram = socket.receive();
          if (datagram == null) return;
          if (!_isMagicPacketFor(datagram.data, expected)) return;
          _lastPacketAt = DateTime.now();
          _lastPacketFrom = datagram.address.address;
        });
        _sockets.add(socket);
        _listening = true;
      } catch (_) {
        // Another process owns this port. The phone sends to both, so one is
        // enough, and reporting nothing is better than refusing to start.
        continue;
      }
    }
  }

  Future<void> stop() async {
    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();
    _listening = false;
  }

  /// Six 0xFF bytes then the MAC sixteen times over, and the MAC has to be
  /// this machine's — a neighbour waking their own PC is not evidence here.
  static bool _isMagicPacketFor(List<int> data, String expectedMac) {
    if (data.length != 102) return false;
    for (var index = 0; index < 6; index++) {
      if (data[index] != 0xFF) return false;
    }
    final mac = data
        .sublist(6, 12)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return mac == expectedMac;
  }

  static String _normalizeMac(String value) {
    final hex = value.replaceAll(RegExp('[^0-9a-fA-F]'), '').toUpperCase();
    return hex.length == 12 ? hex : '';
  }

  Map<String, Object?> toJson() {
    return {
      'listening': _listening,
      'lastPacketAt': _lastPacketAt?.toUtc().toIso8601String(),
      'lastPacketFrom': _lastPacketFrom,
    };
  }
}
