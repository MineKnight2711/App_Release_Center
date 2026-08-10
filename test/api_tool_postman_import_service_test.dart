import 'dart:convert';

import 'package:app_release_center/app/models/api_tool.dart';
import 'package:app_release_center/app/services/api_tool_postman_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports Postman folders, variables, headers, and body modes', () {
    final service = ApiToolPostmanCollectionImportService(
      now: () => DateTime.utc(2026, 8, 5),
    );
    final jsonText = jsonEncode({
      'info': {'name': 'Demo API'},
      'variable': [
        {'key': 'BASE_URL', 'value': 'https://api.example.com'},
      ],
      'item': [
        {
          'name': 'Auth',
          'item': [
            {
              'name': 'Login',
              'request': {
                'method': 'POST',
                'header': [
                  {'key': 'X-API-KEY', 'value': '{{API_KEY}}'},
                  {'key': 'X-DISABLED', 'value': 'off', 'disabled': true},
                ],
                'url': '{{BASE_URL}}/login',
                'body': {
                  'mode': 'urlencoded',
                  'urlencoded': [
                    {'key': 'phone', 'value': '{{PHONE}}'},
                    {'key': 'password', 'value': 'p@ss word'},
                    {'key': 'debug', 'value': '1', 'disabled': true},
                  ],
                },
              },
            },
            {
              'name': 'Upload',
              'request': {
                'method': 'POST',
                'url': '{{BASE_URL}}/upload',
                'body': {
                  'mode': 'formdata',
                  'formdata': [
                    {'key': 'name', 'value': 'Demo', 'type': 'text'},
                    {
                      'key': 'avatar',
                      'src': 'postman-cloud:///avatar',
                      'type': 'file',
                      'contentType': 'image/png',
                      'disabled': true,
                    },
                  ],
                },
              },
            },
          ],
        },
        {
          'name': 'Health',
          'request': {
            'method': 'GET',
            'url': {
              'protocol': 'https',
              'host': ['api', 'example', 'com'],
              'path': ['health'],
              'query': [
                {'key': 'status', 'value': '{{STATUS}}'},
                {'key': 'skip', 'value': '1', 'disabled': true},
              ],
            },
          },
        },
      ],
    });

    final result = service.importJsonText(jsonText);

    expect(result.collection.name, 'Demo API');
    expect(
      result.collection.activeEnvironment?.enabledVariables['BASE_URL'],
      'https://api.example.com',
    );
    expect(result.folders.single.name, 'Auth');
    expect(result.requests, hasLength(3));

    final login = result.requests.singleWhere((entry) => entry.name == 'Login');
    expect(login.method, ApiToolMethod.post);
    expect(login.url, '{{BASE_URL}}/login');
    expect(login.folderId, result.folders.single.id);
    expect(login.headers, hasLength(3));
    expect(login.headers.first.name, 'X-API-KEY');
    expect(
      login.headers.singleWhere((entry) => entry.name == 'X-DISABLED').enabled,
      isFalse,
    );
    expect(
      login.enabledHeaders['Content-Type'],
      'application/x-www-form-urlencoded',
    );
    expect(login.body, 'phone={{PHONE}}&password=p%40ss+word');

    final upload = result.requests.singleWhere(
      (entry) => entry.name == 'Upload',
    );
    expect(upload.bodyMode, ApiToolBodyMode.multipart);
    expect(upload.multipartFields, hasLength(2));
    expect(upload.multipartFields.first.name, 'name');
    expect(upload.multipartFields.first.value, 'Demo');
    final avatar = upload.multipartFields.singleWhere(
      (entry) => entry.name == 'avatar',
    );
    expect(avatar.kind, ApiToolMultipartKind.file);
    expect(avatar.value, 'postman-cloud:///avatar');
    expect(avatar.contentType, 'image/png');
    expect(avatar.enabled, isFalse);

    final health = result.requests.singleWhere(
      (entry) => entry.name == 'Health',
    );
    expect(health.url, 'https://api.example.com/health?status={{STATUS}}');
  });

  test('rejects collections without requests', () {
    final service = ApiToolPostmanCollectionImportService();
    final jsonText = jsonEncode({
      'info': {'name': 'Empty'},
      'item': [
        {'name': 'Folder', 'item': []},
      ],
    });

    expect(
      () => service.importJsonText(jsonText),
      throwsA(isA<ApiToolPostmanImportException>()),
    );
  });
}
