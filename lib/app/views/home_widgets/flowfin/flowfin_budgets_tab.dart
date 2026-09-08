part of '../../home_view.dart';

class _FlowFinBudgetsTab extends StatelessWidget {
  const _FlowFinBudgetsTab();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<FlowFinController>();

    return Obx(() {
      final budgets = controller.budgets;
      final spentByCategory = _spentByCategory(controller);
      final totalSpent = controller.overview.value?.expenseMinor ?? 0;

      return _FlowFinTabScaffold(
        icon: Icons.pie_chart_outline,
        title: 'Budgets · ${FlowFinController.currentPeriodKey()}',
        loading: controller.isLoadingBudgets.value,
        error: controller.budgetsError.value,
        actions: [
          OutlinedButton.icon(
            key: const Key('flowfin-budgets-refresh'),
            onPressed: controller.loadBudgets,
            icon: const Icon(Icons.refresh_outlined, size: 16),
            label: const Text('Refresh'),
          ),
          FilledButton.icon(
            key: const Key('flowfin-budget-new'),
            onPressed: () => _showForm(context),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New'),
          ),
        ],
        child: budgets.isEmpty
            ? const _FlowFinEmpty(
                icon: Icons.pie_chart_outline,
                message: 'No budget set for this period.',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: budgets
                    .map(
                      (budget) => _FlowFinBudgetRow(
                        budget: budget,
                        controller: controller,
                        spentMinor: budget.scope == 'total'
                            ? totalSpent
                            : (spentByCategory[budget.categoryId] ?? 0),
                      ),
                    )
                    .toList(),
              ),
      );
    });
  }

  /// Spend per category for the current period, taken from the breakdown when
  /// the Statistics tab has already loaded it. Absent data shows as no bar
  /// rather than a wrong one.
  static Map<String, int> _spentByCategory(FlowFinController controller) {
    final breakdown = controller.breakdown.value;
    if (breakdown == null || breakdown.kind != 'expense') return const {};
    return {
      for (final item in breakdown.items) item.id: item.amountMinor,
    };
  }

  static Future<void> _showForm(
    BuildContext context, {
    FlowFinBudget? existing,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _FlowFinBudgetForm(existing: existing),
    );
  }
}

class _FlowFinBudgetRow extends StatelessWidget {
  const _FlowFinBudgetRow({
    required this.budget,
    required this.controller,
    required this.spentMinor,
  });

  final FlowFinBudget budget;
  final FlowFinController controller;
  final int spentMinor;

  @override
  Widget build(BuildContext context) {
    final name = budget.scope == 'total'
        ? 'Total spending'
        : controller.categoryName(budget.categoryId);
    final ratio = budget.limitMinor <= 0
        ? 0.0
        : (spentMinor / budget.limitMinor).clamp(0.0, 1.0).toDouble();
    final over = budget.limitMinor > 0 && spentMinor > budget.limitMinor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: over ? Colors.redAccent.withValues(alpha: 0.6) : AppCyberTheme.lineBlue,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name.isEmpty ? 'Category budget' : name,
                  style: AppCyberTheme.dataTextStyle(
                    size: 12.5,
                    color: AppCyberTheme.textPrimary,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${FlowFinMoney.format(spentMinor)} / ${FlowFinMoney.format(budget.limitMinor)}',
                style: AppCyberTheme.dataTextStyle(
                  size: 11.5,
                  color: over ? Colors.redAccent : AppCyberTheme.textMuted,
                  weight: FontWeight.w700,
                ),
              ),
              IconButton(
                tooltip: 'Edit',
                iconSize: 16,
                onPressed: () =>
                    _FlowFinBudgetsTab._showForm(context, existing: budget),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: Key('flowfin-budget-delete-${budget.id}'),
                tooltip: 'Delete',
                iconSize: 16,
                onPressed: () async {
                  final confirmed = await _flowFinConfirm(
                    context,
                    title: 'Delete budget?',
                    message: 'The limit for $name will be removed.',
                  );
                  if (!confirmed || !context.mounted) return;
                  await _flowFinRun(
                    context,
                    () => controller.deleteBudget(budget),
                    successMessage: 'Budget deleted.',
                  );
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppCyberTheme.lineBlue.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation(
                over ? Colors.redAccent : AppCyberTheme.electricBlue,
              ),
            ),
          ),
          if (spentMinor == 0 && budget.scope == 'category') ...[
            const SizedBox(height: 6),
            const _FlowFinNotice(
              icon: Icons.info_outline,
              message: 'Open Statistics to load spending per category.',
            ),
          ],
        ],
      ),
    );
  }
}

class _FlowFinBudgetForm extends StatefulWidget {
  const _FlowFinBudgetForm({this.existing});

  final FlowFinBudget? existing;

  @override
  State<_FlowFinBudgetForm> createState() => _FlowFinBudgetFormState();
}

class _FlowFinBudgetFormState extends State<_FlowFinBudgetForm> {
  final _limitController = TextEditingController();
  late String _scope;
  String _categoryId = '';
  bool _saving = false;
  String _error = '';

  FlowFinController get controller => Get.find<FlowFinController>();

  @override
  void initState() {
    super.initState();
    _scope = widget.existing?.scope ?? 'total';
    _categoryId = widget.existing?.categoryId ?? '';
    if (widget.existing != null) {
      _limitController.text = FlowFinMoney.grouped(widget.existing!.limitMinor);
    }
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final limit = FlowFinMoney.parseInput(_limitController.text);
    if (limit == null || limit <= 0) {
      setState(() => _error = 'The limit must be greater than zero.');
      return;
    }
    if (_scope == 'category' && _categoryId.isEmpty) {
      setState(() => _error = 'Pick a category for a category budget.');
      return;
    }

    setState(() {
      _saving = true;
      _error = '';
    });

    final error = await controller.saveBudget(
      existing: widget.existing,
      scope: _scope,
      limitMinor: limit,
      categoryId: _scope == 'category' ? _categoryId : null,
    );

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    final expenseCategories = controller.activeCategories
        .where((category) => category.kind == 'expense')
        .toList();

    return AlertDialog(
      backgroundColor: AppCyberTheme.panelBackgroundStrong,
      surfaceTintColor: Colors.transparent,
      title: _PanelTitle(
        icon: Icons.pie_chart_outline,
        title: isNew ? 'New budget' : 'Edit budget',
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNew) ...[
              _FlowFinDropdown<String>(
                label: 'Scope',
                value: _scope,
                width: 400,
                items: const [
                  DropdownMenuItem(value: 'total', child: Text('Total')),
                  DropdownMenuItem(
                    value: 'category',
                    child: Text('One category'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _scope = value ?? 'total';
                  _categoryId = '';
                }),
              ),
              if (_scope == 'category') ...[
                const SizedBox(height: 12),
                _FlowFinDropdown<String>(
                  label: 'Category',
                  value: _categoryId,
                  width: 400,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Pick one')),
                    ...expenseCategories.map(
                      (category) => DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _categoryId = value ?? ''),
                ),
              ],
              const SizedBox(height: 12),
            ],
            _FlowFinMoneyField(
              controller: _limitController,
              label: 'Monthly limit',
              autofocus: true,
              fieldKey: const Key('flowfin-budget-limit'),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 8),
              _FlowFinErrorNotice(message: _error),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('flowfin-budget-save'),
          onPressed: _saving ? null : _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
