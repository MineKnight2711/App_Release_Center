import 'package:get/get.dart';

/// HTTP client for the release relay.
///
/// The timeout has to clear the relay's longest long-poll window with room to
/// spare. GetConnect defaults to five seconds, which is shorter than the
/// window, so every idle poll used to die of a TimeoutException, back off, and
/// leave queued commands waiting — see [remoteLongPollWindow].
class ReleaseCenterConnect extends GetConnect {
  /// Set here rather than in `onInit` so the timeout is right even when this
  /// is constructed directly instead of through Get's lifecycle. Getting it
  /// from `onInit` alone left directly built clients on GetConnect's five
  /// second default.
  ReleaseCenterConnect() {
    httpClient.timeout = remoteRequestTimeout;
  }
}

/// How long the relay is asked to hold an idle long-poll open.
const remoteLongPollWindow = Duration(seconds: 12);

/// Comfortably longer than [remoteLongPollWindow], so a poll that simply found
/// nothing comes back as an empty answer rather than as a client timeout.
const remoteRequestTimeout = Duration(seconds: 30);
