import 'package:app_management_center/app/config/backend_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default API URL is a valid https endpoint', () {
    final uri = BackendConfig.parseApiBaseUrl(BackendConfig.defaultApiBaseUrl);
    expect(uri.scheme, 'https');
  });

  test('normalizes trailing slashes and drops query strings', () {
    expect(
      BackendConfig.parseApiBaseUrl('https://api.example.com/base///?x=1#y'),
      Uri.parse('https://api.example.com/base'),
    );
  });

  test('allows plain http only for a local wrangler dev server', () {
    expect(BackendConfig.parseApiBaseUrl('http://localhost:8787').port, 8787);
    for (final value in ['http://api.example.com', 'ftp://x', '', 'nope']) {
      expect(
        () => BackendConfig.parseApiBaseUrl(value),
        throwsA(isA<FormatException>()),
        reason: value,
      );
    }
  });
}
