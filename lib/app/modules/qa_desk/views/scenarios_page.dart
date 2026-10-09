import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../shared/module_widgets.dart';
import '../controllers/qa_workspace_controller.dart';
import '../models/qa_models.dart';
import '../models/scenario_models.dart';
import '../theme/qa_tokens.dart';
import '../widgets/qa_widgets.dart';
import 'automation_dialogs.dart';
import 'scenario_editors.dart';
import 'secrets_dialog.dart';

/// Each source's test cases and the environments its suites run with.
///
/// Environments are defined here; which one a run uses is chosen on the run
/// page, next to the suites it applies to.
class QaScenariosPage extends StatefulWidget {
  const QaScenariosPage({
    super.key,
    required this.controller,
    required this.onRunStarted,
    this.initialSourceId,
  });

  final QaWorkspaceController controller;

  /// Called when a test case is run, so the page can show the run.
  final VoidCallback onRunStarted;
  final String? initialSourceId;

  @override
  State<QaScenariosPage> createState() => _QaScenariosPageState();
}

class _QaScenariosPageState extends State<QaScenariosPage> {
  late String? _sourceId = widget.initialSourceId;
  String? _module;

  QaWorkspaceController get _controller => widget.controller;

  @override
  void didUpdateWidget(covariant QaScenariosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSourceId != oldWidget.initialSourceId &&
        widget.initialSourceId != null) {
      _sourceId = widget.initialSourceId;
      _module = null;
    }
  }

  QaSource _resolveSource() {
    for (final source in _controller.sources) {
      if (source.id == _sourceId) return source;
    }
    return _controller.sources.first;
  }

  Future<void> _import(QaSource source) async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Catalog JSON', extensions: ['json']),
      ],
    );
    if (file == null) return;
    final error = await _controller.importCatalog(source.id, file.path);
    if (mounted) showQaMessage(context, error ?? 'Đã nhập catalog.');
  }

  Future<void> _export(QaSource source) async {
    final location = await getSaveLocation(
      suggestedName: '${source.id}-scenarios.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Catalog JSON', extensions: ['json']),
      ],
    );
    if (location == null) return;
    final error = await _controller.exportCatalog(source.id, location.path);
    if (mounted) showQaMessage(context, error ?? 'Đã xuất catalog.');
  }

  Future<void> _deleteScenario(QaSource source, TestScenario scenario) async {
    final confirmed = await confirmQa(
      context,
      title: 'Xoá test case?',
      message: 'Xoá "${scenario.title}" khỏi catalog của ${source.name}.',
      confirmLabel: 'Xoá',
    );
    if (confirmed) await _controller.deleteScenario(source.id, scenario.id);
  }

  Future<void> _deleteEnvironment(
    QaSource source,
    EnvironmentProfile environment,
  ) async {
    final confirmed = await confirmQa(
      context,
      title: 'Xoá môi trường?',
      message:
          'Xoá "${environment.name}" khỏi catalog của ${source.name}. Secret '
          'đã nhập cho nó trong phiên này cũng bị bỏ.',
      confirmLabel: 'Xoá',
    );
    if (confirmed) {
      await _controller.deleteEnvironment(source.id, environment.id);
    }
  }

  Future<void> _run(QaSource source, TestScenario scenario) async {
    if (scenario.isAutomated) {
      final blocker = _controller.automationBlocker(source.id, scenario);
      if (blocker != null) {
        showQaMessage(context, 'Chưa chạy được: $blocker');
        return;
      }
      if (!await confirmProductionRun(context, _controller, count: 1)) return;
    }
    widget.onRunStarted();
    await _controller.runScenario(source.id, scenario.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (_controller.sources.isEmpty) {
          return const QaEmptyState(
            icon: Icons.account_tree_outlined,
            title: 'Chưa có nguồn',
            message: 'Thêm nguồn ở Chạy test trước, rồi soạn kịch bản cho nó.',
          );
        }
        final source = _resolveSource();
        final catalog = _controller.catalogFor(source.id);
        if (catalog == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final side = _SourceAndEnvironments(
          controller: _controller,
          source: source,
          catalog: catalog,
          onSelectSource: (id) => setState(() {
            _sourceId = id;
            _module = null;
          }),
          onAddEnvironment: () => showEnvironmentEditor(
            context,
            controller: _controller,
            source: source,
          ),
          onEditEnvironment: (environment) => showEnvironmentEditor(
            context,
            controller: _controller,
            source: source,
            existing: environment,
          ),
          onSecrets: (environment) => showSecretsDialog(
            context,
            controller: _controller,
            source: source,
            environment: environment,
          ),
          onDeleteEnvironment: (environment) =>
              _deleteEnvironment(source, environment),
        );
        final list = _TestCaseList(
          controller: _controller,
          source: source,
          catalog: catalog,
          module: _module,
          onModuleChanged: (value) => setState(() => _module = value),
          onCreate: () => showScenarioEditor(
            context,
            controller: _controller,
            source: source,
          ),
          onEdit: (scenario) => showScenarioEditor(
            context,
            controller: _controller,
            source: source,
            existing: scenario,
          ),
          onDelete: (scenario) => _deleteScenario(source, scenario),
          onRun: (scenario) => _run(source, scenario),
          onImport: () => _import(source),
          onExport: () => _export(source),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 950) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  side,
                  const SizedBox(height: 12),
                  SizedBox(height: 640, child: list),
                ],
              );
            }
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 320,
                    child: SingleChildScrollView(child: side),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: list),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SourceAndEnvironments extends StatelessWidget {
  const _SourceAndEnvironments({
    required this.controller,
    required this.source,
    required this.catalog,
    required this.onSelectSource,
    required this.onAddEnvironment,
    required this.onEditEnvironment,
    required this.onSecrets,
    required this.onDeleteEnvironment,
  });

  final QaWorkspaceController controller;
  final QaSource source;
  final SourceScenarioCatalog catalog;
  final ValueChanged<String> onSelectSource;
  final VoidCallback onAddEnvironment;
  final ValueChanged<EnvironmentProfile> onEditEnvironment;
  final ValueChanged<EnvironmentProfile> onSecrets;
  final ValueChanged<EnvironmentProfile> onDeleteEnvironment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final selectedEnvironment = controller.selectedEnvironmentId(source.id);

    return ModuleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Nguồn'),
          const SizedBox(height: 8),
          for (final item in controller.sources) ...[
            QaSelectableRow(
              key: Key('qa-scenario-source-${item.id}'),
              selected: item.id == source.id,
              onTap: () => onSelectSource(item.id),
              child: Row(
                children: [
                  Icon(sourceIcon(item.type), size: 17, color: tokens.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${controller.catalogFor(item.id)?.scenarios.length ?? 0} '
                          'test case · '
                          '${controller.catalogFor(item.id)?.environments.length ?? 0} '
                          'môi trường',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 14),
          SectionLabel(
            'Môi trường',
            action: IconButton(
              key: const Key('qa-add-environment'),
              tooltip: 'Thêm môi trường',
              visualDensity: VisualDensity.compact,
              onPressed: onAddEnvironment,
              icon: const Icon(Icons.add, size: 18),
            ),
          ),
          Text(
            'Biến được truyền vào tiến trình của suite. Môi trường có dấu ● '
            'là môi trường lượt chạy tới sẽ dùng.',
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
          ),
          const SizedBox(height: 8),
          for (final environment in catalog.environments) ...[
            _EnvironmentRow(
              controller: controller,
              source: source,
              environment: environment,
              selected: environment.id == selectedEnvironment,
              canDelete: catalog.environments.length > 1,
              onEdit: () => onEditEnvironment(environment),
              onSecrets: () => onSecrets(environment),
              onDelete: () => onDeleteEnvironment(environment),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _EnvironmentRow extends StatelessWidget {
  const _EnvironmentRow({
    required this.controller,
    required this.source,
    required this.environment,
    required this.selected,
    required this.canDelete,
    required this.onEdit,
    required this.onSecrets,
    required this.onDelete,
  });

  final QaWorkspaceController controller;
  final QaSource source;
  final EnvironmentProfile environment;
  final bool selected;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onSecrets;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final secretsSet = environment.secretKeys
        .where(
          (key) =>
              controller.sessionSecretIsSet(source.id, environment.id, key),
        )
        .length;

    return QaSelectableRow(
      key: Key('qa-environment-${environment.id}'),
      selected: selected,
      padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
      onTap: controller.isRunning
          ? null
          : () => controller.selectEnvironment(source.id, environment.id),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 17,
            color: selected ? tokens.accent : tokens.faint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  environment.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    '${environment.variables.length} biến',
                    if (environment.secretKeys.isNotEmpty)
                      '$secretsSet/${environment.secretKeys.length} secret',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secretsSet < environment.secretKeys.length
                        ? tokens.palette.warning
                        : tokens.muted,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Thao tác môi trường',
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'secrets') onSecrets();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Sửa')),
              if (environment.secretKeys.isNotEmpty)
                const PopupMenuItem(
                  value: 'secrets',
                  child: Text('Nhập secret'),
                ),
              if (canDelete)
                const PopupMenuItem(value: 'delete', child: Text('Xoá')),
            ],
          ),
        ],
      ),
    );
  }
}

class _TestCaseList extends StatelessWidget {
  const _TestCaseList({
    required this.controller,
    required this.source,
    required this.catalog,
    required this.module,
    required this.onModuleChanged,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onRun,
    required this.onImport,
    required this.onExport,
  });

  final QaWorkspaceController controller;
  final QaSource source;
  final SourceScenarioCatalog catalog;
  final String? module;
  final ValueChanged<String?> onModuleChanged;
  final VoidCallback onCreate;
  final ValueChanged<TestScenario> onEdit;
  final ValueChanged<TestScenario> onDelete;
  final ValueChanged<TestScenario> onRun;
  final VoidCallback onImport;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final modules =
        catalog.scenarios.map((item) => item.module).toSet().toList()..sort();
    final activeModule = modules.contains(module) ? module : null;
    final scenarios =
        catalog.scenarios
            .where(
              (item) => activeModule == null || item.module == activeModule,
            )
            .toList()
          ..sort((a, b) {
            final byModule = a.module.compareTo(b.module);
            return byModule == 0 ? a.title.compareTo(b.title) : byModule;
          });
    final error = controller.catalogErrors[source.id];

    return ModuleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaPanelHeader(
            title: 'Test case · ${source.name}',
            subtitle:
                '${catalog.scenarios.length} test case · .fiza-qa/scenarios.json',
            trailing: [
              FilledButton.icon(
                key: const Key('qa-new-scenario'),
                onPressed: source.suites.isEmpty && source.apps.isEmpty
                    ? null
                    : onCreate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Test case'),
              ),
              PopupMenuButton<String>(
                tooltip: 'Nhập hoặc xuất catalog',
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'import') onImport();
                  if (value == 'export') onExport();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'import',
                    child: ListTile(
                      leading: Icon(Icons.file_download_outlined),
                      title: Text('Nhập catalog JSON…'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'export',
                    child: ListTile(
                      leading: Icon(Icons.file_upload_outlined),
                      title: Text('Xuất catalog JSON…'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (modules.length > 1) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: QaChoiceChip(
                      label: 'Tất cả',
                      selected: activeModule == null,
                      onSelected: (_) => onModuleChanged(null),
                    ),
                  ),
                  for (final item in modules)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: QaChoiceChip(
                        label: item,
                        selected: activeModule == item,
                        onSelected: (_) => onModuleChanged(item),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            NoticeBox(text: error, tone: NoticeTone.warning),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: scenarios.isEmpty
                ? const QaEmptyState(
                    icon: Icons.fact_check_outlined,
                    title: 'Chưa có test case',
                    message:
                        'Test case mô tả điều kiện, các bước và kết quả mong '
                        'đợi, và gắn với một suite để chạy lại khi cần.',
                  )
                : ListView.separated(
                    itemCount: scenarios.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _TestCaseTile(
                      controller: controller,
                      source: source,
                      scenario: scenarios[index],
                      onEdit: onEdit,
                      onDelete: onDelete,
                      onRun: onRun,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TestCaseTile extends StatelessWidget {
  const _TestCaseTile({
    required this.controller,
    required this.source,
    required this.scenario,
    required this.onEdit,
    required this.onDelete,
    required this.onRun,
  });

  final QaWorkspaceController controller;
  final QaSource source;
  final TestScenario scenario;
  final ValueChanged<TestScenario> onEdit;
  final ValueChanged<TestScenario> onDelete;
  final ValueChanged<TestScenario> onRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    QaSuite? suite;
    for (final item in source.suites) {
      if (item.id == scenario.suiteId) suite = item;
    }
    final spec = scenario.automation;
    final canRun =
        scenario.enabled &&
        (suite != null || spec != null) &&
        !controller.isRunning;

    return Container(
      decoration: BoxDecoration(
        color: tokens.well,
        borderRadius: BorderRadius.circular(QaTokens.radius),
        border: Border.all(color: tokens.line),
      ),
      child: ExpansionTile(
        key: PageStorageKey('qa-scenario-${scenario.id}'),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          !scenario.enabled
              ? Icons.pause_circle_outline
              : spec != null
              ? Icons.smart_toy_outlined
              : Icons.fact_check_outlined,
          color: scenario.enabled ? tokens.accent : tokens.faint,
        ),
        title: Text(
          scenario.title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: scenario.enabled ? null : tokens.muted,
          ),
        ),
        subtitle: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${scenario.module} · '),
              if (spec != null)
                TextSpan(
                  text:
                      'Tự thao tác · ${source.app(spec.app)?.name ?? spec.app}'
                      ' · ${spec.role}${spec.writes ? ' · ghi dữ liệu' : ''}',
                  style: TextStyle(
                    color: source.app(spec.app) == null
                        ? tokens.palette.danger
                        : null,
                  ),
                )
              else
                TextSpan(
                  text: suite?.name ?? 'thiếu suite ${scenario.suiteId}',
                  style: TextStyle(
                    color: suite == null ? tokens.palette.danger : null,
                  ),
                ),
              if (!scenario.enabled) const TextSpan(text: ' · tạm tắt'),
            ],
          ),
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('qa-run-scenario-${scenario.id}'),
              tooltip: spec != null
                  ? 'QA Desk tự chạy trên ${controller.appEnvironment}'
                  : suite == null
                  ? 'Suite liên kết không còn trong nguồn'
                  : 'Chạy suite liên kết (${suite.name})',
              onPressed: canRun ? () => onRun(scenario) : null,
              icon: const Icon(Icons.play_arrow),
            ),
            PopupMenuButton<String>(
              tooltip: 'Thao tác test case',
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (value) {
                if (value == 'edit') onEdit(scenario);
                if (value == 'delete') onDelete(scenario);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Sửa')),
                PopupMenuItem(value: 'delete', child: Text('Xoá')),
              ],
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(title: 'Điều kiện', lines: scenario.preconditions),
          _Section(title: 'Các bước', lines: scenario.steps, numbered: true),
          _Section(
            title: 'Kết quả mong đợi',
            lines: scenario.expectedResult.isEmpty
                ? const []
                : [scenario.expectedResult],
          ),
          if (scenario.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 5,
              runSpacing: 4,
              children: [for (final tag in scenario.tags) QaTag(label: tag)],
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.lines,
    this.numbered = false,
  });

  final String title;
  final List<String> lines;
  final bool numbered;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          for (final (index, line) in lines.indexed)
            Text(
              numbered ? '${index + 1}. $line' : '• $line',
              style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
            ),
        ],
      ),
    );
  }
}
