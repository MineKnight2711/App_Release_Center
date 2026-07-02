class RemoteControlSettings {
  const RemoteControlSettings({
    this.enabled = false,
    this.desktopId = 'default',
    this.allowedRoots = const [],
  });

  final bool enabled;
  final String desktopId;
  final List<String> allowedRoots;

  RemoteControlSettings copyWith({
    bool? enabled,
    String? desktopId,
    List<String>? allowedRoots,
  }) {
    return RemoteControlSettings(
      enabled: enabled ?? this.enabled,
      desktopId: desktopId ?? this.desktopId,
      allowedRoots: allowedRoots ?? this.allowedRoots,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'desktopId': desktopId,
      'allowedRoots': allowedRoots,
    };
  }

  factory RemoteControlSettings.fromJson(Map<String, Object?> json) {
    return RemoteControlSettings(
      enabled: json['enabled'] == true,
      desktopId: _string(json['desktopId']).isEmpty
          ? 'default'
          : _string(json['desktopId']),
      allowedRoots: _stringList(json['allowedRoots']),
    );
  }
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

  Map<String, Object?> toJson() {
    return {
      'endpointBaseUrl': endpointBaseUrl,
      'deviceControlToken': deviceControlToken,
      'deviceId': deviceId,
    };
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

  factory RemoteDesktopState.fromJson(Map<String, Object?> json) {
    final state = json['state'] is Map<String, Object?>
        ? json['state']! as Map<String, Object?>
        : <String, Object?>{};
    return RemoteDesktopState(
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
