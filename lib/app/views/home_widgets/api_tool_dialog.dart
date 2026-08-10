part of '../home_view.dart';

bool _apiToolDialogVisible = false;
const _defaultApiToolCollectionId = 'api_collection_default';
final _apiToolEnvTokenPattern = RegExp(r'\{\{\s*([^{}]+?)\s*\}\}');

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

class _ApiToolDialogState extends State<_ApiToolDialog> {
  final _nameController = TextEditingController();
  final _urlController = _ApiToolEnvTextEditingController();
  final _bodyController = _ApiToolEnvTextEditingController();
  final _requestScrollController = ScrollController();
  final _multipartScrollController = ScrollController();
  final _responseScrollController = ScrollController();
  final _sidebarScrollController = ScrollController();
  final _requestSearchController = TextEditingController();
  final _environmentVariablesMenuController = MenuController();

  final _historyLimit = 50;
  var _method = ApiToolMethod.get;
  var _headers = <_ApiToolHeaderEditor>[];
  var _collections = <ApiToolCollectionRoot>[];
  var _folders = <ApiToolCollectionFolder>[];
  var _collection = <ApiToolRequest>[];
  var _history = <ApiToolHistoryEntry>[];
  var _headerSerial = 0;
  var _multipartSerial = 0;
  var _selectedCollectionId = '';
  var _selectedFolderId = '';
  String? _activeRequestId;
  var _bodyMode = ApiToolBodyMode.raw;
  var _multipartRows = <_ApiToolMultipartEditor>[];
  ApiToolResponse? _response;
  String? _error;
  bool _isSending = false;
  bool _isRefreshingRepository = false;
  bool _isImportingPostman = false;
  ApiToolCancellationToken? _cancelToken;

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
    _requestSearchController.addListener(_syncFormState);
    _loadCollectionState();
    unawaited(_refreshCollectionState());
    _history = _localStore.apiToolHistory;
    _replaceHeaders(const []);
    _replaceMultipartFields(const []);
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
    _selectedCollectionId = selectedCollectionId;
    final folderIds = _folders
        .where((folder) => folder.collectionId == selectedCollectionId)
        .map((folder) => folder.id)
        .toSet();
    _selectedFolderId =
        previousFolderId.isEmpty || folderIds.contains(previousFolderId)
        ? previousFolderId
        : '';

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
    _requestSearchController.removeListener(_syncFormState);
    _nameController.dispose();
    _urlController.dispose();
    _bodyController.dispose();
    _requestSearchController.dispose();
    _requestScrollController.dispose();
    _multipartScrollController.dispose();
    _responseScrollController.dispose();
    _sidebarScrollController.dispose();
    for (final header in _headers) {
      header.dispose();
    }
    for (final row in _multipartRows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width < 760 ? size.width * 0.98 : size.width * 0.96;
    final height = size.height < 640 ? size.height * 0.98 : size.height * 0.94;

    return SafeArea(
      child: Center(
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
                  AppCyberTheme.panelBackgroundStrong.withValues(alpha: 0.94),
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
    );
  }

  Widget _buildHeader(BuildContext context) {
    final canSend = !_isSending && _urlController.text.trim().isNotEmpty;
    final activeCollection = _activeCollection;
    final activeEnvironment = _activeEnvironment;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 14),
      decoration: BoxDecoration(
        color: AppCyberTheme.baseBackground.withValues(alpha: 0.22),
        border: Border(
          bottom: BorderSide(
            color: AppCyberTheme.electricBlue.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppCyberTheme.electricBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppCyberTheme.electricBlue.withValues(alpha: 0.46),
                  ),
                ),
                child: const SizedBox.square(
                  dimension: 38,
                  child: Icon(Icons.http_outlined),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'API Tool',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Obx(() {
                      final label = _repository.workspaceLabel.value;
                      final status = _repository.repositoryStatus.value;
                      final text = status.isEmpty ? label : '$label - $status';
                      return Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildHeaderCollectionDropdown(),
              const SizedBox(width: 6),
              _buildHeaderEnvironmentDropdown(activeCollection),
              const SizedBox(width: 6),
              _buildEnvironmentVariablesMenu(activeEnvironment),
              IconButton(
                key: const Key('close-api-tool'),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 116,
                child: KeyedSubtree(
                  key: const Key('api-tool-method'),
                  child: DropdownButtonFormField<ApiToolMethod>(
                    key: ValueKey(_method),
                    initialValue: _method,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Method',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    items: ApiToolMethod.values
                        .map(
                          (method) => DropdownMenuItem(
                            value: method,
                            child: Text(method.label),
                          ),
                        )
                        .toList(),
                    onChanged: _isSending
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _method = value);
                          },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildVariableDropField(
                  controller: _urlController,
                  enabled: !_isSending,
                  child: TextField(
                    key: const Key('api-tool-url'),
                    controller: _urlController,
                    enabled: !_isSending,
                    onSubmitted: (_) {
                      if (canSend) unawaited(_sendRequest());
                    },
                    style: AppCyberTheme.dataTextStyle(
                      size: 12,
                      color: AppCyberTheme.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'URL',
                      hintText: 'https://api.example.com/users',
                      prefixIcon: Icon(Icons.link_outlined),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                key: const Key('api-tool-send'),
                onPressed: canSend ? _sendRequest : null,
                icon: _isSending
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(_isSending ? 'Sending' : 'Send'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('api-tool-cancel'),
                onPressed: _isSending ? _cancelRequest : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCollectionDropdown() {
    final collectionIds = _collections.map((entry) => entry.id).toSet();
    final selectedId = collectionIds.contains(_selectedCollectionId)
        ? _selectedCollectionId
        : null;

    return SizedBox(
      width: 146,
      child: KeyedSubtree(
        key: const Key('api-tool-collection-root'),
        child: DropdownButtonFormField<String>(
          key: ValueKey('header-collection-${selectedId ?? ''}'),
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Collection',
            prefixIcon: Icon(Icons.folder_copy_outlined, size: 18),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          items: [
            for (final collection in _collections)
              DropdownMenuItem(
                value: collection.id,
                child: Text(
                  collection.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _isSending
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedCollectionId = value;
                    _selectedFolderId = '';
                    _activeRequestId = null;
                  });
                },
        ),
      ),
    );
  }

  Widget _buildHeaderEnvironmentDropdown(ApiToolCollectionRoot? collection) {
    final activeEnvironmentId =
        collection?.environments.any(
              (environment) => environment.id == collection.activeEnvironmentId,
            ) ==
            true
        ? collection!.activeEnvironmentId
        : '';

    return SizedBox(
      width: 112,
      child: KeyedSubtree(
        key: const Key('api-tool-active-environment'),
        child: DropdownButtonFormField<String>(
          key: ValueKey(
            'header-environment-${collection?.id ?? ''}-$activeEnvironmentId',
          ),
          initialValue: activeEnvironmentId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Env',
            prefixIcon: Icon(Icons.public_outlined, size: 18),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('None')),
            if (collection != null)
              for (final environment in collection.environments)
                DropdownMenuItem(
                  value: environment.id,
                  child: Text(
                    environment.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ],
          onChanged: _isSending || collection == null
              ? null
              : (value) => _setActiveEnvironment(value ?? ''),
        ),
      ),
    );
  }

  Widget _buildEnvironmentVariablesMenu(ApiToolEnvironment? environment) {
    final variables =
        environment?.variables
            .where((variable) => variable.enabled && variable.hasName)
            .toList(growable: false) ??
        const <ApiToolEnvironmentVariable>[];
    final hasVariables = variables.isNotEmpty;

    return MenuAnchor(
      controller: _environmentVariablesMenuController,
      menuChildren: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 282),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _MetaChip(
                  icon: Icons.tune_outlined,
                  label: '${variables.length} variable(s)',
                  highlighted: true,
                ),
                if (variables.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    key: const Key('api-tool-env-token-list'),
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final variable in variables)
                        _ApiToolEnvTokenChip(
                          key: Key(
                            'api-tool-env-token-${variable.name.trim()}',
                          ),
                          token: '{{${variable.name.trim()}}}',
                          onDragStarted:
                              _environmentVariablesMenuController.close,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
      builder: (context, controller, child) {
        return Tooltip(
          message: hasVariables
              ? 'Show environment variables'
              : 'No environment variables',
          child: SizedBox.square(
            dimension: 38,
            child: OutlinedButton(
              key: const Key('api-tool-env-vars-menu'),
              onPressed: hasVariables
                  ? () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    }
                  : null,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(38),
                fixedSize: const Size.square(38),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: const Icon(Icons.tune_outlined, size: 18),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 940;
        if (compact) {
          return Column(
            children: [
              SizedBox(height: 190, child: _buildSidebar()),
              Divider(height: 1, color: AppCyberTheme.lineBlue),
              Expanded(child: _buildWorkspace(compact: true)),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 292, child: _buildSidebar()),
            VerticalDivider(width: 1, color: AppCyberTheme.lineBlue),
            Expanded(child: _buildWorkspace(compact: false)),
          ],
        );
      },
    );
  }

  Widget _buildSidebar() {
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          children: [
            TabBar(
              tabs: [
                Tab(
                  key: Key('api-tool-collections-tab'),
                  child: _CompactTabLabel(
                    icon: Icons.folder_copy_outlined,
                    label: 'Collections',
                  ),
                ),
                Tab(
                  key: Key('api-tool-history-tab'),
                  child: _CompactTabLabel(
                    icon: Icons.history_outlined,
                    label: 'History',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: [_buildCollectionList(), _buildHistoryList()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCollectionToolbar(),
        const SizedBox(height: 8),
        _buildRequestSearchField(),
        const SizedBox(height: 8),
        Expanded(
          child: Scrollbar(
            controller: _sidebarScrollController,
            thumbVisibility: true,
            child: ListView(
              key: const Key('api-tool-collection-list'),
              controller: _sidebarScrollController,
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              children: _collectionTreeRows(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCollectionToolbar() {
    final activeCollection = _activeCollection;
    final canEdit =
        _repository.canWriteApiTools.value &&
        !_isRefreshingRepository &&
        !_isImportingPostman;
    final isTeamMode = _repository.isTeamMode;
    final canImport = canEdit && isTeamMode && _repository.hasLocalApiToolData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ApiToolSidebarActionButton(
                buttonKey: const Key('api-tool-add-collection'),
                tooltip: 'New collection',
                onPressed: _isSending || !canEdit
                    ? null
                    : () => _createCollection(context),
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
              const SizedBox(width: 6),
              _ApiToolSidebarActionButton(
                buttonKey: const Key('api-tool-add-folder'),
                tooltip: 'New folder',
                onPressed:
                    _isSending || !canEdit || _selectedCollectionId.isEmpty
                    ? null
                    : () => _createFolder(context, parentFolderId: ''),
                icon: const Icon(Icons.folder_outlined),
              ),
              const SizedBox(width: 6),
              _ApiToolSidebarActionButton(
                buttonKey: const Key('api-tool-add-subfolder'),
                tooltip: 'New subfolder',
                onPressed: _isSending || !canEdit || _selectedFolderId.isEmpty
                    ? null
                    : () => _createFolder(
                        context,
                        parentFolderId: _selectedFolderId,
                      ),
                icon: const Icon(Icons.snippet_folder_outlined),
              ),
              const SizedBox(width: 6),
              _ApiToolSidebarActionButton(
                buttonKey: const Key('api-tool-environments'),
                tooltip: 'Edit environment',
                onPressed: _isSending || !canEdit || activeCollection == null
                    ? null
                    : () => _editEnvironments(context),
                icon: const Icon(Icons.public_outlined),
              ),
              const SizedBox(width: 6),
              _ApiToolSidebarActionButton(
                buttonKey: const Key('api-tool-import-postman'),
                tooltip: 'Import Postman collection',
                onPressed: _isSending || !canEdit
                    ? null
                    : _importPostmanCollection,
                icon: _isImportingPostman
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_upload_outlined),
              ),
              if (isTeamMode) ...[
                const SizedBox(width: 6),
                _ApiToolSidebarActionButton(
                  buttonKey: const Key('api-tool-import-local'),
                  tooltip: 'Import local tools to team',
                  onPressed: _isSending || !canImport
                      ? null
                      : _importLocalApiTools,
                  icon: const Icon(Icons.upload_file_outlined),
                ),
                const SizedBox(width: 6),
                _ApiToolSidebarActionButton(
                  buttonKey: const Key('api-tool-refresh-team'),
                  tooltip: 'Refresh HTTP Tools',
                  onPressed: _isRefreshingRepository || _isImportingPostman
                      ? null
                      : () => unawaited(_refreshCollectionState()),
                  icon: _isRefreshingRepository
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_outlined),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRequestSearchField() {
    final searchTerm = _requestSearchTerm;
    final totalCount = _activeCollectionRequests.length;
    final matchCount = searchTerm.isEmpty
        ? totalCount
        : _activeCollectionRequests
              .where((request) => _requestMatchesSearch(request, searchTerm))
              .length;

    return TextField(
      key: const Key('api-tool-request-search'),
      controller: _requestSearchController,
      style: AppCyberTheme.dataTextStyle(
        size: 11.2,
        color: AppCyberTheme.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: 'Search requests',
        hintText: 'Name, URL, method',
        prefixIcon: const Icon(Icons.search_outlined),
        suffixIcon: searchTerm.isEmpty
            ? _ApiToolSearchCountBadge(label: totalCount.toString())
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ApiToolSearchCountBadge(label: '$matchCount/$totalCount'),
                  IconButton(
                    key: const Key('api-tool-clear-request-search'),
                    tooltip: 'Clear search',
                    onPressed: _requestSearchController.clear,
                    icon: const Icon(Icons.close_outlined, size: 18),
                  ),
                ],
              ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
      ),
    );
  }

  bool _requestMatchesSearch(ApiToolRequest request, String searchTerm) {
    if (searchTerm.isEmpty) return true;
    final haystack = [
      request.displayName,
      request.name,
      request.method.label,
      request.url,
      for (final header in request.headers) header.name,
    ].join('\n').toLowerCase();
    return haystack.contains(searchTerm);
  }

  bool _folderMatchesSearch(ApiToolCollectionFolder folder, String searchTerm) {
    return searchTerm.isEmpty ||
        folder.displayName.toLowerCase().contains(searchTerm);
  }

  bool _folderHasSearchMatch(
    ApiToolCollectionFolder folder,
    String searchTerm,
  ) {
    if (searchTerm.isEmpty || _folderMatchesSearch(folder, searchTerm)) {
      return true;
    }
    final hasMatchingRequest = _activeCollectionRequests.any(
      (request) =>
          request.folderId == folder.id &&
          _requestMatchesSearch(request, searchTerm),
    );
    if (hasMatchingRequest) return true;

    return _activeCollectionFolders
        .where((child) => child.parentFolderId == folder.id)
        .any((child) => _folderHasSearchMatch(child, searchTerm));
  }

  List<Widget> _collectionTreeRows() {
    final rows = <Widget>[];
    final activeCollection = _activeCollection;
    final searchTerm = _requestSearchTerm;
    if (activeCollection == null) {
      rows.add(
        _ApiToolEmptyTreeMessage(
          label: 'Create a collection to save requests.',
        ),
      );
      return rows;
    }

    rows.add(
      _ApiToolFolderTile(
        key: Key('api-tool-root-folder-${activeCollection.id}'),
        title: activeCollection.displayName,
        subtitle: 'Root collection',
        depth: 0,
        selected: _selectedFolderId.isEmpty,
        onTap: () => setState(() {
          _selectedFolderId = '';
          _activeRequestId = null;
        }),
      ),
    );
    rows.add(const SizedBox(height: 8));
    final contentStartIndex = rows.length;
    _appendRequestRows(
      rows,
      parentFolderId: '',
      depth: 1,
      searchTerm: searchTerm,
    );

    final rootFolders =
        _activeCollectionFolders
            .where((folder) => folder.parentFolderId.isEmpty)
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    for (final folder in rootFolders) {
      _appendFolderRows(rows, folder, 1, searchTerm: searchTerm);
    }

    if (_activeCollectionRequests.isEmpty && rootFolders.isEmpty) {
      rows.add(
        const _ApiToolEmptyTreeMessage(
          label: 'No requests or folders in this collection.',
        ),
      );
    } else if (searchTerm.isNotEmpty && rows.length == contentStartIndex) {
      rows.add(
        _ApiToolEmptyTreeMessage(
          label: 'No requests match "${_requestSearchController.text.trim()}".',
        ),
      );
    }

    return rows;
  }

  void _appendFolderRows(
    List<Widget> rows,
    ApiToolCollectionFolder folder,
    int depth, {
    required String searchTerm,
  }) {
    if (searchTerm.isNotEmpty && !_folderHasSearchMatch(folder, searchTerm)) {
      return;
    }

    rows.add(
      _ApiToolFolderTile(
        key: Key('api-tool-folder-${folder.id}'),
        title: folder.displayName,
        subtitle: 'Folder',
        depth: depth,
        selected: _selectedFolderId == folder.id,
        onTap: () => setState(() {
          _selectedFolderId = folder.id;
          _activeRequestId = null;
        }),
      ),
    );
    rows.add(const SizedBox(height: 8));
    _appendRequestRows(
      rows,
      parentFolderId: folder.id,
      depth: depth + 1,
      searchTerm: searchTerm,
    );

    final children =
        _activeCollectionFolders
            .where((entry) => entry.parentFolderId == folder.id)
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    for (final child in children) {
      _appendFolderRows(rows, child, depth + 1, searchTerm: searchTerm);
    }
  }

  void _appendRequestRows(
    List<Widget> rows, {
    required String parentFolderId,
    required int depth,
    required String searchTerm,
  }) {
    final requests =
        _activeCollectionRequests
            .where(
              (request) =>
                  request.folderId == parentFolderId &&
                  _requestMatchesSearch(request, searchTerm),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    for (final request in requests) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 12.0),
          child: _ApiToolRequestTile(
            key: Key('api-tool-collection-${request.id}'),
            method: request.method,
            title: request.displayName,
            subtitle: request.url,
            selected: _activeRequestId == request.id,
            trailing: _ageLabel(request.updatedAt),
            onTap: () => _loadRequest(request, activeRequestId: request.id),
          ),
        ),
      );
      rows.add(const SizedBox(height: 8));
    }
  }

  Widget _buildHistoryList() {
    if (_history.isEmpty) {
      return Center(
        child: Text(
          'No calls yet',
          style: AppCyberTheme.dataTextStyle(
            size: 11.2,
            color: AppCyberTheme.textMuted,
          ),
        ),
      );
    }

    return ListView.separated(
      key: const Key('api-tool-history-list'),
      itemCount: _history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = _history[index];
        final status = entry.error.trim().isNotEmpty
            ? 'ERR'
            : (entry.statusCode?.toString() ?? '-');
        final savedId =
            _collection.any((request) => request.id == entry.request.id)
            ? entry.request.id
            : null;
        return _ApiToolRequestTile(
          key: Key('api-tool-history-${entry.id}'),
          method: entry.request.method,
          title: entry.request.displayName,
          subtitle: entry.request.url,
          selected: false,
          trailing: '$status  ${_durationLabelMs(entry.durationMs)}',
          onTap: () => _loadRequest(entry.request, activeRequestId: savedId),
        );
      },
    );
  }

  Widget _buildWorkspace({required bool compact}) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Expanded(child: _buildRequestPanel()),
            const SizedBox(height: 12),
            Expanded(child: _buildResponsePanel()),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 420, child: _buildRequestPanel()),
          const SizedBox(width: 14),
          Expanded(child: _buildResponsePanel()),
        ],
      ),
    );
  }

  Widget _buildRequestPanel() {
    final canEdit = _repository.canWriteApiTools.value;
    final canSave = canEdit && _urlController.text.trim().isNotEmpty;
    final hasActiveRequest = _activeRequestId != null;

    return _HudCardShell(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _PanelTitle(icon: Icons.tune_outlined, title: 'Request'),
              const Spacer(),
              IconButton(
                key: const Key('api-tool-new'),
                tooltip: 'New request',
                onPressed: _isSending ? null : _clearRequest,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('api-tool-name'),
            controller: _nameController,
            enabled: !_isSending,
            style: AppCyberTheme.dataTextStyle(
              size: 11.5,
              color: AppCyberTheme.textPrimary,
            ),
            decoration: const InputDecoration(
              labelText: 'Request name',
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('api-tool-save'),
                onPressed: canSave && !_isSending
                    ? () => unawaited(_saveRequest(asNew: false))
                    : null,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
              OutlinedButton.icon(
                key: const Key('api-tool-save-as'),
                onPressed: canSave && !_isSending
                    ? () => unawaited(_saveRequest(asNew: true))
                    : null,
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Save as'),
              ),
              OutlinedButton.icon(
                key: const Key('api-tool-delete'),
                onPressed: canEdit && hasActiveRequest && !_isSending
                    ? () => unawaited(_deleteActiveRequest())
                    : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(
                        key: Key('api-tool-headers-tab'),
                        icon: Icon(Icons.view_headline_outlined),
                        text: 'Headers',
                      ),
                      Tab(
                        key: Key('api-tool-body-tab'),
                        icon: Icon(Icons.data_object_outlined),
                        text: 'Body',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TabBarView(
                      children: [_buildHeadersEditor(), _buildBodyEditor()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeadersEditor() {
    return Scrollbar(
      controller: _requestScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _requestScrollController,
        padding: const EdgeInsets.only(right: 8, bottom: 4),
        child: Column(
          children: [
            for (var index = 0; index < _headers.length; index++) ...[
              _buildHeaderRow(index),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('api-tool-add-header'),
                onPressed: _isSending ? null : _addHeaderRow,
                icon: const Icon(Icons.add_outlined),
                label: const Text('Add header'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(int index) {
    final header = _headers[index];
    return Row(
      children: [
        Checkbox(
          value: header.enabled,
          onChanged: _isSending
              ? null
              : (value) => setState(() => header.enabled = value ?? true),
        ),
        Expanded(
          child: _buildVariableDropField(
            controller: header.nameController,
            enabled: !_isSending && header.enabled,
            child: TextField(
              key: Key('api-tool-header-name-$index'),
              controller: header.nameController,
              enabled: !_isSending && header.enabled,
              style: AppCyberTheme.dataTextStyle(
                size: 11.2,
                color: AppCyberTheme.textPrimary,
              ),
              decoration: const InputDecoration(labelText: 'Key'),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildVariableDropField(
            controller: header.valueController,
            enabled: !_isSending && header.enabled,
            child: TextField(
              key: Key('api-tool-header-value-$index'),
              controller: header.valueController,
              enabled: !_isSending && header.enabled,
              style: AppCyberTheme.dataTextStyle(
                size: 11.2,
                color: AppCyberTheme.textPrimary,
              ),
              decoration: const InputDecoration(labelText: 'Value'),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Remove header',
          onPressed: _isSending || _headers.length == 1
              ? null
              : () => _removeHeaderRow(index),
          icon: const Icon(Icons.remove_circle_outline),
        ),
      ],
    );
  }

  Widget _buildBodyEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<ApiToolBodyMode>(
            key: const Key('api-tool-body-mode'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: ApiToolBodyMode.raw,
                icon: Icon(Icons.data_object_outlined),
                label: Text('Raw'),
              ),
              ButtonSegment(
                value: ApiToolBodyMode.multipart,
                icon: Icon(Icons.attach_file_outlined),
                label: Text('Multipart'),
              ),
            ],
            selected: {_bodyMode},
            onSelectionChanged: _isSending
                ? null
                : (selection) {
                    setState(() => _bodyMode = selection.first);
                  },
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _bodyMode == ApiToolBodyMode.raw
              ? _buildRawBodyEditor()
              : _buildMultipartEditor(),
        ),
      ],
    );
  }

  Widget _buildRawBodyEditor() {
    return _buildVariableDropField(
      controller: _bodyController,
      enabled: !_isSending,
      child: TextField(
        key: const Key('api-tool-body'),
        controller: _bodyController,
        enabled: !_isSending,
        keyboardType: TextInputType.multiline,
        minLines: 14,
        maxLines: null,
        style: AppCyberTheme.dataTextStyle(
          size: 11.4,
          color: AppCyberTheme.textPrimary,
        ).copyWith(height: 1.38),
        decoration: const InputDecoration(
          labelText: 'Raw body',
          alignLabelWithHint: true,
          hintText: '{\n  "name": "Demo"\n}',
        ),
      ),
    );
  }

  Widget _buildMultipartEditor() {
    return Scrollbar(
      controller: _multipartScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _multipartScrollController,
        padding: const EdgeInsets.only(right: 8, bottom: 4),
        child: Column(
          children: [
            for (var index = 0; index < _multipartRows.length; index++) ...[
              _buildMultipartRow(index),
              const SizedBox(height: 10),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('api-tool-add-multipart'),
                onPressed: _isSending ? null : _addMultipartRow,
                icon: const Icon(Icons.add_outlined),
                label: const Text('Add field'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultipartRow(int index) {
    final row = _multipartRows[index];
    final isEnabled = !_isSending && row.enabled;
    final isFile = row.kind == ApiToolMultipartKind.file;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppCyberTheme.electricBlue.withValues(alpha: 0.14),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  value: row.enabled,
                  onChanged: _isSending
                      ? null
                      : (value) => setState(() => row.enabled = value ?? true),
                ),
                SizedBox(
                  width: 92,
                  child: DropdownButtonFormField<ApiToolMultipartKind>(
                    key: Key('api-tool-multipart-kind-$index'),
                    initialValue: row.kind,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    items: ApiToolMultipartKind.values
                        .map(
                          (kind) => DropdownMenuItem(
                            value: kind,
                            child: Text(kind.label),
                          ),
                        )
                        .toList(),
                    onChanged: isEnabled
                        ? (value) {
                            if (value == null) return;
                            setState(() => row.kind = value);
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildVariableDropField(
                    controller: row.nameController,
                    enabled: isEnabled,
                    child: TextField(
                      key: Key('api-tool-multipart-name-$index'),
                      controller: row.nameController,
                      enabled: isEnabled,
                      style: AppCyberTheme.dataTextStyle(
                        size: 11.2,
                        color: AppCyberTheme.textPrimary,
                      ),
                      decoration: const InputDecoration(labelText: 'Key'),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Remove field',
                  onPressed: _isSending || _multipartRows.length == 1
                      ? null
                      : () => _removeMultipartRow(index),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 48),
                Expanded(
                  child: _buildVariableDropField(
                    controller: row.valueController,
                    enabled: isEnabled,
                    child: TextField(
                      key: Key('api-tool-multipart-value-$index'),
                      controller: row.valueController,
                      enabled: isEnabled,
                      style: AppCyberTheme.dataTextStyle(
                        size: 11.2,
                        color: AppCyberTheme.textPrimary,
                      ),
                      decoration: InputDecoration(
                        labelText: isFile ? 'File path' : 'Value',
                        prefixIcon: Icon(
                          isFile
                              ? Icons.insert_drive_file_outlined
                              : Icons.short_text_outlined,
                        ),
                      ),
                    ),
                  ),
                ),
                if (isFile) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 154,
                    child: _buildVariableDropField(
                      controller: row.contentTypeController,
                      enabled: isEnabled,
                      child: TextField(
                        key: Key('api-tool-multipart-content-type-$index'),
                        controller: row.contentTypeController,
                        enabled: isEnabled,
                        style: AppCyberTheme.dataTextStyle(
                          size: 11.2,
                          color: AppCyberTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Content type',
                          hintText: 'auto/octet',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    key: Key('api-tool-multipart-pick-file-$index'),
                    tooltip: 'Choose file',
                    onPressed: isEnabled ? () => _pickMultipartFile(row) : null,
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
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

  Widget _buildResponsePanel() {
    final response = _response;
    final error = _error;

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
                key: const Key('api-tool-copy-response'),
                tooltip: 'Copy response',
                onPressed: response != null || error != null
                    ? _copyResponse
                    : null,
                icon: const Icon(Icons.copy_all_outlined),
              ),
            ],
          ),
          if (_isSending) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: Scrollbar(
              controller: _responseScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _responseScrollController,
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: _buildResponseContent(response, error),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponseContent(ApiToolResponse? response, String? error) {
    if (response == null && error == null) {
      return SizedBox(
        height: 260,
        child: Center(
          child: Text(
            'Send a request to inspect the response.',
            style: AppCyberTheme.dataTextStyle(
              size: 11.4,
              color: AppCyberTheme.textMuted,
            ),
          ),
        ),
      );
    }

    if (error != null) {
      return _ApiToolMessage(
        icon: Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
        message: error,
      );
    }

    final headersText = _formatHeaders(response!.headers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ApiToolStatusBadge(
              label: response.statusCode.toString(),
              color: response.isOk
                  ? AppCyberTheme.neonGreen
                  : Theme.of(context).colorScheme.error,
            ),
            _MetaChip(
              icon: Icons.timer_outlined,
              label: _durationLabelMs(response.durationMs),
            ),
            if (response.reasonPhrase.trim().isNotEmpty)
              _MetaChip(icon: Icons.info_outline, label: response.reasonPhrase),
            if (response.bodyTruncated)
              const _MetaChip(
                icon: Icons.content_cut_outlined,
                label: 'Body truncated',
                highlighted: true,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (headersText.isNotEmpty) ...[
          Text('Headers', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _ApiToolCodeBlock(
            key: const Key('api-tool-response-headers'),
            text: headersText,
          ),
          const SizedBox(height: 12),
        ],
        Text('Body', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _ApiToolCodeBlock(
          key: const Key('api-tool-response-body'),
          text: response.body.isEmpty ? '(empty)' : response.body,
        ),
      ],
    );
  }

  Future<void> _sendRequest() async {
    if (_isSending) return;
    final draftRequest = _draftRequest(
      id: _activeRequestId ?? _newId('api_request'),
      updatedAt: DateTime.now(),
    );
    if (draftRequest.url.trim().isEmpty) {
      setState(() => _error = 'Enter a URL before sending.');
      return;
    }
    final activeVariables = _activeCollection?.activeVariables ?? const {};
    final missingUrlVariables = _missingEnvironmentVariables(
      draftRequest.url,
      activeVariables,
    );
    if (missingUrlVariables.isNotEmpty) {
      setState(() {
        _error =
            'Missing active environment variable(s): '
            '${missingUrlVariables.join(', ')}.';
      });
      return;
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
      return;
    }

    final cancelToken = ApiToolCancellationToken();
    final stopwatch = Stopwatch()..start();
    setState(() {
      _isSending = true;
      _cancelToken = cancelToken;
      _response = null;
      _error = null;
    });

    try {
      final response = await _apiToolService.send(
        request,
        cancelToken: cancelToken,
      );
      await _recordHistory(
        request: draftRequest,
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
        request: draftRequest,
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
        request: draftRequest,
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

    setState(() => _isImportingPostman = true);
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
        _activeRequestId = null;
        _response = null;
        _error = null;
      });
      _showApiToolSnack(
        'Imported ${result.requestCount} request(s) from Postman.',
      );
    } on ApiToolPostmanImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isImportingPostman = false);
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
      _activeRequestId = null;
    });
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

  Future<void> _saveCollectionRoot(ApiToolCollectionRoot collection) async {
    final updated =
        _collections.where((entry) => entry.id != collection.id).toList()
          ..add(collection);
    final saved = await _runRepositoryWrite(
      () => _repository.saveApiToolCollections(updated),
    );
    if (!saved || !mounted) return;
    setState(() {
      _collections = _repository.apiToolCollections;
      _selectedCollectionId = collection.id;
    });
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

    return ApiToolRequest(
      id: id,
      name: _nameController.text.trim(),
      method: _method,
      url: _urlController.text.trim(),
      collectionId: _selectedCollectionId,
      folderId: _selectedFolderId,
      headers: headers,
      bodyMode: _bodyMode,
      body: _bodyController.text,
      multipartFields: multipartFields,
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
      _method = request.method;
      _bodyMode = request.bodyMode;
      _nameController.text = request.name;
      _urlController.text = request.url;
      _bodyController.text = request.body;
      _response = null;
      _error = null;
      _replaceHeaders(request.headers);
      _replaceMultipartFields(request.multipartFields);
    });
  }

  void _clearRequest() {
    setState(() {
      _activeRequestId = null;
      _method = ApiToolMethod.get;
      _bodyMode = ApiToolBodyMode.raw;
      _nameController.clear();
      _urlController.clear();
      _bodyController.clear();
      _response = null;
      _error = null;
      _replaceHeaders(const []);
      _replaceMultipartFields(const []);
    });
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

class _ApiToolTextPromptDialog extends StatefulWidget {
  const _ApiToolTextPromptDialog({
    required this.title,
    required this.label,
    required this.fallback,
  });

  final String title;
  final String label;
  final String fallback;

  @override
  State<_ApiToolTextPromptDialog> createState() =>
      _ApiToolTextPromptDialogState();
}

class _ApiToolTextPromptDialogState extends State<_ApiToolTextPromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.fallback);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppCyberTheme.panelBackgroundStrong,
      surfaceTintColor: Colors.transparent,
      title: _PanelTitle(icon: Icons.edit_outlined, title: widget.title),
      content: SizedBox(
        width: 360,
        child: TextField(
          autofocus: true,
          controller: _controller,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_outlined),
          label: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check_outlined),
          label: const Text('Create'),
        ),
      ],
    );
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }
}

class _ApiToolEnvironmentDialog extends StatefulWidget {
  const _ApiToolEnvironmentDialog({required this.collection});

  final ApiToolCollectionRoot collection;

  @override
  State<_ApiToolEnvironmentDialog> createState() =>
      _ApiToolEnvironmentDialogState();
}

class _ApiToolEnvironmentDialogState extends State<_ApiToolEnvironmentDialog> {
  final _nameController = TextEditingController();
  var _environments = <ApiToolEnvironment>[];
  var _variableRows = <_ApiToolEnvironmentVariableEditor>[];
  var _selectedEnvironmentId = '';
  var _variableSerial = 0;

  ApiToolEnvironment? get _selectedEnvironment {
    for (final environment in _environments) {
      if (environment.id == _selectedEnvironmentId) return environment;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _environments = widget.collection.environments.toList();
    _selectedEnvironmentId =
        _environments.any(
          (environment) =>
              environment.id == widget.collection.activeEnvironmentId,
        )
        ? widget.collection.activeEnvironmentId
        : (_environments.isEmpty ? '' : _environments.first.id);
    _syncSelectedEnvironmentFields();
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final row in _variableRows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedEnvironment;
    return AlertDialog(
      key: const Key('api-tool-env-dialog'),
      backgroundColor: AppCyberTheme.panelBackgroundStrong,
      surfaceTintColor: Colors.transparent,
      title: const _PanelTitle(
        icon: Icons.public_outlined,
        title: 'Environments',
      ),
      content: SizedBox(
        width: 680,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      'api-tool-env-select-$_selectedEnvironmentId',
                    ),
                    initialValue: _selectedEnvironmentId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Active environment',
                      prefixIcon: Icon(Icons.tune_outlined),
                    ),
                    items: [
                      if (_environments.isEmpty)
                        const DropdownMenuItem(
                          value: '',
                          child: Text('No environment'),
                        )
                      else
                        for (final environment in _environments)
                          DropdownMenuItem(
                            value: environment.id,
                            child: Text(environment.displayName),
                          ),
                    ],
                    onChanged: (value) {
                      _commitSelectedEnvironment();
                      setState(() {
                        _selectedEnvironmentId = value ?? '';
                        _syncSelectedEnvironmentFields();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const Key('api-tool-add-environment'),
                  onPressed: _addEnvironment,
                  icon: const Icon(Icons.add_outlined),
                  label: const Text('Add'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('api-tool-delete-environment'),
                  tooltip: 'Delete environment',
                  onPressed: selected == null ? null : _deleteEnvironment,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (selected == null)
              Expanded(
                child: Center(
                  child: Text(
                    'Create an environment for this collection.',
                    style: AppCyberTheme.dataTextStyle(
                      size: 11.4,
                      color: AppCyberTheme.textMuted,
                    ),
                  ),
                ),
              )
            else ...[
              TextField(
                key: const Key('api-tool-environment-name'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Environment name',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  key: const Key('api-tool-env-variable-list'),
                  children: [
                    for (var index = 0; index < _variableRows.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildVariableRow(index),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        key: const Key('api-tool-add-env-variable'),
                        onPressed: _addVariable,
                        icon: const Icon(Icons.add_outlined),
                        label: const Text('Add variable'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_outlined),
          label: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('api-tool-save-environments'),
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildVariableRow(int index) {
    final row = _variableRows[index];
    return Row(
      children: [
        Checkbox(
          value: row.enabled,
          onChanged: (value) => setState(() => row.enabled = value ?? true),
        ),
        Expanded(
          child: TextField(
            key: Key('api-tool-env-var-name-$index'),
            controller: row.nameController,
            enabled: row.enabled,
            decoration: const InputDecoration(labelText: 'Key'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            key: Key('api-tool-env-var-value-$index'),
            controller: row.valueController,
            enabled: row.enabled,
            decoration: const InputDecoration(labelText: 'Value'),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Remove variable',
          onPressed: _variableRows.length == 1
              ? null
              : () => _removeVariable(index),
          icon: const Icon(Icons.remove_circle_outline),
        ),
      ],
    );
  }

  void _addEnvironment() {
    _commitSelectedEnvironment();
    final environment = ApiToolEnvironment(
      id: _newEnvironmentId(),
      name: 'Environment ${_environments.length + 1}',
      variables: [ApiToolEnvironmentVariable(id: _newVariableId())],
      updatedAt: DateTime.now(),
    );
    setState(() {
      _environments = [..._environments, environment];
      _selectedEnvironmentId = environment.id;
      _syncSelectedEnvironmentFields();
    });
  }

  void _deleteEnvironment() {
    final id = _selectedEnvironmentId;
    if (id.isEmpty) return;
    final updated = _environments
        .where((environment) => environment.id != id)
        .toList();
    setState(() {
      _environments = updated;
      _selectedEnvironmentId = updated.isEmpty ? '' : updated.first.id;
      _syncSelectedEnvironmentFields();
    });
  }

  void _addVariable() {
    setState(() {
      _variableRows.add(
        _ApiToolEnvironmentVariableEditor(id: _newVariableId()),
      );
    });
  }

  void _removeVariable(int index) {
    if (_variableRows.length == 1) return;
    setState(() {
      final removed = _variableRows.removeAt(index);
      removed.dispose();
    });
  }

  void _save() {
    _commitSelectedEnvironment();
    final activeEnvironmentId =
        _environments.any(
          (environment) => environment.id == _selectedEnvironmentId,
        )
        ? _selectedEnvironmentId
        : '';
    Navigator.of(context).pop(
      widget.collection.copyWith(
        environments: _environments,
        activeEnvironmentId: activeEnvironmentId,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _commitSelectedEnvironment() {
    final id = _selectedEnvironmentId;
    if (id.isEmpty) return;
    final selected = _selectedEnvironment;
    if (selected == null) return;
    final updated = selected.copyWith(
      name: _nameController.text.trim(),
      variables: _variableRows
          .map((row) => row.toVariable())
          .where(
            (variable) =>
                variable.name.trim().isNotEmpty ||
                variable.value.trim().isNotEmpty,
          )
          .toList(growable: false),
      updatedAt: DateTime.now(),
    );
    _environments = _environments
        .map((environment) => environment.id == id ? updated : environment)
        .toList(growable: false);
  }

  void _syncSelectedEnvironmentFields() {
    for (final row in _variableRows) {
      row.dispose();
    }
    final selected = _selectedEnvironment;
    _nameController.text = selected?.name ?? '';
    final variables =
        selected?.variables ?? const <ApiToolEnvironmentVariable>[];
    final rows = variables.isEmpty
        ? [ApiToolEnvironmentVariable(id: _newVariableId())]
        : variables;
    _variableRows = rows
        .map(
          (variable) => _ApiToolEnvironmentVariableEditor(
            id: variable.id.isEmpty ? _newVariableId() : variable.id,
            name: variable.name,
            value: variable.value,
            enabled: variable.enabled,
          ),
        )
        .toList();
  }

  String _newEnvironmentId() =>
      'api_env_${DateTime.now().microsecondsSinceEpoch}';

  String _newVariableId() {
    _variableSerial += 1;
    return 'api_env_var_${DateTime.now().microsecondsSinceEpoch}_$_variableSerial';
  }
}

class _ApiToolEnvTokenChip extends StatelessWidget {
  const _ApiToolEnvTokenChip({
    super.key,
    required this.token,
    this.onDragStarted,
  });

  final String token;
  final VoidCallback? onDragStarted;

  @override
  Widget build(BuildContext context) {
    return Draggable<String>(
      data: token,
      maxSimultaneousDrags: 1,
      onDragStarted: onDragStarted,
      feedback: Material(
        type: MaterialType.transparency,
        child: _buildChip(context, floating: true),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: _buildChip(context)),
      child: _buildChip(context),
    );
  }

  Widget _buildChip(BuildContext context, {bool floating = false}) {
    final color = floating
        ? AppCyberTheme.neonGreen
        : AppCyberTheme.electricBlue;
    return Tooltip(
      message: token,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppCyberTheme.baseBackground.withValues(
            alpha: floating ? 0.86 : 0.28,
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.66)),
          boxShadow: floating && AppCyberTheme.isCyber
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.24),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Text(
          token,
          overflow: TextOverflow.ellipsis,
          style: AppCyberTheme.dataTextStyle(
            size: 10.6,
            color: AppCyberTheme.textPrimary,
            weight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _CompactTabLabel extends StatelessWidget {
  const _CompactTabLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _ApiToolSidebarActionButton extends StatelessWidget {
  const _ApiToolSidebarActionButton({
    required this.buttonKey,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final Key buttonKey;
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 40,
        child: OutlinedButton(
          key: buttonKey,
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(40),
            fixedSize: const Size.square(40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: IconTheme.merge(
            data: const IconThemeData(size: 19),
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

class _ApiToolSearchCountBadge extends StatelessWidget {
  const _ApiToolSearchCountBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      widthFactor: 1,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        constraints: const BoxConstraints(minWidth: 28),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppCyberTheme.baseBackground.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppCyberTheme.electricBlue.withValues(alpha: 0.32),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppCyberTheme.dataTextStyle(
            size: 9.8,
            color: AppCyberTheme.textMuted,
            weight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ApiToolEnvDropTarget extends StatelessWidget {
  const _ApiToolEnvDropTarget({
    required this.enabled,
    required this.onAcceptToken,
    required this.child,
  });

  final bool enabled;
  final ValueChanged<String> onAcceptToken;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => _isEnvToken(details.data),
      onAcceptWithDetails: (details) => onAcceptToken(details.data),
      builder: (context, candidates, _) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? AppCyberTheme.neonGreen.withValues(alpha: 0.82)
                  : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: child,
        );
      },
    );
  }

  bool _isEnvToken(String value) {
    final trimmed = value.trim();
    return trimmed.startsWith('{{') && trimmed.endsWith('}}');
  }
}

class _ApiToolEnvTextEditingController extends TextEditingController {
  _ApiToolEnvTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final text = value.text;
    if (text.isEmpty) {
      return TextSpan(style: baseStyle, text: text);
    }

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in _apiToolEnvTokenPattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(
            color: AppCyberTheme.neonGreen,
            fontWeight: FontWeight.w800,
            backgroundColor: AppCyberTheme.neonGreen.withValues(alpha: 0.14),
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return TextSpan(style: baseStyle, children: spans);
  }
}

class _ApiToolHeaderEditor {
  _ApiToolHeaderEditor({
    required this.id,
    String name = '',
    String value = '',
    this.enabled = true,
  }) : nameController = _ApiToolEnvTextEditingController(text: name),
       valueController = _ApiToolEnvTextEditingController(text: value);

  final String id;
  final TextEditingController nameController;
  final TextEditingController valueController;
  bool enabled;

  ApiToolHeader toHeader() {
    return ApiToolHeader(
      id: id,
      name: nameController.text.trim(),
      value: valueController.text,
      enabled: enabled,
    );
  }

  void dispose() {
    nameController.dispose();
    valueController.dispose();
  }
}

class _ApiToolMultipartEditor {
  _ApiToolMultipartEditor({
    required this.id,
    this.kind = ApiToolMultipartKind.text,
    String name = '',
    String value = '',
    String contentType = '',
    this.enabled = true,
  }) : nameController = _ApiToolEnvTextEditingController(text: name),
       valueController = _ApiToolEnvTextEditingController(text: value),
       contentTypeController = _ApiToolEnvTextEditingController(
         text: contentType,
       );

  final String id;
  ApiToolMultipartKind kind;
  final TextEditingController nameController;
  final TextEditingController valueController;
  final TextEditingController contentTypeController;
  bool enabled;

  ApiToolMultipartEntry toEntry() {
    return ApiToolMultipartEntry(
      id: id,
      kind: kind,
      name: nameController.text.trim(),
      value: valueController.text,
      contentType: contentTypeController.text.trim(),
      enabled: enabled,
    );
  }

  void dispose() {
    nameController.dispose();
    valueController.dispose();
    contentTypeController.dispose();
  }
}

class _ApiToolEnvironmentVariableEditor {
  _ApiToolEnvironmentVariableEditor({
    required this.id,
    String name = '',
    String value = '',
    this.enabled = true,
  }) : nameController = TextEditingController(text: name),
       valueController = TextEditingController(text: value);

  final String id;
  final TextEditingController nameController;
  final TextEditingController valueController;
  bool enabled;

  ApiToolEnvironmentVariable toVariable() {
    return ApiToolEnvironmentVariable(
      id: id,
      name: nameController.text.trim(),
      value: valueController.text,
      enabled: enabled,
    );
  }

  void dispose() {
    nameController.dispose();
    valueController.dispose();
  }
}

class _ApiToolEmptyTreeMessage extends StatelessWidget {
  const _ApiToolEmptyTreeMessage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppCyberTheme.dataTextStyle(
            size: 11.2,
            color: AppCyberTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

class _ApiToolFolderTile extends StatelessWidget {
  const _ApiToolFolderTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.depth,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final int depth;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: _HudCardShell(
            active: false,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  depth == 0
                      ? Icons.folder_copy_outlined
                      : Icons.folder_outlined,
                  size: 18,
                  color: selected
                      ? AppCyberTheme.neonGreen
                      : AppCyberTheme.electricBlue,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppCyberTheme.dataTextStyle(
                          size: 11.4,
                          color: AppCyberTheme.textPrimary,
                          weight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppCyberTheme.dataTextStyle(
                          size: 10.2,
                          color: AppCyberTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ApiToolRequestTile extends StatelessWidget {
  const _ApiToolRequestTile({
    super.key,
    required this.method,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.trailing,
    required this.onTap,
  });

  final ApiToolMethod method;
  final String title;
  final String subtitle;
  final bool selected;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: _HudCardShell(
          active: selected,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              _ApiMethodPill(method: method),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppCyberTheme.dataTextStyle(
                        size: 11.3,
                        color: AppCyberTheme.textPrimary,
                        weight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppCyberTheme.dataTextStyle(
                        size: 10.2,
                        color: AppCyberTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                style: AppCyberTheme.dataTextStyle(
                  size: 9.8,
                  color: AppCyberTheme.textMuted,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApiMethodPill extends StatelessWidget {
  const _ApiMethodPill({required this.method});

  final ApiToolMethod method;

  @override
  Widget build(BuildContext context) {
    final color = switch (method) {
      ApiToolMethod.get => AppCyberTheme.neonGreen,
      ApiToolMethod.post => AppCyberTheme.electricBlue,
      ApiToolMethod.put => const Color(0xFFF79009),
      ApiToolMethod.patch => const Color(0xFFB692F6),
      ApiToolMethod.delete => Theme.of(context).colorScheme.error,
    };
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Text(
        method.label,
        textAlign: TextAlign.center,
        style: AppCyberTheme.dataTextStyle(
          size: 9.8,
          color: color,
          weight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ApiToolStatusBadge extends StatelessWidget {
  const _ApiToolStatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: AppCyberTheme.dataTextStyle(
          size: 11,
          color: color,
          weight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ApiToolCodeBlock extends StatelessWidget {
  const _ApiToolCodeBlock({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppCyberTheme.baseBackground.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppCyberTheme.electricBlue.withValues(alpha: 0.2),
        ),
      ),
      child: SelectableText(
        text,
        style: AppCyberTheme.dataTextStyle(
          size: 11.2,
          color: AppCyberTheme.textPrimary,
        ).copyWith(height: 1.4),
      ),
    );
  }
}

class _ApiToolMessage extends StatelessWidget {
  const _ApiToolMessage({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              message,
              style: AppCyberTheme.dataTextStyle(
                size: 11.3,
                color: AppCyberTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
