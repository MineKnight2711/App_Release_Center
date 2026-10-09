import 'package:flutter/material.dart';

import '../../shared/module_widgets.dart';
import '../controllers/qa_workspace_controller.dart';
import '../models/automation_models.dart';
import '../models/qa_models.dart';
import '../models/scenario_models.dart';
import '../services/flow_compiler.dart';
import '../theme/qa_tokens.dart';
import '../widgets/qa_widgets.dart';

List<String> _lines(String value) => value
    .split(RegExp(r'\r?\n'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList();

List<String> _csv(String value) => value
    .split(',')
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toSet()
    .toList();

Map<String, String> _keyValues(String value) {
  final result = <String, String>{};
  for (final line in _lines(value)) {
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    result[line.substring(0, separator).trim()] = line.substring(separator + 1);
  }
  return result;
}

/// Creates or edits a test case beside the list it belongs to.
Future<void> showScenarioEditor(
  BuildContext context, {
  required QaWorkspaceController controller,
  required QaSource source,
  TestScenario? existing,
}) {
  return showQaSideSheet<void>(
    context,
    key: const Key('qa-scenario-editor'),
    title: existing == null ? 'Test case mới' : 'Sửa test case',
    subtitle: source.name,
    width: 560,
    builder: (_) => _ScenarioForm(
      controller: controller,
      source: source,
      existing: existing,
    ),
  );
}

class _ScenarioForm extends StatefulWidget {
  const _ScenarioForm({
    required this.controller,
    required this.source,
    this.existing,
  });

  final QaWorkspaceController controller;
  final QaSource source;
  final TestScenario? existing;

  @override
  State<_ScenarioForm> createState() => _ScenarioFormState();
}

class _ScenarioFormState extends State<_ScenarioForm> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _module = TextEditingController(
    text: widget.existing?.module ?? 'General',
  );
  late final _preconditions = TextEditingController(
    text: widget.existing?.preconditions.join('\n'),
  );
  late final _steps = TextEditingController(
    text: widget.existing?.steps.join('\n'),
  );
  late final _expected = TextEditingController(
    text: widget.existing?.expectedResult,
  );
  late final _tags = TextEditingController(
    text: widget.existing?.tags.join(', '),
  );
  late String? _suiteId = () {
    final wanted = widget.existing?.suiteId;
    if (widget.source.suites.any((suite) => suite.id == wanted)) return wanted;
    return widget.source.suites.isEmpty ? null : widget.source.suites.first.id;
  }();
  late bool _enabled = widget.existing?.enabled ?? true;

  late final AutomationSpec? _spec = widget.existing?.automation;
  late bool _automated =
      _spec != null ||
      (widget.existing == null &&
          widget.source.suites.isEmpty &&
          widget.source.apps.isNotEmpty);
  late String? _app = () {
    final wanted = _spec?.app;
    if (widget.source.apps.any((app) => app.id == wanted)) return wanted;
    return widget.source.apps.isEmpty ? null : widget.source.apps.first.id;
  }();
  late final _role = TextEditingController(text: _spec?.role);
  late bool _writes = _spec?.writes ?? false;
  late final Set<String> _environments = {...?_spec?.environments};
  late final List<_StepDraft> _stepDrafts = [
    for (final step
        in _spec?.steps ??
            const [
              AutomationStep(type: AutomationStepType.launch, clearState: true),
              AutomationStep(type: AutomationStepType.login),
            ])
      _StepDraft(step),
  ];

  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final field in [
      _title,
      _module,
      _preconditions,
      _steps,
      _expected,
      _tags,
      _role,
    ]) {
      field.dispose();
    }
    for (final draft in _stepDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  QaApp? get _selectedApp {
    for (final app in widget.source.apps) {
      if (app.id == _app) return app;
    }
    return null;
  }

  AutomationSpec _automationSpec() => AutomationSpec(
    app: _app ?? '',
    role: _role.text.trim(),
    writes: _writes,
    environments: _environments
        .where((name) => _selectedApp?.environment(name) != null)
        .toList(),
    steps: [for (final draft in _stepDrafts) draft.step],
    flow: _spec?.flow ?? '',
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    final spec = _automated ? _automationSpec() : null;
    final error = await widget.controller.saveScenario(
      widget.source.id,
      TestScenario(
        id:
            widget.existing?.id ??
            'scenario-${DateTime.now().microsecondsSinceEpoch}',
        title: _title.text.trim(),
        module: _module.text.trim().isEmpty ? 'General' : _module.text.trim(),
        suiteId: spec == null ? _suiteId ?? '' : '',
        preconditions: _lines(_preconditions.text),
        steps: spec == null
            ? _lines(_steps.text)
            : [for (final step in spec.steps) step.summary],
        expectedResult: _expected.text.trim(),
        tags: _csv(_tags.text),
        enabled: _enabled,
        automation: spec,
      ),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  void _addStep(AutomationStepType type) =>
      setState(() => _stepDrafts.add(_StepDraft(AutomationStep(type: type))));

  void _moveStep(int index, int offset) => setState(() {
    final draft = _stepDrafts.removeAt(index);
    _stepDrafts.insert(index + offset, draft);
  });

  void _removeStep(int index) =>
      setState(() => _stepDrafts.removeAt(index).dispose());

  @override
  Widget build(BuildContext context) {
    final tokens = QaTokens.of(context);
    QaSuite? suite;
    for (final item in widget.source.suites) {
      if (item.id == _suiteId) suite = item;
    }
    return _FormFrame(
      onSave: _saving ? null : _save,
      children: [
        TextField(
          key: const Key('qa-scenario-title'),
          controller: _title,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên test case *'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _module,
          decoration: const InputDecoration(
            labelText: 'Module',
            helperText: 'Dùng để lọc danh sách test case.',
          ),
        ),
        const SizedBox(height: 14),
        SegmentedButton<bool>(
          key: const Key('qa-scenario-mode'),
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.terminal, size: 16),
              label: Text('Chạy suite có sẵn'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.smart_toy_outlined, size: 16),
              label: Text('QA Desk tự thao tác'),
            ),
          ],
          selected: {_automated},
          onSelectionChanged: (value) =>
              setState(() => _automated = value.single),
        ),
        const SizedBox(height: 14),
        if (_automated)
          ..._automationFields(context)
        else ...[
          DropdownButtonFormField<String>(
            key: const Key('qa-scenario-suite'),
            initialValue: _suiteId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Suite liên kết *',
              helperText: suite == null
                  ? null
                  : 'Lệnh: ${suite.commandPreview}',
              helperStyle: tokens.mono(size: 11, color: tokens.muted),
            ),
            items: [
              for (final item in widget.source.suites)
                DropdownMenuItem(
                  value: item.id,
                  child: Text(item.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(() => _suiteId = value),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _preconditions,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Điều kiện',
            helperText: 'Mỗi dòng một điều kiện.',
          ),
        ),
        if (!_automated) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _steps,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Các bước',
              helperText: 'Mỗi dòng một bước; được đánh số khi hiển thị.',
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _expected,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Kết quả mong đợi'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tags,
          decoration: const InputDecoration(
            labelText: 'Tag',
            helperText: 'Cách nhau bằng dấu phẩy.',
          ),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Cho phép chạy test case này'),
          value: _enabled,
          onChanged: (value) => setState(() => _enabled = value),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          NoticeBox(text: _error!, tone: NoticeTone.danger),
        ],
      ],
    );
  }

  List<Widget> _automationFields(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final apps = widget.source.apps;
    if (apps.isEmpty) {
      return const [
        NoticeBox(
          text:
              'Nguồn này chưa khai app nào. Thêm mục apps: vào '
              '.fiza-qa/project.yaml (appId hoặc url theo từng môi trường và '
              'flow đăng nhập), rồi bấm làm mới nguồn. Xem Hướng dẫn để có '
              'mẫu.',
          tone: NoticeTone.warning,
        ),
      ];
    }
    final app = _selectedApp;
    final roles = <String>{
      ...?widget.controller.automation?.vault.accounts
          .where((account) => account.app == _app)
          .map((account) => account.role),
    }.toList()..sort();

    return [
      DropdownButtonFormField<String>(
        key: const Key('qa-scenario-app'),
        initialValue: _app,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'App *',
          helperText: app == null || app.loginFlow.isNotEmpty
              ? null
              : 'App này chưa khai flow đăng nhập: bước "Đăng nhập" sẽ lỗi.',
        ),
        items: [
          for (final item in apps)
            DropdownMenuItem(value: item.id, child: Text(item.name)),
        ],
        onChanged: (value) => setState(() {
          _app = value;
          _environments.clear();
        }),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('qa-scenario-role'),
        controller: _role,
        decoration: InputDecoration(
          labelText: 'Đăng nhập với vai trò *',
          helperText: roles.isEmpty
              ? 'Khớp với vai trò của tài khoản trong kho, như "Chủ shop".'
              : 'Kho đang có: ${roles.join(', ')}',
        ),
      ),
      if (roles.isNotEmpty) ...[
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final role in roles)
              ActionChip(
                label: Text(role),
                onPressed: () => setState(() => _role.text = role),
              ),
          ],
        ),
      ],
      const SizedBox(height: 6),
      SwitchListTile(
        key: const Key('qa-scenario-writes'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Kịch bản tạo, sửa hoặc xoá dữ liệu'),
        subtitle: Text(
          _writes
              ? 'Không bao giờ chạy trên production. Sau khi chạy, QA Desk '
                    'chạy flow dọn dữ liệu nếu app có khai.'
              : 'Chỉ xem: chạy được cả trên production.',
        ),
        value: _writes,
        onChanged: (value) => setState(() => _writes = value),
      ),
      if (app != null && app.environments.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          'Chạy trên môi trường',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final environment in app.environments)
              FilterChip(
                label: Text(
                  environment.isProduction
                      ? '${environment.name} · production'
                      : environment.name,
                ),
                selected:
                    _environments.contains(environment.name) &&
                    !(_writes && environment.isProduction),
                onSelected: _writes && environment.isProduction
                    ? null
                    : (value) => setState(
                        () => value
                            ? _environments.add(environment.name)
                            : _environments.remove(environment.name),
                      ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Không chọn môi trường nào nghĩa là chạy được ở mọi môi trường được '
          'phép.',
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
        ),
      ],
      const SizedBox(height: 16),
      SectionLabel(
        'Các bước QA Desk làm',
        action: PopupMenuButton<AutomationStepType>(
          key: const Key('qa-add-step'),
          tooltip: 'Thêm bước',
          onSelected: _addStep,
          itemBuilder: (_) => [
            for (final type in AutomationStepType.values)
              PopupMenuItem(value: type, child: Text(type.label)),
          ],
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 17),
                SizedBox(width: 4),
                Text('Thêm bước'),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      for (var index = 0; index < _stepDrafts.length; index++) ...[
        _StepRow(
          key: ObjectKey(_stepDrafts[index]),
          index: index,
          draft: _stepDrafts[index],
          first: index == 0,
          last: index == _stepDrafts.length - 1,
          onChanged: () => setState(() {}),
          onMove: (offset) => _moveStep(index, offset),
          onRemove: () => _removeStep(index),
        ),
        const SizedBox(height: 8),
      ],
      Text(
        r'Chữ trên màn hình phải là trọn một dòng của phần tử (bật Khớp '
        r'một phần nếu chỉ là một đoạn). Trong ô Nhập, dùng '
        r'${MAESTRO_QA_USERNAME}, ${MAESTRO_QA_PASSWORD} hoặc '
        r'${MAESTRO_QA_<TRƯỜNG THÊM>} để lấy giá trị từ tài khoản demo: '
        'mật khẩu không bao giờ nằm trong file flow.',
        style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
      ),
      if (app != null) ...[
        const SizedBox(height: 8),
        _FlowPreview(
          compile: () => const FlowCompiler().compile(
            TestScenario(
              id: widget.existing?.id ?? 'test-case-moi',
              title: _title.text.trim().isEmpty
                  ? 'Test case mới'
                  : _title.text.trim(),
              module: '',
              suiteId: '',
              automation: _automationSpec(),
            ),
            app,
          ),
        ),
      ],
    ];
  }
}

