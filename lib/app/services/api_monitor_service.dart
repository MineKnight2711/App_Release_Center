import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ApiMonitorService extends GetxService {
  static const String defaultDashboardUrl =
      'https://flow-api.hieupham101097.workers.dev/admin/dashboard';

  final dashboardUrl = defaultDashboardUrl.obs;
  Webview? _activeWebview;

  bool get isWindowOpen => _activeWebview != null;

  Future<void> openDashboard() => openStandaloneWindow();

  Future<void> openStandaloneWindow() async {
    final url = dashboardUrl.value.trim();
    if (url.isEmpty) return;

    if (_activeWebview != null) {
      try {
        await _activeWebview!.bringToForeground();
        return;
      } catch (_) {
        _activeWebview = null;
      }
    }

    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        final isAvailable = await WebviewWindow.isWebviewAvailable();
        if (isAvailable) {
          final userDataFolder = await _getStoragePath();
          final webview = await WebviewWindow.create(
            configuration: CreateConfiguration(
              windowWidth: 1280,
              windowHeight: 800,
              title: 'Gden API Monitor',
              useWindowPositionAndSize: true,
              userDataFolderWindows: userDataFolder,
            ),
          );

          _activeWebview = webview;
          unawaited(
            webview.onClose.then((_) {
              if (_activeWebview == webview) {
                _activeWebview = null;
              }
            }),
          );

          webview.launch(url);
          return;
        }
      } catch (e) {
        debugPrint('ApiMonitorService: Failed to launch webview window: $e');
        _activeWebview = null;
      }
    }

    // Fallback: Mở trên trình duyệt hệ thống nếu WebView2 không khả dụng
    await openInBrowser();
  }

  Future<void> openInBrowser() async {
    final uri = Uri.tryParse(dashboardUrl.value.trim());
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('ApiMonitorService: Failed to open in browser: $e');
    }
  }

  Future<void> copyDashboardUrl() async {
    final url = dashboardUrl.value.trim();
    await Clipboard.setData(ClipboardData(text: url));
  }

  Future<String> _getStoragePath() async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      final folder = Directory(p.join(appSupport.path, 'api_monitor_webview'));
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      return folder.path;
    } catch (_) {
      final temp = Directory.systemTemp;
      return p.join(temp.path, 'api_monitor_webview');
    }
  }
}
