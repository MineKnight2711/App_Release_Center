import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/services/weak_network_proxy.dart';
import 'package:app_management_center/app/modules/qa_desk/controllers/network_test_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'HTTPS completes TLS through proxy with certificate validation',
    () async {
      final context = SecurityContext()
        ..useCertificateChain('test/fixtures/qa_desk/localhost-test-cert.pem')
        ..usePrivateKey('test/fixtures/qa_desk/localhost-test-key.pem');
      final origin = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      origin.listen((request) async {
        request.response.write('secure API response');
        await request.response.close();
      });
      final proxy = WeakNetworkProxy(
        const NetworkProfile('TLS test', 32768, 0),
      );
      await proxy.start();
      final trust = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates(
          'test/fixtures/qa_desk/localhost-test-cert.pem',
        );
      final client = HttpClient(context: trust)
        ..findProxy = (_) => 'PROXY 127.0.0.1:${proxy.port}';
      addTearDown(() async {
        client.close(force: true);
        await proxy.stop();
        await origin.close(force: true);
      });
      final request = await client.getUrl(
        Uri.parse('https://127.0.0.1:${origin.port}/api'),
      );
      final response = await request.close();
      expect(await utf8.decoder.bind(response).join(), 'secure API response');
      expect(proxy.downloaded, greaterThan(19));
    },
  );
  test(
    'HTTP upload and download are paced at 0.5 KB/s and keep status',
    () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final proxy = WeakNetworkProxy(const NetworkProfile('test', 512, 100));
      await proxy.start();
      final client = HttpClient()
        ..findProxy = (_) => 'PROXY 127.0.0.1:${proxy.port}';
      addTearDown(() async {
        client.close(force: true);
        await proxy.stop();
        await origin.close(force: true);
      });
      final received = Completer<int>();
      origin.listen((request) async {
        final bytes = await request.fold<int>(
          0,
          (sum, chunk) => sum + chunk.length,
        );
        received.complete(bytes);
        request.response.statusCode = 201;
        request.response.contentLength = 512;
        request.response.add(List.filled(512, 65));
        await request.response.close();
      });
      final watch = Stopwatch()..start();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:${origin.port}/api'),
      );
      request.add(List.filled(512, 66));
      final response = await request.close();
      final body = await response.fold<int>(
        0,
        (sum, chunk) => sum + chunk.length,
      );
      expect(await received.future, 512);
      expect(response.statusCode, 201);
      expect(body, 512);
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(2050));
      expect(proxy.uploaded, greaterThanOrEqualTo(512));
      expect(proxy.downloaded, greaterThanOrEqualTo(512));
      expect(proxy.connections, 1);
    },
  );

  test(
    'CONNECT forwards opaque bytes bidirectionally through the limiter',
    () async {
      final origin = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final upstreams = <Socket>[];
      origin.listen((socket) {
        upstreams.add(socket);
        socket.listen(socket.add, onError: (_) {});
      });
      final proxy = WeakNetworkProxy(const NetworkProfile('test', 512, 0));
      await proxy.start();
      final socket = await Socket.connect('127.0.0.1', proxy.port);
      addTearDown(() async {
        socket.destroy();
        for (final item in upstreams) {
          item.destroy();
        }
        await proxy.stop();
        await origin.close();
      });
      final headers = Completer<void>();
      final echoed = Completer<void>();
      final received = <int>[];
      var ready = false;
      var payloadBytes = 0;
      socket.listen((data) {
        if (!ready) {
          received.addAll(data);
          if (ascii.decode(received).contains('\r\n\r\n')) {
            expect(ascii.decode(received), startsWith('HTTP/1.1 200'));
            ready = true;
            headers.complete();
          }
        } else {
          expect(data.every((byte) => byte == 42), isTrue);
          payloadBytes += data.length;
          if (payloadBytes == 256) echoed.complete();
        }
      });
      socket.write(
        'CONNECT 127.0.0.1:${origin.port} HTTP/1.1\r\nHost: 127.0.0.1:${origin.port}\r\n\r\n',
      );
      await socket.flush();
      await headers.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError('No CONNECT headers: $received'),
      );
      final watch = Stopwatch()..start();
      socket.add(List.filled(256, 42));
      await echoed.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError(
          'No echo: $payloadBytes uploaded=${proxy.uploaded} downloaded=${proxy.downloaded}',
        ),
      );
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(500));
      expect(proxy.uploaded, 256);
      expect(proxy.downloaded, 256);
    },
  );

  test(
    'stop interrupts pending latency and allows fresh proxy startup',
    () async {
      final proxy = WeakNetworkProxy(const NetworkProfile('test', 512, 10000));
      await proxy.start();
      final socket = await Socket.connect('127.0.0.1', proxy.port);
      addTearDown(socket.destroy);
      socket.write(
        'GET http://127.0.0.1:1/ HTTP/1.1\r\nHost: localhost\r\n\r\n',
      );
      final done = socket.drain<void>().catchError((Object _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await proxy.stop();
      await done.timeout(const Duration(seconds: 2));
      final next = WeakNetworkProxy(NetworkProfile.presets.first);
      await next.start();
      await next.stop();
    },
  );

  test(
    'API probe distinguishes success, HTTP error, timeout and cancel',
    () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin.listen((request) async {
        request.response.statusCode = request.uri.path == '/error' ? 503 : 200;
        request.response.add(
          List.filled(request.uri.path == '/slow' ? 1000000 : 16, 65),
        );
        try {
          await request.response.close();
        } on Object {
          /* Cancellation. */
        }
      });
      final model = NetworkTestController();
      model.selectProfile(const NetworkProfile('test', 8192, 0));
      await model.toggle();
      addTearDown(() async {
        model.dispose();
        await origin.close(force: true);
      });
      expect(model.environment['HTTPS_PROXY'], model.proxyUrl);
      model.apiUrl = 'http://127.0.0.1:${origin.port}/ok';
      await model.testApi();
      expect(model.result, contains('phản hồi 2xx'));
      expect(model.connections, greaterThan(0));
      model.apiUrl = 'http://127.0.0.1:${origin.port}/error';
      await model.testApi();
      expect(model.result, contains('HTTP 503'));
      model.apiUrl = 'http://127.0.0.1:${origin.port}/slow';
      model.timeoutSeconds = 1;
      await model.testApi();
      expect(model.result, contains('Timeout sau 1 giây'));
      final pending = model.testApi();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      model.cancelProbe();
      await pending.timeout(const Duration(seconds: 2));
      expect(model.result, contains('Đã dừng'));
      await model.toggle();
      expect(model.environment, isEmpty);
    },
  );
}
