import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/automation_models.dart';
import '../models/scenario_models.dart';

class FlowCompileException implements Exception {
  const FlowCompileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Writes the Maestro flow a test case's steps describe.
///
/// The flow is plain YAML under `.fiza-qa/flows/`, readable and runnable
/// without QA Desk. Account values are never written into it: they arrive at
/// run time as `MAESTRO_QA_*` process variables.
class FlowCompiler {
  const FlowCompiler();

  /// Screenshot taken right after the login flow; its presence afterwards
  /// tells a failed login apart from a failure later in the scenario.
  static const loginMarker = 'qa-login-ok';

  /// Where a scenario's flow lives, relative to `.fiza-qa/`.
  static String flowPathFor(TestScenario scenario) =>
      'flows/${_fileSafe(scenario.id)}.yaml';

  String compile(TestScenario scenario, QaApp app) {
    final spec = scenario.automation;
    if (spec == null) {
      throw const FlowCompileException('Test case này không tự thao tác.');
    }
    final flowPath = spec.flow.isEmpty ? flowPathFor(scenario) : spec.flow;
    final buffer = StringBuffer()
      ..writeln(
        '# Sinh bởi QA Desk từ test case "${_oneLine(scenario.title)}". '
        'Sửa các bước trong QA Desk: lưu lại sẽ ghi đè file này.',
      )
      ..writeln(
        r'# Chữ khớp trọn một dòng của phần tử: (?s)(?:.*\n)?…(?:\n.*)?, '
        'vì Flutter gộp chữ của cả một thẻ thành nhiều dòng.',
      )
      ..writeln(
        app.platform == QaAppPlatform.web
            ? r'url: ${MAESTRO_QA_APP_URL}'
            : r'appId: ${MAESTRO_QA_APP_ID}',
      )
      ..writeln('name: ${_quote(flowName(scenario.title))}')
      ..writeln('---');
    for (final step in spec.steps) {
      buffer.write(_step(step, app, flowPath));
    }
    return buffer.toString();
  }

  /// The flow QA Desk runs to check an account: the app's login flow alone.
  ///
  /// It is written outside the repository, so it names the login flow by
  /// [loginFlowPath], an absolute path.
  String loginCheck(QaApp app, String loginFlowPath) {
    if (app.loginFlow.isEmpty) {
      throw FlowCompileException('App "${app.name}" chưa khai flow đăng nhập.');
    }
    return [
      '# Sinh bởi QA Desk: chỉ kiểm tra đăng nhập.',
      app.platform == QaAppPlatform.web
          ? r'url: ${MAESTRO_QA_APP_URL}'
          : r'appId: ${MAESTRO_QA_APP_ID}',
      'name: ${_quote(flowName('Thử đăng nhập · ${app.name}'))}',
      '---',
      '- launchApp:',
      '    clearState: true',
      '- runFlow: ${_quote(loginFlowPath.replaceAll(r'\', '/'))}',
      '- takeScreenshot: $loginMarker',
      '',
    ].join('\n');
  }

  String _step(AutomationStep step, QaApp app, String flowPath) {
    final target = step.target.trim();
    final text = textSelector(target, partial: step.partial);
    String selector(String key) => step.byId
        ? '$key:\n    id: ${_quote(target)}\n'
        : '$key: ${_quote(text)}\n';

    switch (step.type) {
      case AutomationStepType.launch:
        return step.clearState
            ? '- launchApp:\n    clearState: true\n'
            : '- launchApp\n';
      case AutomationStepType.login:
        if (app.loginFlow.isEmpty) {
          throw FlowCompileException(
            'App "${app.name}" chưa khai flow đăng nhập (login) trong '
            'project.yaml.',
          );
        }
        return '- runFlow: ${_quote(_relativeFlow(app.loginFlow, flowPath))}\n'
            '- takeScreenshot: $loginMarker\n';
      case AutomationStepType.tap:
        _require(target, step);
        return '- ${selector('tapOn')}';
      case AutomationStepType.input:
        final focus = target.isEmpty
            ? ''
            : '- ${selector('tapOn')}'
                  // Typing into a field that is still animating in loses the
                  // first characters, and apps prefill fields such as a
                  // remembered phone number: wait, then clear.
                  '- waitForAnimationToEnd\n'
                  '- eraseText\n';
        return '$focus- inputText: ${_quote(step.value)}\n';
      case AutomationStepType.assertVisible:
        _require(target, step);
        return '- ${selector('assertVisible')}';
      case AutomationStepType.assertNotVisible:
        _require(target, step);
        return '- ${selector('assertNotVisible')}';
      case AutomationStepType.waitFor:
        _require(target, step);
        final element = step.byId
            ? '      id: ${_quote(target)}\n'
            : '      text: ${_quote(text)}\n';
        return '- extendedWaitUntil:\n    visible:\n$element'
            '    timeout: 20000\n';
      case AutomationStepType.scrollTo:
        _require(target, step);
        final element = step.byId
            ? '      id: ${_quote(target)}\n'
            : '      text: ${_quote(text)}\n';
        return '- scrollUntilVisible:\n    element:\n$element';
      case AutomationStepType.back:
        return '- back\n';
      case AutomationStepType.screenshot:
        _require(target, step);
        return '- takeScreenshot: ${_quote(_fileSafe(target))}\n';
      case AutomationStepType.runFlow:
        _require(target, step);
        return '- runFlow: ${_quote(_relativeFlow(target, flowPath))}\n';
    }
  }

  static void _require(String target, AutomationStep step) {
    if (target.isEmpty) {
      throw FlowCompileException('Bước "${step.type.label}" thiếu đích.');
    }
  }

