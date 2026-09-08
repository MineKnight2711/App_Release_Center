part of '../home_view.dart';

bool _apiToolDialogVisible = false;
const _defaultApiToolCollectionId = 'api_collection_default';
const _minApiToolTimeoutSeconds = 1;
const _maxApiToolTimeoutSeconds = 3600;
final _apiToolEnvTokenPattern = RegExp(r'\{\{\s*([^{}]+?)\s*\}\}');

const _apiToolSplitterThickness = 14.0;
const _apiToolMinSidebarWidth = 220.0;
const _apiToolMaxSidebarWidth = 460.0;
const _apiToolMinSidebarHeight = 120.0;
const _apiToolMaxSidebarHeight = 320.0;
const _apiToolMinWorkspacePanelWidth = 300.0;

/// Below this the workbench chrome (title, name, tab strip) no longer has room
/// to breathe, so the stacked layout scrolls instead of squeezing.
const _apiToolMinStackedPanelHeight = 260.0;

// Panel sizes survive closing and reopening the dialog within a session, the
// way the home screen keeps its splitters put while the app is running.
double _apiToolSidebarWidth = 292;
double _apiToolCompactSidebarHeight = 190;
double _apiToolWorkspaceRatio = 6 / 11;
double _apiToolStackedRatio = 0.5;

Future<void> showApiToolDialog(BuildContext context) async {
  if (_apiToolDialogVisible) return;
  _apiToolDialogVisible = true;
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'API Tool',
      barrierColor: Colors.black.withValues(alpha: 0.66),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => const _ApiToolDialog(),
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
    _apiToolDialogVisible = false;
  }
}

class _ApiToolButton extends StatelessWidget {
  const _ApiToolButton();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('open-api-tool'),
      onPressed: () => showApiToolDialog(context),
      icon: const Icon(Icons.http_outlined),
      label: const Text('API Tool'),
    );
  }
}

class _ApiToolDialog extends StatefulWidget {
  const _ApiToolDialog();

  @override
  State<_ApiToolDialog> createState() => _ApiToolDialogState();
}

