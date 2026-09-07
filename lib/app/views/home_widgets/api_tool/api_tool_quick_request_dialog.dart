part of '../../home_view.dart';

class _ApiToolQuickRequestDialog extends StatefulWidget {
  const _ApiToolQuickRequestDialog({
    required this.initial,
    required this.collections,
  });

  final ApiToolQuickRequest initial;
  final List<ApiToolCollectionRoot> collections;

  @override
  State<_ApiToolQuickRequestDialog> createState() =>
      _ApiToolQuickRequestDialogState();
}

class _ApiToolQuickRequestDialogState
    extends State<_ApiToolQuickRequestDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _bodyController = TextEditingController();
  final _authTokenController = TextEditingController();
  final _authUsernameController = TextEditingController();
  final _authPasswordController = TextEditingController();
  final _authApiKeyNameController = TextEditingController();
  final _authApiKeyValueController = TextEditingController();
  var _headers = <_ApiToolHeaderEditor>[];
  var _multipartRows = <_ApiToolMultipartEditor>[];
  var _urlEncodedRows = <_ApiToolHeaderEditor>[];
  late String _collectionId;
  late ApiToolMethod _method;
  late ApiToolAuthorizationType _authorizationType;
  late ApiToolBodyMode _bodyMode;
  late bool _requiresConfirmation;
  String? _validationError;
  var _serial = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final request = initial.request;
    _nameController.text = initial.name;
    _urlController.text = request.url;
    _bodyController.text = request.body;
    _collectionId =
        widget.collections.any((entry) => entry.id == initial.collectionId)
        ? initial.collectionId
        : (widget.collections.isEmpty ? '' : widget.collections.first.id);
    _method = request.method;
    _authorizationType = request.authorization.type;
    _bodyMode = request.bodyMode;
    _requiresConfirmation = initial.requiresConfirmation;
    _authTokenController.text = request.authorization.token;
    _authUsernameController.text = request.authorization.username;
    _authPasswordController.text = request.authorization.password;
    _authApiKeyNameController.text = request.authorization.apiKeyName;
    _authApiKeyValueController.text = request.authorization.apiKeyValue;
    _headers = _headerEditors(request.headers, 'header');
    _multipartRows = _multipartEditors(request.multipartFields);
    _urlEncodedRows = _headerEditors(request.urlEncodedFields, 'urlencoded');
  }

  List<_ApiToolHeaderEditor> _headerEditors(
    List<ApiToolHeader> entries,
    String prefix,
  ) {
    final source = entries.isEmpty
        ? [ApiToolHeader(id: _newFieldId(prefix))]
        : entries;
    return source
        .map(
          (entry) => _ApiToolHeaderEditor(
            id: entry.id.isEmpty ? _newFieldId(prefix) : entry.id,
            name: entry.name,
            value: entry.value,
            enabled: entry.enabled,
          ),
        )
        .toList();
  }

  List<_ApiToolMultipartEditor> _multipartEditors(
    List<ApiToolMultipartEntry> entries,
  ) {
    final source = entries.isEmpty
        ? [ApiToolMultipartEntry(id: _newFieldId('part'))]
        : entries;
    return source
        .map(
          (entry) => _ApiToolMultipartEditor(
            id: entry.id.isEmpty ? _newFieldId('part') : entry.id,
            kind: entry.kind,
            name: entry.name,
            value: entry.value,
            contentType: entry.contentType,
            enabled: entry.enabled,
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _bodyController.dispose();
    _authTokenController.dispose();
    _authUsernameController.dispose();
    _authPasswordController.dispose();
    _authApiKeyNameController.dispose();
    _authApiKeyValueController.dispose();
    for (final row in [..._headers, ..._urlEncodedRows]) {
      row.dispose();
    }
    for (final row in _multipartRows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height - 160;
    return AlertDialog(
      key: const Key('api-tool-quick-request-dialog'),
      title: const Row(
        children: [
          Icon(Icons.bolt_outlined),
          SizedBox(width: 8),
          Text('Quick Request'),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: height.clamp(340, 650).toDouble(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('api-tool-quick-name'),
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Quick Request name',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _buildCollectionField()),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(width: 160, child: _buildMethodField()),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('api-tool-quick-url'),
                    controller: _urlController,
                    decoration: const InputDecoration(labelText: 'URL'),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              key: const Key('api-tool-quick-confirmation'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Require confirmation before running'),
              subtitle: const Text(
                'Recommended for reset or destructive calls.',
              ),
              value: _requiresConfirmation,
              onChanged: (value) =>
                  setState(() => _requiresConfirmation = value),
            ),
            if (_validationError != null) ...[
              Text(
                _validationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Authorization'),
                        Tab(text: 'Headers'),
                        Tab(text: 'Body'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildAuthorizationTab(),
                          _buildKeyValueList(
                            rows: _headers,
                            prefix: 'quick-header',
                            onAdd: () => setState(
                              () => _headers.add(
                                _ApiToolHeaderEditor(id: _newFieldId('header')),
                              ),
                            ),
                          ),
                          _buildBodyTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('api-tool-save-quick-request'),
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save Quick Request'),
        ),
      ],
    );
  }

  Widget _buildCollectionField() {
    return DropdownButtonFormField<String>(
      key: const Key('api-tool-quick-collection'),
      initialValue: _collectionId.isEmpty ? null : _collectionId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Collection'),
      items: widget.collections
          .map(
            (entry) => DropdownMenuItem(
              value: entry.id,
              child: Text(
                entry.activeEnvironment == null
                    ? entry.displayName
                    : '${entry.displayName} · ${entry.activeEnvironment!.displayName}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(growable: false),
      onChanged: (value) => setState(() => _collectionId = value ?? ''),
    );
  }

  Widget _buildMethodField() {
    return DropdownButtonFormField<ApiToolMethod>(
      key: const Key('api-tool-quick-method'),
      initialValue: _method,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Method'),
      items: ApiToolMethod.values
          .map(
            (entry) => DropdownMenuItem(value: entry, child: Text(entry.label)),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value != null) setState(() => _method = value);
      },
    );
  }

  Widget _buildAuthorizationTab() {
    return ListView(
      padding: const EdgeInsets.only(right: 6),
      children: [
        DropdownButtonFormField<ApiToolAuthorizationType>(
          key: const Key('api-tool-quick-auth-type'),
          initialValue: _authorizationType,
          decoration: const InputDecoration(labelText: 'Authorization type'),
          items: ApiToolAuthorizationType.values
              .map(
                (entry) =>
                    DropdownMenuItem(value: entry, child: Text(entry.label)),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value != null) setState(() => _authorizationType = value);
          },
        ),
        const SizedBox(height: 10),
        ...switch (_authorizationType) {
          ApiToolAuthorizationType.none => [
            const Text('No authorization header will be added.'),
          ],
          ApiToolAuthorizationType.bearer => [
            _quickTextField(_authTokenController, 'Token', 'quick-auth-token'),
          ],
          ApiToolAuthorizationType.basic => [
            _quickTextField(
              _authUsernameController,
              'Username',
              'quick-auth-username',
            ),
            const SizedBox(height: 10),
            _quickTextField(
              _authPasswordController,
              'Password',
              'quick-auth-password',
            ),
          ],
          ApiToolAuthorizationType.apiKey => [
            _quickTextField(
              _authApiKeyNameController,
              'Header name',
              'quick-auth-api-key-name',
            ),
            const SizedBox(height: 10),
            _quickTextField(
              _authApiKeyValueController,
              'Value',
              'quick-auth-api-key-value',
            ),
          ],
        },
      ],
    );
  }

  Widget _quickTextField(
    TextEditingController controller,
    String label,
    String keyName,
  ) {
    return TextField(
      key: Key('api-tool-$keyName'),
      controller: controller,
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _buildKeyValueList({
    required List<_ApiToolHeaderEditor> rows,
    required String prefix,
    required VoidCallback onAdd,
  }) {
    return ListView(
      padding: const EdgeInsets.only(right: 6),
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          Row(
            children: [
              Checkbox(
                value: rows[index].enabled,
                onChanged: (value) =>
                    setState(() => rows[index].enabled = value ?? true),
              ),
              Expanded(
                child: TextField(
                  key: Key('api-tool-$prefix-name-$index'),
                  controller: rows[index].nameController,
                  decoration: const InputDecoration(labelText: 'Key'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: Key('api-tool-$prefix-value-$index'),
                  controller: rows[index].valueController,
                  decoration: const InputDecoration(labelText: 'Value'),
                ),
              ),
              IconButton(
                tooltip: 'Remove field',
                onPressed: rows.length == 1
                    ? null
                    : () {
                        setState(() {
                          final removed = rows.removeAt(index);
                          removed.dispose();
                        });
                      },
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_outlined),
            label: const Text('Add field'),
          ),
        ),
      ],
    );
  }

  Widget _buildBodyTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<ApiToolBodyMode>(
          key: const Key('api-tool-quick-body-mode'),
          initialValue: _bodyMode,
          decoration: const InputDecoration(labelText: 'Body type'),
          items: ApiToolBodyMode.values
              .map(
                (entry) =>
                    DropdownMenuItem(value: entry, child: Text(entry.label)),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value != null) setState(() => _bodyMode = value);
          },
        ),
        const SizedBox(height: 10),
        Expanded(
          child: switch (_bodyMode) {
            ApiToolBodyMode.raw => TextField(
              key: const Key('api-tool-quick-body'),
              controller: _bodyController,
              minLines: 12,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: 'Raw body',
                alignLabelWithHint: true,
              ),
            ),
            ApiToolBodyMode.multipart => _buildQuickMultipartList(),
            ApiToolBodyMode.urlEncoded => _buildKeyValueList(
              rows: _urlEncodedRows,
              prefix: 'quick-urlencoded',
              onAdd: () => setState(
                () => _urlEncodedRows.add(
                  _ApiToolHeaderEditor(id: _newFieldId('urlencoded')),
                ),
              ),
            ),
          },
        ),
      ],
    );
  }

  Widget _buildQuickMultipartList() {
    return ListView(
      padding: const EdgeInsets.only(right: 6),
      children: [
        for (var index = 0; index < _multipartRows.length; index++) ...[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: AppCyberTheme.lineBlue),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: _multipartRows[index].enabled,
                      onChanged: (value) => setState(
                        () => _multipartRows[index].enabled = value ?? true,
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: DropdownButtonFormField<ApiToolMultipartKind>(
                        key: Key('api-tool-quick-part-kind-$index'),
                        initialValue: _multipartRows[index].kind,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: ApiToolMultipartKind.values
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry,
                                child: Text(entry.label),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _multipartRows[index].kind = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: Key('api-tool-quick-part-name-$index'),
                        controller: _multipartRows[index].nameController,
                        decoration: const InputDecoration(labelText: 'Key'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove field',
                      onPressed: _multipartRows.length == 1
                          ? null
                          : () {
                              setState(() {
                                final removed = _multipartRows.removeAt(index);
                                removed.dispose();
                              });
                            },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: Key('api-tool-quick-part-value-$index'),
                        controller: _multipartRows[index].valueController,
                        decoration: InputDecoration(
                          labelText:
                              _multipartRows[index].kind ==
                                  ApiToolMultipartKind.file
                              ? 'File path'
                              : 'Value',
                        ),
                      ),
                    ),
                    if (_multipartRows[index].kind ==
                        ApiToolMultipartKind.file) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller:
                              _multipartRows[index].contentTypeController,
                          decoration: const InputDecoration(
                            labelText: 'Content type',
                          ),
                        ),
                      ),
                      IconButton(
                        key: Key('api-tool-quick-part-pick-$index'),
                        tooltip: 'Choose file',
                        onPressed: () => _pickQuickFile(index),
                        icon: const Icon(Icons.folder_open_outlined),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(
              () => _multipartRows.add(
                _ApiToolMultipartEditor(id: _newFieldId('part')),
              ),
            ),
            icon: const Icon(Icons.add_outlined),
            label: const Text('Add field'),
          ),
        ),
      ],
    );
  }

  Future<void> _pickQuickFile(int index) async {
    final file = await file_selector.openFile();
    if (file == null || !mounted || index >= _multipartRows.length) return;
    setState(() => _multipartRows[index].valueController.text = file.path);
  }

  void _save() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    if (name.isEmpty) {
      setState(() => _validationError = 'Enter a Quick Request name.');
      return;
    }
    if (_collectionId.isEmpty) {
      setState(() => _validationError = 'Select a collection.');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (!url.contains('{{') &&
            (!uri.hasScheme ||
                uri.host.isEmpty ||
                !const {'http', 'https'}.contains(uri.scheme.toLowerCase())))) {
      setState(() => _validationError = 'Enter a valid HTTP or HTTPS URL.');
      return;
    }

    final now = DateTime.now();
    final request = ApiToolRequest(
      id: widget.initial.id,
      name: name,
      method: _method,
      url: url,
      collectionId: _collectionId,
      authorization: ApiToolAuthorization(
        type: _authorizationType,
        token: _authTokenController.text,
        username: _authUsernameController.text,
        password: _authPasswordController.text,
        apiKeyName: _authApiKeyNameController.text.trim(),
        apiKeyValue: _authApiKeyValueController.text,
      ),
      headers: _headers
          .map((entry) => entry.toHeader())
          .where((entry) => entry.hasName || entry.value.isNotEmpty)
          .toList(growable: false),
      bodyMode: _bodyMode,
      body: _bodyController.text,
      multipartFields: _multipartRows
          .map((entry) => entry.toEntry())
          .where((entry) => entry.hasName || entry.hasValue)
          .toList(growable: false),
      urlEncodedFields: _urlEncodedRows
          .map((entry) => entry.toHeader())
          .where((entry) => entry.hasName || entry.value.isNotEmpty)
          .toList(growable: false),
      updatedAt: now,
    );
    Navigator.of(context).pop(
      widget.initial.copyWith(
        name: name,
        collectionId: _collectionId,
        request: request,
        requiresConfirmation: _requiresConfirmation,
        updatedAt: now,
      ),
    );
  }

  String _newFieldId(String prefix) {
    _serial += 1;
    return 'api_quick_${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_serial';
  }
}

enum _ApiToolQuickRequestAction { edit, duplicate, delete }

class _ApiToolQuickRequestTile extends StatelessWidget {
  const _ApiToolQuickRequestTile({
    super.key,
    required this.request,
    required this.collectionName,
    required this.running,
    required this.canEdit,
    required this.onRun,
    required this.onAction,
  });

  final ApiToolQuickRequest request;
  final String collectionName;
  final bool running;
  final bool canEdit;
  final VoidCallback onRun;
  final ValueChanged<_ApiToolQuickRequestAction> onAction;

  @override
  Widget build(BuildContext context) {
    return _HudCardShell(
      padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
      child: Row(
        children: [
          _ApiMethodPill(method: request.request.method),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        request.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppCyberTheme.dataTextStyle(
                          size: 11.2,
                          color: AppCyberTheme.textPrimary,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (request.requiresConfirmation)
                      const Tooltip(
                        message: 'Confirmation required',
                        child: Icon(Icons.verified_user_outlined, size: 15),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  collectionName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 9.8,
                    color: AppCyberTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('api-tool-run-quick-request-${request.id}'),
            tooltip: 'Run Quick Request',
            onPressed: running ? null : onRun,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
          PopupMenuButton<_ApiToolQuickRequestAction>(
            key: Key('api-tool-quick-request-menu-${request.id}'),
            enabled: canEdit && !running,
            tooltip: 'Manage Quick Request',
            onSelected: onAction,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _ApiToolQuickRequestAction.edit,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                ),
              ),
              PopupMenuItem(
                value: _ApiToolQuickRequestAction.duplicate,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.copy_all_outlined),
                  title: Text('Duplicate'),
                ),
              ),
              PopupMenuItem(
                value: _ApiToolQuickRequestAction.delete,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
