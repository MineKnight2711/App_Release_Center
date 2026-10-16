enum CommandNotificationEventType { started, completed, failed }

/// How a release run ended, which decides the sound and buzz on the phone.
enum ReleasePushOutcome { succeeded, failed }

/// A release that finished or failed, sent to phones that turned release
/// notifications on. One per run outcome, not one per command: the per-command
/// web push already covers those.
class ReleasePushEvent {
  const ReleasePushEvent({
    required this.outcome,
    required this.title,
    this.body = '',
    this.tag = '',
    this.projectName = '',
    this.platform = '',
    this.version = '',
  });

  final ReleasePushOutcome outcome;
  final String title;
  final String body;

  /// Same tag, same notification: a retry that succeeds replaces the failure.
  final String tag;
  final String projectName;
  final String platform;
  final String version;

  Map<String, Object?> toJson() => {
    'outcome': outcome.name,
    'title': title,
    'body': body,
    'tag': tag,
    'projectName': projectName,
    'platform': platform,
    'version': version,
  };
}

/// What the relay did with a release push.
class ReleasePushResult {
  const ReleasePushResult({
    this.devices = 0,
    this.sent = 0,
    this.failed = 0,
    this.removed = 0,
    this.failures = const [],
  });

  /// Phones with release notifications on.
  final int devices;
  final int sent;
  final int failed;

  /// Phones whose app was uninstalled; the relay forgot their token.
  final int removed;
  final List<String> failures;

  factory ReleasePushResult.fromJson(Map<String, Object?> json) {
    int count(String key) => json[key] is num ? (json[key]! as num).toInt() : 0;
    return ReleasePushResult(
      devices: count('devices'),
      sent: count('sent'),
      failed: count('failed'),
      removed: count('removed'),
      failures: json['failures'] is List
          ? (json['failures']! as List).map((entry) => '$entry').toList()
          : const [],
    );
  }
}

class LinkedNotificationDevice {
  const LinkedNotificationDevice({
    required this.id,
    required this.displayName,
    required this.platform,
    required this.browser,
    required this.linkedAt,
    this.lastSeenAt,
  });

  final String id;
  final String displayName;
  final String platform;
  final String browser;
  final DateTime linkedAt;
  final DateTime? lastSeenAt;

  String get label =>
      displayName.trim().isEmpty ? 'Điện thoại đã liên kết' : displayName;

