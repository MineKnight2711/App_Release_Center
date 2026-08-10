import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:app_release_center/app/controllers/home_controller.dart';
import 'package:app_release_center/app/data/release_center_connect.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/models/release_script.dart';
import 'package:app_release_center/app/services/android_cicd_clone_service.dart';
import 'package:app_release_center/app/services/android_keystore_generation_service.dart';
import 'package:app_release_center/app/services/app_store_credential_store_service.dart';
import 'package:app_release_center/app/services/app_store_project_inspector_service.dart';
import 'package:app_release_center/app/services/app_store_version_check_service.dart';
import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_release_center/app/services/ch_play_project_inspector_service.dart';
import 'package:app_release_center/app/services/ch_play_version_check_service.dart';
import 'package:app_release_center/app/services/command_notification_service.dart';
import 'package:app_release_center/app/services/gemini_env_service.dart';
import 'package:app_release_center/app/services/google_drive_credential_store_service.dart';
import 'package:app_release_center/app/services/google_drive_release_upload_service.dart';
import 'package:app_release_center/app/services/notification_credential_store_service.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:app_release_center/app/services/release_apk_artifact_service.dart';
import 'package:app_release_center/app/services/release_installer_artifact_service.dart';
import 'package:app_release_center/app/services/release_note_generation_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:app_release_center/app/services/script_catalog_service.dart';
import 'package:app_release_center/app/services/telegram_credential_store_service.dart';
import 'package:app_release_center/app/services/telegram_release_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('auto sends only after successful generation when enabled', () async {
    final harness = await _ControllerHarness.create();
    addTearDown(harness.dispose);
    harness.telegramClient.responses.add(
      const TelegramHttpResponse(statusCode: 200, body: {'ok': true}),
    );
    await harness.enableTelegramAutoSend();

    await harness.controller.generateReleaseNotes();

    expect(harness.controller.releaseNotesController.text, 'Nội dung mới.');
    expect(harness.telegramClient.requests, hasLength(1));
    expect(
      harness.telegramClient.requests.single.body['text'],
      contains('Phiên bản: 2.3.4+56'),
    );
    expect(
      harness.controller.telegramReleaseStatus.value,
      'Release notes sent to Telegram.',
    );
  });

  test('does not auto send while Telegram auto send is disabled', () async {
    final harness = await _ControllerHarness.create();
    addTearDown(harness.dispose);

    await harness.controller.generateReleaseNotes();

    expect(harness.controller.releaseNotesController.text, 'Nội dung mới.');
    expect(harness.telegramClient.requests, isEmpty);
  });

  test('keeps generated notes when Telegram rejects auto send', () async {
    final harness = await _ControllerHarness.create();
    addTearDown(harness.dispose);
    harness.telegramClient.responses.add(
      const TelegramHttpResponse(
        statusCode: 403,
        body: {'ok': false, 'description': 'Forbidden'},
      ),
    );
    await harness.enableTelegramAutoSend();

    await harness.controller.generateReleaseNotes();

    expect(harness.controller.releaseNotesController.text, 'Nội dung mới.');
    expect(
      harness.controller.releaseNoteAiStatus.value,
      startsWith('Generated from'),
    );
    expect(
      harness.controller.telegramReleaseStatus.value,
      contains('Telegram send failed'),
    );
  });

  test(
    'manual send uses edited notes and is disabled after project change',
    () async {
      final harness = await _ControllerHarness.create();
      addTearDown(harness.dispose);
      await harness.saveTelegramConfiguration();
      await harness.controller.generateReleaseNotes();
      harness.controller.releaseNotesController.text = 'Nội dung đã chỉnh sửa.';
      harness.telegramClient.responses.add(
        const TelegramHttpResponse(statusCode: 200, body: {'ok': true}),
      );

      await harness.controller.sendCurrentReleaseNoteToTelegram();

      expect(
        harness.telegramClient.requests.single.body['text'],
        endsWith('Nội dung đã chỉnh sửa.'),
      );

      final otherProject = await Directory(
        '${harness.root.path}${Platform.pathSeparator}other_project',
      ).create();
      await harness.controller.loadProject(otherProject.path);
      expect(harness.controller.hasTelegramReleaseContext.value, isFalse);
      expect(harness.controller.releaseNotesController.text, isEmpty);

      await harness.controller.sendCurrentReleaseNoteToTelegram();
      expect(harness.telegramClient.requests, hasLength(1));
      expect(
        harness.controller.telegramReleaseStatus.value,
        contains('Generate release notes'),
      );
    },
  );

  test(
    'successful CH Play deploy builds, renames, and uploads the release APK',
    () async {
      final harness = await _ControllerHarness.create();
      addTearDown(harness.dispose);
      final script = await harness.createDeployScript(exitCode: 0);
      harness.controller.chPlayProjects.add(
        ChPlayProject(
          id: 'fizahub',
          path: harness.root.path,
          displayName: 'FizaHUB',
          applicationId: 'com.example.fizahub',
        ),
      );
      harness.controller.playUploadChoice.value = PlayUploadChoice.upload;
      harness.telegramClient.responses.add(
        const TelegramHttpResponse(statusCode: 200, body: {'ok': true}),
      );
      await harness.enableTelegramAutoSend();

      await harness.controller.runScript(script);

      final expectedApk = File(
        p.join(
          harness.root.path,
          'build',
          'app',
          'outputs',
          'flutter-apk',
          'FizaHUB_v2.0.1_21_07_2026.apk',
        ),
      );
      expect(harness.apkExecutor.callCount, 1);
      expect(expectedApk.existsSync(), isTrue);
      expect(harness.telegramClient.uploads, hasLength(1));
      expect(
        harness.telegramClient.uploads.single.fileName,
        'FizaHUB_v2.0.1_21_07_2026.apk',
      );
      expect(harness.controller.runner.workflowTotalSteps.value, 3);
      expect(harness.controller.runner.overallProgress.value, 1);
      expect(harness.controller.runner.status.value, 'Completed');
    },
  );

  test('oversized APK uploads to Drive and sends a Telegram link', () async {
    final harness = await _ControllerHarness.create();
    addTearDown(harness.dispose);
    final script = await harness.createDeployScript(exitCode: 0);
    harness.apkExecutor.apkSizeBytes = 151 * 1024 * 1024;
    harness.controller.chPlayProjects.add(
      ChPlayProject(
        id: 'fizahub',
        path: harness.root.path,
        displayName: 'FizaHUB',
        applicationId: 'com.example.fizahub',
      ),
    );
    harness.controller.playUploadChoice.value = PlayUploadChoice.upload;
    harness.telegramClient.responses.add(
      const TelegramHttpResponse(statusCode: 200, body: {'ok': true}),
    );
    await harness.enableTelegramAutoSend();
    await harness.enableGoogleDriveFallback();

    await harness.controller.runScript(script);

    expect(harness.apkExecutor.callCount, 1);
    expect(harness.telegramClient.uploads, isEmpty);
    expect(harness.googleDriveApiClient.folderCreateCount, 1);
    expect(harness.googleDriveApiClient.uploads, [
      'FizaHUB_v2.0.1_21_07_2026.apk',
    ]);
    expect(harness.googleDriveApiClient.sharedFileIds, ['drive-file-id']);
    final message = harness.telegramClient.requests.single.body['text'];
    expect(message, contains('Google Drive'));
    expect(message, contains('FizaHUB'));
    expect(message, contains('2.0.1+45'));
    expect(message, contains('FizaHUB_v2.0.1_21_07_2026.apk'));
    expect(message, contains('151.0 MB'));
    expect(
      message,
      contains('https://drive.google.com/file/d/drive-file-id/view'),
    );
    expect(harness.controller.runner.workflowTotalSteps.value, 3);
    expect(harness.controller.runner.status.value, 'Completed');
  });

  test('manual Drive APK action builds when no release APK exists', () async {
    final harness = await _ControllerHarness.create();
    addTearDown(harness.dispose);
    harness.controller.chPlayProjects.add(
      ChPlayProject(
        id: 'fizahub',
        path: harness.root.path,
        displayName: 'FizaHUB',
        applicationId: 'com.example.fizahub',
      ),
    );
    await harness.connectGoogleDriveOnly();

    await harness.controller.buildOrUploadReleaseApkToGoogleDrive();

    expect(harness.apkExecutor.callCount, 1);
    expect(harness.googleDriveApiClient.uploads, [
      'FizaHUB_v2.0.1_21_07_2026.apk',
    ]);
    expect(harness.googleDriveApiClient.sharedFileIds, ['drive-file-id']);
    expect(harness.telegramClient.requests, isEmpty);
    expect(harness.telegramClient.uploads, isEmpty);
    expect(harness.controller.runner.workflowTotalSteps.value, 2);
    expect(harness.controller.runner.status.value, 'Completed');
    expect(
      harness.controller.googleDriveReleaseStatus.value,
      contains('Release APK uploaded to Google Drive'),
    );
  });

  test(
    'manual Drive APK action sends Telegram link with release notes when enabled',
    () async {
      final harness = await _ControllerHarness.create();
      addTearDown(harness.dispose);
      harness.controller.chPlayProjects.add(
        ChPlayProject(
          id: 'fizahub',
          path: harness.root.path,
          displayName: 'FizaHUB',
          applicationId: 'com.example.fizahub',
        ),
      );
      harness.controller.releaseNotesController.text = 'Fixed checkout crash.';
      harness.telegramClient.responses.add(
        const TelegramHttpResponse(statusCode: 200, body: {'ok': true}),
      );
      await harness.enableGoogleDriveApkLinkToTelegram(
        includeReleaseNotes: true,
      );

      await harness.controller.buildOrUploadReleaseApkToGoogleDrive();

      expect(harness.apkExecutor.callCount, 1);
      expect(harness.googleDriveApiClient.uploads, [
        'FizaHUB_v2.0.1_21_07_2026.apk',
      ]);
      expect(harness.telegramClient.uploads, isEmpty);
      expect(harness.telegramClient.requests, hasLength(1));
      final message = harness.telegramClient.requests.single.body['text'];
      expect(
        message,
        contains('https://drive.google.com/file/d/drive-file-id/view'),
      );
      expect(message, contains('Release notes:'));
      expect(message, contains('Fixed checkout crash.'));
      expect(harness.controller.runner.workflowTotalSteps.value, 3);
      expect(harness.controller.runner.status.value, 'Completed');
    },
  );

  test(
    'manual Drive APK action uploads existing APK without building',
    () async {
      final harness = await _ControllerHarness.create();
      addTearDown(harness.dispose);
      harness.controller.chPlayProjects.add(
        ChPlayProject(
          id: 'fizahub',
          path: harness.root.path,
          displayName: 'FizaHUB',
          applicationId: 'com.example.fizahub',
        ),
      );
      final output = await Directory(
        p.join(harness.root.path, 'build', 'app', 'outputs', 'flutter-apk'),
      ).create(recursive: true);
      await File(
        p.join(output.path, 'FizaHUB_v2.0.1_21_07_2026.apk'),
      ).writeAsString('existing-apk');
      await harness.connectGoogleDriveOnly();

      await harness.controller.buildOrUploadReleaseApkToGoogleDrive();

      expect(harness.apkExecutor.callCount, 0);
      expect(harness.googleDriveApiClient.uploads, [
        'FizaHUB_v2.0.1_21_07_2026.apk',
      ]);
      expect(harness.googleDriveApiClient.sharedFileIds, ['drive-file-id']);
      expect(harness.controller.runner.workflowTotalSteps.value, 1);
      expect(harness.controller.runner.status.value, 'Completed');
      expect(
        harness.controller.runner.logLines,
        contains(
          'Existing release APK found: '
          '${p.join(output.path, 'FizaHUB_v2.0.1_21_07_2026.apk')}',
        ),
      );
    },
  );

  test(
    'installer action requires Telegram configuration before build',
    () async {
      final harness = await _ControllerHarness.create();
      addTearDown(harness.dispose);

      await harness.controller.buildAndSendWindowsInstallerToTelegram();

      expect(harness.installerExecutor.buildCallCount, 0);
      expect(harness.installerExecutor.packageCallCount, 0);
      expect(harness.telegramClient.requests, isEmpty);
      expect(harness.telegramClient.uploads, isEmpty);
      expect(
        harness.controller.installerDeliveryStatus.value,
        contains('Telegram bot token is required'),
      );
    },
  );

  test('installer action builds and sends direct Telegram document', () async {
    final harness = await _ControllerHarness.create();
    addTearDown(harness.dispose);
    harness.telegramClient.responses.add(
      const TelegramHttpResponse(statusCode: 200, body: {'ok': true}),
    );
    await harness.saveTelegramConfiguration();

    await harness.controller.buildAndSendWindowsInstallerToTelegram();

    expect(harness.installerExecutor.buildCallCount, 1);
    expect(harness.installerExecutor.packageCallCount, 1);
    expect(harness.telegramClient.requests, isEmpty);
    expect(harness.telegramClient.uploads, hasLength(1));
    expect(
      harness.telegramClient.uploads.single.fileName,
      'AppReleaseCenter_Setup_v2.0.1.exe',
    );
    expect(
      harness.telegramClient.uploads.single.contentType,
      windowsInstallerContentType,
    );
    expect(harness.controller.runner.workflowTotalSteps.value, 3);
    expect(harness.controller.runner.status.value, 'Completed');
    expect(
      harness.controller.installerDeliveryStatus.value,
      'Windows installer sent to Telegram.',
    );
  });

  test(
    'oversized installer uploads to Drive and sends Telegram link',
    () async {
      final harness = await _ControllerHarness.create();
      addTearDown(harness.dispose);
      harness.installerExecutor.installerSizeBytes = 151 * 1024 * 1024;
      harness.telegramClient.responses.add(
        const TelegramHttpResponse(statusCode: 200, body: {'ok': true}),
      );
      await harness.saveTelegramConfiguration();
      await harness.connectGoogleDriveOnly();

      await harness.controller.buildAndSendWindowsInstallerToTelegram();

      expect(harness.installerExecutor.buildCallCount, 1);
      expect(harness.telegramClient.uploads, isEmpty);
      expect(harness.googleDriveApiClient.uploads, [
        'AppReleaseCenter_Setup_v2.0.1.exe',
      ]);
      expect(harness.googleDriveApiClient.uploadContentTypes, [
        windowsInstallerContentType,
      ]);
      final message = harness.telegramClient.requests.single.body['text'];
      expect(message, contains('Installer is over Telegram 50 MB limit'));
      expect(message, contains('App Release Center'));
      expect(message, contains('2.0.1+45'));
      expect(
        message,
        contains('https://drive.google.com/file/d/drive-file-id/view'),
      );
      expect(harness.controller.runner.status.value, 'Completed');
    },
  );

  test(
    'oversized installer without Drive config fails after keeping local file',
    () async {
      final harness = await _ControllerHarness.create();
      addTearDown(harness.dispose);
      harness.installerExecutor.installerSizeBytes = 151 * 1024 * 1024;
      await harness.saveTelegramConfiguration();

      await harness.controller.buildAndSendWindowsInstallerToTelegram();

      final installer = File(
        p.join(
          harness.root.path,
          'build',
          'installer',
          'AppReleaseCenter_Setup_v2.0.1.exe',
        ),
      );
      expect(installer.existsSync(), isTrue);
      expect(harness.telegramClient.requests, isEmpty);
      expect(harness.telegramClient.uploads, isEmpty);
      expect(harness.googleDriveApiClient.uploads, isEmpty);
      expect(
        harness.controller.installerDeliveryStatus.value,
        contains('Installer kept at'),
      );
      expect(harness.controller.runner.status.value, 'Failed');
    },
  );

  test('failed CH Play deploy does not build or upload an APK', () async {
    final harness = await _ControllerHarness.create();
    addTearDown(harness.dispose);
    final script = await harness.createDeployScript(exitCode: 1);
    harness.controller.playUploadChoice.value = PlayUploadChoice.upload;
    await harness.enableTelegramAutoSend();

    await harness.controller.runScript(script);

    expect(harness.apkExecutor.callCount, 0);
    expect(harness.telegramClient.uploads, isEmpty);
    expect(harness.controller.runner.workflowTotalSteps.value, 3);
    expect(
      harness.controller.runner.overallProgress.value,
      closeTo(1 / 3, 0.001),
    );
    expect(harness.controller.runner.status.value, 'Failed');
  });

  test(
    'builds and keeps the APK when Telegram auto send is disabled',
    () async {
      final harness = await _ControllerHarness.create();
      addTearDown(harness.dispose);
      final script = await harness.createDeployScript(exitCode: 0);
      harness.controller.playUploadChoice.value = PlayUploadChoice.upload;

      await harness.controller.runScript(script);

      expect(harness.apkExecutor.callCount, 1);
      expect(harness.telegramClient.uploads, isEmpty);
      expect(harness.controller.runner.workflowTotalSteps.value, 2);
      expect(harness.controller.runner.status.value, 'Completed');
      expect(
        harness.controller.runner.logLines,
        contains('Telegram auto send is disabled; APK was kept locally.'),
      );
    },
  );

  test('keeps the built APK when Telegram upload fails', () async {
    final harness = await _ControllerHarness.create();
    addTearDown(harness.dispose);
    final script = await harness.createDeployScript(exitCode: 0);
    harness.controller.playUploadChoice.value = PlayUploadChoice.upload;
    harness.telegramClient.responses.add(
      const TelegramHttpResponse(
        statusCode: 403,
        body: {'ok': false, 'description': 'Forbidden'},
      ),
    );
    await harness.enableTelegramAutoSend();

    await harness.controller.runScript(script);

    final output = Directory(
      p.join(harness.root.path, 'build', 'app', 'outputs', 'flutter-apk'),
    );
    expect(harness.apkExecutor.callCount, 1);
    expect(output.listSync().whereType<File>().single.existsSync(), isTrue);
    expect(harness.telegramClient.uploads, hasLength(1));
    expect(
      harness.controller.telegramReleaseStatus.value,
      contains('Telegram APK upload failed'),
    );
    expect(harness.controller.runner.status.value, 'Failed');
  });

  test('keeps the built APK when Drive fallback delivery fails', () async {
    final harness = await _ControllerHarness.create();
    addTearDown(harness.dispose);
    final script = await harness.createDeployScript(exitCode: 0);
    harness.apkExecutor.apkSizeBytes = 151 * 1024 * 1024;
    harness.googleDriveApiClient.error =
        const GoogleDriveReleaseUploadException('Drive quota exceeded.');
    harness.controller.playUploadChoice.value = PlayUploadChoice.upload;
    await harness.enableTelegramAutoSend();
    await harness.enableGoogleDriveFallback();

    await harness.controller.runScript(script);

    final output = Directory(
      p.join(harness.root.path, 'build', 'app', 'outputs', 'flutter-apk'),
    );
    expect(harness.apkExecutor.callCount, 1);
    expect(output.listSync().whereType<File>().single.existsSync(), isTrue);
    expect(harness.telegramClient.uploads, isEmpty);
    expect(harness.telegramClient.requests, isEmpty);
    expect(
      harness.controller.telegramReleaseStatus.value,
      contains('Google Drive APK delivery failed'),
    );
    expect(harness.controller.runner.status.value, 'Failed');
  });
}

