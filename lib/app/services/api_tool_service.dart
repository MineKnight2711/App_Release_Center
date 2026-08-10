import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_release_center/app/models/api_tool.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

const defaultApiToolRequestTimeout = Duration(seconds: 30);
const apiToolMaxResponseBodyBytes = 2 * 1024 * 1024;

abstract class ApiToolHttpClient {
  Future<ApiToolResponse> send(
    ApiToolRequest request, {
    required Duration timeout,
    ApiToolCancellationToken? cancelToken,
  });
}

class ApiToolCancellationToken {
  bool _isCanceled = false;
  void Function()? _cancelRequest;

  bool get isCanceled => _isCanceled;

  void cancel() {
    if (_isCanceled) return;
    _isCanceled = true;
    _cancelRequest?.call();
  }

  void _bind(void Function() cancelRequest) {
    _cancelRequest = cancelRequest;
    if (_isCanceled) cancelRequest();
  }

  void _clear(void Function() cancelRequest) {
    if (_cancelRequest == cancelRequest) {
      _cancelRequest = null;
    }
  }

  void _throwIfCanceled() {
    if (_isCanceled) {
      throw const ApiToolException('API request canceled.');
    }
  }
}

class ApiToolException implements Exception {
  const ApiToolException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiToolService extends GetxService {
  ApiToolService({
    ApiToolHttpClient? httpClient,
    Duration timeout = defaultApiToolRequestTimeout,
  }) : _httpClient = httpClient ?? DartApiToolHttpClient(),
       _timeout = timeout;

  final ApiToolHttpClient _httpClient;
  final Duration _timeout;

  Future<ApiToolResponse> send(
    ApiToolRequest request, {
    ApiToolCancellationToken? cancelToken,
  }) {
    return _httpClient.send(
      request,
      timeout: _timeout,
      cancelToken: cancelToken,
    );
  }
}

class DartApiToolHttpClient implements ApiToolHttpClient {
  @override
  Future<ApiToolResponse> send(
    ApiToolRequest request, {
    required Duration timeout,
    ApiToolCancellationToken? cancelToken,
  }) async {
    final uri = _validatedUri(request.url);
    final client = HttpClient()..connectionTimeout = timeout;
    final stopwatch = Stopwatch()..start();
    HttpClientRequest? ioRequest;

    void cancelRequest() {
      ioRequest?.abort();
      client.close(force: true);
    }

    cancelToken?._bind(cancelRequest);

    try {
      cancelToken?._throwIfCanceled();
      ioRequest = await client
          .openUrl(request.method.label, uri)
          .timeout(timeout);
      cancelToken?._throwIfCanceled();

      for (final entry in request.enabledHeaders.entries) {
        ioRequest.headers.set(entry.key, entry.value);
      }

      if (request.bodyMode == ApiToolBodyMode.multipart) {
        final boundary =
            'app-release-center-${DateTime.now().microsecondsSinceEpoch}';
        ioRequest.headers.set(
          HttpHeaders.contentTypeHeader,
          'multipart/form-data; boundary=$boundary',
        );
        await _writeMultipartBody(
          ioRequest,
          request,
          boundary,
          cancelToken,
        ).timeout(timeout);
      } else if (request.body.isNotEmpty) {
        final payload = utf8.encode(request.body);
        ioRequest.contentLength = payload.length;
        ioRequest.add(payload);
      }

      final response = await ioRequest.close().timeout(timeout);
      cancelToken?._throwIfCanceled();
      final responseBody = await _readResponseBody(
        response,
        cancelToken,
      ).timeout(timeout);
      stopwatch.stop();

      return ApiToolResponse(
        statusCode: response.statusCode,
        reasonPhrase: response.reasonPhrase,
        headers: _headersFromResponse(response.headers),
        body: prettyPrintJsonText(responseBody.text),
        bodyTruncated: responseBody.truncated,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } on TimeoutException {
      throw const ApiToolException('API request timed out.');
    } on SocketException catch (error) {
      if (cancelToken?.isCanceled ?? false) {
        throw const ApiToolException('API request canceled.');
      }
      throw ApiToolException('Network error: ${error.message}');
    } on HandshakeException {
      if (cancelToken?.isCanceled ?? false) {
        throw const ApiToolException('API request canceled.');
      }
      throw const ApiToolException('Secure connection failed.');
    } on HttpException catch (error) {
      if (cancelToken?.isCanceled ?? false) {
        throw const ApiToolException('API request canceled.');
      }
      throw ApiToolException('HTTP request failed: ${error.message}');
    } on ApiToolException {
      rethrow;
    } catch (error) {
      if (cancelToken?.isCanceled ?? false) {
        throw const ApiToolException('API request canceled.');
      }
      throw ApiToolException('API request failed: $error');
    } finally {
      stopwatch.stop();
      cancelToken?._clear(cancelRequest);
      client.close(force: true);
    }
  }

  Uri _validatedUri(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.trim().isEmpty ||
        (scheme != 'http' && scheme != 'https')) {
      throw const ApiToolException('URL must be a valid http or https URL.');
    }
    return uri;
  }

