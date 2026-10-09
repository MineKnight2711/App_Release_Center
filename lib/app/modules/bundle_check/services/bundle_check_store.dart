import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/bundle_check_models.dart';

/// Keeps finished reports and per-package overrides on this machine, under
/// `<app support>/bundle_check/`.
///
/// Each check is a folder `jobs/<id>/` holding `report.json` plus whatever it
/// produced (a universal APK). Only the newest [keepJobs] survive.
class BundleCheckStore {
  BundleCheckStore({Directory? root, this.keepJobs = 20}) : _root = root;

  static Future<BundleCheckStore> forApp() async {
    final support = await getApplicationSupportDirectory();
    return BundleCheckStore(
      root: Directory(p.join(support.path, 'bundle_check')),
    );
  }

  Directory? _root;
  final int keepJobs;

  Future<Directory> get root async {
    return _root ??= Directory(
      p.join((await getApplicationSupportDirectory()).path, 'bundle_check'),
    );
  }

  Future<Directory> get toolsDirectory async =>
      Directory(p.join((await root).path, 'tools'));

  Future<Directory> jobDirectory(String id) async =>
      Directory(p.join((await root).path, 'jobs', id));

  Future<void> save(BundleCheckReport report) async {
    final directory = await jobDirectory(report.id);
    await directory.create(recursive: true);
    await File(p.join(directory.path, 'report.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
      flush: true,
    );
    await _prune();
  }

  /// Newest first. A report that fails to parse is skipped, not fatal.
  Future<List<BundleCheckReport>> history() async {
    final jobs = Directory(p.join((await root).path, 'jobs'));
    if (!jobs.existsSync()) return const [];
    final reports = <BundleCheckReport>[];
    for (final entity in jobs.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final file = File(p.join(entity.path, 'report.json'));
      if (!file.existsSync()) continue;
      try {
        final json = jsonDecode(await file.readAsString());
        if (json is Map) {
          reports.add(
            BundleCheckReport.fromJson(Map<String, Object?>.from(json)),
          );
        }
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return reports;
  }

  /// The latest earlier report for [packageName] of a different file — what a
  /// new build is compared against. Re-checking the same file is not a diff.
  Future<BundleCheckReport?> previousFor(
    String packageName, {
    required String excludingSha256,
  }) async {
    for (final report in await history()) {
      if (report.packageName == packageName &&
          report.sha256 != excludingSha256) {
        return report;
      }
    }
    return null;
  }

  Future<Map<String, EnvContractOverride>> readOverrides() async {
    final file = File(p.join((await root).path, 'overrides.json'));
    if (!file.existsSync()) return {};
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return {};
      return {
        for (final entry in json.entries)
          if (entry.value is Map)
            '${entry.key}': EnvContractOverride.fromJson(
              Map<String, Object?>.from(entry.value as Map),
            ),
      };
    } on FormatException {
      return {};
    } on FileSystemException {
      return {};
    }
  }

  Future<EnvContractOverride?> overrideFor(String packageName) async {
    return (await readOverrides())[packageName];
  }

  Future<void> saveOverride(
    String packageName,
    EnvContractOverride value,
  ) async {
    final all = await readOverrides()
      ..[packageName] = value;
    final directory = await root;
    await directory.create(recursive: true);
    await File(p.join(directory.path, 'overrides.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        for (final entry in all.entries) entry.key: entry.value.toJson(),
      }),
      flush: true,
    );
  }

  Future<DeviceRunPreferences> readDevicePreferences() async {
    final file = File(p.join((await root).path, 'device.json'));
    if (!file.existsSync()) return const DeviceRunPreferences();
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map
          ? DeviceRunPreferences.fromJson(Map<String, Object?>.from(json))
          : const DeviceRunPreferences();
    } on FormatException {
      return const DeviceRunPreferences();
    } on FileSystemException {
      return const DeviceRunPreferences();
    }
  }

  Future<void> saveDevicePreferences(DeviceRunPreferences value) async {
    final directory = await root;
    await directory.create(recursive: true);
    await File(
      p.join(directory.path, 'device.json'),
    ).writeAsString(jsonEncode(value.toJson()), flush: true);
  }

  Future<void> _prune() async {
    final reports = await history();
    for (final report in reports.skip(keepJobs)) {
      final directory = await jobDirectory(report.id);
      try {
        if (directory.existsSync()) await directory.delete(recursive: true);
      } on FileSystemException {
        continue;
      }
    }
  }
}