class _ControllerHarness {
  const _ControllerHarness({
    required this.root,
    required this.controller,
    required this.telegramClient,
    required this.apkExecutor,
    required this.installerExecutor,
    required this.googleDriveCredentials,
    required this.googleDriveApiClient,
  });

  final Directory root;
  final HomeController controller;
  final _FakeTelegramHttpClient telegramClient;
  final _FakeReleaseApkBuildExecutor apkExecutor;
  final _FakeReleaseInstallerBuildExecutor installerExecutor;
  final GoogleDriveCredentialStoreService googleDriveCredentials;
  final _FakeGoogleDriveApiClient googleDriveApiClient;

  static Future<_ControllerHarness> create() async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp(
      'app_release_center_telegram_controller_',
    );
    await File(p.join(root.path, 'pubspec.yaml')).writeAsString(
      'name: app_release_center\n'
      'version: 2.0.1+45\n',
    );
    final installerScriptDirectory = await Directory(
      p.join(root.path, 'installer', 'windows'),
    ).create(recursive: true);
    await File(
      p.join(installerScriptDirectory.path, 'build_installer.ps1'),
    ).writeAsString('# test installer script\n');
    final store = await ProjectStoreService().init();
    final secureStore = _MemorySecureKeyValueStore();
    final telegramCredentials = TelegramCredentialStoreService(
      secureStore: secureStore,
    );
    final telegramClient = _FakeTelegramHttpClient();
    final apkExecutor = _FakeReleaseApkBuildExecutor();
    final installerExecutor = _FakeReleaseInstallerBuildExecutor();
    final googleDriveCredentials = GoogleDriveCredentialStoreService(
      secureStore: _MemorySecureKeyValueStore(),
    );
    final googleDriveApiClient = _FakeGoogleDriveApiClient();
    final googleDriveService = GoogleDriveReleaseUploadService(
      store: store,
      credentialStore: googleDriveCredentials,
      oauthFlow: _FakeGoogleDriveOAuthFlow(),
      apiClientFactory: _FakeGoogleDriveApiClientFactory(googleDriveApiClient),
    );
    final telegramService = TelegramReleaseNotificationService(
      store: store,
      credentialStore: telegramCredentials,
      httpClient: telegramClient,
    );
    final runner = ReleaseRunnerService();
    final chPlayInspector = ChPlayProjectInspectorService();
    final appStoreInspector = AppStoreProjectInspectorService();
    final notificationCredentials = NotificationCredentialStoreService(
      secureStore: _MemorySecureKeyValueStore(),
    );
    final controller = HomeController(
      store: store,
      catalog: ScriptCatalogService(),
      androidCicdCloner: AndroidCicdCloneService(),
      androidKeystores: AndroidKeystoreGenerationService(),
      runner: runner,
      connect: ReleaseCenterConnect(),
      notifications: CommandNotificationService(
        store: store,
        credentialStore: notificationCredentials,
        httpClient: _UnusedNotificationHttpClient(),
      ),
      geminiEnv: GeminiEnvService(rootDirectory: root),
      releaseNotesGenerator: _FakeReleaseNoteGenerationService(),
      releaseApkArtifacts: ReleaseApkArtifactService(
        buildExecutor: apkExecutor,
        now: () => DateTime(2026, 7, 21),
      ),
      releaseInstallerArtifacts: ReleaseInstallerArtifactService(
        buildExecutor: installerExecutor,
        now: () => DateTime(2026, 8, 3),
        isWindows: () => true,
      ),
      telegramReleaseNotifications: telegramService,
      googleDriveReleaseUploads: googleDriveService,
      chPlayInspector: chPlayInspector,
      chPlayCredentialStore: ChPlayCredentialStoreService(
        secureStore: _MemorySecureKeyValueStore(),
      ),
      chPlayVersionChecker: ChPlayVersionCheckService(
        inspector: chPlayInspector,
        runner: runner,
      ),
      appStoreInspector: appStoreInspector,
      appStoreCredentialStore: AppStoreCredentialStoreService(
        secureStore: _MemorySecureKeyValueStore(),
      ),
      appStoreVersionChecker: AppStoreVersionCheckService(
        inspector: appStoreInspector,
        runner: runner,
      ),
    );
    controller.project.value = ReleaseProject(
      path: root.path,
      scripts: const [],
      fastlaneLanes: const [],
      hasFirebaseDeployTools: false,
      hasPlayReleaseTools: true,
      pubspecVersion: '2.0.1+45',
    );
    controller.geminiApiKeyController.text = 'gemini-key';

