import 'package:app_management_center/app/models/wake_diagnostics.dart';
import 'package:app_management_center/app/models/remote_unlock.dart';

class RemoteControlSettings {
  const RemoteControlSettings({
    this.enabled = false,
    this.desktopId = 'default',
    this.allowedRoots = const [],
    this.allowPowerControl = false,
    this.allowWindowControl = false,
    this.allowRemoteUnlock = false,
    this.allowedApps = const [],
  });

  final bool enabled;
  final String desktopId;
  final List<String> allowedRoots;

  /// Lets a linked phone shut down, restart, sleep, lock or sign out of this
  /// machine. Off unless the person sitting at the desktop turns it on.
  final bool allowPowerControl;

  /// Lets a linked phone list windows and focus, minimise or close them, and
  /// launch entries from [allowedApps]. Off by default for the same reason.
  final bool allowWindowControl;

  /// Allows a separately-scoped, end-to-end encrypted unlock request.
  final bool allowRemoteUnlock;

  /// Executables a phone may launch, by full path. A phone never sends a path
  /// of its own; it sends a key that the desktop resolves against this list.
  final List<String> allowedApps;

  RemoteControlSettings copyWith({
    bool? enabled,
    String? desktopId,
    List<String>? allowedRoots,
    bool? allowPowerControl,
    bool? allowWindowControl,
    bool? allowRemoteUnlock,
    List<String>? allowedApps,
  }) {
    return RemoteControlSettings(
      enabled: enabled ?? this.enabled,
      desktopId: desktopId ?? this.desktopId,
      allowedRoots: allowedRoots ?? this.allowedRoots,
      allowPowerControl: allowPowerControl ?? this.allowPowerControl,
      allowWindowControl: allowWindowControl ?? this.allowWindowControl,
      allowRemoteUnlock: allowRemoteUnlock ?? this.allowRemoteUnlock,
      allowedApps: allowedApps ?? this.allowedApps,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'desktopId': desktopId,
      'allowedRoots': allowedRoots,
      'allowPowerControl': allowPowerControl,
      'allowWindowControl': allowWindowControl,
      'allowRemoteUnlock': allowRemoteUnlock,
      'allowedApps': allowedApps,
    };
  }

  factory RemoteControlSettings.fromJson(Map<String, Object?> json) {
    return RemoteControlSettings(
      enabled: json['enabled'] == true,
      desktopId: _string(json['desktopId']).isEmpty
          ? 'default'
          : _string(json['desktopId']),
      allowedRoots: _stringList(json['allowedRoots']),
      // Absent in settings saved before these gates existed: stay closed.
      allowPowerControl: json['allowPowerControl'] == true,
      allowWindowControl: json['allowWindowControl'] == true,
      allowRemoteUnlock: json['allowRemoteUnlock'] == true,
      allowedApps: _stringList(json['allowedApps']),
    );
  }
}

/// The three values the pairing form needs, read out of the link the desktop
/// shows beside its QR code.
///
/// The desktop offers that link as one copyable string, so letting someone
/// paste it beats asking them to transcribe an id and a code by hand.
class PairingLink {
  const PairingLink({
    required this.endpointBaseUrl,
    required this.pairingId,
    required this.pairingCode,
  });

  final String endpointBaseUrl;
  final String pairingId;
  final String pairingCode;

  /// Returns null when [value] is not a pairing link, so a half-typed
  /// endpoint is left alone rather than being rewritten under the cursor.
  static PairingLink? tryParse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.authority.isEmpty) return null;

    final code = (uri.queryParameters['code'] ?? '').trim();
    if (code.isEmpty) return null;

    return PairingLink(
      // The link points at the site root; the API lives one segment down.
      endpointBaseUrl: '${uri.scheme}://${uri.authority}/api',
      pairingId: (uri.queryParameters['pairing'] ?? '').trim(),
      pairingCode: code,
    );
  }
}

/// Turns a relay error into something that says what to do about it.
///
/// The relay answers in English and states only the rule it enforced, which
/// leaves out the half that matters: both of these messages describe a setup
/// step, not a fault to wait out. Pure so it can be tested without a phone.
String explainRemoteControlError(String message) {
  if (message.contains('invalid or expired')) {
    return '$message\n\n'
        'Mã ghép chỉ sống 10 phút, và chỉ dùng được trên đúng relay đã tạo ra '
        'nó. Kiểm tra máy tính và điện thoại có cùng một endpoint không, rồi '
        'tạo mã mới.';
  }
  // Scopes are frozen when a phone is paired, so switching a permission on
  // afterwards grants this phone nothing. The relay does not say that.
  if (message.contains('not allowed to send')) {
    return '$message\n\n'
        'Điện thoại này được ghép khi quyền đó còn tắt trên máy tính. Quyền '
        'chốt tại lúc ghép, nên bật công tắc sau đó không áp cho máy đã ghép. '
        'Trên máy tính bật quyền cần dùng trước, rồi bấm "Ghép app điều '
        'khiển" lấy mã mới và ghép lại điện thoại.';
  }
  return message;
}

