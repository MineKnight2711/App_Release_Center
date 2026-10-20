import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AnalyticsHttpException implements Exception {
  const AnalyticsHttpException(this.status, {this.retryAfter});
  final int status;
  final Duration? retryAfter;
}

/// Telemetry failures must not invoke AmcApiClient.onUnauthorized (logout).
class AnalyticsTransport {
  AnalyticsTransport({
    required this.baseUrl,
    required this.readToken,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final Uri baseUrl;
  final Future<String?> Function() readToken;
  final http.Client Function() _clientFactory;
  final _active = <http.Client>{};
  int _generation = 0;

  void cancel() {
    _generation++;
    for (final client in _active) {
      client.close();
    }
    _active.clear();
  }

  Future<Map<String, Object?>> request(
    String path, {
    Map<String, Object?>? body,
  }) async {
    final generation = _generation;
    final token = await readToken();
    if (generation != _generation || token == null || token.isEmpty) {
      throw const AnalyticsHttpException(401);
    }
    final route = Uri.parse('${baseUrl.path}/v1/analytics/$path');
    final uri = baseUrl.replace(
      path: route.path,
      query: route.hasQuery ? route.query : null,
    );
    final client = _clientFactory();
    _active.add(client);
    try {
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response =
          await (body == null
                  ? client.get(uri, headers: headers)
                  : client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 15));
      if (generation != _generation) throw const AnalyticsHttpException(401);
      if (response.statusCode != 200) {
        final header = response.headers['retry-after'];
        final seconds = int.tryParse(header ?? '');
        DateTime? date;
        if (header != null && seconds == null) {
          try {
            date = HttpDate.parse(header);
          } on FormatException {
            /* Retry with backoff. */
          }
        }
        throw AnalyticsHttpException(
          response.statusCode,
          retryAfter: seconds != null
              ? Duration(seconds: seconds)
              : date?.difference(DateTime.now().toUtc()),
        );
      }
      return Map<String, Object?>.from(jsonDecode(response.body) as Map);
    } finally {
      _active.remove(client);
      client.close();
    }
  }
}
