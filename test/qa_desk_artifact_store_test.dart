import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/artifact_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writes a raw log artifact for a suite run', () async {
    final sandbox = await Directory.systemTemp.createTemp('fiza_artifacts_');
    addTearDown(() => sandbox.delete(recursive: true));
    final run = SuiteRun(
      runId: 'run:1',
      batchId: 'batch-1',
      sourceId: 'mobile-app',
      sourceName: 'Mobile App',
      suiteId: 'analyze',
      suiteName: 'Analyze',
      command: 'flutter analyze',
      logs: ['first line', 'second line'],
    );

    final savedPath = await ArtifactStore(
      rootOverride: sandbox.path,
    ).saveLog(run);

    expect(await File(savedPath).readAsString(), contains('second line'));
    expect(savedPath, contains('batch-1'));
  });
}
