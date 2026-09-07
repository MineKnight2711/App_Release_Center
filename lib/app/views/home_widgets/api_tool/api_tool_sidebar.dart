part of '../../home_view.dart';

mixin _ApiToolSidebarSection on _ApiToolDialogCore {
  Widget _buildSidebar() {
    return DefaultTabController(
      length: 3,
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
                Tab(
                  key: Key('api-tool-quick-requests-tab'),
                  child: _CompactTabLabel(
                    icon: Icons.bolt_outlined,
                    label: 'Quick',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: [
                  _buildCollectionList(),
                  _buildHistoryList(),
                  _buildQuickRequestList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionList() {
    // On a short window (the stacked compact layout) the chrome above the tree
    // is dropped progressively rather than overflowing it.
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final showSearch = !height.isFinite || height >= 156;
        final showToolbar = !height.isFinite || height >= 100;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showToolbar) ...[
              _buildCollectionToolbar(),
              const SizedBox(height: 8),
            ],
            if (showSearch) ...[
              _buildRequestSearchField(),
              const SizedBox(height: 8),
            ],
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
      },
    );
  }

  /// Two entry points instead of nine icons: everything that creates something
  /// lives under `+ New`, everything else under the overflow menu.
  Widget _buildCollectionToolbar() {
    final activeCollection = _activeCollection;
    final canEdit =
        _repository.canWriteApiTools.value &&
        !_isRefreshingRepository &&
        !_isImportingPostman;
    final isTeamMode = _repository.isTeamMode;
    final canImport = canEdit && isTeamMode && _repository.hasLocalApiToolData;
    final busy = _isSending || !canEdit;

    return Row(
      key: const Key('api-tool-collection-toolbar'),
      children: [
        Expanded(
          child: MenuAnchor(
            menuChildren: [
              MenuItemButton(
                key: const Key('api-tool-new-request'),
                onPressed: _isSending ? null : _clearRequest,
                leadingIcon: const Icon(Icons.add_circle_outline, size: 18),
                child: const Text('New request'),
              ),
              MenuItemButton(
                key: const Key('api-tool-add-folder'),
                onPressed: busy || _selectedCollectionId.isEmpty
                    ? null
                    : () =>
                          unawaited(_createFolder(context, parentFolderId: '')),
                leadingIcon: const Icon(Icons.folder_outlined, size: 18),
                child: const Text('New folder'),
              ),
              MenuItemButton(
                key: const Key('api-tool-add-subfolder'),
                onPressed: busy || _selectedFolderId.isEmpty
                    ? null
                    : () => unawaited(
                        _createFolder(
                          context,
                          parentFolderId: _selectedFolderId,
                        ),
                      ),
                leadingIcon: const Icon(
                  Icons.snippet_folder_outlined,
                  size: 18,
                ),
                child: const Text('New subfolder'),
              ),
              MenuItemButton(
                key: const Key('api-tool-add-collection'),
                onPressed: busy
                    ? null
                    : () => unawaited(_createCollection(context)),
                leadingIcon: const Icon(
                  Icons.create_new_folder_outlined,
                  size: 18,
                ),
                child: const Text('New collection'),
              ),
            ],
            builder: (context, controller, child) {
              return OutlinedButton.icon(
                key: const Key('api-tool-new-menu'),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Icons.add_outlined, size: 18),
                label: const Text('New'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        MenuAnchor(
          menuChildren: [
            MenuItemButton(
              key: const Key('api-tool-environments'),
              onPressed: busy || activeCollection == null
                  ? null
                  : () => unawaited(_editEnvironments(context)),
              leadingIcon: const Icon(Icons.public_outlined, size: 18),
              child: const Text('Edit environment'),
            ),
            MenuItemButton(
              key: const Key('api-tool-import-postman'),
              onPressed: busy
                  ? null
                  : () => unawaited(_importPostmanCollection()),
              leadingIcon: _isImportingPostmanCollection
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_upload_outlined, size: 18),
              child: const Text('Import Postman collection'),
            ),
            MenuItemButton(
              key: const Key('api-tool-import-postman-environment'),
              onPressed: busy || activeCollection == null
                  ? null
                  : () => unawaited(_importPostmanEnvironment()),
              leadingIcon: _isImportingPostmanEnvironment
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.tune_outlined, size: 18),
              child: const Text('Import Postman environment'),
            ),
            if (isTeamMode) ...[
              MenuItemButton(
                key: const Key('api-tool-import-local'),
                onPressed: _isSending || !canImport
                    ? null
                    : () => unawaited(_importLocalApiTools()),
                leadingIcon: const Icon(Icons.upload_file_outlined, size: 18),
                child: const Text('Import local tools to team'),
              ),
              MenuItemButton(
                key: const Key('api-tool-refresh-team'),
                onPressed: _isRefreshingRepository || _isImportingPostman
                    ? null
                    : () => unawaited(_refreshCollectionState()),
                leadingIcon: _isRefreshingRepository
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined, size: 18),
                child: const Text('Refresh HTTP Tools'),
              ),
            ],
            const Divider(height: 8),
            MenuItemButton(
              key: const Key('api-tool-delete-collection'),
              onPressed: busy || activeCollection == null
                  ? null
                  : () => unawaited(_deleteActiveCollection()),
              leadingIcon: const Icon(Icons.delete_outline, size: 18),
              child: const Text('Delete collection'),
            ),
          ],
          builder: (context, controller, child) {
            return _ApiToolSidebarActionButton(
              buttonKey: const Key('api-tool-more-menu'),
              tooltip: 'More collection actions',
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: _isImportingPostman || _isRefreshingRepository
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.more_horiz_outlined),
            );
          },
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

    final collectionExpanded =
        searchTerm.isNotEmpty ||
        _expandedCollectionIds.contains(activeCollection.id);
    rows.add(
      _ApiToolFolderTile(
        key: Key('api-tool-root-folder-${activeCollection.id}'),
        title: activeCollection.displayName,
        subtitle: 'Root collection',
        depth: 0,
        selected: _selectedFolderId.isEmpty,
        expanded: collectionExpanded,
        onTap: () => setState(() {
          _selectedFolderId = '';
          _activeRequestId = null;
          if (_expandedCollectionIds.contains(activeCollection.id)) {
            _expandedCollectionIds.remove(activeCollection.id);
          } else {
            _expandedCollectionIds.add(activeCollection.id);
          }
        }),
      ),
    );
    if (!collectionExpanded) return rows;

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

    final folderExpanded =
        searchTerm.isNotEmpty || _expandedFolderIds.contains(folder.id);
    rows.add(
      _ApiToolFolderTile(
        key: Key('api-tool-folder-${folder.id}'),
        title: folder.displayName,
        subtitle: 'Folder',
        depth: depth,
        selected: _selectedFolderId == folder.id,
        expanded: folderExpanded,
        onTap: () => setState(() {
          _selectedFolderId = folder.id;
          _activeRequestId = null;
          if (_expandedFolderIds.contains(folder.id)) {
            _expandedFolderIds.remove(folder.id);
          } else {
            _expandedFolderIds.add(folder.id);
          }
        }),
      ),
    );
    if (!folderExpanded) return;

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

  Widget _buildQuickRequestList() {
    final canEdit = _repository.canWriteApiTools.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('api-tool-new-quick-request'),
                onPressed: _isSending || !canEdit
                    ? null
                    : () => unawaited(_createQuickRequest()),
                icon: const Icon(Icons.add_outlined),
                label: const Text('New'),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Create from the request currently in the editor',
              child: IconButton.outlined(
                key: const Key('api-tool-copy-to-quick-request'),
                onPressed:
                    _isSending || !canEdit || _urlController.text.trim().isEmpty
                    ? null
                    : () => unawaited(_createQuickRequestFromDraft()),
                icon: const Icon(Icons.content_copy_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _quickRequests.isEmpty
              ? const _ApiToolEmptyTreeMessage(
                  label: 'No Quick Requests yet. Set one up to run it once.',
                )
              : ListView.separated(
                  key: const Key('api-tool-quick-request-list'),
                  padding: const EdgeInsets.only(right: 4, bottom: 4),
                  itemCount: _quickRequests.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final quickRequest = _quickRequests[index];
                    return _ApiToolQuickRequestTile(
                      key: Key('api-tool-quick-request-${quickRequest.id}'),
                      request: quickRequest,
                      collectionName: _collectionName(
                        quickRequest.collectionId,
                      ),
                      running: _isSending,
                      canEdit: canEdit,
                      onRun: () => unawaited(_runQuickRequest(quickRequest)),
                      onAction: (action) => unawaited(
                        _handleQuickRequestAction(quickRequest, action),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _collectionName(String id) {
    for (final collection in _collections) {
      if (collection.id == id) return collection.displayName;
    }
    return 'Missing collection';
  }
}
