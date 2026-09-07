import 'dart:convert';

final _apiToolVariablePattern = RegExp(r'\{\{\s*([^{}]+?)\s*\}\}');

enum ApiToolMethod { get, post, put, patch, delete }

enum ApiToolBodyMode { raw, multipart, urlEncoded }

enum ApiToolAuthorizationType { none, bearer, basic, apiKey }

extension ApiToolAuthorizationTypeLabel on ApiToolAuthorizationType {
  String get label {
    return switch (this) {
      ApiToolAuthorizationType.none => 'No Auth',
      ApiToolAuthorizationType.bearer => 'Bearer Token',
      ApiToolAuthorizationType.basic => 'Basic Auth',
      ApiToolAuthorizationType.apiKey => 'API Key',
    };
  }
}

extension ApiToolBodyModeLabel on ApiToolBodyMode {
  String get label {
    return switch (this) {
      ApiToolBodyMode.raw => 'Raw',
      ApiToolBodyMode.multipart => 'form-data',
      ApiToolBodyMode.urlEncoded => 'x-www-form-urlencoded',
    };
  }
}

enum ApiToolMultipartKind { text, file }

extension ApiToolMultipartKindLabel on ApiToolMultipartKind {
  String get label {
    return switch (this) {
      ApiToolMultipartKind.text => 'Text',
      ApiToolMultipartKind.file => 'File',
    };
  }
}

extension ApiToolMethodLabel on ApiToolMethod {
  String get label => name.toUpperCase();

  bool get usuallyHasBody {
    return switch (this) {
      ApiToolMethod.get || ApiToolMethod.delete => false,
      ApiToolMethod.post || ApiToolMethod.put || ApiToolMethod.patch => true,
    };
  }
}

class ApiToolHeader {
  const ApiToolHeader({
    required this.id,
    this.name = '',
    this.value = '',
    this.enabled = true,
  });

  final String id;
  final String name;
  final String value;
  final bool enabled;

  bool get hasName => name.trim().isNotEmpty;

