import 'dart:io';

import 'package:path/path.dart' as p;

/// When the running build was produced.
///
/// Exists because "the desktop is running an older copy" is invisible and
/// keeps costing real debugging time: a freshly built binary and the installed
/// one look identical, behave differently, and nothing on screen says which is
/// which. Publishing this in the heartbeat lets the phone show it.
///
/// The executable's own timestamp is the wrong thing to read on Windows: a
/// Flutter release build only relinks the C++ runner when native code changes,
/// so `app_management_center.exe` keeps its old date while the Dart payload
/// beside it is rebuilt. `data/app.so` is what actually changes.
class AppBuildStamp {
  const AppBuildStamp({this.executablePath});

  /// Overridable for tests; defaults to the running executable.
  final String? executablePath;

  String get _executable => executablePath ?? Platform.resolvedExecutable;

  /// The newest of the Dart payload and the executable, or null when neither
  /// can be read.
  DateTime? read() {
    final candidates = <String>[
      // Release builds: the AOT snapshot.
      p.join(p.dirname(_executable), 'data', 'app.so'),
      // Debug and profile builds keep the Dart code here instead.
      p.join(p.dirname(_executable), 'data', 'flutter_assets', 'kernel_blob.bin'),
      _executable,
    ];

    DateTime? newest;
    for (final candidate in candidates) {
      try {
        final file = File(candidate);
        if (!file.existsSync()) continue;
        final modified = file.lastModifiedSync();
        if (newest == null || modified.isAfter(newest)) newest = modified;
      } catch (_) {
        continue;
      }
    }
    return newest;
  }
}
