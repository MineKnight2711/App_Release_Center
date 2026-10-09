import 'dart:io';
import 'dart:typed_data';

import 'package:app_management_center/app/modules/bundle_check/models/bundle_check_models.dart';
import 'package:app_management_center/app/modules/bundle_check/services/android_device.dart';
import 'package:app_management_center/app/modules/bundle_check/services/android_toolchain.dart';
import 'package:app_management_center/app/modules/bundle_check/services/device_smoke_runner.dart';
import 'package:app_management_center/app/modules/bundle_check/services/screenshot_analysis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'bundle_check_fixtures.dart';

const _package = 'vn.amc.demo';

final _busyScreen = pngOf(60, 120, (x, y) => [x * 4, y * 2, (x + y) % 256]);
final _blankScreen = pngOf(60, 120, (x, y) => [250, 250, 250]);

/// Plays adb and bundletool from a script, recording every call.
class _Device implements BundleProcessRunner {
  _Device({
    this.serial = 'emulator-5554',
    this.emulator = true,
    this.abis = 'x86_64,arm64-v8a',
    this.connected = true,
    this.installOutputs = const ['Success'],
    this.dieAfterPidChecks,
    this.crashBuffer = '',
    Uint8List? screen,
  }) : screen = screen ?? _busyScreen;

  final String serial;
  final bool emulator;
  final String abis;
  final String avd = 'ZFold_3';
  bool connected;
  final List<String> installOutputs;
  final int? dieAfterPidChecks;
  final String crashBuffer;
  final String mainLog = '';
  final Uint8List screen;

  final calls = <List<String>>[];
  var _installs = 0;
  var _pidChecks = 0;
  var detachedStarts = 0;

  bool called(bool Function(List<String> call) test) => calls.any(test);

  @override
  Future<bool> startDetached(String executable, List<String> arguments) async {
    calls.add([executable, ...arguments]);
    detachedStarts++;
    connected = true;
    return true;
  }

  @override
  Future<BundleProcessResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    calls.add([executable, ...arguments]);
    BundleProcessResult out(String stdout, [int code = 0]) =>
        BundleProcessResult(exitCode: code, stdout: stdout);

    if (arguments.contains('build-apks')) {
      final output = arguments
          .firstWhere((a) => a.startsWith('--output='))
          .substring('--output='.length);
      File(output).writeAsStringSync('apks');
      return out('');
    }
    if (arguments.contains('install-apks')) {
      final text =
          installOutputs[_installs.clamp(0, installOutputs.length - 1)];
      _installs++;
      return out(text, text.contains('INSTALL_') ? 1 : 0);
    }
    if (arguments.contains('-list-avds')) return out('$avd\n');
    if (arguments.length == 1 && arguments.first == 'devices') {
      return out(
        'List of devices attached\n${connected ? '$serial\tdevice\n' : ''}',
      );
    }

    final command = arguments.skip(2).toList();
    final joined = command.join(' ');
    if (joined == 'shell getprop') {
      return out(
        '[ro.product.model]: [sdk_gphone64_x86_64]\n'
        '[ro.build.version.release]: [16]\n'
        '[ro.build.version.sdk]: [36]\n'
        '[ro.product.cpu.abilist]: [$abis]\n'
        '[ro.kernel.qemu]: [${emulator ? 1 : 0}]\n'
        '[sys.boot_completed]: [1]\n',
      );
    }
    if (joined == 'emu avd name') return out('$avd\r\nOK\r\n');
    if (joined.startsWith('uninstall')) return out('Success\n');
    if (joined.startsWith('shell am start')) {
      return out(
        'Starting: Intent { cmp=$_package/.MainActivity }\n'
        'Status: ok\nLaunchState: COLD\nTotalTime: 1234\nWaitTime: 1250\n'
        'Complete\n',
      );
    }
    if (joined.startsWith('shell pidof')) {
      _pidChecks++;
      final dead = dieAfterPidChecks != null && _pidChecks > dieAfterPidChecks!;
      return out(dead ? '' : '4321\n', dead ? 1 : 0);
    }
    if (joined.startsWith('pull')) {
      File(command.last).writeAsBytesSync(screen);
      return out('1 file pulled');
    }
    if (joined.startsWith('shell dumpsys activity activities')) {
      return out(
        '  topResumedActivity=ActivityRecord{1 u0 $_package/.MainActivity t9}\n',
      );
    }
    if (joined.startsWith('logcat -d -b crash')) return out(crashBuffer);
    if (joined.startsWith('logcat -d -b main,system')) return out(mainLog);
    return out('');
  }
}

