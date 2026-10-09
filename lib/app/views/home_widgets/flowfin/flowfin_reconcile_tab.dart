part of '../../home_view.dart';

/// Check-in: record what a wallet actually holds and see how it compares with
/// the ledger.
///
/// FlowFin's rule shows up here directly — a difference is reported, never
/// turned into a transaction. The user decides whether to enter the missing
/// spend or post an adjustment.
class _FlowFinReconcileTab extends StatelessWidget {
  const _FlowFinReconcileTab();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<FlowFinController>();

    return Obx(() {
      final wallets = controller.activeWallets;
      final byWallet = {
        for (final item in controller.reconciliations) item.walletId: item,
      };

      return _FlowFinTabScaffold(
        icon: Icons.fact_check_outlined,
        title: 'Đối soát',
        loading: controller.isLoadingReconciliation.value,
        error: controller.reconciliationError.value,
        actions: [
          _FlowFinDateField(
            value: controller.reconciliationDate.value,
            onChanged: controller.setReconciliationDate,
            fieldKey: const Key('flowfin-reconcile-date'),
          ),
          OutlinedButton.icon(
            key: const Key('flowfin-reconcile-refresh'),
            onPressed: controller.loadReconciliation,
            icon: const Icon(Icons.refresh_outlined, size: 16),
            label: const Text('Làm mới'),
          ),
        ],
        child: wallets.isEmpty
            ? const _FlowFinEmpty(
                icon: Icons.fact_check_outlined,
                message: 'Thêm ví trước khi đối soát.',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: wallets
                    .map(
                      (wallet) => _FlowFinReconcileRow(
                        wallet: wallet,
                        reconciliation: byWallet[wallet.id],
                        controller: controller,
                      ),
                    )
                    .toList(),
              ),
      );
    });
  }
}

class _FlowFinReconcileRow extends StatelessWidget {
  const _FlowFinReconcileRow({
    required this.wallet,
    required this.reconciliation,
    required this.controller,
  });

  final FlowFinWallet wallet;
  final FlowFinReconciliation? reconciliation;
  final FlowFinController controller;

  @override
  Widget build(BuildContext context) {
    final item = reconciliation;
    final difference = item?.differenceMinor ?? 0;
    final settled = item != null && item.isBalanced;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item == null
              ? AppCyberTheme.lineBlue
              : settled
              ? AppCyberTheme.neonGreen.withValues(alpha: 0.5)
              : Colors.orangeAccent.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  wallet.name,
                  style: AppCyberTheme.dataTextStyle(
                    size: 12.5,
                    color: AppCyberTheme.textPrimary,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.icon(
                key: Key('flowfin-checkin-${wallet.id}'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _FlowFinCheckInDialog(wallet: wallet),
                ),
                icon: const Icon(Icons.edit_note_outlined, size: 16),
                label: const Text('Chốt số dư'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (item == null)
            const _FlowFinNotice(
              icon: Icons.help_outline,
              message: 'Ngày này chưa có lần chốt số dư nào.',
            )
          else ...[
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _pair('Sổ ghi', item.expectedBalanceMinor),
                _pair('Đếm thực tế', item.actualBalanceMinor),
                _pair('Chênh lệch', difference, signed: true),
              ],
            ),
            if (item.estimated) ...[
              const SizedBox(height: 6),
              const _FlowFinNotice(
                icon: Icons.info_outline,
                message:
                    'Số theo sổ chỉ là ước tính — có ngày trước đó chưa chốt '
                    'số dư để làm mốc.',
              ),
            ],
            if (!settled) ...[
              const SizedBox(height: 6),
              _FlowFinNotice(
                icon: Icons.report_problem_outlined,
                message: difference > 0
                    ? 'Ví đang nhiều hơn sổ. Nhập khoản thu còn thiếu, hoặc '
                          'ghi một bút toán điều chỉnh.'
                    : 'Ví đang ít hơn sổ. Nhập khoản chi còn thiếu, hoặc ghi '
                          'một bút toán điều chỉnh.',
              ),
              const SizedBox(height: 6),
              // Nothing is posted automatically — this only opens the composer
              // with the gap filled in, and the user still confirms.
              OutlinedButton.icon(
                key: Key('flowfin-adjust-${wallet.id}'),
                onPressed: () => _FlowFinTransactionsTab._showComposer(context),
                icon: const Icon(Icons.tune_outlined, size: 16),
                label: Text(
                  'Ghi điều chỉnh ${FlowFinMoney.format(difference, withSign: true)}',
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _pair(String label, int amount, {bool signed = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppCyberTheme.dataTextStyle(
            size: 9.5,
            color: AppCyberTheme.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          FlowFinMoney.format(amount, withSign: signed),
          style: AppCyberTheme.dataTextStyle(
            size: 12,
            color: signed && amount != 0
                ? Colors.orangeAccent
                : AppCyberTheme.textPrimary,
            weight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _FlowFinCheckInDialog extends StatefulWidget {
  const _FlowFinCheckInDialog({required this.wallet});

  final FlowFinWallet wallet;

  @override
  State<_FlowFinCheckInDialog> createState() => _FlowFinCheckInDialogState();
}

class _FlowFinCheckInDialogState extends State<_FlowFinCheckInDialog> {
  final _balanceController = TextEditingController();
  final _noteController = TextEditingController();
  bool _saving = false;
  String _error = '';
  FlowFinReconciliation? _result;

  FlowFinController get controller => Get.find<FlowFinController>();

  @override
  void dispose() {
    _balanceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final balance = FlowFinMoney.parseInput(_balanceController.text);
    if (balance == null) {
      setState(() => _error = 'Số dư đếm được phải là số nguyên.');
      return;
    }

    setState(() {
      _saving = true;
      _error = '';
    });

    final outcome = await controller.checkIn(
      walletId: widget.wallet.id,
      balanceMinor: balance,
      note: _noteController.text,
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = outcome.error ?? '';
      _result = outcome.result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return AlertDialog(
      backgroundColor: AppCyberTheme.panelBackgroundStrong,
      surfaceTintColor: Colors.transparent,
      title: _PanelTitle(
        icon: Icons.fact_check_outlined,
        title: 'Chốt số dư · ${widget.wallet.name}',
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ngày ${controller.reconciliationDate.value}',
              style: AppCyberTheme.dataTextStyle(
                size: 11,
                color: AppCyberTheme.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            _FlowFinMoneyField(
              controller: _balanceController,
              label: 'Số dư đếm được',
              autofocus: true,
              fieldKey: const Key('flowfin-checkin-balance'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Ghi chú'),
            ),
            if (result != null) ...[
              const SizedBox(height: 8),
              _FlowFinNotice(
                icon: result.isBalanced
                    ? Icons.check_circle_outline
                    : Icons.report_problem_outlined,
                message: result.isBalanced
                    ? 'Khớp chính xác với sổ.'
                    : 'Đã ghi nhận chênh lệch '
                          '${FlowFinMoney.format(result.differenceMinor, withSign: true)}. '
                          'Chưa ghi bút toán nào — bạn quyết định nhập gì.',
              ),
            ],
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
          child: Text(result == null ? 'Huỷ' : 'Đóng'),
        ),
        FilledButton(
          key: const Key('flowfin-checkin-save'),
          onPressed: _saving ? null : _submit,
          child: const Text('Ghi nhận'),
        ),
      ],
    );
  }
}