  String get detail {
    final parts = [
      if (platform.trim().isNotEmpty) platform.trim(),
      if (browser.trim().isNotEmpty) browser.trim(),
    ];
    return parts.isEmpty ? 'Thiết bị Web Push' : parts.join(' / ');
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'platform': platform,
      'browser': browser,
      'linkedAt': linkedAt.toUtc().toIso8601String(),
      'lastSeenAt': lastSeenAt?.toUtc().toIso8601String(),
    };
  }

  factory LinkedNotificationDevice.fromJson(Map<String, Object?> json) {
    return LinkedNotificationDevice(
      id: _string(json['id']),
      displayName: _string(json['displayName']),
      platform: _string(json['platform']),
      browser: _string(json['browser']),
      linkedAt:
          _date(json['linkedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      lastSeenAt: _date(json['lastSeenAt']),
    );
  }
}

class ReleaseNotificationSettings {
  const ReleaseNotificationSettings({
    this.enabled = false,
    this.endpointBaseUrl = '',
    this.selectedDeviceIds = const [],
  });

  final bool enabled;
  final String endpointBaseUrl;
  final List<String> selectedDeviceIds;

  bool get hasEndpoint => endpointBaseUrl.trim().isNotEmpty;
  bool get hasSelectedDevices => selectedDeviceIds.isNotEmpty;

  ReleaseNotificationSettings copyWith({
    bool? enabled,
    String? endpointBaseUrl,
    List<String>? selectedDeviceIds,
  }) {
    return ReleaseNotificationSettings(
      enabled: enabled ?? this.enabled,
      endpointBaseUrl: endpointBaseUrl ?? this.endpointBaseUrl,
      selectedDeviceIds: selectedDeviceIds ?? this.selectedDeviceIds,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'endpointBaseUrl': endpointBaseUrl,
      'selectedDeviceIds': selectedDeviceIds,
    };
  }

  factory ReleaseNotificationSettings.fromJson(Map<String, Object?> json) {
    return ReleaseNotificationSettings(
      enabled: json['enabled'] == true,
      endpointBaseUrl: _string(json['endpointBaseUrl']),
      selectedDeviceIds: _stringList(json['selectedDeviceIds']),
    );
  }
}

class CommandNotificationEvent {
  const CommandNotificationEvent({
    required this.runId,
    required this.event,
    required this.command,
    required this.statusLabel,
    required this.activePath,
    required this.startedAt,
    this.projectName,
    this.finishedAt,
    this.durationMs,
    this.exitCode,
    this.logTail = const [],
    this.targetDeviceIds = const [],
  });

  final String runId;
  final CommandNotificationEventType event;
  final String command;
  final String statusLabel;
  final String activePath;
  final String? projectName;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int? durationMs;
  final int? exitCode;
  final List<String> logTail;
  final List<String> targetDeviceIds;

  CommandNotificationEvent copyWith({
    CommandNotificationEventType? event,
    DateTime? finishedAt,
    int? durationMs,
    int? exitCode,
    List<String>? logTail,
    List<String>? targetDeviceIds,
  }) {
    return CommandNotificationEvent(
      runId: runId,
      event: event ?? this.event,
      command: command,
      statusLabel: statusLabel,
      activePath: activePath,
      projectName: projectName,
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      durationMs: durationMs ?? this.durationMs,
      exitCode: exitCode ?? this.exitCode,
      logTail: logTail ?? this.logTail,
      targetDeviceIds: targetDeviceIds ?? this.targetDeviceIds,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'runId': runId,
      'event': event.name,
      'command': command,
      'statusLabel': statusLabel,
      'activePath': activePath,
      'projectName': projectName,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'finishedAt': finishedAt?.toUtc().toIso8601String(),
      'durationMs': durationMs,
      'exitCode': exitCode,
      'logTail': logTail,
      'targetDeviceIds': targetDeviceIds,
    };
  }

  factory CommandNotificationEvent.fromJson(Map<String, Object?> json) {
    return CommandNotificationEvent(
      runId: _string(json['runId']),
      event: CommandNotificationEventType.values.firstWhere(
        (value) => value.name == json['event'],
        orElse: () => CommandNotificationEventType.started,
      ),
      command: _string(json['command']),
      statusLabel: _string(json['statusLabel']),
      activePath: _string(json['activePath']),
      projectName: _optionalString(json['projectName']),
      startedAt:
          _date(json['startedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      finishedAt: _date(json['finishedAt']),
      durationMs: _int(json['durationMs']),
      exitCode: _int(json['exitCode']),
      logTail: _stringList(json['logTail']),
      targetDeviceIds: _stringList(json['targetDeviceIds']),
    );
  }
}

class NotificationPairingSession {
  const NotificationPairingSession({
    required this.pairingId,
    required this.pairingCode,
    required this.pairingUrl,
    required this.expiresAt,
  });

  final String pairingId;
  final String pairingCode;
  final String pairingUrl;
  final DateTime expiresAt;

  factory NotificationPairingSession.fromJson(Map<String, Object?> json) {
    return NotificationPairingSession(
      pairingId: _string(json['pairingId']),
      pairingCode: _string(json['pairingCode']),
      pairingUrl: _string(json['pairingUrl']),
      expiresAt: _date(json['expiresAt']) ?? DateTime.now(),
    );
  }
}

enum NotificationPairingStatus { pending, linked, expired }

class NotificationPairingPollResult {
  const NotificationPairingPollResult({
    required this.status,
    this.device,
    this.expiresAt,
  });

  final NotificationPairingStatus status;
  final LinkedNotificationDevice? device;
  final DateTime? expiresAt;

  factory NotificationPairingPollResult.fromJson(Map<String, Object?> json) {
    return NotificationPairingPollResult(
      status: NotificationPairingStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => NotificationPairingStatus.pending,
      ),
      device: json['device'] is Map<String, Object?>
          ? LinkedNotificationDevice.fromJson(
              json['device']! as Map<String, Object?>,
            )
          : null,
      expiresAt: _date(json['expiresAt']),
    );
  }
}

String _string(Object? value) => value?.toString() ?? '';

String? _optionalString(Object? value) {
  final stringValue = value?.toString();
  return stringValue == null || stringValue.isEmpty ? null : stringValue;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((entry) => entry.toString()).toList();
}

DateTime? _date(Object? value) {
  if (value is DateTime) return value;
  final stringValue = value?.toString();
  if (stringValue == null || stringValue.isEmpty) return null;
  return DateTime.tryParse(stringValue);
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
