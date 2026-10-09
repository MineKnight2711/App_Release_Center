import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/services/flow_compiler.dart';
import 'package:app_management_center/app/modules/qa_desk/services/scenario_catalog_store.dart';
import 'package:app_management_center/app/modules/qa_desk/services/source_discovery_service.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/validate_catalogs.dart <source> [...]',
    );
    exitCode = 64;
    return;
  }

  var invalid = false;
  for (final sourcePath in arguments) {
    try {
      final source = await const SourceDiscoveryService().discover(sourcePath);
      final catalog = await const ScenarioCatalogStore().load(source);
      final suiteIds = source.suites.map((suite) => suite.id).toSet();
      final scenarioIds = <String>{};
      final environmentIds = <String>{};
      final errors = <String>[];
      for (final scenario in catalog.scenarios) {
        if (scenario.id.isEmpty || !scenarioIds.add(scenario.id)) {
          errors.add('Scenario id rỗng hoặc trùng: ${scenario.id}');
        }
        if (scenario.title.isEmpty) {
          errors.add('Scenario ${scenario.id} thiếu title');
        }
        final spec = scenario.automation;
        if (spec != null) {
          final app = source.app(spec.app);
          if (app == null) {
            errors.add(
              'Scenario ${scenario.id} tham chiếu app không tồn tại: '
              '${spec.app}',
            );
          }
          if (spec.role.trim().isEmpty) {
            errors.add('Scenario ${scenario.id} thiếu vai trò tài khoản');
          }
          if (spec.steps.isEmpty) {
            errors.add('Scenario ${scenario.id} không có bước nào');
          }
          if (app != null) {
            try {
              const FlowCompiler().compile(scenario, app);
            } on FlowCompileException catch (error) {
              errors.add('Scenario ${scenario.id}: ${error.message}');
            }
            for (final name in spec.environments) {
              if (app.environment(name) == null) {
                errors.add(
                  'Scenario ${scenario.id} chạy trên môi trường app không '
                  'khai: $name',
                );
              }
            }
          }
        } else if (!suiteIds.contains(scenario.suiteId)) {
          errors.add(
            'Scenario ${scenario.id} tham chiếu suite không tồn tại: '
            '${scenario.suiteId}',
          );
        }
      }
      for (final environment in catalog.environments) {
        if (environment.id.isEmpty || !environmentIds.add(environment.id)) {
          errors.add('Environment id rỗng hoặc trùng: ${environment.id}');
        }
        for (final key in [
          ...environment.variables.keys,
          ...environment.secretKeys,
        ]) {
          if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
            errors.add('Environment key không hợp lệ: $key');
          }
        }
        final persistedSecrets = environment.secretKeys.where(
          environment.variables.containsKey,
        );
        for (final key in persistedSecrets) {
          errors.add('Secret $key không được lưu trong variables');
        }
      }
      if (errors.isEmpty) {
        stdout.writeln(
          'OK ${source.name}: ${catalog.scenarios.length} scenario(s), '
          '${catalog.environments.length} environment(s)',
        );
      } else {
        invalid = true;
        stderr.writeln('INVALID ${source.name}');
        for (final error in errors) {
          stderr.writeln('  - $error');
        }
      }
    } on Object catch (error) {
      invalid = true;
      stderr.writeln('ERROR $sourcePath: $error');
    }
  }
  if (invalid) exitCode = 1;
}
