import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Replaces secret values with a mask wherever QA Desk writes them down.
///
/// Maestro prints the values it typed in failure messages, its JUnit report,
/// `commands.json` and its own log, so every one of those passes through here
/// before anyone reads it.
class SecretRedactor {
  SecretRedactor(Iterable<String> secrets)
    : _secrets =
          secrets
              .where((value) => value.length >= minimumLength)
              .toSet()
              .toList()
            // Longest first, so a secret containing another is masked whole.
            ..sort((a, b) => b.length.compareTo(a.length));

  /// Shorter values would mask ordinary words and digits all over the log.
  static const minimumLength = 3;
  static const mask = '••••';

  final List<String> _secrets;

  bool get isEmpty => _secrets.isEmpty;

  String redact(String text) {
    var result = text;
    for (final secret in _secrets) {
      if (result.contains(secret)) result = result.replaceAll(secret, mask);
    }
    return result;
  }

  /// Masks the text files under [directory] in place; images are left alone.
  Future<int> redactDirectory(Directory directory) async {
    if (isEmpty || !directory.existsSync()) return 0;
    var changed = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File || !_textExtensions.contains(_extension(entity))) {
        continue;
      }
      if (await _redactText(entity)) changed++;
    }
    return changed;
  }

  Future<void> redactFile(File file) async {
    if (isEmpty || !file.existsSync()) return;
    await _redactText(file);
  }

  /// Masks one file; true when it held a secret. A file that is not valid
  /// UTF-8 (a tool writing the ANSI code page) is still searched rather
  /// than skipped with the secret in it.
  Future<bool> _redactText(File file) async {
    final original = utf8.decode(
      await file.readAsBytes(),
      allowMalformed: true,
    );
    final masked = redact(original);
    if (masked == original) return false;
    await file.writeAsString(masked, flush: true);
    return true;
  }

  static String _extension(File file) => p.extension(file.path).toLowerCase();

  static const _textExtensions = {'.json', '.xml', '.log', '.txt', '.html'};
}
