import 'dart:convert';
import 'dart:io';

import '../models/qa_models.dart';
import '../models/scenario_models.dart';

class ScenarioCatalogException implements Exception {
  const ScenarioCatalogException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ScenarioCatalogStore {
  const ScenarioCatalogStore();

  Future<SourceScenarioCatalog> load(QaSource source) async {
    final file = _catalogFile(source.path);
    if (!await file.exists()) {
      return SourceScenarioCatalog(
        sourceId: source.id,
        environments: const [EnvironmentProfile(id: 'local', name: 'Local')],
      );
    }
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) {
        throw const FormatException('Catalog root must be an object');
      }
      final catalog = SourceScenarioCatalog.fromJson(
        Map<String, dynamic>.from(json),
      );
      final normalized = SourceScenarioCatalog(
        sourceId: source.id,
        scenarios: catalog.scenarios,
        environments: catalog.environments.isEmpty
            ? const [EnvironmentProfile(id: 'local', name: 'Local')]
            : _withoutPersistedSecrets(catalog.environments),
      );
      final containedSecretValue = catalog.environments.any(
        (environment) =>
            environment.secretKeys.any(environment.variables.containsKey),
      );
      if (containedSecretValue) await save(source, normalized);
      return normalized;
    } on Object catch (error) {
      throw ScenarioCatalogException('Không đọc được scenarios.json: $error');
    }
  }

  Future<void> save(QaSource source, SourceScenarioCatalog catalog) async {
    final file = _catalogFile(source.path);
    await file.parent.create(recursive: true);
    await file.writeAsString('${catalog.encode()}\n', flush: true);
  }

  Future<SourceScenarioCatalog> importFrom(
    QaSource source,
    String inputPath,
  ) async {
    try {
      final json = jsonDecode(await File(inputPath).readAsString());
      if (json is! Map) throw const FormatException('Expected JSON object');
      final imported = SourceScenarioCatalog.fromJson(
        Map<String, dynamic>.from(json),
      );
      final normalized = SourceScenarioCatalog(
        sourceId: source.id,
        scenarios: imported.scenarios,
        environments: imported.environments.isEmpty
            ? const [EnvironmentProfile(id: 'local', name: 'Local')]
            : _withoutPersistedSecrets(imported.environments),
      );
      await save(source, normalized);
      return normalized;
    } on Object catch (error) {
      throw ScenarioCatalogException('Không nhập được catalog: $error');
    }
  }

  Future<void> exportTo(
    SourceScenarioCatalog catalog,
    String outputPath,
  ) async {
    await File(outputPath).writeAsString('${catalog.encode()}\n', flush: true);
  }

  File _catalogFile(String sourcePath) => File(
    '$sourcePath${Platform.pathSeparator}.fiza-qa'
    '${Platform.pathSeparator}scenarios.json',
  );
}

List<EnvironmentProfile> _withoutPersistedSecrets(
  List<EnvironmentProfile> environments,
) {
  return environments
      .map((environment) {
        final variables = Map<String, String>.of(environment.variables);
        for (final key in environment.secretKeys) {
          variables.remove(key);
        }
        return EnvironmentProfile(
          id: environment.id,
          name: environment.name,
          variables: variables,
          secretKeys: environment.secretKeys,
        );
      })
      .toList(growable: false);
}
