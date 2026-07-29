import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_release_center/app/models/release_project.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

class ReleaseNoteGenerationService extends GetxService {
  Future<GeneratedReleaseNotes> generate({
    required ReleaseProject project,
    required String apiKey,
    required String customPrompt,
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw const ReleaseNoteGenerationException('Gemini API key is required.');
    }

    final history = await _collectGitHistory(project.path);
    if (history.commits.isEmpty) {
      throw const ReleaseNoteGenerationException(
        'No git commits were found for release note generation.',
      );
    }

    final appDisplayName = await resolveReleaseNoteAppName(project);
    final version = project.pubspecVersion?.trim();
    final input = _buildGeminiInput(
      project: project,
      history: history,
      customPrompt: customPrompt,
      appDisplayName: appDisplayName,
    );
    var notes = await _requestGeminiReleaseNotes(
      apiKey: trimmedKey,
      input: input,
    );
    if (_shouldRetryReleaseNote(notes, appDisplayName)) {
      notes = await _requestGeminiReleaseNotes(
        apiKey: trimmedKey,
        input: _buildRetryInput(input, notes),
      );
      if (_shouldRetryReleaseNote(notes, appDisplayName)) {
        notes = _fallbackReleaseNote(appDisplayName);
      }
    }

    return GeneratedReleaseNotes(
      notes: notes,
      appDisplayName: appDisplayName,
      version: version == null || version.isEmpty ? null : version,
      gitRangeLabel: history.rangeLabel,
      commitCount: history.commits.length,
      usedFallbackRange: history.usedFallbackRange,
    );
  }

  Future<_GitHistory> _collectGitHistory(String projectPath) async {
    await _runGit(projectPath, const [
      'rev-parse',
      '--show-toplevel',
    ], failureMessage: 'Selected project is not a git repository.');

    final tagResult = await _runGit(projectPath, const [
      'describe',
      '--tags',
      '--abbrev=0',
    ], allowFailure: true);
    final latestTag = tagResult.output.trim();
    final hasTag = tagResult.exitCode == 0 && latestTag.isNotEmpty;
    final args = <String>[
      'log',
      if (hasTag) '$latestTag..HEAD',
      if (!hasTag) '-n',
      if (!hasTag) '20',
      if (hasTag) '-n',
      if (hasTag) '80',
      '--date=short',
      r'--pretty=format:%x1e%h%x1f%ad%x1f%s%x1f%b',
    ];
    final logResult = await _runGit(projectPath, args);
    final commits = _parseCommits(logResult.output);

    return _GitHistory(
      rangeLabel: hasTag ? '$latestTag..HEAD' : 'latest 20 commits',
      commits: commits,
      usedFallbackRange: !hasTag,
    );
  }

  Future<_CommandResult> _runGit(
    String projectPath,
    List<String> arguments, {
    bool allowFailure = false,
    String? failureMessage,
  }) async {
    try {
      final result = await Process.run(
        'git',
        arguments,
        workingDirectory: projectPath,
        runInShell: false,
      );
      final output = '${result.stdout}${result.stderr}'.trim();
      if (!allowFailure && result.exitCode != 0) {
        throw ReleaseNoteGenerationException(
          failureMessage ?? 'Git command failed: $output',
        );
      }
      return _CommandResult(exitCode: result.exitCode, output: output);
    } on ProcessException catch (error) {
      if (allowFailure) {
        return _CommandResult(exitCode: -1, output: error.message);
      }
      throw ReleaseNoteGenerationException(
        failureMessage ?? 'Failed to run git: ${error.message}',
      );
    }
  }

  List<_GitCommit> _parseCommits(String output) {
    final records = output
        .split('\x1e')
        .map((record) => record.trim())
        .where((record) => record.isNotEmpty);
    final commits = <_GitCommit>[];

    for (final record in records) {
      final parts = record.split('\x1f');
      if (parts.length < 3) continue;
      commits.add(
        _GitCommit(
          hash: parts[0].trim(),
          date: parts[1].trim(),
          subject: parts[2].trim(),
          body: parts.length > 3 ? parts.sublist(3).join('\x1f').trim() : '',
        ),
      );
    }

    return commits;
  }

