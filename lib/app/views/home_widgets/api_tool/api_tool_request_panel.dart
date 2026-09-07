part of '../../home_view.dart';

/// Zone 2 of the API Tool: the request workbench. Params, Headers, Auth, Body
/// and Settings each own a tab, and every tab label carries the badge that
/// tells you what is configured without opening it.
mixin _ApiToolRequestSection on _ApiToolDialogCore {
  int get _activeParamCount => _paramRows
      .where((row) => row.enabled && row.nameController.text.trim().isNotEmpty)
      .length;

  int get _activeHeaderCount => _headers
      .where((row) => row.enabled && row.nameController.text.trim().isNotEmpty)
      .length;

  String get _bodyModeTag {
    return switch (_bodyMode) {
      ApiToolBodyMode.raw => 'RAW',
      ApiToolBodyMode.multipart => 'FORM',
      ApiToolBodyMode.urlEncoded => 'URLENC',
    };
  }

  Widget _buildRequestPanel() {
    final canEdit = _repository.canWriteApiTools.value;
    final canSave = canEdit && _urlController.text.trim().isNotEmpty;
    final hasActiveRequest = _activeRequestId != null;

    return _HudCardShell(
      padding: const EdgeInsets.all(12),
      child: DefaultTabController(
        length: 5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: _PanelTitle(
                    icon: Icons.tune_outlined,
                    title: 'Request',
                  ),
                ),
                // A Wrap (not a Row) so single actions reflow one by one when
                // the workbench is narrow, instead of the cluster overflowing.
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _ApiToolInlineAction(
                      actionKey: const Key('api-tool-save'),
                      icon: Icons.save_outlined,
                      label: 'Save',
                      tooltip: 'Save request (${_apiToolSaveShortcutLabel()})',
                      onPressed: canSave && !_isSending
                          ? () => unawaited(_saveRequest(asNew: false))
                          : null,
                    ),
                    _ApiToolInlineAction(
                      actionKey: const Key('api-tool-save-as'),
                      icon: Icons.copy_all_outlined,
                      label: 'Save as',
                      tooltip: 'Save as a new request',
                      onPressed: canSave && !_isSending
                          ? () => unawaited(_saveRequest(asNew: true))
                          : null,
                    ),
                    _ApiToolInlineAction(
                      actionKey: const Key('api-tool-copy-curl'),
                      icon: Icons.terminal_outlined,
                      label: 'cURL',
                      tooltip:
                          'Copy this request as a terminal-ready curl command',
                      onPressed: _urlController.text.trim().isEmpty
                          ? null
                          : _copyRequestAsCurl,
                    ),
                    IconButton(
                      key: const Key('api-tool-delete'),
                      tooltip: 'Delete request',
                      visualDensity: VisualDensity.compact,
                      onPressed: canEdit && hasActiveRequest && !_isSending
                          ? () => unawaited(_deleteActiveRequest())
                          : null,
                      icon: const Icon(Icons.delete_outline, size: 19),
                    ),
                    IconButton(
                      key: const Key('api-tool-new'),
                      tooltip: 'New request',
                      visualDensity: VisualDensity.compact,
                      onPressed: _isSending ? null : _clearRequest,
                      icon: const Icon(Icons.add_circle_outline, size: 19),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TabBar(
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              tabs: [
                Tab(
                  key: const Key('api-tool-params-tab'),
                  child: _ApiToolTabLabel(
                    icon: Icons.link_outlined,
                    label: 'Params',
                    count: _activeParamCount,
                  ),
                ),
                Tab(
                  key: const Key('api-tool-headers-tab'),
                  child: _ApiToolTabLabel(
                    icon: Icons.view_headline_outlined,
                    label: 'Headers',
                    count: _activeHeaderCount,
                  ),
                ),
                Tab(
                  key: const Key('api-tool-authorization-tab'),
                  child: _ApiToolTabLabel(
                    icon: Icons.key_outlined,
                    label: 'Auth',
                    marked: _authorizationType != ApiToolAuthorizationType.none,
                  ),
                ),
                Tab(
                  key: const Key('api-tool-body-tab'),
                  child: _ApiToolTabLabel(
                    icon: Icons.data_object_outlined,
                    label: 'Body',
                    tag: _bodyModeTag,
                  ),
                ),
                const Tab(
                  key: Key('api-tool-settings-tab'),
                  child: _ApiToolTabLabel(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: TabBarView(
                children: [
                  _buildParamsEditor(),
                  _buildHeadersEditor(),
                  _buildAuthorizationEditor(),
                  _buildBodyEditor(),
                  _buildSettingsEditor(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Query parameters stay in lockstep with the URL: editing a row rewrites the
  /// query string, and typing a query string into the omnibar refills the rows.
  Widget _buildParamsEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Synced with the URL query string',
                style: AppCyberTheme.dataTextStyle(
                  size: 10.4,
                  color: AppCyberTheme.textMuted,
                ),
              ),
            ),
            _ApiToolInlineAction(
              actionKey: const Key('api-tool-clear-params'),
              icon: Icons.backspace_outlined,
              label: 'Clear',
              tooltip: 'Remove every query parameter from the URL',
              onPressed: _isSending || _activeParamCount == 0
                  ? null
                  : _clearParamRows,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Scrollbar(
            controller: _paramScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _paramScrollController,
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: Column(
                children: [
                  for (var index = 0; index < _paramRows.length; index++) ...[
                    _buildParamRow(index),
                    const SizedBox(height: 8),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('api-tool-add-param'),
                      onPressed: _isSending ? null : _addParamRow,
                      icon: const Icon(Icons.add_outlined),
                      label: const Text('Add param'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildParamRow(int index) {
    final row = _paramRows[index];
    final isEnabled = !_isSending && row.enabled;
    return Row(
      children: [
        Checkbox(
          value: row.enabled,
          onChanged: _isSending
              ? null
              : (value) {
                  setState(() => row.enabled = value ?? true);
                  _syncUrlFromParams();
                },
        ),
        Expanded(
          child: _buildVariableDropField(
            controller: row.nameController,
            enabled: isEnabled,
            child: TextField(
              key: Key('api-tool-param-name-$index'),
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
        const SizedBox(width: 8),
        Expanded(
          child: _buildVariableDropField(
            controller: row.valueController,
            enabled: isEnabled,
            child: TextField(
              key: Key('api-tool-param-value-$index'),
              controller: row.valueController,
              enabled: isEnabled,
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
          tooltip: 'Remove param',
          onPressed: _isSending || _paramRows.length == 1
              ? null
              : () => _removeParamRow(index),
          icon: const Icon(Icons.remove_circle_outline),
        ),
      ],
    );
  }

  /// Connection settings live here so the omnibar stays a pure request line.
  Widget _buildSettingsEditor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 180,
            child: TextField(
              key: const Key('api-tool-timeout-seconds'),
              controller: _timeoutSecondsController,
              enabled: !_isSending,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onEditingComplete: () =>
                  unawaited(_normalizeAndSaveTimeout(showError: true)),
              onSubmitted: (_) =>
                  unawaited(_normalizeAndSaveTimeout(showError: true)),
              style: AppCyberTheme.dataTextStyle(
                size: 11.5,
                color: AppCyberTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Timeout',
                prefixIcon: Icon(Icons.timer_outlined, size: 18),
                suffixText: 's',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _timeoutValidationMessage,
            style: AppCyberTheme.dataTextStyle(
              size: 10.4,
              color: AppCyberTheme.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          _ApiToolMessage(
            icon: Icons.keyboard_outlined,
            color: AppCyberTheme.electricBlue,
            message:
                '${_apiToolSendShortcutLabel()} sends the request from '
                'anywhere in this dialog. '
                '${_apiToolSaveShortcutLabel()} saves it.',
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorizationEditor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Authorization type',
              prefixIcon: Icon(Icons.shield_outlined),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ApiToolAuthorizationType>(
                key: const Key('api-tool-authorization-type'),
                value: _authorizationType,
                isExpanded: true,
                isDense: true,
                items: ApiToolAuthorizationType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _isSending
                    ? null
                    : (type) {
                        if (type == null) return;
                        setState(() => _authorizationType = type);
                      },
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...switch (_authorizationType) {
            ApiToolAuthorizationType.none => [
              _ApiToolMessage(
                icon: Icons.lock_open_outlined,
                color: AppCyberTheme.textMuted,
                message: 'This request does not add an authorization header.',
              ),
            ],
            ApiToolAuthorizationType.bearer => [
              _buildAuthorizationField(
                fieldKey: const Key('api-tool-auth-token'),
                controller: _authTokenController,
                label: 'Token',
                hintText: '{{TOKEN}}',
              ),
            ],
            ApiToolAuthorizationType.basic => [
              _buildAuthorizationField(
                fieldKey: const Key('api-tool-auth-username'),
                controller: _authUsernameController,
                label: 'Username',
              ),
              const SizedBox(height: 10),
              _buildAuthorizationField(
                fieldKey: const Key('api-tool-auth-password'),
                controller: _authPasswordController,
                label: 'Password',
              ),
            ],
            ApiToolAuthorizationType.apiKey => [
              _buildAuthorizationField(
                fieldKey: const Key('api-tool-auth-api-key-name'),
                controller: _authApiKeyNameController,
                label: 'Header name',
                hintText: 'X-API-Key',
              ),
              const SizedBox(height: 10),
              _buildAuthorizationField(
                fieldKey: const Key('api-tool-auth-api-key-value'),
                controller: _authApiKeyValueController,
                label: 'Value',
                hintText: '{{API_KEY}}',
              ),
            ],
          },
        ],
      ),
    );
  }

  Widget _buildAuthorizationField({
    required Key fieldKey,
    required TextEditingController controller,
    required String label,
    String? hintText,
  }) {
    return _buildVariableDropField(
      controller: controller,
      enabled: !_isSending,
      child: TextField(
        key: fieldKey,
        controller: controller,
        enabled: !_isSending,
        style: AppCyberTheme.dataTextStyle(
          size: 11.2,
          color: AppCyberTheme.textPrimary,
        ),
        decoration: InputDecoration(labelText: label, hintText: hintText),
      ),
    );
  }

  Widget _buildHeadersEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$_activeHeaderCount active header(s)',
                style: AppCyberTheme.dataTextStyle(
                  size: 10.4,
                  color: AppCyberTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Scrollbar(
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
          ),
        ),
      ],
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
    final isRaw = _bodyMode == ApiToolBodyMode.raw;

    // One fixed-height chrome strip that scrolls sideways rather than wrapping,
    // so the editor below always gets every remaining pixel.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 46,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(
                  width: 158,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Body type',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ApiToolBodyMode>(
                        key: const Key('api-tool-body-mode'),
                        value: _bodyMode,
                        isExpanded: true,
                        isDense: true,
                        items: ApiToolBodyMode.values
                            .map(
                              (mode) => DropdownMenuItem(
                                value: mode,
                                child: Text(
                                  mode.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _isSending
                            ? null
                            : (mode) {
                                if (mode == null) return;
                                setState(() => _bodyMode = mode);
                              },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (isRaw) ...[
                  _ApiToolInlineAction(
                    actionKey: const Key('api-tool-beautify-json'),
                    icon: Icons.auto_fix_high_outlined,
                    label: 'Beautify',
                    tooltip: 'Format the raw body as indented JSON',
                    onPressed: _isSending || _bodyController.text.trim().isEmpty
                        ? null
                        : _beautifyRawBody,
                  ),
                  _ApiToolInlineAction(
                    actionKey: const Key('api-tool-clear-body'),
                    icon: Icons.backspace_outlined,
                    label: 'Clear',
                    tooltip: 'Empty the raw body',
                    onPressed: _isSending || _bodyController.text.isEmpty
                        ? null
                        : () {
                            _bodyController.clear();
                            _syncFormState();
                          },
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (_bodyMode) {
            ApiToolBodyMode.raw => _buildRawBodyEditor(),
            ApiToolBodyMode.multipart => _buildMultipartEditor(),
            ApiToolBodyMode.urlEncoded => _buildUrlEncodedEditor(),
          },
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 560;
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppCyberTheme.baseBackground.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppCyberTheme.electricBlue.withValues(alpha: 0.22),
            ),
          ),
          child: wide
              ? _buildWideMultipartRow(index, row, isEnabled, isFile)
              : _buildCompactMultipartRow(index, row, isEnabled, isFile),
        );
      },
    );
  }

  Widget _buildWideMultipartRow(
    int index,
    _ApiToolMultipartEditor row,
    bool isEnabled,
    bool isFile,
  ) {
    return Column(
      children: [
        Row(
          children: [
            _buildMultipartEnabledCheckbox(row),
            SizedBox(
              width: 92,
              child: _buildMultipartKindField(index, row, isEnabled),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMultipartTextField(
                fieldKey: Key('api-tool-multipart-name-$index'),
                controller: row.nameController,
                enabled: isEnabled,
                label: 'Key',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMultipartTextField(
                fieldKey: Key('api-tool-multipart-value-$index'),
                controller: row.valueController,
                enabled: isEnabled,
                label: isFile ? 'File path' : 'Value',
              ),
            ),
            if (isFile) _buildMultipartFilePicker(index, row, isEnabled),
            _buildRemoveMultipartButton(index),
          ],
        ),
        if (isFile) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: _buildMultipartContentTypeField(index, row, isEnabled),
          ),
        ],
      ],
    );
  }

  Widget _buildCompactMultipartRow(
    int index,
    _ApiToolMultipartEditor row,
    bool isEnabled,
    bool isFile,
  ) {
    return Column(
      children: [
        Row(
          children: [
            _buildMultipartEnabledCheckbox(row),
            Expanded(child: _buildMultipartKindField(index, row, isEnabled)),
            const SizedBox(width: 4),
            _buildRemoveMultipartButton(index),
          ],
        ),
        const SizedBox(height: 8),
        _buildMultipartTextField(
          fieldKey: Key('api-tool-multipart-name-$index'),
          controller: row.nameController,
          enabled: isEnabled,
          label: 'Key',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildMultipartTextField(
                fieldKey: Key('api-tool-multipart-value-$index'),
                controller: row.valueController,
                enabled: isEnabled,
                label: isFile ? 'File path' : 'Value',
              ),
            ),
            if (isFile) _buildMultipartFilePicker(index, row, isEnabled),
          ],
        ),
        if (isFile) ...[
          const SizedBox(height: 8),
          _buildMultipartContentTypeField(index, row, isEnabled),
        ],
      ],
    );
  }

  Widget _buildMultipartEnabledCheckbox(_ApiToolMultipartEditor row) {
    return Checkbox(
      value: row.enabled,
      onChanged: _isSending
          ? null
          : (value) => setState(() => row.enabled = value ?? true),
    );
  }

  Widget _buildMultipartKindField(
    int index,
    _ApiToolMultipartEditor row,
    bool isEnabled,
  ) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Type',
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ApiToolMultipartKind>(
          key: Key('api-tool-multipart-kind-$index'),
          value: row.kind,
          isExpanded: true,
          isDense: true,
          items: ApiToolMultipartKind.values
              .map(
                (kind) =>
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
              )
              .toList(growable: false),
          onChanged: isEnabled
              ? (value) {
                  if (value == null) return;
                  setState(() => row.kind = value);
                }
              : null,
        ),
      ),
    );
  }

  Widget _buildMultipartTextField({
    required Key fieldKey,
    required TextEditingController controller,
    required bool enabled,
    required String label,
  }) {
    return _buildVariableDropField(
      controller: controller,
      enabled: enabled,
      child: TextField(
        key: fieldKey,
        controller: controller,
        enabled: enabled,
        style: AppCyberTheme.dataTextStyle(
          size: 11.2,
          color: AppCyberTheme.textPrimary,
        ),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _buildMultipartContentTypeField(
    int index,
    _ApiToolMultipartEditor row,
    bool isEnabled,
  ) {
    return _buildVariableDropField(
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
          hintText: 'Auto detect',
        ),
      ),
    );
  }

  Widget _buildMultipartFilePicker(
    int index,
    _ApiToolMultipartEditor row,
    bool isEnabled,
  ) {
    return IconButton(
      key: Key('api-tool-multipart-pick-file-$index'),
      tooltip: 'Choose file',
      onPressed: isEnabled ? () => _pickMultipartFile(row) : null,
      icon: const Icon(Icons.folder_open_outlined),
    );
  }

  Widget _buildRemoveMultipartButton(int index) {
    return IconButton(
      tooltip: 'Remove field',
      onPressed: _isSending || _multipartRows.length == 1
          ? null
          : () => _removeMultipartRow(index),
      icon: const Icon(Icons.remove_circle_outline),
    );
  }

  Widget _buildUrlEncodedEditor() {
    return Scrollbar(
      controller: _urlEncodedScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _urlEncodedScrollController,
        padding: const EdgeInsets.only(right: 8, bottom: 4),
        child: Column(
          children: [
            for (var index = 0; index < _urlEncodedRows.length; index++) ...[
              _buildUrlEncodedRow(index),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('api-tool-add-urlencoded'),
                onPressed: _isSending ? null : _addUrlEncodedRow,
                icon: const Icon(Icons.add_outlined),
                label: const Text('Add field'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUrlEncodedRow(int index) {
    final row = _urlEncodedRows[index];
    final isEnabled = !_isSending && row.enabled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppCyberTheme.baseBackground.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppCyberTheme.electricBlue.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: row.enabled,
            onChanged: _isSending
                ? null
                : (value) => setState(() => row.enabled = value ?? true),
          ),
          Expanded(
            child: _buildVariableDropField(
              controller: row.nameController,
              enabled: isEnabled,
              child: TextField(
                key: Key('api-tool-urlencoded-name-$index'),
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
          const SizedBox(width: 8),
          Expanded(
            child: _buildVariableDropField(
              controller: row.valueController,
              enabled: isEnabled,
              child: TextField(
                key: Key('api-tool-urlencoded-value-$index'),
                controller: row.valueController,
                enabled: isEnabled,
                style: AppCyberTheme.dataTextStyle(
                  size: 11.2,
                  color: AppCyberTheme.textPrimary,
                ),
                decoration: const InputDecoration(labelText: 'Value'),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove field',
            onPressed: _isSending || _urlEncodedRows.length == 1
                ? null
                : () => _removeUrlEncodedRow(index),
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
      ),
    );
  }
}
