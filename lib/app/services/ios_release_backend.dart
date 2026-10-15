import 'package:app_management_center/app/models/app_store_project.dart';
import 'package:app_management_center/app/models/ios_release.dart';
import 'package:get/get.dart';

/// Where the iOS release dialog sends its steps: this Mac, or a Mac build host
/// reached through the relay. Both run the same workflow, so the dialog asks
/// the same questions of either and only the transport differs.
abstract interface class IosReleaseBackend {
  Rxn<IosReleaseRun> get current;
  RxList<IosReleaseRun> get history;
  RxBool get busy;

  /// The log of the step running now, as this backend sees it.
  RxList<String> get liveLog;

  /// Whether steps run on this machine's runner, and so wait on anything else
  /// using it. A remote host has its own.
  bool get usesLocalRunner;

  /// Loads run history. A remote host answers for one [project] at a time.
  Future<void> load([AppStoreProject? project]);

  Future<IosReleaseRun> prepare({
    required AppStoreProject project,
    required IosReleaseSettings settings,
    String? version,
    IosStoreBuild? existingBuild,
  });

  Future<IosStoreState> inspect(
    AppStoreProject project,
    IosReleaseSettings settings,
    String version,
  );

  Future<void> build(IosReleaseRun run);
  Future<void> upload(IosReleaseRun run, {bool retryAfterVerification = false});
  Future<void> continueToTestFlight(IosReleaseRun run);
  Future<void> refresh(IosReleaseRun run);
  Future<void> waitForProcessing(IosReleaseRun run);
  Future<void> storeAction(IosReleaseRun run, String action);
  Future<void> cancel();

  /// Tail of a finished run's command log.
  Future<List<String>> savedLog(IosReleaseRun run);
}
