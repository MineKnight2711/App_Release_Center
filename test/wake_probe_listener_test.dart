import 'dart:io';

import 'package:app_management_center/app/services/wake_probe_listener.dart';
import 'package:flutter_test/flutter_test.dart';

/// The listener exists so nobody has to run a packet sniffer to find out
/// whether a wake packet reaches the machine. These tests send real datagrams
/// at it, because a listener that compiles but never hears anything would look
/// exactly like a network with no route.
void main() {
  const mac = '84:9E:56:EA:B7:F1';

  List<int> magicPacketFor(String address) {
    final hex = address.replaceAll(RegExp('[^0-9a-fA-F]'), '');
    final bytes = [
      for (var index = 0; index < 12; index += 2)
        int.parse(hex.substring(index, index + 2), radix: 16),
    ];
    return [
      ...List.filled(6, 0xFF),
      for (var repeat = 0; repeat < 16; repeat++) ...bytes,
    ];
  }

  Future<void> sendTo(int port, List<int> packet) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      for (var attempt = 0; attempt < 5; attempt++) {
        if (socket.send(packet, InternetAddress('127.0.0.1'), port) > 0) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } finally {
      socket.close();
    }
  }

  /// A free port, so the test never fights the real port 9 or another run.
  Future<int> freePort() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final port = socket.port;
    socket.close();
    return port;
  }

  test('records a magic packet aimed at this machine', () async {
    final port = await freePort();
    final listener = WakeProbeListener(ports: [port]);
    addTearDown(listener.stop);

    await listener.start(mac);
    expect(listener.isListening, isTrue);
    expect(listener.lastPacketAt, isNull);

    await sendTo(port, magicPacketFor(mac));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(listener.lastPacketAt, isNotNull);
    expect(listener.lastPacketFrom, '127.0.0.1');
  });

  test('ignores a packet for a different machine', () async {
    final port = await freePort();
    final listener = WakeProbeListener(ports: [port]);
    addTearDown(listener.stop);
    await listener.start(mac);

    await sendTo(port, magicPacketFor('AA:BB:CC:DD:EE:FF'));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(
      listener.lastPacketAt,
      isNull,
      reason: 'a neighbour waking their own PC is not evidence about this one',
    );
  });

  test('ignores traffic that is not a magic packet', () async {
    final port = await freePort();
    final listener = WakeProbeListener(ports: [port]);
    addTearDown(listener.stop);
    await listener.start(mac);

    await sendTo(port, List.filled(102, 0x00));
    await sendTo(port, magicPacketFor(mac).sublist(0, 50));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(listener.lastPacketAt, isNull);
  });

  test('refuses to start without a usable MAC', () async {
    final port = await freePort();
    final listener = WakeProbeListener(ports: [port]);
    addTearDown(listener.stop);

    await listener.start('');
    expect(listener.isListening, isFalse);

    await listener.start('not-a-mac');
    expect(listener.isListening, isFalse);
  });

  test('a taken port does not stop the other one', () async {
    final taken = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    addTearDown(taken.close);
    final free = await freePort();

    // Binding an already-bound port without reuse is what happens when Simple
    // TCP/IP Services owns port 9.
    final listener = WakeProbeListener(ports: [taken.port, free]);
    addTearDown(listener.stop);
    await listener.start(mac);

    expect(listener.isListening, isTrue);
    await sendTo(free, magicPacketFor(mac));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(listener.lastPacketAt, isNotNull);
  });

  test('stopping releases the port', () async {
    final port = await freePort();
    final listener = WakeProbeListener(ports: [port]);
    await listener.start(mac);
    await listener.stop();

    expect(listener.isListening, isFalse);
    // Rebinding proves the socket is really closed, not just forgotten.
    final rebound = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    addTearDown(rebound.close);
    expect(rebound.port, port);
  });
}
