import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/bundle_check_models.dart';
import 'android_device.dart';
import 'android_toolchain.dart';
import 'screenshot_analysis.dart';

class DeviceRunOptions {
  const DeviceRunOptions({
    this.watchSeconds = 20,
    this.freshInstall = true,
    this.uninstallAfter = false,
    this.allowUninstall = false,
  });

  /// How long the app is watched after it opens.
  final int watchSeconds;

  /// On an emulator, remove any installed copy first so the run starts from
  /// a clean install, as a new user would.
  final bool freshInstall;

  /// On an emulator, remove the app once the run is over.
  final bool uninstallAfter;

  /// Uninstalling a conflicting copy on a physical device wipes its data, so
  /// it happens only after the user has confirmed.
  final bool allowUninstall;
}

class DeviceRunOutcome {
  const DeviceRunOutcome({
    required this.results,
    required this.summary,
    this.needsUninstallConfirm = false,
  });

  final List<CheckResult> results;
  final DeviceRunSummary summary;

  /// A physical device holds a copy signed with another key; installing
  /// needs it removed first.
  final bool needsUninstallConfirm;
}

/// R01–R06: install the bundle on a device, open it, watch it.
///
/// "Runs" means installs, opens, and does not crash or hang for the watch
/// window — not that its features work.
class DeviceSmokeRunner {
  DeviceSmokeRunner({
    required this.runner,
    required this.tools,
    required this.sdk,
    required this.bundletoolJar,
    Future<void> Function(Duration)? sleep,
    DateTime Function()? now,
    this.bootTimeout = const Duration(minutes: 3),
  }) : _sleep = sleep ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  final BundleProcessRunner runner;
  final JavaTools tools;
  final AndroidSdk sdk;
  final File bundletoolJar;
  final Duration bootTimeout;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _now;

  static const _remoteShot = '/data/local/tmp/amc_bundle_check.png';
  static const _maxLogBytes = 8 * 1024 * 1024;

  AdbClient get _adb => AdbClient(runner: runner, adb: sdk.adb);

  BundletoolClient get _bundletool =>
      BundletoolClient(runner: runner, tools: tools, jar: bundletoolJar);

  Future<DeviceRunOutcome> run({
    required BundleCheckReport report,
    required DeviceTarget target,
    required Directory jobDirectory,
    KeystoreRef? keystore,
    DeviceRunOptions options = const DeviceRunOptions(),
    void Function(String step)? onProgress,
  }) async {
    final started = _now();
    final stopwatch = Stopwatch()..start();
    final results = <CheckResult>[];
    final screenshots = <String>[];
    String? logcatFile;
    int? coldStartMs;
    var needsConfirm = false;
    final signedWith = keystore?.source ?? 'debug key của bundletool';
    final package = report.packageName;
    AndroidDevice? device;

    DeviceRunOutcome finish() {
      const order = ['R01', 'R02', 'R03', 'R04', 'R05', 'R06'];
      final done = {for (final result in results) result.id};
      for (final id in order) {
        if (done.contains(id)) continue;
        results.add(
          _result(
            id,
            CheckStatus.skip,
            _titles[id]!,
            'Bỏ qua vì bước trước lỗi.',
          ),
        );
      }
      results.sort(
        (a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)),
      );
      return DeviceRunOutcome(
        results: results,
        needsUninstallConfirm: needsConfirm,
        summary: DeviceRunSummary(
          deviceLabel: device?.label ?? target.label,
          serial: device?.serial ?? '',
          startedAt: started,
          durationMs: stopwatch.elapsedMilliseconds,
          coldStartMs: coldStartMs,
          screenshots: screenshots,
          logcatFile: logcatFile,
          signedWith: signedWith,
        ),
      );
    }

    await jobDirectory.create(recursive: true);