/// A step being edited, with the text fields it needs.
class _StepDraft {
  _StepDraft(AutomationStep step)
    : type = step.type,
      byId = step.byId,
      clearState = step.clearState,
      partial = step.partial,
      target = TextEditingController(text: step.target),
      value = TextEditingController(text: step.value);

  AutomationStepType type;
  bool byId;
  bool clearState;
  bool partial;
  final TextEditingController target;
  final TextEditingController value;

  AutomationStep get step => AutomationStep(
    type: type,
    target: type.hasTarget ? target.text.trim() : '',
    value: type == AutomationStepType.input ? value.text : '',
    byId: byId && _selectsElement(type),
    clearState: type == AutomationStepType.launch && clearState,
    partial: partial && !byId && _selectsElement(type),
  );

  void dispose() {
    target.dispose();
    value.dispose();
  }
}

bool _selectsElement(AutomationStepType type) => switch (type) {
  AutomationStepType.tap ||
  AutomationStepType.input ||
  AutomationStepType.assertVisible ||
  AutomationStepType.assertNotVisible ||
  AutomationStepType.waitFor ||
  AutomationStepType.scrollTo => true,
  _ => false,
};

class _StepRow extends StatelessWidget {
  const _StepRow({
    super.key,
    required this.index,
    required this.draft,
    required this.first,
    required this.last,
    required this.onChanged,
    required this.onMove,
    required this.onRemove,
  });

