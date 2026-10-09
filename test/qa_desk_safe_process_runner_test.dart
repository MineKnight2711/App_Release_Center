import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/safe_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs an allowlisted command and streams output', () async {
    final running = await const SafeProcessRunner().start(
      suite: const QaSuite(
        id: 'version',
        name: 'Dart Version',
        executable: 'dart',
        arguments: ['--version'],
      ),
      workingDirectory: Directory.current.path,
    );

    final output = await running.output.toList();
    final exitCode = await running.exitCode;

    expect(exitCode, 0);
    expect(output.join('\n'), contains('Dart SDK version'));
  });

  test('blocks shell metacharacters in arguments', () async {
    expect(
      () => const SafeProcessRunner().start(
        suite: const QaSuite(
          id: 'unsafe',
          name: 'Unsafe',
          executable: 'dart',
          arguments: ['--version & whoami'],
        ),
        workingDirectory: Directory.current.path,
      ),
      throwsA(isA<ProcessStartFailure>()),
    );
  });

  test('a tool that does not write UTF-8 does not end the output', () async {
    // Java writes the ANSI code page when piped: "và" arrived as 76 E0.
    final sandbox = await Directory.systemTemp.createTemp('fiza_bytes_');
    addTearDown(() => sandbox.delete(recursive: true));
    final script = File('${sandbox.path}${Platform.pathSeparator}bytes.dart');
    await script.writeAsString(
      "import 'dart:io'; void main() { "
      "stdout.add([0x5B, 0x46, 0x5D, 0x20, 0x76, 0xE0, 0x20, 0x41, 0x0A]); "
      "stdout.add('after\\n'.codeUnits); }",
    );
    final running = await const SafeProcessRunner().start(
      suite: QaSuite(
        id: 'bytes',
        name: 'Bytes',
        executable: 'dart',
        arguments: [script.path],
      ),
      workingDirectory: sandbox.path,
    );

    final output = await running.output.toList();
    expect(await running.exitCode, 0);
    expect(output, ['[F] v\uFFFD A', 'after']);
  });

  test('passes source environment variables to the process', () async {
    final sandbox = await Directory.systemTemp.createTemp('fiza_env_');
    addTearDown(() => sandbox.delete(recursive: true));
    final script = File('${sandbox.path}${Platform.pathSeparator}env.dart');
    await script.writeAsString(
      "import 'dart:io'; void main() => print(Platform.environment['FIZA_TEST_ENV']);",
    );
    final running = await const SafeProcessRunner().start(
      suite: QaSuite(
        id: 'environment',
        name: 'Environment',
        executable: 'dart',
        arguments: [script.path],
      ),
      workingDirectory: sandbox.path,
      environment: const {'FIZA_TEST_ENV': 'staging'},
    );

    final output = await running.output.toList();
    expect(await running.exitCode, 0);
    expect(output, contains('staging'));
  });
}
