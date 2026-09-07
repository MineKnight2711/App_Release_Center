part of '../../home_view.dart';

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
