import 'dart:io';

import 'package:app_management_center/app/modules/shared/device_run_lock.dart';
import 'package:app_management_center/app/services/ch_play_project_inspector_service.dart';
import 'package:path/path.dart' as p;

import '../models/bundle_check_models.dart';
import 'android_device.dart';
import 'android_toolchain.dart';
import 'bundle_check_store.dart';
import 'bundle_inspector.dart';
import 'checks/build_checks.dart';
import 'checks/env_checks.dart';
import 'device_smoke_runner.dart';
import 'project_contract_scanner.dart';

/// A project on this machine that a bundle could have been built from.
class BundleProjectCandidate {
  const BundleProjectCandidate({
    required this.name,
    required this.path,
    this.applicationId,
    this.chPlayProjectId,
    this.storeVersionCode,
  });

  final String name;
  final String path;
  final String? applicationId;
  final String? chPlayProjectId;
  final int? storeVersionCode;

  /// Exact applicationId, or the applicationId plus a flavor suffix.
  bool matches(String packageName) {
    final id = applicationId;
    if (id == null || id.isEmpty) return false;
    return packageName == id || packageName.startsWith('$id.');
  }
}

/// Where the checker learns about projects, kept apart from GetX so the
/// service can be tested with a plain list.
abstract class BundleProjectSource {
  Future<List<BundleProjectCandidate>> candidates();

  /// The keystore saved for this project's CH Play entry, if any.
  Future<KeystoreRef?> savedKeystore(BundleProjectCandidate candidate);
}

/// One check as it ran: the saved report plus what only lives in memory.
class BundleCheckRun {
  const BundleCheckRun({
    required this.report,
    required this.candidates,
    required this.contract,
    this.project,
    this.keystore,
  });

  final BundleCheckReport report;

  /// Every project whose applicationId fits the bundle's package.
  final List<BundleProjectCandidate> candidates;
  final BundleProjectCandidate? project;
  final EnvContract contract;

  /// For signing a universal APK; never written to disk.
  final KeystoreRef? keystore;

  BundleCheckRun withReport(BundleCheckReport value) {
    return BundleCheckRun(
      report: value,
      candidates: candidates,
      contract: contract,
      project: project,
      keystore: keystore,
    );
  }
}

class BundleCheckService {
  BundleCheckService({
    required this.store,
    required this.projects,
    this.inspector = const BundleInspector(),
    this.scanner = const ProjectContractScanner(),
    BundleProcessRunner runner = const IoBundleProcessRunner(),
    JavaTools? tools,
    BundletoolManager? bundletool,
    DateTime Function()? now,
    bool inspectInBackground = true,
    AndroidSdk? sdk,
    Future<void> Function(Duration)? sleep,
  }) : _runner = runner,
       _tools = tools ?? JavaTools.locate(),
       _bundletool = bundletool,
       _now = now ?? DateTime.now,
       _inspectInBackground = inspectInBackground,
       sdk = sdk ?? AndroidSdk.locate(),
       _sleep = sleep;

  final BundleCheckStore store;
  final BundleProjectSource projects;
  final BundleInspector inspector;
  final ProjectContractScanner scanner;
  final BundleProcessRunner _runner;
  final JavaTools _tools;
  final DateTime Function() _now;
  final bool _inspectInBackground;
  BundletoolManager? _bundletool;
  final Map<String, String> _fingerprintCache = {};
  final AndroidSdk sdk;
  final Future<void> Function(Duration)? _sleep;

  Future<BundletoolManager> bundletool() async {
    return _bundletool ??= BundletoolManager(
      toolsDirectory: await store.toolsDirectory,
    );
  }

  Future<List<BundleProjectCandidate>> matchProjects(String packageName) async {
    final all = await projects.candidates();
    final exact = all.where((c) => c.applicationId == packageName);
    final flavored = all.where(
      (c) => c.applicationId != packageName && c.matches(packageName),
    );
    return [...exact, ...flavored];
  }

