import 'dart:async';

import 'package:app_management_center/app/models/flowfin_models.dart';
import 'package:app_management_center/app/models/flowfin_settings.dart';
import 'package:app_management_center/app/services/flowfin_api_client.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:get/get.dart';

/// Drives the FlowFin dialog.
///
/// Kept out of HomeController on purpose: FlowFin is its own product surface
/// with its own account, and HomeController is already the app's largest file.
/// State is grouped by tab below; reference data (wallets, categories) is
/// shared because almost every tab needs it.
class FlowFinController extends GetxController {
  FlowFinController({required this.client, required this.store});

  final FlowFinApiClient client;
  final ProjectStoreService store;

  // ----- shell

  final settings = const FlowFinSettings().obs;
  final user = Rxn<FlowFinUser>();
  final isSigningIn = false.obs;
  final signInError = ''.obs;
  final isCheckingHealth = false.obs;
  final healthStatus = ''.obs;

  // ----- shared reference data

  final bootstrap = Rxn<FlowFinBootstrap>();
  final wallets = <FlowFinWallet>[].obs;
  final categories = <FlowFinCategory>[].obs;

  // ----- overview

  final overview = Rxn<FlowFinStatsOverview>();
  final isLoadingDashboard = false.obs;
  final dashboardError = ''.obs;

  /// Set when the dashboard loaded but the AI-produced insight did not.
  /// FlowFin's rule: a broken AI path never blocks the numbers.
  final insightError = ''.obs;

  // ----- transactions

  final transactions = <FlowFinTransaction>[].obs;
  final transactionTotalIncome = 0.obs;
  final transactionTotalExpense = 0.obs;
  final transactionCursor = ''.obs;
  final isLoadingTransactions = false.obs;
  final transactionsError = ''.obs;
  final filterWalletId = ''.obs;
  final filterCategoryId = ''.obs;
  final filterType = ''.obs;
  final filterQuery = ''.obs;

  // ----- budgets

  final budgets = <FlowFinBudget>[].obs;
  final isLoadingBudgets = false.obs;
  final budgetsError = ''.obs;

  // ----- statistics

  final timeline = Rxn<FlowFinTimeline>();
  final breakdown = Rxn<FlowFinBreakdown>();
  final breakdownKind = 'expense'.obs;
  final isLoadingStats = false.obs;
  final statsError = ''.obs;

  // ----- insights

  final insights = <FlowFinInsight>[].obs;
  final isLoadingInsights = false.obs;
  final isRefreshingInsight = false.obs;
  final insightsError = ''.obs;

  // ----- reconciliation

  final reconciliations = <FlowFinReconciliation>[].obs;
  final reconciliationDate = ''.obs;
  final isLoadingReconciliation = false.obs;
  final reconciliationError = ''.obs;

  // ----- imports

  final importBatches = <FlowFinImportBatch>[].obs;
  final activeImportBatch = Rxn<FlowFinImportBatch>();
  final isLoadingImports = false.obs;
  final importsError = ''.obs;

  // ----- account

  final notificationPrefs = Rxn<FlowFinNotificationPrefs>();
  final isSavingAccount = false.obs;
  final accountError = ''.obs;
  final accountStatus = ''.obs;

  bool get isSignedIn => user.value != null;
  FlowFinEnvironment get environment => settings.value.environment;
  String get baseUrl => settings.value.baseUrl;

  @override
  void onInit() {
    super.onInit();
    settings.value = store.flowFinSettings;
    client.settings = settings.value;
    reconciliationDate.value = isoDate(DateTime.now());
    unawaited(restore());
  }

  // ------------------------------------------------------------------ shell

  Future<void> restore() async {
    final session = await client.restoreSession();
    user.value = session?.user;
    if (session != null) unawaited(loadDashboard());
  }

  Future<void> setEnvironment(FlowFinEnvironment next) async {
    if (next == settings.value.environment) return;
    await _applySettings(settings.value.copyWith(environment: next));
  }

  Future<void> setBaseUrl(FlowFinEnvironment target, String? baseUrl) async {
    await _applySettings(settings.value.withBaseUrl(target, baseUrl));
  }

