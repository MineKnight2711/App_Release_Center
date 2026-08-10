import 'dart:convert';
import 'dart:io';

import 'package:app_release_center/app/models/api_tool.dart';
import 'package:path/path.dart' as p;

class ApiToolPostmanImportException implements Exception {
  const ApiToolPostmanImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiToolPostmanImportResult {
  const ApiToolPostmanImportResult({
    required this.collection,
    this.folders = const [],
    this.requests = const [],
  });

  final ApiToolCollectionRoot collection;
  final List<ApiToolCollectionFolder> folders;
  final List<ApiToolRequest> requests;

  int get folderCount => folders.length;
  int get requestCount => requests.length;
}

class ApiToolPostmanCollectionImportService {
  ApiToolPostmanCollectionImportService({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  var _serial = 0;

  Future<ApiToolPostmanImportResult> importFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw ApiToolPostmanImportException(
        'Postman collection file was not found.',
      );
    }
    final text = await file.readAsString();
    return importJsonText(
      text,
      fallbackName: p.basenameWithoutExtension(file.path),
    );
  }

  ApiToolPostmanImportResult importJsonText(
    String text, {
    String fallbackName = '',
  }) {
    final decoded = _decodeCollection(text);
    final info = _map(decoded['info']);
    final collectionName = _firstNonEmpty([
      _string(info['name']),
      fallbackName,
      'Imported Postman Collection',
    ]);
    final collectionId = _newId('api_collection');
    final now = _now();
    final environments = _importVariables(decoded['variable']);
    final collection = ApiToolCollectionRoot(
      id: collectionId,
      name: collectionName,
      environments: environments,
      activeEnvironmentId: environments.isEmpty ? '' : environments.first.id,
      updatedAt: now,
    );
    final folders = <ApiToolCollectionFolder>[];
    final requests = <ApiToolRequest>[];

    _walkItems(
      decoded['item'],
      collectionId: collectionId,
      parentFolderId: '',
      folders: folders,
      requests: requests,
    );

    if (requests.isEmpty) {
      throw const ApiToolPostmanImportException(
        'No requests were found in this Postman collection.',
      );
    }

    return ApiToolPostmanImportResult(
      collection: collection,
      folders: folders,
      requests: requests,
    );
  }

  Map<String, Object?> _decodeCollection(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return decoded.cast<String, Object?>();
    } on FormatException catch (error) {
      throw ApiToolPostmanImportException(
        'Postman collection JSON is invalid: ${error.message}',
      );
    }
    throw const ApiToolPostmanImportException(
      'Postman collection must be a JSON object.',
    );
  }

  void _walkItems(
    Object? rawItems, {
    required String collectionId,
    required String parentFolderId,
    required List<ApiToolCollectionFolder> folders,
    required List<ApiToolRequest> requests,
  }) {
    for (final rawItem in _list(rawItems)) {
      final item = _map(rawItem);
      if (item.isEmpty) continue;

      final request = _mapOrNull(item['request']);
      if (request != null) {
        requests.add(
          _importRequest(
            item,
            request,
            collectionId: collectionId,
            folderId: parentFolderId,
          ),
        );
      }

      final children = _list(item['item']);
      if (children.isEmpty) continue;

      final folder = ApiToolCollectionFolder(
        id: _newId('api_folder'),
        collectionId: collectionId,
        parentFolderId: parentFolderId,
        name: _firstNonEmpty([_string(item['name']), 'Folder']),
        updatedAt: _now(),
      );
      folders.add(folder);
      _walkItems(
        children,
        collectionId: collectionId,
        parentFolderId: folder.id,
        folders: folders,
        requests: requests,
      );
    }
  }

  ApiToolRequest _importRequest(
    Map<String, Object?> item,
    Map<String, Object?> request, {
    required String collectionId,
    required String folderId,
  }) {
    final headers = _importHeaders(request['header']).toList();
    final body = _importBody(request['body'], headers);
    final method = _methodFromPostman(request['method']);
    final url = _urlFromPostman(request['url']);
    final now = _now();

    return ApiToolRequest(
      id: _newId('api_request'),
      name: _firstNonEmpty([_string(item['name']), '${method.label} request']),
      method: method,
      url: url,
      collectionId: collectionId,
      folderId: folderId,
      headers: headers,
      bodyMode: body.mode,
      body: body.rawBody,
      multipartFields: body.multipartFields,
      updatedAt: now,
    );
  }

