import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/module_widgets.dart';
import '../controllers/qa_workspace_controller.dart';
import '../models/qa_models.dart';
import '../models/scenario_models.dart';
import '../theme/qa_tokens.dart';
import 'qa_widgets.dart';

/// Sources and their suites as one tree, replacing the standalone app's two
/// columns where a source had to be ticked before its suites even showed.
///
/// Each source row also carries the environment its suites will run with,
/// which used to be chosen on a different tab and was invisible here.
class QaSuiteTree extends StatefulWidget {
  const QaSuiteTree({
    super.key,
    required this.controller,
    required this.addSourceButton,
    required this.onOpenScenarios,
    required this.onEnterSecrets,
    this.onSelectionChanged,
  });

  final QaWorkspaceController controller;
  final Widget addSourceButton;
  final ValueChanged<String> onOpenScenarios;
  final void Function(QaSource source, EnvironmentProfile environment)
  onEnterSecrets;
  final VoidCallback? onSelectionChanged;

  @override
  State<QaSuiteTree> createState() => _QaSuiteTreeState();
}

class _QaSuiteTreeState extends State<QaSuiteTree> {
  final _filter = TextEditingController();
  final _collapsed = <String>{};

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  bool _matchesScenario(TestScenario scenario, String query) =>
      scenario.title.toLowerCase().contains(query) ||
      scenario.module.toLowerCase().contains(query) ||
      scenario.tags.any((tag) => tag.toLowerCase().contains(query));

  bool _matches(QaSuite suite, String query) =>
      suite.name.toLowerCase().contains(query) ||
      suite.id.toLowerCase().contains(query) ||
      suite.description.toLowerCase().contains(query) ||
      suite.commandPreview.toLowerCase().contains(query) ||
      suite.tags.any((tag) => tag.toLowerCase().contains(query));

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final query = _filter.text.trim().toLowerCase();
    final total = controller.sources.fold<int>(
      0,
      (sum, source) => sum + source.suites.length,
    );
    final automatedTotal = controller.sources.fold<int>(
      0,
      (sum, source) => sum + controller.automatedScenarios(source).length,
    );
    final nodes = <Widget>[];
    for (final source in controller.sources) {
      final everything =
          query.isEmpty || source.name.toLowerCase().contains(query);
      final suites = everything
          ? source.suites
          : source.suites.where((suite) => _matches(suite, query)).toList();
      final automated = [
        for (final scenario in controller.automatedScenarios(source))
          if (everything || _matchesScenario(scenario, query)) scenario,
      ];
      if (suites.isEmpty && automated.isEmpty) continue;
      nodes.add(
        _SourceNode(
          controller: controller,
          source: source,
          suites: suites,
          automated: automated,
          expanded: query.isNotEmpty || !_collapsed.contains(source.id),
          onToggleExpanded: () => setState(() {
            if (!_collapsed.remove(source.id)) _collapsed.add(source.id);
          }),
          onOpenScenarios: () => widget.onOpenScenarios(source.id),
          onEnterSecrets: (environment) =>
              widget.onEnterSecrets(source, environment),
          onSelectionChanged: widget.onSelectionChanged,
        ),
      );
    }

    return ModuleCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaPanelHeader(
            title: 'Nguồn & suite',
            subtitle: [
              '${controller.selectedSuiteCount}/$total suite',
              if (automatedTotal > 0)
                '${controller.selectedAutomationCount}/$automatedTotal tự thao '
                    'tác',
              '${controller.sources.length} nguồn',
            ].join(' · '),
            trailing: [widget.addSourceButton],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('qa-suite-filter'),
            controller: _filter,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: 'Lọc theo tên suite, lệnh hoặc tag',
              suffixIcon: _filter.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Xoá bộ lọc',
                      onPressed: () => setState(_filter.clear),
                      icon: const Icon(Icons.close, size: 16),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: nodes.isEmpty
                ? const QaEmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'Không có suite khớp',
                    message: 'Thử từ khoá khác, hoặc xoá bộ lọc.',
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: nodes,
                  ),
          ),
        ],
      ),
    );
  }
}

class _SourceNode extends StatelessWidget {
  const _SourceNode({
    required this.controller,
    required this.source,
    required this.suites,
    required this.automated,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onOpenScenarios,
    required this.onEnterSecrets,
    this.onSelectionChanged,
  });

  final QaWorkspaceController controller;
  final QaSource source;

  /// The suites the filter lets through.
  final List<QaSuite> suites;

  /// The automated scenarios the filter lets through.
  final List<TestScenario> automated;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onOpenScenarios;
  final ValueChanged<EnvironmentProfile> onEnterSecrets;
  final VoidCallback? onSelectionChanged;

