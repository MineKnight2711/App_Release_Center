import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/weak_network_proxy.dart';

class NetworkTestController extends ChangeNotifier {
  NetworkProfile profile = NetworkProfile.presets.first;
  WeakNetworkProxy? _proxy;
  HttpClient? _probe;
  Timer? _statsTimer;
  bool busy = false;
  bool probing = false;
  bool _disposed = false;
  bool _cancelled = false;
  String? error;
  String? result;
  String apiUrl = '';
  int timeoutSeconds = 30;
  bool get enabled => _proxy != null;
  String? get proxyUrl => _proxy?.url;
  int get connections => _proxy?.connections ?? 0;
  Map<String, String> get environment => _proxy == null
      ? {}
      : {
          'HTTP_PROXY': _proxy!.url,
          'HTTPS_PROXY': _proxy!.url,
          'http_proxy': _proxy!.url,
          'https_proxy': _proxy!.url,
          'NO_PROXY': '',
          'no_proxy': '',
          'FIZA_QA_PROXY': _proxy!.url,
        };

  void selectProfile(NetworkProfile value) {
    if (enabled || busy || probing) return;
    profile = value;
    _notify();
  }

  Future<void> toggle() async {
    if (busy || probing) return;
    busy = true;
    error = null;
    _notify();
    try {
      if (_proxy != null) {
        _statsTimer?.cancel();
        final proxy = _proxy!;
        _proxy = null;
        await proxy.stop();
      } else {
        final proxy = WeakNetworkProxy(profile);
        await proxy.start();
        if (_disposed) {
          await proxy.stop();
          return;
        }
        _proxy = proxy;
        var lastConnections = 0;
        _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (connections != lastConnections) {
            lastConnections = connections;
            _notify();
          }
        });
      }
    } on Object catch (e) {
      error = 'Không bật/tắt được giả lập: $e';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> testApi() async {
    if (probing || busy || _proxy == null) return;
    final uri = Uri.tryParse(apiUrl.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      error =
          'Nhập URL http:// hoặc https:// hợp lệ, không chứa user/password.';
      _notify();
      return;
    }
    final proxy = _proxy!;
    final client = HttpClient()
      ..findProxy = (_) => 'PROXY 127.0.0.1:${proxy.port}';
    _probe = client;
    probing = true;
    _cancelled = false;
    error = null;
    result = null;
    _notify();
    final watch = Stopwatch()..start();
    var bytes = 0;
    int? status;
    var outcome = '';
    try {
      await (() async {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        final response = await request.close();
        status = response.statusCode;
        await for (final chunk in response) {
          bytes += chunk.length;
        }
      })().timeout(Duration(seconds: timeoutSeconds));
      outcome = status! >= 200 && status! < 300
          ? 'Đã nhận đủ phản hồi 2xx. Chưa kiểm tra nội dung nghiệp vụ.'
          : 'API trả HTTP $status. Kiểm tra endpoint, quyền truy cập và server.';
    } on TimeoutException {
      outcome =
          'Timeout sau $timeoutSeconds giây. Chưa nhận đủ phản hồi với mạng giả lập.';
    } on Object {
      outcome = _cancelled
          ? 'Đã dừng theo yêu cầu; chưa có kết luận.'
          : 'Không hoàn tất được kết nối. Kiểm tra URL, DNS, TLS và server.';
    } finally {
      client.close(force: true);
      _probe = null;
      probing = false;
      watch.stop();
      result = [
        'Kiểm tra API • GET $uri',
        'Mạng: ${profile.description}',
        'Timeout: $timeoutSeconds giây',
        'Kết quả: $outcome',
        'HTTP: ${status ?? 'chưa nhận header'} • ${watch.elapsedMilliseconds} ms • $bytes byte đã nhận',
        'Tái hiện: QA Desk → chip Mạng → chọn cùng mức mạng → Bật giả lập → nhập URL → Kiểm tra API.',
        'Mong đợi: API trả đủ phản hồi hợp lệ trong timeout; xác minh xử lý timeout/retry trong ứng dụng.',
      ].join('\n');
      _notify();
    }
  }

  void cancelProbe() {
    _cancelled = true;
    _probe?.close(force: true);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _statsTimer?.cancel();
    cancelProbe();
    unawaited(_proxy?.stop());
    super.dispose();
  }
}