  List<ApiToolEnvironment> _importVariables(Object? rawVariables) {
    final variables = <ApiToolEnvironmentVariable>[];
    for (final rawVariable in _list(rawVariables)) {
      final variable = _map(rawVariable);
      final name = _firstNonEmpty([
        _string(variable['key']),
        _string(variable['name']),
      ]);
      if (name.isEmpty) continue;
      variables.add(
        ApiToolEnvironmentVariable(
          id: _newId('api_env_var'),
          name: name,
          value: _string(variable['value']),
          enabled: !_isDisabled(variable),
        ),
      );
    }
    if (variables.isEmpty) return const [];

    return [
      ApiToolEnvironment(
        id: _newId('api_env'),
        name: 'Postman Variables',
        variables: variables,
        updatedAt: _now(),
      ),
    ];
  }

  Iterable<ApiToolHeader> _importHeaders(Object? rawHeaders) sync* {
    for (final rawHeader in _list(rawHeaders)) {
      final header = _map(rawHeader);
      final name = _firstNonEmpty([
        _string(header['key']),
        _string(header['name']),
      ]);
      final value = _string(header['value']);
      if (name.isEmpty && value.isEmpty) continue;
      yield ApiToolHeader(
        id: _newId('api_header'),
        name: name,
        value: value,
        enabled: !_isDisabled(header),
      );
    }
  }

  _ImportedPostmanBody _importBody(
    Object? rawBody,
    List<ApiToolHeader> headers,
  ) {
    final body = _mapOrNull(rawBody);
    if (body == null) return const _ImportedPostmanBody();

    final mode = _string(body['mode']).trim().toLowerCase();
    return switch (mode) {
      'formdata' => _importFormDataBody(body),
      'urlencoded' => _importUrlEncodedBody(body, headers),
      'raw' => _importRawBody(body, headers),
      'graphql' => _importGraphqlBody(body, headers),
      _ => const _ImportedPostmanBody(),
    };
  }

  _ImportedPostmanBody _importFormDataBody(Map<String, Object?> body) {
    final fields = <ApiToolMultipartEntry>[];
    for (final rawField in _list(body['formdata'])) {
      final field = _map(rawField);
      final name = _firstNonEmpty([
        _string(field['key']),
        _string(field['name']),
      ]);
      final value = _firstNonEmpty([
        _stringOrFirst(field['src']),
        _string(field['value']),
      ]);
      if (name.isEmpty && value.isEmpty) continue;
      final type = _string(field['type']).trim().toLowerCase();
      fields.add(
        ApiToolMultipartEntry(
          id: _newId('api_part'),
          kind: type == 'file'
              ? ApiToolMultipartKind.file
              : ApiToolMultipartKind.text,
          name: name,
          value: value,
          contentType: _string(field['contentType']),
          enabled: !_isDisabled(field),
        ),
      );
    }

    return _ImportedPostmanBody(
      mode: ApiToolBodyMode.multipart,
      multipartFields: fields,
    );
  }

  _ImportedPostmanBody _importUrlEncodedBody(
    Map<String, Object?> body,
    List<ApiToolHeader> headers,
  ) {
    final fields = <String>[];
    for (final rawField in _list(body['urlencoded'])) {
      final field = _map(rawField);
      if (_isDisabled(field)) continue;
      final name = _firstNonEmpty([
        _string(field['key']),
        _string(field['name']),
      ]);
      if (name.isEmpty) continue;
      final value = _string(field['value']);
      fields.add(
        '${_encodeFormComponent(name)}=${_encodeFormComponent(value)}',
      );
    }
    _ensureContentType(headers, 'application/x-www-form-urlencoded');

    return _ImportedPostmanBody(rawBody: fields.join('&'));
  }

  _ImportedPostmanBody _importRawBody(
    Map<String, Object?> body,
    List<ApiToolHeader> headers,
  ) {
    final raw = _string(body['raw']);
    final options = _map(_map(body['options'])['raw']);
    final language = _string(options['language']).trim().toLowerCase();
    if (language == 'json') {
      _ensureContentType(headers, 'application/json');
    }
    return _ImportedPostmanBody(rawBody: raw);
  }

  _ImportedPostmanBody _importGraphqlBody(
    Map<String, Object?> body,
    List<ApiToolHeader> headers,
  ) {
    final graphql = _map(body['graphql']);
    final query = _string(graphql['query']);
    final variables = _string(graphql['variables']);
    _ensureContentType(headers, 'application/json');

    return _ImportedPostmanBody(
      rawBody: const JsonEncoder.withIndent('  ').convert({
        'query': query,
        if (variables.trim().isNotEmpty) 'variables': variables,
      }),
    );
  }