  String _buildGeminiInput({
    required ReleaseProject project,
    required _GitHistory history,
    required String customPrompt,
    required String appDisplayName,
  }) {
    final buffer = StringBuffer()
      ..writeln('Project: ${project.name}')
      ..writeln('App display name: $appDisplayName')
      ..writeln('Version: ${project.pubspecVersion ?? 'unknown'}')
      ..writeln('Git range: ${history.rangeLabel}')
      ..writeln()
      ..writeln('Release note rules:')
      ..writeln('- Start with a warm thank-you sentence using the app name.')
      ..writeln('- End with a short call to update/download and experience it.')
      ..writeln('- Return 2-3 complete Vietnamese sentences.')
      ..writeln('- Write for app users, not developers.')
      ..writeln('- Convert technical commit subjects into user benefits.')
      ..writeln('- Never copy commit subjects verbatim.')
      ..writeln('- Avoid internal words such as architecture, refactor, API,')
      ..writeln('  service, controller, module, database, migration.')
      ..writeln('- If changes are only technical, say that stability and')
      ..writeln('  experience were improved without naming internals.')
      ..writeln()
      ..writeln('User custom prompt:')
      ..writeln(
        customPrompt.trim().isEmpty
            ? defaultReleaseNotePrompt
            : customPrompt.trim(),
      )
      ..writeln()
      ..writeln('Git commits:');

    var totalChars = 0;
    for (final commit in history.commits) {
      final formatted = commit.formatForPrompt();
      if (totalChars + formatted.length > _maxPromptCommitChars) {
        buffer.writeln('- Additional commits omitted to keep prompt compact.');
        break;
      }
      buffer.writeln(formatted);
      totalChars += formatted.length;
    }

    return buffer.toString();
  }

  Future<String> _requestGeminiReleaseNotes({
    required String apiKey,
    required String input,
  }) async {
    final client = HttpClient()..connectionTimeout = _connectionTimeout;

    try {
      final request = await client.postUrl(_geminiInteractionsUri);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.headers.set('x-goog-api-key', apiKey);
      final payload = utf8.encode(
        jsonEncode({
          'model': defaultGeminiReleaseNoteModel,
          'system_instruction': _systemInstruction,
          'input': input,
          'generation_config': {
            'temperature': 0.25,
            'max_output_tokens': _geminiReleaseNoteMaxOutputTokens,
            'thinking_level': 'low',
          },
        }),
      );
      request.contentLength = payload.length;
      request.add(payload);

      final response = await request.close().timeout(_requestTimeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ReleaseNoteGenerationException(
          _geminiErrorMessage(response.statusCode, body),
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const ReleaseNoteGenerationException(
          'Gemini returned an unexpected response.',
        );
      }

      final text = _extractResponseText(decoded).trim();
      if (text.isEmpty) {
        throw const ReleaseNoteGenerationException(
          'Gemini did not return release note text.',
        );
      }

      return _normalizeReleaseNoteText(_stripCodeFence(text));
    } on TimeoutException {
      throw const ReleaseNoteGenerationException('Gemini request timed out.');
    } on SocketException catch (error) {
      throw ReleaseNoteGenerationException(
        'Network error while calling Gemini: ${error.message}',
      );
    } on FormatException {
      throw const ReleaseNoteGenerationException(
        'Gemini returned invalid JSON.',
      );
    } finally {
      client.close(force: true);
    }
  }

  String _extractResponseText(Map response) {
    final outputText = response['output_text'];
    if (outputText is String && outputText.trim().isNotEmpty) {
      return outputText;
    }

    final steps = response['steps'];
    if (steps is List) {
      final parts = <String>[];
      for (final step in steps) {
        if (step is! Map) continue;
        if (step['type'] != 'model_output') continue;
        final content = step['content'];
        if (content is! List) continue;
        for (final item in content) {
          if (item is! Map) continue;
          final text = item['text'];
          if (item['type'] == 'text' && text is String) {
            parts.add(text);
          }
        }
      }
      if (parts.isNotEmpty) return parts.join('\n').trim();
    }

    final candidates = response['candidates'];
    if (candidates is List) {
      final parts = <String>[];
      for (final candidate in candidates) {
        if (candidate is! Map) continue;
        final content = candidate['content'];
        if (content is! Map) continue;
        final candidateParts = content['parts'];
        if (candidateParts is! List) continue;
        for (final part in candidateParts) {
          if (part is! Map) continue;
          final text = part['text'];
          if (text is String) parts.add(text);
        }
      }
      if (parts.isNotEmpty) return parts.join('\n').trim();
    }

    return '';
  }

  String _stripCodeFence(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('```') || !trimmed.endsWith('```')) {
      return trimmed;
    }

    final firstLineBreak = trimmed.indexOf('\n');
    if (firstLineBreak < 0) return trimmed;
    return trimmed.substring(firstLineBreak + 1, trimmed.length - 3).trim();
  }

