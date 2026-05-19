import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_release_center/app/models/release_fastlane_lane.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/models/release_script.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

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

    return _runPlan(
      plan: _commandPlan(script, args),
      workingDirectory: project.autoDirectory.path,
      statusLabel: script.fileName,
      activePath: script.path,
      environment: environment,
      clearLog: clearLog,
    );
  }

  Future<int> runFastlaneLane({
    required ReleaseProject project,
    required ReleaseFastlaneLane lane,
    List<String> args = const [],
    Map<String, String> environment = const {},
    bool clearLog = false,
  }) async {
    if (!project.androidDirectory.existsSync()) {
      _append('Project does not contain an android folder.');
      return -1;
    }

    final gemfile = File(
      p.join(project.androidDirectory.path, 'fastlane', 'Gemfile'),
    );
    final bundleExecutable = gemfile.existsSync() ? _bundleExecutable() : null;
    final fastlaneEnvironment = Map<String, String>.from(environment);
    if (bundleExecutable != null) {
      fastlaneEnvironment['BUNDLE_GEMFILE'] = gemfile.path;
    }

    return _runPlan(
      plan: _fastlaneCommandPlan(
        lane,
        args,
        bundleExecutable: bundleExecutable,
      ),
      workingDirectory: project.androidDirectory.path,
      statusLabel: lane.name,
      activePath: lane.key,
      environment: fastlaneEnvironment,
      clearLog: clearLog,
    );
  }

  Future<int> runCommand({
    required String workingDirectory,
    required String statusLabel,
    required String activePath,
    required String executable,
    List<String> arguments = const [],
    List<String>? displayArguments,
    Map<String, String> environment = const {},
    bool clearLog = false,
  }) {
    return _runPlan(
      plan: CommandPlan(
        executable: executable,
        arguments: arguments,
        displayArguments: displayArguments,
      ),
      workingDirectory: workingDirectory,
      statusLabel: statusLabel,
      activePath: activePath,
      environment: environment,
      clearLog: clearLog,
    );
  }

  String resolveFastlaneExecutable() {
    return _fastlaneExecutable();
  }

  String resolveGemExecutable() {
    return _gemExecutable();
  }

  void appendSystemLog(String message) {
    _append(message);
  }

  Future<int> _runPlan({
    required CommandPlan plan,
    required String workingDirectory,
    required String statusLabel,
    required String activePath,
    required Map<String, String> environment,
    required bool clearLog,
  }) async {
    if (isRunning.value) {
      _append('A script is already running.');
      return -1;
    }

    if (clearLog) {
      this.clearLog();
    }

    final mergedEnvironment = Map<String, String>.from(Platform.environment)
      ..addAll(_plainLogEnvironment)
      ..addAll(environment);

    isRunning.value = true;
    status.value = 'Running $statusLabel';
    activeScriptPath.value = activePath;
    exitCode.value = null;
    _append('\$ ${plan.display}');

    try {
      final process = await Process.start(
        plan.executable,
        plan.arguments,
        workingDirectory: workingDirectory,
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
      _append('Failed to start $statusLabel: ${error.message}');
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
      final executable = _dartExecutable();
      return CommandPlan(
        executable: executable,
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

  CommandPlan _fastlaneCommandPlan(
    ReleaseFastlaneLane lane,
    List<String> args, {
    String? bundleExecutable,
  }) {
    final target = [
      if (lane.platform != null) lane.platform!,
      lane.name,
      ...args,
    ];

    if (bundleExecutable != null) {
      return CommandPlan(
        executable: bundleExecutable,
        arguments: ['exec', 'fastlane', ...target],
      );
    }

    return CommandPlan(executable: _fastlaneExecutable(), arguments: target);
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

  String _dartExecutable() {
    if (!Platform.isWindows) return 'dart';

    final fromPath = _resolveFromPath('dart');
    if (fromPath != null) return fromPath;

    final candidates = [
      _candidateFromEnv('DART_SDK', ['bin', 'dart.exe']),
      _candidateFromEnv('DART_SDK', ['bin', 'dart.bat']),
      _candidateFromEnv('FLUTTER_ROOT', [
        'bin',
        'cache',
        'dart-sdk',
        'bin',
        'dart.exe',
      ]),
      _candidateFromEnv('FLUTTER_ROOT', ['bin', 'dart.bat']),
      r'C:\flutter\bin\cache\dart-sdk\bin\dart.exe',
      r'C:\flutter\bin\dart.bat',
      r'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe',
      r'C:\src\flutter\bin\dart.bat',
    ];

    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      if (File(candidate).existsSync()) return candidate;
    }

    // Keep as final fallback for environments where PATH resolution works.
    return 'dart';
  }

  String _fastlaneExecutable() {
    if (!Platform.isWindows) return 'fastlane';

    final fromPath = _resolveFromPath('fastlane');
    if (fromPath != null) return fromPath;

    final candidates = [
      _candidateFromEnv('GEM_HOME', ['bin', 'fastlane.bat']),
      _candidateFromEnv('GEM_HOME', ['bin', 'fastlane.cmd']),
    ];

    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      if (File(candidate).existsSync()) return candidate;
    }

    return 'fastlane';
  }

  String _gemExecutable() {
    if (!Platform.isWindows) return 'gem';

    final fromPath = _resolveFromPath('gem');
    if (fromPath != null) return fromPath;

    final candidates = [
      _candidateFromEnv('GEM_HOME', ['bin', 'gem.bat']),
      _candidateFromEnv('GEM_HOME', ['bin', 'gem.cmd']),
    ];

    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      if (File(candidate).existsSync()) return candidate;
    }

    return 'gem';
  }

  String? _bundleExecutable() {
    if (!Platform.isWindows) return 'bundle';

    final fromPath = _resolveFromPath('bundle');
    if (fromPath != null) return fromPath;

    return null;
  }

  String _candidateFromEnv(String key, List<String> childSegments) {
    final rawRoot = Platform.environment[key]?.trim();
    if (rawRoot == null || rawRoot.isEmpty) return '';
    final root = rawRoot.replaceAll('"', '');
    return p.joinAll([root, ...childSegments]);
  }

  String? _resolveFromPath(String executable) {
    final rawPath = Platform.environment['PATH'];
    if (rawPath == null || rawPath.trim().isEmpty) return null;

    final pathDirs = rawPath
        .split(';')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .map((entry) => entry.replaceAll('"', ''));

    final rawPathExt = Platform.environment['PATHEXT'] ?? '.COM;.EXE;.BAT;.CMD';
    final extensions = rawPathExt
        .split(';')
        .map((ext) => ext.trim())
        .where((ext) => ext.isNotEmpty)
        .toList();

    final executableLower = executable.toLowerCase();
    final hasExtension = extensions.any(
      (ext) => executableLower.endsWith(ext.toLowerCase()),
    );
    final namesToTry = hasExtension
        ? <String>[executable]
        : extensions.map((ext) => '$executable$ext').toList();

    for (final dir in pathDirs) {
      for (final name in namesToTry) {
        final fullPath = p.join(dir, name);
        if (File(fullPath).existsSync()) {
          return fullPath;
        }
      }
    }

    return null;
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
exec 9<&0

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
    printf "%s" "$prompt" >&2
    builtin read "${args[@]}" <&9
  else
    builtin read "${args[@]}"
  fi
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
