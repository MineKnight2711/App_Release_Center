part of '../../home_view.dart';

const _flowFinWalletTypes = <String, String>{
  'cash': 'Cash',
  'bank': 'Bank',
  'ewallet': 'E-wallet',
  'credit': 'Credit',
  'savings': 'Savings',
  'other': 'Other',
};

class _FlowFinAccountsTab extends StatelessWidget {
  const _FlowFinAccountsTab();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<FlowFinController>();

    return Obx(
      () => _FlowFinTabScaffold(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Wallets & categories',
        loading: controller.isLoadingDashboard.value,
        actions: [
          OutlinedButton.icon(
            key: const Key('flowfin-wallet-new'),
            onPressed: () => _showWalletForm(context),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Wallet'),
          ),
          OutlinedButton.icon(
            key: const Key('flowfin-category-new'),
            onPressed: () => _showCategoryForm(context),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Category'),
          ),
        ],
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 820;
            final wallets = _FlowFinWalletManager(controller: controller);
            final categories = _FlowFinCategoryList(controller: controller);

            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [wallets, const SizedBox(height: 18), categories],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: wallets),
                const SizedBox(width: 18),
                Expanded(child: categories),
              ],
            );
          },
        ),
      ),
    );
  }

  static Future<void> _showWalletForm(
    BuildContext context, {
    FlowFinWallet? existing,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _FlowFinWalletForm(existing: existing),
    );
  }

  static Future<void> _showCategoryForm(
    BuildContext context, {
    FlowFinCategory? existing,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _FlowFinCategoryForm(existing: existing),
    );
  }
}

class _FlowFinWalletManager extends StatelessWidget {
  const _FlowFinWalletManager({required this.controller});

  final FlowFinController controller;