    // R01 — a ready device that can run this bundle's native code.
    try {
      device = await _ready(target, onProgress);
    } on BundleToolException catch (error) {
      results.add(
        _result('R01', CheckStatus.fail, _titles['R01']!, error.message),
      );
      return finish();
    }
    final serial = device.serial;
    final shared = [
      for (final abi in device.abis)
        if (report.abis.contains(abi)) abi,
    ];
    if (report.abis.isNotEmpty && shared.isEmpty) {
      results.add(
        _result(
          'R01',
          CheckStatus.fail,
          _titles['R01']!,
          '${device.label} chạy ${device.abis.join(', ')}; bundle chỉ có '
              '${report.abis.join(', ')}.',
          hint: 'Chọn thiết bị khác, hoặc build thêm ABI đó.',
        ),
      );
      return finish();
    }
    final minSdk = report.minSdk;
    if (minSdk != null && device.sdkInt != null && device.sdkInt! < minSdk) {
      results.add(
        _result(
          'R01',
          CheckStatus.fail,
          _titles['R01']!,
          '${device.label} là API ${device.sdkInt}, app cần minSdk $minSdk.',
        ),
      );
      return finish();
    }
    results.add(
      _result(
        'R01',
        CheckStatus.pass,
        _titles['R01']!,
        '${device.label}, API ${device.sdkInt ?? '?'}, '
            'ABI ${device.abis.join(', ')}. Dùng ${shared.isEmpty ? 'bản không có native' : shared.first}.',
      ),
    );
    await _adb.shell(serial, const ['input', 'keyevent', 'KEYCODE_WAKEUP']);
    await _adb.shell(serial, const ['wm', 'dismiss-keyguard']);

    // R02 — the APKs Play would serve this exact device.
    onProgress?.call('bundletool build-apks cho $serial');
    final apks = File(p.join(jobDirectory.path, 'device.apks'));
    try {
      await _bundletool.buildDeviceApks(
        bundlePath: report.sourcePath,
        output: apks,
        serial: serial,
        adb: sdk.adb,
        keystore: keystore,
      );
    } on BundleToolException catch (error) {
      results.add(
        _result(
          'R02',
          CheckStatus.fail,
          _titles['R02']!,
          'bundletool build-apks lỗi: ${error.message}',
          hint: keystore == null
              ? 'Không có keystore của project nên bundletool cần '
                    '~/.android/debug.keystore — build debug một app bất kỳ một '
                    'lần để Gradle tạo nó.'
              : '',
        ),
      );
      return finish();
    }
    results.add(
      _result(
        'R02',
        CheckStatus.pass,
        _titles['R02']!,
        'Đã sinh APK cho ${device.label}, ký bằng $signedWith.',
        hint:
            'APK được ký lại, không phải bằng app signing key của Play. '
            'Google Sign-In, Maps, App Check gắn SHA-1 có thể lỗi khi chạy '
            'local dù bản trên Play vẫn đúng.',
      ),
    );

    // R03 — install, clean on an emulator.
    try {
      final install = await _install(
        device: device,
        package: package,
        apks: apks,
        options: options,
        onProgress: onProgress,
      );
      if (install.needsConfirm) needsConfirm = true;
      results.add(install.result);
      if (install.result.status == CheckStatus.fail) return finish();
    } finally {
      if (apks.existsSync()) await apks.delete();
    }

    // R04 — open it and time the cold start.
    onProgress?.call('Mở app');
    await _adb.shell(serial, const ['logcat', '-b', 'all', '-c']);
    final activity = report.launcherActivity;
    final component = activity != null && activity.isNotEmpty
        ? '$package/$activity'
        : await _adb.launcherComponent(serial, package);
    if (component == null) {
      results.add(
        _result(
          'R04',
          CheckStatus.fail,
          _titles['R04']!,
          'Không tìm thấy activity LAUNCHER của $package.',
        ),
      );
      return finish();
    }
    final launch = await _adb.shell(serial, [
      'am',
      'start',
      '-W',
      '-n',
      component,
    ], timeout: const Duration(seconds: 90));
    final start = parseAmStart(launch.output);
    coldStartMs = start.totalTimeMs;
    if (!start.ok) {
      results.add(
        _result(
          'R04',
          CheckStatus.fail,
          _titles['R04']!,
          'am start không mở được $component.',
          items: [if (start.error != null) start.error!],
        ),
      );
      return finish();
    }
    final slow = (coldStartMs ?? 0) > 5000;
    results.add(
      _result(
        'R04',
        slow ? CheckStatus.warn : CheckStatus.pass,
        _titles['R04']!,
        coldStartMs == null
            ? 'Đã mở $component.'
            : 'Cold start ${coldStartMs}ms${slow ? ' — chậm, người dùng sẽ thấy màn trống lâu' : ''}.',
        hint: device.isEmulator && slow
            ? 'Máy ảo chậm hơn máy thật; so với các lần trước trên cùng máy.'
            : '',
      ),
    );