  Future<void> _remove(BuildContext context) async {
    final confirmed = await confirmQa(
      context,
      title: 'Bỏ nguồn khỏi QA Desk?',
      message:
          'Bỏ "${source.name}" khỏi danh sách nguồn. Lịch sử chạy và thư mục '
          '.fiza-qa trong dự án vẫn được giữ nguyên.',
      confirmLabel: 'Bỏ nguồn',
    );
    if (confirmed) await controller.removeSource(source.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final running = controller.isRunning;
    final runnable = [
      for (final scenario in controller.automatedScenarios(source))
        if (scenario.enabled) scenario,
    ];
    final selectedSuites = source.suites
        .where((suite) => controller.isSuiteSelected(source, suite))
        .length;
    final selectedAutomated = runnable
        .where((scenario) => controller.isAutomationSelected(source, scenario))
        .length;
    final selectedCount = selectedSuites + selectedAutomated;
    final allSelected = selectedCount == source.suites.length + runnable.length;
    final catalog = controller.catalogFor(source.id);
    final environmentId = controller.selectedEnvironmentId(source.id);
    EnvironmentProfile? environment;
    for (final item in catalog?.environments ?? const <EnvironmentProfile>[]) {
      if (item.id == environmentId) environment = item;
    }
    final catalogError = controller.catalogErrors[source.id];

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: expanded ? 'Thu gọn' : 'Mở rộng',
                visualDensity: VisualDensity.compact,
                onPressed: onToggleExpanded,
                icon: Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 20,
                ),
              ),
              Checkbox(
                key: Key('qa-source-${source.id}'),
                tristate: true,
                value: selectedCount == 0
                    ? false
                    : allSelected
                    ? true
                    : null,
                onChanged: running
                    ? null
                    : (_) {
                        controller.setSourceSelected(source.id, !allSelected);
                        onSelectionChanged?.call();
                      },
              ),
              Icon(sourceIcon(source.type), size: 17, color: tokens.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: source.path,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        [
                          source.type.label,
                          if (source.manifestBacked) 'manifest',
                          if (source.suites.isNotEmpty)
                            '$selectedSuites/${source.suites.length} suite',
                          if (runnable.isNotEmpty)
                            '$selectedAutomated/${runnable.length} tự thao tác',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.muted,
                          fontFeatures: QaTokens.tabular,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Thao tác nguồn',
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (value) {
                  switch (value) {
                    case 'scenarios':
                      onOpenScenarios();
                    case 'folder':
                      launchUrl(Uri.file(source.path));
                    case 'remove':
                      _remove(context);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'scenarios',
                    child: ListTile(
                      leading: Icon(Icons.account_tree_outlined),
                      title: Text('Kịch bản & môi trường'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'folder',
                    child: ListTile(
                      leading: Icon(Icons.folder_open_outlined),
                      title: Text('Mở thư mục'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'remove',
                    enabled: !running,
                    child: const ListTile(
                      leading: Icon(Icons.remove_circle_outline),
                      title: Text('Bỏ khỏi QA Desk'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (expanded) ...[
            if (catalog != null && catalog.environments.isNotEmpty)
              _EnvironmentLine(
                controller: controller,
                source: source,
                environments: catalog.environments,
                selected: environment,
                onEnterSecrets: onEnterSecrets,
              ),
            if (catalogError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(44, 4, 4, 4),
                child: NoticeBox(text: catalogError, tone: NoticeTone.warning),
              ),
            for (final suite in suites)
              _SuiteRow(
                controller: controller,
                source: source,
                suite: suite,
                onSelectionChanged: onSelectionChanged,
              ),
            if (automated.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(44, 8, 4, 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 15,
                      color: tokens.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'QA Desk tự thao tác',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: tokens.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              for (final scenario in automated)
                _AutomationRow(
                  controller: controller,
                  source: source,
                  scenario: scenario,
                  onSelectionChanged: onSelectionChanged,
                ),
            ],
          ],
          const SizedBox(height: 4),
          Divider(height: 1, color: tokens.line),
        ],
      ),
    );
  }
}

/// The environment this source's suites run with, chosen in place.
class _EnvironmentLine extends StatelessWidget {
  const _EnvironmentLine({
    required this.controller,
    required this.source,
    required this.environments,
    required this.selected,
    required this.onEnterSecrets,
  });

  final QaWorkspaceController controller;
  final QaSource source;
  final List<EnvironmentProfile> environments;
  final EnvironmentProfile? selected;
  final ValueChanged<EnvironmentProfile> onEnterSecrets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final environment = selected;
    final secretKeys = environment?.secretKeys ?? const <String>[];
    final secretsSet = environment == null
        ? 0
        : secretKeys
              .where(
                (key) => controller.sessionSecretIsSet(
                  source.id,
                  environment.id,
                  key,
                ),
              )
              .length;
    final missing = secretsSet < secretKeys.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(52, 0, 4, 2),
      child: Row(
        children: [
          Icon(Icons.tune, size: 14, color: tokens.muted),
          const SizedBox(width: 6),
          Text(
            'Môi trường',
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: DropdownButton<String>(
              key: Key('qa-env-${source.id}'),
              value: environment?.id,
              isDense: true,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: tokens.text,
              ),
              items: [
                for (final item in environments)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: controller.isRunning
                  ? null
                  : (value) {
                      if (value != null) {
                        controller.selectEnvironment(source.id, value);
                      }
                    },
            ),
          ),
          if (environment != null && secretKeys.isNotEmpty) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: missing
                  ? 'Còn thiếu secret cho phiên này. Bấm để nhập.'
                  : 'Đã nhập đủ secret cho phiên này.',
              child: TextButton.icon(
                key: Key('qa-secrets-${source.id}'),
                style: TextButton.styleFrom(
                  foregroundColor: missing
                      ? tokens.palette.warning
                      : tokens.palette.success,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => onEnterSecrets(environment),
                icon: Icon(
                  missing ? Icons.key_off_outlined : Icons.key_outlined,
                  size: 15,
                ),
                label: Text(
                  '$secretsSet/${secretKeys.length}',
                  style: const TextStyle(fontFeatures: QaTokens.tabular),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SuiteRow extends StatelessWidget {
  const _SuiteRow({
    required this.controller,
    required this.source,
    required this.suite,
    this.onSelectionChanged,
  });

  final QaWorkspaceController controller;
  final QaSource source;
  final QaSuite suite;
  final VoidCallback? onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final selected = controller.isSuiteSelected(source, suite);
    final enabled = !controller.isRunning;
    void toggle() {
      controller.setSuiteSelected(source.id, suite.id, !selected);
      onSelectionChanged?.call();
    }

    return InkWell(
      borderRadius: BorderRadius.circular(QaTokens.radius),
      onTap: enabled ? toggle : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 2, 4, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: Key('qa-suite-${source.id}-${suite.id}'),
              value: selected,
              onChanged: enabled ? (_) => toggle() : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suite.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      suite.description.isEmpty
                          ? suite.commandPreview
                          : suite.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: suite.description.isEmpty
                          ? tokens.mono(size: 11, color: tokens.muted)
                          : theme.textTheme.bodySmall?.copyWith(
                              color: tokens.muted,
                            ),
                    ),
                    if (suite.tags.isNotEmpty ||
                        suite.requiresDevice ||
                        suite.requiresPhysicalDevice ||
                        suite.requiresAppium) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          if (suite.requiresPhysicalDevice)
                            QaTag(
                              label: 'máy thật',
                              icon: Icons.smartphone,
                              color: tokens.palette.warning,
                            )
                          else if (suite.requiresDevice)
                            QaTag(
                              label: 'thiết bị',
                              icon: Icons.phone_android,
                              color: tokens.palette.info,
                            ),
                          if (suite.requiresAppium)
                            QaTag(
                              label: 'Appium',
                              icon: Icons.hub_outlined,
                              color: tokens.palette.info,
                            ),
                          for (final tag in suite.tags) QaTag(label: tag),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A test case QA Desk operates itself: ticked like a suite, run with a demo
/// account of its role.
class _AutomationRow extends StatelessWidget {
  const _AutomationRow({
    required this.controller,
    required this.source,
    required this.scenario,
    this.onSelectionChanged,
  });

  final QaWorkspaceController controller;
  final QaSource source;
  final TestScenario scenario;
  final VoidCallback? onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QaTokens.of(context);
    final spec = scenario.automation!;
    final selected =
        scenario.enabled && controller.isAutomationSelected(source, scenario);
    final enabled = !controller.isRunning && scenario.enabled;
    final appName = source.app(spec.app)?.name ?? spec.app;
    void toggle() {
      controller.setAutomationSelected(source.id, scenario.id, !selected);
      onSelectionChanged?.call();
    }

    return InkWell(
      borderRadius: BorderRadius.circular(QaTokens.radius),
      onTap: enabled ? toggle : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 2, 4, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: Key('qa-automation-${source.id}-${scenario.id}'),
              value: selected,
              onChanged: enabled ? (_) => toggle() : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scenario.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scenario.enabled ? null : tokens.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      scenario.enabled
                          ? '$appName · ${spec.steps.length} bước'
                          : 'Đang tắt trong kịch bản',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        QaTag(
                          label: spec.role,
                          icon: Icons.account_circle_outlined,
                          color: tokens.palette.info,
                        ),
                        if (spec.writes)
                          QaTag(
                            label: 'ghi dữ liệu',
                            icon: Icons.edit_note,
                            color: tokens.palette.warning,
                          ),
                        for (final tag in scenario.tags) QaTag(label: tag),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