  Future<void> _applySettings(FlowFinSettings next) async {
    settings.value = next;
    client.settings = next;
    await store.saveFlowFinSettings(next);

    // Sessions are per environment, so switching means re-reading the store.
    _clearData();
    client.forgetSessionInMemory();
    await restore();
  }

  Future<bool> signIn({required String email, required String password}) async {
    if (isSigningIn.value) return false;
    isSigningIn.value = true;
    signInError.value = '';

    try {
      final session = await client.login(email: email, password: password);
      user.value = session.user;
      unawaited(loadDashboard());
      return true;
    } catch (error) {
      signInError.value = describeError(error);
      return false;
    } finally {
      isSigningIn.value = false;
    }
  }

  Future<void> signOut() async {
    await client.logout();
    user.value = null;
    _clearData();
  }

  Future<void> checkHealth() async {
    if (isCheckingHealth.value) return;
    isCheckingHealth.value = true;
    healthStatus.value = '';

    try {
      final body = await client.health();
      final ok = body['ok'] == true;
      final env = (body['environment'] as String?) ?? environment.id;
      healthStatus.value = ok ? 'OK · $env' : 'Unhealthy · $env';
    } catch (error) {
      healthStatus.value = 'Unreachable: ${describeError(error)}';
    } finally {
      isCheckingHealth.value = false;
    }
  }

  void _clearData() {
    bootstrap.value = null;
    overview.value = null;
    wallets.clear();
    categories.clear();
    transactions.clear();
    budgets.clear();
    insights.clear();
    reconciliations.clear();
    importBatches.clear();
    activeImportBatch.value = null;
    timeline.value = null;
    breakdown.value = null;
    notificationPrefs.value = null;
    for (final message in [
      dashboardError,
      insightError,
      transactionsError,
      budgetsError,
      statsError,
      insightsError,
      reconciliationError,
      importsError,
      accountError,
      accountStatus,
    ]) {
      message.value = '';
    }
  }

  // --------------------------------------------------------------- overview

  /// One `/bootstrap` for the reference data, one `/stats/overview` for the
  /// month's numbers.
  Future<void> loadDashboard() async {
    if (isLoadingDashboard.value) return;
    isLoadingDashboard.value = true;
    dashboardError.value = '';
    insightError.value = '';

    try {
      final snapshot = await client.bootstrap();
      bootstrap.value = snapshot;
      user.value = snapshot.user;
      wallets.value = snapshot.wallets;
      categories.value = snapshot.categories;
      budgets.value = snapshot.budgets;
      if (snapshot.latestInsight == null) {
        insightError.value = 'No AI insight yet for this period.';
      }

      overview.value = await client.statsOverview(
        from: isoDate(monthStart()),
        to: isoDate(DateTime.now()),
      );
    } on FlowFinAuthRequiredException {
      user.value = null;
      dashboardError.value = 'FlowFin session expired. Sign in again.';
    } catch (error) {
      dashboardError.value = describeError(error);
    } finally {
      isLoadingDashboard.value = false;
    }
  }

  /// Reloads only the reference lists, after a wallet or category changed.
  Future<void> _reloadReferenceData() async {
    try {
      final results = await Future.wait([
        client.listWallets(includeArchived: true),
        client.listCategories(),
      ]);
      wallets.value = results[0] as List<FlowFinWallet>;
      categories.value = results[1] as List<FlowFinCategory>;
    } catch (_) {
      // The caller already surfaced whatever failed; a stale list is better
      // than replacing a completed action with an error.
    }
  }

  // ----------------------------------------------------------- transactions

  Future<void> loadTransactions({bool append = false}) async {
    if (isLoadingTransactions.value) return;
    isLoadingTransactions.value = true;
    transactionsError.value = '';

    try {
      final page = await client.listTransactions(
        walletId: filterWalletId.value,
        categoryId: filterCategoryId.value,
        type: filterType.value,
        query: filterQuery.value,
        cursor: append ? transactionCursor.value : null,
      );
      transactions.value = append
          ? [...transactions, ...page.items]
          : page.items;
      transactionCursor.value = page.nextCursor;
      transactionTotalIncome.value = page.incomeMinor;
      transactionTotalExpense.value = page.expenseMinor;
    } catch (error) {
      transactionsError.value = describeError(error);
    } finally {
      isLoadingTransactions.value = false;
    }
  }