    // R05 — watch the process; R06 — look at the screen.
    final pids = <int>{};
    int? diedAt;
    final watch = options.watchSeconds.clamp(5, 300);
    for (var second = 1; second <= watch; second++) {
      onProgress?.call('Theo dõi $second/$watch giây');
      await _sleep(const Duration(seconds: 1));
      final pid = await _adb.pidOf(serial, package);
      if (pid != null) {
        pids.add(pid);
      } else if (second >= 2) {
        diedAt = second;
        break;
      }
      if (second == 3) {
        final shot = await _screenshot(serial, jobDirectory, 1);
        if (shot != null) screenshots.add(shot);
      }
    }
    String? focused;
    if (diedAt == null) {
      final last = await _screenshot(serial, jobDirectory, 2);
      if (last != null) screenshots.add(last);
      focused = parseResumedActivity(
        (await _adb.shell(serial, const [
          'dumpsys',
          'activity',
          'activities',
        ], timeout: const Duration(seconds: 30))).stdout,
      );
    }

    onProgress?.call('Đọc logcat');
    final crash = await _adb.run(serial, const [
      'logcat',
      '-d',
      '-b',
      'crash',
      '-v',
      'threadtime',
    ]);
    final main = await _adb.run(serial, const [
      'logcat',
      '-d',
      '-b',
      'main,system',
      '-v',
      'threadtime',
    ], timeout: const Duration(seconds: 60));
    logcatFile = 'logcat.txt';
    final log =
        '--- crash ---\n${crash.stdout}\n--- main,system ---\n${main.stdout}';
    await File(p.join(jobDirectory.path, logcatFile)).writeAsString(
      log.length > _maxLogBytes
          ? log.substring(log.length - _maxLogBytes)
          : log,
    );
    final findings = analyzeLogcat(
      crashBuffer: crash.stdout,
      mainLog: main.stdout,
      packageName: package,
      pids: pids,
    );
    results.add(
      _watchResult(
        findings: findings,
        diedAt: diedAt,
        watch: watch,
        focused: focused,
        package: package,
      ),
    );
    results.add(await _screenResult(jobDirectory, screenshots, diedAt != null));

