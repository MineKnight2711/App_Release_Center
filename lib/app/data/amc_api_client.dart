import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AmcApiException implements Exception {
  const AmcApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  /// 0 when the server could not be reached.
  final int statusCode;
  final String code;
  final String message;

  bool get isUnauthorized => statusCode == 401;
  bool get isNetworkError => statusCode == 0;

  @override
  String toString() => message;
}

/// JSON client for the App Management Center Worker (`cloudflare/amc-api`).
class AmcApiClient {
  AmcApiClient({
    required Uri baseUrl,
    required Future<String?> Function() readToken,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _baseUrl = baseUrl,
       _readToken = readToken,
       _http = httpClient ?? http.Client();

  final Uri _baseUrl;
  final Future<String?> Function() _readToken;
  final http.Client _http;
  final Duration timeout;

  /// Called when a request that carried a session token is rejected with 401.
  void Function()? onUnauthorized;

  Future<Map<String, Object?>> get(String path) => _send('GET', path);

  Future<Map<String, Object?>> post(
    String path, {
    Object? body,
    bool authenticated = true,
  }) =>
      _send('POST', path, body: body ?? const {}, authenticated: authenticated);

  Future<Map<String, Object?>> put(String path, {required Object body}) =>
      _send('PUT', path, body: body);

  Future<Map<String, Object?>> patch(String path, {required Object body}) =>
      _send('PATCH', path, body: body);

  Future<Map<String, Object?>> delete(String path) => _send('DELETE', path);

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    final target = Uri.parse('${_baseUrl.path}/v1$path');
    final request = http.Request(
      method,
      _baseUrl.replace(
        path: target.path,
        query: target.hasQuery ? target.query : null,
      ),
    )..headers['Accept'] = 'application/json';
    final token = authenticated ? (await _readToken())?.trim() : null;
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw const AmcApiException(
        statusCode: 0,
        code: 'timeout',
        message: 'Server App Management Center không phản hồi kịp.',
      );
    } on SocketException catch (error) {
      throw AmcApiException(
        statusCode: 0,
        code: 'network',
        message:
            'Không kết nối được server App Management Center: '
            '${error.message}',
      );
    } on http.ClientException catch (error) {
      throw AmcApiException(
        statusCode: 0,
        code: 'network',
        message:
            'Không kết nối được server App Management Center: '
            '${error.message}',
      );
    }

    final decoded = _decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded is Map ? Map<String, Object?>.from(decoded) : const {};
    }

    final error = decoded is Map && decoded['error'] is Map
        ? decoded['error'] as Map
        : const {};
    final code = error['code']?.toString() ?? 'http-${response.statusCode}';
    final exception = AmcApiException(
      statusCode: response.statusCode,
      code: code,
      message:
          _messagesByCode[code] ??
          error['message']?.toString() ??
          'Server lỗi (HTTP ${response.statusCode}).',
    );
    if (exception.isUnauthorized && token != null && token.isNotEmpty) {
      onUnauthorized?.call();
    }
    throw exception;
  }

  static Object? _decode(String body) {
    if (body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}

/// The Worker answers in English; the app shows these for known error codes
/// and falls back to the server's message for anything newer.
const _messagesByCode = {
  'email-already-in-use': 'Email này đã được đăng ký.',
  'invalid-email': 'Email không hợp lệ.',
  'invalid-credential': 'Email hoặc mật khẩu không đúng.',
  'too-many-requests': 'Thử quá nhiều lần. Đợi một phút rồi thử lại.',
  'unauthenticated': 'Hãy đăng nhập trước.',
  'session-expired': 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.',
  'permission-denied': 'Bạn không có quyền làm việc này trong nhóm.',
  'invalid-invite': 'Mã mời không đúng hoặc đã hết hạn.',
  'team-name-required': 'Phải nhập tên nhóm.',
  'cannot-change-self': 'Bạn không đổi được vai trò của chính mình.',
  'cannot-remove-self': 'Bạn không tự xoá mình được.',
  'member-not-found': 'Không tìm thấy thành viên này.',
};