class _ApiToolDialogState extends State<_ApiToolDialog>
    with
        _ApiToolDialogCore,
        _ApiToolOmnibarSection,
        _ApiToolSidebarSection,
        _ApiToolRequestSection,
        _ApiToolResponseSection {
  Widget _buildWorkspace({required bool compact}) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxHeight - _apiToolSplitterThickness;
            final needed = _apiToolMinStackedPanelHeight * 2;
            final total = math.max(available, needed);
            final ratio = _stackedRatioFor(total);
            final requestHeight = total * ratio;

            final column = Column(
              children: [
                SizedBox(height: requestHeight, child: _buildRequestPanel()),
                SizedBox(
                  height: _apiToolSplitterThickness,
                  child: _PanelSplitter(
                    key: const Key('api-tool-workspace-splitter'),
                    axis: Axis.vertical,
                    onDelta: (delta) => _resizeStackedPanels(delta, total),
                  ),
                ),
                SizedBox(
                  height: total - requestHeight,
                  child: _buildResponsePanel(),
                ),
              ],
            );

            // Below the combined minimum the panels keep their size and the
            // workspace scrolls, instead of squeezing the workbench chrome.
            return available >= needed
                ? column
                : SingleChildScrollView(child: column);
          },
        ),
      );
    }

    // The request workbench grows with the dialog instead of being pinned to a
    // cramped fixed width; long JSON bodies and multipart tables need the room.
    return Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final splitWidth = constraints.maxWidth - _apiToolSplitterThickness;
          if (splitWidth <= 0) return const SizedBox.shrink();
          final ratio = _workspaceRatioFor(splitWidth);
          final requestWidth = splitWidth * ratio;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: requestWidth, child: _buildRequestPanel()),
              SizedBox(
                width: _apiToolSplitterThickness,
                child: _PanelSplitter(
                  key: const Key('api-tool-workspace-splitter'),
                  axis: Axis.horizontal,
                  onDelta: (delta) => _resizeWorkspace(delta, splitWidth),
                ),
              ),
              Expanded(child: _buildResponsePanel()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 940;
        if (compact) {
          final maxHeight = constraints.maxHeight;
          final upper = maxHeight.isFinite
              ? math.min(_apiToolMaxSidebarHeight, maxHeight * 0.5)
              : _apiToolMaxSidebarHeight;
          final sidebarHeight = _clampToRange(
            _apiToolCompactSidebarHeight,
            _apiToolMinSidebarHeight,
            upper,
          );
          return Column(
            children: [
              SizedBox(
                key: const Key('api-tool-sidebar'),
                height: sidebarHeight,
                child: _buildSidebar(),
              ),
              SizedBox(
                height: _apiToolSplitterThickness,
                child: _PanelSplitter(
                  key: const Key('api-tool-sidebar-splitter'),
                  axis: Axis.vertical,
                  onDelta: (delta) => _resizeCompactSidebar(delta, upper),
                ),
              ),
              Expanded(child: _buildWorkspace(compact: true)),
            ],
          );
        }

        final sidebarWidth = _sidebarWidthFor(constraints.maxWidth);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const Key('api-tool-sidebar'),
              width: sidebarWidth,
              child: _buildSidebar(),
            ),
            SizedBox(
              width: _apiToolSplitterThickness,
              child: _PanelSplitter(
                key: const Key('api-tool-sidebar-splitter'),
                axis: Axis.horizontal,
                onDelta: (delta) => _resizeSidebar(delta, constraints.maxWidth),
              ),
            ),
            Expanded(child: _buildWorkspace(compact: false)),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Panel sizing. Same model as the home screen: the sidebar is a pixel width,
  // the two workbench panels share a ratio so they track the dialog's size.
  // ---------------------------------------------------------------------------

  /// Widest the sidebar may get before the workbench drops below its own
  /// minimum. Mirrors `_enforceMainWidth` on the home scaffold.
  double _maxSidebarWidthFor(double bodyWidth) {
    final workspaceMin =
        _apiToolMinWorkspacePanelWidth * 2 +
        _apiToolSplitterThickness +
        28; // workspace padding
    final room = bodyWidth - _apiToolSplitterThickness - workspaceMin;
    return math.min(_apiToolMaxSidebarWidth, room);
  }

  double _sidebarWidthFor(double bodyWidth) {
    return _clampToRange(
      _apiToolSidebarWidth,
      _apiToolMinSidebarWidth,
      _maxSidebarWidthFor(bodyWidth),
    );
  }

  double _workspaceRatioFor(double splitWidth) {
    final minRatio = _apiToolMinWorkspacePanelWidth / splitWidth;
    if (minRatio >= 0.5) return 0.5;
    return _clampToRange(_apiToolWorkspaceRatio, minRatio, 1 - minRatio);
  }

  double _stackedRatioFor(double total) {
    final minRatio = _apiToolMinStackedPanelHeight / total;
    if (minRatio >= 0.5) return 0.5;
    return _clampToRange(_apiToolStackedRatio, minRatio, 1 - minRatio);
  }

  void _resizeSidebar(double delta, double bodyWidth) {
    final next = _clampToRange(
      _sidebarWidthFor(bodyWidth) + delta,
      _apiToolMinSidebarWidth,
      _maxSidebarWidthFor(bodyWidth),
    );
    if (next == _apiToolSidebarWidth) return;
    setState(() => _apiToolSidebarWidth = next);
  }

  void _resizeCompactSidebar(double delta, double upperBound) {
    final current = _clampToRange(
      _apiToolCompactSidebarHeight,
      _apiToolMinSidebarHeight,
      upperBound,
    );
    final next = _clampToRange(
      current + delta,
      _apiToolMinSidebarHeight,
      upperBound,
    );
    if (next == _apiToolCompactSidebarHeight) return;
    setState(() => _apiToolCompactSidebarHeight = next);
  }

  void _resizeWorkspace(double delta, double splitWidth) {
    if (splitWidth <= 0) return;
    final next = _workspaceRatioFor(splitWidth) + (delta / splitWidth);
    final minRatio = _apiToolMinWorkspacePanelWidth / splitWidth;
    if (minRatio >= 0.5) return;
    final clamped = _clampToRange(next, minRatio, 1 - minRatio);
    if (clamped == _apiToolWorkspaceRatio) return;
    setState(() => _apiToolWorkspaceRatio = clamped);
  }

  void _resizeStackedPanels(double delta, double total) {
    if (total <= 0) return;
    final minRatio = _apiToolMinStackedPanelHeight / total;
    if (minRatio >= 0.5) return;
    final next = _stackedRatioFor(total) + (delta / total);
    final clamped = _clampToRange(next, minRatio, 1 - minRatio);
    if (clamped == _apiToolStackedRatio) return;
    setState(() => _apiToolStackedRatio = clamped);
  }

  /// `num.clamp` asserts when the bounds cross, which a very small dialog can
  /// produce; fall back to the lower bound there.
  static double _clampToRange(double value, double lower, double upper) {
    if (!value.isFinite) return lower;
    if (upper <= lower) return lower;
    return value.clamp(lower, upper).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width < 760 ? size.width * 0.98 : size.width * 0.96;
    final height = size.height < 640 ? size.height * 0.98 : size.height * 0.94;

    return SafeArea(
      child: Center(
        child: CallbackShortcuts(
          bindings: _apiToolShortcutBindings(),
          child: Focus(
            autofocus: true,
            child: Material(
              color: Colors.transparent,
              child: Container(
                key: const Key('api-tool-dialog'),
                width: width,
                height: height,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppCyberTheme.panelBackgroundStrong,
                      AppCyberTheme.panelBackgroundStrong.withValues(
                        alpha: 0.94,
                      ),
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
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildHeader(context),
                    Expanded(child: _buildBody(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Dev-standard shortcuts. `CallbackShortcuts` sits above every field in the
  /// dialog, so these fire no matter which input currently holds focus.
  Map<ShortcutActivator, VoidCallback> _apiToolShortcutBindings() {
    void send() {
      if (_canSendRequest) unawaited(_sendRequest());
    }

    void save() {
      if (!_isSending &&
          _repository.canWriteApiTools.value &&
          _urlController.text.trim().isNotEmpty) {
        unawaited(_saveRequest(asNew: false));
      }
    }

    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter, control: true): send,
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): send,
      const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
          send,
      const SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true): send,
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): save,
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): save,
    };
  }
}

mixin _ApiToolDialogCore on State<_ApiToolDialog> {
  final _nameController = TextEditingController();
  final _urlController = _ApiToolEnvTextEditingController();
  final _bodyController = _ApiToolEnvTextEditingController();
  final _authTokenController = _ApiToolEnvTextEditingController();
  final _authUsernameController = _ApiToolEnvTextEditingController();
  final _authPasswordController = _ApiToolEnvTextEditingController();
  final _authApiKeyNameController = _ApiToolEnvTextEditingController();
  final _authApiKeyValueController = _ApiToolEnvTextEditingController();
  final _timeoutSecondsController = TextEditingController();
  final _requestScrollController = ScrollController();
  final _multipartScrollController = ScrollController();
  final _urlEncodedScrollController = ScrollController();
  final _paramScrollController = ScrollController();
  final _responseScrollController = ScrollController();
  final _sidebarScrollController = ScrollController();
  final _requestSearchController = TextEditingController();
  final _environmentVariablesMenuController = MenuController();

  final _historyLimit = 50;
  var _method = ApiToolMethod.get;
  var _authorizationType = ApiToolAuthorizationType.none;
  var _headers = <_ApiToolHeaderEditor>[];
  var _collections = <ApiToolCollectionRoot>[];
  var _folders = <ApiToolCollectionFolder>[];
  var _collection = <ApiToolRequest>[];
  var _quickRequests = <ApiToolQuickRequest>[];
  var _history = <ApiToolHistoryEntry>[];
  var _headerSerial = 0;
  var _multipartSerial = 0;
  var _urlEncodedSerial = 0;
  var _selectedCollectionId = '';
  var _selectedFolderId = '';
  final _expandedCollectionIds = <String>{};
  final _expandedFolderIds = <String>{};
  String? _activeRequestId;
  var _bodyMode = ApiToolBodyMode.raw;
  var _multipartRows = <_ApiToolMultipartEditor>[];
  var _urlEncodedRows = <_ApiToolHeaderEditor>[];
  ApiToolResponse? _response;
  String? _error;

  /// Something worth reading that is not a failure — currently the list of
  /// oversized values a Postman import had to drop.
  String? _notice;
  bool _isSending = false;
  bool _isRefreshingRepository = false;
  bool _isImportingPostmanCollection = false;
  bool _isImportingPostmanEnvironment = false;
  ApiToolCancellationToken? _cancelToken;
  var _paramRows = <_ApiToolHeaderEditor>[];
  var _paramSerial = 0;
  bool _syncingParams = false;
  ApiToolRequest? _sentRequest;

  ProjectStoreService get _localStore => Get.find<ProjectStoreService>();

  ApiToolRepositoryService get _repository {
    if (Get.isRegistered<ApiToolRepositoryService>()) {
      return Get.find<ApiToolRepositoryService>();
    }
    final repository = ApiToolRepositoryService(localStore: _localStore);
    Get.put<ApiToolRepositoryService>(repository);
    return repository;
  }

  ApiToolService get _apiToolService {
    if (Get.isRegistered<ApiToolService>()) {
      return Get.find<ApiToolService>();
    }
    return ApiToolService();
  }

  ApiToolPostmanCollectionImportService get _postmanImportService {
    if (Get.isRegistered<ApiToolPostmanCollectionImportService>()) {
      return Get.find<ApiToolPostmanCollectionImportService>();
    }
    return ApiToolPostmanCollectionImportService();
  }

  ApiToolPostmanEnvironmentImportService get _postmanEnvironmentImportService {
    if (Get.isRegistered<ApiToolPostmanEnvironmentImportService>()) {
      return Get.find<ApiToolPostmanEnvironmentImportService>();
    }
    return ApiToolPostmanEnvironmentImportService();
  }

  bool get _isImportingPostman =>
      _isImportingPostmanCollection || _isImportingPostmanEnvironment;

  String get _timeoutValidationMessage =>
      'Enter a timeout from $_minApiToolTimeoutSeconds to '
      '$_maxApiToolTimeoutSeconds seconds.';

  ApiToolCollectionRoot? get _activeCollection {
    for (final collection in _collections) {
      if (collection.id == _selectedCollectionId) return collection;
    }
    return _collections.isEmpty ? null : _collections.first;
  }

  ApiToolEnvironment? get _activeEnvironment =>
      _activeCollection?.activeEnvironment;

  String get _requestSearchTerm =>
      _requestSearchController.text.trim().toLowerCase();

  List<ApiToolRequest> get _activeCollectionRequests {
    return _collection
        .where((request) => request.collectionId == _selectedCollectionId)
        .toList(growable: false);
  }

  List<ApiToolCollectionFolder> get _activeCollectionFolders {
    return _folders
        .where((folder) => folder.collectionId == _selectedCollectionId)
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_syncFormState);
    _nameController.addListener(_syncFormState);
    _bodyController.addListener(_syncFormState);
    _requestSearchController.addListener(_syncFormState);
    _timeoutSecondsController.text = _localStore.apiToolTimeoutSeconds
        .toString();
    _loadCollectionState();
    unawaited(_refreshCollectionState());
    _history = _localStore.apiToolHistory;
    _replaceHeaders(const []);
    _replaceMultipartFields(const []);
    _replaceUrlEncodedFields(const []);
    _replaceParamRows(const []);
  }

  void _loadCollectionState({bool persistDefaults = true}) {
    final now = DateTime.now();
    var collections = _repository.apiToolCollections;
    final folders = _repository.apiToolFolders;
    var requests = _repository.apiToolRequests;
    var shouldSaveCollections = false;
    var shouldSaveRequests = false;

    if (collections.isEmpty) {
      collections = [
        ApiToolCollectionRoot(
          id: _defaultApiToolCollectionId,
          name: 'Default Collection',
          updatedAt: now,
        ),
      ];
      shouldSaveCollections = true;
    }

    final collectionIds = collections.map((entry) => entry.id).toSet();
    final defaultCollectionId = collections.first.id;
    final previousCollectionId = _selectedCollectionId;
    final previousFolderId = _selectedFolderId;
    final selectedCollectionId = collectionIds.contains(previousCollectionId)
        ? previousCollectionId
        : defaultCollectionId;
    requests = requests
        .map((request) {
          if (collectionIds.contains(request.collectionId)) return request;
          shouldSaveRequests = true;
          return request.copyWith(
            collectionId: defaultCollectionId,
            folderId: '',
          );
        })
        .toList(growable: false);

    _collections = collections;
    _folders = folders
        .where((folder) => collectionIds.contains(folder.collectionId))
        .toList(growable: false);
    _collection = requests;
    _quickRequests = _repository.apiToolQuickRequests;
    _selectedCollectionId = selectedCollectionId;
    final folderIds = _folders
        .where((folder) => folder.collectionId == selectedCollectionId)
        .map((folder) => folder.id)
        .toSet();
    _selectedFolderId =
        previousFolderId.isEmpty || folderIds.contains(previousFolderId)
        ? previousFolderId
        : '';
    _expandedCollectionIds.removeWhere((id) => !collectionIds.contains(id));
    final allFolderIds = _folders.map((folder) => folder.id).toSet();
    _expandedFolderIds.removeWhere((id) => !allFolderIds.contains(id));

    if (persistDefaults &&
        _repository.canWriteApiTools.value &&
        shouldSaveCollections) {
      unawaited(
        _repository.saveApiToolCollections(collections).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          if (mounted) setState(() => _error = error.toString());
        }),
      );
    }
    if (persistDefaults &&
        _repository.canWriteApiTools.value &&
        shouldSaveRequests) {
      unawaited(
        _repository.saveApiToolRequests(requests).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          if (mounted) setState(() => _error = error.toString());
        }),
      );
    }
  }

  Future<void> _refreshCollectionState() async {
    if (_isRefreshingRepository) return;
    setState(() => _isRefreshingRepository = true);
    await _repository.refresh();
    if (!mounted) return;
    setState(() {
      _loadCollectionState(persistDefaults: _repository.canWriteApiTools.value);
      _isRefreshingRepository = false;
      final status = _repository.repositoryStatus.value;
      if (status.isNotEmpty) _error = status;
    });
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _nameController.removeListener(_syncFormState);
    _urlController.removeListener(_syncFormState);
    _bodyController.removeListener(_syncFormState);
    _requestSearchController.removeListener(_syncFormState);
    _nameController.dispose();
    _urlController.dispose();
    _bodyController.dispose();
    _authTokenController.dispose();
    _authUsernameController.dispose();
    _authPasswordController.dispose();
    _authApiKeyNameController.dispose();
    _authApiKeyValueController.dispose();
    _timeoutSecondsController.dispose();
    _requestSearchController.dispose();
    _requestScrollController.dispose();
    _multipartScrollController.dispose();
    _urlEncodedScrollController.dispose();
    _paramScrollController.dispose();
    _responseScrollController.dispose();
    _sidebarScrollController.dispose();
    for (final header in _headers) {
      header.dispose();
    }
    for (final row in _multipartRows) {
      row.dispose();
    }
    for (final row in _urlEncodedRows) {
      row.dispose();
    }
    for (final row in _paramRows) {
      row.nameController.removeListener(_syncUrlFromParams);
      row.valueController.removeListener(_syncUrlFromParams);
      row.dispose();
    }
    _paramRows = const [];
    super.dispose();
  }

  Widget _buildVariableDropField({
    required TextEditingController controller,
    required bool enabled,
    required Widget child,
  }) {
    return _ApiToolEnvDropTarget(
      enabled: enabled,
      onAcceptToken: (token) {
        _insertVariableToken(controller, token);
        _syncFormState();
      },
      child: child,
    );
  }

  void _insertVariableToken(TextEditingController controller, String token) {
    final text = controller.text;
    final selection = controller.selection;
    var start = text.length;
    var end = text.length;

    if (selection.isValid) {
      start = selection.start.clamp(0, text.length).toInt();
      end = selection.end.clamp(0, text.length).toInt();
      if (end < start) {
        final previousStart = start;
        start = end;
        end = previousStart;
      }
    }

    final nextText = text.replaceRange(start, end, token);
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
  }

  List<String> _missingEnvironmentVariables(
    String input,
    Map<String, String> variables,
  ) {
    final names = <String>{};
    for (final match in _apiToolEnvTokenPattern.allMatches(input)) {
      final name = match.group(1);
      if (name != null && !variables.containsKey(name)) {
        names.add(name);
      }
    }
    return names.toList()..sort();
  }

  String? _resolvedUrlValidationError({
    required String originalUrl,
    required String resolvedUrl,
  }) {
    if (!_apiToolEnvTokenPattern.hasMatch(originalUrl)) return null;

    final uri = Uri.tryParse(resolvedUrl.trim());
    final scheme = uri?.scheme.toLowerCase();
    if (uri != null &&
        uri.hasScheme &&
        uri.host.trim().isNotEmpty &&
        (scheme == 'http' || scheme == 'https')) {
      return null;
    }

    return 'Resolved URL must be a valid http or https URL. '
        'Check the active environment value used in the URL.';
  }

  Future<void> _sendRequest() async {
    if (_isSending) return;
    final draftRequest = _draftRequest(
      id: _activeRequestId ?? _newId('api_request'),
      updatedAt: DateTime.now(),
    );
    final prepared = _prepareRequestForSend(
      draftRequest,
      collection: _activeCollection,
    );
    if (prepared == null) return;
    await _executeRequest(
      request: prepared.resolved,
      historyRequest: draftRequest,
    );
  }

  ({ApiToolRequest resolved, ApiToolCollectionRoot collection})?
  _prepareRequestForSend(
    ApiToolRequest draftRequest, {
    required ApiToolCollectionRoot? collection,
  }) {
    if (draftRequest.url.trim().isEmpty) {
      setState(() => _error = 'Enter a URL before sending.');
      return null;
    }
    if (collection == null) {
      setState(() => _error = 'The request collection no longer exists.');
      return null;
    }
    final activeVariables = collection.activeVariables;
    final missingVariables = _missingRequestVariables(
      draftRequest,
      activeVariables,
    );
    if (missingVariables.isNotEmpty) {
      setState(() {
        _error =
            'Missing active environment variable(s): '
            '${missingVariables.join(', ')}.';
      });
      return null;
    }
    final request = resolveApiToolRequestVariables(
      draftRequest,
      activeVariables,
    );
    final resolvedUrlError = _resolvedUrlValidationError(
      originalUrl: draftRequest.url,
      resolvedUrl: request.url,
    );
    if (resolvedUrlError != null) {
      setState(() => _error = resolvedUrlError);
      return null;
    }
    return (resolved: request, collection: collection);
  }

  List<String> _missingRequestVariables(
    ApiToolRequest request,
    Map<String, String> variables,
  ) {
    final missing = <String>{};
    final inputs = <String>[request.url];
    for (final header in request.headers.where((entry) => entry.enabled)) {
      inputs.addAll([header.name, header.value]);
    }
    switch (request.authorization.type) {
      case ApiToolAuthorizationType.none:
        break;
      case ApiToolAuthorizationType.bearer:
        inputs.add(request.authorization.token);
      case ApiToolAuthorizationType.basic:
        inputs.addAll([
          request.authorization.username,
          request.authorization.password,
        ]);
      case ApiToolAuthorizationType.apiKey:
        inputs.addAll([
          request.authorization.apiKeyName,
          request.authorization.apiKeyValue,
        ]);
    }
    switch (request.bodyMode) {
      case ApiToolBodyMode.raw:
        inputs.add(request.body);
      case ApiToolBodyMode.multipart:
        for (final field in request.multipartFields.where(
          (entry) => entry.enabled,
        )) {
          inputs.addAll([field.name, field.value, field.contentType]);
        }
      case ApiToolBodyMode.urlEncoded:
        for (final field in request.urlEncodedFields.where(
          (entry) => entry.enabled,
        )) {
          inputs.addAll([field.name, field.value]);
        }
    }
    for (final input in inputs) {
      missing.addAll(_missingEnvironmentVariables(input, variables));
    }
    return missing.toList()..sort();
  }

  Future<void> _runQuickRequest(ApiToolQuickRequest quickRequest) async {
    if (_isSending) return;
    ApiToolCollectionRoot? collection;
    for (final entry in _collections) {
      if (entry.id == quickRequest.collectionId) {
        collection = entry;
        break;
      }
    }
    final draftRequest = quickRequest.executableRequest.copyWith(
      updatedAt: DateTime.now(),
    );
    final prepared = _prepareRequestForSend(
      draftRequest,
      collection: collection,
    );
    if (prepared == null) return;

    if (quickRequest.requiresConfirmation) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Run Quick Request?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(quickRequest.displayName),
              const SizedBox(height: 10),
              Text(
                '${prepared.resolved.method.label} ${prepared.resolved.url}',
                style: AppCyberTheme.dataTextStyle(
                  size: 11.2,
                  color: AppCyberTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Environment: '
                '${prepared.collection.activeEnvironment?.displayName ?? 'None'}',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              key: const Key('api-tool-confirm-run-quick-request'),
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.bolt_outlined),
              label: const Text('Run'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    await _executeRequest(
      request: prepared.resolved,
      historyRequest: draftRequest,
    );
  }

  Future<void> _executeRequest({
    required ApiToolRequest request,
    required ApiToolRequest historyRequest,
  }) async {
    if (_isSending) return;

    final timeout = await _normalizeAndSaveTimeout(showError: true);
    if (timeout == null) return;

    final cancelToken = ApiToolCancellationToken();
    final stopwatch = Stopwatch()..start();
    setState(() {
      _isSending = true;
      _cancelToken = cancelToken;
      _response = null;
      _error = null;
      _notice = null;
      _sentRequest = request;
    });

    try {
      final response = await _apiToolService.send(
        request,
        timeout: timeout,
        cancelToken: cancelToken,
      );
      await _recordHistory(
        request: historyRequest,
        statusCode: response.statusCode,
        durationMs: response.durationMs,
      );
      if (!mounted) return;
      setState(() {
        _response = response;
        _error = null;
      });
    } on ApiToolException catch (error) {
      await _recordHistory(
        request: historyRequest,
        durationMs: stopwatch.elapsedMilliseconds,
        error: error.message,
      );
      if (!mounted) return;
      setState(() {
        _response = null;
        _error = error.message;
      });
    } catch (error) {
      final message = 'API request failed: $error';
      await _recordHistory(
        request: historyRequest,
        durationMs: stopwatch.elapsedMilliseconds,
        error: message,
      );
      if (!mounted) return;
      setState(() {
        _response = null;
        _error = message;
      });
    } finally {
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _isSending = false;
          _cancelToken = null;
        });
      }
    }
  }

  Future<Duration?> _normalizeAndSaveTimeout({required bool showError}) async {
    final raw = _timeoutSecondsController.text.trim();
    final seconds = int.tryParse(raw);
    if (seconds == null ||
        seconds < _minApiToolTimeoutSeconds ||
        seconds > _maxApiToolTimeoutSeconds) {
      if (showError && mounted) {
        setState(() {
          _error = _timeoutValidationMessage;
        });
      }
      return null;
    }

    final normalized = seconds.toString();
    if (_timeoutSecondsController.text != normalized) {
      _timeoutSecondsController.text = normalized;
    }
    await _localStore.saveApiToolTimeoutSeconds(seconds);
    if (showError && mounted && _error == _timeoutValidationMessage) {
      setState(() => _error = null);
    }
    return Duration(seconds: seconds);
  }

  Future<void> _recordHistory({
    required ApiToolRequest request,
    int? statusCode,
    int? durationMs,
    String error = '',
  }) async {
    final entry = ApiToolHistoryEntry(
      id: _newId('api_history'),
      request: request.copyWith(updatedAt: DateTime.now()),
      statusCode: statusCode,
      durationMs: durationMs,
      sentAt: DateTime.now(),
      error: error,
    );
    await _localStore.saveApiToolHistory(
      [entry, ..._history].take(_historyLimit).toList(),
    );
    if (mounted) {
      setState(() => _history = _localStore.apiToolHistory);
    }
  }

  Future<bool> _runRepositoryWrite(Future<void> Function() write) async {
    try {
      await write();
      return true;
    } on ApiToolRepositoryException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return false;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return false;
    }
  }

  Future<void> _importPostmanCollection() async {
    if (_isImportingPostman) return;
    final file = await file_selector.openFile(
      acceptedTypeGroups: const [
        file_selector.XTypeGroup(
          label: 'Postman Collection',
          extensions: ['json'],
          mimeTypes: ['application/json'],
        ),
      ],
    );
    if (file == null || !mounted) return;

    setState(() => _isImportingPostmanCollection = true);
    try {
      final result = await _postmanImportService.importFile(file.path);
      final saved = await _runRepositoryWrite(
        () => _repository.importApiTools(
          collections: [result.collection],
          folders: result.folders,
          requests: result.requests,
        ),
      );
      if (!saved || !mounted) return;

      setState(() {
        _loadCollectionState(persistDefaults: false);
        _selectedCollectionId = result.collection.id;
        _selectedFolderId = '';
        _expandedCollectionIds.add(result.collection.id);
        _activeRequestId = null;
        _response = null;
        _error = null;
        _notice = _importNotice(result);
      });
      _showApiToolSnack(
        result.warnings.isEmpty
            ? 'Imported ${result.requestCount} request(s) from Postman.'
            : 'Imported ${result.requestCount} request(s); '
                  '${result.warnings.length} oversized value(s) dropped.',
      );
    } on ApiToolPostmanImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isImportingPostmanCollection = false);
    }
  }

  Future<void> _importPostmanEnvironment() async {
    if (_isImportingPostman) return;
    final targetCollectionId = _activeCollection?.id ?? '';
    if (targetCollectionId.isEmpty) {
      setState(() => _error = 'Select a collection before importing.');
      return;
    }
    final file = await file_selector.openFile(
      acceptedTypeGroups: const [
        file_selector.XTypeGroup(
          label: 'Postman Environment',
          extensions: ['json'],
          mimeTypes: ['application/json'],
        ),
      ],
    );
    if (file == null || !mounted) return;

    setState(() => _isImportingPostmanEnvironment = true);
    try {
      final environment = await _postmanEnvironmentImportService.importFile(
        file.path,
      );
      ApiToolCollectionRoot? targetCollection;
      for (final collection in _collections) {
        if (collection.id == targetCollectionId) {
          targetCollection = collection;
          break;
        }
      }
      if (targetCollection == null) {
        throw const ApiToolPostmanImportException(
          'The selected collection no longer exists.',
        );
      }

      final updatedCollection = targetCollection.copyWith(
        environments: [...targetCollection.environments, environment],
        activeEnvironmentId: environment.id,
        updatedAt: DateTime.now(),
      );
      final saved = await _saveCollectionRoot(updatedCollection);
      if (!saved || !mounted) return;

      setState(() => _error = null);
      _showApiToolSnack(
        'Imported "${environment.displayName}" into '
        '${updatedCollection.displayName}.',
      );
    } on ApiToolPostmanImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isImportingPostmanEnvironment = false);
    }
  }

  Future<void> _importLocalApiTools() async {
    final imported = await _runRepositoryWrite(
      _repository.importLocalApiToolsToTeam,
    );
    if (!imported || !mounted) return;
    setState(() {
      _loadCollectionState(persistDefaults: false);
      _error = null;
    });
  }

  String? _importNotice(ApiToolPostmanImportResult result) {
    if (result.warnings.isEmpty) return null;
    return [
      'Imported ${result.requestCount} request(s). '
          '${result.warnings.length} value(s) were too large to store and were '
          'dropped — Postman had inlined them as base64, and the file entry '
          'beside each one still points at the real upload:',
      ...result.warnings.map((warning) => '  • $warning'),
    ].join('\n');
  }

  void _showApiToolSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  Future<void> _saveRequest({required bool asNew}) async {
    final id = asNew || _activeRequestId == null
        ? _newId('api_request')
        : _activeRequestId!;
    final request = _draftRequest(id: id, updatedAt: DateTime.now());
    if (request.url.trim().isEmpty) {
      setState(() => _error = 'Enter a URL before saving.');
      return;
    }

    final normalized = request.copyWith(
      name: request.name.trim().isEmpty ? _fallbackName(request) : request.name,
    );
    final updated =
        _collection.where((entry) => entry.id != normalized.id).toList()
          ..insert(0, normalized);

    final saved = await _runRepositoryWrite(
      () => _repository.saveApiToolRequests(updated),
    );
    if (!saved || !mounted) return;
    setState(() {
      _collection = _repository.apiToolRequests;
      _activeRequestId = normalized.id;
      _expandPathToFolder(normalized.collectionId, normalized.folderId);
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = normalized.name;
      }
      _error = null;
    });
  }

  Future<void> _deleteActiveRequest() async {
    final id = _activeRequestId;
    if (id == null) return;

    final saved = await _runRepositoryWrite(
      () => _repository.saveApiToolRequests(
        _collection.where((entry) => entry.id != id).toList(),
      ),
    );
    if (!saved || !mounted) return;
    setState(() {
      _collection = _repository.apiToolRequests;
      _activeRequestId = null;
    });
  }

  Future<void> _createQuickRequest() async {
    final id = _newId('api_quick_request');
    final now = DateTime.now();
    final initial = ApiToolQuickRequest(
      id: id,
      name: '',
      collectionId: _selectedCollectionId,
      request: ApiToolRequest(
        id: id,
        name: '',
        method: ApiToolMethod.get,
        url: '',
        collectionId: _selectedCollectionId,
        updatedAt: now,
      ),
      updatedAt: now,
    );
    await _openQuickRequestEditor(initial);
  }

  Future<void> _createQuickRequestFromDraft() async {
    final id = _newId('api_quick_request');
    final now = DateTime.now();
    final draft = _draftRequest(id: id, updatedAt: now).copyWith(folderId: '');
    final initial = ApiToolQuickRequest(
      id: id,
      name: draft.name.trim().isEmpty ? _fallbackName(draft) : draft.name,
      collectionId: draft.collectionId,
      request: draft,
      updatedAt: now,
    );
    await _openQuickRequestEditor(initial);
  }

  Future<void> _openQuickRequestEditor(ApiToolQuickRequest initial) async {
    final result = await showDialog<ApiToolQuickRequest>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ApiToolQuickRequestDialog(
        initial: initial,
        collections: _collections,
      ),
    );
    if (result == null || !mounted) return;

    final updated =
        _quickRequests.where((entry) => entry.id != result.id).toList()
          ..insert(0, result);
    final saved = await _runRepositoryWrite(
      () => _repository.saveApiToolQuickRequests(updated),
    );
    if (!saved || !mounted) return;
    setState(() {
      _quickRequests = _repository.apiToolQuickRequests;
      _error = null;
    });
  }

  Future<void> _handleQuickRequestAction(
    ApiToolQuickRequest quickRequest,
    _ApiToolQuickRequestAction action,
  ) async {
    switch (action) {
      case _ApiToolQuickRequestAction.edit:
        await _openQuickRequestEditor(quickRequest);
        return;
      case _ApiToolQuickRequestAction.duplicate:
        final id = _newId('api_quick_request');
        final now = DateTime.now();
        final copy = quickRequest.copyWith(
          id: id,
          name: '${quickRequest.displayName} Copy',
          request: quickRequest.request.copyWith(id: id, updatedAt: now),
          updatedAt: now,
        );
        await _openQuickRequestEditor(copy);
        return;
      case _ApiToolQuickRequestAction.delete:
        await _deleteQuickRequest(quickRequest);
        return;
    }
  }

  Future<void> _deleteQuickRequest(ApiToolQuickRequest quickRequest) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Quick Request?'),
        content: Text(
          'Delete "${quickRequest.displayName}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('api-tool-confirm-delete-quick-request'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final saved = await _runRepositoryWrite(
      () => _repository.saveApiToolQuickRequests(
        _quickRequests.where((entry) => entry.id != quickRequest.id).toList(),
      ),
    );
    if (!saved || !mounted) return;
    setState(() => _quickRequests = _repository.apiToolQuickRequests);
  }

  Future<void> _createCollection(BuildContext context) async {
    final name = await _promptApiToolText(
      context,
      title: 'New Collection',
      label: 'Collection name',
      fallback: 'New Collection',
    );
    if (name == null || !mounted) return;

    final collection = ApiToolCollectionRoot(
      id: _newId('api_collection'),
      name: name,
      updatedAt: DateTime.now(),
    );
    final updated = [..._collections, collection];
    final saved = await _runRepositoryWrite(
      () => _repository.saveApiToolCollections(updated),
    );
    if (!saved || !mounted) return;
    setState(() {
      _collections = _repository.apiToolCollections;
      _selectedCollectionId = collection.id;
      _selectedFolderId = '';
      _expandedCollectionIds.remove(collection.id);
      _activeRequestId = null;
    });
  }

  Future<void> _deleteActiveCollection() async {
    final collection = _activeCollection;
    if (collection == null) return;

    final folderCount = _folders
        .where((entry) => entry.collectionId == collection.id)
        .length;
    final requestCount = _collection
        .where((entry) => entry.collectionId == collection.id)
        .length;
    final quickRequestCount = _quickRequests
        .where((entry) => entry.collectionId == collection.id)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Collection?'),
        content: Text(
          'Delete "${collection.displayName}" and all linked data?\n\n'
          '$folderCount folder(s), $requestCount saved request(s), and '
          '$quickRequestCount Quick Request(s) will be deleted. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('api-tool-confirm-delete-collection'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final deleted = await _runRepositoryWrite(
      () => _repository.deleteApiToolCollection(collection.id),
    );
    if (!deleted || !mounted) return;

    if (_repository.apiToolCollections.isEmpty) {
      final savedDefault = await _runRepositoryWrite(
        () => _repository.saveApiToolCollections([
          ApiToolCollectionRoot(
            id: _defaultApiToolCollectionId,
            name: 'Default Collection',
            updatedAt: DateTime.now(),
          ),
        ]),
      );
      if (!savedDefault || !mounted) return;
    }

    final deletedFolderIds = _folders
        .where((folder) => folder.collectionId == collection.id)
        .map((folder) => folder.id)
        .toSet();
    setState(() {
      _expandedCollectionIds.remove(collection.id);
      _expandedFolderIds.removeAll(deletedFolderIds);
      _loadCollectionState(persistDefaults: false);
      _selectedFolderId = '';
      _activeRequestId = null;
      _error = null;
    });
    _clearRequest();
    _showApiToolSnack('Collection "${collection.displayName}" was deleted.');
  }

  Future<void> _createFolder(
    BuildContext context, {
    required String parentFolderId,
  }) async {
    final activeCollection = _activeCollection;
    if (activeCollection == null) return;
    final name = await _promptApiToolText(
      context,
      title: parentFolderId.isEmpty ? 'New Folder' : 'New Subfolder',
      label: 'Folder name',
      fallback: parentFolderId.isEmpty ? 'New Folder' : 'New Subfolder',
    );
    if (name == null || !mounted) return;

    final folder = ApiToolCollectionFolder(
      id: _newId('api_folder'),
      collectionId: activeCollection.id,
      parentFolderId: parentFolderId,
      name: name,
      updatedAt: DateTime.now(),
    );
    final updated = [..._folders, folder];
    final saved = await _runRepositoryWrite(
      () => _repository.saveApiToolFolders(updated),
    );
    if (!saved || !mounted) return;
    setState(() {
      _folders = _repository.apiToolFolders;
      _selectedCollectionId = activeCollection.id;
      _selectedFolderId = folder.id;
      _expandedCollectionIds.add(activeCollection.id);
      if (parentFolderId.isNotEmpty) {
        _expandedFolderIds.add(parentFolderId);
      }
      _activeRequestId = null;
    });
  }

  Future<void> _editEnvironments(BuildContext context) async {
    final activeCollection = _activeCollection;
    if (activeCollection == null) return;
    final updatedCollection = await showDialog<ApiToolCollectionRoot>(
      context: context,
      builder: (_) => _ApiToolEnvironmentDialog(collection: activeCollection),
    );
    if (updatedCollection == null || !mounted) return;

    await _saveCollectionRoot(updatedCollection);
  }

  Future<void> _setActiveEnvironment(String environmentId) async {
    final activeCollection = _activeCollection;
    if (activeCollection == null) return;
    await _saveCollectionRoot(
      activeCollection.copyWith(
        activeEnvironmentId: environmentId,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<bool> _saveCollectionRoot(ApiToolCollectionRoot collection) async {
    final updated =
        _collections.where((entry) => entry.id != collection.id).toList()
          ..add(collection);
    final saved = await _runRepositoryWrite(
      () => _repository.saveApiToolCollections(updated),
    );
    if (!saved || !mounted) return false;
    setState(() {
      _collections = _repository.apiToolCollections;
      _selectedCollectionId = collection.id;
    });
    return true;
  }

  ApiToolRequest _draftRequest({
    required String id,
    required DateTime updatedAt,
  }) {
    final headers = _headers
        .map((entry) => entry.toHeader())
        .where(
          (entry) =>
              entry.name.trim().isNotEmpty || entry.value.trim().isNotEmpty,
        )
        .toList(growable: false);
    final multipartFields = _multipartRows
        .map((entry) => entry.toEntry())
        .where(
          (entry) =>
              entry.name.trim().isNotEmpty || entry.value.trim().isNotEmpty,
        )
        .toList(growable: false);
    final urlEncodedFields = _urlEncodedRows
        .map((entry) => entry.toHeader())
        .where(
          (entry) =>
              entry.name.trim().isNotEmpty || entry.value.trim().isNotEmpty,
        )
        .toList(growable: false);

    return ApiToolRequest(
      id: id,
      name: _nameController.text.trim(),
      method: _method,
      url: _urlController.text.trim(),
      collectionId: _selectedCollectionId,
      folderId: _selectedFolderId,
      headers: headers,
      authorization: ApiToolAuthorization(
        type: _authorizationType,
        token: _authTokenController.text,
        username: _authUsernameController.text,
        password: _authPasswordController.text,
        apiKeyName: _authApiKeyNameController.text.trim(),
        apiKeyValue: _authApiKeyValueController.text,
      ),
      bodyMode: _bodyMode,
      body: _bodyController.text,
      multipartFields: multipartFields,
      urlEncodedFields: urlEncodedFields,
      updatedAt: updatedAt,
    );
  }

  void _loadRequest(
    ApiToolRequest request, {
    required String? activeRequestId,
  }) {
    setState(() {
      _activeRequestId = activeRequestId;
      _selectedCollectionId = request.collectionId.isEmpty
          ? _selectedCollectionId
          : request.collectionId;
      _selectedFolderId = request.folderId;
      _expandPathToFolder(_selectedCollectionId, request.folderId);
      _method = request.method;
      _replaceAuthorization(request.authorization);
      _bodyMode = request.bodyMode;
      _nameController.text = request.name;
      // Reset first so a previously disabled param cannot leak into the
      // request being loaded; the URL listener refills the rows.
      _replaceParamRows(const []);
      _urlController.text = request.url;
      _bodyController.text = request.body;
      _response = null;
      _error = null;
      _sentRequest = null;
      _replaceHeaders(request.headers);
      _replaceMultipartFields(request.multipartFields);
      _replaceUrlEncodedFields(request.urlEncodedFields);
    });
  }

  void _expandPathToFolder(String collectionId, String folderId) {
    if (collectionId.isNotEmpty) {
      _expandedCollectionIds.add(collectionId);
    }
    var currentFolderId = folderId;
    final visited = <String>{};
    while (currentFolderId.isNotEmpty && visited.add(currentFolderId)) {
      _expandedFolderIds.add(currentFolderId);
      ApiToolCollectionFolder? currentFolder;
      for (final folder in _folders) {
        if (folder.id == currentFolderId) {
          currentFolder = folder;
          break;
        }
      }
      if (currentFolder == null) break;
      currentFolderId = currentFolder.parentFolderId;
    }
  }

  void _clearRequest() {
    setState(() {
      _activeRequestId = null;
      _method = ApiToolMethod.get;
      _replaceAuthorization(const ApiToolAuthorization());
      _bodyMode = ApiToolBodyMode.raw;
      _nameController.clear();
      _urlController.clear();
      _bodyController.clear();
      _response = null;
      _error = null;
      _replaceHeaders(const []);
      _replaceMultipartFields(const []);
      _replaceUrlEncodedFields(const []);
      _replaceParamRows(const []);
      _sentRequest = null;
    });
  }

  void _replaceAuthorization(ApiToolAuthorization authorization) {
    _authorizationType = authorization.type;
    _authTokenController.text = authorization.token;
    _authUsernameController.text = authorization.username;
    _authPasswordController.text = authorization.password;
    _authApiKeyNameController.text = authorization.apiKeyName;
    _authApiKeyValueController.text = authorization.apiKeyValue;
  }

  void _replaceHeaders(List<ApiToolHeader> headers) {
    for (final header in _headers) {
      header.dispose();
    }
    final nextHeaders = headers.isEmpty
        ? [ApiToolHeader(id: _newHeaderId())]
        : headers;
    _headers = nextHeaders
        .map(
          (header) => _ApiToolHeaderEditor(
            id: header.id.isEmpty ? _newHeaderId() : header.id,
            name: header.name,
            value: header.value,
            enabled: header.enabled,
          ),
        )
        .toList();
  }

  void _addHeaderRow() {
    setState(() {
      _headers.add(_ApiToolHeaderEditor(id: _newHeaderId()));
    });
  }

  void _removeHeaderRow(int index) {
    if (_headers.length == 1) return;
    setState(() {
      final removed = _headers.removeAt(index);
      removed.dispose();
    });
  }

  void _replaceMultipartFields(List<ApiToolMultipartEntry> entries) {
    for (final row in _multipartRows) {
      row.dispose();
    }
    final nextEntries = entries.isEmpty
        ? [ApiToolMultipartEntry(id: _newMultipartId())]
        : entries;
    _multipartRows = nextEntries
        .map(
          (entry) => _ApiToolMultipartEditor(
            id: entry.id.isEmpty ? _newMultipartId() : entry.id,
            kind: entry.kind,
            name: entry.name,
            value: entry.value,
            contentType: entry.contentType,
            enabled: entry.enabled,
          ),
        )
        .toList();
  }

  void _addMultipartRow() {
    setState(() {
      _multipartRows.add(_ApiToolMultipartEditor(id: _newMultipartId()));
    });
  }

  void _removeMultipartRow(int index) {
    if (_multipartRows.length == 1) return;
    setState(() {
      final removed = _multipartRows.removeAt(index);
      removed.dispose();
    });
  }

  void _replaceUrlEncodedFields(List<ApiToolHeader> entries) {
    for (final row in _urlEncodedRows) {
      row.dispose();
    }
    final nextEntries = entries.isEmpty
        ? [ApiToolHeader(id: _newUrlEncodedId())]
        : entries;
    _urlEncodedRows = nextEntries
        .map(
          (entry) => _ApiToolHeaderEditor(
            id: entry.id.isEmpty ? _newUrlEncodedId() : entry.id,
            name: entry.name,
            value: entry.value,
            enabled: entry.enabled,
          ),
        )
        .toList();
  }

  void _addUrlEncodedRow() {
    setState(() {
      _urlEncodedRows.add(_ApiToolHeaderEditor(id: _newUrlEncodedId()));
    });
  }

  void _removeUrlEncodedRow(int index) {
    if (_urlEncodedRows.length == 1) return;
    setState(() {
      final removed = _urlEncodedRows.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _pickMultipartFile(_ApiToolMultipartEditor row) async {
    final file = await file_selector.openFile();
    if (file == null || !mounted) return;
    setState(() {
      row.valueController.text = file.path;
    });
  }

  void _cancelRequest() {
    _cancelToken?.cancel();
  }

  void _copyResponse() {
    final response = _response;
    final error = _error;
    final text = response != null
        ? [
            'Status: ${response.statusCode} ${response.reasonPhrase}',
            'Duration: ${_durationLabelMs(response.durationMs)}',
            '',
            _formatHeaders(response.headers),
            '',
            response.body,
          ].join('\n').trim()
        : error ?? '';
    Clipboard.setData(ClipboardData(text: text));
  }

  void _syncFormState() {
    _syncParamsFromUrl();
    if (mounted) setState(() {});
  }

  String _fallbackName(ApiToolRequest request) {
    final host = Uri.tryParse(request.url.trim())?.host;
    final suffix = (host == null || host.isEmpty) ? 'request' : host;
    return '${request.method.label} $suffix';
  }

  String _formatHeaders(Map<String, List<String>> headers) {
    if (headers.isEmpty) return '';
    final lines = <String>[];
    final names = headers.keys.toList()..sort();
    for (final name in names) {
      lines.add('$name: ${headers[name]!.join(', ')}');
    }
    return lines.join('\n');
  }

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

  String _newHeaderId() {
    _headerSerial += 1;
    return 'api_header_${DateTime.now().microsecondsSinceEpoch}_$_headerSerial';
  }

  String _newMultipartId() {
    _multipartSerial += 1;
    return 'api_part_${DateTime.now().microsecondsSinceEpoch}_$_multipartSerial';
  }

  String _newUrlEncodedId() {
    _urlEncodedSerial += 1;
    return 'api_urlencoded_${DateTime.now().microsecondsSinceEpoch}_$_urlEncodedSerial';
  }

  String _ageLabel(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    if (now.difference(local).inHours < 24 && now.day == local.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }

  String _durationLabelMs(int? durationMs) {
    if (durationMs == null) return '-';
    if (durationMs < 1000) return '${durationMs}ms';
    return '${(durationMs / 1000).toStringAsFixed(2)}s';
  }

  // ---------------------------------------------------------------------------
  // Query parameters <-> URL synchronisation
  // ---------------------------------------------------------------------------

  /// Splits the URL into `[before '?', query, fragment]` without going through
  /// [Uri], which would mangle `{{TOKEN}}` placeholders.
  static ({String base, String query, String fragment}) _splitUrl(String url) {
    var rest = url;
    var fragment = '';
    final hash = rest.indexOf('#');
    if (hash >= 0) {
      fragment = rest.substring(hash);
      rest = rest.substring(0, hash);
    }
    final mark = rest.indexOf('?');
    if (mark < 0) return (base: rest, query: '', fragment: fragment);
    return (
      base: rest.substring(0, mark),
      query: rest.substring(mark + 1),
      fragment: fragment,
    );
  }

  static List<MapEntry<String, String>> _parseQueryPairs(String query) {
    if (query.isEmpty) return const [];
    final pairs = <MapEntry<String, String>>[];
    for (final chunk in query.split('&')) {
      if (chunk.isEmpty) continue;
      final split = chunk.indexOf('=');
      if (split < 0) {
        pairs.add(MapEntry(chunk, ''));
      } else {
        pairs.add(
          MapEntry(chunk.substring(0, split), chunk.substring(split + 1)),
        );
      }
    }
    return pairs;
  }

  List<MapEntry<String, String>> get _enabledParamPairs => _paramRows
      .where((row) => row.enabled && row.nameController.text.trim().isNotEmpty)
      .map(
        (row) =>
            MapEntry(row.nameController.text.trim(), row.valueController.text),
      )
      .toList(growable: false);

  /// URL -> rows. Runs on every URL edit; rebuilds rows only when the query
  /// string actually differs so the caret never jumps while typing.
  void _syncParamsFromUrl() {
    if (_syncingParams) return;
    final parsed = _parseQueryPairs(_splitUrl(_urlController.text).query);
    final current = _enabledParamPairs;
    if (parsed.length == current.length) {
      var identical = true;
      for (var index = 0; index < parsed.length; index++) {
        if (parsed[index].key != current[index].key ||
            parsed[index].value != current[index].value) {
          identical = false;
          break;
        }
      }
      if (identical) return;
    }

    _syncingParams = true;
    try {
      final disabled = _paramRows
          .where(
            (row) => !row.enabled && row.nameController.text.trim().isNotEmpty,
          )
          .map(
            (row) => ApiToolHeader(
              id: row.id,
              name: row.nameController.text,
              value: row.valueController.text,
              enabled: false,
            ),
          )
          .toList();
      _replaceParamRows([
        for (final pair in parsed)
          ApiToolHeader(id: _newParamId(), name: pair.key, value: pair.value),
        ...disabled,
      ]);
    } finally {
      _syncingParams = false;
    }
  }

  /// Rows -> URL. Rewrites only the query segment, leaving path and fragment
  /// untouched.
  void _syncUrlFromParams() {
    if (_syncingParams) return;
    _syncingParams = true;
    try {
      final parts = _splitUrl(_urlController.text);
      final query = _enabledParamPairs
          .map((pair) => '${pair.key}=${pair.value}')
          .join('&');
      final next =
          parts.base + (query.isEmpty ? '' : '?$query') + parts.fragment;
      if (next != _urlController.text) {
        final atEnd =
            _urlController.selection.baseOffset >= _urlController.text.length;
        _urlController.value = TextEditingValue(
          text: next,
          selection: atEnd
              ? TextSelection.collapsed(offset: next.length)
              : _urlController.selection,
        );
      }
    } finally {
      _syncingParams = false;
    }
    _syncFormState();
  }

  void _replaceParamRows(List<ApiToolHeader> entries) {
    // This can run from inside a row controller's own notifyListeners() (a
    // typed '&' re-splits the query), and disposing a ChangeNotifier mid
    // notification asserts. Detach now, dispose after the frame.
    final stale = _paramRows;
    for (final row in stale) {
      row.nameController.removeListener(_syncUrlFromParams);
      row.valueController.removeListener(_syncUrlFromParams);
    }
    if (stale.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final row in stale) {
          row.dispose();
        }
      });
    }
    final nextEntries = entries.isEmpty
        ? [ApiToolHeader(id: _newParamId())]
        : entries;
    _paramRows = nextEntries
        .map(
          (entry) => _ApiToolHeaderEditor(
            id: entry.id.isEmpty ? _newParamId() : entry.id,
            name: entry.name,
            value: entry.value,
            enabled: entry.enabled,
          ),
        )
        .toList();
    for (final row in _paramRows) {
      row.nameController.addListener(_syncUrlFromParams);
      row.valueController.addListener(_syncUrlFromParams);
    }
  }

  void _addParamRow() {
    setState(() {
      final row = _ApiToolHeaderEditor(id: _newParamId());
      row.nameController.addListener(_syncUrlFromParams);
      row.valueController.addListener(_syncUrlFromParams);
      _paramRows.add(row);
    });
  }

  void _removeParamRow(int index) {
    if (_paramRows.length == 1) return;
    setState(() {
      final removed = _paramRows.removeAt(index);
      removed.nameController.removeListener(_syncUrlFromParams);
      removed.valueController.removeListener(_syncUrlFromParams);
      removed.dispose();
    });
  }

  void _clearParamRows() {
    setState(() => _replaceParamRows(const []));
    _syncUrlFromParams();
  }

  String _newParamId() {
    _paramSerial += 1;
    return 'param_$_paramSerial';
  }

  // ---------------------------------------------------------------------------
  // One-click developer actions
  // ---------------------------------------------------------------------------

  void _beautifyRawBody() {
    final source = _bodyController.text;
    final formatted = prettyPrintJsonText(source);
    if (formatted == source) {
      _showApiToolSnack('Body is not valid JSON, nothing to format.');
      return;
    }
    _bodyController.text = formatted;
    _syncFormState();
  }

  /// Copies the request as a curl command with environment tokens resolved, so
  /// the command can be pasted straight into a terminal.
  void _copyRequestAsCurl() {
    final draft = _draftRequest(
      id: _activeRequestId ?? 'api_request_draft',
      updatedAt: DateTime.now(),
    );
    final variables = _activeCollection?.activeVariables ?? const {};
    final resolved = variables.isEmpty
        ? draft
        : resolveApiToolRequestVariables(draft, variables);
    unawaited(
      Clipboard.setData(ClipboardData(text: _apiToolCurlCommand(resolved))),
    );
    _showApiToolSnack('curl command copied to the clipboard.');
  }

  String _payloadSizeLabel(String body) {
    final bytes = utf8.encode(body).length;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

Future<String?> _promptApiToolText(
  BuildContext context, {
  required String title,
  required String label,
  required String fallback,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ApiToolTextPromptDialog(
      title: title,
      label: label,
      fallback: fallback,
    ),
  );
}

/// Platform-correct label for the "send request" chord.
String _apiToolSendShortcutLabel() {
  return defaultTargetPlatform == TargetPlatform.macOS
      ? 'Cmd+Enter'
      : 'Ctrl+Enter';
}

/// Platform-correct label for the "save request" chord.
String _apiToolSaveShortcutLabel() {
  return defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd+S' : 'Ctrl+S';
}

String _apiToolShellQuote(String value) {
  return "'${value.replaceAll("'", r"'\''")}'";
}

/// Builds a terminal-ready curl command for [request]. The request is expected
/// to already have its environment tokens resolved.
String _apiToolCurlCommand(ApiToolRequest request) {
  final lines = <String>[
    'curl -X ${request.method.label} ${_apiToolShellQuote(request.url.trim())}',
  ];

  final headers = request.enabledHeaders.entries.toList()
    ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
  for (final header in headers) {
    lines.add('  -H ${_apiToolShellQuote('${header.key}: ${header.value}')}');
  }

  switch (request.bodyMode) {
    case ApiToolBodyMode.raw:
      final body = request.body;
      if (body.trim().isNotEmpty) {
        lines.add('  --data-raw ${_apiToolShellQuote(body)}');
      }
    case ApiToolBodyMode.multipart:
      for (final field in request.multipartFields) {
        if (!field.enabled || !field.hasName) continue;
        final value = field.isFile ? '@${field.value}' : field.value;
        final typed = field.contentType.trim().isEmpty
            ? value
            : '$value;type=${field.contentType.trim()}';
        lines.add('  -F ${_apiToolShellQuote('${field.name}=$typed')}');
      }
    case ApiToolBodyMode.urlEncoded:
      for (final field in request.urlEncodedFields) {
        if (!field.enabled || !field.hasName) continue;
        lines.add(
          '  --data-urlencode ${_apiToolShellQuote('${field.name}=${field.value}')}',
        );
      }
  }

  return lines.join(' \\\n');
}
