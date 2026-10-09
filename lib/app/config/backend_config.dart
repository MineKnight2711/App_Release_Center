import 'dart:io';

/// Location of the App Management Center API (Cloudflare Worker `amc-api`).
///
/// Override order: `--dart-define=AMC_API_BASE_URL=...`, process environment,
/// `.env` files, then [defaultApiBaseUrl].
class BackendConfig {
  const BackendConfig({required this.apiBaseUrl});

  static const defaultApiBaseUrl = 'https://amc-api.huynhphuocdat2.workers.dev';
  static const _apiBaseUrlKey = 'AMC_API_BASE_URL';
  static const _dartDefineApiBaseUrl = String.fromEnvironment(_apiBaseUrlKey);

  final Uri apiBaseUrl;

  static Future<BackendConfig> load() async {
    final dotenv = await _readDotEnvValues();
    final configured = _value(dotenv);
    return BackendConfig(
      apiBaseUrl: parseApiBaseUrl(
        configured.isEmpty ? defaultApiBaseUrl : configured,
      ),
    );
  }

  /// Requires https, except plain http to a local `wrangler dev` server.
  static Uri parseApiBaseUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    final isLocal =
        uri != null &&
        (uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '::1');
    if (uri == null ||
        uri.host.isEmpty ||
        !(uri.scheme == 'https' || (uri.scheme == 'http' && isLocal))) {
      throw FormatException(
        '$_apiBaseUrlKey phải là URL https (http chỉ dùng cho localhost). '
        'Sửa giá trị rồi build và mở lại app.',
      );
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path.replaceFirst(RegExp(r'/+$'), ''),
    );
  }

  static String _value(Map<String, String> dotenv) {
    final fromDefine = _dartDefineApiBaseUrl.trim();
    if (fromDefine.isNotEmpty) return fromDefine;

    final fromEnv = Platform.environment[_apiBaseUrlKey]?.trim() ?? '';
    if (fromEnv.isNotEmpty) return fromEnv;

    return dotenv[_apiBaseUrlKey]?.trim() ?? '';
  }

  static Future<Map<String, String>> _readDotEnvValues() async {
    final values = <String, String>{};
    for (final file in _envFiles()) {
      try {
        if (!file.existsSync()) continue;
        for (final line in await file.readAsLines()) {
          final match = RegExp(
            r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$',
          ).firstMatch(line);
          if (match == null) continue;
          values.putIfAbsent(
            match.group(1)!,
            () => _decodeEnvValue(match.group(2) ?? ''),
          );
        }
      } on FileSystemException {
        // Sandboxed builds may not be allowed to read a candidate location.
        continue;
      }
    }
    return values;
  }

  static List<File> _envFiles() {
    final files = <File>[File('.env')];

    final executableDirectory = File(Platform.resolvedExecutable).parent;
    files.add(File('${executableDirectory.path}${Platform.pathSeparator}.env'));

    final appData = Platform.environment['APPDATA']?.trim();
    if (appData != null && appData.isNotEmpty) {
      // The pre-rebrand directory is still searched after the rename.
      for (final directoryName in const [
        'App Management Center',
        'App Release Center',
      ]) {
        files.add(
          File(
            '$appData${Platform.pathSeparator}$directoryName'
            '${Platform.pathSeparator}.env',
          ),
        );
      }
    }

    final seen = <String>{};
    return files
        .where((file) => seen.add(file.absolute.path.toLowerCase()))
        .toList(growable: false);
  }

  static String _decodeEnvValue(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.length >= 2) {
      final quote = trimmed[0];
      if ((quote == '"' || quote == "'") && trimmed.endsWith(quote)) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }

    final commentStart = trimmed.indexOf(' #');
    return commentStart >= 0
        ? trimmed.substring(0, commentStart).trimRight()
        : trimmed;
  }
}
