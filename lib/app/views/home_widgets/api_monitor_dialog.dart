part of '../home_view.dart';

bool _apiMonitorDialogVisible = false;

Future<void> showApiMonitorDialog(
  BuildContext context, {
  String? initialUrl,
}) async {
  if (_apiMonitorDialogVisible) return;
  _apiMonitorDialogVisible = true;
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'API Monitor',
      barrierColor: Colors.black.withValues(alpha: 0.66),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => _ApiMonitorDialog(
        initialUrl: initialUrl ??
            Get.find<ApiMonitorService>().dashboardUrl.value.trim(),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final reduceMotion =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  } finally {
    _apiMonitorDialogVisible = false;
  }
}

class _ApiMonitorDialog extends StatefulWidget {
  const _ApiMonitorDialog({required this.initialUrl});

  final String initialUrl;

  @override
  State<_ApiMonitorDialog> createState() => _ApiMonitorDialogState();
}

class _ApiMonitorDialogState extends State<_ApiMonitorDialog> {
  final _controller = WebviewController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool _isInitialized = false;
  bool _isLoading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _errorMessage;
  String _currentUrl = '';
  String _documentTitle = 'Gden API Monitor';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    unawaited(_initWebview());
  }

  Future<void> _initWebview() async {
    if (!Platform.isWindows) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'In-App WebView is only supported on Windows desktop runtime.';
          _isLoading = false;
        });
      }
      return;
    }

    try {
      await _controller.initialize();

      _subscriptions.addAll([
        _controller.loadingState.listen((state) {
          if (mounted) {
            setState(() {
              _isLoading = state == LoadingState.loading;
            });
          }
        }),
        _controller.historyChanged.listen((event) {
          if (mounted) {
            setState(() {
              _canGoBack = event.canGoBack;
              _canGoForward = event.canGoForward;
            });
          }
        }),
        _controller.url.listen((url) {
          if (mounted && url.isNotEmpty) {
            setState(() {
              _currentUrl = url;
            });
          }
        }),
        _controller.title.listen((title) {
          if (mounted && title.isNotEmpty) {
            setState(() {
              _documentTitle = title;
            });
          }
        }),
      ]);

      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await _controller.loadUrl(widget.initialUrl);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ApiMonitorDialog: failed to initialize webview: $e');
      if (mounted) {
        setState(() {
          _errorMessage =
              'Could not initialize WebView2 engine.\nPlease ensure Microsoft Edge WebView2 Runtime is installed.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width < 760 ? size.width * 0.98 : size.width * 0.94;
    final height = size.height < 640 ? size.height * 0.98 : size.height * 0.92;

    return SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            key: const Key('api-monitor-dialog'),
            width: width,
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppCyberTheme.panelBackgroundStrong,
                  AppCyberTheme.panelBackgroundStrong.withValues(alpha: 0.96),
                  AppCyberTheme.panelBackgroundStrong,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppCyberTheme.isCyber
                    ? AppCyberTheme.electricBlue.withValues(alpha: 0.58)
                    : AppCyberTheme.lineBlue,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppCyberTheme.electricBlue.withValues(
                    alpha: AppCyberTheme.isCyber ? 0.22 : 0.08,
                  ),
                  blurRadius: 38,
                  spreadRadius: -8,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  if (_isLoading)
                    LinearProgressIndicator(
                      minHeight: 2.5,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppCyberTheme.electricBlue,
                      ),
                    )
                  else
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppCyberTheme.lineBlue.withValues(alpha: 0.3),
                    ),
                  Expanded(
                    child: _buildBody(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final host = Uri.tryParse(_currentUrl)?.host ?? 'flow-api.workers.dev';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: AppCyberTheme.panelBackground.withValues(alpha: 0.8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppCyberTheme.electricBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppCyberTheme.electricBlue.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              Icons.query_stats_outlined,
              size: 20,
              color: AppCyberTheme.electricBlue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _documentTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 13,
                    weight: FontWeight.w700,
                    color: AppCyberTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                InkWell(
                  onTap: _copyUrl,
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.link,
                        size: 12,
                        color: AppCyberTheme.textMuted,
                      ),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(
                          host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppCyberTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildToolbarActions(context),
        ],
      ),
    );
  }

  Widget _buildToolbarActions(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Back',
          iconSize: 18,
          onPressed: _canGoBack && _isInitialized
              ? () => _controller.goBack()
              : null,
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        IconButton(
          tooltip: 'Forward',
          iconSize: 18,
          onPressed: _canGoForward && _isInitialized
              ? () => _controller.goForward()
              : null,
          icon: const Icon(Icons.arrow_forward_ios_rounded),
        ),
        IconButton(
          tooltip: 'Reload',
          iconSize: 18,
          onPressed: _isInitialized ? () => _controller.reload() : null,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Copy URL',
          iconSize: 18,
          onPressed: _copyUrl,
          icon: const Icon(Icons.copy_outlined),
        ),
        IconButton(
          tooltip: 'Open in Browser',
          iconSize: 18,
          onPressed: _openInBrowser,
          icon: const Icon(Icons.open_in_browser_rounded),
        ),
        const SizedBox(width: 6),
        Container(
          height: 20,
          width: 1,
          color: AppCyberTheme.lineBlue.withValues(alpha: 0.4),
        ),
        const SizedBox(width: 6),
        IconButton(
          key: const Key('close-api-monitor-dialog'),
          tooltip: 'Close',
          iconSize: 20,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 48,
                color: Colors.amberAccent,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: AppCyberTheme.dataTextStyle(
                  size: 14,
                  color: AppCyberTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open in System Browser'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppCyberTheme.electricBlue,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Initializing In-App WebView...',
              style: AppCyberTheme.dataTextStyle(
                size: 12,
                color: AppCyberTheme.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      child: Webview(_controller),
    );
  }

  Future<void> _copyUrl() async {
    final url = _currentUrl.isNotEmpty ? _currentUrl : widget.initialUrl;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied API Monitor URL to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openInBrowser() async {
    final url = _currentUrl.isNotEmpty ? _currentUrl : widget.initialUrl;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('ApiMonitorDialog: failed to launch browser: $e');
      }
    }
  }
}
