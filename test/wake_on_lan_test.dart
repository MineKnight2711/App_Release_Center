import 'package:app_management_center/app/models/wake_diagnostics.dart';
import 'package:app_management_center/app/services/machine_power_service.dart';
import 'package:app_management_center/app/services/wake_diagnostics_service.dart';
import 'package:app_management_center/app/services/wake_on_lan_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('magic packet', () {
    test('is six 0xFF bytes then the MAC sixteen times', () {
      final packet = WakeOnLanService.buildMagicPacket('84:9E:56:EA:B7:F1');

      expect(packet, hasLength(102));
      expect(packet.sublist(0, 6), everyElement(0xFF));

      const mac = [0x84, 0x9E, 0x56, 0xEA, 0xB7, 0xF1];
      for (var repeat = 0; repeat < 16; repeat++) {
        final start = 6 + (repeat * 6);
        expect(
          packet.sublist(start, start + 6),
          mac,
          reason: 'repetition $repeat',
        );
      }
    });

    test('accepts the separators adapters actually report', () {
      const expected = [0x84, 0x9E, 0x56, 0xEA, 0xB7, 0xF1];
      for (final form in [
        '84:9E:56:EA:B7:F1',
        '84-9E-56-EA-B7-F1',
        '849e56eab7f1',
        '84 9e 56 ea b7 f1',
      ]) {
        expect(
          WakeOnLanService.buildMagicPacket(form).sublist(6, 12),
          expected,
          reason: form,
        );
      }
    });

    test('refuses anything that is not six octets', () {
      for (final bad in ['', '84:9E:56', '84:9E:56:EA:B7:F1:AA', 'zz']) {
        expect(
          () => WakeOnLanService.buildMagicPacket(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('sends to broadcast and last-known host addresses', () async {
      // Three targets times two ports. Nothing is listening, which is fine — a
      // magic packet is never acknowledged.
      final sent = await const WakeOnLanService().sendMagicPacket(
        '84:9E:56:EA:B7:F1',
        broadcastAddress: '192.168.1.255',
        hostAddress: '192.168.1.225',
      );

      expect(sent, 6);
    });

    test('still sends when no subnet broadcast is known', () async {
      final sent = await const WakeOnLanService().sendMagicPacket(
        '84:9E:56:EA:B7:F1',
      );

      expect(sent, 2);
    });

    test(
      'can repeat a burst so a sleepy adapter has several chances',
      () async {
        final sent = await const WakeOnLanService().sendMagicPacket(
          '84:9E:56:EA:B7:F1',
          broadcastAddress: '192.168.1.255',
          repeatCount: 3,
          repeatInterval: Duration.zero,
        );

        expect(sent, 12);
      },
    );
  });

  group('broadcast address', () {
    test('derives from an address and prefix length', () {
      expect(
        WakeDiagnosticsService.broadcastFor('192.168.1.225', 24),
        '192.168.1.255',
      );
      expect(
        WakeDiagnosticsService.broadcastFor('10.0.5.7', 16),
        '10.0.255.255',
      );
      expect(
        WakeDiagnosticsService.broadcastFor('172.16.3.9', 30),
        '172.16.3.11',
      );
    });

    test('gives up on input it cannot use', () {
      expect(WakeDiagnosticsService.broadcastFor('192.168.1.1', null), isNull);
      expect(WakeDiagnosticsService.broadcastFor('', 24), isNull);
      expect(WakeDiagnosticsService.broadcastFor('192.168.1', 24), isNull);
      expect(WakeDiagnosticsService.broadcastFor('192.168.1.999', 24), isNull);
      expect(WakeDiagnosticsService.broadcastFor('192.168.1.1', 33), isNull);
    });
  });

  group('reading diagnostics', () {
    // Captured from a real machine: MediaTek Wi-Fi 7, Fast Startup on, and a
    // card that does support magic packets and is armed to use them.
    const realOutput =
        '{"adapterName":"Wi-Fi","physicalMediaType":"Native 802.11",'
        '"mac":"84-9E-56-EA-B7-F1","ipv4":"192.168.1.225","prefixLength":24,'
        '"wakeOnMagicPacket":1,"wakeOnPattern":1,"shutdownWakeOnLan":null,'
        '"wakeArmed":true,"hiberbootEnabled":1,"disableArso":null,'
        '"bitlockerPin":null}';

    test('reads a real machine correctly', () {
      final wake = WakeDiagnosticsService.parse(
        realOutput,
        autoStartEnabled: true,
        sleepSupport: const MachineSleepSupport(standby: true, hibernate: true),
      );

      expect(wake.macAddress, '84:9E:56:EA:B7:F1');
      expect(wake.ipAddress, '192.168.1.225');
      expect(wake.broadcastAddress, '192.168.1.255');
      expect(wake.wirelessAdapter, isTrue);
      expect(wake.wakeOnMagicPacket, isTrue);
      expect(wake.wakeArmed, isTrue);
      expect(wake.fastStartupEnabled, isTrue);
      // The Wi-Fi driver has no shutdown switch at all, which is unknown and
      // must not be read as "disabled".
      expect(wake.shutdownWakeOnLan, isNull);
    });

    test('a Wi-Fi card supporting magic packets can wake from sleep', () {
      final wake = WakeDiagnosticsService.parse(
        realOutput,
        autoStartEnabled: true,
        sleepSupport: const MachineSleepSupport(standby: true, hibernate: true),
      );

      expect(
        wake.canWakeFromSleep,
        isTrue,
        reason: 'wireless alone must not disqualify a capable card',
      );
      expect(
        wake.canWakeFromShutdown,
        isFalse,
        reason: 'a wireless card loses power when the machine is off',
      );

      final titles = wake.blockers.map((blocker) => blocker.title).toList();
      expect(titles, contains('Chỉ đánh thức được từ trạng thái Ngủ'));
      // Measured on the real machine: it woke itself 3-6 seconds after every
      // sleep, which reads as "sleep is broken" until this is pointed out.
      expect(titles, contains('Máy sẽ tự dậy ngay sau khi ngủ'));
      expect(
        titles.where((title) => title.contains('đang tắt Wake on Magic')),
        isEmpty,
        reason: 'the card is enabled, so do not claim otherwise',
      );
    });

    test('an unreadable setting never becomes a false accusation', () {
      final wake = WakeDiagnosticsService.parse(
        '{"adapterName":"Wi-Fi","physicalMediaType":"Native 802.11",'
        '"mac":"84-9E-56-EA-B7-F1","wakeOnMagicPacket":null,'
        '"disableArso":null,"bitlockerPin":null}',
      );

      final titles = wake.blockers.map((blocker) => blocker.title);
      expect(
        titles,
        isNot(contains(contains('đang tắt Wake on Magic'))),
        reason: 'the setting could not be read, so say it is unknown instead',
      );
      expect(titles, contains(contains('Không đọc được cấu hình')));
      expect(
        titles,
        isNot(contains(contains('tự đăng nhập lại'))),
        reason: 'the policy value was absent, not set to block',
      );
    });

    test('survives output that is not JSON at all', () {
      final wake = WakeDiagnosticsService.parse('Access denied.');

      expect(wake.canAttemptWake, isFalse);
      expect(wake.macAddress, isEmpty);
      expect(wake.blockers, isNotEmpty);
    });

    test('normalises the MAC forms adapters report', () {
      expect(
        WakeDiagnosticsService.normalizeMac('84-9e-56-ea-b7-f1'),
        '84:9E:56:EA:B7:F1',
      );
      expect(WakeDiagnosticsService.normalizeMac(''), isEmpty);
      expect(WakeDiagnosticsService.normalizeMac('not-a-mac'), isEmpty);
    });
  });

  group('blockers', () {
    test(
      'pattern-match wake is reported before anything about magic packets',
      () {
        const wake = WakeDiagnostics(
          adapterName: 'Wi-Fi',
          macAddress: '84:9E:56:EA:B7:F1',
          autoStartEnabled: true,
          standbySupported: true,
          wakeOnMagicPacket: true,
          wakeOnPattern: true,
          wakeArmed: true,
        );

        final titles = wake.blockers.map((blocker) => blocker.title).toList();
        final pattern = titles.indexWhere((t) => t.contains('tự dậy ngay'));
        expect(pattern, greaterThanOrEqualTo(0));
        expect(wake.blockers[pattern].fix, contains('magic packet'));
      },
    );

    test('a wireless card Windows calls ready still points at the BIOS', () {
      // The real machine: magic packet Enabled, armed, pattern match off,
      // keyboard wake working — and the phone still could not wake it.
      const wake = WakeDiagnostics(
        adapterName: 'Wi-Fi',
        wirelessAdapter: true,
        macAddress: '84:9E:56:EA:B7:F1',
        broadcastAddress: '192.168.1.255',
        autoStartEnabled: true,
        standbySupported: true,
        hibernateSupported: true,
        wakeOnMagicPacket: true,
        wakeOnPattern: false,
        wakeArmed: true,
      );

      final blocker = wake.blockers.singleWhere(
        (entry) => entry.title.contains('phụ thuộc BIOS'),
      );
      expect(blocker.fix, contains('Wake on WLAN'));
      expect(
        blocker.detail,
        contains('Bàn phím'),
        reason: 'the symptom is what lets someone recognise their own case',
      );
    });

    test('a wired card ready to wake is not sent to the BIOS', () {
      const wake = WakeDiagnostics(
        adapterName: 'Ethernet',
        macAddress: '84:9E:56:EA:B7:F1',
        autoStartEnabled: true,
        standbySupported: true,
        hibernateSupported: true,
        wakeOnMagicPacket: true,
        wakeOnPattern: false,
        wakeArmed: true,
        shutdownWakeOnLan: true,
        fastStartupEnabled: false,
        autoSignOnBlocked: false,
        bitLockerPreBootPin: false,
      );

      expect(wake.blockers, isEmpty);
    });

    test('pattern-match off is not reported', () {
      const wake = WakeDiagnostics(
        adapterName: 'Ethernet',
        macAddress: '84:9E:56:EA:B7:F1',
        autoStartEnabled: true,
        standbySupported: true,
        hibernateSupported: true,
        wakeOnMagicPacket: true,
        wakeOnPattern: false,
        wakeArmed: true,
        shutdownWakeOnLan: true,
        fastStartupEnabled: false,
        autoSignOnBlocked: false,
        bitLockerPreBootPin: false,
      );

      expect(wake.blockers, isEmpty);
    });

    test('a pre-boot PIN outranks everything and is fatal', () {
      const wake = WakeDiagnostics(
        macAddress: '84:9E:56:EA:B7:F1',
        autoStartEnabled: true,
        standbySupported: true,
        wakeOnMagicPacket: true,
        wakeArmed: true,
        bitLockerPreBootPin: true,
      );

      expect(wake.blockers.first.fatal, isTrue);
      expect(wake.blockers.first.title, contains('BitLocker'));
    });

    test('a wired machine set up properly reports nothing to fix', () {
      const wake = WakeDiagnostics(
        adapterName: 'Ethernet',
        macAddress: '84:9E:56:EA:B7:F1',
        autoStartEnabled: true,
        standbySupported: true,
        hibernateSupported: true,
        wakeOnMagicPacket: true,
        wakeArmed: true,
        shutdownWakeOnLan: true,
        fastStartupEnabled: false,
        autoSignOnBlocked: false,
        bitLockerPreBootPin: false,
      );

      expect(wake.canWakeFromSleep, isTrue);
      expect(wake.canWakeFromShutdown, isTrue);
      expect(wake.blockers, isEmpty);
    });

    test('a card supporting magic packets but not armed is called out', () {
      const wake = WakeDiagnostics(
        adapterName: 'Ethernet',
        macAddress: '84:9E:56:EA:B7:F1',
        autoStartEnabled: true,
        standbySupported: true,
        wakeOnMagicPacket: true,
        wakeArmed: false,
      );

      expect(wake.canWakeFromSleep, isFalse);
      expect(
        wake.blockers.map((blocker) => blocker.title).join(),
        contains('chưa cho card mạng đánh thức'),
      );
    });

    test('shutdown wake off is reported as a sleep-only boundary', () {
      const wake = WakeDiagnostics(
        adapterName: 'Ethernet',
        macAddress: '84:9E:56:EA:B7:F1',
        autoStartEnabled: true,
        standbySupported: true,
        wakeOnMagicPacket: true,
        wakeArmed: true,
        shutdownWakeOnLan: false,
        fastStartupEnabled: false,
      );

      expect(wake.canWakeFromSleep, isTrue);
      expect(wake.canWakeFromShutdown, isFalse);
      final blocker = wake.blockers.singleWhere(
        (entry) => entry.title.contains('Chỉ đánh thức được'),
      );
      expect(blocker.detail, contains('Shutdown Wake-On-Lan'));
    });

    test('an agent that never starts makes a successful wake invisible', () {
      const wake = WakeDiagnostics(
        macAddress: '84:9E:56:EA:B7:F1',
        standbySupported: true,
        wakeOnMagicPacket: true,
        wakeArmed: true,
      );

      expect(
        wake.blockers.map((blocker) => blocker.title).join(),
        contains('không tự khởi động'),
      );
    });

    test('every blocker says what to do about it', () {
      const wake = WakeDiagnostics(
        wirelessAdapter: true,
        wakeOnMagicPacket: false,
        wakeArmed: false,
        fastStartupEnabled: true,
        autoSignOnBlocked: true,
        bitLockerPreBootPin: true,
      );

      expect(wake.blockers, isNotEmpty);
      for (final blocker in wake.blockers) {
        expect(blocker.fix, isNotEmpty, reason: blocker.title);
        expect(blocker.detail, isNotEmpty, reason: blocker.title);
      }
    });
  });

  group('packet reach reporting', () {
    test('survives the heartbeat so the phone can show it', () {
      final seenAt = DateTime.now();
      const base = WakeDiagnostics(
        adapterName: 'Wi-Fi',
        macAddress: '84:9E:56:EA:B7:F1',
      );

      final restored = WakeDiagnostics.fromJson(
        base
            .withProbe(
              probeListening: true,
              lastPacketAt: seenAt,
              lastPacketFrom: '192.168.1.50',
            )
            .toJson(),
      );

      expect(restored.probeListening, isTrue);
      expect(restored.lastPacketFrom, '192.168.1.50');
      expect(
        restored.lastPacketAt!.difference(seenAt).inSeconds.abs(),
        lessThan(2),
      );
    });

    test('never having heard a packet is distinct from not listening', () {
      const base = WakeDiagnostics(macAddress: '84:9E:56:EA:B7:F1');

      final listening = base.withProbe(probeListening: true);
      final notListening = base.withProbe(probeListening: false);

      expect(listening.lastPacketAt, isNull);
      expect(listening.probeListening, isTrue);
      expect(notListening.probeListening, isFalse);
    });

    test('withProbe leaves the rest of the reading alone', () {
      const base = WakeDiagnostics(
        adapterName: 'Wi-Fi',
        wirelessAdapter: true,
        macAddress: '84:9E:56:EA:B7:F1',
        broadcastAddress: '192.168.1.255',
        wakeOnMagicPacket: true,
        wakeArmed: true,
        fastStartupEnabled: true,
        autoStartEnabled: true,
        standbySupported: true,
      );

      final probed = base.withProbe(probeListening: true);

      expect(probed.macAddress, base.macAddress);
      expect(probed.broadcastAddress, base.broadcastAddress);
      expect(probed.wakeOnMagicPacket, isTrue);
      expect(probed.wakeArmed, isTrue);
      expect(probed.fastStartupEnabled, isTrue);
      expect(probed.wirelessAdapter, isTrue);
      expect(probed.blockers.length, base.blockers.length);
    });
  });

  group('round trip', () {
    test('survives the heartbeat', () {
      const original = WakeDiagnostics(
        adapterName: 'Ethernet',
        wirelessAdapter: false,
        macAddress: '84:9E:56:EA:B7:F1',
        ipAddress: '192.168.1.225',
        broadcastAddress: '192.168.1.255',
        wakeOnMagicPacket: true,
        wakeArmed: true,
        shutdownWakeOnLan: false,
        fastStartupEnabled: false,
        autoSignOnBlocked: null,
        bitLockerPreBootPin: false,
        autoStartEnabled: true,
        standbySupported: true,
        hibernateSupported: true,
      );

      final restored = WakeDiagnostics.fromJson(original.toJson());

      expect(restored.macAddress, original.macAddress);
      expect(restored.ipAddress, original.ipAddress);
      expect(restored.broadcastAddress, original.broadcastAddress);
      expect(restored.wakeOnMagicPacket, isTrue);
      expect(restored.wakeArmed, isTrue);
      expect(restored.shutdownWakeOnLan, isFalse);
      expect(restored.fastStartupEnabled, isFalse);
      expect(
        restored.autoSignOnBlocked,
        isNull,
        reason: 'unknown must not collapse into false across the wire',
      );
      expect(restored.autoStartEnabled, isTrue);
    });
  });
}
