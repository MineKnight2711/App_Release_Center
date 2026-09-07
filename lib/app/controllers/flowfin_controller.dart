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
class FlowFinController extends GetxController {
  FlowFinController({required this.client, required this.store});

  final FlowFinApiClient client;
  final ProjectStoreService store;

  final settings = const FlowFinSettings().obs;
  final user = Rxn<FlowFinUser>();
  final bootstrap = Rxn<FlowFinBootstrap>();
  final overview = Rxn<FlowFinStatsOverview>();

  final isSigningIn = false.obs;
  final isLoadingDashboard = false.obs;
  final isCheckingHealth = false.obs;

  final signInError = ''.obs;
  final dashboardError = ''.obs;

  /// Set when the dashboard loaded but the AI-produced insight did not.
  /// FlowFin's rule: a broken AI path never blocks the numbers.
  final insightError = ''.obs;
  final healthStatus = ''.obs;

  bool get isSignedIn => user.value != null;
  FlowFinEnvironment get environment => settings.value.environment;
  String get baseUrl => settings.value.baseUrl;

  @override
  void onInit() {
    super.onInit();
    settings.value = store.flowFinSettings;
    client.settings = settings.value;
    unawaited(restore());
  }

  Future<void> restore() async {
    final session = await client.restoreSession();
    user.value = session?.user;
    if (session != null) {
      unawaited(loadDashboard());
    }
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
    bootstrap.value = null;
    overview.value = null;
    dashboardError.value = '';
    insightError.value = '';
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
    } on FlowFinApiException catch (error) {
      signInError.value = _describe(error);
      return false;
    } on TimeoutException {
      signInError.value = 'FlowFin did not answer in time at $baseUrl.';
      return false;
    } catch (error) {
      signInError.value = 'Could not reach FlowFin at $baseUrl: $error';
      return false;
    } finally {
      isSigningIn.value = false;
    }
  }

  Future<void> signOut() async {
    await client.logout();
    user.value = null;
    bootstrap.value = null;
    overview.value = null;
    dashboardError.value = '';
    insightError.value = '';
  }

  /// One `/bootstrap` for the reference data, one `/stats/overview` for the
  /// month's numbers. Deltas after this go through `/sync?cursor=`.
  Future<void> loadDashboard() async {
    if (isLoadingDashboard.value) return;
    isLoadingDashboard.value = true;
    dashboardError.value = '';
    insightError.value = '';

    try {
      final snapshot = await client.bootstrap();
      bootstrap.value = snapshot;
      user.value = snapshot.user;
      if (snapshot.latestInsight == null) {
        insightError.value = 'No AI insight yet for this period.';
      }

      final now = DateTime.now();
      overview.value = await client.statsOverview(
        from: _isoDate(DateTime(now.year, now.month, 1)),
        to: _isoDate(now),
      );
    } on FlowFinAuthRequiredException {
      user.value = null;
      dashboardError.value = 'FlowFin session expired. Sign in again.';
    } on FlowFinApiException catch (error) {
      dashboardError.value = _describe(error);
    } on TimeoutException {
      dashboardError.value = 'FlowFin did not answer in time at $baseUrl.';
    } catch (error) {
      dashboardError.value = 'Could not reach FlowFin at $baseUrl: $error';
    } finally {
      isLoadingDashboard.value = false;
    }
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
    } on TimeoutException {
      healthStatus.value = 'No answer from $baseUrl';
    } catch (error) {
      healthStatus.value = 'Unreachable: $error';
    } finally {
      isCheckingHealth.value = false;
    }
  }

  /// Wallets the overview counts, in display order.
  List<FlowFinWallet> get activeWallets {
    final snapshot = bootstrap.value;
    if (snapshot == null) return const [];
    final wallets = snapshot.wallets.where((w) => !w.isArchived).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return wallets;
  }

  int balanceMinorFor(String walletId) {
    final balances = overview.value?.walletBalances ?? const [];
    for (final balance in balances) {
      if (balance.walletId == walletId) return balance.balanceMinor;
    }
    return 0;
  }

  String _describe(FlowFinApiException error) {
    if (error.isRateLimited) {
      return 'FlowFin is rate limiting this request. Wait a moment before retrying.';
    }
    return error.toString();
  }

  static String _isoDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