    return _ControllerHarness(
      root: root,
      controller: controller,
      telegramClient: telegramClient,
      apkExecutor: apkExecutor,
      installerExecutor: installerExecutor,
      googleDriveCredentials: googleDriveCredentials,
      googleDriveApiClient: googleDriveApiClient,
    );
  }

  Future<ReleaseScript> createDeployScript({required int exitCode}) async {
    final auto = await Directory(p.join(root.path, 'auto')).create();
    final file = File(p.join(auto.path, 'deploy.dart'));
    await file.writeAsString(
      exitCode == 0
          ? 'void main(List<String> args) {}'
          : "import 'dart:io'; void main(List<String> args) { exit(1); }",
    );
    return ReleaseScript(path: file.path, kind: ReleaseScriptKind.deploy);
  }

  Future<void> enableTelegramAutoSend() async {
    controller.telegramBotTokenController.text = 'telegram-token';
    controller.telegramChatIdController.text = '-100123';
    await controller.setTelegramAutoSendEnabled(true);
  }

  Future<void> enableGoogleDriveFallback() async {
    controller.googleDriveOAuthClientIdController.text = 'drive-client-id';
    await googleDriveCredentials.saveCredentialsJson('drive-credentials-json');
    await controller.setGoogleDriveFallbackEnabled(true);
  }

  Future<void> enableGoogleDriveApkLinkToTelegram({
    bool includeReleaseNotes = false,
  }) async {
    controller.telegramBotTokenController.text = 'telegram-token';
    controller.telegramChatIdController.text = '-100123';
    controller.googleDriveOAuthClientIdController.text = 'drive-client-id';
    await googleDriveCredentials.saveCredentialsJson('drive-credentials-json');
    await controller.setGoogleDriveApkLinkTelegramEnabled(true);
    if (includeReleaseNotes) {
      await controller.setGoogleDriveLinkReleaseNotesIncluded(true);
    }
  }

  Future<void> connectGoogleDriveOnly() async {
    controller.googleDriveOAuthClientIdController.text = 'drive-client-id';
    await googleDriveCredentials.saveCredentialsJson('drive-credentials-json');
    await controller.saveGoogleDriveConfiguration();
  }

  Future<void> saveTelegramConfiguration() async {
    controller.telegramBotTokenController.text = 'telegram-token';
    controller.telegramChatIdController.text = '-100123';
    await controller.saveTelegramConfiguration();
  }

  Future<void> dispose() async {
    controller.onClose();
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  }
}