  void setTransactionFilter({
    String? walletId,
    String? categoryId,
    String? type,
    String? query,
  }) {
    if (walletId != null) filterWalletId.value = walletId;
    if (categoryId != null) filterCategoryId.value = categoryId;
    if (type != null) filterType.value = type;
    if (query != null) filterQuery.value = query;
    transactionCursor.value = '';
    unawaited(loadTransactions());
  }

  void clearTransactionFilters() {
    filterWalletId.value = '';
    filterCategoryId.value = '';
    filterType.value = '';
    filterQuery.value = '';
    transactionCursor.value = '';
    unawaited(loadTransactions());
  }

  Future<String?> saveTransaction({
    FlowFinTransaction? existing,
    required String type,
    required int amountMinor,
    required String walletId,
    required String localDate,
    String? categoryId,
    String? toWalletId,
    String note = '',
  }) async {
    try {
      if (existing == null) {
        await client.createTransaction(
          type: type,
          amountMinor: amountMinor,
          walletId: walletId,
          localDate: localDate,
          categoryId: categoryId,
          toWalletId: toWalletId,
          note: note,
        );
      } else {
        await client.updateTransaction(
          id: existing.id,
          baseVersion: existing.version,
          amountMinor: amountMinor,
          walletId: walletId,
          localDate: localDate,
          categoryId: categoryId ?? '',
          toWalletId: toWalletId ?? '',
          note: note,
        );
      }
      await Future.wait([loadTransactions(), loadDashboard()]);
      return null;
    } catch (error) {
      return describeError(error);
    }
  }

  Future<String?> deleteTransaction(FlowFinTransaction transaction) async {
    try {
      await client.deleteTransaction(
        id: transaction.id,
        baseVersion: transaction.version,
      );
      await Future.wait([loadTransactions(), loadDashboard()]);
      return null;
    } catch (error) {
      return describeError(error);
    }
  }

  // --------------------------------------------------------- wallets

  Future<String?> saveWallet({
    FlowFinWallet? existing,
    required String name,
    required String type,
    required int initialBalanceMinor,
    required String openedOn,
    bool includeInTotal = true,
  }) async {
    try {
      if (existing == null) {
        await client.createWallet(
          name: name,
          type: type,
          initialBalanceMinor: initialBalanceMinor,
          openedOn: openedOn,
          includeInTotal: includeInTotal,
        );
      } else {
        await client.updateWallet(
          id: existing.id,
          baseVersion: existing.version,
          name: name,
          type: type,
          includeInTotal: includeInTotal,
        );
      }
      await _reloadReferenceData();
      unawaited(loadDashboard());
      return null;
    } catch (error) {
      return describeError(error);
    }
  }

  Future<String?> setWalletArchived(FlowFinWallet wallet, bool archived) async {
    try {
      await client.updateWallet(
        id: wallet.id,
        baseVersion: wallet.version,
        archived: archived,
      );
      await _reloadReferenceData();
      return null;
    } catch (error) {
      return describeError(error);
    }
  }

  Future<String?> deleteWallet(FlowFinWallet wallet) async {
    try {
      await client.deleteWallet(id: wallet.id, baseVersion: wallet.version);
      await _reloadReferenceData();
      unawaited(loadDashboard());
      return null;
    } catch (error) {
      return describeError(error);
    }
  }

  // -------------------------------------------------------------- categories

  Future<String?> saveCategory({
    FlowFinCategory? existing,
    required String name,
    required String kind,
  }) async {
    try {
      if (existing == null) {
        await client.createCategory(name: name, kind: kind);
      } else {
        await client.updateCategory(
          id: existing.id,
          baseVersion: existing.version,
          name: name,
        );
      }
      await _reloadReferenceData();
      return null;
    } catch (error) {
      return describeError(error);
    }
  }

  Future<String?> setCategoryArchived(
    FlowFinCategory category,
    bool archived,
  ) async {
    try {
      await client.updateCategory(
        id: category.id,
        baseVersion: category.version,
        archived: archived,
      );
      await _reloadReferenceData();
      return null;
    } catch (error) {
      return describeError(error);
    }
  }

