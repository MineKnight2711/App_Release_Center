import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/controllers/qa_workspace_controller.dart';
import 'package:app_management_center/app/modules/qa_desk/models/preflight.dart';
import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/models/scenario_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/artifact_store.dart';
import 'package:app_management_center/app/modules/qa_desk/services/scenario_catalog_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'qa_desk_fakes.dart';

void main() {
  late Directory sandbox;
  late FakeRunner runner;
  late QaWorkspaceController controller;

  Future<void> open(Map<String, int> exitCodes) async {
    final project = Directory(p.join(sandbox.path, 'project'));
    await project.create();
    runner = FakeRunner(exitCodes);
    controller = fakeController(
      runner: runner,
      sources: [appSource(path: project.path)],
      artifacts: ArtifactStore(rootOverride: sandbox.path),
      catalogs: const ScenarioCatalogStore(),
    );
    await controller.initialize();
  }

  /// Lets the run loop reach the point where [suiteId] has been started.
  Future<void> untilStarted(String suiteId) async {
    for (var i = 0; i < 100 && !runner.started.contains(suiteId); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(runner.started, contains(suiteId));
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('qa_desk_controller_');
  });

  tearDown(() async {
    controller.dispose();
    await sandbox.delete(recursive: true);
  });

  test('runs the selected suites in order and records the batch', () async {
    await open({'analyze': 0, 'unit': 1, 'smoke': 0});

    await controller.runSelected();

    expect(runner.started, ['analyze', 'unit']);
    expect(controller.isRunning, isFalse);
    final runs = {for (final run in controller.runs) run.suiteId: run};
    expect(runs['analyze']!.status, RunStatus.passed);
    expect(runs['unit']!.status, RunStatus.failed);
    expect(runs['unit']!.exitCode, 1);
    expect(runs['unit']!.gitBranch, 'develop');
    expect(runs['unit']!.logs, contains('output of unit'));
    expect(
      File(runs['unit']!.logPath!).readAsStringSync(),
      contains('Process exited with code 1.'),
    );

    final batch = controller.historyBatches.single;
    expect(batch.status, RunStatus.failed);
    expect(batch.total, 2);
    expect(batch.passed, 1);
    expect(batch.failed, 1);
  });

  test('stopping ends the running suite and skips the rest', () async {
    // analyze never exits on its own.
    await open({'unit': 0});

    final run = controller.runSelected();
    await untilStarted('analyze');
    expect(controller.isRunning, isTrue);
    await controller.cancelAll();
    await run;

    expect(runner.processes['analyze']!.stopped, isTrue);
    expect(runner.started, ['analyze']);
    expect(controller.runs.map((run) => run.status), [
      RunStatus.cancelled,
      RunStatus.cancelled,
    ]);
    final batch = controller.historyBatches.single;
    expect(batch.status, RunStatus.cancelled);
    expect(batch.cancelled, 2);
    expect(controller.isRunning, isFalse);
  });

  test('shutdown stops a run in progress', () async {
    await open({'unit': 0});

    final run = controller.runSelected();
    await untilStarted('analyze');
    await controller.shutdown();
    await run;

    expect(runner.processes['analyze']!.stopped, isTrue);
    expect(controller.isRunning, isFalse);
  });

  test(
    're-running failures runs only those and restores the selection',
    () async {
      await open({'analyze': 0, 'unit': 1, 'smoke': 0});
      await controller.runSelected();
      final failedBatch = controller.historyBatches.single.id;
      runner.started.clear();

      final message = await controller.rerunFailures(failedBatch);

      expect(message, isNull);
      expect(runner.started, ['unit']);
      expect(controller.historyBatches, hasLength(2));
      final source = controller.sources.single;
      expect(source.selected, isTrue);
      expect(
        {for (final suite in source.suites) suite.id: suite.selected},
        {'analyze': true, 'unit': true, 'smoke': false},
      );
    },
  );

  test(
    'the chosen environment reaches the process; secrets stay in memory',
    () async {
      await open({'analyze': 0, 'unit': 0});
      final saved = await controller.saveEnvironment(
        'app',
        const EnvironmentProfile(
          id: 'staging',
          name: 'Staging',
          variables: {'API_URL': 'https://staging.example'},
          secretKeys: ['API_TOKEN'],
        ),
      );
      expect(saved, isNull);
      controller.selectEnvironment('app', 'staging');
      controller.setSessionSecrets('app', 'staging', {'API_TOKEN': 's3cret'});

      await controller.runSelected();

      expect(runner.environments['analyze'], {
        'API_URL': 'https://staging.example',
        'API_TOKEN': 's3cret',
      });
      expect(controller.runs.first.environmentName, 'Staging');
      final catalog = File(
        p.join(sandbox.path, 'project', '.fiza-qa', 'scenarios.json'),
      ).readAsStringSync();
      expect(catalog, contains('API_TOKEN'));
      expect(catalog, isNot(contains('s3cret')));
      for (final run in controller.runs) {
        expect(
          File(run.logPath!).readAsStringSync(),
          isNot(contains('s3cret')),
        );
      }
    },
  );

  test(
    'a failure is screenshotted only when the suite ran on the phone',
    () async {
      const phone = DeviceInfo(
        id: 'emulator-5554',
        name: 'Pixel 7',
        platform: 'android-x64',
        category: 'mobile',
        isEmulator: true,
      );
      final mobile = FakeMobile();
      runner = FakeRunner({'unit': 1, 'smoke': 1});
      controller = fakeController(
        runner: runner,
        devices: const [phone],
        mobile: mobile,
        sources: [
          appSource(suites: [unitSuite, smokeSuite.copyWith(selected: true)]),
        ],
      );
      await controller.initialize();
      await controller.refreshDevices();

      await controller.runSelected();

      expect(mobile.screenshots, ['emulator-5554']);
      final runs = {for (final run in controller.runs) run.suiteId: run};
      expect(runs['unit']!.screenshotPath, isNull);
      expect(runs['smoke']!.screenshotPath, isNotNull);
    },
  );

  group('preflight', () {
    const emulator = DeviceInfo(
      id: 'emulator-5554',
      name: 'Pixel 7',
      platform: 'android-x64',
      category: 'mobile',
      isEmulator: true,
    );

    Set<PreflightKind> kinds() => {
      for (final issue in controller.preflight()) issue.kind,
    };

    test('a hardware-only suite refuses an emulator', () async {
      runner = FakeRunner();
      controller = fakeController(
        runner: runner,
        devices: const [emulator],
        sources: [
          appSource(
            suites: [
              smokeSuite.copyWith(selected: true),
              const QaSuite(
                id: 'nfc',
                name: 'NFC',
                executable: 'flutter',
                arguments: ['test'],
                requiresPhysicalDevice: true,
              ),
            ],
          ),
        ],
      );
      await controller.initialize();
      expect(kinds(), contains(PreflightKind.deviceMissing));

      await controller.refreshDevices();

      expect(kinds(), {PreflightKind.physicalDeviceRequired});
      expect(controller.preflight().single.message, contains('máy ảo'));
    });

    test('an Appium suite is blocked only when Appium is missing', () async {
      runner = FakeRunner();
      controller = fakeController(
        runner: runner,
        sources: [
          appSource(
            suites: const [
              QaSuite(
                id: 'appium',
                name: 'Appium flow',
                executable: 'npx',
                arguments: ['wdio'],
                requiresAppium: true,
              ),
            ],
          ),
        ],
      );
      await controller.initialize();

      expect(kinds(), {PreflightKind.appiumMissing});
    });

    test('the weak network is a note, not a blocker', () async {
      runner = FakeRunner();
      controller = fakeController(runner: runner);
      await controller.initialize();
      await controller.network.toggle();
      addTearDown(controller.network.toggle);

      final issue = controller.preflight().single;
      expect(issue.kind, PreflightKind.networkSimulated);
      expect(issue.blocking, isFalse);
    });

    test('secrets left blank keep the ones already entered', () async {
      runner = FakeRunner();
      controller = fakeController(runner: runner);
      await controller.initialize();
      await controller.saveEnvironment(
        'app',
        const EnvironmentProfile(
          id: 'staging',
          name: 'Staging',
          secretKeys: ['API_TOKEN', 'SIGNING_KEY'],
        ),
      );
      controller.selectEnvironment('app', 'staging');
      expect(controller.preflight().single.message, contains('API_TOKEN'));

      controller.updateSessionSecrets('app', 'staging', {'API_TOKEN': 'a'});
      controller.updateSessionSecrets('app', 'staging', {
        'API_TOKEN': '',
        'SIGNING_KEY': 'b',
      });

      expect(kinds(), isEmpty);
      expect(
        controller.sessionSecretIsSet('app', 'staging', 'API_TOKEN'),
        isTrue,
      );
    });
  });
}