class _FakeReleaseNoteGenerationService extends ReleaseNoteGenerationService {
  @override
  Future<GeneratedReleaseNotes> generate({
    required ReleaseProject project,
    required String apiKey,
    required String customPrompt,
  }) async {
    return const GeneratedReleaseNotes(
      notes: 'Nội dung mới.',
      appDisplayName: 'Demo App',
      version: '2.3.4+56',
      gitRangeLabel: 'v2.3.3..HEAD',
      commitCount: 3,
      usedFallbackRange: false,
    );
  }
}

class _TelegramRequest {
  const _TelegramRequest(this.url, this.body);

  final Uri url;
  final Map<String, Object?> body;
}

class _TelegramUploadRequest {
  const _TelegramUploadRequest({
    required this.fileName,
    required this.contentType,
  });

  final String fileName;
  final String contentType;
}

class _FakeTelegramHttpClient implements TelegramHttpClient {
  final requests = <_TelegramRequest>[];
  final uploads = <_TelegramUploadRequest>[];
  final responses = <TelegramHttpResponse>[];

  @override
  Future<TelegramHttpResponse> postJson(
    Uri url,
    Map<String, Object?> body,
  ) async {
    requests.add(_TelegramRequest(url, body));
    return responses.removeAt(0);
  }

  @override
  Future<TelegramHttpResponse> postMultipartFile(
    Uri url, {
    required Map<String, String> fields,
    required String fileField,
    required File file,
    required String fileName,
    required String contentType,
  }) async {
    uploads.add(
      _TelegramUploadRequest(fileName: fileName, contentType: contentType),
    );
    return responses.removeAt(0);
  }
}