    // Clean up: stop the app, and remove it only where that loses nothing.
    await _adb.shell(serial, ['am', 'force-stop', package]);
    if (options.uninstallAfter && device.isEmulator) {
      await _adb.run(serial, [
        'uninstall',
        package,
      ], timeout: const Duration(minutes: 1));
    }
    return finish();
  }

  Future<AndroidDevice> _ready(
    DeviceTarget target,
    void Function(String)? onProgress,
  ) async {
    final avd = target.avdName;
    if (avd == null) {
      final serial = target.device!.serial;
      final device = (await _adb.devices())
          .where((d) => d.serial == serial)
          .firstOrNull;
      if (device == null) {
        throw BundleToolException('Không còn thấy $serial trong adb devices.');
      }
      if (device.state == 'unauthorized') {
        throw const BundleToolException(
          'Điện thoại chưa cho phép USB debugging — mở khoá máy và bấm Cho '
          'phép trên hộp thoại.',
        );
      }
      if (!device.isReady) {
        throw BundleToolException(
          '${device.serial} đang ở trạng thái ${device.state}, chưa sẵn sàng.',
        );
      }
      return device;
    }

    for (final device in await _adb.devices()) {
      if (device.avdName == avd && device.isReady) return device;
    }
    onProgress?.call('Bật máy ảo $avd');
    await EmulatorLauncher(runner: runner, emulator: sdk.emulator).start(avd);
    final deadline = _now().add(bootTimeout);
    while (_now().isBefore(deadline)) {
      await _sleep(const Duration(seconds: 3));
      for (final device in await _adb.devices()) {
        if (device.avdName == avd && device.isReady) {
          onProgress?.call('Máy ảo $avd đã khởi động');
          // The launcher settles a moment after boot_completed.
          await _sleep(const Duration(seconds: 5));
          return device;
        }
      }
      onProgress?.call('Chờ máy ảo $avd khởi động');
    }
    throw BundleToolException(
      'Máy ảo $avd không khởi động xong trong ${bootTimeout.inSeconds} giây.',
    );
  }

  Future<({CheckResult result, bool needsConfirm})> _install({
    required AndroidDevice device,
    required String package,
    required File apks,
    required DeviceRunOptions options,
    void Function(String)? onProgress,
  }) async {
    final notes = <String>[];
    if (options.freshInstall && device.isEmulator) {
      final removed = await _adb.run(device.serial, [
        'uninstall',
        package,
      ], timeout: const Duration(minutes: 1));
      if (removed.stdout.contains('Success')) {
        notes.add('Đã gỡ bản cũ để cài sạch.');
      }
    }

    onProgress?.call('Cài lên ${device.label}');
    var install = await _bundletool.installApks(
      apks: apks,
      serial: device.serial,
      adb: sdk.adb,
    );
    var code = installFailureCode(install);
    const conflicts = {
      'INSTALL_FAILED_UPDATE_INCOMPATIBLE',
      'INSTALL_FAILED_VERSION_DOWNGRADE',
    };
    if (code != null && conflicts.contains(code)) {
      if (!device.isEmulator && !options.allowUninstall) {
        return (
          result: _result(
            'R03',
            CheckStatus.fail,
            _titles['R03']!,
            'Máy đang có $package ${code == 'INSTALL_FAILED_VERSION_DOWNGRADE' ? 'version cao hơn' : 'ký bằng key khác'}.',
            hint:
                'Phải gỡ bản đang cài (mất dữ liệu app trên máy đó) rồi cài '
                'lại. AMC chỉ làm khi bạn xác nhận.',
            items: [code],
          ),
          needsConfirm: true,
        );
      }
      onProgress?.call('Gỡ bản xung đột rồi cài lại');
      await _adb.run(device.serial, [
        'uninstall',
        package,
      ], timeout: const Duration(minutes: 1));
      notes.add('Đã gỡ bản đang cài ($code) rồi cài lại.');
      install = await _bundletool.installApks(
        apks: apks,
        serial: device.serial,
        adb: sdk.adb,
      );
      code = installFailureCode(install);
    }

    if (code != null || install.exitCode != 0) {
      return (
        result: _result(
          'R03',
          CheckStatus.fail,
          _titles['R03']!,
          _installFailureText[code] ??
              'Cài không thành công: ${BundletoolClient.lastError(install.output)}',
          items: [?code],
        ),
        needsConfirm: false,
      );
    }
    return (
      result: _result(
        'R03',
        CheckStatus.pass,
        _titles['R03']!,
        ['Đã cài $package.', ...notes].join(' '),
      ),
      needsConfirm: false,
    );
  }

  Future<String?> _screenshot(String serial, Directory job, int index) async {
    final capture = await _adb.shell(serial, const [
      'screencap',
      '-p',
      _remoteShot,
    ]);
    if (capture.exitCode != 0) return null;
    final name = 'screen_$index.png';
    final ok = await _adb.pull(serial, _remoteShot, p.join(job.path, name));
    await _adb.shell(serial, const ['rm', '-f', _remoteShot]);
    return ok ? name : null;
  }

  CheckResult _watchResult({
    required LogcatFindings findings,
    required int? diedAt,
    required int watch,
    required String? focused,
    required String package,
  }) {
    final title = 'Chạy $watch giây';
    if (findings.fatal || findings.anr || diedAt != null) {
      final reasons = [
        if (findings.fatal) 'crash',
        if (findings.anr) 'ANR',
        if (diedAt != null) 'process chết ở giây thứ $diedAt',
      ];
      return _result(
        'R05',
        CheckStatus.fail,
        title,
        'App không trụ được: ${reasons.join(', ')}.',
        hint: findings.hint,
        items: findings.lines,
      );
    }
    final away = focused != null && !focused.startsWith('$package/');
    if (findings.lines.isNotEmpty || away) {
      return _result(
        'R05',
        CheckStatus.warn,
        title,
        [
          'App vẫn chạy sau $watch giây.',
          if (findings.errorCount > 0)
            'Log có ${findings.errorCount} lỗi đáng xem.',
          if (away)
            'Màn hình trên cùng lúc kết thúc là $focused, không phải app.',
        ].join(' '),
        hint: findings.hint,
        items: findings.lines,
      );
    }
    return _result(
      'R05',
      CheckStatus.pass,
      title,
      'Không crash, không ANR, không có lỗi Flutter trong log.',
    );
  }

  Future<CheckResult> _screenResult(
    Directory job,
    List<String> screenshots,
    bool died,
  ) async {
    const title = 'Màn hình';
    if (screenshots.isEmpty) {
      return _result(
        'R06',
        CheckStatus.skip,
        title,
        died ? 'App chết trước khi chụp được.' : 'Không chụp được màn hình.',
      );
    }
    final last = File(p.join(job.path, screenshots.last));
    final share = dominantColorShare(await last.readAsBytes());
    if (share != null && share >= 0.97) {
      return _result(
        'R06',
        CheckStatus.warn,
        title,
        'Ảnh cuối gần như một màu (${(share * 100).round()}%) — có thể kẹt ở '
            'splash, màn trắng, hoặc máy đang khoá.',
      );
    }
    return _result(
      'R06',
      CheckStatus.pass,
      title,
      'Đã chụp ${screenshots.length} ảnh; màn hình có nội dung.',
    );
  }

  static const _titles = {
    'R01': 'Thiết bị',
    'R02': 'Sinh APK cho thiết bị',
    'R03': 'Cài đặt',
    'R04': 'Mở app',
    'R05': 'Chạy ổn định',
    'R06': 'Màn hình',
  };

  static const _installFailureText = {
    'INSTALL_FAILED_NO_MATCHING_ABIS':
        'Thiết bị không có ABI nào mà bundle hỗ trợ.',
    'INSTALL_FAILED_OLDER_SDK': 'minSdk của app cao hơn Android của thiết bị.',
    'INSTALL_FAILED_INSUFFICIENT_STORAGE': 'Thiết bị hết dung lượng.',
    'INSTALL_FAILED_TEST_ONLY': 'App đánh dấu testOnly nên không cài được.',
    'INSTALL_FAILED_USER_RESTRICTED':
        'Máy chặn cài qua USB — trên Xiaomi/Oppo bật "Cài qua USB" trong '
        'tuỳ chọn nhà phát triển.',
    'INSTALL_PARSE_FAILED_NO_CERTIFICATES': 'APK không có chữ ký hợp lệ.',
  };
}

