import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'android_toolchain.dart';

/// Where the Android SDK lives: ANDROID_HOME, ANDROID_SDK_ROOT, then the
/// Android Studio default. `adb` falls back to PATH when none is found.
class AndroidSdk {
  const AndroidSdk({this.root});

  final String? root;

  static AndroidSdk locate({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final candidates = [
      env['ANDROID_HOME'],
      env['ANDROID_SDK_ROOT'],
      if (Platform.isWindows)
        p.join(env['LOCALAPPDATA'] ?? '', 'Android', 'Sdk'),
      if (Platform.isMacOS)
        p.join(env['HOME'] ?? '', 'Library', 'Android', 'sdk'),
      if (Platform.isLinux) p.join(env['HOME'] ?? '', 'Android', 'Sdk'),
    ];
    for (final candidate in candidates) {
      if (candidate == null || candidate.trim().isEmpty) continue;
      if (Directory(p.join(candidate, 'platform-tools')).existsSync()) {
        return AndroidSdk(root: candidate);
      }
    }
    return const AndroidSdk();
  }

  static String get _exe => Platform.isWindows ? '.exe' : '';

  String get adb {
    final sdk = root;
    if (sdk != null) {
      final path = p.join(sdk, 'platform-tools', 'adb$_exe');
      if (File(path).existsSync()) return path;
    }
    return 'adb';
  }

  String? get emulator {
    final sdk = root;
    if (sdk == null) return null;
    final path = p.join(sdk, 'emulator', 'emulator$_exe');
    return File(path).existsSync() ? path : null;
  }
}

class AndroidDevice {
  const AndroidDevice({
    required this.serial,
    required this.state,
    this.model = '',
    this.manufacturer = '',
    this.release = '',
    this.sdkInt,
    this.abis = const [],
    this.isEmulator = false,
    this.avdName,
    this.bootCompleted = false,
  });

  final String serial;

  /// `device`, `offline`, `unauthorized`…
  final String state;
  final String model;
  final String manufacturer;
  final String release;
  final int? sdkInt;
  final List<String> abis;
  final bool isEmulator;
  final String? avdName;
  final bool bootCompleted;

  bool get isReady => state == 'device' && bootCompleted;

  String get label {
    final name = isEmulator && avdName != null ? avdName! : model;
    final android = release.isEmpty ? '' : ' · Android $release';
    final kind = isEmulator ? 'máy ảo' : 'máy thật';
    return '$name ($kind$android)';
  }
}

/// A device the user can pick: one that is connected, or an AVD that is
/// switched off and will be started.
class DeviceTarget {
  const DeviceTarget.device(AndroidDevice this.device) : avdName = null;
  const DeviceTarget.avd(String this.avdName) : device = null;

  final AndroidDevice? device;
  final String? avdName;

  bool get isEmulator => device?.isEmulator ?? true;

  /// Survives a restart: the AVD name for emulators, the serial otherwise.
  String get key => device?.avdName ?? avdName ?? device!.serial;

  String get label => device?.label ?? '$avdName (máy ảo đang tắt — sẽ bật)';
}

/// The `adb` commands the device run needs, each with a timeout so a hung
/// device never hangs the page.
class AdbClient {
  const AdbClient({required this.runner, required this.adb});

  final BundleProcessRunner runner;
  final String adb;

  Future<BundleProcessResult> run(
    String serial,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    return runner.run(adb, ['-s', serial, ...arguments], timeout: timeout);
  }

  Future<BundleProcessResult> shell(
    String serial,
    List<String> command, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    return run(serial, ['shell', ...command], timeout: timeout);
  }

  Future<List<AndroidDevice>> devices() async {
    final result = await runner.run(adb, const [
      'devices',
    ], timeout: const Duration(seconds: 15));
    if (result.missingExecutable) {
      throw const BundleToolException(
        'Không tìm thấy adb. Cài Android SDK platform-tools.',
      );
    }
    final devices = <AndroidDevice>[];
    for (final line in result.stdout.split('\n').skip(1)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2 || parts[0].isEmpty) continue;
      final serial = parts[0];
      final state = parts[1];
      if (state != 'device') {
        devices.add(
          AndroidDevice(
            serial: serial,
            state: state,
            isEmulator: serial.startsWith('emulator-'),
          ),
        );
        continue;
      }
      devices.add(await describe(serial));
    }
    return devices;
  }