  Future<String?> deleteCategory(FlowFinCategory category) async {
    try {
      await client.deleteCategory(
        id: category.id,
        baseVersion: category.version,
      );
      await _reloadReferenceData();
      return null;
    } catch (error) {
      return describeError(error);
    }
  }

  // ----------------------------------------------------------------- budgets

  Future<void> loadBudgets() async {
    if (isLoadingBudgets.value) return;
    isLoadingBudgets.value = true;
    budgetsError.value = '';

    try {
      budgets.value = await client.listBudgets(periodKey: currentPeriodKey());
    } catch (error) {
      budgetsError.value = describeError(error);
    } finally {
      isLoadingBudgets.value = false;
    }
  }

  Future<String?> saveBudget({
    FlowFinBudget? existing,
    required String scope,
    required int limitMinor,
    String? categoryId,
  }) async {
    try {
      if (existing == null) {
        await client.createBudget(
          scope: scope,
          limitMinor: limitMinor,
          categoryId: categoryId,
          periodKey: currentPeriodKey(),
        );
      } else {
        await client.updateBudget(
          id: existing.id,
          baseVersion: existing.version,
          limitMinor: limitMinor,
        );
      }
      await loadBudgets();
      return null;
    } catch (error) {
      return describeError(error);
    }
  }

  Future<String?> deleteBudget(FlowFinBudget budget) async {
    try {
      await client.deleteBudget(id: budget.id, baseVersion: budget.version);
      await loadBudgets();
      return null;
    } catch (error) {
      return describeError(error);
    }
  }

  // -------------------------------------------------------------- statistics

  Future<void> loadStats() async {
    if (isLoadingStats.value) return;
    isLoadingStats.value = true;
    statsError.value = '';

    final from = isoDate(monthStart());
    final to = isoDate(DateTime.now());

    try {
      timeline.value = await client.statsTimeline(from: from, to: to);
      breakdown.value = await client.statsBreakdown(
        from: from,
        to: to,
        kind: breakdownKind.value,
      );
    } catch (error) {
      statsError.value = describeError(error);
    } finally {
      isLoadingStats.value = false;
    }
  }

  void setBreakdownKind(String kind) {
    if (kind == breakdownKind.value) return;
    breakdownKind.value = kind;
    unawaited(loadStats());
  }

  // ---------------------------------------------------------------- insights

  Future<void> loadInsights() async {
    if (isLoadingInsights.value) return;
    isLoadingInsights.value = true;
    insightsError.value = '';

    try {
      insights.value = await client.listInsights();
    } catch (error) {
      insightsError.value = describeError(error);
    } finally {
      isLoadingInsights.value = false;
    }
  }

  /// Queues a new insight. AI is interpretation only, so a failure here is
  /// reported and nothing else stops working.
  Future<String?> refreshInsight(String insightType) async {
    if (isRefreshingInsight.value) return null;
    isRefreshingInsight.value = true;

    try {
      await client.refreshInsight(insightType: insightType);
      await loadInsights();
      return null;
    } catch (error) {
      return describeError(error);
    } finally {
      isRefreshingInsight.value = false;
    }
  }

  // ---------------------------------------------------------- reconciliation

  Future<void> loadReconciliation() async {
    if (isLoadingReconciliation.value) return;
    isLoadingReconciliation.value = true;
    reconciliationError.value = '';

    try {
      reconciliations.value = await client.reconciliation(
        date: reconciliationDate.value,
      );
    } catch (error) {
      reconciliationError.value = describeError(error);
    } finally {
      isLoadingReconciliation.value = false;
    }
  }

  void setReconciliationDate(String date) {
    reconciliationDate.value = date;
    unawaited(loadReconciliation());
  }

  /// Records a counted balance. The returned difference is reported to the
  /// user — FlowFin never turns a gap into a transaction on its own.
  Future<({String? error, FlowFinReconciliation? result})> checkIn({
    required String walletId,
    required int balanceMinor,
    String note = '',
  }) async {
    try {
      final outcome = await client.upsertSnapshot(
        walletId: walletId,
        localDate: reconciliationDate.value,
        balanceMinor: balanceMinor,
        note: note,
      );
      await loadReconciliation();
      unawaited(loadDashboard());
      return (error: null, result: outcome.reconciliation);
    } catch (error) {
      return (error: describeError(error), result: null);
    }
  }

