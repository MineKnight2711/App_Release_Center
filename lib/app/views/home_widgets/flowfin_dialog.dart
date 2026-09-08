part of '../home_view.dart';

bool _flowFinDialogVisible = false;

Future<void> showFlowFinDialog(BuildContext context) async {
  if (_flowFinDialogVisible) return;
  _flowFinDialogVisible = true;
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'FlowFin',
      barrierColor: Colors.black.withValues(alpha: 0.66),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => const _FlowFinDialog(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final reduceMotion =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  } finally {
    _flowFinDialogVisible = false;
  }
}

class _FlowFinButton extends StatelessWidget {
  const _FlowFinButton({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Tooltip(
        message: 'Open FlowFin',
        child: OutlinedButton(
          key: const Key('open-flowfin'),
          onPressed: () => showFlowFinDialog(context),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(36, 36),
          ),
          child: const Icon(Icons.savings_outlined, size: 18),
        ),
      );
    }

    return OutlinedButton.icon(
      key: const Key('open-flowfin'),
      onPressed: () => showFlowFinDialog(context),
      icon: const Icon(Icons.savings_outlined, size: 18),
      label: const Text('FlowFin'),
    );
  }
}

class _FlowFinDialog extends StatefulWidget {
  const _FlowFinDialog();

  @override
  State<_FlowFinDialog> createState() => _FlowFinDialogState();
}

class _FlowFinDialogState extends State<_FlowFinDialog> {
  FlowFinController get controller => Get.find<FlowFinController>();

