import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'flow_compiler.dart';

/// One command Maestro ran, as `commands.json` records it.
class FlowStepResult {
  const FlowStepResult({
    required this.label,
    required this.status,
    required this.durationMs,
    required this.depth,
    this.error = '',
  });

  final String label;

  /// `COMPLETED`, `FAILED`, `SKIPPED`…, as Maestro writes it.
  final String status;
  final int durationMs;

  /// 0 for the scenario's own steps, deeper inside flows it runs.
  final int depth;
  final String error;

  bool get failed => status == 'FAILED';

  Map<String, dynamic> toJson() => {
    'label': label,
    'status': status,
    'durationMs': durationMs,
    'depth': depth,
    if (error.isNotEmpty) 'error': error,
  };

  factory FlowStepResult.fromJson(Map<String, dynamic> json) => FlowStepResult(
    label: json['label']?.toString() ?? '',
    status: json['status']?.toString() ?? '',
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    depth: (json['depth'] as num?)?.toInt() ?? 0,
    error: json['error']?.toString() ?? '',
  );
}

/// What a finished Maestro run left behind, read from its output folder.
class MaestroRunReport {
  const MaestroRunReport({
    required this.steps,
    this.failureScreenshot,
    this.loggedIn = false,
    this.usedLogin = false,
    this.loginStepFailed = false,
  });

  final List<FlowStepResult> steps;
  final String? failureScreenshot;

  /// The login marker screenshot exists: the account got in.
  final bool loggedIn;

  /// The scenario runs the login flow at all.
  final bool usedLogin;

  /// The login flow itself failed. Maestro lists only the commands it got
  /// to, so the marker's absence alone cannot tell this apart from a
  /// failure before login, such as the app not starting.
  final bool loginStepFailed;

  /// The account, not the app, is the first suspect.
  bool get loginFailed => usedLogin && !loggedIn && loginStepFailed;

  FlowStepResult? get failedStep {
    for (final step in steps.reversed) {
      if (step.failed) return step;
    }
    return null;
  }
}

/// Reads Maestro's `--test-output-dir`: the commands it ran with their
/// status, the screenshot of the failing step, and whether login got through.
class MaestroResultReader {
  const MaestroResultReader();

  /// [loginFlow] is the app's login flow when the scenario logs in, empty
  /// when it does not.
  MaestroRunReport read(Directory outputDirectory, {String loginFlow = ''}) {
    if (!outputDirectory.existsSync()) {
      return const MaestroRunReport(steps: []);
    }
    final files = outputDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .toList();
    File? commandsFile;
    for (final file in files) {
      if (p.basename(file.path) == 'commands.json') commandsFile = file;
    }
    final steps = commandsFile == null
        ? const <FlowStepResult>[]
        : parseCommands(commandsFile.readAsStringSync());
    String? failure;
    var loggedIn = false;
    for (final file in files) {
      final name = p.basename(file.path);
      final folder = p.basename(p.dirname(file.path));
      if (name == '${FlowCompiler.loginMarker}.png') loggedIn = true;
      if (folder == 'screenshots' && name.endsWith('.png')) {
        failure = file.path;
      }
    }
    final loginName = p.basename(loginFlow.replaceAll(r'\', '/'));
    return MaestroRunReport(
      steps: steps,
      failureScreenshot: failure,
      loggedIn: loggedIn,
      usedLogin: loginFlow.isNotEmpty,
      loginStepFailed:
          loginFlow.isNotEmpty &&
          steps.any(
            (step) =>
                step.failed &&
                step.depth == 0 &&
                step.label.startsWith(_runFlowLabel) &&
                step.label.endsWith(loginName),
          ),
    );
  }

  /// The commands worth showing. Labels come from the command as written,
  /// with `${…}` still in place, never from the evaluated copy that holds
  /// the typed values.
  List<FlowStepResult> parseCommands(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final steps = <FlowStepResult>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final command = item['command'];
      final metadata = item['metadata'];
      if (command is! Map || command.isEmpty || metadata is! Map) continue;
      final name = command.keys.first.toString();
      if (_hidden.contains(name)) continue;
      final body = command.values.first;
      final error = metadata['error'];
      steps.add(
        FlowStepResult(
          label: describe(name, body is Map ? body : const {}),
          status: metadata['status']?.toString() ?? '',
          durationMs: (metadata['duration'] as num?)?.toInt() ?? 0,
          depth: (metadata['depth'] as num?)?.toInt() ?? 0,
          error: error is Map ? error['message']?.toString() ?? '' : '',
        ),
      );
    }
    return steps;
  }

  static const _runFlowLabel = 'Chạy flow';

  static const _hidden = {
    'defineVariablesCommand',
    'applyConfigurationCommand',
  };

  static String describe(String name, Map<dynamic, dynamic> body) {
    String selector(dynamic value) {
      if (value is! Map) return '';
      final text = value['textRegex'] ?? value['text'];
      final id = value['idRegex'] ?? value['id'];
      if (text != null) {
        final label = FlowCompiler.readSelector(text.toString());
        return label.partial ? 'chữ có "${label.text}"' : '"${label.text}"';
      }
      if (id != null) return 'id "${_unescape(id.toString())}"';
      return '';
    }

    return switch (name) {
      'launchAppCommand' =>
        body['clearState'] == true ? 'Mở app, xoá dữ liệu cũ' : 'Mở app',
      // A `runFlow` with `when:` and inline commands has no file to name.
      'runFlowCommand' when body['sourceDescription'] == null =>
        'Nhóm bước có điều kiện',
      'runFlowCommand' => '$_runFlowLabel ${body['sourceDescription']}',
      'tapOnElement' => 'Bấm ${selector(body['selector'])}',
      'inputTextCommand' => 'Nhập "${body['text'] ?? ''}"',
      'assertConditionCommand' => _condition(body['condition'], selector),
      'takeScreenshotCommand' =>
        p.basename(body['path']?.toString() ?? '') == FlowCompiler.loginMarker
            ? 'Đã qua đăng nhập'
            : 'Chụp màn hình ${p.basename(body['path']?.toString() ?? '')}',
      'waitForAnimationToEndCommand' => 'Chờ hết chuyển cảnh',
      'backPressCommand' => 'Quay lại',
      'eraseTextCommand' => 'Xoá chữ trong ô',
      'hideKeyboardCommand' => 'Ẩn bàn phím',
      'stopAppCommand' => 'Đóng app',
      'scrollUntilVisibleCommand' => 'Cuộn tới ${selector(body['selector'])}',
      _ => name.replaceAll('Command', ''),
    };
  }

  static String _condition(dynamic condition, String Function(dynamic) sel) {
    if (condition is! Map) return 'Kiểm tra';
    if (condition['visible'] != null) {
      return 'Thấy ${sel(condition['visible'])}';
    }
    if (condition['notVisible'] != null) {
      return 'Không thấy ${sel(condition['notVisible'])}';
    }
    return 'Kiểm tra';
  }

  /// Back from the regex form QA Desk writes labels in.
  static String _unescape(String value) =>
      value.replaceAllMapped(RegExp(r'\\(.)'), (match) => match[1]!);
}