CheckResult _result(
  String id,
  CheckStatus status,
  String title,
  String detail, {
  String hint = '',
  List<String> items = const [],
}) {
  return CheckResult(
    id: id,
    group: CheckGroup.run,
    status: status,
    title: title,
    detail: detail,
    hint: hint,
    items: items,
  );
}

String? installFailureCode(BundleProcessResult result) {
  return RegExp(
    r'INSTALL_(?:PARSE_)?FAILED_[A-Z_]+',
  ).firstMatch(result.output)?.group(0);
}

class AmStartResult {
  const AmStartResult({required this.ok, this.totalTimeMs, this.error});

  final bool ok;
  final int? totalTimeMs;
  final String? error;
}

AmStartResult parseAmStart(String output) {
  final error = RegExp(r'^Error.*$', multiLine: true).firstMatch(output);
  final status = RegExp(
    r'^Status:\s*(\S+)',
    multiLine: true,
  ).firstMatch(output);
  final total = RegExp(
    r'^TotalTime:\s*(\d+)',
    multiLine: true,
  ).firstMatch(output);
  final ok = error == null && (status == null || status.group(1) == 'ok');
  return AmStartResult(
    ok: ok && (status != null || total != null),
    totalTimeMs: int.tryParse(total?.group(1) ?? ''),
    error:
        error?.group(0)?.trim() ??
        (status != null && status.group(1) != 'ok'
            ? 'Status: ${status.group(1)}'
            : null),
  );
}

/// `package/activity` on top of the activity stack, or null if unreadable.
String? parseResumedActivity(String dumpsys) {
  final match = RegExp(
    r'(?:topResumedActivity|mResumedActivity|ResumedActivity)[:=]\s*ActivityRecord\{\S+\s+\S+\s+(\S+/\S+)',
  ).firstMatch(dumpsys);
  return match?.group(1);
}

class LogcatFindings {
  const LogcatFindings({
    required this.fatal,
    required this.anr,
    required this.lines,
    this.hint = '',
  });

  final bool fatal;
  final bool anr;

  /// The lines worth reading, most telling first; stack frames under an
  /// error are indented.
  final List<String> lines;

  int get errorCount => lines.where((line) => !line.startsWith(' ')).length;
  final String hint;
}

