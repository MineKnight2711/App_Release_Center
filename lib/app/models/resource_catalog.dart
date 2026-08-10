enum ResourceCatalogKind {
  summaryLink,
  googleSheet,
  driveFolder,
  driveFile,
  resourceDocument,
  figma,
  playConsole,
  appStoreConnect,
  firebase,
  cicd,
  repository,
  backendAdmin,
  apiDocs,
  analyticsCrash,
  authProvider,
  payment,
  deepLinkDomain,
  signingCertificate,
  qaDevice,
  testAccount,
  legal,
  releaseRunbook,
  other,
}

class ResourceCatalogBundle {
  const ResourceCatalogBundle({
    required this.projectPath,
    this.resources = const [],
    this.passwords = const [],
  });

  final String projectPath;
  final List<ResourceCatalogItem> resources;
  final List<ResourcePasswordEntry> passwords;

  bool get isEmpty => resources.isEmpty && passwords.isEmpty;

  ResourceCatalogBundle copyWith({
    String? projectPath,
    List<ResourceCatalogItem>? resources,
    List<ResourcePasswordEntry>? passwords,
  }) {
    return ResourceCatalogBundle(
      projectPath: projectPath ?? this.projectPath,
      resources: resources ?? this.resources,
      passwords: passwords ?? this.passwords,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'projectPath': projectPath,
      'resources': resources.map((entry) => entry.toJson()).toList(),
      'passwords': passwords.map((entry) => entry.toJson()).toList(),
    };
  }

  factory ResourceCatalogBundle.fromJson(Map<String, Object?> json) {
    return ResourceCatalogBundle(
      projectPath: json['projectPath']?.toString() ?? '',
      resources: _resourceList(json['resources']),
      passwords: _passwordList(json['passwords']),
    );
  }
}

class ResourceCatalogItem {
  const ResourceCatalogItem({
    required this.id,
    required this.kind,
    required this.title,
    this.url = '',
    this.localPath = '',
    this.environment = '',
    this.owner = '',
    this.notes = '',
    this.tags = const [],
    required this.updatedAt,
  });

  final String id;
  final ResourceCatalogKind kind;
  final String title;
  final String url;
  final String localPath;
  final String environment;
  final String owner;
  final String notes;
  final List<String> tags;
  final DateTime updatedAt;

  bool get hasUrl => url.trim().isNotEmpty;
  bool get hasLocalPath => localPath.trim().isNotEmpty;

  ResourceCatalogItem copyWith({
    String? id,
    ResourceCatalogKind? kind,
    String? title,
    String? url,
    String? localPath,
    String? environment,
    String? owner,
    String? notes,
    List<String>? tags,
    DateTime? updatedAt,
  }) {
    return ResourceCatalogItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      url: url ?? this.url,
      localPath: localPath ?? this.localPath,
      environment: environment ?? this.environment,
      owner: owner ?? this.owner,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'title': title,
      'url': url,
      'localPath': localPath,
      'environment': environment,
      'owner': owner,
      'notes': notes,
      'tags': tags,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ResourceCatalogItem.fromJson(Map<String, Object?> json) {
    return ResourceCatalogItem(
      id: json['id']?.toString() ?? '',
      kind: _enumByName(
        ResourceCatalogKind.values,
        json['kind'],
        ResourceCatalogKind.other,
      ),
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      localPath: json['localPath']?.toString() ?? '',
      environment: json['environment']?.toString() ?? '',
      owner: json['owner']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      tags: _stringList(json['tags']),
      updatedAt: _dateTimeOrNow(json['updatedAt']),
    );
  }
}

class ResourcePasswordEntry {
  const ResourcePasswordEntry({
    required this.id,
    required this.secretKey,
    required this.site,
    this.loginUrl = '',
    this.username = '',
    this.environment = '',
    this.owner = '',
    this.twoFactorLocation = '',
    this.notes = '',
    this.tags = const [],
    required this.updatedAt,
  });

  final String id;
  final String secretKey;
  final String site;
  final String loginUrl;
  final String username;
  final String environment;
  final String owner;
  final String twoFactorLocation;
  final String notes;
  final List<String> tags;
  final DateTime updatedAt;

  bool get hasLoginUrl => loginUrl.trim().isNotEmpty;