BundleCheckReport _report(
  String sourcePath, {
  List<String> abis = const ['arm64-v8a', 'x86_64'],
}) {
  return BundleCheckReport(
    id: 'job',
    createdAt: DateTime(2026, 9, 30),
    sourcePath: sourcePath,
    fileName: 'app.aab',
    fileSize: 1,
    sha256: 'x',
    packageName: _package,
    versionName: '1.0.0',
    versionCode: 1,
    minSdk: 24,
    targetSdk: 36,
    permissions: const [],
    abis: abis,
    estimatedArm64DownloadBytes: 0,
    results: const [],
    launcherActivity: '$_package.MainActivity',
  );
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('bundle_device'));
  tearDown(() => temp.deleteSync(recursive: true));

  Future<DeviceRunOutcome> runWith(
    _Device device, {
    DeviceTarget? target,
    DeviceRunOptions options = const DeviceRunOptions(watchSeconds: 5),
    List<String> abis = const ['arm64-v8a', 'x86_64'],
  }) async {
    final aab = File(p.join(temp.path, 'app.aab'))..writeAsStringSync('aab');
    // A stand-in SDK folder, so the emulator binary is "installed".
    final exe = Platform.isWindows ? '.exe' : '';
    final sdk = Directory(p.join(temp.path, 'sdk'));
    for (final tool in ['platform-tools/adb$exe', 'emulator/emulator$exe']) {
      File(p.join(sdk.path, tool)).createSync(recursive: true);
    }
    final runner = DeviceSmokeRunner(
      runner: device,
      tools: const JavaTools(java: 'java', keytool: 'keytool'),
      sdk: AndroidSdk(root: sdk.path),
      bundletoolJar: File('bundletool.jar'),
      sleep: (_) async {},
    );
    return runner.run(
      report: _report(aab.path, abis: abis),
      target:
          target ??
          DeviceTarget.device(
            AndroidDevice(
              serial: device.serial,
              state: 'device',
              isEmulator: device.emulator,
              bootCompleted: true,
            ),
          ),
      jobDirectory: Directory(p.join(temp.path, 'job')),
      options: options,
    );
  }

  CheckStatus status(DeviceRunOutcome outcome, String id) =>
      outcome.results.singleWhere((r) => r.id == id).status;

  test('máy ảo: cài sạch, mở, theo dõi, chụp màn hình — đều đạt', () async {
    final device = _Device();
    final outcome = await runWith(device);

    expect(outcome.results.map((r) => r.id), [
      'R01',
      'R02',
      'R03',
      'R04',
      'R05',
      'R06',
    ]);
    for (final result in outcome.results) {
      expect(
        result.status,
        CheckStatus.pass,
        reason: '${result.id}: ${result.detail}',
      );
    }
    expect(outcome.summary.coldStartMs, 1234);
    expect(outcome.summary.screenshots, ['screen_1.png', 'screen_2.png']);
    expect(File(p.join(temp.path, 'job', 'logcat.txt')).existsSync(), isTrue);
    // A clean install on the emulator: the old copy goes first.
    final uninstall = device.calls.indexWhere((c) => c.contains('uninstall'));
    final install = device.calls.indexWhere((c) => c.contains('install-apks'));
    expect(uninstall, lessThan(install));
    // The device APK set is not left behind in the job folder.
    expect(File(p.join(temp.path, 'job', 'device.apks')).existsSync(), isFalse);
    // Launched straight from the manifest's activity.
    expect(
      device.called((c) => c.contains('$_package/$_package.MainActivity')),
      isTrue,
    );
  });

  test('app chết và có FATAL EXCEPTION → R05 lỗi kèm stack', () async {
    final device = _Device(
      dieAfterPidChecks: 1,
      crashBuffer:
          '09-30 10:00:01.000  4321  4321 E AndroidRuntime: FATAL EXCEPTION: main\n'
          '09-30 10:00:01.000  4321  4321 E AndroidRuntime: Process: $_package, PID: 4321\n'
          '09-30 10:00:01.000  4321  4321 E AndroidRuntime: java.lang.RuntimeException: boom\n',
    );
    final outcome = await runWith(device);
    final watch = outcome.results.singleWhere((r) => r.id == 'R05');
    expect(watch.status, CheckStatus.fail);
    expect(watch.detail, contains('crash'));
    expect(watch.items.join('\n'), contains('RuntimeException: boom'));
    expect(status(outcome, 'R06'), CheckStatus.skip);
  });

  test('màn hình một màu sau khi mở → R06 cảnh báo', () async {
    final outcome = await runWith(_Device(screen: _blankScreen));
    expect(status(outcome, 'R06'), CheckStatus.warn);
  });

  test('máy thật khác chữ ký: không tự gỡ, hỏi trước', () async {
    final device = _Device(
      serial: 'R5CXA1X0GLW',
      emulator: false,
      abis: 'arm64-v8a',
      installOutputs: const [
        'Error: INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match',
        'Success',
      ],
    );
    final outcome = await runWith(device);
    expect(status(outcome, 'R03'), CheckStatus.fail);
    expect(outcome.needsUninstallConfirm, isTrue);
    expect(device.called((c) => c.contains('uninstall')), isFalse);
    expect(status(outcome, 'R04'), CheckStatus.skip);

    final confirmed = _Device(
      serial: 'R5CXA1X0GLW',
      emulator: false,
      abis: 'arm64-v8a',
      installOutputs: const [
        'Error: INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match',
        'Success',
      ],
    );
    final retried = await runWith(
      confirmed,
      options: const DeviceRunOptions(watchSeconds: 5, allowUninstall: true),
    );
    expect(status(retried, 'R03'), CheckStatus.pass);
    expect(confirmed.called((c) => c.contains('uninstall')), isTrue);
  });

  test('máy ảo xung đột chữ ký thì tự gỡ và cài lại', () async {
    final device = _Device(
      installOutputs: const ['INSTALL_FAILED_UPDATE_INCOMPATIBLE', 'Success'],
    );
    final outcome = await runWith(
      device,
      options: const DeviceRunOptions(watchSeconds: 5, freshInstall: false),
    );
    expect(status(outcome, 'R03'), CheckStatus.pass);
    expect(
      outcome.results.singleWhere((r) => r.id == 'R03').detail,
      contains('INSTALL_FAILED_UPDATE_INCOMPATIBLE'),
    );
  });

  test('thiết bị không có ABI của bundle → R01 lỗi, phần sau bỏ qua', () async {
    final outcome = await runWith(
      _Device(abis: 'armeabi-v7a'),
      abis: const ['arm64-v8a'],
    );
    expect(status(outcome, 'R01'), CheckStatus.fail);
    expect(outcome.results.skip(1).map((r) => r.status).toSet(), {
      CheckStatus.skip,
    });
  });

  test('AVD đang tắt thì bật rồi chờ khởi động', () async {
    final device = _Device(connected: false);
    final outcome = await runWith(
      device,
      target: const DeviceTarget.avd('ZFold_3'),
    );
    expect(device.detachedStarts, 1);
    expect(
      device.calls.firstWhere((c) => c.contains('-avd')),
      containsAll(['-avd', 'ZFold_3', '-no-snapshot-save']),
    );
    expect(status(outcome, 'R01'), CheckStatus.pass);
  });

  group('Đọc log', () {
    test('lỗi Flutter của đúng process, gợi ý R8 khi thiếu class', () {
      final findings = analyzeLogcat(
        crashBuffer: '',
        mainLog:
            '09-30 10:00:01.000  4321  4400 E flutter : [ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: Null check operator\n'
            '09-30 10:00:01.000  4321  4400 E flutter : #0      Navigator.of (package:flutter/src/widgets/navigator.dart:2937)\n'
            '09-30 10:00:01.000  4321  4400 E flutter : #1      showDialog (package:flutter/src/material/dialog.dart:1642)\n'
            '09-30 10:00:01.000  9999  9999 E flutter : Unhandled Exception: someone else\n'
            '09-30 10:00:02.000  4321  4321 E AndroidRuntime: java.lang.ClassNotFoundException: com.x.Y\n'
            '09-30 10:00:03.000  4321  4321 I flutter : hello\n',
        packageName: _package,
        pids: {4321},
      );
      expect(findings.fatal, isFalse);
      expect(findings.lines, hasLength(4));
      expect(findings.lines.first, contains('Null check operator'));
      // The Dart stack follows the error, indented.
      expect(findings.lines[1], startsWith('    #0      Navigator.of'));
      expect(findings.lines[2], startsWith('    #1      showDialog'));
      expect(findings.hint, contains('R8'));
    });

    test('ANR và crash native', () {
      final findings = analyzeLogcat(
        crashBuffer:
            '09-30 10:00:01.000  1  1 F DEBUG   : pid: 4321, name: ui  >>> $_package <<<\n'
            '09-30 10:00:01.000  1  1 F DEBUG   : signal 11 (SIGSEGV)\n',
        mainLog:
            '09-30 10:00:01.000  500  600 E ActivityManager: ANR in $_package (x)\n',
        packageName: _package,
      );
      expect(findings.fatal, isTrue);
      expect(findings.anr, isTrue);
    });

    test('am start lỗi, activity trên cùng, mã lỗi cài đặt', () {
      final failed = parseAmStart(
        'Starting: Intent\nError: Activity class {x/y} does not exist.\n',
      );
      expect(failed.ok, isFalse);
      expect(failed.error, contains('does not exist'));
      expect(
        parseResumedActivity(
          'topResumedActivity=ActivityRecord{161706271 u0 com.google.launcher/.Home t2}',
        ),
        'com.google.launcher/.Home',
      );
      expect(
        installFailureCode(
          const BundleProcessResult(
            exitCode: 1,
            stderr: 'Failure [INSTALL_FAILED_OLDER_SDK: Requires newer sdk]',
          ),
        ),
        'INSTALL_FAILED_OLDER_SDK',
      );
      expect(parseGetprop('[ro.product.model]: [Pixel 8]\n[x]: []\n'), {
        'ro.product.model': 'Pixel 8',
        'x': '',
      });
    });
  });

  group('Ảnh màn hình', () {
    test('ảnh có nội dung vs ảnh một màu', () {
      expect(dominantColorShare(_busyScreen)!, lessThan(0.5));
      expect(dominantColorShare(_blankScreen), 1.0);
    });

    test('giải đúng các bộ lọc Sub và Up', () {
      for (final filter in [1, 2]) {
        final png = pngOf(40, 40, (x, y) => [x * 6, y * 6, 90], filter: filter);
        expect(
          dominantColorShare(png),
          dominantColorShare(pngOf(40, 40, (x, y) => [x * 6, y * 6, 90])),
          reason: 'filter $filter',
        );
      }
    });

    test('PNG lạ hoặc hỏng thì không đoán', () {
      expect(
        dominantColorShare(Uint8List.fromList(List.filled(40, 1))),
        isNull,
      );
    });
  });
}
