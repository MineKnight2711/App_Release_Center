import 'dart:io';

import 'package:app_management_center/app/data/release_center_connect.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/machine_power_service.dart';
import 'package:app_management_center/app/services/mobile_control_credential_store_service.dart';
import 'package:app_management_center/app/services/notification_credential_store_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:app_management_center/app/services/remote_control_service.dart';
import 'package:app_management_center/app/services/script_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('power command policy', () {
    const busyStatus = 'Đang build Demo';

    String? reject({
      required MachinePowerAction action,
      bool allowPowerControl = true,
      bool powerSupported = true,
      bool runnerBusy = false,
      bool force = false,
    }) {
      return powerCommandRejection(
        action: action,
        allowPowerControl: allowPowerControl,
        powerSupported: powerSupported,
        runnerBusy: runnerBusy,
        force: force,
        runnerStatus: busyStatus,
      );
    }

    test('refuses every action while the gate is closed', () {
      for (final action in MachinePowerAction.values) {
        expect(
          reject(action: action, allowPowerControl: false),
          contains('chưa bật quyền'),
          reason: '$action',
        );
      }
    });

    test('refuses on a platform that cannot do it', () {
      expect(
        reject(action: MachinePowerAction.lock, powerSupported: false),
        contains('không hỗ trợ'),
      );
    });

    test('protects a running release from a disruptive action', () {
      final disruptive = [
        MachinePowerAction.shutdown,
        MachinePowerAction.restart,
        MachinePowerAction.sleep,
        MachinePowerAction.hibernate,
        MachinePowerAction.logoff,
      ];

      for (final action in disruptive) {
        final reason = reject(action: action, runnerBusy: true);
        expect(reason, isNotNull, reason: '$action');
        expect(reason, contains(busyStatus), reason: '$action');
      }
    });

    test('lets locking and cancelling through while a release runs', () {
      expect(reject(action: MachinePowerAction.lock, runnerBusy: true), isNull);
      expect(
        reject(action: MachinePowerAction.cancel, runnerBusy: true),
        isNull,
      );
    });

    test('a deliberate force overrides the busy check', () {
      expect(
        reject(
          action: MachinePowerAction.shutdown,
          runnerBusy: true,
          force: true,
        ),
        isNull,
      );
    });

    test('allows everything on an idle machine', () {
      for (final action in MachinePowerAction.values) {
        expect(reject(action: action), isNull, reason: '$action');
      }
    });
  });

  group('applying a power command', () {
    late _FakeProcesses processes;
    late RemoteControlService service;
    late ReleaseRunnerService runner;

    Future<void> build({bool allowPowerControl = true}) async {
      SharedPreferences.setMockInitialValues({});
      final store = await ProjectStoreService().init();
      processes = _FakeProcesses();
      runner = ReleaseRunnerService();
      service = RemoteControlService(
        store: store,
        catalog: ScriptCatalogService(),
        runner: runner,
        connect: ReleaseCenterConnect(),
        credentialStore: NotificationCredentialStoreService(
          secureStore: _MemorySecureKeyValueStore(),
        ),
        mobileCredentialStore: MobileControlCredentialStoreService(
          secureStore: _MemorySecureKeyValueStore(),
        ),
        power: MachinePowerService(processRunner: processes.run),
      );
      await service.init();
      if (allowPowerControl) await service.setAllowPowerControl(true);
    }

    tearDown(Get.reset);

    test('runs the action and reports what it did', () async {
      await build();

      final log = await service.applyPowerCommand(
        action: MachinePowerAction.shutdown,
        delaySeconds: 15,
      );

      expect(processes.calls.single.arguments, ['/s', '/t', '15']);
      expect(log.single, contains('shutdown'));
      expect(log.single, contains('15s'));
    });

    test('remembers a delayed shutdown so the desktop can cancel it', () async {
      await build();

      await service.applyPowerCommand(
        action: MachinePowerAction.shutdown,
        delaySeconds: 30,
      );

      final pending = service.pendingPowerCommand.value;
      expect(pending, isNotNull);
      expect(pending!.action, MachinePowerAction.shutdown);
      expect(pending.remaining().inSeconds, greaterThan(25));
    });

    test('an immediate action leaves nothing to cancel', () async {
      await build();

      await service.applyPowerCommand(action: MachinePowerAction.shutdown);

      expect(service.pendingPowerCommand.value, isNull);
    });

    test('locking is never treated as cancellable', () async {
      await build();

      await service.applyPowerCommand(
        action: MachinePowerAction.lock,
        delaySeconds: 30,
      );

      expect(service.pendingPowerCommand.value, isNull);
    });

    test('cancelling clears the pending command', () async {
      await build();
      await service.applyPowerCommand(
        action: MachinePowerAction.shutdown,
        delaySeconds: 30,
      );

      await service.cancelPendingPowerCommand();

      expect(service.pendingPowerCommand.value, isNull);
      expect(processes.calls.last.arguments, ['/a']);
    });

    test('refuses and runs nothing while the gate is closed', () async {
      await build(allowPowerControl: false);

      await expectLater(
        service.applyPowerCommand(action: MachinePowerAction.shutdown),
        throwsA(isA<RemoteControlException>()),
      );
      expect(processes.calls, isEmpty);
    });

    test('a negative delay becomes immediate', () async {
      await build();

      await service.applyPowerCommand(
        action: MachinePowerAction.restart,
        delaySeconds: -10,
      );

      expect(processes.calls.single.arguments, ['/g', '/t', '0']);
      expect(service.pendingPowerCommand.value, isNull);
    });
  });
}

class _FakeProcesses {
  final calls = <({String executable, List<String> arguments})>[];

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add((executable: executable, arguments: arguments));
    return ProcessResult(1, 0, '', '');
  }
}

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}
