import 'dart:convert';
import 'dart:io';

import 'package:app_release_center/app/models/api_tool.dart';
import 'package:app_release_center/app/services/api_tool_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves collection environment variables before sending', () {
    final request = resolveApiToolRequestVariables(
      ApiToolRequest(
        id: 'request-1',
        name: 'Variables',
        method: ApiToolMethod.post,
        url: '{{BASE_URL}}/users',
        headers: const [
          ApiToolHeader(
            id: 'header-1',
            name: 'Authorization',
            value: 'Bearer {{TOKEN}}',
          ),
        ],
        body: '{"host":"{{BASE_URL}}"}',
        bodyMode: ApiToolBodyMode.multipart,
        multipartFields: const [
          ApiToolMultipartEntry(
            id: 'part-1',
            name: 'asset',
            value: '{{ASSET_PATH}}',
            kind: ApiToolMultipartKind.file,
          ),
        ],
        updatedAt: DateTime.utc(2026, 8, 4),
      ),
      const {
        'BASE_URL': 'https://api.example.com',
        'TOKEN': 'secret',
        'ASSET_PATH': r'C:\tmp\demo.txt',
      },
    );

    expect(request.url, 'https://api.example.com/users');
    expect(request.headers.single.value, 'Bearer secret');
    expect(request.body, '{"host":"https://api.example.com"}');
    expect(request.multipartFields.single.value, r'C:\tmp\demo.txt');
  });

  test('resolves environment variables with spaces in their names', () {
    final request = resolveApiToolRequestVariables(
      ApiToolRequest(
        id: 'request-1',
        name: 'Variables',
        method: ApiToolMethod.post,
        url: '{{Base Url}}',
        headers: const [
          ApiToolHeader(
            id: 'header-1',
            name: 'x-api-key',
            value: '{{Api Key}}',
          ),
        ],
        body: '{"host":"{{ Base Url }}"}',
        updatedAt: DateTime.utc(2026, 8, 4),
      ),
      const {
        'Base Url': 'https://emed.vn/APIs-Android.htm',
        'Api Key': 'secret',
      },
    );

    expect(request.url, 'https://emed.vn/APIs-Android.htm');
    expect(request.headers.single.value, 'secret');
    expect(request.body, '{"host":"https://emed.vn/APIs-Android.htm"}');
  });

  test('sends GET and POST requests with headers and body', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = <String, Object?>{};

    server.listen((request) async {
      if (request.method == 'GET') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'method': 'GET', 'ok': true}));
        await request.response.close();
        return;
      }

      final body = await utf8.decoder.bind(request).join();
      received['method'] = request.method;
      received['body'] = body;
      received['header'] = request.headers.value('x-test');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'method': request.method,
          'received': body,
          'header': request.headers.value('x-test'),
        }),
      );
      await request.response.close();
    });

    final service = ApiToolService(timeout: const Duration(seconds: 2));
    final baseUrl = 'http://${server.address.host}:${server.port}';

    final getResponse = await service.send(
      ApiToolRequest(
        id: 'get-1',
        name: 'GET demo',
        method: ApiToolMethod.get,
        url: '$baseUrl/users',
        updatedAt: DateTime.utc(2026, 8, 4),
      ),
    );
    final postResponse = await service.send(
      ApiToolRequest(
        id: 'post-1',
        name: 'POST demo',
        method: ApiToolMethod.post,
        url: '$baseUrl/users',
        headers: const [
          ApiToolHeader(id: 'header-1', name: 'x-test', value: 'demo'),
        ],
        body: '{"name":"Demo"}',
        updatedAt: DateTime.utc(2026, 8, 4),
      ),
    );

    expect(getResponse.statusCode, 200);
    expect(getResponse.body, contains('"ok": true'));
    expect(received['method'], 'POST');
    expect(received['header'], 'demo');
    expect(received['body'], '{"name":"Demo"}');
    expect(postResponse.statusCode, 200);
    expect(
      postResponse.body,
      contains('"received": "{\\"name\\":\\"Demo\\"}"'),
    );
  });

  test('rejects non-http URLs', () async {
    final service = ApiToolService(timeout: const Duration(seconds: 2));

    await expectLater(
      service.send(
        ApiToolRequest(
          id: 'bad-url',
          name: 'Bad URL',
          method: ApiToolMethod.get,
          url: 'ftp://example.com',
          updatedAt: DateTime.utc(2026, 8, 4),
        ),
      ),
      throwsA(
        isA<ApiToolException>().having(
          (error) => error.message,
          'message',
          contains('http or https'),
        ),
      ),
    );
  });

  test('sends multipart form-data with text and file fields', () async {
    final temp = await Directory.systemTemp.createTemp('arc_api_tool_');
    addTearDown(() => temp.delete(recursive: true));
    final file = await File(
      '${temp.path}${Platform.pathSeparator}demo.txt',
    ).writeAsString('file-body');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = <String, String>{};

    server.listen((request) async {
      received['contentType'] =
          request.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      received['body'] = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'ok': true}));
      await request.response.close();
    });

    final service = ApiToolService(timeout: const Duration(seconds: 2));
    final response = await service.send(
      ApiToolRequest(
        id: 'multipart-1',
        name: 'Multipart demo',
        method: ApiToolMethod.post,
        url: 'http://${server.address.host}:${server.port}/upload',
        bodyMode: ApiToolBodyMode.multipart,
        multipartFields: [
          const ApiToolMultipartEntry(
            id: 'field-1',
            name: 'name',
            value: 'Demo',
          ),
          ApiToolMultipartEntry(
            id: 'field-2',
            kind: ApiToolMultipartKind.file,
            name: 'asset',
            value: file.path,
            contentType: 'text/plain',
          ),
        ],
        updatedAt: DateTime.utc(2026, 8, 4),
      ),
    );

    expect(response.statusCode, 200);
    expect(received['contentType'], contains('multipart/form-data'));
    expect(received['contentType'], contains('boundary='));
    expect(received['body'], contains('name="name"'));
    expect(received['body'], contains('Demo'));
    expect(received['body'], contains('name="asset"; filename="demo.txt"'));
    expect(received['body'], contains('Content-Type: text/plain'));
    expect(received['body'], contains('file-body'));
  });

  test('reports request timeouts', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      request.response.write('late');
      await request.response.close();
    });

    final service = ApiToolService(timeout: const Duration(milliseconds: 25));

    await expectLater(
      service.send(
        ApiToolRequest(
          id: 'slow',
          name: 'Slow',
          method: ApiToolMethod.get,
          url: 'http://${server.address.host}:${server.port}/slow',
          updatedAt: DateTime.utc(2026, 8, 4),
        ),
      ),
      throwsA(
        isA<ApiToolException>().having(
          (error) => error.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });
}