  ResourcePasswordEntry copyWith({
    String? id,
    String? secretKey,
    String? site,
    String? loginUrl,
    String? username,
    String? environment,
    String? owner,
    String? twoFactorLocation,
    String? notes,
    List<String>? tags,
    DateTime? updatedAt,
  }) {
    return ResourcePasswordEntry(
      id: id ?? this.id,
      secretKey: secretKey ?? this.secretKey,
      site: site ?? this.site,
      loginUrl: loginUrl ?? this.loginUrl,
      username: username ?? this.username,
      environment: environment ?? this.environment,
      owner: owner ?? this.owner,
      twoFactorLocation: twoFactorLocation ?? this.twoFactorLocation,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'secretKey': secretKey,
      'site': site,
      'loginUrl': loginUrl,
      'username': username,
      'environment': environment,
      'owner': owner,
      'twoFactorLocation': twoFactorLocation,
      'notes': notes,
      'tags': tags,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ResourcePasswordEntry.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString() ?? '';
    final secretKey = json['secretKey']?.toString() ?? id;
    return ResourcePasswordEntry(
      id: id,
      secretKey: secretKey,
      site: json['site']?.toString() ?? '',
      loginUrl: json['loginUrl']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      environment: json['environment']?.toString() ?? '',
      owner: json['owner']?.toString() ?? '',
      twoFactorLocation: json['twoFactorLocation']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      tags: _stringList(json['tags']),
      updatedAt: _dateTimeOrNow(json['updatedAt']),
    );
  }
}

extension ResourceCatalogKindText on ResourceCatalogKind {
  String get label {
    return switch (this) {
      ResourceCatalogKind.summaryLink => 'Summary link',
      ResourceCatalogKind.googleSheet => 'Google Sheet',
      ResourceCatalogKind.driveFolder => 'Drive folder',
      ResourceCatalogKind.driveFile => 'Drive file',
      ResourceCatalogKind.resourceDocument => 'Resource',
      ResourceCatalogKind.figma => 'Figma',
      ResourceCatalogKind.playConsole => 'CH Play console',
      ResourceCatalogKind.appStoreConnect => 'App Store Connect',
      ResourceCatalogKind.firebase => 'Firebase',
      ResourceCatalogKind.cicd => 'CI/CD',
      ResourceCatalogKind.repository => 'Repository',
      ResourceCatalogKind.backendAdmin => 'Backend admin',
      ResourceCatalogKind.apiDocs => 'API docs',
      ResourceCatalogKind.analyticsCrash => 'Analytics/crash',
      ResourceCatalogKind.authProvider => 'Auth provider',
      ResourceCatalogKind.payment => 'Payment',
      ResourceCatalogKind.deepLinkDomain => 'Deep link/domain',
      ResourceCatalogKind.signingCertificate => 'Signing/cert',
      ResourceCatalogKind.qaDevice => 'QA device',
      ResourceCatalogKind.testAccount => 'Test account',
      ResourceCatalogKind.legal => 'Legal',
      ResourceCatalogKind.releaseRunbook => 'Release runbook',
      ResourceCatalogKind.other => 'Other',
    };
  }
}

List<ResourceCatalogItem> _resourceList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (entry) => ResourceCatalogItem.fromJson(entry.cast<String, Object?>()),
      )
      .where((entry) => entry.id.isNotEmpty)
      .toList();
}

List<ResourcePasswordEntry> _passwordList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (entry) =>
            ResourcePasswordEntry.fromJson(entry.cast<String, Object?>()),
      )
      .where((entry) => entry.id.isNotEmpty && entry.secretKey.isNotEmpty)
      .toList();
}

T _enumByName<T extends Enum>(List<T> values, Object? value, T fallback) {
  final name = value?.toString();
  for (final entry in values) {
    if (entry.name == name) return entry;
  }
  return fallback;
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }
  final text = value?.toString() ?? '';
  if (text.trim().isEmpty) return const [];
  return text
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
}

DateTime _dateTimeOrNow(Object? value) {
  final text = value?.toString();
  if (text == null || text.trim().isEmpty) return DateTime.now().toUtc();
  return DateTime.tryParse(text)?.toUtc() ?? DateTime.now().toUtc();
}
