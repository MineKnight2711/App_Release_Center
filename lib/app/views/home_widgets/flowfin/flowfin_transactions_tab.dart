part of '../../home_view.dart';

class _FlowFinTransactionsTab extends StatelessWidget {
  const _FlowFinTransactionsTab();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<FlowFinController>();

    return Obx(
      () => _FlowFinTabScaffold(
        icon: Icons.receipt_long_outlined,
        title: 'Transactions',
        loading: controller.isLoadingTransactions.value,
        error: controller.transactionsError.value,
        scrollable: false,
        actions: [
          OutlinedButton.icon(
            key: const Key('flowfin-transactions-refresh'),
            onPressed: controller.loadTransactions,
            icon: const Icon(Icons.refresh_outlined, size: 16),
            label: const Text('Refresh'),
          ),
          FilledButton.icon(
            key: const Key('flowfin-transaction-new'),
            onPressed: () => _showComposer(context),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FlowFinTransactionFilters(),
            const SizedBox(height: 10),
            _FlowFinTransactionTotals(controller: controller),
            const SizedBox(height: 10),
            Expanded(child: _FlowFinTransactionList(controller: controller)),
          ],
        ),
      ),
    );
  }

  static Future<void> _showComposer(
    BuildContext context, {
    FlowFinTransaction? existing,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _FlowFinTransactionComposer(existing: existing),
    );
  }
}

class _FlowFinTransactionTotals extends StatelessWidget {
  const _FlowFinTransactionTotals({required this.controller});

  final FlowFinController controller;

  @override
  Widget build(BuildContext context) {
    final income = controller.transactionTotalIncome.value;
    final expense = controller.transactionTotalExpense.value;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _FlowFinStatTile(
          label: 'Income (filtered)',
          value: FlowFinMoney.format(income),
        ),
        _FlowFinStatTile(
          label: 'Expense (filtered)',
          value: FlowFinMoney.format(expense),
        ),
        _FlowFinStatTile(
          label: 'Net',
          value: FlowFinMoney.format(income - expense, withSign: true),
        ),
      ],
    );
  }
}

class _FlowFinTransactionFilters extends StatefulWidget {
  const _FlowFinTransactionFilters();

  @override
  State<_FlowFinTransactionFilters> createState() =>
      _FlowFinTransactionFiltersState();
}

class _FlowFinTransactionFiltersState
    extends State<_FlowFinTransactionFilters> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  FlowFinController get controller => Get.find<FlowFinController>();

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Typing must not fire a request per keystroke — FlowFin rate limits, and
  /// every call costs the Worker.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      controller.setTransactionFilter(query: value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final wallets = controller.activeWallets;
      final categories = controller.activeCategories;

      return Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              key: const Key('flowfin-transaction-search'),
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search note',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          _FlowFinDropdown<String>(
            label: 'Type',
            value: controller.filterType.value,
            width: 150,
            items: const [
              DropdownMenuItem(value: '', child: Text('All')),
              DropdownMenuItem(value: 'expense', child: Text('Expense')),
              DropdownMenuItem(value: 'income', child: Text('Income')),
              DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
              DropdownMenuItem(value: 'adjustment', child: Text('Adjustment')),
            ],
            onChanged: (value) =>
                controller.setTransactionFilter(type: value ?? ''),
          ),
          _FlowFinDropdown<String>(
            label: 'Wallet',
            value: controller.filterWalletId.value,
            items: [
              const DropdownMenuItem(value: '', child: Text('All')),
              ...wallets.map(
                (wallet) => DropdownMenuItem(
                  value: wallet.id,
                  child: Text(wallet.name, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (value) =>
                controller.setTransactionFilter(walletId: value ?? ''),
          ),
          _FlowFinDropdown<String>(
            label: 'Category',
            value: controller.filterCategoryId.value,
            items: [
              const DropdownMenuItem(value: '', child: Text('All')),
              ...categories.map(
                (category) => DropdownMenuItem(
                  value: category.id,
                  child: Text(category.name, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (value) =>
                controller.setTransactionFilter(categoryId: value ?? ''),
          ),
          TextButton.icon(
            key: const Key('flowfin-filters-clear'),
            onPressed: () {
              _searchController.clear();
              controller.clearTransactionFilters();
            },
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Clear'),
          ),
        ],
      );
    });
  }
}

class _FlowFinTransactionList extends StatelessWidget {
  const _FlowFinTransactionList({required this.controller});

  final FlowFinController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.transactions;
    if (items.isEmpty && !controller.isLoadingTransactions.value) {
      return const _FlowFinEmpty(
        icon: Icons.receipt_long_outlined,
        message: 'No transactions match these filters.',
      );
    }

    return ListView.builder(
      itemCount: items.length + (controller.transactionCursor.value.isEmpty ? 0 : 1),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: OutlinedButton(
                key: const Key('flowfin-transactions-more'),
                onPressed: () => controller.loadTransactions(append: true),
                child: const Text('Load more'),
              ),
            ),
          );
        }
        return _FlowFinTransactionRow(
          transaction: items[index],
          controller: controller,
        );
      },
    );
  }
}

