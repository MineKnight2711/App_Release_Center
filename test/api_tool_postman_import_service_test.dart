import 'dart:convert';

import 'package:app_management_center/app/models/api_tool.dart';
import 'package:app_management_center/app/services/api_tool_postman_import_service.dart';
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
                'auth': {
                  'type': 'bearer',
                  'bearer': [
                    {'key': 'token', 'value': '{{ACCESS_TOKEN}}'},
                  ],
                },
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
    expect(login.authorization.type, ApiToolAuthorizationType.bearer);
    expect(login.authorization.token, '{{ACCESS_TOKEN}}');
    expect(login.enabledHeaders['Authorization'], 'Bearer {{ACCESS_TOKEN}}');
    expect(login.bodyMode, ApiToolBodyMode.urlEncoded);
    expect(login.urlEncodedFields, hasLength(3));
    expect(login.urlEncodedFields.first.name, 'phone');
    expect(login.urlEncodedFields.first.value, '{{PHONE}}');
    expect(
      login.urlEncodedFields
          .singleWhere((entry) => entry.name == 'debug')
          .enabled,
      isFalse,
    );

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

  test('imports Postman environment files into collection environments', () {
    final service = ApiToolPostmanEnvironmentImportService(
      now: () => DateTime.utc(2026, 8, 12),
    );
    final jsonText = jsonEncode({
      'id': '3db6569d-c8f1-48ca-b12d-e4fa9af41bee',
      'name': 'VneCheck Ai API',
      'values': [
        {
          'key': 'LINKS',
          'value': '',
          'type': 'default',
          'description': 'Links API',
          'enabled': true,
        },
        {
          'key': 'APP_USER',
          'value': 'demo@example.com',
          'type': 'default',
          'enabled': true,
        },
        {
          'key': 'APP_KEYS',
          'value': 'secret',
          'type': 'default',
          'enabled': false,
        },
      ],
      '_postman_variable_scope': 'environment',
    });

    final environment = service.importJsonText(jsonText);

    expect(environment.name, 'VneCheck Ai API');
    expect(environment.variables, hasLength(3));
    expect(environment.variables[0].name, 'LINKS');
    expect(environment.variables[0].value, '');
    expect(environment.enabledVariables['APP_USER'], 'demo@example.com');
    expect(environment.enabledVariables.containsKey('APP_KEYS'), isFalse);
  });

  test('drops inline values too large for a Firestore document', () {
    final service = ApiToolPostmanCollectionImportService(
      now: () => DateTime.utc(2026, 9, 8),
    );
    final oversized =
        'A' * (ApiToolPostmanCollectionImportService.maxImportedValueBytes + 1);
    final jsonText = jsonEncode({
      'info': {'name': 'Uploads'},
      'item': [
        {
          'name': 'Upload signature',
          'request': {
            'method': 'POST',
            'url': 'https://example.com/upload',
            'body': {
              'mode': 'formdata',
              'formdata': [
                {'key': 'chuky', 'value': oversized, 'type': 'text'},
                {'key': 'chuky', 'src': 'postman-cloud:///abc', 'type': 'file'},
              ],
            },
          },
        },
      ],
    });

    final result = service.importJsonText(jsonText);
    final fields = result.requests.single.multipartFields;

    expect(fields, hasLength(2));
    expect(fields.first.value, isEmpty);
    expect(fields.last.value, 'postman-cloud:///abc');
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single, contains('Upload signature'));
    expect(result.warnings.single, contains('chuky'));
  });

  test('keeps values that fit and reports no warnings', () {
    final service = ApiToolPostmanCollectionImportService(
      now: () => DateTime.utc(2026, 9, 8),
    );
    final body = 'B' * 1024;
    final jsonText = jsonEncode({
      'info': {'name': 'Uploads'},
      'item': [
        {
          'name': 'Create',
          'request': {
            'method': 'POST',
            'url': 'https://example.com/create',
            'body': {'mode': 'raw', 'raw': body},
          },
        },
      ],
    });

    final result = service.importJsonText(jsonText);

    expect(result.requests.single.body, body);
    expect(result.warnings, isEmpty);
  });

  test('rejects Postman environments without variables', () {
    final service = ApiToolPostmanEnvironmentImportService();
    final jsonText = jsonEncode({'name': 'Empty', 'values': []});

    expect(
      () => service.importJsonText(jsonText),
      throwsA(isA<ApiToolPostmanImportException>()),
    );
  });
}
