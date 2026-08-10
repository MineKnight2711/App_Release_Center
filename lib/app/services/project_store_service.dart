import 'dart:convert';

import 'package:app_release_center/app/models/api_tool.dart';
import 'package:app_release_center/app/models/auth_models.dart';
import 'package:app_release_center/app/models/app_store_project.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/models/google_drive_release_settings.dart';
import 'package:app_release_center/app/models/release_notification.dart';
import 'package:app_release_center/app/models/resource_catalog.dart';
import 'package:app_release_center/app/models/resource_collection.dart';
import 'package:app_release_center/app/models/remote_control.dart';
import 'package:app_release_center/app/models/telegram_release_settings.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class ProjectStoreService extends GetxService implements AuthSessionStore {
  static const _lastProjectKey = 'last_project_path';
  static const _recentProjectsKey = 'recent_project_paths';
  static const _dismissedRecentProjectsKey = 'dismissed_recent_project_paths';
  static const _authSessionKey = 'auth_session';
  static const _chPlayProjectsKey = 'ch_play_projects';
  static const _appStoreProjectsKey = 'app_store_projects';
  static const _notificationSettingsKey = 'release_notification_settings';
  static const _linkedNotificationDevicesKey = 'linked_notification_devices';
  static const _remoteControlSettingsKey = 'remote_control_settings';
  static const _mobileControlSettingsKey = 'mobile_control_settings';
  static const _telegramReleaseSettingsKey = 'telegram_release_settings';
  static const _googleDriveReleaseSettingsKey = 'google_drive_release_settings';
  static const _resourceCollectionSettingsKey = 'resource_collection_settings';
  static const _resourceCatalogsKey = 'resource_catalogs';
  static const _apiToolCollectionsKey = 'api_tool_collections';
  static const _apiToolFoldersKey = 'api_tool_folders';
  static const _apiToolRequestsKey = 'api_tool_requests';
  static const _apiToolHistoryKey = 'api_tool_history';
  static const _apiToolHistoryLimit = 50;

  late final SharedPreferences _preferences;

  Future<ProjectStoreService> init() async {
    _preferences = await SharedPreferences.getInstance();
    return this;
  }

  String? get lastProjectPath => _preferences.getString(_lastProjectKey);

  List<String> get recentProjectPaths {
    return _preferences.getStringList(_recentProjectsKey) ?? const [];
  }

  List<String> get dismissedRecentProjectPaths {
    return _preferences.getStringList(_dismissedRecentProjectsKey) ?? const [];
  }

  @override
  AuthSessionMetadata? get authSession {
    final entry = _preferences.getString(_authSessionKey);
    if (entry == null || entry.trim().isEmpty) return null;

    try {
      final json = jsonDecode(entry);
      if (json is Map<String, Object?>) {
        final session = AuthSessionMetadata.fromJson(json);
        if (session.uid.isNotEmpty) return session;
      }
    } catch (_) {
      // Ignore invalid legacy entries and ask the user to sign in again.
    }

    return null;
  }

  List<ChPlayProject> get chPlayProjects {
    final entries = _preferences.getStringList(_chPlayProjectsKey) ?? const [];
    final projects = <ChPlayProject>[];

    for (final entry in entries) {
      try {
        final json = jsonDecode(entry);
        if (json is Map<String, Object?>) {
          final project = ChPlayProject.fromJson(json);
          if (project.id.isNotEmpty && project.path.isNotEmpty) {
            projects.add(project);
          }
        }
      } catch (_) {
        // Ignore invalid legacy entries and keep loading the rest.
      }
    }

    return projects;
  }

  List<AppStoreProject> get appStoreProjects {
    final entries =
        _preferences.getStringList(_appStoreProjectsKey) ?? const [];
    final projects = <AppStoreProject>[];

    for (final entry in entries) {
      try {
        final json = jsonDecode(entry);
        if (json is Map<String, Object?>) {
          final project = AppStoreProject.fromJson(json);
          if (project.id.isNotEmpty && project.path.isNotEmpty) {
            projects.add(project);
          }
        }
      } catch (_) {
        // Ignore invalid entries and keep loading the rest.
      }
    }

    return projects;
  }

  ReleaseNotificationSettings get notificationSettings {
    final entry = _preferences.getString(_notificationSettingsKey);
    if (entry == null || entry.trim().isEmpty) {
      return const ReleaseNotificationSettings();
    }

    try {
      final json = jsonDecode(entry);
      if (json is Map<String, Object?>) {
        return ReleaseNotificationSettings.fromJson(json);
      }
    } catch (_) {
      // Ignore invalid legacy entries and fall back to defaults.
    }

    return const ReleaseNotificationSettings();
  }

  TelegramReleaseSettings get telegramReleaseSettings {
    final entry = _preferences.getString(_telegramReleaseSettingsKey);
    if (entry == null || entry.trim().isEmpty) {
      return const TelegramReleaseSettings();
    }

    try {
      final json = jsonDecode(entry);
      if (json is Map<String, Object?>) {
        return TelegramReleaseSettings.fromJson(json);
      }
    } catch (_) {
      // Ignore invalid or legacy entries and fall back to safe defaults.
    }

    return const TelegramReleaseSettings();
  }

  GoogleDriveReleaseSettings get googleDriveReleaseSettings {
    final entry = _preferences.getString(_googleDriveReleaseSettingsKey);
    if (entry == null || entry.trim().isEmpty) {
      return const GoogleDriveReleaseSettings();
    }

    try {
      final json = jsonDecode(entry);
      if (json is Map<String, Object?>) {
        return GoogleDriveReleaseSettings.fromJson(json);
      }
    } catch (_) {
      // Ignore invalid or legacy entries and fall back to safe defaults.
    }

    return const GoogleDriveReleaseSettings();
  }

  ResourceCollectionSettings get resourceCollectionSettings {
    final entry = _preferences.getString(_resourceCollectionSettingsKey);
    if (entry == null || entry.trim().isEmpty) {
      return const ResourceCollectionSettings();
    }

    try {
      final json = jsonDecode(entry);
      if (json is Map<String, Object?>) {
        return ResourceCollectionSettings.fromJson(json);
      }
    } catch (_) {
      // Ignore invalid or legacy entries and fall back to safe defaults.
    }

    return const ResourceCollectionSettings();
  }

  List<ResourceCatalogBundle> get resourceCatalogs {
    final entries =
        _preferences.getStringList(_resourceCatalogsKey) ?? const [];
    final catalogs = <ResourceCatalogBundle>[];

    for (final entry in entries) {
      try {
        final json = jsonDecode(entry);
        if (json is Map<String, Object?>) {
          final catalog = ResourceCatalogBundle.fromJson(json);
          if (catalog.projectPath.isNotEmpty) {
            catalogs.add(catalog);
          }
        }
      } catch (_) {
        // Ignore invalid entries and keep loading the rest.
      }
    }

    return catalogs;
  }

  List<ApiToolRequest> get apiToolRequests {
    final entries = _preferences.getStringList(_apiToolRequestsKey) ?? const [];
    final requests = <ApiToolRequest>[];

    for (final entry in entries) {
      try {
        final json = jsonDecode(entry);
        if (json is Map<String, Object?>) {
          final request = ApiToolRequest.fromJson(json);
          if (request.id.isNotEmpty) {
            requests.add(request);
          }
        }
      } catch (_) {
        // Ignore invalid entries and keep loading the rest.
      }
    }

    requests.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return requests;
  }

  List<ApiToolCollectionRoot> get apiToolCollections {
    final entries =
        _preferences.getStringList(_apiToolCollectionsKey) ?? const [];
    final collections = <ApiToolCollectionRoot>[];

    for (final entry in entries) {
      try {
        final json = jsonDecode(entry);
        if (json is Map<String, Object?>) {
          final collection = ApiToolCollectionRoot.fromJson(json);
          if (collection.id.isNotEmpty) {
            collections.add(collection);
          }
        }
      } catch (_) {
        // Ignore invalid entries and keep loading the rest.
      }
    }

    collections.sort((a, b) => a.displayName.compareTo(b.displayName));
    return collections;
  }

  List<ApiToolCollectionFolder> get apiToolFolders {
    final entries = _preferences.getStringList(_apiToolFoldersKey) ?? const [];
    final folders = <ApiToolCollectionFolder>[];

    for (final entry in entries) {
      try {
        final json = jsonDecode(entry);
        if (json is Map<String, Object?>) {
          final folder = ApiToolCollectionFolder.fromJson(json);
          if (folder.id.isNotEmpty && folder.collectionId.isNotEmpty) {
            folders.add(folder);
          }
        }
      } catch (_) {
        // Ignore invalid entries and keep loading the rest.
      }
    }

    folders.sort((a, b) => a.displayName.compareTo(b.displayName));
    return folders;
  }

  List<ApiToolHistoryEntry> get apiToolHistory {
    final entries = _preferences.getStringList(_apiToolHistoryKey) ?? const [];
    final history = <ApiToolHistoryEntry>[];

    for (final entry in entries) {
      try {
        final json = jsonDecode(entry);
        if (json is Map<String, Object?>) {
          final historyEntry = ApiToolHistoryEntry.fromJson(json);
          if (historyEntry.id.isNotEmpty) {
            history.add(historyEntry);
          }
        }
      } catch (_) {
        // Ignore invalid entries and keep loading the rest.
      }
    }

    history.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return history.take(_apiToolHistoryLimit).toList();
  }

  ResourceCatalogBundle resourceCatalogForProject(String projectPath) {
    final normalizedPath = p.normalize(projectPath);
    final lowerPath = normalizedPath.toLowerCase();
    for (final catalog in resourceCatalogs) {
      if (p.normalize(catalog.projectPath).toLowerCase() == lowerPath) {
        return catalog.copyWith(projectPath: normalizedPath);
      }
    }

    return ResourceCatalogBundle(projectPath: normalizedPath);
  }

  List<LinkedNotificationDevice> get linkedNotificationDevices {
    final entries =
        _preferences.getStringList(_linkedNotificationDevicesKey) ?? const [];
    final devices = <LinkedNotificationDevice>[];

    for (final entry in entries) {
      try {
        final json = jsonDecode(entry);
        if (json is Map<String, Object?>) {
          final device = LinkedNotificationDevice.fromJson(json);
          if (device.id.isNotEmpty) {
            devices.add(device);
          }
        }
      } catch (_) {
        // Ignore invalid entries and keep loading the rest.
      }
    }

    return devices;
  }

  RemoteControlSettings get remoteControlSettings {
    final entry = _preferences.getString(_remoteControlSettingsKey);
    if (entry == null || entry.trim().isEmpty) {
      return const RemoteControlSettings();
    }

    try {
      final json = jsonDecode(entry);
      if (json is Map<String, Object?>) {
        return RemoteControlSettings.fromJson(json);
      }
    } catch (_) {
      // Ignore invalid entries and fall back to defaults.
    }

    return const RemoteControlSettings();
  }

  MobileControlSettings get mobileControlSettings {
    final entry = _preferences.getString(_mobileControlSettingsKey);
    if (entry == null || entry.trim().isEmpty) {
      return const MobileControlSettings();
    }

    try {
      final json = jsonDecode(entry);
      if (json is Map<String, Object?>) {
        return MobileControlSettings.fromJson(json);
      }
    } catch (_) {
      // Ignore invalid entries and fall back to defaults.
    }

    return const MobileControlSettings();
  }

  Future<void> saveProjectPath(String path) async {
    final normalizedPath = p.normalize(path);
    final lowerPath = normalizedPath.toLowerCase();
    final paths = <String>[
      normalizedPath,
      ...recentProjectPaths.where(
        (existingPath) => existingPath.toLowerCase() != lowerPath,
      ),
    ].take(8).toList();
    final dismissedPaths = dismissedRecentProjectPaths
        .where((existingPath) => existingPath.toLowerCase() != lowerPath)
        .toList();

    await _preferences.setString(_lastProjectKey, normalizedPath);
    await _preferences.setStringList(_recentProjectsKey, paths);
    await _preferences.setStringList(
      _dismissedRecentProjectsKey,
      dismissedPaths,
    );
  }

  Future<void> removeRecentProjectPath(String path) async {
    final normalizedPath = p.normalize(path);
    final lowerPath = normalizedPath.toLowerCase();
    final paths = recentProjectPaths
        .where((existingPath) => existingPath.toLowerCase() != lowerPath)
        .toList();
    final dismissedPaths = <String>[
      normalizedPath,
      ...dismissedRecentProjectPaths.where(
        (existingPath) => existingPath.toLowerCase() != lowerPath,
      ),
    ].take(32).toList();

    await _preferences.setStringList(_recentProjectsKey, paths);
    await _preferences.setStringList(
      _dismissedRecentProjectsKey,
      dismissedPaths,
    );

    final lastPath = lastProjectPath;
    if (lastPath != null && p.normalize(lastPath).toLowerCase() == lowerPath) {
      await _preferences.remove(_lastProjectKey);
    }
  }

  @override
  Future<void> saveAuthSession(AuthSessionMetadata session) async {
    await _preferences.setString(_authSessionKey, jsonEncode(session.toJson()));
  }

  @override
  Future<void> clearAuthSession() async {
    await _preferences.remove(_authSessionKey);
  }

  Future<void> saveChPlayProjects(List<ChPlayProject> projects) async {
    final entries = projects
        .map((project) => jsonEncode(project.toJson()))
        .toList();
    await _preferences.setStringList(_chPlayProjectsKey, entries);
  }

  Future<void> saveAppStoreProjects(List<AppStoreProject> projects) async {
    final entries = projects
        .map((project) => jsonEncode(project.toJson()))
        .toList();
    await _preferences.setStringList(_appStoreProjectsKey, entries);
  }

  Future<void> saveNotificationSettings(
    ReleaseNotificationSettings settings,
  ) async {
    await _preferences.setString(
      _notificationSettingsKey,
      jsonEncode(settings.toJson()),
    );
  }

  Future<void> saveTelegramReleaseSettings(
    TelegramReleaseSettings settings,
  ) async {
    await _preferences.setString(
      _telegramReleaseSettingsKey,
      jsonEncode(settings.toJson()),
    );
  }

  Future<void> saveGoogleDriveReleaseSettings(
    GoogleDriveReleaseSettings settings,
  ) async {
    await _preferences.setString(
      _googleDriveReleaseSettingsKey,
      jsonEncode(settings.toJson()),
    );
  }

  Future<void> saveResourceCollectionSettings(
    ResourceCollectionSettings settings,
  ) async {
    await _preferences.setString(
      _resourceCollectionSettingsKey,
      jsonEncode(settings.toJson()),
    );
  }

  Future<void> saveResourceCatalog(ResourceCatalogBundle catalog) async {
    final normalizedPath = p.normalize(catalog.projectPath);
    final lowerPath = normalizedPath.toLowerCase();
    final catalogs = resourceCatalogs
        .where(
          (entry) => p.normalize(entry.projectPath).toLowerCase() != lowerPath,
        )
        .toList();
    final normalizedCatalog = catalog.copyWith(projectPath: normalizedPath);
    if (!normalizedCatalog.isEmpty) {
      catalogs.add(normalizedCatalog);
    }
    catalogs.sort((a, b) => a.projectPath.compareTo(b.projectPath));

    await _preferences.setStringList(
      _resourceCatalogsKey,
      catalogs.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }

  Future<void> saveApiToolRequests(List<ApiToolRequest> requests) async {
    final normalized = requests.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    await _preferences.setStringList(
      _apiToolRequestsKey,
      normalized.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }

  Future<void> saveApiToolCollections(
    List<ApiToolCollectionRoot> collections,
  ) async {
    final normalized = collections.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    await _preferences.setStringList(
      _apiToolCollectionsKey,
      normalized.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }

  Future<void> saveApiToolFolders(List<ApiToolCollectionFolder> folders) async {
    final normalized = folders.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    await _preferences.setStringList(
      _apiToolFoldersKey,
      normalized.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }

  Future<void> saveApiToolHistory(List<ApiToolHistoryEntry> history) async {
    final normalized =
        (history.toList()..sort((a, b) => b.sentAt.compareTo(a.sentAt)))
            .take(_apiToolHistoryLimit)
            .toList();

    await _preferences.setStringList(
      _apiToolHistoryKey,
      normalized.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }

  Future<void> saveLinkedNotificationDevices(
    List<LinkedNotificationDevice> devices,
  ) async {
    final entries = devices
        .map((device) => jsonEncode(device.toJson()))
        .toList();
    await _preferences.setStringList(_linkedNotificationDevicesKey, entries);
  }

  Future<void> saveRemoteControlSettings(RemoteControlSettings settings) async {
    await _preferences.setString(
      _remoteControlSettingsKey,
      jsonEncode(settings.toJson()),
    );
  }

  Future<void> saveMobileControlSettings(MobileControlSettings settings) async {
    await _preferences.setString(
      _mobileControlSettingsKey,
      jsonEncode(settings.toJson()),
    );
  }
}
