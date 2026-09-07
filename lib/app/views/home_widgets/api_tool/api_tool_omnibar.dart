part of '../../home_view.dart';

/// Zone 1 of the API Tool: a subtle meta bar (workspace, collection and
/// environment pills) stacked on top of a single seamless omnibar that owns the
/// natural `[METHOD] -> [URL] -> [SEND]` flow.
mixin _ApiToolOmnibarSection on _ApiToolDialogCore {
  bool get _canSendRequest =>
      !_isSending && _urlController.text.trim().isNotEmpty;

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 12),
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
          _buildMetaBar(context),
          const SizedBox(height: 10),
          _buildOmnibar(context),
        ],
      ),
    );
  }

  Widget _buildMetaBar(BuildContext context) {
    final activeCollection = _activeCollection;

    return Row(
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
            dimension: 32,
            child: Icon(Icons.http_outlined, size: 18),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('API Tool', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 10),
              Flexible(
                child: Obx(() {
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
              ),
            ],
          ),
        ),
        const Spacer(),
        _buildHeaderCollectionDropdown(),
        const SizedBox(width: 6),
        _buildHeaderEnvironmentDropdown(activeCollection),
        const SizedBox(width: 6),
        _buildEnvironmentVariablesMenu(_activeEnvironment),
        IconButton(
          key: const Key('close-api-tool'),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  /// The unified omnibar. Method selector, URL field and the dynamic
  /// Send/Stop button share one continuous surface so the eye never leaves the
  /// request line.
  Widget _buildOmnibar(BuildContext context) {
    final methodColor = _apiToolMethodColor(_method);

    return Container(
      decoration: BoxDecoration(
        color: AppCyberTheme.baseBackground.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppCyberTheme.electricBlue.withValues(alpha: 0.34),
        ),
        boxShadow: AppCyberTheme.isCyber
            ? [
                BoxShadow(
                  color: AppCyberTheme.electricBlue.withValues(alpha: 0.12),
                  blurRadius: 16,
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: KeyedSubtree(
              key: const Key('api-tool-method'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ApiToolMethod>(
                  value: _method,
                  isExpanded: true,
                  isDense: true,
                  borderRadius: BorderRadius.circular(8),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  style: AppCyberTheme.dataTextStyle(
                    size: 12,
                    color: methodColor,
                    weight: FontWeight.w900,
                  ),
                  iconEnabledColor: methodColor,
                  items: ApiToolMethod.values
                      .map(
                        (method) => DropdownMenuItem(
                          value: method,
                          child: Text(
                            method.label,
                            style: AppCyberTheme.dataTextStyle(
                              size: 12,
                              color: _apiToolMethodColor(method),
                              weight: FontWeight.w900,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _isSending
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _method = value);
                        },
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 26,
            color: AppCyberTheme.electricBlue.withValues(alpha: 0.26),
          ),
          Expanded(
            child: _buildVariableDropField(
              controller: _urlController,
              enabled: !_isSending,
              child: TextField(
                key: const Key('api-tool-url'),
                controller: _urlController,
                enabled: !_isSending,
                onSubmitted: (_) {
                  if (_canSendRequest) unawaited(_sendRequest());
                },
                style: AppCyberTheme.dataTextStyle(
                  size: 12.4,
                  color: AppCyberTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'https://api.example.com/users',
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  hintStyle: AppCyberTheme.dataTextStyle(
                    size: 12.4,
                    color: AppCyberTheme.textMuted,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _buildSendButton(),
        ],
      ),
    );
  }

  /// The Send button doubles as the Cancel control while a request is in
  /// flight, which keeps the omnibar free of a permanently disabled button.
  Widget _buildSendButton() {
    if (_isSending) {
      return Tooltip(
        message: 'Stop the request in flight',
        child: FilledButton.icon(
          key: const Key('api-tool-cancel'),
          onPressed: _cancelRequest,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          icon: const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: const Text('Stop'),
        ),
      );
    }

    return Tooltip(
      message: 'Send request (${_apiToolSendShortcutLabel()})',
      child: FilledButton.icon(
        key: const Key('api-tool-send'),
        onPressed: _canSendRequest ? _sendRequest : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        icon: const Icon(Icons.send_outlined, size: 18),
        label: const Text('Send'),
      ),
    );
  }

  Widget _buildHeaderCollectionDropdown() {
    final collectionIds = _collections.map((entry) => entry.id).toSet();
    final selectedId = collectionIds.contains(_selectedCollectionId)
        ? _selectedCollectionId
        : null;

    return _ApiToolMetaPill(
      icon: Icons.folder_copy_outlined,
      width: 168,
      child: KeyedSubtree(
        key: const Key('api-tool-collection-root'),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedId,
            isExpanded: true,
            isDense: true,
            hint: Text('Collection', style: _metaPillTextStyle()),
            style: _metaPillTextStyle(),
            borderRadius: BorderRadius.circular(10),
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
                      _expandedCollectionIds.add(value);
                    });
                  },
          ),
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
    final variableCount = _activeEnvironment?.variables
        .where((variable) => variable.enabled && variable.hasName)
        .length;

    return _ApiToolMetaPill(
      icon: Icons.public_outlined,
      width: 158,
      highlighted: activeEnvironmentId.isNotEmpty,
      child: KeyedSubtree(
        key: const Key('api-tool-active-environment'),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: activeEnvironmentId,
            isExpanded: true,
            isDense: true,
            style: _metaPillTextStyle(
              highlighted: activeEnvironmentId.isNotEmpty,
            ),
            borderRadius: BorderRadius.circular(10),
            items: [
              const DropdownMenuItem(value: '', child: Text('No environment')),
              if (collection != null)
                for (final environment in collection.environments)
                  DropdownMenuItem(
                    value: environment.id,
                    child: Text(
                      environment.id == activeEnvironmentId &&
                              (variableCount ?? 0) > 0
                          ? '${environment.displayName} ($variableCount vars)'
                          : environment.displayName,
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
      ),
    );
  }

  TextStyle _metaPillTextStyle({bool highlighted = false}) {
    return AppCyberTheme.dataTextStyle(
      size: 11,
      color: highlighted ? AppCyberTheme.neonGreen : AppCyberTheme.textPrimary,
      weight: FontWeight.w700,
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
            dimension: 34,
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
                minimumSize: const Size.square(34),
                fixedSize: const Size.square(34),
                shape: const CircleBorder(),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: const Icon(Icons.tune_outlined, size: 17),
            ),
          ),
        );
      },
    );
  }
}
