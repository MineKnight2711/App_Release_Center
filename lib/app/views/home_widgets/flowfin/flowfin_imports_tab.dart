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
        title: 'Nhập liệu',
        loading: controller.isLoadingImports.value,
        error: controller.importsError.value,
        actions: [
          if (batch != null)
            OutlinedButton.icon(
              key: const Key('flowfin-import-close'),
              onPressed: () => controller.activeImportBatch.value = null,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Đóng lô'),
            ),
          OutlinedButton.icon(
            key: const Key('flowfin-imports-refresh'),
            onPressed: controller.loadImports,
            icon: const Icon(Icons.refresh_outlined, size: 16),
            label: const Text('Làm mới'),
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
              label: 'Nguồn',
              value: _source,
              width: 170,
              fieldKey: const Key('flowfin-import-source'),
              items: const [
                DropdownMenuItem(value: 'momo', child: Text('MoMo')),
                DropdownMenuItem(value: 'receipt', child: Text('Hoá đơn')),
                DropdownMenuItem(value: 'manual', child: Text('Văn bản thường')),
              ],
              onChanged: (value) => setState(() => _source = value ?? 'momo'),
            ),
            _FlowFinDropdown<String>(
              label: 'Ví mặc định',
              value: _walletId,
              items: [
                const DropdownMenuItem(value: '', child: Text('Không')),
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
            labelText: 'Dán nội dung thông báo hoặc hoá đơn',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const Key('flowfin-import-parse'),
          onPressed: _submitting ? null : _submit,
          icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
          label: const Text('Phân tích'),
        ),
        const SizedBox(height: 20),
        const _PanelTitle(icon: Icons.history_outlined, title: 'Các lô gần đây'),
        const SizedBox(height: 8),
        if (batches.isEmpty)
          const _FlowFinEmpty(
            icon: Icons.history_outlined,
            message: 'Chưa có lô nhập liệu nào.',
          )
        else
          ...batches.map(
            (batch) => _FlowFinRow(
              title: '${batch.source} · ${batch.status}',
              subtitle: [
                '${batch.itemCount} dòng',
                if (batch.createdAt.isNotEmpty) batch.createdAt,
                if (batch.lastError.isNotEmpty) batch.lastError,
              ].join(' · '),
              actions: [
                IconButton(
                  tooltip: 'Mở',
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
      await _flowFinRun(context, () async => 'Mỗi dòng đã chọn đều phải có ví.');
      return;
    }

    setState(() => _confirming = true);
    final ok = await _flowFinRun(
      context,
      () => widget.controller.confirmImport(entries),
      successMessage: 'Đã tạo ${entries.length} giao dịch.',
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
            ? 'Lô đang được phân tích. Làm mới lại sau giây lát.'
            : 'Không đọc được gì từ đoạn văn bản đó.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Đã chọn ${_selected.length}/${items.length} dòng',
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
              label: const Text('Tạo giao dịch'),
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
                          item.merchant.isEmpty ? 'Không rõ' : item.merchant,
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
                        'Có vẻ trùng với một giao dịch đã nhập. Mặc định bỏ '
                        'tick để không bị đếm hai lần.',
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _FlowFinDropdown<String>(
                      label: 'Ví',
                      value: _walletByItem[item.id] ?? '',
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Chọn')),
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
                      label: 'Danh mục',
                      value: _categoryByItem[item.id] ?? '',
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Không')),
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
