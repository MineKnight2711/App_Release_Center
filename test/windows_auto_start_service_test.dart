import 'dart:io';

import 'package:app_management_center/app/services/windows_auto_start_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory startup;

  setUp(() {
    startup = Directory.systemTemp.createTempSync('amc-startup-');
  });

  tearDown(() {
    if (startup.existsSync()) startup.deleteSync(recursive: true);
  });

  WindowsAutoStartService build({
    List<({String executable, List<String> arguments})>? calls,
    int exitCode = 0,
  }) {
    return WindowsAutoStartService(
      startupDirectory: startup.path,
      executablePath: r"C:\Program Files\Tom's App\app.exe",
      processRunner: (executable, arguments) async {
        calls?.add((executable: executable, arguments: arguments));
        return ProcessResult(1, exitCode, '', exitCode == 0 ? '' : 'failed');
      },
    );
  }

  test('reports disabled until the shortcut exists', () {
    final service = build();
    expect(service.isEnabled(), isFalse);

    File(
      p.join(startup.path, WindowsAutoStartService.shortcutName),
    ).writeAsStringSync('');

    expect(service.isEnabled(), isTrue);
  });

  test('escapes quotes in paths so the script stays one literal', () async {
    final calls = <({String executable, List<String> arguments})>[];
    final service = build(calls: calls);

    await service.setEnabled(true);

    final script = calls.single.arguments.last;
    expect(calls.single.executable, 'powershell.exe');
    // The apostrophe in "Tom's App" must be doubled, not left to terminate
    // the literal and turn the rest of the path into PowerShell code.
    expect(script, contains(r"Tom''s App"));
    expect(script, contains('CreateShortcut('));
    expect(script, contains(r'$link.Save()'));
  });

  test('removing clears the shortcut without running anything', () async {
    final shortcut = File(
      p.join(startup.path, WindowsAutoStartService.shortcutName),
    )..writeAsStringSync('');
    final calls = <({String executable, List<String> arguments})>[];
    final service = build(calls: calls);

    await service.setEnabled(false);

    expect(shortcut.existsSync(), isFalse);
    expect(calls, isEmpty);
  });

  test('disabling an already absent shortcut is not an error', () async {
    final service = build();
    await service.setEnabled(false);
    expect(service.isEnabled(), isFalse);
  });

  test('surfaces a failure from PowerShell', () async {
    final service = build(exitCode: 1);

    await expectLater(
      service.setEnabled(true),
      throwsA(isA<ProcessException>()),
    );
  });

  test('the generated script really creates a shortcut', () async {
    // Runs PowerShell for real: a script that looks right but does not build
    // a .lnk would pass every check above.
    final service = WindowsAutoStartService(
      startupDirectory: startup.path,
      executablePath: Platform.resolvedExecutable,
    );

    await service.setEnabled(true);

    expect(service.isEnabled(), isTrue);
    expect(
      File(
        p.join(startup.path, WindowsAutoStartService.shortcutName),
      ).lengthSync(),
      greaterThan(0),
    );
  }, skip: !Platform.isWindows);
}