  /// Checks the bundle at [path].
  ///
  /// [project] picks a project explicitly; left null the first match by
  /// package is used, and [detachProject] checks without any project.
  Future<BundleCheckRun> check(
    String path, {
    BundleProjectCandidate? project,
    bool detachProject = false,
    bool runBundletoolValidate = true,
    void Function(String step)? onProgress,
  }) async {
    final started = _now();
    final stopwatch = Stopwatch()..start();

    onProgress?.call('Đọc manifest');
    final manifest = await inspector.readManifest(path);
    final package = manifest.packageName;
    final candidates = await matchProjects(package);
    final chosen = detachProject ? null : project ?? candidates.firstOrNull;
    final override = await store.overrideFor(package);

    onProgress?.call('Đọc cấu hình project');
    final contract = chosen == null
        ? const EnvContract().withOverride(override)
        : (await scanner.scan(chosen.path)).withOverride(override);
    final keystore = chosen == null ? null : await _keystore(chosen);
    final context = chosen == null ? null : await _context(chosen);
    final signer = await _signerExpectation(override, keystore);

    onProgress?.call('Giải nén và soi bundle');
    final facts = _inspectInBackground
        ? await inspector.inspectInBackground(
            path,
            nativeNeedles: contract.nativeNeedles,
          )
        : await inspector.inspect(path, nativeNeedles: contract.nativeNeedles);

    bool? valid;
    var validateMessage = '';
    if (runBundletoolValidate) {
      final jar = await (await bundletool()).find();
      if (jar != null) {
        onProgress?.call('bundletool validate');
        try {
          (valid, validateMessage) = await BundletoolClient(
            runner: _runner,
            tools: _tools,
            jar: jar,
          ).validate(path);
        } on BundleToolException catch (error) {
          validateMessage = error.message;
        }
      }
    }

    final previous = await store.previousFor(
      package,
      excludingSha256: facts.sha256,
    );
    final results = [
      ...runBuildChecks(
        facts,
        project: context,
        signer: signer,
        previous: previous,
        now: started,
        bundletoolValid: valid,
        bundletoolMessage: validateMessage,
      ),
      ...runEnvChecks(facts, contract),
    ];

    final report = BundleCheckReport(
      id: 'check_${started.microsecondsSinceEpoch}',
      createdAt: started,
      sourcePath: path,
      fileName: p.basename(path),
      fileSize: facts.fileSize,
      sha256: facts.sha256,
      packageName: package,
      versionName: manifest.versionName,
      versionCode: manifest.versionCode,
      minSdk: manifest.minSdk,
      targetSdk: manifest.targetSdk,
      permissions: manifest.permissions,
      abis: facts.abis.toList()..sort(),
      estimatedArm64DownloadBytes: facts.estimatedArm64DownloadBytes,
      results: results,
      signer: facts.signer,
      projectName: chosen?.name,
      projectPath: chosen?.path,
      durationMs: stopwatch.elapsedMilliseconds,
      launcherActivity: manifest.launcherActivity,
    );
    await store.save(report);
    return BundleCheckRun(
      report: report,
      candidates: candidates,
      project: chosen,
      contract: contract,
      keystore: keystore,
    );
  }

  /// Accepts the key [report] was signed with as the right one for its
  /// package, so later bundles signed with anything else fail B04.
  Future<void> pinSigner(BundleCheckReport report) async {
    final signer = report.signer;
    if (signer == null) return;
    final current =
        await store.overrideFor(report.packageName) ??
        const EnvContractOverride();
    await store.saveOverride(
      report.packageName,
      current.copyWith(pinnedSignerSha256: signer.sha256),
    );
  }

  Future<File> exportUniversalApk(
    BundleCheckRun run, {
    void Function(String step)? onProgress,
  }) async {
    final jar = await (await bundletool()).find();
    if (jar == null) {
      throw const BundleToolException('Chưa có bundletool — tải về trước.');
    }
    final report = run.report;
    if (!File(report.sourcePath).existsSync()) {
      throw BundleToolException(
        'File gốc ${report.sourcePath} không còn ở đó.',
      );
    }
    onProgress?.call('bundletool build-apks --mode=universal');
    final baseName = p.basenameWithoutExtension(report.fileName);
    return BundletoolClient(
      runner: _runner,
      tools: _tools,
      jar: jar,
    ).buildUniversalApk(
      bundlePath: report.sourcePath,
      outputDirectory: await store.jobDirectory(report.id),
      apkFileName: '${baseName}_universal.apk',
      keystore: run.keystore,
    );
  }

