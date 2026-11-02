import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/public_broker.dart';
import 'package:app_management_center/app/modules/swift_desk/infrastructure/lan_identity.dart';

/// Disposable publish/subscribe against the same public rendezvous used by AMC.
/// No user identity, account, desktop, clipboard or credential is accessed.
Future<void> main() async {
  final host = MqttPublicBroker(), viewer = MqttPublicBroker();
  try {
    await Future.wait([host.connect(), viewer.connect()]);
    final topic = 'amc/swiftdesk/v1/probe/${remoteToken()}';
    await viewer.subscribe(topic);
    final received = viewer.messages.firstWhere((m) => m.topic == topic);
    host.publish(topic, '{"disposableProbe":true}');
    final message = await received.timeout(const Duration(seconds: 10));
    if (message.payload != '{"disposableProbe":true}') {
      throw StateError('Unexpected payload');
    }
    stdout.writeln(
      jsonEncode({
        'outcome': 'passed',
        'publicBrokerRoundTrip': true,
        'accountRequired': false,
        'privateDataUsed': false,
      }),
    );
  } finally {
    await host.close();
    await viewer.close();
  }
}