  String _normalizeReleaseNoteText(String value) {
    final lines = value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) {
          return line
              .trim()
              .replaceFirst(RegExp(r'''^[`'"“”‘’:\-\s•]+'''), '')
              .replaceFirst(_conventionalCommitPrefixPattern, '')
              .trim();
        })
        .where((line) => line.isNotEmpty)
        .toList();

    return lines.join('\n').trim();
  }

  bool _looksInternalReleaseNote(String notes) {
    final normalized = notes.toLowerCase();
    return _internalReleaseNoteTerms.any(normalized.contains);
  }

  bool _shouldRetryReleaseNote(String notes, String appDisplayName) {
    return _looksInternalReleaseNote(notes) ||
        !isUsableGeneratedReleaseNote(
          notes: notes,
          appDisplayName: appDisplayName,
        );
  }

  String _buildRetryInput(String input, String previousOutput) {
    return '$input\n\n'
        'The previous output was incomplete or too technical for Google Play users:\n'
        '$previousOutput\n\n'
        'Rewrite it in 2-3 complete natural Vietnamese sentences for end users. '
        'Do not stop after the thank-you sentence. Do not copy commit '
        'subjects. Do not use words like "triển khai", "kiến trúc", '
        '"refactor", "API", "service", "controller", "module", or "database". '
        'Include a thank-you opening sentence and a final update/download CTA. '
        'If the commits are only internal work, use a concise safe note like '
        '"Cảm ơn bạn đã tin tưởng sử dụng VNeTrip. Phiên bản mới cải thiện độ '
        'ổn định và trải nghiệm sử dụng. Hãy cập nhật ngay để trải nghiệm nhé."';
  }

  String _geminiErrorMessage(int statusCode, String body) {
    var message = body.trim();
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          message = error['message'] as String;
        }
      }
    } catch (_) {
      // Keep the raw response body when it is not JSON.
    }

    final prefix = switch (statusCode) {
      401 || 403 => 'Gemini API key is invalid or lacks permission',
      429 => 'Gemini rate limit exceeded',
      >= 500 => 'Gemini service error',
      _ => 'Gemini request failed',
    };

    if (message.isEmpty) return '$prefix ($statusCode).';
    return '$prefix ($statusCode): $message';
  }
}

class GeneratedReleaseNotes {
  const GeneratedReleaseNotes({
    required this.notes,
    required this.appDisplayName,
    required this.version,
    required this.gitRangeLabel,
    required this.commitCount,
    required this.usedFallbackRange,
  });

  final String notes;
  final String appDisplayName;
  final String? version;
  final String gitRangeLabel;
  final int commitCount;
  final bool usedFallbackRange;
}

class ReleaseNoteGenerationException implements Exception {
  const ReleaseNoteGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _CommandResult {
  const _CommandResult({required this.exitCode, required this.output});

  final int exitCode;
  final String output;
}

class _GitHistory {
  const _GitHistory({
    required this.rangeLabel,
    required this.commits,
    required this.usedFallbackRange,
  });

  final String rangeLabel;
  final List<_GitCommit> commits;
  final bool usedFallbackRange;
}

class _GitCommit {
  const _GitCommit({
    required this.hash,
    required this.date,
    required this.subject,
    required this.body,
  });

  final String hash;
  final String date;
  final String subject;
  final String body;

  String formatForPrompt() {
    final compactBody = body
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(4)
        .join(' ');
    final details = compactBody.isEmpty ? '' : ' Details: $compactBody';
    return '- $date $hash: ${_truncate(subject, 220)}$details';
  }

  String _truncate(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars - 3)}...';
  }
}

const defaultGeminiReleaseNoteModel = 'gemini-3.5-flash';

Future<String> resolveReleaseNoteAppName(ReleaseProject project) async {
  final androidAppName = await readAndroidAppDisplayName(project.path);
  if (androidAppName != null && androidAppName.trim().isNotEmpty) {
    return androidAppName.trim();
  }

  return releaseNoteAppName(project.name);
}