class _FlowFinTransactionRow extends StatelessWidget {
  const _FlowFinTransactionRow({
    required this.transaction,
    required this.controller,
  });

  final FlowFinTransaction transaction;
  final FlowFinController controller;

  @override
  Widget build(BuildContext context) {
    final walletName = controller.walletName(transaction.walletId);
    final categoryName = controller.categoryName(transaction.categoryId);
    final destination = controller.walletName(transaction.toWalletId);

    final subtitle = <String>[
      transaction.localDate,
      if (transaction.isTransfer && destination.isNotEmpty)
        '$walletName → $destination'
      else if (walletName.isNotEmpty)
        walletName,
      if (categoryName.isNotEmpty) categoryName,
      if (transaction.note.isNotEmpty) transaction.note,
    ].join(' · ');

    return _FlowFinRow(
      title: _title,
      subtitle: subtitle,
      leadingColor: _accent,
      trailing: Text(
        FlowFinMoney.format(transaction.amountMinor, withSign: _signed),
        style: AppCyberTheme.dataTextStyle(
          size: 12.5,
          color: _accent,
          weight: FontWeight.w800,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Edit',
          iconSize: 16,
          onPressed: () => _FlowFinTransactionsTab._showComposer(
            context,
            existing: transaction,
          ),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          key: Key('flowfin-transaction-delete-${transaction.id}'),
          tooltip: 'Delete',
          iconSize: 16,
          onPressed: () async {
            final confirmed = await _flowFinConfirm(
              context,
              title: 'Delete transaction?',
              message:
                  '${FlowFinMoney.format(transaction.amountMinor)} on '
                  '${transaction.localDate} will be removed.',
            );
            if (!confirmed || !context.mounted) return;
            await _flowFinRun(
              context,
              () => controller.deleteTransaction(transaction),
              successMessage: 'Transaction deleted.',
            );
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  String get _title {
    return switch (transaction.type) {
      'income' => 'Income',
      'expense' => 'Expense',
      'transfer' => 'Transfer',
      _ => 'Adjustment',
    };
  }

  bool get _signed => transaction.type == 'adjustment';

  Color get _accent {
    return switch (transaction.type) {
      'income' => AppCyberTheme.neonGreen,
      'expense' => Colors.redAccent,
      'transfer' => AppCyberTheme.electricBlue,
      _ => Colors.orangeAccent,
    };
  }
}

/// Create or edit one transaction.
///
/// The form mirrors the rules the API enforces so a request is not spent on a
/// shape that will be rejected: a transfer needs a different destination wallet
/// and carries no category, an adjustment is non-zero and carries no category,
/// and everything else must be positive.
class _FlowFinTransactionComposer extends StatefulWidget {
  const _FlowFinTransactionComposer({this.existing});

  final FlowFinTransaction? existing;

  @override
  State<_FlowFinTransactionComposer> createState() =>
      _FlowFinTransactionComposerState();
}

class _FlowFinTransactionComposerState
    extends State<_FlowFinTransactionComposer> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  late String _type;
  late String _walletId;
  late String _localDate;
  String _toWalletId = '';
  String _categoryId = '';
  bool _saving = false;
  String _error = '';

  FlowFinController get controller => Get.find<FlowFinController>();

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final wallets = controller.activeWallets;

    _type = existing?.type ?? 'expense';
    _walletId = existing?.walletId ?? (wallets.isEmpty ? '' : wallets.first.id);
    _localDate = existing?.localDate ?? FlowFinController.isoDate(DateTime.now());
    _toWalletId = existing?.toWalletId ?? '';
    _categoryId = existing?.categoryId ?? '';
    if (existing != null) {
      _amountController.text = FlowFinMoney.grouped(existing.amountMinor.abs());
      _noteController.text = existing.note;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _isTransfer => _type == 'transfer';
  bool get _isAdjustment => _type == 'adjustment';
  bool get _takesCategory => !_isTransfer && !_isAdjustment;

  List<FlowFinCategory> get _categoryChoices {
    final kind = _type == 'income' ? 'income' : 'expense';
    return controller.activeCategories
        .where((category) => category.kind == kind)
        .toList();
  }

  String? _validate(int? amount) {
    if (_walletId.isEmpty) return 'Pick a wallet.';
    if (amount == null) return 'Amount must be a whole number.';
    if (_isAdjustment && amount == 0) return 'An adjustment cannot be zero.';
    if (!_isAdjustment && amount <= 0) return 'Amount must be greater than zero.';
    if (_isTransfer) {
      if (_toWalletId.isEmpty) return 'A transfer needs a destination wallet.';
      if (_toWalletId == _walletId) {
        return 'The destination wallet must differ from the source.';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final amount = FlowFinMoney.parseInput(_amountController.text);
    final problem = _validate(amount);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = '';
    });

    final error = await controller.saveTransaction(
      existing: widget.existing,
      type: _type,
      amountMinor: amount!,
      walletId: _walletId,
      localDate: _localDate,
      categoryId: _takesCategory ? _categoryId : '',
      toWalletId: _isTransfer ? _toWalletId : '',
      note: _noteController.text,
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
    final wallets = controller.activeWallets;

    return AlertDialog(
      backgroundColor: AppCyberTheme.panelBackgroundStrong,
      surfaceTintColor: Colors.transparent,
      title: _PanelTitle(
        icon: Icons.receipt_long_outlined,
        title: widget.existing == null ? 'New transaction' : 'Edit transaction',
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.existing == null)
                _FlowFinDropdown<String>(
                  label: 'Type',
                  value: _type,
                  fieldKey: const Key('flowfin-composer-type'),
                  width: 460,
                  items: const [
                    DropdownMenuItem(value: 'expense', child: Text('Expense')),
                    DropdownMenuItem(value: 'income', child: Text('Income')),
                    DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                    DropdownMenuItem(
                      value: 'adjustment',
                      child: Text('Adjustment'),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _type = value ?? 'expense';
                    _categoryId = '';
                    _toWalletId = '';
                  }),
                ),
              const SizedBox(height: 12),
              _FlowFinMoneyField(
                controller: _amountController,
                fieldKey: const Key('flowfin-composer-amount'),
                autofocus: true,
                label: _isAdjustment ? 'Adjustment (may be negative)' : 'Amount',
              ),
              const SizedBox(height: 12),
              _FlowFinDropdown<String>(
                label: _isTransfer ? 'From wallet' : 'Wallet',
                value: _walletId,
                width: 460,
                fieldKey: const Key('flowfin-composer-wallet'),
                items: wallets
                    .map(
                      (wallet) => DropdownMenuItem(
                        value: wallet.id,
                        child: Text(wallet.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _walletId = value ?? ''),
              ),
              if (_isTransfer) ...[
                const SizedBox(height: 12),
                _FlowFinDropdown<String>(
                  label: 'To wallet',
                  value: _toWalletId,
                  width: 460,
                  fieldKey: const Key('flowfin-composer-to-wallet'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Pick one')),
                    ...wallets
                        .where((wallet) => wallet.id != _walletId)
                        .map(
                          (wallet) => DropdownMenuItem(
                            value: wallet.id,
                            child: Text(wallet.name),
                          ),
                        ),
                  ],
                  onChanged: (value) =>
                      setState(() => _toWalletId = value ?? ''),
                ),
              ],
              if (_takesCategory) ...[
                const SizedBox(height: 12),
                _FlowFinDropdown<String>(
                  label: 'Category',
                  value: _categoryId,
                  width: 460,
                  fieldKey: const Key('flowfin-composer-category'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('None')),
                    ..._categoryChoices.map(
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
              _FlowFinDateField(
                value: _localDate,
                onChanged: (value) => setState(() => _localDate = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 8),
                _FlowFinErrorNotice(message: _error),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('flowfin-composer-save'),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
