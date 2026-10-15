/// The desktop's release flows, as the phone reaches them through the relay.
///
/// Implemented next to the desktop's own release dialogs (see
/// RemoteReleaseBridge) so a release started from the phone is the same
/// release the desktop would have run: same preflight, same steps, same
/// post-processing. This side only carries commands to it and results back.
abstract interface class RemoteReleaseHandler {
  /// Projects that can be released, and every release in progress or last
  /// finished, for the phone's release tab.
  Future<Map<String, Object?>> overview();

  /// One project's iOS state in detail: its runs, local version and notes.
  Future<Map<String, Object?>> iosProject(String projectId);

  /// Runs one release step and returns the run it moved.
  Future<Map<String, Object?>> run(Map<String, Object?> payload);

  /// The run the step in progress is moving, re-read for each progress report.
  Map<String, Object?>? get live;

  /// The log of the step in progress when it is not on this machine's runner,
  /// as when a Mac builds the iOS release for this desktop.
  List<String>? get liveLog;

  /// Stops whatever [platform] is running, whoever started it.
  Future<void> cancel(String platform);
}
