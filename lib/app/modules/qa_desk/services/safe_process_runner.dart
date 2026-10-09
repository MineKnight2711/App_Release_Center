import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/qa_models.dart';

class ProcessStartFailure implements Exception {
  const ProcessStartFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class RunningProcess {
  RunningProcess({
    required this.process,
    required this.output,
    required this.exitCode,
  });

  final Process process;
  final Stream<String> output;
  final Future<int> exitCode;

  Future<void> stop() async {
    final pid = process.pid;
    if (Platform.isWindows) {
      await Process.run('taskkill.exe', [
        '/PID',
        '$pid',
        '/T',
        '/F',
      ], runInShell: false);
      return;
    }
    process.kill(ProcessSignal.sigterm);
  }
}

/// A tool QA Desk installs itself, as the command that starts it.
class ManagedTool {
  const ManagedTool({required this.executable, this.prefix = const []});

  /// Absolute path of the program to start, never looked up on PATH.
  final String executable;

  /// Arguments placed before the suite's own.
  final List<String> prefix;
}

class SafeProcessRunner {
  const SafeProcessRunner({this.managedTool});

  /// The command for a tool QA Desk installs itself, by the name a suite
  /// uses (`maestro`), or null when it is not one.
  final ManagedTool? Function(String name)? managedTool;

  Future<RunningProcess> start({
    required QaSuite suite,
    required String workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    final directory = Directory(workingDirectory);
    if (!await directory.exists()) {
      throw const ProcessStartFailure('Working directory không tồn tại.');
    }

    final requested = suite.executable.toLowerCase();
    final managed = managedTool?.call(requested);
    if (managed == null && !_allowedExecutables.contains(requested)) {
      throw ProcessStartFailure(
        'Executable "${suite.executable}" không được phép.',
      );
    }
    if (managed != null && !File(managed.executable).existsSync()) {
      throw ProcessStartFailure('Chưa cài "${suite.executable}".');
    }
    for (final argument in suite.arguments) {
      if (_unsafeShellCharacters.hasMatch(argument)) {
        throw ProcessStartFailure(
          'Argument chứa ký tự shell không an toàn: $argument',
        );
      }
    }

    final resolved =
        managed?.executable ?? await _resolveExecutable(suite.executable);
    final arguments = [...?managed?.prefix, ...suite.arguments];
    final Process process;
    if (Platform.isWindows &&
        (resolved.toLowerCase().endsWith('.bat') ||
            resolved.toLowerCase().endsWith('.cmd'))) {
      process = await Process.start(
        resolved,
        arguments,
        workingDirectory: directory.absolute.path,
        environment: environment.isEmpty ? null : environment,
        includeParentEnvironment: true,
        // Batch launchers such as flutter.bat and npm.cmd require cmd.exe.
        // Both executable and arguments were allowlisted/validated above.
        runInShell: true,
      );
    } else {
      process = await Process.start(
        resolved,
        arguments,
        workingDirectory: directory.absolute.path,
        environment: environment.isEmpty ? null : environment,
        includeParentEnvironment: true,
        runInShell: false,
      );
    }

    final controller = StreamController<String>();
    var openStreams = 2;

    void closeOne() {
      openStreams -= 1;
      if (openStreams == 0 && !controller.isClosed) {
        controller.close();
      }
    }

    // Tools do not all write UTF-8 (Java writes the ANSI code page when
    // piped): a stray byte becomes U+FFFD instead of ending the run's output.
    const decoder = Utf8Decoder(allowMalformed: true);
    process.stdout
        .transform(decoder)
        .transform(const LineSplitter())
        .listen(controller.add, onError: controller.addError, onDone: closeOne);
    process.stderr
        .transform(decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => controller.add('[stderr] $line'),
          onError: controller.addError,
          onDone: closeOne,
        );

    return RunningProcess(
      process: process,
      output: controller.stream,
      exitCode: process.exitCode,
    );
  }

  Future<String> _resolveExecutable(String executable) async {
    if (executable.contains(Platform.pathSeparator)) {
      final file = File(executable);
      if (await file.exists()) return file.absolute.path;
      throw ProcessStartFailure('Không tìm thấy executable: $executable');
    }

    final lookup = await Process.run(
      Platform.isWindows ? 'where.exe' : 'which',
      [executable],
      runInShell: false,
    );
    if (lookup.exitCode != 0) {
      throw ProcessStartFailure('Không tìm thấy "$executable" trong PATH.');
    }
    final candidates = const LineSplitter()
        .convert(lookup.stdout.toString())
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (candidates.isEmpty) {
      throw ProcessStartFailure('Không resolve được "$executable".');
    }
    if (Platform.isWindows) {
      final runnable = candidates.where((candidate) {
        final lower = candidate.toLowerCase();
        return lower.endsWith('.exe') ||
            lower.endsWith('.com') ||
            lower.endsWith('.bat') ||
            lower.endsWith('.cmd');
      }).toList();
      if (runnable.isNotEmpty) return runnable.first;
    }
    return candidates.first;
  }
}

const _allowedExecutables = {
  'flutter',
  'dart',
  'node',
  'npm',
  'npx',
  'adb',
  'appium',
};

final _unsafeShellCharacters = RegExp(r'[&|<>^\r\n]');
