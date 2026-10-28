import 'package:amc_remote_core/amc_remote_core.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/remote_network.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/remote_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const turn = <Map<String, dynamic>>[
    {
      'urls': ['stun:turn.example:3478', 'turns:turn.example:443'],
      'username': 'temporary',
      'credential': 'temporary',
    },
  ];
  const v4 = 'a=candidate:1 1 udp 100 192.0.2.10 5000 typ host';
  const v6 = 'a=candidate:2 1 udp 100 2001:db8::10 5002 typ host';
  const relay6 = 'a=candidate:3 1 udp 100 2001:db8::30 5004 typ relay';
  const mapped = 'a=candidate:4 1 udp 100 ::ffff:192.0.2.10 5006 typ host';
  const mdns = 'a=candidate:5 1 udp 100 opaque.local 5008 typ host';
  const sdp =
      'v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\nc=IN IP4 0.0.0.0\r\na=fingerprint:sha-256 AB:CD\r\n$v4\r\n$v6\r\n$relay6\r\n$mapped\r\n$mdns\r\na=end-of-candidates\r\n';

  test(
    'automatic retains IPv6 and IPv4 candidates and available TURN fallback',
    () {
      final policy = RemoteIcePolicy(turn);
      expect(policy.description(sdp), sdp);
      expect(policy.configuration['iceTransportPolicy'], 'all');
      expect(policy.configuration['iceServers'], turn);
      expect(policy.configuration['maxIPv6Networks'], greaterThan(5));
    },
  );
  test(
    'IPv6-only excludes IPv4, mapped IPv4, mDNS and IPv6 TURN candidates in both SDP directions',
    () {
      final policy = RemoteIcePolicy(
        turn,
        mode: RemoteConnectionMode.directIpv6,
      );
      expect(policy.iceServers, isEmpty);
      final outbound = policy.description(sdp);
      final inbound = policy.description(
        sdp.replaceFirst('2001:db8::10', 'fd00::20'),
      );
      for (final description in [outbound, inbound]) {
        expect(description, isNot(contains(v4)));
        expect(description, isNot(contains(relay6)));
        expect(description, isNot(contains(mapped)));
        expect(description, isNot(contains(mdns)));
        expect(description, contains('a=fingerprint:sha-256 AB:CD'));
        expect(description, contains('c=IN IP6 ::'));
        expect(description, contains('a=end-of-candidates'));
      }
      expect(outbound, contains(v6));
      expect(inbound, contains('fd00::20'));
      expect(policy.description(outbound), outbound);
    },
  );
  test(
    'IPv6-only fails when a side offers only IPv4 or relay instead of silently falling back',
    () {
      final policy = RemoteIcePolicy(
        turn,
        mode: RemoteConnectionMode.directIpv6,
      );
      for (final candidate in [
        v4,
        relay6,
        mapped,
        mdns,
        'a=candidate:6 1 udp 100 :: 5010 typ host',
        'a=candidate:7 1 udp 100 ff02::1 5010 typ host',
      ]) {
        expect(
          () => policy.description('v=0\r\n$candidate\r\n'),
          throwsStateError,
        );
      }
    },
  );
  test(
    'relay remains explicit and requires TURN, while IPv6 P2P needs no TURN',
    () {
      expect(
        () => RemoteIcePolicy([], mode: RemoteConnectionMode.relay),
        throwsStateError,
      );
      expect(
        () => RemoteIcePolicy([
          {'urls': 'stun:turn.example:3478'},
        ], mode: RemoteConnectionMode.relay),
        throwsStateError,
      );
      expect(
        RemoteIcePolicy(
          turn,
          mode: RemoteConnectionMode.relay,
        ).configuration['iceTransportPolicy'],
        'relay',
      );
      expect(
        RemoteIcePolicy(
          [],
          mode: RemoteConnectionMode.directIpv6,
        ).description(sdp),
        contains(v6),
      );
    },
  );
  test(
    'a strict peer constrains automatic mode; incompatible strict modes are refused',
    () {
      for (final mode in RemoteConnectionMode.values) {
        expect(
          resolveRemoteConnectionMode(RemoteConnectionMode.automatic, mode),
          mode,
        );
        expect(
          resolveRemoteConnectionMode(mode, RemoteConnectionMode.automatic),
          mode,
        );
        expect(resolveRemoteConnectionMode(mode, mode), mode);
      }
      expect(
        () => resolveRemoteConnectionMode(
          RemoteConnectionMode.relay,
          RemoteConnectionMode.directIpv6,
        ),
        throwsStateError,
      );
      expect(
        () => resolveRemoteConnectionMode(
          RemoteConnectionMode.directIpv6,
          RemoteConnectionMode.relay,
        ),
        throwsStateError,
      );
      expect(parseRemoteConnectionMode(null), RemoteConnectionMode.automatic);
      expect(
        () => parseRemoteConnectionMode('silently-fallback'),
        throwsFormatException,
      );
    },
  );
  test(
    'selected path distinguishes real IPv6, IPv4 and TURN without exposing addresses',
    () {
      Map<String, dynamic> host(String address) => {
        'candidateType': 'host',
        'address': address,
      };
      expect(
        selectedRemoteNetworkPath(host('2001:db8::1'), host('2001:db8::2')),
        'direct-ipv6',
      );
      expect(
        selectedRemoteNetworkPath(host('192.0.2.1'), host('192.0.2.2')),
        'direct-ipv4',
      );
      expect(
        selectedRemoteNetworkPath(
          host('::ffff:192.0.2.1'),
          host('0:0:0:0:0:ffff:c000:202'),
        ),
        'direct-ipv4',
      );
      expect(
        selectedRemoteNetworkPath(host('2001:db8::1'), {
          'candidateType': 'relay',
          'ip': '2001:db8::3',
        }),
        'relay',
      );
      expect(
        selectedRemoteNetworkPath(
          {'candidateType': 'host', 'ip': 'fd00::1'},
          {'candidateType': 'host', 'ipAddress': 'fd00::2'},
        ),
        'direct-ipv6',
      );
      expect(
        selectedRemoteNetworkPath(host('opaque.local'), host('2001:db8::2')),
        'direct',
      );
      expect(selectedRemoteNetworkPath(null, host('2001:db8::2')), 'unknown');
      expect(remoteNetworkPathLabel('direct-ipv6'), 'P2P IPv6');
    },
  );
  test(
    'old force-TURN choice survives; new IPv6 choice persists and can return to automatic',
    () async {
      SharedPreferences.setMockInitialValues({'swift_desk.forceRelay': true});
      final prefs = await SharedPreferences.getInstance();
      final settings = SwiftDeskSettings(prefs);
      expect(settings.connectionMode, RemoteConnectionMode.relay);
      await settings.setConnectionMode(RemoteConnectionMode.directIpv6);
      expect(
        SwiftDeskSettings(prefs).connectionMode,
        RemoteConnectionMode.directIpv6,
      );
      await settings.setConnectionMode(RemoteConnectionMode.automatic);
      expect(
        SwiftDeskSettings(prefs).connectionMode,
        RemoteConnectionMode.automatic,
      );
      expect(
        SwiftDeskSettings().connectionMode,
        RemoteConnectionMode.automatic,
      );
    },
  );
}
