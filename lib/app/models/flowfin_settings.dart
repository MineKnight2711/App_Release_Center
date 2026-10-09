/// Which FlowFin deployment the module talks to.
///
/// The desktop app calls the FlowFin Worker directly. Nothing here routes
/// through App Management Center's own Firebase project or its notification
/// relay, so the module adds no load to that backend.
enum FlowFinEnvironment { local, staging, production }

extension FlowFinEnvironmentMeta on FlowFinEnvironment {
  String get id {
    return switch (this) {
      FlowFinEnvironment.local => 'local',
      FlowFinEnvironment.staging => 'staging',
      FlowFinEnvironment.production => 'production',
    };
  }

  String get label {
    return switch (this) {
      FlowFinEnvironment.local => 'Local',
      FlowFinEnvironment.staging => 'Staging',
      FlowFinEnvironment.production => 'Production',
    };
  }

  /// `wrangler dev` serves the local Worker on 127.0.0.1:8787.
  String get defaultBaseUrl {
    return switch (this) {
      FlowFinEnvironment.local => 'http://127.0.0.1:8787/v1',
      FlowFinEnvironment.staging =>
        'https://qlct-api-staging.huynhphuocdat2.workers.dev/v1',
      FlowFinEnvironment.production =>
        'https://qlct-api.huynhphuocdat2.workers.dev/v1',
    };
  }

  bool get isProduction => this == FlowFinEnvironment.production;

  /// Production is the default because that is where the real money data
  /// lives; staging is close to empty, so defaulting there shows figures that
  /// look real and are not. Reads are safe — the module only reads today — and
  /// writes must ask for confirmation on production, the way release does.
  static const defaultEnvironment = FlowFinEnvironment.production;

  static FlowFinEnvironment fromId(String? id) {
    return switch (id?.trim()) {
      'local' => FlowFinEnvironment.local,
      'staging' => FlowFinEnvironment.staging,
      'production' => FlowFinEnvironment.production,
      // Unreadable settings land on the same default as a fresh install
      // rather than on a dead localhost URL.
      _ => defaultEnvironment,
    };
  }
}

class FlowFinSettings {
  const FlowFinSettings({
    this.environment = FlowFinEnvironmentMeta.defaultEnvironment,
    this.baseUrlOverrides = const {},
  });

  final FlowFinEnvironment environment;

  /// Per-environment base URL overrides, keyed by [FlowFinEnvironmentMeta.id].
  /// Absent or blank entries fall back to [FlowFinEnvironmentMeta.defaultBaseUrl].
  final Map<String, String> baseUrlOverrides;

  String get baseUrl => baseUrlFor(environment);

  String baseUrlFor(FlowFinEnvironment target) {
    final override = baseUrlOverrides[target.id]?.trim();
    if (override == null || override.isEmpty) return target.defaultBaseUrl;
    return _stripTrailingSlash(override);
  }

  FlowFinSettings copyWith({
    FlowFinEnvironment? environment,
    Map<String, String>? baseUrlOverrides,
  }) {
    return FlowFinSettings(
      environment: environment ?? this.environment,
      baseUrlOverrides: baseUrlOverrides ?? this.baseUrlOverrides,
    );
  }

  FlowFinSettings withBaseUrl(FlowFinEnvironment target, String? baseUrl) {
    final next = Map<String, String>.from(baseUrlOverrides);
    final trimmed = baseUrl?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      next.remove(target.id);
    } else {
      next[target.id] = _stripTrailingSlash(trimmed);
    }
    return copyWith(baseUrlOverrides: next);
  }

  Map<String, Object?> toJson() {
    return {'environment': environment.id, 'baseUrlOverrides': baseUrlOverrides};
  }

  factory FlowFinSettings.fromJson(Map<String, Object?> json) {
    final rawOverrides = json['baseUrlOverrides'];
    final overrides = <String, String>{};
    if (rawOverrides is Map) {
      for (final entry in rawOverrides.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is String && value.trim().isNotEmpty) {
          overrides[key] = value.trim();
        }
      }
    }

    return FlowFinSettings(
      environment: FlowFinEnvironmentMeta.fromId(json['environment'] as String?),
      baseUrlOverrides: overrides,
    );
  }

  static String _stripTrailingSlash(String value) {
    var result = value;
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