  @override
  void dispose() {
    // Cleared here as well as in showFlowFinDialog's finally: if the tree is
    // torn down without the route completing, the guard would otherwise stay
    // latched and refuse to open the dialog again.
    _flowFinDialogVisible = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = (media.size.width * 0.94).clamp(360.0, 1280.0).toDouble();
    final height = (media.size.height * 0.9).clamp(420.0, 900.0).toDouble();

    return Center(
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: width,
          height: height,
          child: _Panel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FlowFinHeader(),
                const SizedBox(height: 12),
                Expanded(
                  child: Obx(() {
                    if (!controller.isSignedIn) return const _FlowFinSignIn();
                    return const _FlowFinWorkspace();
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _FlowFinTab {
  overview,
  transactions,
  accounts,
  budgets,
  statistics,
  reconcile,
  imports,
  settings,
}

extension _FlowFinTabMeta on _FlowFinTab {
  IconData get icon {
    return switch (this) {
      _FlowFinTab.overview => Icons.dashboard_outlined,
      _FlowFinTab.transactions => Icons.receipt_long_outlined,
      _FlowFinTab.accounts => Icons.account_balance_wallet_outlined,
      _FlowFinTab.budgets => Icons.pie_chart_outline,
      _FlowFinTab.statistics => Icons.insights_outlined,
      _FlowFinTab.reconcile => Icons.fact_check_outlined,
      _FlowFinTab.imports => Icons.file_download_outlined,
      _FlowFinTab.settings => Icons.tune_outlined,
    };
  }

  String get label {
    return switch (this) {
      _FlowFinTab.overview => 'Overview',
      _FlowFinTab.transactions => 'Transactions',
      _FlowFinTab.accounts => 'Accounts',
      _FlowFinTab.budgets => 'Budgets',
      _FlowFinTab.statistics => 'Statistics',
      _FlowFinTab.reconcile => 'Reconcile',
      _FlowFinTab.imports => 'Imports',
      _FlowFinTab.settings => 'Settings',
    };
  }
}

class _FlowFinWorkspace extends StatefulWidget {
  const _FlowFinWorkspace();

  @override
  State<_FlowFinWorkspace> createState() => _FlowFinWorkspaceState();
}

class _FlowFinWorkspaceState extends State<_FlowFinWorkspace>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Each tab loads on first visit rather than up front, so opening the dialog
  /// costs one bootstrap call instead of eight.
  final _loaded = <_FlowFinTab>{_FlowFinTab.overview};

  FlowFinController get controller => Get.find<FlowFinController>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _FlowFinTab.values.length,
      vsync: this,
    )..addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _ensureLoaded(_FlowFinTab.values[_tabController.index]);
  }

  void _ensureLoaded(_FlowFinTab tab) {
    if (!_loaded.add(tab)) return;
    switch (tab) {
      case _FlowFinTab.transactions:
        unawaited(controller.loadTransactions());
      case _FlowFinTab.budgets:
        unawaited(controller.loadBudgets());
      case _FlowFinTab.statistics:
        unawaited(controller.loadStats());
      case _FlowFinTab.reconcile:
        unawaited(controller.loadReconciliation());
      case _FlowFinTab.imports:
        unawaited(controller.loadImports());
      case _FlowFinTab.settings:
        unawaited(controller.loadAccount());
      case _FlowFinTab.overview:
      case _FlowFinTab.accounts:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _FlowFinTab.values
              .map(
                (tab) => Tab(
                  key: Key('flowfin-tab-${tab.name}'),
                  icon: Icon(tab.icon, size: 18),
                  text: tab.label,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _FlowFinOverview(),
              _FlowFinTransactionsTab(),
              _FlowFinAccountsTab(),
              _FlowFinBudgetsTab(),
              _FlowFinStatisticsTab(),
              _FlowFinReconcileTab(),
              _FlowFinImportsTab(),
              _FlowFinSettingsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _FlowFinHeader extends StatelessWidget {
  const _FlowFinHeader();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<FlowFinController>();

    return Row(
      children: [
        const _PanelTitle(icon: Icons.savings_outlined, title: 'FlowFin'),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Obx(
                  () => _FlowFinEnvironmentSelector(
                    value: controller.environment,
                    onChanged: controller.setEnvironment,
                  ),
                ),
                Obx(() {
                  final status = controller.healthStatus.value;
                  if (status.isEmpty) {
                    return OutlinedButton.icon(
                      key: const Key('flowfin-health'),
                      onPressed: controller.checkHealth,
                      icon: const Icon(Icons.favorite_border, size: 16),
                      label: const Text('Health'),
                    );
                  }
                  return _MetaChip(
                    icon: status.startsWith('OK')
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    label: status,
                  );
                }),
                Obx(
                  () => controller.isSignedIn
                      ? OutlinedButton.icon(
                          key: const Key('flowfin-sign-out'),
                          onPressed: controller.signOut,
                          icon: const Icon(Icons.logout_outlined, size: 16),
                          label: const Text('Sign out'),
                        )
                      : const SizedBox.shrink(),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FlowFinEnvironmentSelector extends StatelessWidget {
  const _FlowFinEnvironmentSelector({
    required this.value,
    required this.onChanged,
  });

  final FlowFinEnvironment value;
  final ValueChanged<FlowFinEnvironment> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: value.isProduction
              ? Colors.orangeAccent.withValues(alpha: 0.7)
              : AppCyberTheme.lineBlue,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<FlowFinEnvironment>(
          key: const Key('flowfin-environment'),
          value: value,
          isDense: true,
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
          items: FlowFinEnvironment.values
              .map(
                (environment) => DropdownMenuItem(
                  value: environment,
                  child: Text(environment.label),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _FlowFinSignIn extends StatefulWidget {
  const _FlowFinSignIn();

  @override
  State<_FlowFinSignIn> createState() => _FlowFinSignInState();
}

class _FlowFinSignInState extends State<_FlowFinSignIn> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  FlowFinController get controller => Get.find<FlowFinController>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await controller.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );
    if (controller.isSignedIn) _passwordController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Sign in to FlowFin',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Obx(
                () => Text(
                  controller.baseUrl,
                  style: AppCyberTheme.dataTextStyle(
                    size: 11,
                    color: AppCyberTheme.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('flowfin-email'),
                controller: _emailController,
                autofillHints: const [AutofillHints.email],
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('flowfin-password'),
                controller: _passwordController,
                obscureText: _obscurePassword,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline, size: 18),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? 'Show' : 'Hide',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Obx(
                () => FilledButton.icon(
                  key: const Key('flowfin-sign-in'),
                  onPressed: controller.isSigningIn.value ? null : _submit,
                  icon: controller.isSigningIn.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_outlined, size: 18),
                  label: const Text('Sign in'),
                ),
              ),
              const SizedBox(height: 12),
              Obx(() {
                final error = controller.signInError.value;
                if (error.isEmpty) return const SizedBox.shrink();
                return _FlowFinErrorNotice(message: error);
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlowFinOverview extends StatelessWidget {
  const _FlowFinOverview();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<FlowFinController>();

    return Obx(() {
      final snapshot = controller.bootstrap.value;
      final overview = controller.overview.value;
      final loading = controller.isLoadingDashboard.value;

      if (loading && snapshot == null) {
        return const Center(child: CircularProgressIndicator());
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  controller.user.value?.email ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: AppCyberTheme.dataTextStyle(
                    size: 11.5,
                    color: AppCyberTheme.textMuted,
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('flowfin-refresh'),
                onPressed: loading ? null : controller.loadDashboard,
                icon: const Icon(Icons.refresh_outlined, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Obx(() {
            final error = controller.dashboardError.value;
            if (error.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FlowFinErrorNotice(message: error),
            );
          }),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (overview != null) _FlowFinTotals(overview: overview),
                  if (overview != null && overview.estimated) ...[
                    const SizedBox(height: 8),
                    // FlowFin never turns a reconciliation gap into a
                    // transaction; it only reports it.
                    _FlowFinNotice(
                      icon: Icons.info_outline,
                      message:
                          'Balances are estimates — '
                          '${overview.missingCheckInWalletIds.length} wallet(s) '
                          'have no check-in for this period.',
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (snapshot != null) ...[
                    _FlowFinWalletList(controller: controller),
                    const SizedBox(height: 14),
                    _FlowFinInsightCard(
                      insight: snapshot.latestInsight,
                      fallback: controller.insightError.value,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _FlowFinTotals extends StatelessWidget {
  const _FlowFinTotals({required this.overview});

  final FlowFinStatsOverview overview;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _FlowFinStatTile(
          label: 'Total balance',
          value: FlowFinMoney.format(overview.totalBalanceMinor),
        ),
        _FlowFinStatTile(
          label: 'Income',
          value: FlowFinMoney.format(overview.incomeMinor),
        ),
        _FlowFinStatTile(
          label: 'Expense',
          value: FlowFinMoney.format(overview.expenseMinor),
        ),
        _FlowFinStatTile(
          label: 'Net',
          value: FlowFinMoney.format(overview.netMinor, withSign: true),
        ),
        _FlowFinStatTile(
          label: 'Transfers',
          value: '${overview.transferCount}',
        ),
      ],
    );
  }
}

class _FlowFinStatTile extends StatelessWidget {
  const _FlowFinStatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppCyberTheme.lineBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppCyberTheme.dataTextStyle(
              size: 10,
              color: AppCyberTheme.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppCyberTheme.dataTextStyle(
              size: 15,
              color: AppCyberTheme.textPrimary,
              weight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowFinWalletList extends StatelessWidget {
  const _FlowFinWalletList({required this.controller});

  final FlowFinController controller;

  @override
  Widget build(BuildContext context) {
    final wallets = controller.activeWallets;
    if (wallets.isEmpty) {
      return const _FlowFinNotice(
        icon: Icons.account_balance_wallet_outlined,
        message: 'No wallets yet.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PanelTitle(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Wallets',
        ),
        const SizedBox(height: 8),
        ...wallets.map(
          (wallet) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    wallet.name,
                    overflow: TextOverflow.ellipsis,
                    style: AppCyberTheme.dataTextStyle(
                      size: 12,
                      color: AppCyberTheme.textPrimary,
                    ),
                  ),
                ),
                Text(
                  FlowFinMoney.format(
                    controller.balanceMinorFor(wallet.id),
                  ),
                  style: AppCyberTheme.dataTextStyle(
                    size: 12,
                    color: AppCyberTheme.textPrimary,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FlowFinInsightCard extends StatelessWidget {
  const _FlowFinInsightCard({required this.insight, required this.fallback});

  final FlowFinInsight? insight;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final current = insight;
    // The database is the source of truth and AI only interprets it, so a
    // missing insight is a note, never an error that hides the numbers above.
    if (current == null) {
      return _FlowFinNotice(
        icon: Icons.auto_awesome_outlined,
        message: fallback.isEmpty ? 'No AI insight yet.' : fallback,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppCyberTheme.lineBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.auto_awesome_outlined,
            title: 'Latest insight',
          ),
          const SizedBox(height: 8),
          Text(
            current.title,
            style: AppCyberTheme.dataTextStyle(
              size: 13,
              color: AppCyberTheme.textPrimary,
              weight: FontWeight.w800,
            ),
          ),
          if (current.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              current.summary,
              style: AppCyberTheme.dataTextStyle(
                size: 12,
                color: AppCyberTheme.textMuted,
              ),
            ),
          ],
          ...current.suggestions.map(
            (suggestion) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '• $suggestion',
                style: AppCyberTheme.dataTextStyle(
                  size: 12,
                  color: AppCyberTheme.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowFinNotice extends StatelessWidget {
  const _FlowFinNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppCyberTheme.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: AppCyberTheme.dataTextStyle(
              size: 11.5,
              color: AppCyberTheme.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _FlowFinErrorNotice extends StatelessWidget {
  const _FlowFinErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              key: const Key('flowfin-error'),
              style: AppCyberTheme.dataTextStyle(
                size: 11.5,
                color: AppCyberTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