class MobileControlSettings {
  const MobileControlSettings({
    this.endpointBaseUrl = '',
    this.deviceControlToken = '',
    this.deviceId = '',
  });

  final String endpointBaseUrl;
  final String deviceControlToken;
  final String deviceId;

  bool get isLinked =>
      endpointBaseUrl.trim().isNotEmpty && deviceControlToken.trim().isNotEmpty;

  MobileControlSettings copyWith({
    String? endpointBaseUrl,
    String? deviceControlToken,
    String? deviceId,
  }) {
    return MobileControlSettings(
      endpointBaseUrl: endpointBaseUrl ?? this.endpointBaseUrl,
      deviceControlToken: deviceControlToken ?? this.deviceControlToken,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  /// Deliberately omits [deviceControlToken].
  ///
  /// This is what gets written to preferences, and the token belongs in secure
  /// storage instead. [fromJson] still reads the field so that a token left
  /// behind by an older build can be migrated, which makes the pair
  /// asymmetric on purpose.
  Map<String, Object?> toJson() {
    return {'endpointBaseUrl': endpointBaseUrl, 'deviceId': deviceId};
  }

  factory MobileControlSettings.fromJson(Map<String, Object?> json) {
    return MobileControlSettings(
      endpointBaseUrl: _string(json['endpointBaseUrl']),
      deviceControlToken: _string(json['deviceControlToken']),
      deviceId: _string(json['deviceId']),
    );
  }
}

class RemoteDesktopState {
  const RemoteDesktopState({
    required this.desktopId,
    required this.displayName,
    required this.online,
    required this.remoteControlEnabled,
    required this.projects,
    required this.isRunning,
    required this.status,
    required this.logLines,
    this.yesNoPrompt,
    this.sessionLocked = false,
    this.powerControlEnabled = false,
    this.windowControlEnabled = false,
    this.sleepFallsBackToHibernate = false,
    this.sleepSupported = false,
    this.hibernateSupported = false,
    this.remoteUnlock = const RemoteUnlockState(),
    this.wake = const WakeDiagnostics(),
    this.buildStamp,
  });

  final String desktopId;
  final String displayName;
  final bool online;
  final bool remoteControlEnabled;
  final List<RemoteProjectSummary> projects;
  final bool isRunning;
  final String status;
  final List<String> logLines;
  final String? yesNoPrompt;

  /// Sitting at the lock screen. Still online and still takes commands — the
  /// phone must not present this as if the machine were unreachable.
  final bool sessionLocked;

  /// Whether the desktop will accept power commands at all. Mirrors the switch
  /// in Options, so the phone can grey buttons out instead of failing later.
  final bool powerControlEnabled;
  final bool windowControlEnabled;

  /// Asking this machine to sleep would hibernate it instead.
  final bool sleepFallsBackToHibernate;

  /// Whether Windows advertises an S3 or Modern Standby sleep state.
  final bool sleepSupported;

  /// Whether Windows advertises the S4 hibernation state.
  final bool hibernateSupported;

  /// Public key and one-time challenge advertised only while locked.
  final RemoteUnlockState remoteUnlock;

  /// What the machine last said about being woken. Survives the machine going
  /// offline, which is the only time it is of any use.
  final WakeDiagnostics wake;

  /// When the desktop build it is running was produced. A copy older than the
  /// phone's expectations explains missing behaviour that otherwise looks like
  /// a broken feature.
  final DateTime? buildStamp;

  factory RemoteDesktopState.fromJson(Map<String, Object?> json) {
    final state = json['state'] is Map<String, Object?>
        ? json['state']! as Map<String, Object?>
        : <String, Object?>{};
    final sleepSupport = state['sleepSupport'] is Map
        ? Map<String, Object?>.from(state['sleepSupport']! as Map)
        : const <String, Object?>{};
    return RemoteDesktopState(
      buildStamp: DateTime.tryParse(
        state['buildStamp']?.toString() ?? '',
      )?.toLocal(),
      wake: state['wake'] is Map
          ? WakeDiagnostics.fromJson(
              Map<String, Object?>.from(state['wake']! as Map),
            )
          : const WakeDiagnostics(),
      remoteUnlock: state['remoteUnlock'] is Map
          ? RemoteUnlockState.fromJson(
              Map<String, Object?>.from(state['remoteUnlock']! as Map),
            )
          : const RemoteUnlockState(),
      sessionLocked: state['sessionLocked'] == true,
      powerControlEnabled: state['powerControlEnabled'] == true,
      windowControlEnabled: state['windowControlEnabled'] == true,
      sleepFallsBackToHibernate:
          sleepSupport['sleepFallsBackToHibernate'] == true,
      sleepSupported:
          sleepSupport['standby'] == true ||
          sleepSupport['modernStandby'] == true,
      hibernateSupported: sleepSupport['hibernate'] == true,
      desktopId: _string(json['desktopId']),
      displayName: _string(json['displayName']).isEmpty
          ? 'Desktop'
          : _string(json['displayName']),
      online: json['online'] == true,
      remoteControlEnabled: json['remoteControlEnabled'] != false,
      projects: _mapList(state['projects'], RemoteProjectSummary.fromJson),
      isRunning: state['isRunning'] == true,
      status: _string(state['status']).isEmpty
          ? 'Idle'
          : _string(state['status']),
      logLines: _stringList(state['logLines']),
      yesNoPrompt: _optionalString(state['yesNoPrompt']),
    );
  }
}

class RemoteProjectSummary {
  const RemoteProjectSummary({
    required this.path,
    required this.name,
    required this.scripts,
    required this.fastlaneLanes,
  });

  final String path;
  final String name;
  final List<RemoteScriptSummary> scripts;
  final List<RemoteFastlaneSummary> fastlaneLanes;

  factory RemoteProjectSummary.fromJson(Map<String, Object?> json) {
    return RemoteProjectSummary(
      path: _string(json['path']),
      name: _string(json['name']),
      scripts: _mapList(json['scripts'], RemoteScriptSummary.fromJson),
      fastlaneLanes: _mapList(
        json['fastlaneLanes'],
        RemoteFastlaneSummary.fromJson,
      ),
    );
  }
}

class RemoteScriptSummary {
  const RemoteScriptSummary({
    required this.path,
    required this.fileName,
    required this.label,
    required this.description,
  });

  final String path;
  final String fileName;
  final String label;
  final String description;

  factory RemoteScriptSummary.fromJson(Map<String, Object?> json) {
    return RemoteScriptSummary(
      path: _string(json['path']),
      fileName: _string(json['fileName']),
      label: _string(json['label']),
      description: _string(json['description']),
    );
  }
}

class RemoteFastlaneSummary {
  const RemoteFastlaneSummary({
    required this.key,
    required this.name,
    required this.label,
    required this.command,
  });

  final String key;
  final String name;
  final String label;
  final String command;

  factory RemoteFastlaneSummary.fromJson(Map<String, Object?> json) {
    return RemoteFastlaneSummary(
      key: _string(json['key']),
      name: _string(json['name']),
      label: _string(json['label']),
      command: _string(json['command']),
    );
  }
}

class RemoteCommand {
  const RemoteCommand({
    required this.commandId,
    required this.type,
    required this.status,
    required this.payload,
    required this.logLines,
    this.exitCode,
    this.error,
    this.yesNoPrompt,
  });

  final String commandId;
  final String type;
  final String status;
  final Map<String, Object?> payload;
  final List<String> logLines;
  final int? exitCode;
  final String? error;
  final String? yesNoPrompt;

  bool get isActive =>
      status == 'queued' || status == 'claimed' || status == 'running';

  factory RemoteCommand.fromJson(Map<String, Object?> json) {
    return RemoteCommand(
      commandId: _string(json['commandId']),
      type: _string(json['type']),
      status: _string(json['status']).isEmpty
          ? 'queued'
          : _string(json['status']),
      payload: json['payload'] is Map<String, Object?>
          ? Map<String, Object?>.from(json['payload']! as Map<String, Object?>)
          : const {},
      logLines: _stringList(json['logLines']),
      exitCode: _int(json['exitCode']),
      error: _optionalString(json['error']),
      yesNoPrompt: _optionalString(json['yesNoPrompt']),
    );
  }
}

String _string(Object? value) => value?.toString() ?? '';

String? _optionalString(Object? value) {
  final result = _string(value);
  return result.trim().isEmpty ? null : result;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((entry) => entry.toString()).toList();
}

List<T> _mapList<T>(
  Object? value,
  T Function(Map<String, Object?> json) fromJson,
) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) => fromJson(Map<String, Object?>.from(entry)))
      .toList();
}
