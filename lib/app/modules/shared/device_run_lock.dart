/// One job driving a phone or emulator at a time, across the whole app.
///
/// The AAB checker installs and launches bundles, its Telegram bot does the
/// same on request, and QA Desk runs mobile suites; any two of them on one
/// emulator at once would uninstall each other's app mid-run. Jobs queue in
/// the order they ask, whichever module they come from.
abstract final class DeviceRunLock {
  static Future<void> _tail = Future.value();
  static int _pending = 0;

  /// Runs [job] once every job queued before it has finished.
  ///
  /// A job that fails releases the lock the same as one that succeeds; its
  /// error goes to its own caller only.
  static Future<T> run<T>(Future<T> Function() job) {
    _pending++;
    final result = _tail.then((_) => job());
    _tail = result.then<void>(
      (_) => _pending--,
      onError: (Object _) => _pending--,
    );
    return result;
  }

  /// Whether a job is running or waiting; lets a page say it is queued.
  static bool get busy => _pending > 0;
}