  // ----------------------------------------------------------------- imports

  Future<void> loadImports() async {
    if (isLoadingImports.value) return;
    isLoadingImports.value = true;
    importsError.value = '';

    try {
      importBatches.value = await client.listImports();
    } catch (error) {
      importsError.value = describeError(error);
    } finally {
      isLoadingImports.value = false;
    }
  }

  /// Desktop has no camera, so a batch starts from pasted text.
  Future<String?> createImport({
    required String source,
    required String text,
    String? defaultWalletId,
  }) async {
    isLoadingImports.value = true;
    importsError.value = '';

    try {
      final batch = await client.createImport(
        source: source,
        text: text,
        defaultWalletId: defaultWalletId,
      );
      activeImportBatch.value = batch;
      return null;
    } catch (error) {
      final message = describeError(error);
      importsError.value = message;
      return message;
    } finally {
      isLoadingImports.value = false;
    }
  }

  Future<String?> openImport(String id) async {
    try {
      activeImportBatch.value = await client.getImport(id);
      return null;
    } catch (error) {
      return describeError(error);
    }
  }

  Future<String?> confirmImport(
    List<FlowFinImportConfirmEntry> entries,
  ) async {
    final batch = activeImportBatch.value;
    if (batch == null) return 'No import batch is open.';

    try {
      await client.confirmImport(batchId: batch.id, entries: entries);
      activeImportBatch.value = null;
      await Future.wait([loadImports(), loadTransactions(), loadDashboard()]);
      return null;
    } catch (error) {
      return describeError(error);
    }
  }

  // ----------------------------------------------------------------- account

  Future<void> loadAccount() async {
    accountError.value = '';
    try {
      final profile = await client.me();
      user.value = profile.user;
      notificationPrefs.value = profile.prefs;
    } catch (error) {
      accountError.value = describeError(error);
    }
  }

  Future<String?> saveAccount({
    String? displayName,
    FlowFinNotificationPrefs? prefs,
  }) async {
    if (isSavingAccount.value) return null;
    isSavingAccount.value = true;
    accountError.value = '';
    accountStatus.value = '';

    try {
      final profile = await client.updateMe(
        displayName: displayName,
        notificationPreferences: prefs,
      );
      user.value = profile.user;
      notificationPrefs.value = profile.prefs;
      accountStatus.value = 'Saved.';
      return null;
    } catch (error) {
      final message = describeError(error);
      accountError.value = message;
      return message;
    } finally {
      isSavingAccount.value = false;
    }
  }

  // ----------------------------------------------------------------- helpers

  /// Wallets the overview counts, in display order.
  List<FlowFinWallet> get activeWallets {
    final active = wallets.where((wallet) => !wallet.isArchived).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return active;
  }

  List<FlowFinCategory> get activeCategories {
    final active = categories.where((category) => !category.isArchived).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return active;
  }

  int balanceMinorFor(String walletId) {
    for (final balance in overview.value?.walletBalances ?? const []) {
      if (balance.walletId == walletId) return balance.balanceMinor;
    }
    return 0;
  }

  String walletName(String? id) {
    if (id == null || id.isEmpty) return '';
    for (final wallet in wallets) {
      if (wallet.id == id) return wallet.name;
    }
    return '';
  }

  String categoryName(String? id) {
    if (id == null || id.isEmpty) return '';
    for (final category in categories) {
      if (category.id == id) return category.name;
    }
    return '';
  }

  String describeError(Object error) {
    if (error is FlowFinApiException) {
      if (error.isRateLimited) {
        return 'FlowFin is rate limiting this request. Wait a moment before retrying.';
      }
      if (error.isVersionConflict) {
        return 'This record changed elsewhere. Refresh before saving again.';
      }
      return error.toString();
    }
    if (error is FlowFinAuthRequiredException) return error.message;
    if (error is TimeoutException) {
      return 'FlowFin did not answer in time at $baseUrl.';
    }
    return 'Could not reach FlowFin at $baseUrl: $error';
  }

  static DateTime monthStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  static String currentPeriodKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static String isoDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
