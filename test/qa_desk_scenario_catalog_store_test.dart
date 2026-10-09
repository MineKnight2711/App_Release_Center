import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/models/scenario_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/scenario_catalog_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'persists a source-owned scenario catalog without secret values',
    () async {
      final sandbox = await Directory.systemTemp.createTemp('fiza_catalog_');
      addTearDown(() => sandbox.delete(recursive: true));
      final source = QaSource(
        id: 'sample',
        name: 'Sample',
        path: sandbox.path,
        type: SourceType.flutter,
        suites: const [],
      );
      const catalog = SourceScenarioCatalog(
        sourceId: 'sample',
        scenarios: [
          TestScenario(
            id: 'login',
            title: 'Login',
            module: 'Auth',
            suiteId: 'auth-tests',
            steps: ['Enter credentials', 'Submit'],
            expectedResult: 'Dashboard opens',
          ),
        ],
        environments: [
          EnvironmentProfile(
            id: 'staging',
            name: 'Staging',
            variables: {
              'FIZA_ENV': 'staging',
              'TEST_PASSWORD': 'actual-password',
            },
            secretKeys: ['TEST_PASSWORD'],
          ),
        ],
      );

      await const ScenarioCatalogStore().save(source, catalog);
      final loaded = await const ScenarioCatalogStore().load(source);
      final raw = await File(
        '${sandbox.path}${Platform.pathSeparator}.fiza-qa'
        '${Platform.pathSeparator}scenarios.json',
      ).readAsString();

      expect(loaded.scenarios.single.title, 'Login');
      expect(loaded.environments.single.variables['FIZA_ENV'], 'staging');
      expect(loaded.environments.single.secretKeys, ['TEST_PASSWORD']);
      expect(
        loaded.environments.single.variables,
        isNot(contains('TEST_PASSWORD')),
      );
      expect(raw, isNot(contains('actual-password')));
    },
  );
}