Future<String?> readAndroidAppDisplayName(String projectPath) async {
  final manifest = File(
    p.join(projectPath, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
  );
  if (!manifest.existsSync()) return null;

  try {
    final label = parseAndroidManifestLabel(await manifest.readAsString());
    if (label == null || label.trim().isEmpty) return null;

    final stringName = androidStringResourceName(label);
    if (stringName != null) {
      return _readAndroidStringResource(projectPath, stringName);
    }

    if (label.trim().startsWith('@')) return null;
    return normalizeAndroidResourceText(label);
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

String? parseAndroidManifestLabel(String source) {
  final applicationTag = RegExp(
    r'<application\b[^>]*>',
    dotAll: true,
  ).firstMatch(_removeXmlComments(source))?.group(0);
  if (applicationTag == null) return null;

  return _parseXmlAttribute(applicationTag, 'android:label') ??
      _parseXmlAttribute(applicationTag, 'label');
}

String? parseAndroidStringResource(String source, String name) {
  final cleaned = _removeXmlComments(source);
  final escapedName = RegExp.escape(name);
  final stringPattern = RegExp(
    '<string\\b(?=[^>]*\\bname\\s*=\\s*["\']$escapedName["\'])[^>]*>'
    r'(.*?)</string>',
    dotAll: true,
  );
  final match = stringPattern.firstMatch(cleaned);
  if (match == null) return null;

  return normalizeAndroidResourceText(match.group(1) ?? '');
}

String? androidStringResourceName(String value) {
  final match = RegExp(r'^@string/([A-Za-z0-9_.]+)$').firstMatch(value.trim());
  return match?.group(1);
}

String _fallbackReleaseNote(String appName) {
  return 'Cảm ơn bạn đã tin tưởng sử dụng $appName.\n'
      'Phiên bản mới cải thiện độ ổn định và trải nghiệm sử dụng.\n'
      'Hãy cập nhật ngay để trải nghiệm nhé.';
}

String releaseNoteAppName(String projectName) {
  final normalized = projectName.toLowerCase();
  if (normalized.contains('vnetrip') || normalized.contains('vntrip')) {
    return 'VNeTrip';
  }
  return projectName
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

bool isUsableGeneratedReleaseNote({
  required String notes,
  required String appDisplayName,
}) {
  final trimmed = notes.trim();
  if (trimmed.runes.length < _minimumGeneratedReleaseNoteRunes) {
    return false;
  }

  if (_commitHashOnlyPattern.hasMatch(trimmed) ||
      _analysisLeakPattern.hasMatch(trimmed)) {
    return false;
  }

  final normalized = trimmed.toLowerCase();
  final normalizedAppName = appDisplayName.trim().toLowerCase();
  if (normalizedAppName.isNotEmpty && !normalized.contains(normalizedAppName)) {
    return false;
  }

  if (!_releaseNoteCtaPattern.hasMatch(normalized)) {
    return false;
  }

  if (_incompleteThankYouPattern.hasMatch(normalized)) {
    return false;
  }

  return true;
}

Future<String?> _readAndroidStringResource(
  String projectPath,
  String name,
) async {
  final valuesDirectory = Directory(
    p.join(projectPath, 'android', 'app', 'src', 'main', 'res', 'values'),
  );
  if (!valuesDirectory.existsSync()) return null;

  final files = <File>[];
  final preferred = File(p.join(valuesDirectory.path, 'strings.xml'));
  if (preferred.existsSync()) files.add(preferred);

  try {
    final otherFiles =
        valuesDirectory
            .listSync()
            .whereType<File>()
            .where((file) => p.extension(file.path).toLowerCase() == '.xml')
            .where((file) => !p.equals(file.path, preferred.path))
            .toList()
          ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    files.addAll(otherFiles);
  } on FileSystemException {
    return null;
  }

  for (final file in files) {
    try {
      final value = parseAndroidStringResource(await file.readAsString(), name);
      if (value != null && value.trim().isNotEmpty) return value.trim();
    } on FileSystemException {
      continue;
    } on FormatException {
      continue;
    }
  }

  return null;
}

String? _parseXmlAttribute(String tag, String name) {
  final escapedName = RegExp.escape(name);
  final doubleQuoted = RegExp(
    '\\b$escapedName\\s*=\\s*"([^"]*)"',
    dotAll: true,
  ).firstMatch(tag);
  if (doubleQuoted != null) {
    return normalizeAndroidResourceText(doubleQuoted.group(1) ?? '');
  }

  final singleQuoted = RegExp(
    "\\b$escapedName\\s*=\\s*'([^']*)'",
    dotAll: true,
  ).firstMatch(tag);
  if (singleQuoted != null) {
    return normalizeAndroidResourceText(singleQuoted.group(1) ?? '');
  }

  return null;
}

String normalizeAndroidResourceText(String value) {
  final withoutCdata = value.replaceAllMapped(
    RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true),
    (match) => match.group(1) ?? '',
  );
  final withoutTags = withoutCdata.replaceAll(RegExp(r'<[^>]+>'), '');
  return _decodeXmlEntities(withoutTags)
      .replaceAllMapped(RegExp(r'\\u([0-9A-Fa-f]{4})'), (match) {
        final codePoint = int.tryParse(match.group(1)!, radix: 16);
        return codePoint == null
            ? match.group(0)!
            : String.fromCharCode(codePoint);
      })
      .replaceAll(r'\n', ' ')
      .replaceAll(r'\t', ' ')
      .replaceAll(r'\"', '"')
      .replaceAll(r"\'", "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _removeXmlComments(String source) {
  return source.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
}

String _decodeXmlEntities(String value) {
  return value
      .replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (match) {
        final codePoint = int.tryParse(match.group(1)!, radix: 16);
        return codePoint == null
            ? match.group(0)!
            : String.fromCharCode(codePoint);
      })
      .replaceAllMapped(RegExp(r'&#([0-9]+);'), (match) {
        final codePoint = int.tryParse(match.group(1)!);
        return codePoint == null
            ? match.group(0)!
            : String.fromCharCode(codePoint);
      })
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}

const defaultReleaseNotePrompt =
    'Write concise Vietnamese Google Play release notes for app users. '
    'Start with a warm thank-you sentence using the app name, for example '
    '"Cảm ơn bạn đã tin tưởng sử dụng VNeTrip." End with a short call to '
    'update or download the latest version, for example "Hãy cập nhật phiên '
    'bản mới để trải nghiệm nhé." Turn technical commits into user-facing '
    'benefits. Focus on visible improvements and bug fixes. Never copy commit '
    'subjects verbatim. Do not mention commit hashes, architecture, refactors, '
    'APIs, services, modules, controllers, databases, or other implementation '
    'details. Do not invent changes. Keep the final text under 500 Unicode '
    'characters.';

const _systemInstruction =
    'You generate mobile app release notes from git history. Write only the '
    'release note text. Do not include headings, markdown fences, commit '
    'hashes, internal branch names, or implementation-only details. The text '
    'must start with a warm thank-you sentence using the app display name and '
    'must end with a short update/download call to action. Never copy commit '
    'subjects verbatim. Avoid technical wording such as triển khai, kiến trúc, '
    'refactor, API, service, controller, module, database, and migration. If '
    'commits are mostly internal, summarize them as stability or experience '
    'improvements. Keep it truthful, user-facing, concise, and under 500 '
    'Unicode characters.';

const _maxPromptCommitChars = 30000;
const _geminiReleaseNoteMaxOutputTokens = 2048;
const _minimumGeneratedReleaseNoteRunes = 45;
const _connectionTimeout = Duration(seconds: 20);
const _requestTimeout = Duration(seconds: 60);
final _geminiInteractionsUri = Uri.parse(
  'https://generativelanguage.googleapis.com/v1beta/interactions',
);

final _conventionalCommitPrefixPattern = RegExp(
  r'^(?:feat|fix|chore|refactor|perf|build|ci|docs|test|style)'
  r'(?:\([^)]+\))?!?:\s*',
  caseSensitive: false,
);
final _releaseNoteCtaPattern = RegExp(
  r'(cập nhật|tải|download|trải nghiệm|khám phá)',
  caseSensitive: false,
);
final _commitHashOnlyPattern = RegExp(
  r'''^[\s`'",.;:\-\[\]()]*[0-9a-f]{6,40}[\s`'",.;:\-\[\](),]*$''',
  caseSensitive: false,
);
final _analysisLeakPattern = RegExp(
  r'(^|\n)\s*\d+\.\s+\*\*|final polish|no markdown|plain text',
  caseSensitive: false,
);
final _incompleteThankYouPattern = RegExp(
  r'cảm ơn bạn đã tin tưởng sử dụng\s*$',
  caseSensitive: false,
);

const _internalReleaseNoteTerms = [
  'triển khai kiến trúc',
  'kiến trúc',
  'refactor',
  'api',
  'service',
  'controller',
  'module',
  'database',
  'migration',
  'schema',
  'repository',
  'endpoint',
  'commit',
];