  @override
  Widget build(BuildContext context) {
    final wallets = [...controller.wallets]
      ..sort((a, b) {
        if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
        return a.sortOrder.compareTo(b.sortOrder);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PanelTitle(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Wallets',
        ),
        const SizedBox(height: 8),
        if (wallets.isEmpty)
          const _FlowFinEmpty(
            icon: Icons.account_balance_wallet_outlined,
            message: 'No wallets yet.',
          )
        else
          ...wallets.map(
            (wallet) => _FlowFinRow(
              title: wallet.name,
              dimmed: wallet.isArchived,
              leadingColor: _flowFinParseColor(
                wallet.color,
                AppCyberTheme.electricBlue,
              ),
              subtitle: [
                _flowFinWalletTypes[wallet.type] ?? wallet.type,
                if (!wallet.includeInTotal) 'excluded from total',
                if (wallet.isArchived) 'archived',
              ].join(' · '),
              trailing: Text(
                FlowFinMoney.format(controller.balanceMinorFor(wallet.id)),
                style: AppCyberTheme.dataTextStyle(
                  size: 12.5,
                  color: AppCyberTheme.textPrimary,
                  weight: FontWeight.w800,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Edit',
                  iconSize: 16,
                  onPressed: () => _FlowFinAccountsTab._showWalletForm(
                    context,
                    existing: wallet,
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: wallet.isArchived ? 'Restore' : 'Archive',
                  iconSize: 16,
                  onPressed: () => _flowFinRun(
                    context,
                    () => controller.setWalletArchived(
                      wallet,
                      !wallet.isArchived,
                    ),
                  ),
                  icon: Icon(
                    wallet.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                ),
                IconButton(
                  key: Key('flowfin-wallet-delete-${wallet.id}'),
                  tooltip: 'Delete',
                  iconSize: 16,
                  onPressed: () async {
                    final confirmed = await _flowFinConfirm(
                      context,
                      title: 'Delete ${wallet.name}?',
                      message:
                          'Transactions in this wallet stay, but the wallet '
                          'disappears from every view.',
                    );
                    if (!confirmed || !context.mounted) return;
                    await _flowFinRun(
                      context,
                      () => controller.deleteWallet(wallet),
                      successMessage: 'Wallet deleted.',
                    );
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FlowFinCategoryList extends StatelessWidget {
  const _FlowFinCategoryList({required this.controller});

  final FlowFinController controller;

  @override
  Widget build(BuildContext context) {
    final categories = [...controller.categories]
      ..sort((a, b) {
        if (a.kind != b.kind) return a.kind == 'income' ? -1 : 1;
        if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
        return a.sortOrder.compareTo(b.sortOrder);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PanelTitle(icon: Icons.label_outline, title: 'Categories'),
        const SizedBox(height: 8),
        if (categories.isEmpty)
          const _FlowFinEmpty(
            icon: Icons.label_outline,
            message: 'No categories yet.',
          )
        else
          ...categories.map(
            (category) => _FlowFinRow(
              title: category.name,
              dimmed: category.isArchived,
              leadingColor: _flowFinParseColor(
                category.color,
                category.kind == 'income'
                    ? AppCyberTheme.neonGreen
                    : Colors.redAccent,
              ),
              subtitle: [
                category.kind == 'income' ? 'Income' : 'Expense',
                if (category.isDefault) 'default',
                if (category.isArchived) 'archived',
              ].join(' · '),
              actions: [
                IconButton(
                  tooltip: 'Edit',
                  iconSize: 16,
                  onPressed: () => _FlowFinAccountsTab._showCategoryForm(
                    context,
                    existing: category,
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: category.isArchived ? 'Restore' : 'Archive',
                  iconSize: 16,
                  onPressed: () => _flowFinRun(
                    context,
                    () => controller.setCategoryArchived(
                      category,
                      !category.isArchived,
                    ),
                  ),
                  icon: Icon(
                    category.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                ),
                IconButton(
                  key: Key('flowfin-category-delete-${category.id}'),
                  tooltip: 'Delete',
                  iconSize: 16,
                  onPressed: () async {
                    final confirmed = await _flowFinConfirm(
                      context,
                      title: 'Delete ${category.name}?',
                      message:
                          'Transactions keep their amounts but lose this '
                          'category label.',
                    );
                    if (!confirmed || !context.mounted) return;
                    await _flowFinRun(
                      context,
                      () => controller.deleteCategory(category),
                      successMessage: 'Category deleted.',
                    );
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FlowFinWalletForm extends StatefulWidget {
  const _FlowFinWalletForm({this.existing});

  final FlowFinWallet? existing;

  @override
  State<_FlowFinWalletForm> createState() => _FlowFinWalletFormState();
}

class _FlowFinWalletFormState extends State<_FlowFinWalletForm> {
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();

  late String _type;
  late String _openedOn;
  late bool _includeInTotal;
  bool _saving = false;
  String _error = '';

  FlowFinController get controller => Get.find<FlowFinController>();

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? 'cash';
    _openedOn = FlowFinController.isoDate(DateTime.now());
    _includeInTotal = existing?.includeInTotal ?? true;
    if (existing != null) {
      _nameController.text = existing.name;
      _balanceController.text = FlowFinMoney.grouped(
        existing.initialBalanceMinor,
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the wallet a name.');
      return;
    }
    final balance = FlowFinMoney.parseInput(_balanceController.text) ?? 0;

    setState(() {
      _saving = true;
      _error = '';
    });

    final error = await controller.saveWallet(
      existing: widget.existing,
      name: name,
      type: _type,
      initialBalanceMinor: balance,
      openedOn: _openedOn,
      includeInTotal: _includeInTotal,
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

    return AlertDialog(
      backgroundColor: AppCyberTheme.panelBackgroundStrong,
      surfaceTintColor: Colors.transparent,
      title: _PanelTitle(
        icon: Icons.account_balance_wallet_outlined,
        title: isNew ? 'New wallet' : 'Edit wallet',
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('flowfin-wallet-name'),
              controller: _nameController,
              autofocus: true,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            _FlowFinDropdown<String>(
              label: 'Type',
              value: _type,
              width: 420,
              items: _flowFinWalletTypes.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _type = value ?? 'cash'),
            ),
            if (isNew) ...[
              const SizedBox(height: 12),
              _FlowFinMoneyField(
                controller: _balanceController,
                label: 'Opening balance',
                fieldKey: const Key('flowfin-wallet-balance'),
              ),
              const SizedBox(height: 12),
              _FlowFinDateField(
                label: 'Opened on',
                value: _openedOn,
                onChanged: (value) => setState(() => _openedOn = value),
              ),
            ],
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _includeInTotal,
              title: const Text('Count in the total balance'),
              onChanged: (value) => setState(() => _includeInTotal = value),
            ),
            if (_error.isNotEmpty) _FlowFinErrorNotice(message: _error),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('flowfin-wallet-save'),
          onPressed: _saving ? null : _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _FlowFinCategoryForm extends StatefulWidget {
  const _FlowFinCategoryForm({this.existing});

  final FlowFinCategory? existing;

  @override
  State<_FlowFinCategoryForm> createState() => _FlowFinCategoryFormState();
}

class _FlowFinCategoryFormState extends State<_FlowFinCategoryForm> {
  final _nameController = TextEditingController();
  late String _kind;
  bool _saving = false;
  String _error = '';

  FlowFinController get controller => Get.find<FlowFinController>();

  @override
  void initState() {
    super.initState();
    _kind = widget.existing?.kind ?? 'expense';
    _nameController.text = widget.existing?.name ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the category a name.');
      return;
    }

    setState(() {
      _saving = true;
      _error = '';
    });

    final error = await controller.saveCategory(
      existing: widget.existing,
      name: name,
      kind: _kind,
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

    return AlertDialog(
      backgroundColor: AppCyberTheme.panelBackgroundStrong,
      surfaceTintColor: Colors.transparent,
      title: _PanelTitle(
        icon: Icons.label_outline,
        title: isNew ? 'New category' : 'Edit category',
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('flowfin-category-name'),
              controller: _nameController,
              autofocus: true,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            if (isNew)
              // The kind is fixed once created: moving a category between
              // income and expense would reinterpret every transaction on it.
              _FlowFinDropdown<String>(
                label: 'Kind',
                value: _kind,
                width: 380,
                items: const [
                  DropdownMenuItem(value: 'expense', child: Text('Expense')),
                  DropdownMenuItem(value: 'income', child: Text('Income')),
                ],
                onChanged: (value) => setState(() => _kind = value ?? 'expense'),
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
          key: const Key('flowfin-category-save'),
          onPressed: _saving ? null : _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
