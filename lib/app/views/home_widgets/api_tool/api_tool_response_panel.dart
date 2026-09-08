part of '../../home_view.dart';

/// Zone 3 of the API Tool: the response inspector. A hero status bar answers
/// "did it work, how fast, how big" at a glance, and the payload is split into
/// tabs so long headers can never push the body off screen.
mixin _ApiToolResponseSection on _ApiToolDialogCore {
  Widget _buildResponsePanel() {
    final response = _response;
    final error = _error;
    final hasPayload = response != null || error != null;

    return _HudCardShell(
      padding: const EdgeInsets.all(12),
      active: _isSending,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _PanelTitle(
                icon: Icons.receipt_long_outlined,
                title: 'Response',
              ),
              const Spacer(),
              IconButton(
                key: const Key('api-tool-expand-response'),
                tooltip: 'Focus mode',
                visualDensity: VisualDensity.compact,
                onPressed: response != null
                    ? () => unawaited(_showResponseFocusMode(response))
                    : null,
                icon: const Icon(Icons.open_in_full_outlined, size: 18),
              ),
              IconButton(
                key: const Key('api-tool-copy-response'),
                tooltip: 'Copy response',
                visualDensity: VisualDensity.compact,
                onPressed: hasPayload ? _copyResponse : null,
                icon: const Icon(Icons.copy_all_outlined, size: 19),
              ),
            ],
          ),
          if (_isSending) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 10),
          Expanded(child: _buildResponseContent(response, error)),
        ],
      ),
    );
  }

  Widget _buildResponseContent(ApiToolResponse? response, String? error) {
    if (error != null) {
      return SingleChildScrollView(
        controller: _responseScrollController,
        padding: const EdgeInsets.only(right: 8, bottom: 4),
        child: _ApiToolMessage(
          icon: Icons.error_outline,
          color: Theme.of(context).colorScheme.error,
          message: error,
        ),
      );
    }

    final notice = _notice;
    if (response == null && notice != null) {
      return SingleChildScrollView(
        controller: _responseScrollController,
        padding: const EdgeInsets.only(right: 8, bottom: 4),
        child: _ApiToolMessage(
          icon: Icons.warning_amber_outlined,
          color: AppCyberTheme.amber,
          message: notice,
        ),
      );
    }

    if (response == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.satellite_alt_outlined,
              size: 34,
              color: AppCyberTheme.textMuted.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 10),
            Text(
              'Send a request to inspect the response.',
              style: AppCyberTheme.dataTextStyle(
                size: 11.4,
                color: AppCyberTheme.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_apiToolSendShortcutLabel()} works from any field.',
              style: AppCyberTheme.dataTextStyle(
                size: 10.4,
                color: AppCyberTheme.textMuted.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApiToolResponseHero(
            statusCode: response.statusCode,
            reasonPhrase: response.reasonPhrase,
            durationLabel: _durationLabelMs(response.durationMs),
            sizeLabel: _payloadSizeLabel(response.body),
            truncated: response.bodyTruncated,
          ),
          const SizedBox(height: 10),
          const TabBar(
            labelPadding: EdgeInsets.symmetric(horizontal: 4),
            tabs: [
              Tab(
                key: Key('api-tool-response-pretty-tab'),
                child: _ApiToolTabLabel(
                  icon: Icons.data_object_outlined,
                  label: 'Pretty',
                ),
              ),
              Tab(
                key: Key('api-tool-response-raw-tab'),
                child: _ApiToolTabLabel(
                  icon: Icons.notes_outlined,
                  label: 'Raw',
                ),
              ),
              Tab(
                key: Key('api-tool-response-headers-tab'),
                child: _ApiToolTabLabel(
                  icon: Icons.view_headline_outlined,
                  label: 'Headers',
                ),
              ),
              Tab(
                key: Key('api-tool-response-request-tab'),
                child: _ApiToolTabLabel(
                  icon: Icons.outbound_outlined,
                  label: 'Sent Request',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              children: [
                _buildResponseScroll(
                  _ApiToolCodeBlock(
                    key: const Key('api-tool-response-body'),
                    text: response.body.isEmpty
                        ? '(empty)'
                        : prettyPrintJsonText(response.body),
                  ),
                  controller: _responseScrollController,
                ),
                _buildResponseScroll(
                  _ApiToolCodeBlock(
                    key: const Key('api-tool-response-raw'),
                    text: response.body.isEmpty ? '(empty)' : response.body,
                  ),
                ),
                _buildResponseScroll(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ApiToolHeaderTable(
                        key: const Key('api-tool-response-headers'),
                        entries: _responseHeaderEntries(response.headers),
                      ),
                    ],
                  ),
                ),
                _buildResponseScroll(_buildSentRequestView()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponseScroll(Widget child, {ScrollController? controller}) {
    return Scrollbar(
      controller: controller,
      thumbVisibility: controller != null,
      child: SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.only(right: 8, bottom: 4),
        child: child,
      ),
    );
  }

  /// Shows exactly what left the machine, with environment tokens already
  /// resolved, so a failing request can be diffed against the editor.
  Widget _buildSentRequestView() {
    final sent = _sentRequest;
    if (sent == null) {
      return _ApiToolMessage(
        icon: Icons.info_outline,
        color: AppCyberTheme.textMuted,
        message: 'The resolved request will show up here after the next send.',
      );
    }

    final headers =
        sent.enabledHeaders.entries
            .map((entry) => MapEntry(entry.key, entry.value))
            .toList(growable: false)
          ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ApiToolCodeBlock(
          key: const Key('api-tool-sent-request-line'),
          text: '${sent.method.label} ${sent.url}',
        ),
        const SizedBox(height: 12),
        Text('Headers', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _ApiToolHeaderTable(entries: headers),
        if (sent.bodyMode == ApiToolBodyMode.raw &&
            sent.body.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Body', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _ApiToolCodeBlock(
            key: const Key('api-tool-sent-request-body'),
            text: sent.body,
          ),
        ],
      ],
    );
  }

  List<MapEntry<String, String>> _responseHeaderEntries(
    Map<String, List<String>> headers,
  ) {
    final entries =
        headers.entries
            .map((entry) => MapEntry(entry.key, entry.value.join(', ')))
            .toList()
          ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return entries;
  }

  Future<void> _showResponseFocusMode(ApiToolResponse response) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        key: const Key('api-tool-response-focus'),
        insetPadding: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const _PanelTitle(
                    icon: Icons.open_in_full_outlined,
                    title: 'Response body',
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('api-tool-close-response-focus'),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: _ApiToolCodeBlock(
                    text: response.body.isEmpty
                        ? '(empty)'
                        : prettyPrintJsonText(response.body),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