  void _ensureContentType(List<ApiToolHeader> headers, String value) {
    final hasContentType = headers.any(
      (header) =>
          header.enabled && header.name.trim().toLowerCase() == 'content-type',
    );
    if (hasContentType) return;
    headers.add(
      ApiToolHeader(
        id: _newId('api_header'),
        name: 'Content-Type',
        value: value,
      ),
    );
  }

  ApiToolMethod _methodFromPostman(Object? value) {
    final raw = _string(value).trim().toLowerCase();
    for (final method in ApiToolMethod.values) {
      if (method.name == raw || method.label.toLowerCase() == raw) {
        return method;
      }
    }
    return ApiToolMethod.get;
  }

  String _urlFromPostman(Object? rawUrl) {
    if (rawUrl is String) return rawUrl;
    final url = _mapOrNull(rawUrl);
    if (url == null) return '';

    final raw = _string(url['raw']);
    if (raw.trim().isNotEmpty) return raw;

    final protocol = _string(url['protocol']).trim();
    final host = _joinUrlParts(url['host'], '.');
    final path = _joinUrlParts(url['path'], '/');
    final query = _queryString(url['query']);
    final buffer = StringBuffer();
    if (protocol.isNotEmpty && !host.contains('://')) {
      buffer.write('$protocol://');
    }
    buffer.write(host);
    if (path.isNotEmpty) {
      if (buffer.isNotEmpty && !buffer.toString().endsWith('/')) {
        buffer.write('/');
      }
      buffer.write(path);
    }
    if (query.isNotEmpty) buffer.write('?$query');
    return buffer.toString();
  }

  String _joinUrlParts(Object? value, String separator) {
    if (value is String) return value.trim();
    return _list(value)
        .map(_string)
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .map((entry) {
          if (separator == '/') {
            return entry.replaceAll(RegExp(r'^/+|/+$'), '');
          }
          return entry;
        })
        .join(separator);
  }

  String _queryString(Object? rawQuery) {
    final parts = <String>[];
    for (final rawPart in _list(rawQuery)) {
      final part = _map(rawPart);
      if (_isDisabled(part)) continue;
      final name = _string(part['key']);
      if (name.isEmpty) continue;
      final value = _string(part['value']);
      parts.add('${_encodeFormComponent(name)}=${_encodeFormComponent(value)}');
    }
    return parts.join('&');
  }

  String _encodeFormComponent(String value) {
    if (value.isEmpty) return value;
    final placeholders = <String, String>{};
    var index = 0;
    final masked = value.replaceAllMapped(RegExp(r'\{\{\s*[^{}]+?\s*\}\}'), (
      match,
    ) {
      final key = '\u0000POSTMAN_VAR_${index++}\u0000';
      placeholders[key] = match.group(0)!;
      return key;
    });
    var encoded = Uri.encodeQueryComponent(masked);
    for (final entry in placeholders.entries) {
      encoded = encoded.replaceAll(
        Uri.encodeQueryComponent(entry.key),
        entry.value,
      );
    }
    return encoded;
  }

  bool _isDisabled(Map<String, Object?> json) {
    final raw = json['disabled'];
    if (raw is bool) return raw;
    return raw?.toString().trim().toLowerCase() == 'true';
  }

  Map<String, Object?> _map(Object? value) {
    if (value is Map) return value.cast<String, Object?>();
    return const {};
  }

  Map<String, Object?>? _mapOrNull(Object? value) {
    if (value is Map) return value.cast<String, Object?>();
    return null;
  }

  List<Object?> _list(Object? value) {
    if (value is List) return value;
    return const [];
  }

  String _firstNonEmpty(Iterable<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  String _stringOrFirst(Object? value) {
    if (value is List && value.isNotEmpty) return _string(value.first);
    return _string(value);
  }

  String _string(Object? value) => value?.toString() ?? '';

  String _newId(String prefix) {
    _serial += 1;
    return '${prefix}_${_now().microsecondsSinceEpoch}_$_serial';
  }
}

class _ImportedPostmanBody {
  const _ImportedPostmanBody({
    this.mode = ApiToolBodyMode.raw,
    this.rawBody = '',
    this.multipartFields = const [],
  });

  final ApiToolBodyMode mode;
  final String rawBody;
  final List<ApiToolMultipartEntry> multipartFields;
}
