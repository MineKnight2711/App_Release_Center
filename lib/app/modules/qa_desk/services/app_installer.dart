import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../bundle_check/services/android_device.dart';
import '../../bundle_check/services/android_toolchain.dart';

class AppInstallException implements Exception {
  const AppInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Puts the right build of an app on a device before a scenario runs.
///
/// "Right" means the environment's build: when staging and production share
/// one package, only the build installed tells which backend the app talks
/// to, so QA Desk records what it installed and reinstalls when the
/// environment or the build changes.
class AppInstaller {
  AppInstaller({
    required this.recordFile,
    String? adb,
    BundleProcessRunner runner = const IoBundleProcessRunner(),
    this.bundletoolJar,
  }) : _adb = adb ?? AndroidSdk.locate().adb,
       _runner = runner;

  /// Remembers which environment's build is on which device.
  final File recordFile;
  final String _adb;
  final BundleProcessRunner _runner;

  /// The AAB checker's verified bundletool, for `.aab` builds.
  final Future<File?> Function()? bundletoolJar;

  Future<bool> isInstalled(String serial, String appId) async {
    final result = await _runner.run(_adb, [
      '-s',
      serial,
      'shell',
      'pm',
      'path',
      appId,
    ], timeout: const Duration(seconds: 20));
    return result.exitCode == 0 && result.stdout.contains('package:');
  }

  /// Makes sure [appId] runs [environment]'s build on [serial].
  ///
  /// Returns a line for the run log saying what was done.
  Future<String> ensure({
    required String serial,
    required String appId,
    required String environment,
    required String projectPath,
    required String build,
    required bool emulator,
  }) async {
    final key = '$serial|$appId';
    final records = _readRecords();
    final installed = await isInstalled(serial, appId);
    if (build.isEmpty) {
      if (!installed) {
        throw AppInstallException(
          'App $appId chưa cài trên thiết bị, và môi trường "$environment" '
          'không khai build để QA Desk cài.',
        );
      }
      final recorded = records[key]?['environment'];
      return recorded == null || recorded == environment
          ? 'App: dùng bản đang cài ($appId).'
          : 'App: dùng bản đang cài, nhưng lần trước QA Desk cài bản '
                '"$recorded"; môi trường "$environment" không khai build nên '
                'không xác minh được.';
    }

    final file = File(p.isAbsolute(build) ? build : p.join(projectPath, build));
    if (!file.existsSync()) {
      throw AppInstallException('Không thấy build ${file.path}.');
    }
    final stamp = file.lastModifiedSync().toIso8601String();
    final record = records[key];
    if (installed &&
        record != null &&
        record['environment'] == environment &&
        record['build'] == file.path &&
        record['modified'] == stamp) {
      return 'App: bản $environment đã cài sẵn.';
    }

    final apk = file.path.toLowerCase().endsWith('.aab')
        ? await _universalApk(file)
        : file;
    var result = await _install(serial, apk.path);
    if (!result.ok && emulator && result.signatureMismatch) {
      // A different signature cannot be upgraded in place. On an emulator a
      // clean install is the point; a real phone keeps its data.
      await _runner.run(_adb, ['-s', serial, 'uninstall', appId]);
      result = await _install(serial, apk.path);
    }
    if (!result.ok) {
      throw AppInstallException(
        result.signatureMismatch
            ? 'Bản cài trên điện thoại ký khác build này. Gỡ app trên điện '
                  'thoại rồi chạy lại (QA Desk không tự gỡ trên máy thật).'
            : 'Cài app lỗi: ${result.message}',
      );
    }
    records[key] = {
      'environment': environment,
      'build': file.path,
      'modified': stamp,
    };
    await _writeRecords(records);
    return 'App: đã cài bản $environment từ ${p.basename(file.path)}.';
  }

  Future<File> _universalApk(File bundle) async {
    final jar = await bundletoolJar?.call();
    if (jar == null) {
      throw const AppInstallException(
        'Build là AAB: cần bundletool. Mở Kiểm tra AAB và bấm Tải bundletool.',
      );
    }
    final client = BundletoolClient(
      runner: _runner,
      tools: JavaTools.locate(),
      jar: jar,
    );
    final output = Directory(p.join(Directory.systemTemp.path, 'qa_desk_apk'));
    try {
      return await client.buildUniversalApk(
        bundlePath: bundle.path,
        outputDirectory: output,
        apkFileName: 'qa-universal.apk',
      );
    } on BundleToolException catch (error) {
      throw AppInstallException('Không dựng được APK từ AAB: ${error.message}');
    }
  }

  Future<_InstallResult> _install(String serial, String apk) async {
    final result = await _runner.run(_adb, [
      '-s',
      serial,
      'install',
      '-r',
      '-d',
      apk,
    ], timeout: const Duration(minutes: 5));
    final output = result.output;
    return _InstallResult(
      ok: result.exitCode == 0 && output.contains('Success'),
      signatureMismatch:
          output.contains('INSTALL_FAILED_UPDATE_INCOMPATIBLE') ||
          output.contains('signatures do not match'),
      message: output
          .split('\n')
          .lastWhere(
            (line) => line.trim().isNotEmpty,
            orElse: () => 'adb install thất bại',
          ),
    );
  }

  Map<String, Map<String, dynamic>> _readRecords() {
    if (!recordFile.existsSync()) return {};
    try {
      final decoded = jsonDecode(recordFile.readAsStringSync());
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map)
            entry.key.toString(): Map<String, dynamic>.from(entry.value as Map),
      };
    } on FormatException {
      return {};
    }
  }

  Future<void> _writeRecords(Map<String, Map<String, dynamic>> records) async {
    await recordFile.parent.create(recursive: true);
    await recordFile.writeAsString(jsonEncode(records), flush: true);
  }
}

class _InstallResult {
  const _InstallResult({
    required this.ok,
    required this.signatureMismatch,
    required this.message,
  });

  final bool ok;
  final bool signatureMismatch;
  final String message;
}