  ApiToolHeader copyWith({
    String? id,
    String? name,
    String? value,
    bool? enabled,
  }) {
    return ApiToolHeader(
      id: id ?? this.id,
      name: name ?? this.name,
      value: value ?? this.value,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toJson() {
    return {'id': id, 'name': name, 'value': value, 'enabled': enabled};
  }

  factory ApiToolHeader.fromJson(Map<String, Object?> json) {
    return ApiToolHeader(
      id: _string(json['id']),
      name: _string(json['name']),
      value: _string(json['value']),
      enabled: json['enabled'] != false,
    );
  }
}

class ApiToolAuthorization {
  const ApiToolAuthorization({
    this.type = ApiToolAuthorizationType.none,
    this.token = '',
    this.username = '',
    this.password = '',
    this.apiKeyName = '',
    this.apiKeyValue = '',
  });

  final ApiToolAuthorizationType type;
  final String token;
  final String username;
  final String password;
  final String apiKeyName;
  final String apiKeyValue;

  MapEntry<String, String>? get header {
    return switch (type) {
      ApiToolAuthorizationType.none => null,
      ApiToolAuthorizationType.bearer =>
        token.trim().isEmpty
            ? null
            : MapEntry('Authorization', 'Bearer $token'),
      ApiToolAuthorizationType.basic =>
        username.isEmpty && password.isEmpty
            ? null
            : MapEntry(
                'Authorization',
                'Basic ${base64Encode(utf8.encode('$username:$password'))}',
              ),
      ApiToolAuthorizationType.apiKey =>
        apiKeyName.trim().isEmpty
            ? null
            : MapEntry(apiKeyName.trim(), apiKeyValue),
    };
  }

  ApiToolAuthorization copyWith({
    ApiToolAuthorizationType? type,
    String? token,
    String? username,
    String? password,
    String? apiKeyName,
    String? apiKeyValue,
  }) {
    return ApiToolAuthorization(
      type: type ?? this.type,
      token: token ?? this.token,
      username: username ?? this.username,
      password: password ?? this.password,
      apiKeyName: apiKeyName ?? this.apiKeyName,
      apiKeyValue: apiKeyValue ?? this.apiKeyValue,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'type': type.name,
      'token': token,
      'username': username,
      'password': password,
      'apiKeyName': apiKeyName,
      'apiKeyValue': apiKeyValue,
    };
  }

  factory ApiToolAuthorization.fromJson(Map<String, Object?> json) {
    return ApiToolAuthorization(
      type: _authorizationTypeFromJson(json['type']),
      token: _string(json['token']),
      username: _string(json['username']),
      password: _string(json['password']),
      apiKeyName: _string(json['apiKeyName']),
      apiKeyValue: _string(json['apiKeyValue']),
    );
  }
}

class ApiToolMultipartEntry {
  const ApiToolMultipartEntry({
    required this.id,
    this.kind = ApiToolMultipartKind.text,
    this.name = '',
    this.value = '',
    this.contentType = '',
    this.enabled = true,
  });

  final String id;
  final ApiToolMultipartKind kind;
  final String name;
  final String value;
  final String contentType;
  final bool enabled;

  bool get hasName => name.trim().isNotEmpty;
  bool get hasValue => value.trim().isNotEmpty;
  bool get isFile => kind == ApiToolMultipartKind.file;

  ApiToolMultipartEntry copyWith({
    String? id,
    ApiToolMultipartKind? kind,
    String? name,
    String? value,
    String? contentType,
    bool? enabled,
  }) {
    return ApiToolMultipartEntry(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      value: value ?? this.value,
      contentType: contentType ?? this.contentType,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'name': name,
      'value': value,
      'contentType': contentType,
      'enabled': enabled,
    };
  }

  factory ApiToolMultipartEntry.fromJson(Map<String, Object?> json) {
    return ApiToolMultipartEntry(
      id: _string(json['id']),
      kind: _multipartKindFromJson(json['kind']),
      name: _string(json['name']),
      value: _string(json['value']),
      contentType: _string(json['contentType']),
      enabled: json['enabled'] != false,
    );
  }
}

class ApiToolEnvironmentVariable {
  const ApiToolEnvironmentVariable({
    required this.id,
    this.name = '',
    this.value = '',
    this.enabled = true,
  });

  final String id;
  final String name;
  final String value;
  final bool enabled;

  bool get hasName => name.trim().isNotEmpty;

  ApiToolEnvironmentVariable copyWith({
    String? id,
    String? name,
    String? value,
    bool? enabled,
  }) {
    return ApiToolEnvironmentVariable(
      id: id ?? this.id,
      name: name ?? this.name,
      value: value ?? this.value,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toJson() {
    return {'id': id, 'name': name, 'value': value, 'enabled': enabled};
  }

  factory ApiToolEnvironmentVariable.fromJson(Map<String, Object?> json) {
    return ApiToolEnvironmentVariable(
      id: _string(json['id']),
      name: _string(json['name']),
      value: _string(json['value']),
      enabled: json['enabled'] != false,
    );
  }
}

class ApiToolEnvironment {
  const ApiToolEnvironment({
    required this.id,
    required this.name,
    this.variables = const [],
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<ApiToolEnvironmentVariable> variables;
  final DateTime updatedAt;

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'Environment' : trimmed;
  }

  Map<String, String> get enabledVariables {
    final mapped = <String, String>{};
    for (final variable in variables) {
      final name = variable.name.trim();
      if (!variable.enabled || name.isEmpty) continue;
      mapped[name] = variable.value;
    }
    return mapped;
  }

  ApiToolEnvironment copyWith({
    String? id,
    String? name,
    List<ApiToolEnvironmentVariable>? variables,
    DateTime? updatedAt,
  }) {
    return ApiToolEnvironment(
      id: id ?? this.id,
      name: name ?? this.name,
      variables: variables ?? this.variables,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'variables': variables.map((entry) => entry.toJson()).toList(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ApiToolEnvironment.fromJson(Map<String, Object?> json) {
    return ApiToolEnvironment(
      id: _string(json['id']),
      name: _string(json['name']),
      variables: _environmentVariableList(json['variables']),
      updatedAt: _date(json['updatedAt']) ?? DateTime.now(),
    );
  }
}

class ApiToolCollectionRoot {
  const ApiToolCollectionRoot({
    required this.id,
    required this.name,
    this.environments = const [],
    this.activeEnvironmentId = '',
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<ApiToolEnvironment> environments;
  final String activeEnvironmentId;
  final DateTime updatedAt;

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'Collection' : trimmed;
  }

  ApiToolEnvironment? get activeEnvironment {
    for (final environment in environments) {
      if (environment.id == activeEnvironmentId) return environment;
    }
    return null;
  }

  Map<String, String> get activeVariables {
    return activeEnvironment?.enabledVariables ?? const {};
  }

  ApiToolCollectionRoot copyWith({
    String? id,
    String? name,
    List<ApiToolEnvironment>? environments,
    String? activeEnvironmentId,
    DateTime? updatedAt,
  }) {
    return ApiToolCollectionRoot(
      id: id ?? this.id,
      name: name ?? this.name,
      environments: environments ?? this.environments,
      activeEnvironmentId: activeEnvironmentId ?? this.activeEnvironmentId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'environments': environments.map((entry) => entry.toJson()).toList(),
      'activeEnvironmentId': activeEnvironmentId,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ApiToolCollectionRoot.fromJson(Map<String, Object?> json) {
    return ApiToolCollectionRoot(
      id: _string(json['id']),
      name: _string(json['name']),
      environments: _environmentList(json['environments']),
      activeEnvironmentId: _string(json['activeEnvironmentId']),
      updatedAt: _date(json['updatedAt']) ?? DateTime.now(),
    );
  }
}

class ApiToolCollectionFolder {
  const ApiToolCollectionFolder({
    required this.id,
    required this.collectionId,
    this.parentFolderId = '',
    required this.name,
    required this.updatedAt,
  });

  final String id;
  final String collectionId;
  final String parentFolderId;
  final String name;
  final DateTime updatedAt;

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'Folder' : trimmed;
  }

  ApiToolCollectionFolder copyWith({
    String? id,
    String? collectionId,
    String? parentFolderId,
    String? name,
    DateTime? updatedAt,
  }) {
    return ApiToolCollectionFolder(
      id: id ?? this.id,
      collectionId: collectionId ?? this.collectionId,
      parentFolderId: parentFolderId ?? this.parentFolderId,
      name: name ?? this.name,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'collectionId': collectionId,
      'parentFolderId': parentFolderId,
      'name': name,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ApiToolCollectionFolder.fromJson(Map<String, Object?> json) {
    return ApiToolCollectionFolder(
      id: _string(json['id']),
      collectionId: _string(json['collectionId']),
      parentFolderId: _string(json['parentFolderId']),
      name: _string(json['name']),
      updatedAt: _date(json['updatedAt']) ?? DateTime.now(),
    );
  }
}

class ApiToolRequest {
  const ApiToolRequest({
    required this.id,
    required this.name,
    required this.method,
    required this.url,
    this.collectionId = '',
    this.folderId = '',
    this.headers = const [],
    this.authorization = const ApiToolAuthorization(),
    this.bodyMode = ApiToolBodyMode.raw,
    this.body = '',
    this.multipartFields = const [],
    this.urlEncodedFields = const [],
    required this.updatedAt,
  });

  final String id;
  final String name;
  final ApiToolMethod method;
  final String url;
  final String collectionId;
  final String folderId;
  final List<ApiToolHeader> headers;
  final ApiToolAuthorization authorization;
  final ApiToolBodyMode bodyMode;
  final String body;
  final List<ApiToolMultipartEntry> multipartFields;
  final List<ApiToolHeader> urlEncodedFields;
  final DateTime updatedAt;

  String get displayName {
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty) return trimmedName;
    final trimmedUrl = url.trim();
    if (trimmedUrl.isNotEmpty) return trimmedUrl;
    return '${method.label} request';
  }

  Map<String, String> get enabledHeaders {
    final mapped = <String, String>{};
    for (final header in headers) {
      final name = header.name.trim();
      if (!header.enabled || name.isEmpty) continue;
      mapped[name] = header.value;
    }
    final authorizationHeader = authorization.header;
    if (authorizationHeader != null) {
      mapped.removeWhere(
        (name, _) =>
            name.toLowerCase() == authorizationHeader.key.toLowerCase(),
      );
      mapped[authorizationHeader.key] = authorizationHeader.value;
    }
    return mapped;
  }

  List<ApiToolMultipartEntry> get enabledMultipartFields {
    return multipartFields
        .where((entry) => entry.enabled && entry.hasName)
        .toList(growable: false);
  }

  List<ApiToolHeader> get enabledUrlEncodedFields {
    return urlEncodedFields
        .where((entry) => entry.enabled && entry.hasName)
        .toList(growable: false);
  }

  ApiToolRequest copyWith({
    String? id,
    String? name,
    ApiToolMethod? method,
    String? url,
    String? collectionId,
    String? folderId,
    List<ApiToolHeader>? headers,
    ApiToolAuthorization? authorization,
    ApiToolBodyMode? bodyMode,
    String? body,
    List<ApiToolMultipartEntry>? multipartFields,
    List<ApiToolHeader>? urlEncodedFields,
    DateTime? updatedAt,
  }) {
    return ApiToolRequest(
      id: id ?? this.id,
      name: name ?? this.name,
      method: method ?? this.method,
      url: url ?? this.url,
      collectionId: collectionId ?? this.collectionId,
      folderId: folderId ?? this.folderId,
      headers: headers ?? this.headers,
      authorization: authorization ?? this.authorization,
      bodyMode: bodyMode ?? this.bodyMode,
      body: body ?? this.body,
      multipartFields: multipartFields ?? this.multipartFields,
      urlEncodedFields: urlEncodedFields ?? this.urlEncodedFields,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'method': method.label,
      'url': url,
      'collectionId': collectionId,
      'folderId': folderId,
      'headers': headers.map((entry) => entry.toJson()).toList(),
      'authorization': authorization.toJson(),
      'bodyMode': bodyMode.name,
      'body': body,
      'multipartFields': multipartFields
          .map((entry) => entry.toJson())
          .toList(),
      'urlEncodedFields': urlEncodedFields
          .map((entry) => entry.toJson())
          .toList(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ApiToolRequest.fromJson(Map<String, Object?> json) {
    return ApiToolRequest(
      id: _string(json['id']),
      name: _string(json['name']),
      method: _methodFromJson(json['method']),
      url: _string(json['url']),
      collectionId: _string(json['collectionId']),
      folderId: _string(json['folderId']),
      headers: _headerList(json['headers']),
      authorization: _authorizationFromJson(json['authorization']),
      bodyMode: _bodyModeFromJson(json['bodyMode']),
      body: _string(json['body']),
      multipartFields: _multipartList(json['multipartFields']),
      urlEncodedFields: _headerList(json['urlEncodedFields']),
      updatedAt: _date(json['updatedAt']) ?? DateTime.now(),
    );
  }
}

class ApiToolQuickRequest {
  const ApiToolQuickRequest({
    required this.id,
    required this.name,
    required this.collectionId,
    required this.request,
    this.requiresConfirmation = false,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String collectionId;
  final ApiToolRequest request;
  final bool requiresConfirmation;
  final DateTime updatedAt;

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? request.displayName : trimmed;
  }

  ApiToolRequest get executableRequest => request.copyWith(
    id: id,
    name: displayName,
    collectionId: collectionId,
    folderId: '',
  );

  ApiToolQuickRequest copyWith({
    String? id,
    String? name,
    String? collectionId,
    ApiToolRequest? request,
    bool? requiresConfirmation,
    DateTime? updatedAt,
  }) {
    return ApiToolQuickRequest(
      id: id ?? this.id,
      name: name ?? this.name,
      collectionId: collectionId ?? this.collectionId,
      request: request ?? this.request,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'collectionId': collectionId,
      'request': request.toJson(),
      'requiresConfirmation': requiresConfirmation,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ApiToolQuickRequest.fromJson(Map<String, Object?> json) {
    final requestJson = json['request'];
    return ApiToolQuickRequest(
      id: _string(json['id']),
      name: _string(json['name']),
      collectionId: _string(json['collectionId']),
      request: requestJson is Map
          ? ApiToolRequest.fromJson(requestJson.cast<String, Object?>())
          : ApiToolRequest(
              id: '',
              name: '',
              method: ApiToolMethod.get,
              url: '',
              updatedAt: DateTime.now(),
            ),
      requiresConfirmation: json['requiresConfirmation'] == true,
      updatedAt: _date(json['updatedAt']) ?? DateTime.now(),
    );
  }
}

class ApiToolHistoryEntry {
  const ApiToolHistoryEntry({
    required this.id,
    required this.request,
    this.statusCode,
    this.durationMs,
    required this.sentAt,
    this.error = '',
  });

  final String id;
  final ApiToolRequest request;
  final int? statusCode;
  final int? durationMs;
  final DateTime sentAt;
  final String error;

  bool get isSuccess {
    final code = statusCode;
    return error.trim().isEmpty && code != null && code >= 200 && code < 300;
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'request': request.toJson(),
      'statusCode': statusCode,
      'durationMs': durationMs,
      'sentAt': sentAt.toUtc().toIso8601String(),
      'error': error,
    };
  }

  factory ApiToolHistoryEntry.fromJson(Map<String, Object?> json) {
    final requestJson = json['request'];
    return ApiToolHistoryEntry(
      id: _string(json['id']),
      request: requestJson is Map
          ? ApiToolRequest.fromJson(requestJson.cast<String, Object?>())
          : ApiToolRequest(
              id: '',
              name: '',
              method: ApiToolMethod.get,
              url: '',
              updatedAt: DateTime.now(),
            ),
      statusCode: _int(json['statusCode']),
      durationMs: _int(json['durationMs']),
      sentAt: _date(json['sentAt']) ?? DateTime.now(),
      error: _string(json['error']),
    );
  }
}

class ApiToolResponse {
  const ApiToolResponse({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.body,
    required this.bodyTruncated,
    required this.durationMs,
  });

  final int statusCode;
  final String reasonPhrase;
  final Map<String, List<String>> headers;
  final String body;
  final bool bodyTruncated;
  final int durationMs;

  bool get isOk => statusCode >= 200 && statusCode < 300;
}

String prettyPrintJsonText(String rawBody) {
  final trimmed = rawBody.trim();
  if (trimmed.isEmpty) return rawBody;

  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(trimmed));
  } on FormatException {
    return rawBody;
  }
}

ApiToolRequest resolveApiToolRequestVariables(
  ApiToolRequest request,
  Map<String, String> variables,
) {
  if (variables.isEmpty) return request;

  return request.copyWith(
    url: _resolveVariables(request.url, variables),
    headers: request.headers
        .map(
          (header) => header.copyWith(
            name: _resolveVariables(header.name, variables),
            value: _resolveVariables(header.value, variables),
          ),
        )
        .toList(growable: false),
    authorization: request.authorization.copyWith(
      token: _resolveVariables(request.authorization.token, variables),
      username: _resolveVariables(request.authorization.username, variables),
      password: _resolveVariables(request.authorization.password, variables),
      apiKeyName: _resolveVariables(
        request.authorization.apiKeyName,
        variables,
      ),
      apiKeyValue: _resolveVariables(
        request.authorization.apiKeyValue,
        variables,
      ),
    ),
    body: _resolveVariables(request.body, variables),
    multipartFields: request.multipartFields
        .map(
          (field) => field.copyWith(
            name: _resolveVariables(field.name, variables),
            value: _resolveVariables(field.value, variables),
            contentType: _resolveVariables(field.contentType, variables),
          ),
        )
        .toList(growable: false),
    urlEncodedFields: request.urlEncodedFields
        .map(
          (field) => field.copyWith(
            name: _resolveVariables(field.name, variables),
            value: _resolveVariables(field.value, variables),
          ),
        )
        .toList(growable: false),
  );
}

String _resolveVariables(String input, Map<String, String> variables) {
  if (input.isEmpty || variables.isEmpty) return input;
  return input.replaceAllMapped(_apiToolVariablePattern, (match) {
    final key = match.group(1)?.trim() ?? '';
    return variables.containsKey(key) ? variables[key]! : match.group(0)!;
  });
}

ApiToolMethod _methodFromJson(Object? value) {
  final raw = value?.toString().trim().toLowerCase() ?? '';
  for (final method in ApiToolMethod.values) {
    if (method.name == raw || method.label.toLowerCase() == raw) {
      return method;
    }
  }
  return ApiToolMethod.get;
}

ApiToolBodyMode _bodyModeFromJson(Object? value) {
  final raw = value?.toString().trim().toLowerCase() ?? '';
  for (final mode in ApiToolBodyMode.values) {
    if (mode.name == raw || mode.label.toLowerCase() == raw) {
      return mode;
    }
  }
  return ApiToolBodyMode.raw;
}

ApiToolAuthorizationType _authorizationTypeFromJson(Object? value) {
  final raw = value?.toString().trim().toLowerCase() ?? '';
  for (final type in ApiToolAuthorizationType.values) {
    if (type.name.toLowerCase() == raw || type.label.toLowerCase() == raw) {
      return type;
    }
  }
  return ApiToolAuthorizationType.none;
}

ApiToolAuthorization _authorizationFromJson(Object? value) {
  if (value is! Map) return const ApiToolAuthorization();
  return ApiToolAuthorization.fromJson(value.cast<String, Object?>());
}

ApiToolMultipartKind _multipartKindFromJson(Object? value) {
  final raw = value?.toString().trim().toLowerCase() ?? '';
  for (final kind in ApiToolMultipartKind.values) {
    if (kind.name == raw || kind.label.toLowerCase() == raw) {
      return kind;
    }
  }
  return ApiToolMultipartKind.text;
}

List<ApiToolHeader> _headerList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) => ApiToolHeader.fromJson(entry.cast<String, Object?>()))
      .where((entry) => entry.id.isNotEmpty || entry.hasName)
      .toList(growable: false);
}

List<ApiToolMultipartEntry> _multipartList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (entry) =>
            ApiToolMultipartEntry.fromJson(entry.cast<String, Object?>()),
      )
      .where((entry) => entry.id.isNotEmpty || entry.hasName || entry.hasValue)
      .toList(growable: false);
}

List<ApiToolEnvironment> _environmentList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (entry) => ApiToolEnvironment.fromJson(entry.cast<String, Object?>()),
      )
      .where((entry) => entry.id.isNotEmpty)
      .toList(growable: false);
}

List<ApiToolEnvironmentVariable> _environmentVariableList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (entry) =>
            ApiToolEnvironmentVariable.fromJson(entry.cast<String, Object?>()),
      )
      .where((entry) => entry.id.isNotEmpty || entry.hasName)
      .toList(growable: false);
}

String _string(Object? value) => value?.toString() ?? '';

int? _int(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _date(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}
