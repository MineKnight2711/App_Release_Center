import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// QA Desk's own folder inside AMC's app-support directory.
///
/// The standalone app wrote `sources.json`, its database and `artifacts/`
/// straight into its app-support root. Inside AMC they get a folder of their
/// own, like `plan_studio/` and `bundle_check/`, so nothing lands beside AMC's
/// preferences.
Future<String> qaDeskRoot() async => p.join(
  (await getApplicationSupportDirectory()).path,
  QaDeskStorage.folderName,
);

enum QaDeskImportOutcome {
  /// No standalone data on this machine, or QA Desk already has its own.
  skipped,

  /// The standalone app's data was copied in.
  imported,

  /// Copying failed; the standalone data is untouched and QA Desk starts empty.
  failed,
}

class QaDeskImportResult {
  const QaDeskImportResult({
    required this.outcome,
    this.legacyPath = '',
    this.copiedFiles = 0,
    this.relinkedPaths = 0,
    this.error = '',
  });

  static const skipped = QaDeskImportResult(
    outcome: QaDeskImportOutcome.skipped,
  );

  final QaDeskImportOutcome outcome;
  final String legacyPath;
  final int copiedFiles;

  /// Log and screenshot paths in the run history pointed back at the new
  /// folder.
  final int relinkedPaths;
  final String error;
}

/// Where QA Desk keeps its files, and the one-time move from the standalone
/// Fiza QA Desk app.
class QaDeskStorage {
  const QaDeskStorage({required this.root, this.legacyRoot});

  static const folderName = 'qa_desk';
  static const databaseName = 'qa_desk.db';
  static const sourcesName = 'sources.json';
  static const artifactsName = 'artifacts';
  static const importMarkerName = 'imported_from.txt';
  static const legacyDatabaseName = 'fiza_qa_desk.db';

  /// Resolves both folders for this machine.
  ///
  /// The standalone app's VERSIONINFO named it `vn.fizahub.qa` /
  /// `Fiza QA Desk`, so on Windows its data sits beside AMC's own
  /// `%APPDATA%\<company>\<product>` folder. It only ever shipped for Windows.
  static Future<QaDeskStorage> forApp() async {
    final support = (await getApplicationSupportDirectory()).path;
    return QaDeskStorage(
      root: p.join(support, folderName),
      legacyRoot: Platform.isWindows
          ? p.join(
              p.dirname(p.dirname(support)),
              'vn.fizahub.qa',
              'Fiza QA Desk',
            )
          : null,
    );
  }

  final String root;
  final String? legacyRoot;

  String get databasePath => p.join(root, databaseName);
  String get sourcesPath => p.join(root, sourcesName);
  String get artifactsPath => p.join(root, artifactsName);

  /// Copies the standalone app's sources, history and artifacts in, once.
  ///
  /// Runs only while [root] is missing or empty, so it never overwrites what
  /// QA Desk has already written. Everything is assembled in a sibling staging
  /// folder and renamed into place at the end: a failure part-way leaves no
  /// half-imported workspace, and the standalone folder is only ever read.
  Future<QaDeskImportResult> importLegacyIfNeeded() async {
    final legacy = legacyRoot;
    if (legacy == null) return QaDeskImportResult.skipped;
    final legacyDatabase = File(p.join(legacy, legacyDatabaseName));
    final legacySources = File(p.join(legacy, sourcesName));
    if (!legacyDatabase.existsSync() && !legacySources.existsSync()) {
      return QaDeskImportResult.skipped;
    }
    final target = Directory(root);
    if (target.existsSync() && target.listSync().isNotEmpty) {
      return QaDeskImportResult.skipped;
    }

    final staging = Directory('$root.importing');
    try {
      if (staging.existsSync()) await staging.delete(recursive: true);
      await staging.create(recursive: true);

      var copied = 0;
      if (legacySources.existsSync()) {
        await legacySources.copy(p.join(staging.path, sourcesName));
        copied++;
      }
      // A database left mid-transaction keeps part of itself in a sidecar.
      for (final suffix in const ['', '-wal', '-shm', '-journal']) {
        final file = File('${legacyDatabase.path}$suffix');
        if (!file.existsSync()) continue;
        await file.copy(p.join(staging.path, '$databaseName$suffix'));
        copied++;
      }
      final legacyArtifacts = Directory(p.join(legacy, artifactsName));
      if (legacyArtifacts.existsSync()) {
        copied += await _copyTree(
          legacyArtifacts,
          Directory(p.join(staging.path, artifactsName)),
        );
      }

      final stagedDatabase = p.join(staging.path, databaseName);
      final relinked = File(stagedDatabase).existsSync()
          ? await _relinkArtifacts(stagedDatabase, from: legacy, to: root)
          : 0;
      await File(
        p.join(staging.path, importMarkerName),
      ).writeAsString('$legacy\n${DateTime.now().toIso8601String()}\n');

      // Empty, checked above; Windows cannot rename onto an existing folder.
      if (target.existsSync()) await target.delete();
      await staging.rename(root);
      return QaDeskImportResult(
        outcome: QaDeskImportOutcome.imported,
        legacyPath: legacy,
        copiedFiles: copied,
        relinkedPaths: relinked,
      );
    } on Object catch (error) {
      try {
        if (staging.existsSync()) await staging.delete(recursive: true);
      } on Object {
        // The staging folder is retried and replaced on the next start.
      }
      return QaDeskImportResult(
        outcome: QaDeskImportOutcome.failed,
        legacyPath: legacy,
        error: '$error',
      );
    }
  }

  static Future<int> _copyTree(Directory from, Directory to) async {
    var count = 0;
    await to.create(recursive: true);
    await for (final entity in from.list(recursive: true, followLinks: false)) {
      final target = p.join(to.path, p.relative(entity.path, from: from.path));
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(target)).create(recursive: true);
        await entity.copy(target);
        count++;
      }
    }
    return count;
  }

  /// The history stores absolute artifact paths, so copied rows would still
  /// point into the standalone folder. Rewrites the prefix of every path that
  /// lives under [from]; paths elsewhere are left alone.
  static Future<int> _relinkArtifacts(
    String databasePath, {
    required String from,
    required String to,
  }) async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(databasePath);
    try {
      final oldPrefix = '$from${p.separator}';
      final newPrefix = '$to${p.separator}';
      // Schema v1 had no screenshot column; the history store adds it on
      // open, after this runs.
      final columns = {
        for (final row in await database.rawQuery(
          'PRAGMA table_info(suite_runs)',
        ))
          row['name'],
      };
      var changed = 0;
      for (final column in const ['log_path', 'screenshot_path']) {
        if (!columns.contains(column)) continue;
        // Windows paths are case-insensitive, and the two apps resolved
        // %APPDATA% separately.
        changed += await database.rawUpdate(
          'UPDATE suite_runs SET $column = ? || substr($column, ?) '
          'WHERE lower(substr($column, 1, ?)) = lower(?)',
          [newPrefix, oldPrefix.length + 1, oldPrefix.length, oldPrefix],
        );
      }
      return changed;
    } finally {
      await database.close();
    }
  }
}
