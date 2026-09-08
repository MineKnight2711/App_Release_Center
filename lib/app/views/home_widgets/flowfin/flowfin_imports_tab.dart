part of '../../home_view.dart';

/// Bulk entry from pasted text.
///
/// The phone app feeds this from the camera; a desktop has no camera pipeline,
/// so text is pasted here instead — a MoMo notification, a bank SMS, a receipt
/// someone typed out. The API takes raw text either way.
class _FlowFinImportsTab extends StatelessWidget {
  const _FlowFinImportsTab();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<FlowFinController>();

    return Obx(() {
      final batch = controller.activeImportBatch.value;

      return _FlowFinTabScaffold(
        icon: Icons.file_download_outlined,
        title: 'Imports',
        loading: controller.isLoadingImports.value,
        error: controller.importsError.value,
        actions: [
          if (batch != null)
            OutlinedButton.icon(
              key: const Key('flowfin-import-close'),
              onPressed: () => controller.activeImportBatch.value = null,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Close batch'),
            ),
          OutlinedButton.icon(
            key: const Key('flowfin-imports-refresh'),
            onPressed: controller.loadImports,
            icon: const Icon(Icons.refresh_outlined, size: 16),
            label: const Text('Refresh'),
          ),
        ],
        child: batch == null
            ? _FlowFinImportStart(controller: controller)
            : _FlowFinImportReview(batch: batch, controller: controller),
      );
    });
  }
}

class _FlowFinImportStart extends StatefulWidget {
  const _FlowFinImportStart({required this.controller});

  final FlowFinController controller;

  @override
  State<_FlowFinImportStart> createState() => _FlowFinImportStartState();
}