  Future<AndroidDevice> describe(String serial) async {
    final props = parseGetprop((await shell(serial, const ['getprop'])).stdout);
    final isEmulator =
        serial.startsWith('emulator-') || props['ro.kernel.qemu'] == '1';
    String? avd;
    if (isEmulator) {
      final result = await run(serial, const [
        'emu',
        'avd',
        'name',
      ], timeout: const Duration(seconds: 10));
      final name = result.stdout
          .split('\n')
          .map((line) => line.trim())
          .firstWhere((line) => line.isNotEmpty, orElse: () => '');
      if (name.isNotEmpty && name != 'OK' && !name.startsWith('KO')) {
        avd = name;
      }
    }
    return AndroidDevice(
      serial: serial,
      state: 'device',
      model: props['ro.product.model'] ?? '',
      manufacturer: props['ro.product.manufacturer'] ?? '',
      release: props['ro.build.version.release'] ?? '',
      sdkInt: int.tryParse(props['ro.build.version.sdk'] ?? ''),
      abis: (props['ro.product.cpu.abilist'] ?? '')
          .split(',')
          .map((abi) => abi.trim())
          .where((abi) => abi.isNotEmpty)
          .toList(),
      isEmulator: isEmulator,
      avdName: avd,
      bootCompleted: props['sys.boot_completed'] == '1',
    );
  }

  Future<int?> pidOf(String serial, String packageName) async {
    final result = await shell(serial, ['pidof', packageName]);
    return int.tryParse(result.stdout.trim().split(RegExp(r'\s+')).first);
  }

  /// `package/activity` of the launcher entry, as the package manager sees it.
  Future<String?> launcherComponent(String serial, String packageName) async {
    final result = await shell(serial, [
      'cmd',
      'package',
      'resolve-activity',
      '--brief',
      '-c',
      'android.intent.category.LAUNCHER',
      packageName,
    ]);
    final line = result.stdout
        .split('\n')
        .map((l) => l.trim())
        .lastWhere((l) => l.isNotEmpty, orElse: () => '');
    return line.startsWith('$packageName/') ? line : null;
  }

  Future<bool> pull(String serial, String remote, String local) async {
    final result = await run(serial, [
      'pull',
      remote,
      local,
    ], timeout: const Duration(seconds: 60));
    return result.exitCode == 0 && File(local).existsSync();
  }
}

Map<String, String> parseGetprop(String output) {
  final values = <String, String>{};
  for (final match in RegExp(
    r'^\[([^\]]+)\]:\s*\[(.*)\]\s*$',
    multiLine: true,
  ).allMatches(output)) {
    values[match.group(1)!] = match.group(2)!;
  }
  return values;
}

/// Lists and starts AVDs.
class EmulatorLauncher {
  const EmulatorLauncher({required this.runner, required this.emulator});

  final BundleProcessRunner runner;
  final String? emulator;

  Future<List<String>> listAvds() async {
    final path = emulator;
    if (path == null) return const [];
    final result = await runner.run(path, const [
      '-list-avds',
    ], timeout: const Duration(seconds: 20));
    return result.stdout
        .split('\n')
        .map((line) => line.trim())
        // The emulator prints INFO/WARNING lines on some setups.
        .where((line) => line.isNotEmpty && !line.contains(' '))
        .toList();
  }

  /// Starts [avd] without saving a snapshot on exit, so every run begins from
  /// the same state rather than whatever the last test left behind.
  Future<void> start(String avd) async {
    final path = emulator;
    if (path == null) {
      throw const BundleToolException(
        'Không tìm thấy emulator trong Android SDK.',
      );
    }
    final started = await runner.startDetached(path, [
      '-avd',
      avd,
      '-no-snapshot-save',
    ]);
    if (!started) {
      throw BundleToolException('Không chạy được emulator cho $avd.');
    }
  }
}