  Map<String, List<String>> _headersFromResponse(HttpHeaders headers) {
    final result = <String, List<String>>{};
    headers.forEach((name, values) {
      result[name] = List<String>.unmodifiable(values);
    });
    return Map<String, List<String>>.unmodifiable(result);
  }

  Future<_ApiToolResponseBody> _readResponseBody(
    HttpClientResponse response,
    ApiToolCancellationToken? cancelToken,
  ) async {
    final builder = BytesBuilder(copy: false);
    var totalBytes = 0;
    var truncated = false;

    await for (final chunk in response) {
      cancelToken?._throwIfCanceled();
      final remaining = apiToolMaxResponseBodyBytes - totalBytes;
      if (remaining > 0) {
        if (chunk.length <= remaining) {
          builder.add(chunk);
        } else {
          builder.add(chunk.sublist(0, remaining));
          truncated = true;
        }
      } else {
        truncated = true;
      }
      totalBytes += chunk.length;
    }

    return _ApiToolResponseBody(
      utf8.decode(builder.takeBytes(), allowMalformed: true),
      truncated,
    );
  }

  Future<void> _writeMultipartBody(
    HttpClientRequest request,
    ApiToolRequest toolRequest,
    String boundary,
    ApiToolCancellationToken? cancelToken,
  ) async {
    for (final field in toolRequest.enabledMultipartFields) {
      cancelToken?._throwIfCanceled();
      final name = _escapeMultipartValue(field.name.trim());
      if (field.isFile) {
        final filePath = field.value.trim();
        if (filePath.isEmpty) {
          throw ApiToolException('Multipart file path is empty for "$name".');
        }
        final file = File(filePath);
        if (!file.existsSync()) {
          throw ApiToolException('Multipart file not found: $filePath');
        }
        final fileName = _escapeMultipartValue(p.basename(filePath));
        final contentType = field.contentType.trim().isEmpty
            ? 'application/octet-stream'
            : field.contentType.trim();
        request.add(
          utf8.encode(
            '--$boundary\r\n'
            'Content-Disposition: form-data; name="$name"; '
            'filename="$fileName"\r\n'
            'Content-Type: $contentType\r\n\r\n',
          ),
        );
        await for (final chunk in file.openRead()) {
          cancelToken?._throwIfCanceled();
          request.add(chunk);
        }
        request.add(utf8.encode('\r\n'));
      } else {
        request.add(
          utf8.encode(
            '--$boundary\r\n'
            'Content-Disposition: form-data; name="$name"\r\n\r\n'
            '${field.value}\r\n',
          ),
        );
      }
    }

    request.add(utf8.encode('--$boundary--\r\n'));
  }

  String _escapeMultipartValue(String value) {
    return value.replaceAll(RegExp(r'["\r\n]'), '_');
  }
}

class _ApiToolResponseBody {
  const _ApiToolResponseBody(this.text, this.truncated);

  final String text;
  final bool truncated;
}