class _FlowFinImportStartState extends State<_FlowFinImportStart> {
  final _textController = TextEditingController();
  String _source = 'momo';
  String _walletId = '';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final wallets = widget.controller.activeWallets;
    if (wallets.isNotEmpty) _walletId = wallets.first.id;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() => _submitting = true);
    final error = await widget.controller.createImport(
      source: _source,
      text: text,
      defaultWalletId: _walletId.isEmpty ? null : _walletId,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (error == null) _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final wallets = widget.controller.activeWallets;
    final batches = widget.controller.importBatches;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _FlowFinDropdown<String>(
              label: 'Source',
              value: _source,
              width: 170,
              fieldKey: const Key('flowfin-import-source'),
              items: const [
                DropdownMenuItem(value: 'momo', child: Text('MoMo')),
                DropdownMenuItem(value: 'receipt', child: Text('Receipt')),
                DropdownMenuItem(value: 'manual', child: Text('Plain text')),
              ],
              onChanged: (value) => setState(() => _source = value ?? 'momo'),
            ),
            _FlowFinDropdown<String>(
              label: 'Default wallet',
              value: _walletId,
              items: [
                const DropdownMenuItem(value: '', child: Text('None')),
                ...wallets.map(
                  (wallet) => DropdownMenuItem(
                    value: wallet.id,
                    child: Text(wallet.name),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _walletId = value ?? ''),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('flowfin-import-text'),
          controller: _textController,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Paste the notification or receipt text',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const Key('flowfin-import-parse'),
          onPressed: _submitting ? null : _submit,
          icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
          label: const Text('Parse'),
        ),
        const SizedBox(height: 20),
        const _PanelTitle(icon: Icons.history_outlined, title: 'Recent batches'),
        const SizedBox(height: 8),
        if (batches.isEmpty)
          const _FlowFinEmpty(
            icon: Icons.history_outlined,
            message: 'No import batches yet.',
          )
        else
          ...batches.map(
            (batch) => _FlowFinRow(
              title: '${batch.source} · ${batch.status}',
              subtitle: [
                '${batch.itemCount} item(s)',
                if (batch.createdAt.isNotEmpty) batch.createdAt,
                if (batch.lastError.isNotEmpty) batch.lastError,
              ].join(' · '),
              actions: [
                IconButton(
                  tooltip: 'Open',
                  iconSize: 16,
                  onPressed: () => _flowFinRun(
                    context,
                    () => widget.controller.openImport(batch.id),
                  ),
                  icon: const Icon(Icons.open_in_new_outlined),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FlowFinImportReview extends StatefulWidget {
  const _FlowFinImportReview({required this.batch, required this.controller});

  final FlowFinImportBatch batch;
  final FlowFinController controller;

  @override
  State<_FlowFinImportReview> createState() => _FlowFinImportReviewState();
}

class _FlowFinImportReviewState extends State<_FlowFinImportReview> {
  final _selected = <String>{};
  final _walletByItem = <String, String>{};
  final _categoryByItem = <String, String>{};
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    final wallets = widget.controller.activeWallets;
    final fallbackWallet = wallets.isEmpty ? '' : wallets.first.id;
    for (final item in widget.batch.items) {
      // Duplicates start unticked: the parser flagged them as already entered,
      // so importing again would double-count.
      if (!item.isDuplicate) _selected.add(item.id);
      _walletByItem[item.id] = item.suggestedWalletId ?? fallbackWallet;
      _categoryByItem[item.id] = item.suggestedCategoryId ?? '';
    }
  }

  Future<void> _confirm() async {
    final entries = widget.batch.items
        .where((item) => _selected.contains(item.id))
        .map(
          (item) => FlowFinImportConfirmEntry(
            itemId: item.id,
            transactionId: widget.controller.client.newId(),
            walletId: _walletByItem[item.id] ?? '',
            categoryId: _categoryByItem[item.id],
          ),
        )
        .toList();

    if (entries.isEmpty) return;
    if (entries.any((entry) => entry.walletId.isEmpty)) {
      await _flowFinRun(context, () async => 'Every selected row needs a wallet.');
      return;
    }

    setState(() => _confirming = true);
    final ok = await _flowFinRun(
      context,
      () => widget.controller.confirmImport(entries),
      successMessage: '${entries.length} transaction(s) created.',
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (!ok) return;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.batch.items;
    final wallets = widget.controller.activeWallets;
    final categories = widget.controller.activeCategories;

    if (items.isEmpty) {
      return _FlowFinEmpty(
        icon: Icons.hourglass_empty_outlined,
        message: widget.batch.status == 'pending'
            ? 'The batch is still being parsed. Refresh in a moment.'
            : 'Nothing could be read from that text.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${_selected.length} of ${items.length} selected',
              style: AppCyberTheme.dataTextStyle(
                size: 11.5,
                color: AppCyberTheme.textMuted,
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              key: const Key('flowfin-import-confirm'),
              onPressed: _confirming || _selected.isEmpty ? null : _confirm,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Create transactions'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...items.map((item) {
          final selected = _selected.contains(item.id);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: item.isDuplicate
                    ? Colors.orangeAccent.withValues(alpha: 0.55)
                    : AppCyberTheme.lineBlue,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Checkbox(
                      key: Key('flowfin-import-item-${item.id}'),
                      value: selected,
                      onChanged: (value) => setState(() {
                        if (value ?? false) {
                          _selected.add(item.id);
                        } else {
                          _selected.remove(item.id);
                        }
                      }),
                    ),
                    Expanded(
                      child: Text(
                        [
                          item.merchant.isEmpty ? 'Unnamed' : item.merchant,
                          item.localDate,
                          if (item.direction.isNotEmpty) item.direction,
                        ].join(' · '),
                        overflow: TextOverflow.ellipsis,
                        style: AppCyberTheme.dataTextStyle(
                          size: 12,
                          color: AppCyberTheme.textPrimary,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      FlowFinMoney.format(item.amountMinor),
                      style: AppCyberTheme.dataTextStyle(
                        size: 12.5,
                        color: AppCyberTheme.textPrimary,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (item.isDuplicate)
                  const _FlowFinNotice(
                    icon: Icons.copy_all_outlined,
                    message:
                        'Looks like a transaction already entered. Unticked by '
                        'default so it is not counted twice.',
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _FlowFinDropdown<String>(
                      label: 'Wallet',
                      value: _walletByItem[item.id] ?? '',
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Pick')),
                        ...wallets.map(
                          (wallet) => DropdownMenuItem(
                            value: wallet.id,
                            child: Text(wallet.name),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(
                        () => _walletByItem[item.id] = value ?? '',
                      ),
                    ),
                    _FlowFinDropdown<String>(
                      label: 'Category',
                      value: _categoryByItem[item.id] ?? '',
                      items: [
                        const DropdownMenuItem(value: '', child: Text('None')),
                        ...categories.map(
                          (category) => DropdownMenuItem(
                            value: category.id,
                            child: Text(category.name),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(
                        () => _categoryByItem[item.id] = value ?? '',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