  final int index;
  final _StepDraft draft;
  final bool first;
  final bool last;
  final VoidCallback onChanged;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;

  String get _targetLabel => switch (draft.type) {
    AutomationStepType.input =>
      draft.byId ? 'Id của ô (tuỳ chọn)' : 'Chữ trong ô, như gợi ý (tuỳ chọn)',
    AutomationStepType.screenshot => 'Tên ảnh',
    AutomationStepType.runFlow => 'File flow, như flows/tao-don.yaml',
    _ => draft.byId ? 'Id trợ năng' : 'Chữ trên màn hình',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = QaTokens.of(context);
    final type = draft.type;
    return Container(
      key: Key('qa-step-$index'),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: tokens.well,
        borderRadius: BorderRadius.circular(QaTokens.radius),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${index + 1}.',
                  style: tokens.mono(size: 12, color: tokens.muted),
                ),
              ),
              Expanded(
                child: DropdownButton<AutomationStepType>(
                  value: type,
                  isExpanded: true,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final item in AutomationStepType.values)
                      DropdownMenuItem(value: item, child: Text(item.label)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    draft.type = value;
                    onChanged();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Lên',
                visualDensity: VisualDensity.compact,
                onPressed: first ? null : () => onMove(-1),
                icon: const Icon(Icons.arrow_upward, size: 16),
              ),
              IconButton(
                tooltip: 'Xuống',
                visualDensity: VisualDensity.compact,
                onPressed: last ? null : () => onMove(1),
                icon: const Icon(Icons.arrow_downward, size: 16),
              ),
              IconButton(
                tooltip: 'Xoá bước',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
          if (type.hasTarget) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 22, right: 8),
              child: TextField(
                key: Key('qa-step-$index-target'),
                controller: draft.target,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: _targetLabel,
                ),
              ),
            ),
          ],
          if (type == AutomationStepType.input) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 22, right: 8),
              child: TextField(
                key: Key('qa-step-$index-value'),
                controller: draft.value,
                onChanged: (_) => onChanged(),
                style: tokens.mono(size: 12.5),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Nội dung nhập',
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final (label, variable) in const [
                    ('Tên đăng nhập', r'${MAESTRO_QA_USERNAME}'),
                    ('Mật khẩu', r'${MAESTRO_QA_PASSWORD}'),
                    ('Mã lần chạy', r'${MAESTRO_QA_RUN_ID}'),
                  ])
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(label),
                      onPressed: () {
                        draft.value.text = variable;
                        onChanged();
                      },
                    ),
                ],
              ),
            ),
          ],
          if (_selectsElement(type) || type == AutomationStepType.launch)
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Wrap(
                children: [
                  if (_selectsElement(type))
                    _InlineCheck(
                      label: 'Tìm theo id',
                      value: draft.byId,
                      onChanged: (value) {
                        draft.byId = value;
                        onChanged();
                      },
                    ),
                  if (_selectsElement(type) && !draft.byId)
                    Tooltip(
                      message:
                          'Tắt: chữ phải là trọn một dòng của phần tử. Bật: '
                          'chỉ cần nằm trong chữ của phần tử.',
                      child: _InlineCheck(
                        label: 'Khớp một phần',
                        value: draft.partial,
                        onChanged: (value) {
                          draft.partial = value;
                          onChanged();
                        },
                      ),
                    ),
                  if (type == AutomationStepType.launch)
                    _InlineCheck(
                      label: 'Xoá dữ liệu app trước khi mở',
                      value: draft.clearState,
                      onChanged: (value) {
                        draft.clearState = value;
                        onChanged();
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InlineCheck extends StatelessWidget {
  const _InlineCheck({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          visualDensity: VisualDensity.compact,
          onChanged: (next) => onChanged(next ?? false),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 8),
      ],
    ),
  );
}

/// The Maestro flow the steps compile to, for whoever wants to read it.
class _FlowPreview extends StatelessWidget {
  const _FlowPreview({required this.compile});

  final String Function() compile;

  @override
  Widget build(BuildContext context) {
    final tokens = QaTokens.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        'Xem flow Maestro sẽ ghi ra',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: [
        Builder(
          builder: (context) {
            String text;
            try {
              text = compile();
            } on FlowCompileException catch (error) {
              text = '# ${error.message}';
            }
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tokens.well,
                borderRadius: BorderRadius.circular(QaTokens.radius),
                border: Border.all(color: tokens.line),
              ),
              child: SelectableText(text, style: tokens.mono(size: 11.5)),
            );
          },
        ),
      ],
    );
  }
}

