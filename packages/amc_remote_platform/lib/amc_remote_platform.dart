import 'package:flutter/services.dart';

class RemotePlatformPermissions {
  const RemotePlatformPermissions({required this.screen, required this.input});
  final bool screen;
  final bool input;
}

/// Only callable inside AMC. Native input is additionally bound to an explicit
/// session and display; this channel is never exposed as a network endpoint.
class AmcRemotePlatform {
  const AmcRemotePlatform();
  static const channel = MethodChannel('amc/remote_platform');

  Future<List<Map<String, dynamic>>> displays() async {
    final values = await channel.invokeListMethod<dynamic>('displays') ?? [];
    return values.map((v) => Map<String, dynamic>.from(v as Map)).toList();
  }

  Future<void> releaseInputs(String sessionId) =>
      channel.invokeMethod('releaseInputs', {'sessionId': sessionId});

  Future<RemotePlatformPermissions> permissions({bool request = false}) async {
    final data = await channel.invokeMapMethod<String, dynamic>('permissions', {
      'request': request,
    });
    return RemotePlatformPermissions(
      screen: data?['screen'] == true,
      input: data?['input'] == true,
    );
  }

  Future<void> beginInput(String sessionId, String displayId) =>
      channel.invokeMethod('beginInput', {
        'sessionId': sessionId,
        'displayId': displayId,
      });

  Future<void> sendInput(String sessionId, Map<String, Object> input) =>
      channel.invokeMethod('input', {'sessionId': sessionId, ...input});

  Future<void> endInput(String sessionId) =>
      channel.invokeMethod('endInput', {'sessionId': sessionId});
}
