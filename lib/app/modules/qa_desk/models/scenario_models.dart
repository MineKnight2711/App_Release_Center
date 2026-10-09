import 'dart:convert';

import 'automation_models.dart';

class TestScenario {
  const TestScenario({
    required this.id,
    required this.title,
    required this.module,
    required this.suiteId,
    this.preconditions = const [],
    this.steps = const [],
    this.expectedResult = '',
    this.tags = const [],
    this.enabled = true,
    this.automation,
  });

  final String id;
  final String title;
  final String module;
  final String suiteId;
  final List<String> preconditions;
  final List<String> steps;
  final String expectedResult;
  final List<String> tags;
  final bool enabled;

  /// Set when QA Desk operates the app itself instead of running [suiteId].
  final AutomationSpec? automation;

  bool get isAutomated => automation != null;

  TestScenario copyWith({
    String? id,
    String? title,
    String? module,
    String? suiteId,
    List<String>? preconditions,
    List<String>? steps,
    String? expectedResult,
    List<String>? tags,
    bool? enabled,
    AutomationSpec? automation,
  }) {
    return TestScenario(
      id: id ?? this.id,
      title: title ?? this.title,
      module: module ?? this.module,
      suiteId: suiteId ?? this.suiteId,
      preconditions: preconditions ?? this.preconditions,
      steps: steps ?? this.steps,
      expectedResult: expectedResult ?? this.expectedResult,
      tags: tags ?? this.tags,
      enabled: enabled ?? this.enabled,
      automation: automation ?? this.automation,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'module': module,
    'suiteId': suiteId,
    'preconditions': preconditions,
    'steps': steps,
    'expectedResult': expectedResult,
    'tags': tags,
    'enabled': enabled,
    if (automation != null) 'automation': automation!.toJson(),
  };

  factory TestScenario.fromJson(Map<String, dynamic> json) => TestScenario(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    module: json['module']?.toString() ?? 'General',
    suiteId: json['suiteId']?.toString() ?? '',
    preconditions: _stringList(json['preconditions']),
    steps: _stringList(json['steps']),
    expectedResult: json['expectedResult']?.toString() ?? '',
    tags: _stringList(json['tags']),
    enabled: json['enabled'] as bool? ?? true,
    automation: json['automation'] is Map
        ? AutomationSpec.fromJson(
            Map<String, dynamic>.from(json['automation'] as Map),
          )
        : null,
  );
}

class EnvironmentProfile {
  const EnvironmentProfile({
    required this.id,
    required this.name,
    this.variables = const {},
    this.secretKeys = const [],
  });

  final String id;
  final String name;
  final Map<String, String> variables;
  final List<String> secretKeys;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'variables': variables,
    'secretKeys': secretKeys,
  };

  factory EnvironmentProfile.fromJson(Map<String, dynamic> json) {
    final rawVariables = Map<String, dynamic>.from(
      json['variables'] as Map? ?? const {},
    );
    return EnvironmentProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      variables: rawVariables.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      secretKeys: _stringList(json['secretKeys']),
    );
  }
}

class SourceScenarioCatalog {
  const SourceScenarioCatalog({
    required this.sourceId,
    this.scenarios = const [],
    this.environments = const [],
  });

  final String sourceId;
  final List<TestScenario> scenarios;
  final List<EnvironmentProfile> environments;

  SourceScenarioCatalog copyWith({
    List<TestScenario>? scenarios,
    List<EnvironmentProfile>? environments,
  }) {
    return SourceScenarioCatalog(
      sourceId: sourceId,
      scenarios: scenarios ?? this.scenarios,
      environments: environments ?? this.environments,
    );
  }

  Map<String, dynamic> toJson() => {
    // 2 adds automated scenarios; version 1 catalogs still read as before.
    'schemaVersion': scenarios.any((item) => item.isAutomated) ? 2 : 1,
    'sourceId': sourceId,
    'scenarios': scenarios.map((item) => item.toJson()).toList(),
    'environments': environments.map((item) => item.toJson()).toList(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory SourceScenarioCatalog.fromJson(Map<String, dynamic> json) {
    return SourceScenarioCatalog(
      sourceId: json['sourceId']?.toString() ?? '',
      scenarios: (json['scenarios'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                TestScenario.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
      environments: (json['environments'] as List<dynamic>? ?? const [])
          .map(
            (item) => EnvironmentProfile.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

List<String> _stringList(dynamic value) => (value as List<dynamic>? ?? const [])
    .map((item) => item.toString())
    .toList(growable: false);
