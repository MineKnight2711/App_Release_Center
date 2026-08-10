import 'dart:convert';

import 'package:app_release_center/app/models/api_tool.dart';
import 'package:app_release_center/app/models/app_store_project.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/models/release_notification.dart';
import 'package:app_release_center/app/models/resource_catalog.dart';
import 'package:app_release_center/app/models/resource_collection.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'removes recent project paths without deleting saved projects',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = await ProjectStoreService().init();

      await service.saveProjectPath(r'C:\apps\demo-a');
      await service.saveProjectPath(r'C:\apps\demo-b');

      expect(service.recentProjectPaths, [
        r'C:\apps\demo-b',
        r'C:\apps\demo-a',
      ]);
      expect(service.lastProjectPath, r'C:\apps\demo-b');

      await service.removeRecentProjectPath(r'C:\apps\demo-a');

      expect(service.recentProjectPaths, [r'C:\apps\demo-b']);
      expect(service.lastProjectPath, r'C:\apps\demo-b');

      await service.removeRecentProjectPath(r'C:\apps\demo-b');

      expect(service.recentProjectPaths, isEmpty);
      expect(service.lastProjectPath, isNull);

      await service.saveProjectPath(r'C:\apps\demo-b');

      expect(service.recentProjectPaths, [r'C:\apps\demo-b']);
      expect(
        service.dismissedRecentProjectPaths,
        isNot(contains(r'C:\apps\demo-b')),
      );
      expect(service.lastProjectPath, r'C:\apps\demo-b');
    },
  );

  test('stores and loads managed CH Play projects', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await ProjectStoreService().init();

    const project = ChPlayProject(
      id: 'project-1',
      path: r'C:\apps\demo',
      displayName: 'Demo',
      applicationId: 'com.example.demo',
      hasSavedGooglePlayJson: true,
      hasSavedJksPath: true,
    );

    await service.saveChPlayProjects([project]);

    final loaded = service.chPlayProjects;
    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'project-1');
    expect(loaded.single.applicationId, 'com.example.demo');
    expect(loaded.single.hasSavedGooglePlayJson, isTrue);
    expect(loaded.single.hasSavedSigningCredentials, isTrue);
  });

  test('stores App Store projects separately from CH Play projects', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await ProjectStoreService().init();

    const chPlayProject = ChPlayProject(
      id: 'android-1',
      path: r'C:\apps\android-demo',
      displayName: 'Android Demo',
      applicationId: 'com.example.android',
    );
    const appStoreProject = AppStoreProject(
      id: 'ios-1',
      path: r'C:\apps\ios-demo',
      displayName: 'iOS Demo',
      bundleId: 'com.example.ios',
      hasSavedP8PrivateKey: true,
      hasSavedKeyId: true,
      hasSavedIssuerId: true,
    );

    await service.saveChPlayProjects([chPlayProject]);
    await service.saveAppStoreProjects([appStoreProject]);

    expect(service.chPlayProjects.single.applicationId, 'com.example.android');
    expect(service.appStoreProjects.single.bundleId, 'com.example.ios');
    expect(service.appStoreProjects.single.platform, 'ios');
    expect(service.appStoreProjects.single.hasSavedRequiredCredentials, isTrue);
  });

  test('stores notification settings and linked devices', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await ProjectStoreService().init();

    await service.saveNotificationSettings(
      const ReleaseNotificationSettings(
        enabled: true,
        endpointBaseUrl: 'https://example.com/api',
        selectedDeviceIds: ['phone-1'],
      ),
    );
    await service.saveLinkedNotificationDevices([
      LinkedNotificationDevice(
        id: 'phone-1',
        displayName: 'Pixel',
        platform: 'Android',
        browser: 'Chrome',
        linkedAt: DateTime.utc(2026, 7, 1),
      ),
    ]);

    expect(service.notificationSettings.enabled, isTrue);
    expect(
      service.notificationSettings.endpointBaseUrl,
      'https://example.com/api',
    );
    expect(service.notificationSettings.selectedDeviceIds, ['phone-1']);
    expect(service.linkedNotificationDevices.single.label, 'Pixel');
  });

  test(
    'stores resource collection preferences without secret values',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = await ProjectStoreService().init();

      await service.saveResourceCollectionSettings(
        const ResourceCollectionSettings(
          sourcePath: r'C:\apps\demo',
          targetPath: r'D:\exports',
          preset: ResourceCollectionPreset.custom,
          customKinds: {
            ResourceTargetKind.envFile,
            ResourceTargetKind.signingKey,
          },
          includeSigningCredentials: true,
        ),
      );

      final settings = service.resourceCollectionSettings;
      expect(settings.sourcePath, r'C:\apps\demo');
      expect(settings.targetPath, r'D:\exports');
      expect(settings.preset, ResourceCollectionPreset.custom);
      expect(settings.customKinds, {
        ResourceTargetKind.envFile,
        ResourceTargetKind.signingKey,
      });
      expect(settings.includeSigningCredentials, isTrue);
    },
  );

  test('stores resource catalogs by project path without passwords', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await ProjectStoreService().init();

    await service.saveResourceCatalog(
      ResourceCatalogBundle(
        projectPath: r'C:\apps\demo',
        resources: [
          ResourceCatalogItem(
            id: 'resource-1',
            kind: ResourceCatalogKind.googleSheet,
            title: 'Task tracker',
            url: 'https://docs.google.com/spreadsheets/d/demo',
            updatedAt: DateTime.utc(2026, 8, 3),
          ),
        ],
        passwords: [
          ResourcePasswordEntry(
            id: 'password-1',
            secretKey: 'secret-key-1',
            site: 'Admin',
            username: 'release@example.com',
            updatedAt: DateTime.utc(2026, 8, 3),
          ),
        ],
      ),
    );

    final catalog = service.resourceCatalogForProject(r'C:\apps\demo');
    expect(catalog.resources.single.kind, ResourceCatalogKind.googleSheet);
    expect(catalog.passwords.single.secretKey, 'secret-key-1');
    expect(
      service.resourceCatalogForProject(r'C:\apps\other').resources,
      isEmpty,
    );
  });

  test('stores API tool requests and caps history', () async {
    final historyEntries = List.generate(55, (index) {
      return jsonEncode(
        ApiToolHistoryEntry(
          id: 'history-$index',
          request: ApiToolRequest(
            id: 'request-$index',
            name: 'Request $index',
            method: ApiToolMethod.get,
            url: 'https://example.com/$index',
            updatedAt: DateTime.utc(2026, 8, 4, 10, index),
          ),
          statusCode: 200,
          durationMs: index,
          sentAt: DateTime.utc(2026, 8, 4, 10, index),
        ).toJson(),
      );
    });
    SharedPreferences.setMockInitialValues({
      'api_tool_requests': [
        'invalid-json',
        jsonEncode(
          ApiToolRequest(
            id: 'request-1',
            name: 'Saved request',
            method: ApiToolMethod.post,
            url: 'https://example.com/users',
            headers: const [
              ApiToolHeader(
                id: 'header-1',
                name: 'Authorization',
                value: 'Bearer token',
              ),
            ],
            bodyMode: ApiToolBodyMode.multipart,
            body: '{"name":"Demo"}',
            multipartFields: const [
              ApiToolMultipartEntry(
                id: 'part-1',
                name: 'asset',
                value: r'C:\tmp\demo.txt',
                kind: ApiToolMultipartKind.file,
                contentType: 'text/plain',
              ),
            ],
            updatedAt: DateTime.utc(2026, 8, 4),
          ).toJson(),
        ),
      ],
      'api_tool_history': ['broken', ...historyEntries],
    });
    final service = await ProjectStoreService().init();

    expect(service.apiToolRequests, hasLength(1));
    expect(service.apiToolRequests.single.method, ApiToolMethod.post);
    expect(service.apiToolRequests.single.headers.single.name, 'Authorization');
    expect(service.apiToolRequests.single.bodyMode, ApiToolBodyMode.multipart);
    expect(
      service.apiToolRequests.single.multipartFields.single.kind,
      ApiToolMultipartKind.file,
    );
    expect(service.apiToolHistory, hasLength(50));
    expect(service.apiToolHistory.first.id, 'history-54');

    await service.saveApiToolHistory([
      ...service.apiToolHistory,
      ApiToolHistoryEntry(
        id: 'history-new',
        request: ApiToolRequest(
          id: 'request-new',
          name: 'Newest',
          method: ApiToolMethod.delete,
          url: 'https://example.com/new',
          updatedAt: DateTime.utc(2026, 8, 4, 12),
        ),
        statusCode: 204,
        durationMs: 15,
        sentAt: DateTime.utc(2026, 8, 4, 12),
      ),
    ]);

    expect(service.apiToolHistory, hasLength(50));
    expect(service.apiToolHistory.first.id, 'history-new');
  });

  test('stores API tool collection folders and environments', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await ProjectStoreService().init();

    await service.saveApiToolCollections([
      ApiToolCollectionRoot(
        id: 'collection-1',
        name: 'CRM',
        activeEnvironmentId: 'env-1',
        environments: [
          ApiToolEnvironment(
            id: 'env-1',
            name: 'Local',
            variables: const [
              ApiToolEnvironmentVariable(
                id: 'var-1',
                name: 'BASE_URL',
                value: 'https://local.example.com',
              ),
            ],
            updatedAt: DateTime.utc(2026, 8, 4),
          ),
        ],
        updatedAt: DateTime.utc(2026, 8, 4),
      ),
    ]);
    await service.saveApiToolFolders([
      ApiToolCollectionFolder(
        id: 'folder-1',
        collectionId: 'collection-1',
        name: 'Auth',
        updatedAt: DateTime.utc(2026, 8, 4),
      ),
      ApiToolCollectionFolder(
        id: 'folder-2',
        collectionId: 'collection-1',
        parentFolderId: 'folder-1',
        name: 'OAuth',
        updatedAt: DateTime.utc(2026, 8, 4),
      ),
    ]);

    expect(service.apiToolCollections.single.displayName, 'CRM');
    expect(
      service.apiToolCollections.single.activeEnvironment?.enabledVariables,
      {'BASE_URL': 'https://local.example.com'},
    );
    expect(service.apiToolFolders, hasLength(2));
    expect(service.apiToolFolders.last.parentFolderId, 'folder-1');
  });
}