  /// The regular expression a step's label becomes.
  ///
  /// Maestro wants the expression to match an element's whole text, and
  /// Flutter merges the text of a card into one element, one line each
  /// ("Ca hôm nay\n…\nTổng đơn hàng\n0"). So a label matches a whole line of
  /// an element, or with [partial] any part of it. Labels such as
  /// "Tổng (VNĐ)" match literally; `${…}` variables are left for Maestro.
  static String textSelector(String text, {bool partial = false}) {
    final pattern = text.contains(r'${') ? text : RegExp.escape(text);
    return partial ? '(?s).*$pattern.*' : '(?s)(?:.*\\n)?$pattern(?:\\n.*)?';
  }

  /// The label [textSelector] made [pattern] from, for reading results;
  /// a pattern written by hand comes back as it is.
  static ({String text, bool partial}) readSelector(String pattern) {
    String unescape(String value) =>
        value.replaceAllMapped(RegExp(r'\\(.)'), (match) => match[1]!);
    const lineStart = r'(?s)(?:.*\n)?';
    const lineEnd = r'(?:\n.*)?';
    if (pattern.startsWith(lineStart) && pattern.endsWith(lineEnd)) {
      return (
        text: unescape(
          pattern.substring(lineStart.length, pattern.length - lineEnd.length),
        ),
        partial: false,
      );
    }
    if (pattern.startsWith('(?s).*') &&
        pattern.endsWith('.*') &&
        pattern.length >= 8) {
      return (
        text: unescape(pattern.substring(6, pattern.length - 2)),
        partial: true,
      );
    }
    return (text: unescape(pattern), partial: false);
  }

  /// Single-quoted YAML: no escape sequences, so backslashes from the regex
  /// escaping survive and `${…}` stays for Maestro to fill in.
  static String _quote(String value) => "'${value.replaceAll("'", "''")}'";

  /// [title] as a flow name. Maestro names a folder of its output after
  /// the flow, so a character Windows forbids in a path (a title such as
  /// "Đơn hàng: tạo nháp") made it fail before running anything.
  static String flowName(String title) {
    final name = _oneLine(title)
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '-')
        .replaceAll(RegExp(r'[. ]+$'), '');
    return name.isEmpty ? 'flow' : name;
  }

  static String _oneLine(String value) =>
      value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

  /// [target] and [from] are both relative to `.fiza-qa/`; Maestro resolves
  /// `runFlow` paths against the flow that names them.
  static String _relativeFlow(String target, String from) => p.posix.relative(
    p.posix.normalize(target.replaceAll(r'\', '/')),
    from: p.posix.dirname(from.replaceAll(r'\', '/')),
  );

  static String _fileSafe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
}

/// Finds the labels a flow would tap that the app forbids on production.
///
/// Reads the flow and every flow it runs. It can only see what the YAML
/// names: a selector by id or a coordinate tap cannot be judged, which is why
/// production accounts must also lack write permission at the backend.
class ProductionGuard {
  const ProductionGuard();

  List<String> guardedTaps(File flow, List<String> guard) {
    if (guard.isEmpty) return const [];
    final folded = {for (final label in guard) label: _fold(label)};
    final hits = <String>{};
    for (final text in _tapTexts(flow, <String>{})) {
      final value = _fold(FlowCompiler.readSelector(text).text);
      for (final entry in folded.entries) {
        if (entry.value.isNotEmpty && value.contains(entry.value)) {
          hits.add(entry.key);
        }
      }
    }
    return hits.toList()..sort();
  }

  Iterable<String> _tapTexts(File flow, Set<String> seen) sync* {
    final path = p.normalize(flow.absolute.path).toLowerCase();
    if (!seen.add(path) || !flow.existsSync()) return;
    final documents = loadYamlDocuments(flow.readAsStringSync());
    final commands = documents.isEmpty ? null : documents.last.contents;
    if (commands is! YamlList) return;
    yield* _commandTexts(commands, flow, seen);
  }

  Iterable<String> _commandTexts(
    YamlList commands,
    File flow,
    Set<String> seen,
  ) sync* {
    for (final command in commands) {
      if (command is! YamlMap) continue;
      for (final entry in command.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (const {'tapOn', 'longPressOn', 'doubleTapOn'}.contains(key)) {
          if (value is String) yield value;
          if (value is YamlMap && value['text'] != null) {
            yield value['text'].toString();
          }
        } else if (key == 'runFlow') {
          final file = value is String
              ? value
              : value is YamlMap
              ? value['file']?.toString()
              : null;
          if (file != null) {
            yield* _tapTexts(File(p.join(p.dirname(flow.path), file)), seen);
          }
          if (value is YamlMap && value['commands'] is YamlList) {
            yield* _commandTexts(value['commands'] as YamlList, flow, seen);
          }
        } else if (const {'repeat', 'retry'}.contains(key) &&
            value is YamlMap &&
            value['commands'] is YamlList) {
          yield* _commandTexts(value['commands'] as YamlList, flow, seen);
        }
      }
    }
  }
}

/// Lowercase without Vietnamese diacritics or repeated spaces, so "Xoá" and
/// "XOA" match.
String _fold(String value) {
  final lower = value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_folding[char] ?? char);
  }
  return buffer.toString();
}

const _folding = <String, String>{
  'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a', //
  'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a', //
  'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a', //
  'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e', //
  'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e', //
  'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i', //
  'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o', //
  'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o', //
  'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o', //
  'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u', //
  'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u', //
  'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y', 'đ': 'd', //
};
