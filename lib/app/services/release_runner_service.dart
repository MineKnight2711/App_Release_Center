import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/models/release_script.dart';
import 'package:get/get.dart';

class ReleaseRunnerService extends GetxService {
  final isRunning = false.obs;
  final status = 'Idle'.obs;
  final activeScriptPath = ''.obs;
  final exitCode = RxnInt();
  final logLines = <String>[].obs;
  final yesNoPrompt = RxnString();

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  bool _hasOpenLogLine = false;
  String _openLogPrefix = '';

  Future<int> run({
    required ReleaseProject project,
    required ReleaseScript script,
    List<String> args = const [],
    Map<String, String> environment = const {},
    bool clearLog = false,
  }) async {
    if (isRunning.value) {
      _append('A script is already running.');
      return -1;
    }

    if (clearLog) {
      this.clearLog();
    }

    final plan = _commandPlan(script, args);
    final mergedEnvironment = Map<String, String>.from(Platform.environment)
      ..addAll(_plainLogEnvironment)
      ..addAll(environment);

    isRunning.value = true;
    status.value = 'Running ${script.fileName}';
    activeScriptPath.value = script.path;
    exitCode.value = null;
    _append('\$ ${plan.display}');

    try {
      final process = await Process.start(
        plan.executable,
        plan.arguments,
        workingDirectory: project.autoDirectory.path,
        environment: mergedEnvironment,
        runInShell: false,
      );
      _process = process;

      _stdoutSubscription = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_appendOutput);
      _stderrSubscription = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((chunk) => _appendOutput(chunk, prefix: '[stderr] '));

      final code = await process.exitCode;
      await _stdoutSubscription?.cancel();
      await _stderrSubscription?.cancel();

      exitCode.value = code;
      status.value = code == 0 ? 'Completed' : 'Failed';
      _append('Finished with exit code $code.');
      return code;
    } on ProcessException catch (error) {
      exitCode.value = -1;
      status.value = 'Failed to start';
      _append('Failed to start ${script.fileName}: ${error.message}');
      return -1;
    } finally {
      _process = null;
      _stdoutSubscription = null;
      _stderrSubscription = null;
      yesNoPrompt.value = null;
      isRunning.value = false;
      activeScriptPath.value = '';
    }
  }

  void sendInput(String value) {
    final process = _process;
    if (process == null) {
      _append('No active process.');
      return;
    }

    final cleanValue = _sanitizeTerminalOutput(value);

    process.stdin.writeln(value);
    yesNoPrompt.value = null;
    if (_hasOpenLogLine && logLines.isNotEmpty) {
      logLines[logLines.length - 1] = '${logLines.last}$cleanValue';
      _hasOpenLogLine = false;
      _openLogPrefix = '';
      _trimLog();
    } else {
      _append('> $cleanValue');
    }
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) return;

    _append('Stopping active process...');
    process.kill();
  }

  void clearLog() {
    logLines.clear();
    _hasOpenLogLine = false;
    _openLogPrefix = '';
    yesNoPrompt.value = null;
  }

  CommandPlan _commandPlan(ReleaseScript script, List<String> args) {
    if (script.isShellScript) {
      final executable = _bashExecutable();
      return CommandPlan(
        executable: executable,
        arguments: [
          '-c',
          _promptShim,
          'app-release-center',
          script.fileName,
          ...args,
        ],
        displayArguments: [script.fileName, ...args],
      );
    }

    if (script.isDartTool) {
      return CommandPlan(
        executable: 'dart',
        arguments: [script.fileName, ...args],
      );
    }

    if (Platform.isWindows) {
      return CommandPlan(
        executable: 'cmd',
        arguments: ['/c', script.fileName, ...args],
      );
    }

    return CommandPlan(executable: './${script.fileName}', arguments: args);
  }

  String _bashExecutable() {
    if (!Platform.isWindows) return 'bash';

    const candidates = [
      r'C:\Program Files\Git\bin\bash.exe',
      r'C:\Program Files\Git\usr\bin\bash.exe',
      r'C:\Program Files (x86)\Git\bin\bash.exe',
    ];

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }

    return 'bash';
  }

  void _append(String line) {
    if (_hasOpenLogLine) {
      _hasOpenLogLine = false;
      _openLogPrefix = '';
    }
    logLines.add(_sanitizeTerminalOutput(line));
    _trimLog();
    _refreshYesNoPrompt();
  }

  void _appendOutput(String chunk, {String prefix = ''}) {
    if (chunk.isEmpty) return;

    final sanitized = _sanitizeTerminalOutput(chunk);
    if (sanitized.isEmpty) return;

    final normalized = sanitized
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final endsWithNewLine = normalized.endsWith('\n');
    final parts = normalized.split('\n');

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final isLast = i == parts.length - 1;

      if (isLast && part.isEmpty && endsWithNewLine) {
        _hasOpenLogLine = false;
        _openLogPrefix = '';
        continue;
      }

      if (_hasOpenLogLine && _openLogPrefix == prefix && logLines.isNotEmpty) {
        logLines[logLines.length - 1] = '${logLines.last}$part';
      } else {
        logLines.add('$prefix$part');
      }

      _hasOpenLogLine = isLast && !endsWithNewLine;
      _openLogPrefix = _hasOpenLogLine ? prefix : '';
    }

    _trimLog();
    _refreshYesNoPrompt();
  }

  void _trimLog() {
    if (logLines.length > 1500) {
      logLines.removeRange(0, logLines.length - 1500);
    }
  }

  void _refreshYesNoPrompt() {
    if (!isRunning.value || !_hasOpenLogLine || logLines.isEmpty) {
      yesNoPrompt.value = null;
      return;
    }

    final line = logLines.last.trimRight();
    yesNoPrompt.value = _yesNoPromptPattern.hasMatch(line) ? line : null;
  }

  String _sanitizeTerminalOutput(String value) {
    return value
        .replaceAll(_ansiEscapePattern, '')
        .replaceAll(_ansiOscPattern, '')
        .replaceAll(_remainingEscapePattern, '')
        .replaceAll('\u0007', '')
        .replaceAll('\u0008', '');
  }
}

class CommandPlan {
  const CommandPlan({
    required this.executable,
    required this.arguments,
    List<String>? displayArguments,
  }) : displayArguments = displayArguments ?? arguments;

  final String executable;
  final List<String> arguments;
  final List<String> displayArguments;

  String get display {
    return [executable, ...displayArguments].map(_quote).join(' ');
  }

  static String _quote(String value) {
    if (!value.contains(RegExp(r'\s'))) return value;
    return '"${value.replaceAll('"', r'\"')}"';
  }
}

const _promptShim = r'''
read() {
  local prompt=""
  local args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p)
        shift
        prompt="${1-}"
        ;;
      *)
        args+=("$1")
        ;;
    esac
    shift || break
  done

  if [[ -n "$prompt" ]]; then
    printf "%s" "$prompt"
  fi

  builtin read "${args[@]}"
}

export -f read
exec "$BASH" "$@"
''';

const _plainLogEnvironment = {
  'NO_COLOR': '1',
  'CLICOLOR': '0',
  'FASTLANE_DISABLE_COLORS': '1',
};

final _yesNoPromptPattern = RegExp(
  r'(?:^|[\s\[(])(?:y\s*/\s*n|n\s*/\s*y)(?:\]|\))?\s*[:?]?\s*$',
  caseSensitive: false,
);

final _ansiEscapePattern = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
final _ansiOscPattern = RegExp(r'\x1B\][^\x07]*(?:\x07|\x1B\\)');
final _remainingEscapePattern = RegExp(r'\x1B[@-Z\\-_]');