/// Creates or edits an environment: the variables a suite process receives,
/// and the names of secrets asked for each session.
Future<void> showEnvironmentEditor(
  BuildContext context, {
  required QaWorkspaceController controller,
  required QaSource source,
  EnvironmentProfile? existing,
}) {
  return showQaSideSheet<void>(
    context,
    key: const Key('qa-environment-editor'),
    title: existing == null ? 'Môi trường mới' : 'Sửa môi trường',
    subtitle: source.name,
    width: 520,
    builder: (_) => _EnvironmentForm(
      controller: controller,
      source: source,
      existing: existing,
    ),
  );
}

class _EnvironmentForm extends StatefulWidget {
  const _EnvironmentForm({
    required this.controller,
    required this.source,
    this.existing,
  });

  final QaWorkspaceController controller;
  final QaSource source;
  final EnvironmentProfile? existing;

  @override
  State<_EnvironmentForm> createState() => _EnvironmentFormState();
}

class _EnvironmentFormState extends State<_EnvironmentForm> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _variables = TextEditingController(
    text: widget.existing?.variables.entries
        .map((item) => '${item.key}=${item.value}')
        .join('\n'),
  );
  late final _secretKeys = TextEditingController(
    text: widget.existing?.secretKeys.join(', '),
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _variables.dispose();
    _secretKeys.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final error = await widget.controller.saveEnvironment(
      widget.source.id,
      EnvironmentProfile(
        id:
            widget.existing?.id ??
            'env-${DateTime.now().microsecondsSinceEpoch}',
        name: _name.text.trim(),
        variables: _keyValues(_variables.text),
        secretKeys: _csv(_secretKeys.text),
      ),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QaTokens.of(context);
    return _FormFrame(
      onSave: _saving ? null : _save,
      children: [
        TextField(
          key: const Key('qa-environment-name'),
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên môi trường *'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('qa-environment-variables'),
          controller: _variables,
          minLines: 5,
          maxLines: 12,
          style: tokens.mono(size: 12.5),
          decoration: const InputDecoration(
            labelText: 'Biến',
            helperText: 'KEY=value, mỗi dòng một biến. Được lưu vào catalog.',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('qa-environment-secrets'),
          controller: _secretKeys,
          decoration: const InputDecoration(
            labelText: 'Tên secret',
            helperText:
                'Cách nhau bằng dấu phẩy. Chỉ lưu tên; giá trị nhập theo phiên.',
          ),
        ),
        const SizedBox(height: 12),
        const NoticeBox(
          text:
              'Catalog nằm ở .fiza-qa/scenarios.json trong dự án và có thể '
              'được commit: đừng đặt token hay mật khẩu vào phần Biến.',
          tone: NoticeTone.warning,
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          NoticeBox(text: _error!, tone: NoticeTone.danger),
        ],
      ],
    );
  }
}

/// A side-sheet form: scrolling fields above a fixed save bar.
class _FormFrame extends StatelessWidget {
  const _FormFrame({required this.children, required this.onSave});

  final List<Widget> children;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            children: children,
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Huỷ'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('qa-form-save'),
                onPressed: onSave,
                child: const Text('Lưu'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
