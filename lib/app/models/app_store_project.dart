import 'package:app_release_center/app/models/app_store_credentials.dart';
import 'package:path/path.dart' as p;

class AppStoreProject {
  const AppStoreProject({
    required this.id,
    required this.path,
    required this.displayName,
    required this.bundleId,
    this.platform = 'ios',
    this.hasSavedP8PrivateKey = false,
    this.hasSavedKeyId = false,
    this.hasSavedIssuerId = false,
    this.hasSavedTeamId = false,
    this.inHouse = false,
  });

  final String id;
  final String path;
  final String displayName;
  final String bundleId;
  final String platform;
  final bool hasSavedP8PrivateKey;
  final bool hasSavedKeyId;
  final bool hasSavedIssuerId;
  final bool hasSavedTeamId;
  final bool inHouse;

  String get name {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? p.basename(path) : trimmed;
  }

  bool get hasSavedRequiredCredentials {
    return hasSavedP8PrivateKey && hasSavedKeyId && hasSavedIssuerId;
  }

  AppStoreProject copyWith({
    String? id,
    String? path,
    String? displayName,
    String? bundleId,
    String? platform,
    bool? hasSavedP8PrivateKey,
    bool? hasSavedKeyId,
    bool? hasSavedIssuerId,
    bool? hasSavedTeamId,
    bool? inHouse,
  }) {
    return AppStoreProject(
      id: id ?? this.id,
      path: path ?? this.path,
      displayName: displayName ?? this.displayName,
      bundleId: bundleId ?? this.bundleId,
      platform: platform ?? this.platform,
      hasSavedP8PrivateKey: hasSavedP8PrivateKey ?? this.hasSavedP8PrivateKey,
      hasSavedKeyId: hasSavedKeyId ?? this.hasSavedKeyId,
      hasSavedIssuerId: hasSavedIssuerId ?? this.hasSavedIssuerId,
      hasSavedTeamId: hasSavedTeamId ?? this.hasSavedTeamId,
      inHouse: inHouse ?? this.inHouse,
    );
  }

  AppStoreProject withCredentialMetadata(AppStoreCredentialMetadata metadata) {
    return copyWith(
      hasSavedP8PrivateKey: metadata.hasP8PrivateKey,
      hasSavedKeyId: metadata.hasKeyId,
      hasSavedIssuerId: metadata.hasIssuerId,
      hasSavedTeamId: metadata.hasTeamId,
      inHouse: metadata.inHouse,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'path': path,
      'displayName': displayName,
      'bundleId': bundleId,
      'platform': platform,
      'hasSavedP8PrivateKey': hasSavedP8PrivateKey,
      'hasSavedKeyId': hasSavedKeyId,
      'hasSavedIssuerId': hasSavedIssuerId,
      'hasSavedTeamId': hasSavedTeamId,
      'inHouse': inHouse,
    };
  }

  factory AppStoreProject.fromJson(Map<String, Object?> json) {
    return AppStoreProject(
      id: (json['id'] as String?) ?? '',
      path: (json['path'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '',
      bundleId: (json['bundleId'] as String?) ?? '',
      platform: (json['platform'] as String?) ?? 'ios',
      hasSavedP8PrivateKey: (json['hasSavedP8PrivateKey'] as bool?) ?? false,
      hasSavedKeyId: (json['hasSavedKeyId'] as bool?) ?? false,
      hasSavedIssuerId: (json['hasSavedIssuerId'] as bool?) ?? false,
      hasSavedTeamId: (json['hasSavedTeamId'] as bool?) ?? false,
      inHouse: (json['inHouse'] as bool?) ?? false,
    );
  }
}
