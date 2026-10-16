/// This desktop's link to a Mac that builds iOS releases for it.
///
/// Made once from a pairing code the Mac shows. The Mac's public key is pinned
/// here at that moment: every envelope is sealed to the pinned key, never to
/// whatever key the relay reports later.
class IosBuildHostLink {
  const IosBuildHostLink({
    this.endpointBaseUrl = '',
    this.deviceId = '',
    this.desktopId = '',
    this.displayName = '',
    this.publicKey = '',
    this.fingerprint = '',
    this.linkedAt,
    this.controlToken = '',
  });

  final String endpointBaseUrl;

  /// This desktop's device id on the relay.
  final String deviceId;

  /// The Mac's desktop id on the relay; commands are addressed to it.
  final String desktopId;
  final String displayName;

  /// Base64 X25519 public key of the Mac, pinned at pairing.
  final String publicKey;
  final String fingerprint;
  final DateTime? linkedAt;

  /// Bearer token for the relay. Kept in secure storage, never serialised.
  final String controlToken;

  bool get isLinked =>
      endpointBaseUrl.isNotEmpty &&
      desktopId.isNotEmpty &&
      publicKey.isNotEmpty &&
      controlToken.isNotEmpty;

  IosBuildHostLink copyWith({String? controlToken}) => IosBuildHostLink(
    endpointBaseUrl: endpointBaseUrl,
    deviceId: deviceId,
    desktopId: desktopId,
    displayName: displayName,
    publicKey: publicKey,
    fingerprint: fingerprint,
    linkedAt: linkedAt,
    controlToken: controlToken ?? this.controlToken,
  );

  Map<String, Object?> toJson() => {
    'endpointBaseUrl': endpointBaseUrl,
    'deviceId': deviceId,
    'desktopId': desktopId,
    'displayName': displayName,
    'publicKey': publicKey,
    'fingerprint': fingerprint,
    'linkedAt': linkedAt?.toUtc().toIso8601String(),
  };

  factory IosBuildHostLink.fromJson(Map<String, Object?> json) =>
      IosBuildHostLink(
        endpointBaseUrl: _string(json['endpointBaseUrl']),
        deviceId: _string(json['deviceId']),
        desktopId: _string(json['desktopId']),
        displayName: _string(json['displayName']),
        publicKey: _string(json['publicKey']),
        fingerprint: _string(json['fingerprint']),
        linkedAt: DateTime.tryParse(_string(json['linkedAt']))?.toLocal(),
      );
}

/// What a build host says about itself in its heartbeat.
class IosBuildHostState {
  const IosBuildHostState({
    required this.desktopId,
    required this.displayName,
    required this.online,
    required this.enabled,
    this.publicKey = '',
    this.fingerprint = '',
    this.busy = false,
    this.status = '',
    this.xcode = '',
    this.activeCommandId = '',
    this.lastSeenAt,
  });

  final String desktopId;
  final String displayName;
  final bool online;

  /// The Mac has "accept iOS builds" switched on.
  final bool enabled;
  final String publicKey;
  final String fingerprint;
  final bool busy;
  final String status;

  /// `xcodebuild -version`, first line, when the Mac could read it.
  final String xcode;

  /// The relay command the Mac is executing right now, if any. Empty from a
  /// Mac too old to say.
  final String activeCommandId;
  final DateTime? lastSeenAt;

  /// Reads one entry of the relay's desktop list.
  factory IosBuildHostState.fromDesktopJson(Map<String, Object?> json) {
    final state = json['state'] is Map
        ? Map<String, Object?>.from(json['state']! as Map)
        : const <String, Object?>{};
    final host = state['iosBuildHost'] is Map
        ? Map<String, Object?>.from(state['iosBuildHost']! as Map)
        : const <String, Object?>{};
    return IosBuildHostState(
      desktopId: _string(json['desktopId']),
      displayName: _string(json['displayName']).isEmpty
          ? 'Mac'
          : _string(json['displayName']),
      online: json['online'] == true,
      enabled: host['enabled'] == true,
      publicKey: _string(host['publicKey']),
      fingerprint: _string(host['fingerprint']),
      busy: state['isRunning'] == true,
      status: _string(state['status']),
      xcode: _string(host['xcode']),
      activeCommandId: _string(state['activeCommandId']),
      lastSeenAt: DateTime.tryParse(_string(json['lastSeenAt']))?.toLocal(),
    );
  }
}

String _string(Object? value) => value?.toString().trim() ?? '';
