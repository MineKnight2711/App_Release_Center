import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Outcome of a single migration attempt.
enum LegacyStorageMigrationOutcome {
  /// Nothing to do: no legacy directory, or the current one is already in use.
  skipped,

  /// Files were copied from the legacy directory into the current one.
  migrated,

  /// The legacy directory was found but could not be copied.
  failed,
}

class LegacyStorageMigrationResult {
  const LegacyStorageMigrationResult({
    required this.outcome,
    this.legacyPath = '',
    this.currentPath = '',
    this.copiedFiles = 0,
    this.error = '',
  });

  final LegacyStorageMigrationOutcome outcome;
  final String legacyPath;
  final String currentPath;
  final int copiedFiles;
  final String error;
}

/// Moves application data left behind by the App Release Center name.
///
/// On Windows `getApplicationSupportDirectory()` resolves to
/// `%APPDATA%\<CompanyName>\<ProductName>`, both read from the executable's
/// VERSIONINFO resource. Renaming the product therefore points the app at an
/// empty directory and orphans `shared_preferences.json` (projects, API tool
/// collections, every panel setting) together with `flutter_secure_storage.dat`
/// (Telegram, Google Drive, Play and App Store credentials).
///
/// The legacy payload is copied, never moved, so a failed migration leaves the
/// old data untouched and the app still starts.
class LegacyStorageMigrationService {
  const LegacyStorageMigrationService();

  /// Directory names used by the app before the App Management Center rename,
  /// newest first.
  static const legacyDirectoryNames = <String>['app_release_center'];

  /// A directory counts as already in use once one of these exists in it.
  static const _occupancyMarkers = <String>[
    'shared_preferences.json',
    'flutter_secure_storage.dat',
  ];

  Future<LegacyStorageMigrationResult> migrateIfNeeded() async {
    if (!Platform.isWindows) {
      return const LegacyStorageMigrationResult(
        outcome: LegacyStorageMigrationOutcome.skipped,
      );
    }

    try {
      final current = await getApplicationSupportDirectory();
      return migrateInto(current);
    } catch (error) {
      return LegacyStorageMigrationResult(
        outcome: LegacyStorageMigrationOutcome.failed,
        error: '$error',
      );
    }
  }

  /// Testable core: [currentDirectory] is the support directory in use now.
  /// Legacy directories are looked up as its siblings.
  LegacyStorageMigrationResult migrateInto(Directory currentDirectory) {
    if (_isOccupied(currentDirectory)) {
      return LegacyStorageMigrationResult(
        outcome: LegacyStorageMigrationOutcome.skipped,
        currentPath: currentDirectory.path,
      );
    }

    final legacy = _findLegacyDirectory(currentDirectory);
    if (legacy == null) {
      return LegacyStorageMigrationResult(
        outcome: LegacyStorageMigrationOutcome.skipped,
        currentPath: currentDirectory.path,
      );
    }

    try {
      final copied = _copyDirectory(legacy, currentDirectory);
      return LegacyStorageMigrationResult(
        outcome: LegacyStorageMigrationOutcome.migrated,
        legacyPath: legacy.path,
        currentPath: currentDirectory.path,
        copiedFiles: copied,
      );
    } catch (error) {
      return LegacyStorageMigrationResult(
        outcome: LegacyStorageMigrationOutcome.failed,
        legacyPath: legacy.path,
        currentPath: currentDirectory.path,
        error: '$error',
      );
    }
  }

  bool _isOccupied(Directory directory) {
    if (!directory.existsSync()) return false;
    return _occupancyMarkers.any(
      (marker) => File(p.join(directory.path, marker)).existsSync(),
    );
  }

  Directory? _findLegacyDirectory(Directory currentDirectory) {
    final parent = currentDirectory.parent;
    for (final name in legacyDirectoryNames) {
      final candidate = Directory(p.join(parent.path, name));
      if (!candidate.existsSync()) continue;
      if (p.equals(candidate.path, currentDirectory.path)) continue;
      if (_isOccupied(candidate)) return candidate;
    }
    return null;
  }

  int _copyDirectory(Directory source, Directory destination) {
    destination.createSync(recursive: true);
    var copied = 0;

    for (final entity in source.listSync(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: source.path);
      final target = p.join(destination.path, relative);

      if (entity is Directory) {
        Directory(target).createSync(recursive: true);
        continue;
      }
      if (entity is! File) continue;

      // Never overwrite: whatever the new directory already holds wins.
      if (File(target).existsSync()) continue;
      Directory(p.dirname(target)).createSync(recursive: true);
      entity.copySync(target);
      copied++;
    }

    return copied;
  }
}