final _threadtime = RegExp(
  r'^\S+\s+\S+\s+(\d+)\s+\d+\s+([VDIWEF])\s+([^:]*?)\s*:\s?(.*)$',
);

/// Picks crashes, ANRs and errors belonging to [packageName] out of logcat.
LogcatFindings analyzeLogcat({
  required String crashBuffer,
  required String mainLog,
  required String packageName,
  Set<int> pids = const {},
}) {
  final lines = <String>[];
  var fatal = false;
  var hint = '';

  // Java crash: AndroidRuntime writes "Process: <package>, PID: n" under the
  // FATAL EXCEPTION header, then the stack.
  final crashLines = crashBuffer.split('\n');
  for (var i = 0; i < crashLines.length; i++) {
    final line = crashLines[i];
    if (!line.contains('FATAL EXCEPTION')) continue;
    final block = crashLines.skip(i).take(16).toList();
    if (!block.any((l) => l.contains('Process: $packageName'))) continue;
    fatal = true;
    lines.addAll(block.map(_message).where((l) => l.isNotEmpty).take(12));
    break;
  }
  // Native crash: debuggerd names the process between >>> and <<<.
  if (!fatal && crashBuffer.contains('>>> $packageName <<<')) {
    fatal = true;
    lines.addAll(
      crashLines
          .where(
            (l) =>
                l.contains('signal ') ||
                l.contains('Abort message') ||
                l.contains('>>> $packageName <<<'),
          )
          .map(_message)
          .take(6),
    );
  }

  final anr = RegExp(
    'ANR in ${RegExp.escape(packageName)}\\b',
  ).hasMatch(mainLog);
  if (anr) lines.add('ANR in $packageName');

  const interesting = [
    'Unhandled Exception',
    '[ERROR:flutter',
    'MissingPluginException',
    'UnsatisfiedLinkError',
    'ClassNotFoundException',
    'NoClassDefFoundError',
    'NoSuchMethodError',
    'EXCEPTION CAUGHT BY',
  ];
  const maxLines = 30;
  const maxFrames = 6;
  final seen = <String>{};
  final entries = [
    for (final raw in mainLog.split('\n'))
      ?_threadtime.firstMatch(raw.trimRight()),
  ];
  for (var i = 0; i < entries.length; i++) {
    final match = entries[i];
    final pid = int.parse(match.group(1)!);
    final level = match.group(2)!;
    final tag = match.group(3)!;
    final message = match.group(4)!;
    final ours = pids.contains(pid) || (pids.isEmpty && tag == 'flutter');
    if (!ours || (level != 'E' && level != 'F' && tag != 'flutter')) continue;
    if (!interesting.any(message.contains)) continue;
    final text = '$tag: $message';
    if (!seen.add(text) || lines.length >= maxLines) continue;
    lines.add(text);
    // The stack right under the error is what points at the culprit: Dart
    // frames (`#0 ...`) or Java frames (`at ...`) from the same process.
    for (var j = i + 1; j < entries.length && j <= i + maxFrames; j++) {
      final next = entries[j];
      final frame = next.group(4)!.trim();
      if (next.group(1) != match.group(1) ||
          next.group(3) != tag ||
          !(frame.startsWith('#') || frame.startsWith('at '))) {
        break;
      }
      if (lines.length < maxLines) lines.add('    $frame');
    }
    if (message.contains('ClassNotFoundException') ||
        message.contains('NoSuchMethodError') ||
        message.contains('NoClassDefFoundError')) {
      hint =
          'Lỗi thiếu class/method chỉ ở bản release thường do R8 cắt nhầm — '
          'thêm rule -keep vào proguard-rules.pro cho thư viện đó.';
    } else if (message.contains('MissingPluginException') && hint.isEmpty) {
      hint =
          'Plugin native không được đăng ký ở bản release — thường cũng do R8 '
          'hoặc plugin chỉ hỗ trợ một số nền tảng.';
    } else if (message.contains('UnsatisfiedLinkError') && hint.isEmpty) {
      hint = 'Thiếu thư viện native cho ABI của thiết bị.';
    }
  }
  return LogcatFindings(fatal: fatal, anr: anr, lines: lines, hint: hint);
}

String _message(String line) {
  final match = _threadtime.firstMatch(line.trimRight());
  if (match == null) return line.trim();
  return '${match.group(3)}: ${match.group(4)}'.trim();
}
