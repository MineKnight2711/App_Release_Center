import 'dart:io';

import 'package:app_release_center/app/controllers/home_controller.dart';
import 'package:app_release_center/app/data/release_center_connect.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/models/release_project.dart';
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
import 'package:app_release_center/app/services/release_note_generation_service.dart';
import 'package:app_release_center/app/services/release_runner_service.dart';
import 'package:app_release_center/app/services/remote_control_service.dart';
import 'package:app_release_center/app/services/script_catalog_service.dart';
import 'package:app_release_center/app/services/telegram_credential_store_service.dart';
import 'package:app_release_center/app/services/telegram_release_notification_service.dart';
import 'package:app_release_center/app/services/theme_service.dart';
import 'package:app_release_center/app/views/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _Harness harness;

  setUp(() async {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1280, 720);
    view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    harness = await _Harness.create();
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    harness.dispose();
    Get.reset();
  });

  testWidgets('keeps command input dock visible on desktop', (tester) async {
    await _pumpHome(tester, harness);

    expect(find.text('Send to script'), findsOneWidget);
    expect(find.text('Clear log'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('keeps global command progress dock visible', (tester) async {
    await _pumpHome(tester, harness);

    expect(find.byKey(const Key('global-command-progress')), findsOneWidget);
    expect(
      find.byKey(const Key('global-command-battery-track')),
      findsOneWidget,
    );
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('READY  |  0%'), findsOneWidget);
  });

  testWidgets('updates charging progress during a workflow', (tester) async {
    await _pumpHome(tester, harness);

    harness.controller.runner.beginWorkflow(
      totalSteps: 3,
      label: 'Build and upload APK',
    );
    harness.controller.runner.beginWorkflowStep('Build release APK');
    await tester.pump();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('global-command-progress-label')))
          .data,
      contains('Build release APK'),
    );
    expect(find.text('STEP 1/3  |  0%'), findsOneWidget);

    harness.controller.runner.completeWorkflowStep(success: true);
    harness.controller.runner.beginWorkflowStep('Upload APK to Drive');
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester
          .widget<Text>(find.byKey(const Key('global-command-progress-label')))
          .data,
      contains('Upload APK to Drive'),
    );
    expect(find.text('STEP 2/3  |  33%'), findsOneWidget);

    harness.controller.runner.finishWorkflow(success: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('STEP 3/3  |  100%'), findsOneWidget);
  });

  testWidgets('moves app controls into automation header', (tester) async {
    await _pumpHome(tester, harness);

    expect(find.text('App Release Center'), findsNothing);
    expect(find.text('AUTOMATION'), findsOneWidget);
    expect(find.text('Cyber'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);
    expect(find.text('Extend'), findsOneWidget);
  });

  testWidgets('shows Android JKS generation in extended actions', (
    tester,
  ) async {
    await _pumpHome(tester, harness);

    await tester.tap(find.text('Extend'));
    await tester.pumpAndSettle();

    expect(find.text('Generate Android JKS'), findsOneWidget);
  });

  testWidgets('switches right panel feature tabs', (tester) async {
    await _pumpHome(tester, harness);

    expect(find.text('Release notes'), findsOneWidget);

    await tester.tap(find.text('Telegram'));
    await tester.pumpAndSettle();
    expect(find.text('Telegram bot token'), findsOneWidget);
    expect(find.text('Auto send release updates'), findsOneWidget);

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    expect(find.text('Command notifications'), findsOneWidget);
    expect(find.text('Serverless endpoint'), findsOneWidget);

    await tester.tap(find.text('Remote'));
    await tester.pumpAndSettle();
    expect(find.text('Phone command relay'), findsOneWidget);
    expect(find.text('Pair control app'), findsOneWidget);
    expect(find.text('Send to script'), findsOneWidget);
  });

  testWidgets('updates command dock running and prompt states', (tester) async {
    await _pumpHome(tester, harness);

    expect(_stdinField(tester, harness.controller).enabled, isFalse);

    harness.controller.runner.isRunning.value = true;
    await tester.pump();
    expect(_stdinField(tester, harness.controller).enabled, isTrue);

    harness.controller.runner.yesNoPrompt.value = 'Continue release?';
    await tester.pump();
    expect(find.text('Continue release?'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(_hasStdinField(tester, harness.controller), isFalse);
  });

  testWidgets('generates JKS from CH Play credentials dialog', (tester) async {
    await _pumpHome(tester, harness);
    harness.controller.chPlayProjects.assignAll([
      ChPlayProject(
        id: 'chp-1',
        path: harness.projectDirectory.path,
        displayName: 'Release App',
        applicationId: 'com.example.release',
      ),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Credentials'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Generate'));
    await tester.pump();
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      final jksPath = _textFieldByLabel(
        tester,
        'JKS keystore',
      ).controller?.text;
      if (jksPath != null && jksPath.isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.androidKeystores.calls, hasLength(1));
    expect(
      _textFieldByLabel(tester, 'JKS keystore').controller?.text,
      endsWith(
        'android${Platform.pathSeparator}fastlane'
        '${Platform.pathSeparator}keys${Platform.pathSeparator}release.jks',
      ),
    );
    expect(_textFieldByLabel(tester, 'Key alias').controller?.text, 'release');
    expect(
      _textFieldByLabel(tester, 'Store password').controller?.text,
      'dialog-secret',
    );

    await tester.tap(find.text('Key password matches store password'));
    await tester.pump();
    expect(
      _textFieldByLabel(tester, 'Key password').controller?.text,
      'dialog-secret',
    );
  });
}

Future<void> _pumpHome(WidgetTester tester, _Harness harness) async {
  harness.controller.project.value = ReleaseProject(
    path: harness.projectDirectory.path,
    scripts: const [],
    fastlaneLanes: const [],
    hasFirebaseDeployTools: true,
    hasPlayReleaseTools: true,
    pubspecVersion: '1.0.0+1',
  );

  await tester.pumpWidget(
    GetMaterialApp(
      theme: Get.find<ThemeService>().themeData,
      home: const HomeView(),
    ),
  );
  await tester.pumpAndSettle();
}

TextField _stdinField(WidgetTester tester, HomeController controller) {
  return tester
      .widgetList<TextField>(find.byType(TextField))
      .firstWhere((field) => field.controller == controller.stdinController);
}

bool _hasStdinField(WidgetTester tester, HomeController controller) {
  return tester
      .widgetList<TextField>(find.byType(TextField))
      .any((field) => field.controller == controller.stdinController);
}

TextField _textFieldByLabel(WidgetTester tester, String label) {
  return tester
      .widgetList<TextField>(find.byType(TextField))
      .firstWhere((field) => field.decoration?.labelText == label);
}

class _Harness {
  _Harness({
    required this.controller,
    required this.projectDirectory,
    required this.androidKeystores,
  });

  final HomeController controller;
  final Directory projectDirectory;
  final _FakeAndroidKeystoreGenerationService androidKeystores;

  static Future<_Harness> create() async {
    final root = await Directory.systemTemp.createTemp('arc_options_panel_');
    final projectDirectory = await Directory(
      '${root.path}${Platform.pathSeparator}release_app',
    ).create();
    await Directory(
      '${projectDirectory.path}${Platform.pathSeparator}android',
    ).create();
    final secureStore = _MemorySecureKeyValueStore();
    final store = await ProjectStoreService().init();
    final theme = await ThemeService().init();
    final catalog = ScriptCatalogService();
    final androidCicdCloner = AndroidCicdCloneService();
    final androidKeystores = _FakeAndroidKeystoreGenerationService();
    final connect = ReleaseCenterConnect();
    final notificationCredentials = NotificationCredentialStoreService(
      secureStore: secureStore,
    );
    final notifications = CommandNotificationService(
      store: store,
      credentialStore: notificationCredentials,
      httpClient: _NoopNotificationHttpClient(),
    );
    final runner = ReleaseRunnerService(notificationService: notifications);
    final telegramCredentials = TelegramCredentialStoreService(
      secureStore: secureStore,
    );
    final telegramNotifications = TelegramReleaseNotificationService(
      store: store,
      credentialStore: telegramCredentials,
      httpClient: _NoopTelegramHttpClient(),
    );
    final googleDriveCredentials = GoogleDriveCredentialStoreService(
      secureStore: secureStore,
    );
    final googleDriveUploads = GoogleDriveReleaseUploadService(
      store: store,
      credentialStore: googleDriveCredentials,
    );
    final releaseApkArtifacts = ReleaseApkArtifactService(
      buildExecutor: RunnerReleaseApkBuildExecutor(runner),
    );
    final remote = RemoteControlService(
      store: store,
      catalog: catalog,
      runner: runner,
      connect: connect,
      credentialStore: notificationCredentials,
    );
    final chPlayInspector = ChPlayProjectInspectorService();
    final chPlayCredentialStore = ChPlayCredentialStoreService(
      secureStore: secureStore,
    );
    final appStoreInspector = AppStoreProjectInspectorService();
    final appStoreCredentialStore = AppStoreCredentialStoreService(
      secureStore: secureStore,
    );

    Get.put<ProjectStoreService>(store);
    Get.put<ThemeService>(theme);
    Get.put<ScriptCatalogService>(catalog);
    Get.put<AndroidCicdCloneService>(androidCicdCloner);
    Get.put<AndroidKeystoreGenerationService>(androidKeystores);
    Get.put<ReleaseCenterConnect>(connect);
    Get.put<GeminiEnvService>(GeminiEnvService(rootDirectory: root));
    Get.put<ReleaseNoteGenerationService>(ReleaseNoteGenerationService());
    Get.put<TelegramCredentialStoreService>(telegramCredentials);
    Get.put<TelegramReleaseNotificationService>(telegramNotifications);
    Get.put<GoogleDriveCredentialStoreService>(googleDriveCredentials);
    Get.put<GoogleDriveReleaseUploadService>(googleDriveUploads);
    Get.put<NotificationCredentialStoreService>(notificationCredentials);
    Get.put<CommandNotificationService>(notifications);
    Get.put<ReleaseRunnerService>(runner);
    Get.put<ReleaseApkArtifactService>(releaseApkArtifacts);
    Get.put<RemoteControlService>(remote);
    Get.put<ChPlayProjectInspectorService>(chPlayInspector);
    Get.put<ChPlayCredentialStoreService>(chPlayCredentialStore);
    Get.put<ChPlayVersionCheckService>(
      ChPlayVersionCheckService(inspector: chPlayInspector, runner: runner),
    );
    Get.put<AppStoreProjectInspectorService>(appStoreInspector);
    Get.put<AppStoreCredentialStoreService>(appStoreCredentialStore);
    Get.put<AppStoreVersionCheckService>(
      AppStoreVersionCheckService(inspector: appStoreInspector, runner: runner),
    );

    final controller = Get.put<HomeController>(
      HomeController(
        store: store,
        catalog: catalog,
        androidCicdCloner: androidCicdCloner,
        androidKeystores: androidKeystores,
        runner: runner,
        connect: connect,
        notifications: notifications,
        geminiEnv: Get.find<GeminiEnvService>(),
        releaseNotesGenerator: Get.find<ReleaseNoteGenerationService>(),
        releaseApkArtifacts: releaseApkArtifacts,
        telegramReleaseNotifications: telegramNotifications,
        googleDriveReleaseUploads: googleDriveUploads,
        chPlayInspector: chPlayInspector,
        chPlayCredentialStore: chPlayCredentialStore,
        chPlayVersionChecker: Get.find<ChPlayVersionCheckService>(),
        appStoreInspector: appStoreInspector,
        appStoreCredentialStore: appStoreCredentialStore,
        appStoreVersionChecker: Get.find<AppStoreVersionCheckService>(),
      ),
    );

    return _Harness(
      controller: controller,
      projectDirectory: projectDirectory,
      androidKeystores: androidKeystores,
    );
  }

  void dispose() {
    final root = projectDirectory.parent;
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
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

class _NoopNotificationHttpClient implements NotificationHttpClient {
  @override
  Future<NotificationHttpResponse> deleteJson(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    return const NotificationHttpResponse(statusCode: 200, body: {});
  }

  @override
  Future<NotificationHttpResponse> getJson(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    return const NotificationHttpResponse(
      statusCode: 200,
      body: {'devices': []},
    );
  }

  @override
  Future<NotificationHttpResponse> postJson(
    String url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
  }) async {
    return const NotificationHttpResponse(statusCode: 200, body: {});
  }
}

class _NoopTelegramHttpClient implements TelegramHttpClient {
  @override
  Future<TelegramHttpResponse> postJson(
    Uri url,
    Map<String, Object?> body,
  ) async {
    return const TelegramHttpResponse(statusCode: 200, body: {'ok': true});
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
    return const TelegramHttpResponse(statusCode: 200, body: {'ok': true});
  }
}

class _FakeAndroidKeystoreGenerationService
    extends AndroidKeystoreGenerationService {
  final calls = <_GenerateKeystoreCall>[];

  @override
  Future<AndroidKeystoreGenerationResult> generate({
    required String projectPath,
    String keyAlias = defaultAndroidKeyAlias,
    bool forceRecreate = false,
    String? distinguishedName,
  }) async {
    final alias = keyAlias.trim().isEmpty
        ? defaultAndroidKeyAlias
        : keyAlias.trim();
    calls.add(
      _GenerateKeystoreCall(
        projectPath: projectPath,
        keyAlias: alias,
        forceRecreate: forceRecreate,
      ),
    );

    final keystorePath =
        '$projectPath${Platform.pathSeparator}android'
        '${Platform.pathSeparator}fastlane${Platform.pathSeparator}keys'
        '${Platform.pathSeparator}$alias.jks';
    return AndroidKeystoreGenerationResult(
      keystorePath: keystorePath,
      envPropertiesPath:
          '$projectPath${Platform.pathSeparator}android'
          '${Platform.pathSeparator}env.properties',
      keyPropertiesPath:
          '$projectPath${Platform.pathSeparator}android'
          '${Platform.pathSeparator}key.properties',
      keyAlias: alias,
      storePassword: 'dialog-secret',
      keyPassword: 'dialog-secret',
      envKeystorePath: 'fastlane/keys/$alias.jks',
      keyPropertiesStoreFile: '../fastlane/keys/$alias.jks',
    );
  }
}

class _GenerateKeystoreCall {
  const _GenerateKeystoreCall({
    required this.projectPath,
    required this.keyAlias,
    required this.forceRecreate,
  });

  final String projectPath;
  final String keyAlias;
  final bool forceRecreate;
}