class _FakeReleaseApkBuildExecutor implements ReleaseApkBuildExecutor {
  int apkSizeBytes = 3;
  int callCount = 0;

  @override
  Future<int> buildReleaseApk(ReleaseProject project) async {
    callCount++;
    final output = await Directory(
      p.join(project.path, 'build', 'app', 'outputs', 'flutter-apk'),
    ).create(recursive: true);
    final apk = File(p.join(output.path, 'app-release.apk'));
    if (apkSizeBytes <= 3) {
      await apk.writeAsBytes(List<int>.filled(apkSizeBytes, 1));
    } else {
      final handle = await apk.open(mode: FileMode.write);
      await handle.truncate(apkSizeBytes);
      await handle.close();
    }
    return 0;
  }
}

class _FakeReleaseInstallerBuildExecutor
    implements ReleaseInstallerBuildExecutor {
  int installerSizeBytes = 3;
  int buildCallCount = 0;
  int packageCallCount = 0;

  @override
  Future<int> buildWindowsRelease(ReleaseProject project) async {
    buildCallCount++;
    return 0;
  }

  @override
  Future<int> packageWindowsInstaller({
    required ReleaseProject project,
    required String versionName,
  }) async {
    packageCallCount++;
    final output = await Directory(
      p.join(project.path, 'build', 'installer'),
    ).create(recursive: true);
    final installer = File(
      p.join(output.path, 'AppReleaseCenter_Setup_v$versionName.exe'),
    );
    if (installerSizeBytes <= 3) {
      await installer.writeAsBytes(List<int>.filled(installerSizeBytes, 1));
    } else {
      final handle = await installer.open(mode: FileMode.write);
      await handle.truncate(installerSizeBytes);
      await handle.close();
    }
    await _writeInstallerPayload(project);
    return 0;
  }

  Future<void> _writeInstallerPayload(ReleaseProject project) async {
    final buildRoot = Directory(p.join(project.path, 'build', 'installer'));
    final payloadRoot = Directory(p.join(buildRoot.path, 'payload'));
    final stageRoot = Directory(p.join(buildRoot.path, 'stage'));
    await payloadRoot.create(recursive: true);
    await stageRoot.create(recursive: true);

    final archive = Archive();
    for (final path in _requiredInstallerPayloadFiles) {
      final bytes = [1, 2, 3];
      final file = File(p.joinAll([payloadRoot.path, ...path.split('/')]));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      archive.add(ArchiveFile(path, bytes.length, bytes));
    }

    await File(
      p.join(stageRoot.path, 'payload.zip'),
    ).writeAsBytes(ZipEncoder().encode(archive));
  }
}

