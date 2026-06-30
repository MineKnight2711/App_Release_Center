import 'package:app_release_center/app/models/ch_play_credentials.dart';
import 'package:path/path.dart' as p;

class ChPlayProject {
  const ChPlayProject({
    required this.id,
    required this.path,
    required this.displayName,
    required this.applicationId,
    this.track = 'production',
    this.hasSavedGooglePlayJson = false,
    this.hasSavedJksPath = false,
    this.hasSavedKeyAlias = false,
    this.hasSavedStorePassword = false,
    this.hasSavedKeyPassword = false,
  });

  final String id;
  final String path;
  final String displayName;
  final String applicationId;
  final String track;
  final bool hasSavedGooglePlayJson;
  final bool hasSavedJksPath;
  final bool hasSavedKeyAlias;
  final bool hasSavedStorePassword;
  final bool hasSavedKeyPassword;

  String get name {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? p.basename(path) : trimmed;
  }

  bool get hasSavedSigningCredentials {
    return hasSavedJksPath ||
        hasSavedKeyAlias ||
        hasSavedStorePassword ||
        hasSavedKeyPassword;
  }

  ChPlayProject copyWith({
    String? id,
    String? path,
    String? displayName,
    String? applicationId,
    String? track,
    bool? hasSavedGooglePlayJson,
    bool? hasSavedJksPath,
    bool? hasSavedKeyAlias,
    bool? hasSavedStorePassword,
    bool? hasSavedKeyPassword,
  }) {
    return ChPlayProject(
      id: id ?? this.id,
      path: path ?? this.path,
      displayName: displayName ?? this.displayName,
      applicationId: applicationId ?? this.applicationId,
      track: track ?? this.track,
      hasSavedGooglePlayJson:
          hasSavedGooglePlayJson ?? this.hasSavedGooglePlayJson,
      hasSavedJksPath: hasSavedJksPath ?? this.hasSavedJksPath,
      hasSavedKeyAlias: hasSavedKeyAlias ?? this.hasSavedKeyAlias,
      hasSavedStorePassword:
          hasSavedStorePassword ?? this.hasSavedStorePassword,
      hasSavedKeyPassword: hasSavedKeyPassword ?? this.hasSavedKeyPassword,
    );
  }

  ChPlayProject withCredentialMetadata(ChPlayCredentialMetadata metadata) {
    return copyWith(
      hasSavedGooglePlayJson: metadata.hasGooglePlayJson,
      hasSavedJksPath: metadata.hasJksPath,
      hasSavedKeyAlias: metadata.hasKeyAlias,
      hasSavedStorePassword: metadata.hasStorePassword,
      hasSavedKeyPassword: metadata.hasKeyPassword,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'path': path,
      'displayName': displayName,
      'applicationId': applicationId,
      'track': track,
      'hasSavedGooglePlayJson': hasSavedGooglePlayJson,
      'hasSavedJksPath': hasSavedJksPath,
      'hasSavedKeyAlias': hasSavedKeyAlias,
      'hasSavedStorePassword': hasSavedStorePassword,
      'hasSavedKeyPassword': hasSavedKeyPassword,
    };
  }

  factory ChPlayProject.fromJson(Map<String, Object?> json) {
    return ChPlayProject(
      id: (json['id'] as String?) ?? '',
      path: (json['path'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '',
      applicationId: (json['applicationId'] as String?) ?? '',
      track: (json['track'] as String?) ?? 'production',
      hasSavedGooglePlayJson:
          (json['hasSavedGooglePlayJson'] as bool?) ?? false,
      hasSavedJksPath: (json['hasSavedJksPath'] as bool?) ?? false,
      hasSavedKeyAlias: (json['hasSavedKeyAlias'] as bool?) ?? false,
      hasSavedStorePassword: (json['hasSavedStorePassword'] as bool?) ?? false,
      hasSavedKeyPassword: (json['hasSavedKeyPassword'] as bool?) ?? false,
    );
  }
}
