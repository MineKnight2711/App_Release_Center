import 'dart:convert';

import 'package:app_release_center/app/models/app_store_project.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/models/release_notification.dart';
import 'package:app_release_center/app/models/remote_control.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class ProjectStoreService extends GetxService {
  static const _lastProjectKey = 'last_project_path';
  static const _recentProjectsKey = 'recent_project_paths';
  static const _chPlayProjectsKey = 'ch_play_projects';
  static const _appStoreProjectsKey = 'app_store_projects';
  static const _notificationSettingsKey = 'release_notification_settings';
  static const _linkedNotificationDevicesKey = 'linked_notification_devices';
  static const _remoteControlSettingsKey = 'remote_control_settings';
  static const _mobileControlSettingsKey = 'mobile_control_settings';

  late final SharedPreferences _preferences;

  Future<ProjectStoreService> init() async {
    _preferences = await SharedPreferences.getInstance();
    return this;
  }

  String? get lastProjectPath => _preferences.getString(_lastProjectKey);

  List<String> get recentProjectPaths {
    return _preferences.getStringList(_recentProjectsKey) ?? const [];
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

    await _preferences.setString(_lastProjectKey, normalizedPath);
    await _preferences.setStringList(_recentProjectsKey, paths);
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
