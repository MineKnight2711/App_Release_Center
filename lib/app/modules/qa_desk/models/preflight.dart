/// Something that stands between the current selection and a useful run.
enum PreflightKind {
  noSuites,
  deviceMissing,
  physicalDeviceRequired,
  appiumMissing,
  secretsMissing,
  networkBusy,

  /// Not a blocker: the run works, but through the slowed proxy.
  networkSimulated,

  /// Not a blocker: AMC is releasing the same project, and a test run will
  /// fight the build for its `build/` folder and Gradle locks.
  projectBusy,

  /// Maestro or Java missing.
  automationSetup,

  /// The demo-account vault is not created, locked or unreachable.
  vaultNotReady,

  /// The app or environment an automated scenario names is not declared.
  automationConfig,
  accountMissing,
  writesOnProduction,
  productionGuard,

  /// Not a blocker: the page confirms before running against production.
  productionRun,
}

class PreflightIssue {
  const PreflightIssue({
    required this.kind,
    required this.message,
    this.blocking = true,
    this.sourceId,
    this.environmentId,
  });

  final PreflightKind kind;
  final String message;

  /// Blocking issues disable the run button; the rest are shown as notes.
  final bool blocking;

  /// Set for [PreflightKind.secretsMissing], so the page can open the right
  /// secrets form.
  final String? sourceId;
  final String? environmentId;
}