  /// Connected devices first, then AVDs that are switched off.
  Future<List<DeviceTarget>> listTargets() async {
    final devices = await AdbClient(runner: _runner, adb: sdk.adb).devices();
    final running = {
      for (final device in devices)
        if (device.avdName != null) device.avdName!,
    };
    final avds = await EmulatorLauncher(
      runner: _runner,
      emulator: sdk.emulator,
    ).listAvds();
    return [
      for (final device in devices) DeviceTarget.device(device),
      for (final avd in avds)
        if (!running.contains(avd)) DeviceTarget.avd(avd),
    ];
  }

  /// Installs [run]'s bundle on [target], opens it, watches it, and saves the
  /// "runs" results into the same report.
  ///
  /// Queued on the app-wide [DeviceRunLock]: the page, the Telegram bot and
  /// QA Desk's mobile suites must not drive the same emulator at once.
  Future<(BundleCheckRun, DeviceRunOutcome)> runOnDevice(
    BundleCheckRun run,
    DeviceTarget target, {
    DeviceRunOptions options = const DeviceRunOptions(),
    void Function(String step)? onProgress,
  }) => DeviceRunLock.run(
    () => _runOnDevice(run, target, options: options, onProgress: onProgress),
  );

  Future<(BundleCheckRun, DeviceRunOutcome)> _runOnDevice(
    BundleCheckRun run,
    DeviceTarget target, {
    required DeviceRunOptions options,
    void Function(String step)? onProgress,
  }) async {
    final jar = await (await bundletool()).find();
    if (jar == null) {
      throw const BundleToolException(
        'Chạy thử cần bundletool — bấm "Tải bundletool" trước.',
      );
    }
    final report = run.report;
    if (!File(report.sourcePath).existsSync()) {
      throw BundleToolException(
        'File gốc ${report.sourcePath} không còn ở đó.',
      );
    }
    final outcome =
        await DeviceSmokeRunner(
          runner: _runner,
          tools: _tools,
          sdk: sdk,
          bundletoolJar: jar,
          sleep: _sleep,
          now: _now,
        ).run(
          report: report,
          target: target,
          jobDirectory: await store.jobDirectory(report.id),
          keystore: run.keystore,
          options: options,
          onProgress: onProgress,
        );
    final updated = report.withDeviceRun(outcome.results, outcome.summary);
    await store.save(updated);
    return (run.withReport(updated), outcome);
  }

  Future<BundleProjectContext> _context(BundleProjectCandidate project) async {
    String? versionName;
    int? versionCode;
    final pubspec = File(p.join(project.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      try {
        final version = ChPlayProjectInspectorService.parsePubspecVersion(
          await pubspec.readAsString(),
        );
        versionName = version?.name;
        versionCode = version?.code;
      } on FileSystemException {
        // No pubspec version; B03 then compares with CH Play only.
      }
    }
    return BundleProjectContext(
      name: project.name,
      path: project.path,
      applicationId: project.applicationId,
      pubspecVersionName: versionName,
      pubspecVersionCode: versionCode,
      storeVersionCode: project.storeVersionCode,
    );
  }

  Future<KeystoreRef?> _keystore(BundleProjectCandidate project) async {
    return await projects.savedKeystore(project) ??
        readProjectKeystore(project.path);
  }

  Future<SignerExpectation?> _signerExpectation(
    EnvContractOverride? override,
    KeystoreRef? keystore,
  ) async {
    final pinned = override?.pinnedSignerSha256;
    if (pinned != null && pinned.isNotEmpty) {
      return SignerExpectation(sha256: pinned, source: 'đã ghim trong AMC');
    }
    if (keystore == null) return null;

    final cacheKey = [
      keystore.path,
      keystore.alias,
      File(keystore.path).existsSync()
          ? File(keystore.path).lastModifiedSync().millisecondsSinceEpoch
          : 0,
    ].join('|');
    final cached = _fingerprintCache[cacheKey];
    if (cached != null) {
      return SignerExpectation(sha256: cached, source: keystore.source);
    }
    try {
      final sha256 = await KeystoreFingerprintReader(
        runner: _runner,
        tools: _tools,
      ).sha256Of(keystore);
      _fingerprintCache[cacheKey] = sha256;
      return SignerExpectation(sha256: sha256, source: keystore.source);
    } on BundleToolException catch (error) {
      return SignerExpectation(
        source: keystore.source,
        lookupError: '${keystore.source}: ${error.message}',
      );
    }
  }
}
