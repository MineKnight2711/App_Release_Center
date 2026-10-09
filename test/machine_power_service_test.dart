import 'dart:io';

import 'package:app_management_center/app/services/machine_power_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordedCall {
  const _RecordedCall(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

class _FakeProcesses {
  _FakeProcesses({this.exitCode = 0, this.stdout = '', this.stderr = ''});

  final calls = <_RecordedCall>[];
  int exitCode;
  String stdout;
  String stderr;

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add(_RecordedCall(executable, arguments));
    return ProcessResult(1, exitCode, stdout, stderr);
  }

  _RecordedCall get only {
    expect(calls, hasLength(1));
    return calls.single;
  }
}

void main() {
  group('power commands', () {
    test('shuts down without forcing applications closed', () async {
      final processes = _FakeProcesses();
      final service = MachinePowerService(processRunner: processes.run);

      await service.perform(MachinePowerAction.shutdown, delaySeconds: 15);

      expect(processes.only.executable, 'shutdown.exe');
      expect(processes.only.arguments, ['/s', '/t', '15']);
      expect(
        processes.only.arguments,
        isNot(contains('/f')),
        reason: 'unsaved work must not be killed unless asked',
      );
    });

    test('forces only when the caller asks', () async {
      final processes = _FakeProcesses();
      final service = MachinePowerService(processRunner: processes.run);

      await service.perform(MachinePowerAction.shutdown, force: true);

      expect(processes.only.arguments, ['/s', '/t', '0', '/f']);
    });

    test(
      'restarts with /g so the session comes back on a PIN machine',
      () async {
        final processes = _FakeProcesses();
        final service = MachinePowerService(processRunner: processes.run);

        await service.perform(MachinePowerAction.restart, delaySeconds: 15);

        expect(processes.only.arguments, ['/g', '/t', '15']);
      },
    );

    test('maps the remaining actions to their Windows commands', () async {
      final expected = {
        MachinePowerAction.lock: (
          'rundll32.exe',
          ['user32.dll,LockWorkStation'],
        ),
        MachinePowerAction.sleep: (
          'powershell.exe',
          [
            '-NoProfile',
            '-NonInteractive',
            '-WindowStyle',
            'Hidden',
            '-Command',
            r'Add-Type -AssemblyName System.Windows.Forms; '
                r'$slept = [System.Windows.Forms.Application]::SetSuspendState('
                r'[System.Windows.Forms.PowerState]::Suspend, $false, $false); '
                r'if (-not $slept) { exit 1 }',
          ],
        ),
        MachinePowerAction.hibernate: ('shutdown.exe', ['/h']),
        MachinePowerAction.logoff: ('shutdown.exe', ['/l']),
        MachinePowerAction.cancel: ('shutdown.exe', ['/a']),
      };

      for (final entry in expected.entries) {
        final processes = _FakeProcesses();
        final service = MachinePowerService(processRunner: processes.run);

        await service.perform(entry.key);

        expect(
          processes.only.executable,
          entry.value.$1,
          reason: '${entry.key}',
        );
        expect(
          processes.only.arguments,
          entry.value.$2,
          reason: '${entry.key}',
        );
      }
    });

    test('sleep explicitly suspends and keeps wake events enabled', () async {
      final processes = _FakeProcesses();
      final service = MachinePowerService(processRunner: processes.run);

      await service.perform(MachinePowerAction.sleep);

      expect(processes.only.executable, 'powershell.exe');
      final command = processes.only.arguments.last;
      expect(command, contains('PowerState]::Suspend'));
      expect(command, contains(r'$false, $false'));
      expect(command, isNot(contains('Hibernate')));
      expect(command, isNot(contains('rundll32')));
    });

    test('turning the screen off does not suspend the machine', () async {
      final processes = _FakeProcesses();
      final service = MachinePowerService(processRunner: processes.run);

      await service.perform(MachinePowerAction.displayOff);

      final call = processes.only;
      final script = call.arguments.last;
      expect(call.executable, 'powershell.exe');
      // WM_SYSCOMMAND with SC_MONITORPOWER, lParam 2 for "off".
      expect(script, contains('0x0112'));
      expect(script, contains('0xF170'));
      expect(script, contains('SendMessage'));
      // The whole point is that the machine stays awake and reachable.
      expect(script, isNot(contains('SetSuspendState')));
      expect(call.arguments, isNot(contains('/s')));
      expect(call.arguments, isNot(contains('/h')));
    });

    test('the screen-off script is a single argument', () async {
      // A here-string would split across lines and stop being one argument,
      // which is how the first attempt at this broke.
      final processes = _FakeProcesses();
      final service = MachinePowerService(processRunner: processes.run);

      await service.perform(MachinePowerAction.displayOff);

      final script = processes.only.arguments.last;
      expect(script.contains('\n'), isFalse);
    });

    test('treats a negative delay as immediate', () async {
      final processes = _FakeProcesses();
      final service = MachinePowerService(processRunner: processes.run);

      await service.perform(MachinePowerAction.shutdown, delaySeconds: -5);

      expect(processes.only.arguments, ['/s', '/t', '0']);
    });

    test('raises when the command fails', () async {
      final processes = _FakeProcesses(exitCode: 1, stderr: 'Access denied.');
      final service = MachinePowerService(processRunner: processes.run);

      await expectLater(
        service.perform(MachinePowerAction.shutdown),
        throwsA(isA<ProcessException>()),
      );
    });
  });

  group('sleep support', () {
    test(
      'reads the available states and ignores the unavailable block',
      () async {
        final processes = _FakeProcesses(
          stdout: '''
The following sleep states are available on this system:
    Standby (S3)
    Hibernate
    Hybrid Sleep

The following sleep states are not available on this system:
    Standby (S0 Low Power Idle)
        The system firmware does not support this standby state.
''',
        );
        final service = MachinePowerService(processRunner: processes.run);

        final support = await service.readSleepSupport();

        expect(support.standby, isTrue);
        expect(support.hibernate, isTrue);
        expect(
          support.modernStandby,
          isFalse,
          reason: 'it was listed under the unavailable heading',
        );
        expect(support.sleepFallsBackToHibernate, isFalse);
      },
    );

    test('flags a machine where sleeping would hibernate instead', () {
      final support = MachinePowerService.parseSleepSupport('''
The following sleep states are available on this system:
    Hibernate

The following sleep states are not available on this system:
    Standby (S3)
    Standby (S0 Low Power Idle)
''');

      expect(support.hibernate, isTrue);
      expect(support.standby, isFalse);
      expect(support.sleepFallsBackToHibernate, isTrue);
    });

    test('reports nothing when powercfg cannot be read', () async {
      final processes = _FakeProcesses(exitCode: 1);
      final service = MachinePowerService(processRunner: processes.run);

      final support = await service.readSleepSupport();

      expect(support.standby, isFalse);
      expect(support.hibernate, isFalse);
      expect(support.modernStandby, isFalse);
    });
  });

  group('action names', () {
    test('round trip through the wire name', () {
      for (final action in MachinePowerAction.values) {
        expect(machinePowerActionFromName(action.name), action);
      }
      expect(
        machinePowerActionFromName('  SHUTDOWN '),
        MachinePowerAction.shutdown,
      );
    });

    test('a camelCase name survives being lowercased on the way in', () {
      // displayOff is the first action whose name is not a single word, and
      // the old parser compared the enum spelling against a lowercased input,
      // so it could never match.
      expect(
        machinePowerActionFromName('displayOff'),
        MachinePowerAction.displayOff,
      );
      expect(
        machinePowerActionFromName('DISPLAYOFF'),
        MachinePowerAction.displayOff,
      );
      expect(
        machinePowerActionFromName(' displayoff '),
        MachinePowerAction.displayOff,
      );
    });

    test('rejects anything else', () {
      expect(machinePowerActionFromName('format'), isNull);
      expect(machinePowerActionFromName(''), isNull);
    });
  });
}