const _requiredInstallerPayloadFiles = [
  'app_release_center.exe',
  'flutter_windows.dll',
  'data/app.so',
  'data/icudtl.dat',
  'data/flutter_assets/AssetManifest.bin',
  'data/flutter_assets/FontManifest.json',
  'data/flutter_assets/NativeAssetsManifest.json',
];

class _FakeGoogleDriveOAuthFlow implements GoogleDriveOAuthFlow {
  @override
  Future<String> authorize({
    required String oauthClientId,
    String? oauthClientSecret,
  }) async {
    return 'drive-credentials-json';
  }
}

class _FakeGoogleDriveApiClientFactory implements GoogleDriveApiClientFactory {
  const _FakeGoogleDriveApiClientFactory(this.client);

  final _FakeGoogleDriveApiClient client;

  @override
  GoogleDriveApiClient create({
    required String oauthClientId,
    String? oauthClientSecret,
    required String credentialsJson,
  }) {
    return client;
  }
}

class _FakeGoogleDriveApiClient implements GoogleDriveApiClient {
  final uploads = <String>[];
  final uploadContentTypes = <String>[];
  final sharedFileIds = <String>[];
  int folderCreateCount = 0;
  Object? error;

  @override
  Future<GoogleDriveRemoteFile> createFolder({
    required String folderName,
  }) async {
    final currentError = error;
    if (currentError != null) throw currentError;
    folderCreateCount++;
    return const GoogleDriveRemoteFile(
      id: 'drive-folder-id',
      name: googleDriveReleaseFolderName,
    );
  }

  @override
  Future<GoogleDriveRemoteFile> uploadFile({
    required File file,
    required String fileName,
    required String folderId,
    required String contentType,
  }) async {
    final currentError = error;
    if (currentError != null) throw currentError;
    uploads.add(fileName);
    uploadContentTypes.add(contentType);
    return const GoogleDriveRemoteFile(
      id: 'drive-file-id',
      name: 'FizaHUB_v2.0.1_21_07_2026.apk',
      webViewLink: 'https://drive.google.com/file/d/drive-file-id/view',
    );
  }

  @override
  Future<void> makeAnyoneReadable(String fileId) async {
    final currentError = error;
    if (currentError != null) throw currentError;
    sharedFileIds.add(fileId);
  }

  @override
  String credentialsJson() => 'updated-drive-credentials-json';

  @override
  void close() {}
}

class _UnusedNotificationHttpClient implements NotificationHttpClient {
  @override
  Future<NotificationHttpResponse> deleteJson(
    String url, {
    Map<String, String> headers = const {},
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NotificationHttpResponse> getJson(
    String url, {
    Map<String, String> headers = const {},
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NotificationHttpResponse> postJson(
    String url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
  }) {
    throw UnimplementedError();
  }
}

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}
