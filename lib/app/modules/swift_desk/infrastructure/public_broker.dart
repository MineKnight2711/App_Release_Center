import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'lan_identity.dart';

class RemoteBrokerMessage {
  const RemoteBrokerMessage(this.topic, this.payload);
  final String topic, payload;
}

abstract interface class RemotePublicBroker {
  bool get online;
  Stream<bool> get states;
  Stream<RemoteBrokerMessage> get messages;
  Future<void> connect();
  Future<void> subscribe(String topic);
  void unsubscribe(String topic);
  void publish(String topic, String payload);
  Future<void> close();
}

/// Public rendezvous only. Both broker clusters receive the same bounded,
/// authenticated envelopes, so peers can meet even if one endpoint is blocked.
/// No account, password, raw trust token, SDP or media is published in plaintext.
class MqttPublicBroker implements RemotePublicBroker {
  final _clients = <MqttServerClient>[];
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _topics = <String>{};
  final _acks = <MqttServerClient, Map<String, Completer<void>>>{};
  final _messages = StreamController<RemoteBrokerMessage>.broadcast();
  final _states = StreamController<bool>.broadcast();
  Future<void>? _connecting;
  bool _closed = false;
  @override
  bool get online => _clients.any(
    (c) => c.connectionStatus?.state == MqttConnectionState.connected,
  );
  @override
  Stream<bool> get states => _states.stream;
  @override
  Stream<RemoteBrokerMessage> get messages => _messages.stream;
  @override
  Future<void> connect() =>
      _connecting ??= _connect().whenComplete(() => _connecting = null);

  Future<void> _connect() async {
    if (_closed) throw StateError('Dịch vụ ghép nối đã đóng.');
    if (online) return;
    await Future.wait([
      _cluster([
        'mqtts://broker.emqx.io:8883',
        'wss://broker.emqx.io:8084/mqtt',
      ]),
      _cluster(['wss://broker.hivemq.com:8884/mqtt']),
    ]);
    if (!online) {
      throw StateError(
        'Chưa tới được dịch vụ ghép nối. Kiểm tra Internet rồi thử lại.',
      );
    }
  }

  Future<void> _cluster(List<String> urls) async {
    for (final url in urls) {
      if (_closed) return;
      final uri = Uri.parse(url);
      final client = MqttServerClient.withPort(
        uri.scheme == 'mqtts' ? uri.host : url,
        'amc_${remoteToken().substring(0, 16)}',
        uri.port,
        maxConnectionAttempts: 1,
      )..logging(on: false);
      client.setProtocolV311();
      client.keepAlivePeriod = 20;
      client.connectTimeoutPeriod = 4000;
      client.useWebSocket = uri.scheme == 'wss';
      client.secure = uri.scheme == 'mqtts';
      client.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(client.clientIdentifier)
          .startClean();
      _acks[client] = {};
      client.onSubscribed = (topic) => _acks[client]?.remove(topic)?.complete();
      client.onSubscribeFail = (topic) => _acks[client]
          ?.remove(topic)
          ?.completeError(StateError('Không đăng ký được mã máy.'));
      client.onAutoReconnect = () {
        if (!_closed) _states.add(online);
      };
      client.onAutoReconnected = () {
        if (!_closed) _states.add(online);
      };
      client.onDisconnected = () {
        if (!_closed) _states.add(online);
      };
      try {
        await client.connect().timeout(const Duration(seconds: 6));
        if (_closed ||
            client.connectionStatus?.state != MqttConnectionState.connected) {
          throw StateError('offline');
        }
        _clients.add(client);
        _subscriptions.add(
          client.updates!.listen((batch) {
            if (_closed) return;
            for (final update in batch) {
              final message = update.payload;
              if (message is! MqttPublishMessage ||
                  message.header?.retain == true) {
                continue;
              }
              final bytes = message.payload.message;
              if (bytes.length > 400000 || !_topics.contains(update.topic)) {
                continue;
              }
              try {
                _messages.add(
                  RemoteBrokerMessage(update.topic, utf8.decode(bytes)),
                );
              } catch (_) {}
            }
          }),
        );
        for (final topic in _topics) {
          await _subscribe(client, topic);
        }
        client.autoReconnect = true;
        client.resubscribeOnAutoReconnect = true;
        _states.add(true);
        return;
      } catch (_) {
        _clients.remove(client);
        _acks.remove(client);
        client.disconnect();
      }
    }
  }

  Future<void> _subscribe(MqttServerClient client, String topic) async {
    final pending = _acks[client]![topic] ??= Completer<void>();
    client.subscribe(topic, MqttQos.atMostOnce);
    try {
      await pending.future.timeout(const Duration(seconds: 4));
    } finally {
      _acks[client]?.remove(topic);
    }
  }

  @override
  Future<void> subscribe(String topic) async {
    _topics.add(topic);
    final clients = _clients
        .where(
          (c) => c.connectionStatus?.state == MqttConnectionState.connected,
        )
        .toList();
    if (clients.isEmpty) throw StateError('Dịch vụ ghép nối chưa sẵn sàng.');
    final results = await Future.wait(
      clients.map((c) async {
        try {
          await _subscribe(c, topic);
          return true;
        } catch (_) {
          return false;
        }
      }),
    );
    if (!results.any((v) => v)) throw StateError('Không đăng ký được mã máy.');
  }

  @override
  void unsubscribe(String topic) {
    _topics.remove(topic);
    for (final client in _clients) {
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        client.unsubscribe(topic);
      }
    }
  }

  @override
  void publish(String topic, String payload) {
    if (_closed || !online) {
      throw StateError('Dịch vụ ghép nối đang mất kết nối.');
    }
    final bytes = utf8.encode(payload);
    if (bytes.length > 400000) {
      throw const FormatException('Thông điệp ghép nối quá lớn.');
    }
    final body = MqttClientPayloadBuilder()..addUTF8String(payload);
    for (final client in _clients) {
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        client.publishMessage(
          topic,
          MqttQos.atMostOnce,
          body.payload!,
          retain: false,
        );
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final client in _clients) {
      client.autoReconnect = false;
      client.disconnect();
    }
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _clients.clear();
    await _messages.close();
    await _states.close();
  }
}
