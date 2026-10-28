import 'dart:convert';

import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:amc_remote_core/probe_signal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 23, 5);
  RemoteInputPacket packet(int sequence, {String session = 'local-session'}) =>
      RemoteInputPacket(
        sessionId: session,
        sequence: sequence,
        input: RemoteText('Tiếng Việt ✓'),
      );

  test(
    'input requires explicit grant and is revoked by disable, expiry and close',
    () {
      final gate = RemoteInputGate(
        sessionId: 'local-session',
        expiresAt: now.add(const Duration(minutes: 1)),
      );
      expect(gate.accept(packet(0), now: now), isFalse);
      gate.setEnabled(true);
      expect(gate.accept(packet(0), now: now), isTrue);
      gate.setEnabled(false);
      expect(gate.accept(packet(1), now: now), isFalse);
      gate.setEnabled(true);
      expect(
        gate.accept(packet(1), now: now.add(const Duration(minutes: 1))),
        isFalse,
      );
      gate.close();
      expect(gate.accept(packet(1), now: now), isFalse);
      expect(() => gate.setEnabled(true), throwsStateError);
    },
  );

  test('reordered, duplicate and foreign-session packets never apply', () {
    final gate = RemoteInputGate(
      sessionId: 'local-session',
      expiresAt: now.add(const Duration(minutes: 1)),
    )..setEnabled(true);
    expect(
      gate.accept(packet(90, session: 'another-session'), now: now),
      isFalse,
    );
    expect(gate.accept(packet(2), now: now), isTrue);
    expect(gate.accept(packet(1), now: now), isFalse);
    expect(gate.accept(packet(2), now: now), isFalse);
    expect(gate.accept(packet(3), now: now), isTrue);
  });

  test('versioned input preserves Unicode and normalized coordinates', () {
    final decoded = RemoteInputPacket.decode(packet(0).encode());
    expect((decoded.input as RemoteText).text, 'Tiếng Việt ✓');
    final move =
        RemoteInputPacket.decode(
              RemoteInputPacket(
                sessionId: 'local-session',
                sequence: 4,
                input: RemotePointer(0.25, 1),
              ).encode(),
            ).input
            as RemotePointer;
    expect(move.x, 0.25);
    expect(move.y, 1);
  });

  test('malformed input is rejected before native dispatch', () {
    final valid = jsonDecode(packet(0).encode()) as Map<String, dynamic>;
    for (final value in [
      '[]',
      '{',
      'x' * 16385,
      jsonEncode({...valid, 'version': 2}),
      jsonEncode({...valid, 'sequence': -1}),
      jsonEncode({...valid, 'sequence': 1.5}),
      jsonEncode({...valid, 'sessionId': ''}),
      jsonEncode({
        ...valid,
        'input': {'type': 'shell', 'command': 'ignored'},
      }),
      jsonEncode({
        ...valid,
        'input': {'type': 'pointer', 'x': -0.1, 'y': 0},
      }),
      jsonEncode({
        ...valid,
        'input': {'type': 'text', 'text': 'bad\u0000text'},
      }),
      jsonEncode({
        ...valid,
        'input': {'type': 'text', 'text': 'x' * 1025},
      }),
    ]) {
      expect(() => RemoteInputPacket.decode(value), throwsFormatException);
    }
    expect(() => RemotePointer(double.nan, 0), throwsFormatException);
    expect(() => RemotePointer(0, double.infinity), throwsFormatException);
  });

  const sdp = 'v=0\r\na=fingerprint:sha-256 AB:CD\r\n';
  ProbeSignal signal({DateTime? expiry}) => ProbeSignal(
    sessionId: '12345678-1234-1234-1234-123456789abc',
    type: 'offer',
    sdp: sdp,
    expiresAt: expiry ?? now.add(const Duration(minutes: 10)),
  );

  test(
    'manual signal roundtrip keeps peer fingerprint and session binding',
    () {
      final decoded = ProbeSignal.decode(signal().encode(), now: now);
      expect(decoded.sessionId, signal().sessionId);
      expect(decoded.sdp, sdp);
      expect(decoded.type, 'offer');
    },
  );

  test(
    'manual signals reject expiry, oversized data and incompatible versions',
    () {
      final valid = jsonDecode(signal().encode()) as Map<String, dynamic>;
      for (final value in [
        signal(expiry: now).encode(),
        signal(expiry: now.add(const Duration(minutes: 16))).encode(),
        'x' * 300001,
        jsonEncode({...valid, 'version': 2}),
        jsonEncode({...valid, 'sessionId': 'a'}),
        jsonEncode({...valid, 'type': 'unknown'}),
        jsonEncode({...valid, 'sdp': 'v=0\r\n'}),
      ]) {
        expect(
          () => ProbeSignal.decode(value, now: now),
          throwsFormatException,
        );
      }
    },
  );
}
