import 'dart:io';

import 'package:app_release_center/app/controllers/home_controller.dart';
import 'package:app_release_center/app/data/release_center_connect.dart';
import 'package:app_release_center/app/models/api_tool.dart';
import 'package:app_release_center/app/models/app_store_project.dart';
import 'package:app_release_center/app/models/ch_play_project.dart';
import 'package:app_release_center/app/models/cicd_dependency.dart';
import 'package:app_release_center/app/models/release_project.dart';
import 'package:app_release_center/app/models/release_workflow.dart';
import 'package:app_release_center/app/models/resource_catalog.dart';
import 'package:app_release_center/app/models/resource_collection.dart';
import 'package:app_release_center/app/services/android_cicd_clone_service.dart';
import 'package:app_release_center/app/services/android_keystore_generation_service.dart';
import 'package:app_release_center/app/services/api_tool_service.dart';
import 'package:app_release_center/app/services/app_store_credential_store_service.dart';
import 'package:app_release_center/app/services/app_store_project_inspector_service.dart';
import 'package:app_release_center/app/services/app_store_version_check_service.dart';
import 'package:app_release_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_release_center/app/services/ch_play_project_inspector_service.dart';
import 'package:app_release_center/app/services/ch_play_version_check_service.dart';
import 'package:app_release_center/app/services/cicd_dependency_doctor_service.dart';
import 'package:app_release_center/app/services/cicd_dependency_installer_service.dart';
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
import 'package:app_release_center/app/services/resource_catalog_crypto_service.dart';
import 'package:app_release_center/app/services/resource_catalog_excel_service.dart';
import 'package:app_release_center/app/services/resource_catalog_password_store_service.dart';
import 'package:app_release_center/app/services/remote_control_service.dart';
import 'package:app_release_center/app/services/script_catalog_service.dart';
import 'package:app_release_center/app/services/telegram_credential_store_service.dart';
import 'package:app_release_center/app/services/telegram_release_notification_service.dart';
import 'package:app_release_center/app/services/theme_service.dart';
import 'package:app_release_center/app/views/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    expect(find.byKey(const Key('open-api-tool')), findsOneWidget);
    expect(find.text('Cyber'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);
    expect(find.text('Extend'), findsOneWidget);
  });

  testWidgets('opens project setup wizard from project summary', (
    tester,
  ) async {
    await _pumpHome(tester, harness);

    await tester.ensureVisible(find.byKey(const Key('project-setup-stores')));
    await tester.tap(find.byKey(const Key('project-setup-stores')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('project-setup-chplay')), findsOneWidget);
    expect(find.byKey(const Key('project-setup-appstore')), findsOneWidget);
    expect(
      find.byKey(const Key('project-setup-clone-android-cicd')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('project-setup-start')), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Skip'));
    await tester.pumpAndSettle();
  });

  testWidgets('Store Versions shows only stores for the selected project', (
    tester,
  ) async {
    await _pumpHome(tester, harness);
    final otherProjectPath =
        '${harness.projectDirectory.parent.path}${Platform.pathSeparator}'
        'other_release_app';

    harness.controller.chPlayProjects.assignAll([
      ChPlayProject(
        id: 'selected-play',
        path: harness.projectDirectory.path,
        displayName: 'Selected Play',
        applicationId: 'com.example.selected.play',
        track: 'production',
      ),
      ChPlayProject(
        id: 'other-play',
        path: otherProjectPath,
        displayName: 'Other Play',
        applicationId: 'com.example.other.play',
        track: 'internal',
      ),
    ]);
    harness.controller.appStoreProjects.assignAll([
      AppStoreProject(
        id: 'selected-ios',
        path: harness.projectDirectory.path,
        displayName: 'Selected iOS',
        bundleId: 'com.example.selected.ios',
      ),
      AppStoreProject(
        id: 'other-ios',
        path: otherProjectPath,
        displayName: 'Other iOS',
        bundleId: 'com.example.other.ios',
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Add CH Play'), findsNothing);
    expect(find.text('Add App Store'), findsNothing);
    expect(
      find.byKey(const Key('store-version-chplay-selected-play')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('store-version-appstore-selected-ios')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('store-version-chplay-other-play')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('store-version-appstore-other-ios')),
      findsNothing,
    );
    expect(find.text('com.example.selected.play'), findsOneWidget);
    expect(find.text('com.example.selected.ios'), findsOneWidget);
    expect(find.text('com.example.other.play'), findsNothing);
    expect(find.text('com.example.other.ios'), findsNothing);
  });

  testWidgets('Setup tab scans dependencies and previews install steps', (
    tester,
  ) async {
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('options-tab-setup')).hitTestable());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cicd-doctor-check')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cicd-doctor-check')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cicd-check-git')), findsOneWidget);
    expect(find.byKey(const Key('cicd-option-git')), findsOneWidget);
    expect(find.byKey(const Key('cicd-option-jdk')), findsOneWidget);
    expect(find.byKey(const Key('cicd-option-fastlane')), findsOneWidget);
    expect(find.byKey(const Key('cicd-step-install-git')), findsOneWidget);
    expect(find.textContaining('winget install --id Git.Git'), findsOneWidget);
    expect(
      find.byKey(const Key('cicd-step-install-firebase-cli')),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(const Key('cicd-option-firebase-cli')),
    );
    await tester.tap(find.byKey(const Key('cicd-option-firebase-cli')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('cicd-step-install-firebase-cli')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const Key('cicd-run-install-git')));
    await tester.tap(find.byKey(const Key('cicd-run-install-git')));
    await tester.pumpAndSettle();
    expect(find.text('Preview command'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Run'),
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.cicdInstaller.runStepIds, contains('install-git'));
    expect(harness.cicdDoctor.checkCalls, greaterThanOrEqualTo(2));
    expect(find.textContaining('fake install install-git'), findsWidgets);
  });

  testWidgets('opens API tool and sends a request', (tester) async {
    final apiTool = _FakeApiToolService();
    Get.put<ApiToolService>(apiTool);
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('api-tool-dialog')), findsOneWidget);
    expect(find.byKey(const Key('api-tool-url')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      'https://example.com/users',
    );

    await _openApiToolTab(tester, 'api-tool-settings-tab');
    expect(find.byKey(const Key('api-tool-timeout-seconds')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('api-tool-timeout-seconds')),
      '120',
    );

    await _openApiToolTab(tester, 'api-tool-headers-tab');
    expect(find.byKey(const Key('api-tool-header-name-0')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('api-tool-header-name-0')),
      'x-test',
    );
    await tester.enterText(
      find.byKey(const Key('api-tool-header-value-0')),
      'demo',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('api-tool-send')));
    await tester.pumpAndSettle();

    expect(apiTool.requests, hasLength(1));
    expect(apiTool.timeouts.single, const Duration(seconds: 120));
    expect(apiTool.requests.single.url, 'https://example.com/users');
    expect(apiTool.requests.single.enabledHeaders['x-test'], 'demo');
    expect(harness.controller.store.apiToolTimeoutSeconds, 120);
    expect(find.text('200'), findsOneWidget);
    expect(find.textContaining('"ok": true'), findsOneWidget);

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool saves authorization and headers per request', (
    tester,
  ) async {
    final apiTool = _FakeApiToolService();
    Get.put<ApiToolService>(apiTool);
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-tool-name')),
      'Authorized Demo',
    );
    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      'https://example.com/private',
    );
    await _openApiToolTab(tester, 'api-tool-headers-tab');
    await tester.enterText(
      find.byKey(const Key('api-tool-header-name-0')),
      'X-Request-ID',
    );
    await tester.enterText(
      find.byKey(const Key('api-tool-header-value-0')),
      'request-123',
    );

    await tester.tap(find.byKey(const Key('api-tool-authorization-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('api-tool-authorization-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bearer Token').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-tool-auth-token')),
      'demo-token',
    );

    await tester.tap(find.byKey(const Key('api-tool-save')));
    await tester.pump(const Duration(milliseconds: 300));

    final saved = harness.controller.store.apiToolRequests.single;
    expect(saved.enabledHeaders['X-Request-ID'], 'request-123');
    expect(saved.authorization.type, ApiToolAuthorizationType.bearer);
    expect(saved.authorization.token, 'demo-token');

    await tester.tap(find.byKey(const Key('api-tool-new')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Authorized Demo').first);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(const Key('api-tool-send')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(apiTool.requests, hasLength(1));
    expect(
      apiTool.requests.single.enabledHeaders['X-Request-ID'],
      'request-123',
    );
    expect(
      apiTool.requests.single.enabledHeaders['Authorization'],
      'Bearer demo-token',
    );

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool sends multipart text fields from body tab', (
    tester,
  ) async {
    final apiTool = _FakeApiToolService();
    Get.put<ApiToolService>(apiTool);
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      'https://example.com/upload',
    );

    await tester.tap(find.byKey(const Key('api-tool-body-tab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('api-tool-body-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('form-data').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-tool-multipart-name-0')),
      'name',
    );
    await tester.enterText(
      find.byKey(const Key('api-tool-multipart-value-0')),
      'Demo',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('api-tool-send')));
    await tester.pumpAndSettle();

    expect(apiTool.requests, hasLength(1));
    expect(apiTool.requests.single.bodyMode, ApiToolBodyMode.multipart);
    expect(apiTool.requests.single.multipartFields.single.name, 'name');
    expect(apiTool.requests.single.multipartFields.single.value, 'Demo');

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool sends x-www-form-urlencoded fields', (tester) async {
    final apiTool = _FakeApiToolService();
    Get.put<ApiToolService>(apiTool);
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      'https://example.com/token',
    );
    await tester.tap(find.byKey(const Key('api-tool-body-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('api-tool-body-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('x-www-form-urlencoded').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-tool-urlencoded-name-0')),
      'grant_type',
    );
    await tester.enterText(
      find.byKey(const Key('api-tool-urlencoded-value-0')),
      'client credentials',
    );

    await tester.tap(find.byKey(const Key('api-tool-send')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(apiTool.requests, hasLength(1));
    expect(apiTool.requests.single.bodyMode, ApiToolBodyMode.urlEncoded);
    expect(apiTool.requests.single.urlEncodedFields.single.name, 'grant_type');
    expect(
      apiTool.requests.single.urlEncodedFields.single.value,
      'client credentials',
    );

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'API tool runs a confirmed Quick Request with active environment',
    (tester) async {
      final apiTool = _FakeApiToolService();
      Get.put<ApiToolService>(apiTool);
      final now = DateTime(2026, 8, 17);
      await harness.controller.store.saveApiToolCollections([
        ApiToolCollectionRoot(
          id: 'collection-quick',
          name: 'Sandbox',
          activeEnvironmentId: 'environment-quick',
          environments: [
            ApiToolEnvironment(
              id: 'environment-quick',
              name: 'Local',
              variables: const [
                ApiToolEnvironmentVariable(
                  id: 'variable-url',
                  name: 'BASE_URL',
                  value: 'https://sandbox.example.com',
                ),
                ApiToolEnvironmentVariable(
                  id: 'variable-token',
                  name: 'TOKEN',
                  value: 'quick-secret',
                ),
              ],
              updatedAt: now,
            ),
          ],
          updatedAt: now,
        ),
      ]);
      await harness.controller.store.saveApiToolQuickRequests([
        ApiToolQuickRequest(
          id: 'quick-reset',
          name: 'Reset sandbox',
          collectionId: 'collection-quick',
          request: ApiToolRequest(
            id: 'quick-reset',
            name: 'Reset sandbox',
            method: ApiToolMethod.post,
            url: '{{BASE_URL}}/reset',
            collectionId: 'collection-quick',
            authorization: const ApiToolAuthorization(
              type: ApiToolAuthorizationType.bearer,
              token: '{{TOKEN}}',
            ),
            updatedAt: now,
          ),
          requiresConfirmation: true,
          updatedAt: now,
        ),
      ]);
      await _pumpHome(tester, harness);

      await tester.tap(find.byKey(const Key('open-api-tool')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('api-tool-quick-requests-tab')));
      await tester.pumpAndSettle();
      expect(find.text('Reset sandbox'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('api-tool-run-quick-request-quick-reset')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('api-tool-confirm-run-quick-request')),
        findsOneWidget,
      );
      expect(apiTool.requests, isEmpty);

      await tester.tap(
        find.byKey(const Key('api-tool-confirm-run-quick-request')),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(apiTool.requests, hasLength(1));
      expect(apiTool.requests.single.url, 'https://sandbox.example.com/reset');
      expect(
        apiTool.requests.single.enabledHeaders['Authorization'],
        'Bearer quick-secret',
      );
      expect(harness.controller.store.apiToolHistory, hasLength(1));

      await tester.tap(find.byKey(const Key('close-api-tool')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'API tool creates, edits, duplicates, and deletes Quick Requests',
    (tester) async {
      Get.put<ApiToolService>(_FakeApiToolService());
      await _pumpHome(tester, harness);

      await tester.tap(find.byKey(const Key('open-api-tool')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('api-tool-quick-requests-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('api-tool-new-quick-request')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('api-tool-quick-name')),
        'Health check',
      );
      await tester.enterText(
        find.byKey(const Key('api-tool-quick-url')),
        'https://example.com/health',
      );
      await tester.tap(find.byKey(const Key('api-tool-save-quick-request')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(harness.controller.store.apiToolQuickRequests, hasLength(1));
      final quickId = harness.controller.store.apiToolQuickRequests.single.id;

      await tester.tap(find.byKey(Key('api-tool-quick-request-menu-$quickId')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('api-tool-quick-name')),
        'Health check updated',
      );
      await tester.tap(find.byKey(const Key('api-tool-save-quick-request')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        harness.controller.store.apiToolQuickRequests.single.name,
        'Health check updated',
      );

      await tester.tap(find.byKey(Key('api-tool-quick-request-menu-$quickId')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('api-tool-save-quick-request')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(harness.controller.store.apiToolQuickRequests, hasLength(2));

      await tester.tap(find.byTooltip('Manage Quick Request').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('api-tool-confirm-delete-quick-request')),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(harness.controller.store.apiToolQuickRequests, hasLength(1));

      await tester.tap(find.byKey(const Key('close-api-tool')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('API tool copies the current draft into a Quick Request', (
    tester,
  ) async {
    Get.put<ApiToolService>(_FakeApiToolService());
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-tool-name')),
      'Current draft',
    );
    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      'https://example.com/call-now',
    );
    await _openApiToolTab(tester, 'api-tool-headers-tab');
    await tester.enterText(
      find.byKey(const Key('api-tool-header-name-0')),
      'X-Source',
    );
    await tester.enterText(
      find.byKey(const Key('api-tool-header-value-0')),
      'quick-copy',
    );
    await tester.tap(find.byKey(const Key('api-tool-quick-requests-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('api-tool-copy-to-quick-request')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('api-tool-quick-name')))
          .controller
          ?.text,
      'Current draft',
    );
    await tester.tap(find.byKey(const Key('api-tool-save-quick-request')));
    await tester.pump(const Duration(milliseconds: 400));

    final saved = harness.controller.store.apiToolQuickRequests.single;
    expect(saved.request.url, 'https://example.com/call-now');
    expect(saved.request.enabledHeaders['X-Source'], 'quick-copy');

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool blocks Quick Requests with missing variables', (
    tester,
  ) async {
    final apiTool = _FakeApiToolService();
    Get.put<ApiToolService>(apiTool);
    final now = DateTime(2026, 8, 17);
    await harness.controller.store.saveApiToolCollections([
      ApiToolCollectionRoot(
        id: 'collection-missing-variable',
        name: 'Missing variable',
        updatedAt: now,
      ),
    ]);
    await harness.controller.store.saveApiToolQuickRequests([
      ApiToolQuickRequest(
        id: 'quick-missing-variable',
        name: 'Broken quick call',
        collectionId: 'collection-missing-variable',
        request: ApiToolRequest(
          id: 'quick-missing-variable',
          name: 'Broken quick call',
          method: ApiToolMethod.post,
          url: 'https://example.com/reset',
          collectionId: 'collection-missing-variable',
          headers: const [
            ApiToolHeader(
              id: 'missing-header',
              name: 'X-Token',
              value: '{{MISSING_TOKEN}}',
            ),
          ],
          updatedAt: now,
        ),
        updatedAt: now,
      ),
    ]);
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('api-tool-quick-requests-tab')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('api-tool-run-quick-request-quick-missing-variable'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(apiTool.requests, isEmpty);
    expect(find.textContaining('MISSING_TOKEN'), findsOneWidget);

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool saves requests inside nested collection folders', (
    tester,
  ) async {
    Get.put<ApiToolService>(_FakeApiToolService());
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();

    await _openApiToolMenu(tester, 'api-tool-new-menu');
    await tester.tap(find.byKey(const Key('api-tool-add-collection')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Collection name'),
      'CRM',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump(const Duration(milliseconds: 300));

    await _openApiToolMenu(tester, 'api-tool-new-menu');
    await tester.tap(find.byKey(const Key('api-tool-add-folder')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Folder name'),
      'Auth',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump(const Duration(milliseconds: 300));

    await _openApiToolMenu(tester, 'api-tool-new-menu');
    await tester.tap(find.byKey(const Key('api-tool-add-subfolder')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Folder name'),
      'OAuth',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byKey(const Key('api-tool-name')),
      'Token Request',
    );
    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      'https://example.com/token',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('api-tool-save')));
    await tester.pump(const Duration(milliseconds: 300));

    final folders = harness.controller.store.apiToolFolders;
    final request = harness.controller.store.apiToolRequests.singleWhere(
      (entry) => entry.name == 'Token Request',
    );
    final oauthFolder = folders.singleWhere((entry) => entry.name == 'OAuth');
    expect(
      harness.controller.store.apiToolCollections.map((entry) => entry.name),
      contains('CRM'),
    );
    expect(folders, hasLength(2));
    expect(oauthFolder.parentFolderId, isNotEmpty);
    expect(request.folderId, oauthFolder.id);
    // 'Auth' is also the request workbench tab label, so scope to the tree.
    expect(
      find.descendant(
        of: find.byKey(const Key('api-tool-collection-list')),
        matching: find.text('Auth'),
      ),
      findsOneWidget,
    );
    expect(find.text('OAuth'), findsOneWidget);

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool groups collection actions behind New and overflow', (
    tester,
  ) async {
    Get.put<ApiToolService>(_FakeApiToolService());
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();

    final toolbar = find.byKey(const Key('api-tool-collection-toolbar'));
    final toolbarRect = tester.getRect(toolbar);
    for (final key in const ['api-tool-new-menu', 'api-tool-more-menu']) {
      final trigger = find.byKey(Key(key));
      expect(trigger, findsOneWidget);
      final triggerRect = tester.getRect(trigger);
      expect(triggerRect.left, greaterThanOrEqualTo(toolbarRect.left));
      expect(triggerRect.right, lessThanOrEqualTo(toolbarRect.right));
    }

    await _openApiToolMenu(tester, 'api-tool-new-menu');
    for (final key in const [
      'api-tool-new-request',
      'api-tool-add-folder',
      'api-tool-add-subfolder',
      'api-tool-add-collection',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await _openApiToolMenu(tester, 'api-tool-more-menu');
    for (final key in const [
      'api-tool-environments',
      'api-tool-import-postman',
      'api-tool-import-postman-environment',
      'api-tool-delete-collection',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool reveals requests only after expanding their branch', (
    tester,
  ) async {
    Get.put<ApiToolService>(_FakeApiToolService());
    final now = DateTime(2026, 8, 17);
    await harness.controller.store.saveApiToolCollections([
      ApiToolCollectionRoot(
        id: 'collection-tree',
        name: 'Tree API',
        updatedAt: now,
      ),
    ]);
    await harness.controller.store.saveApiToolFolders([
      ApiToolCollectionFolder(
        id: 'folder-users',
        collectionId: 'collection-tree',
        name: 'Users',
        updatedAt: now,
      ),
    ]);
    await harness.controller.store.saveApiToolRequests([
      ApiToolRequest(
        id: 'request-root',
        name: 'Health Check',
        method: ApiToolMethod.get,
        url: 'https://example.com/health',
        collectionId: 'collection-tree',
        updatedAt: now,
      ),
      ApiToolRequest(
        id: 'request-users',
        name: 'List Users',
        method: ApiToolMethod.get,
        url: 'https://example.com/users',
        collectionId: 'collection-tree',
        folderId: 'folder-users',
        updatedAt: now,
      ),
    ]);
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();

    final collection = find.byKey(
      const Key('api-tool-root-folder-collection-tree'),
    );
    const folderKey = Key('api-tool-folder-folder-users');
    const rootRequestKey = Key('api-tool-collection-request-root');
    const folderRequestKey = Key('api-tool-collection-request-users');
    expect(collection, findsOneWidget);
    expect(find.byKey(folderKey), findsNothing);
    expect(find.byKey(rootRequestKey), findsNothing);
    expect(find.byKey(folderRequestKey), findsNothing);

    await tester.tap(collection);
    await tester.pumpAndSettle();
    expect(find.byKey(folderKey), findsOneWidget);
    expect(find.byKey(rootRequestKey), findsOneWidget);
    expect(find.byKey(folderRequestKey), findsNothing);

    await tester.tap(find.byKey(folderKey));
    await tester.pumpAndSettle();
    expect(find.byKey(folderRequestKey), findsOneWidget);

    await tester.tap(find.byKey(folderKey));
    await tester.pumpAndSettle();
    expect(find.byKey(folderRequestKey), findsNothing);

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool deletes a collection and all linked data', (
    tester,
  ) async {
    Get.put<ApiToolService>(_FakeApiToolService());
    final now = DateTime(2026, 8, 17);
    await harness.controller.store.saveApiToolCollections([
      ApiToolCollectionRoot(
        id: 'collection-delete',
        name: 'Temporary API',
        updatedAt: now,
      ),
    ]);
    await harness.controller.store.saveApiToolFolders([
      ApiToolCollectionFolder(
        id: 'folder-delete',
        collectionId: 'collection-delete',
        name: 'Temporary Folder',
        updatedAt: now,
      ),
    ]);
    await harness.controller.store.saveApiToolRequests([
      ApiToolRequest(
        id: 'request-delete',
        name: 'Temporary Request',
        method: ApiToolMethod.get,
        url: 'https://example.com/temporary',
        collectionId: 'collection-delete',
        folderId: 'folder-delete',
        updatedAt: now,
      ),
    ]);
    await harness.controller.store.saveApiToolQuickRequests([
      ApiToolQuickRequest(
        id: 'quick-delete',
        name: 'Temporary Reset',
        collectionId: 'collection-delete',
        request: ApiToolRequest(
          id: 'quick-delete',
          name: 'Temporary Reset',
          method: ApiToolMethod.post,
          url: 'https://example.com/reset',
          collectionId: 'collection-delete',
          updatedAt: now,
        ),
        updatedAt: now,
      ),
    ]);
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();
    await _openApiToolMenu(tester, 'api-tool-more-menu');
    await tester.tap(find.byKey(const Key('api-tool-delete-collection')));
    await tester.pumpAndSettle();

    expect(find.text('Delete Collection?'), findsOneWidget);
    expect(
      find.textContaining(
        '1 folder(s), 1 saved request(s), and 1 Quick Request(s)',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('api-tool-confirm-delete-collection')),
    );
    await tester.pumpAndSettle();

    expect(
      harness.controller.store.apiToolCollections.single.displayName,
      'Default Collection',
    );
    expect(harness.controller.store.apiToolFolders, isEmpty);
    expect(harness.controller.store.apiToolRequests, isEmpty);
    expect(harness.controller.store.apiToolQuickRequests, isEmpty);
    expect(find.textContaining('Temporary API" was deleted'), findsOneWidget);

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool applies active collection environment variables', (
    tester,
  ) async {
    final apiTool = _FakeApiToolService();
    Get.put<ApiToolService>(apiTool);
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();

    await _openApiToolMenu(tester, 'api-tool-more-menu');
    await tester.tap(find.byKey(const Key('api-tool-environments')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('api-tool-add-environment')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('api-tool-environment-name')),
      'Local',
    );
    await tester.enterText(
      find.byKey(const Key('api-tool-env-var-name-0')),
      'BASE_URL',
    );
    await tester.enterText(
      find.byKey(const Key('api-tool-env-var-value-0')),
      'https://local.example.com',
    );
    await tester.tap(find.byKey(const Key('api-tool-save-environments')));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      '{{BASE_URL}}/users',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('api-tool-send')));
    await tester.pumpAndSettle();

    expect(apiTool.requests, hasLength(1));
    expect(apiTool.requests.single.url, 'https://local.example.com/users');
    expect(
      harness
          .controller
          .store
          .apiToolCollections
          .single
          .activeEnvironment
          ?.enabledVariables['BASE_URL'],
      'https://local.example.com',
    );

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool drags environment tokens into request fields', (
    tester,
  ) async {
    final apiTool = _FakeApiToolService();
    Get.put<ApiToolService>(apiTool);
    final now = DateTime.now();
    await harness.controller.store.saveApiToolCollections([
      ApiToolCollectionRoot(
        id: 'collection-1',
        name: 'CRM',
        activeEnvironmentId: 'env-1',
        environments: [
          ApiToolEnvironment(
            id: 'env-1',
            name: 'Local',
            updatedAt: now,
            variables: const [
              ApiToolEnvironmentVariable(
                id: 'var-base-url',
                name: 'Base Url',
                value: 'https://local.example.com',
              ),
              ApiToolEnvironmentVariable(
                id: 'var-token',
                name: 'TOKEN',
                value: 'Bearer demo-token',
              ),
              ApiToolEnvironmentVariable(
                id: 'var-user-id',
                name: 'USER_ID',
                value: '42',
              ),
            ],
          ),
        ],
        updatedAt: now,
      ),
    ]);
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();

    await _dragEnvToken(tester, 'Base Url', const Key('api-tool-url'));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('api-tool-url')))
          .controller
          ?.text,
      '{{Base Url}}',
    );
    final urlHighlight = _highlightSpanForText(
      tester,
      const Key('api-tool-url'),
      '{{Base Url}}',
    );
    expect(urlHighlight?.style?.backgroundColor, isNotNull);
    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      '{{Base Url}}/users',
    );
    await _openApiToolTab(tester, 'api-tool-headers-tab');
    await tester.enterText(
      find.byKey(const Key('api-tool-header-name-0')),
      'authorization',
    );
    await _dragEnvToken(tester, 'TOKEN', const Key('api-tool-header-value-0'));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('api-tool-header-value-0')))
          .controller
          ?.text,
      '{{TOKEN}}',
    );

    await tester.tap(find.byKey(const Key('api-tool-body-tab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('api-tool-body-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('form-data').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-tool-multipart-name-0')),
      'user_id',
    );
    await _dragEnvToken(
      tester,
      'USER_ID',
      const Key('api-tool-multipart-value-0'),
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('api-tool-multipart-value-0')),
          )
          .controller
          ?.text,
      '{{USER_ID}}',
    );

    await tester.tap(find.byKey(const Key('api-tool-send')));
    await tester.pumpAndSettle();

    expect(apiTool.requests, hasLength(1));
    expect(apiTool.requests.single.url, 'https://local.example.com/users');
    expect(
      apiTool.requests.single.enabledHeaders['authorization'],
      'Bearer demo-token',
    );
    expect(apiTool.requests.single.bodyMode, ApiToolBodyMode.multipart);
    expect(apiTool.requests.single.multipartFields.single.value, '42');

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool reports URL environment problems before sending', (
    tester,
  ) async {
    final apiTool = _FakeApiToolService();
    Get.put<ApiToolService>(apiTool);
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      '{{Base Url}}/users',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('api-tool-send')));
    await tester.pumpAndSettle();

    expect(apiTool.requests, isEmpty);
    expect(
      find.textContaining('Missing active environment variable(s): Base Url.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    await harness.controller.store.saveApiToolCollections([
      ApiToolCollectionRoot(
        id: 'collection-1',
        name: 'CRM',
        activeEnvironmentId: 'env-1',
        environments: [
          ApiToolEnvironment(
            id: 'env-1',
            name: 'Local',
            updatedAt: now,
            variables: const [
              ApiToolEnvironmentVariable(
                id: 'var-base-url',
                name: 'Base Url',
                value: 'local.example.com',
              ),
            ],
          ),
        ],
        updatedAt: now,
      ),
    ]);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      '{{Base Url}}/users',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('api-tool-send')));
    await tester.pumpAndSettle();

    expect(apiTool.requests, isEmpty);
    expect(
      find.textContaining('Resolved URL must be a valid http or https URL.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('saves, reloads, records history, and deletes API requests', (
    tester,
  ) async {
    Get.put<ApiToolService>(_FakeApiToolService());
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('api-tool-name')),
      'Saved Demo',
    );
    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      'https://example.com/saved',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('api-tool-save')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(harness.controller.store.apiToolRequests, hasLength(1));
    expect(find.text('Saved Demo'), findsWidgets);

    await tester.tap(find.byKey(const Key('api-tool-new')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('api-tool-url')))
          .controller
          ?.text,
      isEmpty,
    );

    await tester.tap(find.text('Saved Demo').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('api-tool-url')))
          .controller
          ?.text,
      'https://example.com/saved',
    );

    await tester.tap(find.byKey(const Key('api-tool-send')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(harness.controller.store.apiToolHistory, hasLength(1));

    await tester.tap(find.byKey(const Key('api-tool-history-tab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    final historyTile = find.descendant(
      of: find.byKey(const Key('api-tool-history-list')),
      matching: find.text('Saved Demo'),
    );
    expect(historyTile, findsOneWidget);
    await tester.tap(historyTile);
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('api-tool-url')))
          .controller
          ?.text,
      'https://example.com/saved',
    );

    await tester.tap(find.byKey(const Key('api-tool-delete')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(harness.controller.store.apiToolRequests, isEmpty);

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool filters saved requests from the sidebar search', (
    tester,
  ) async {
    Get.put<ApiToolService>(_FakeApiToolService());
    final now = DateTime(2026, 8, 10);
    await harness.controller.store.saveApiToolCollections([
      ApiToolCollectionRoot(
        id: 'collection-1',
        name: 'Default Collection',
        updatedAt: now,
      ),
    ]);
    await harness.controller.store.saveApiToolRequests([
      ApiToolRequest(
        id: 'request-alpha',
        name: 'Alpha Login',
        method: ApiToolMethod.post,
        url: 'https://example.com/auth/login',
        collectionId: 'collection-1',
        updatedAt: now,
      ),
      ApiToolRequest(
        id: 'request-billing',
        name: 'Billing Status',
        method: ApiToolMethod.get,
        url: 'https://example.com/billing/status',
        collectionId: 'collection-1',
        updatedAt: now.subtract(const Duration(minutes: 1)),
      ),
    ]);
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('api-tool-root-folder-collection-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('api-tool-request-search')), findsOneWidget);
    expect(find.text('Alpha Login'), findsOneWidget);
    expect(find.text('Billing Status'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('api-tool-request-search')),
      'billing',
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Billing Status'), findsOneWidget);
    expect(find.text('Alpha Login'), findsNothing);

    await tester.tap(find.byKey(const Key('api-tool-clear-request-search')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Alpha Login'), findsOneWidget);
    expect(find.text('Billing Status'), findsOneWidget);

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool keeps the Params tab in sync with the URL', (
    tester,
  ) async {
    final apiTool = _FakeApiToolService();
    Get.put<ApiToolService>(apiTool);
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();

    // URL -> rows.
    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      'https://example.com/users?page=2&role=admin',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('api-tool-param-name-0')))
          .controller
          ?.text,
      'page',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('api-tool-param-value-1')))
          .controller
          ?.text,
      'admin',
    );

    // Rows -> URL.
    await tester.enterText(
      find.byKey(const Key('api-tool-param-value-0')),
      '7',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('api-tool-url')))
          .controller
          ?.text,
      'https://example.com/users?page=7&role=admin',
    );

    await tester.tap(find.byKey(const Key('api-tool-send')));
    await tester.pumpAndSettle();
    expect(
      apiTool.requests.single.url,
      'https://example.com/users?page=7&role=admin',
    );

    // A separator typed into a value re-splits the query; must not throw even
    // though the focused row's controller gets rebuilt underneath.
    await tester.enterText(
      find.byKey(const Key('api-tool-param-value-1')),
      'admin&extra=1',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('api-tool-param-name-2')))
          .controller
          ?.text,
      'extra',
    );

    await tester.tap(find.byKey(const Key('api-tool-clear-params')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('api-tool-url')))
          .controller
          ?.text,
      'https://example.com/users',
    );

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool beautifies the raw body and copies it as cURL', (
    tester,
  ) async {
    Get.put<ApiToolService>(_FakeApiToolService());
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      'https://example.com/users',
    );
    await _openApiToolTab(tester, 'api-tool-headers-tab');
    await tester.enterText(
      find.byKey(const Key('api-tool-header-name-0')),
      'content-type',
    );
    await tester.enterText(
      find.byKey(const Key('api-tool-header-value-0')),
      'application/json',
    );
    await _openApiToolTab(tester, 'api-tool-body-tab');
    await tester.enterText(
      find.byKey(const Key('api-tool-body')),
      '{"name":"Demo","tags":[1,2]}',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('api-tool-beautify-json')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('api-tool-body')))
          .controller
          ?.text,
      '{\n  "name": "Demo",\n  "tags": [\n    1,\n    2\n  ]\n}',
    );

    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    debugPrint(
      'DBG view=${TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.physicalSize} '
      'dialog=${tester.getRect(find.byKey(const Key('api-tool-dialog')))} '
      'btn=${tester.getRect(find.byKey(const Key('api-tool-copy-curl')))}',
    );
    await tester.tap(find.byKey(const Key('api-tool-copy-curl')));
    await tester.pumpAndSettle();
    expect(copiedText, contains("curl -X GET 'https://example.com/users'"));
    expect(copiedText, contains("-H 'content-type: application/json'"));
    expect(copiedText, contains('--data-raw'));

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool sends with the keyboard shortcut', (tester) async {
    final apiTool = _FakeApiToolService();
    Get.put<ApiToolService>(apiTool);
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      'https://example.com/shortcut',
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(apiTool.requests, hasLength(1));
    expect(apiTool.requests.single.url, 'https://example.com/shortcut');

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool response inspector splits payload across tabs', (
    tester,
  ) async {
    Get.put<ApiToolService>(_FakeApiToolService());
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      'https://example.com/users',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('api-tool-send')));
    await tester.pumpAndSettle();

    // Hero keeps the status code and reason phrase as separate glances.
    expect(find.text('200'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.textContaining('B'), findsWidgets);
    expect(find.byKey(const Key('api-tool-response-body')), findsOneWidget);

    await tester.tap(find.byKey(const Key('api-tool-response-headers-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('api-tool-response-headers')), findsOneWidget);
    expect(find.text('content-type'), findsOneWidget);

    await tester.tap(find.byKey(const Key('api-tool-response-request-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('api-tool-sent-request-line')), findsOneWidget);
    expect(find.textContaining('GET https://example.com/users'), findsWidgets);

    await tester.tap(find.byKey(const Key('api-tool-expand-response')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('api-tool-response-focus')), findsOneWidget);
    await tester.tap(find.byKey(const Key('api-tool-close-response-focus')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool lays out without overflow across window sizes', (
    tester,
  ) async {
    Get.put<ApiToolService>(_FakeApiToolService());
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;

    for (final size in const [
      Size(1600, 900),
      Size(1280, 720),
      Size(1000, 700),
      Size(880, 640),
    ]) {
      view.physicalSize = size;
      await _pumpHome(tester, harness);
      await tester.ensureVisible(find.byKey(const Key('open-api-tool')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-api-tool')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('api-tool-dialog')),
        findsOneWidget,
        reason: 'dialog should render at $size',
      );

      for (final tab in const [
        'api-tool-params-tab',
        'api-tool-headers-tab',
        'api-tool-authorization-tab',
        'api-tool-body-tab',
        'api-tool-settings-tab',
      ]) {
        await _openApiToolTab(tester, tab);
      }

      await tester.tap(find.byKey(const Key('close-api-tool')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('API tool resizes its panels from the splitters', (tester) async {
    Get.put<ApiToolService>(_FakeApiToolService());
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();

    // Send once so the response panel has measurable content.
    await tester.enterText(
      find.byKey(const Key('api-tool-url')),
      'https://example.com/users',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('api-tool-send')));
    await tester.pumpAndSettle();

    double widthOf(Key key) => tester.getSize(find.byKey(key)).width;
    const sidebarKey = Key('api-tool-sidebar');
    const requestKey = Key('api-tool-name');
    const responseKey = Key('api-tool-response-body');

    // Two horizontal splitters: sidebar | workbench | response.
    final sidebarSplitter = find.byKey(const Key('api-tool-sidebar-splitter'));
    final workspaceSplitter = find.byKey(
      const Key('api-tool-workspace-splitter'),
    );
    expect(sidebarSplitter, findsOneWidget);
    expect(workspaceSplitter, findsOneWidget);

    final sidebarBefore = widthOf(sidebarKey);
    final requestBefore = widthOf(requestKey);
    final responseBefore = widthOf(responseKey);

    // Widen the sidebar; the workbench gives up the space.
    await tester.drag(sidebarSplitter, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(widthOf(sidebarKey), greaterThan(sidebarBefore + 60));
    expect(widthOf(requestKey), lessThan(requestBefore));

    // Drag it back and the sidebar returns to where it started.
    await tester.drag(sidebarSplitter, const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(widthOf(sidebarKey), closeTo(sidebarBefore, 1));

    // Give the response panel room at the request panel's expense.
    await tester.drag(workspaceSplitter, const Offset(-70, 0));
    await tester.pumpAndSettle();
    expect(widthOf(requestKey), lessThan(requestBefore - 50));
    expect(widthOf(responseKey), greaterThan(responseBefore + 50));

    // A drag far past the minimum stops at it rather than collapsing a panel.
    await tester.drag(workspaceSplitter, const Offset(-4000, 0));
    await tester.pumpAndSettle();
    expect(widthOf(requestKey), greaterThan(200));

    // Restore the shared layout so later tests start from the default split.
    await tester.drag(workspaceSplitter, const Offset(4000, 0));
    await tester.pumpAndSettle();
    await tester.drag(
      workspaceSplitter,
      Offset(requestBefore - widthOf(requestKey), 0),
    );
    await tester.pumpAndSettle();
    expect(widthOf(requestKey), closeTo(requestBefore, 1));

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('API tool stacks resizable panels on a narrow window', (
    tester,
  ) async {
    Get.put<ApiToolService>(_FakeApiToolService());
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(880, 1100);
    await _pumpHome(tester, harness);
    await tester.ensureVisible(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-api-tool')));
    await tester.pumpAndSettle();

    final sidebarSplitter = find.byKey(const Key('api-tool-sidebar-splitter'));
    expect(sidebarSplitter, findsOneWidget);
    expect(
      find.byKey(const Key('api-tool-workspace-splitter')),
      findsOneWidget,
    );

    double heightOf(Key key) => tester.getSize(find.byKey(key)).height;
    const sidebarKey = Key('api-tool-sidebar');
    final sidebarBefore = heightOf(sidebarKey);

    await tester.drag(sidebarSplitter, const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(heightOf(sidebarKey), greaterThan(sidebarBefore + 40));

    await tester.drag(sidebarSplitter, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(heightOf(sidebarKey), closeTo(sidebarBefore, 1));

    await tester.tap(find.byKey(const Key('close-api-tool')));
    await tester.pumpAndSettle();
  });

  testWidgets('opens the responsive release workflow preflight popup', (
    tester,
  ) async {
    await _pumpHome(tester, harness);

    expect(find.byKey(const Key('run-release-workflow')), findsOneWidget);
    await tester.tap(find.byKey(const Key('run-release-workflow')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('release-workflow-dialog')), findsOneWidget);
    expect(find.byKey(const Key('release-track-selector')), findsOneWidget);
    expect(find.text('Prepare release'), findsOneWidget);
    expect(find.text('CH Play track'), findsOneWidget);
    expect(find.byKey(const Key('review-release-workflow')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hide-release-workflow')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('release-workflow-dialog')), findsNothing);

    await tester.tap(find.byKey(const Key('run-release-workflow')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('release-workflow-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('hide-release-workflow')));
    await tester.pumpAndSettle();
  });

  testWidgets('requires explicit confirmation for production releases', (
    tester,
  ) async {
    await _pumpHome(tester, harness);
    await tester.tap(find.byKey(const Key('run-release-workflow')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('PRODUCTION'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('production-release-confirmation')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('review-release-workflow')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('production-release-confirmation')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('review-release-workflow')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('hide-release-workflow')));
    await tester.pumpAndSettle();
  });

  testWidgets('honors reduced motion while a release step is active', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 27, 10);
    harness.controller.releaseWorkflow.currentRun.value = ReleaseWorkflowRun(
      id: 'reduced-motion-release',
      projectPath: harness.projectDirectory.path,
      projectName: 'Demo App',
      track: 'internal',
      currentBranch: 'main',
      currentVersion: '1.0.0+1',
      proposedVersion: '1.0.1+2',
      changedFiles: const [],
      supportsSplitBuildDeploy: true,
      steps: [
        ReleaseWorkflowStepRun(
          kind: ReleaseWorkflowStepKind.build,
          label: 'Build AAB',
          status: ReleaseStepStatus.running,
          startedAt: now,
        ),
      ],
      createdAt: now,
      startedAt: now,
    );
    await _pumpHome(tester, harness, reduceMotion: true);

    await tester.tap(find.byKey(const Key('run-release-workflow')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('release-workflow-dialog')), findsOneWidget);
    expect(find.text('RUNNING'), findsWidgets);
    expect(
      MediaQuery.of(
        tester.element(find.text('RUNNING').first),
      ).disableAnimations,
      isTrue,
    );
    final motionFinder = find.byKey(
      const Key('release-workflow-step-motion-build'),
    );
    final before = tester
        .widget<Transform>(motionFinder)
        .transform
        .storage
        .toList();
    await tester.pump(const Duration(milliseconds: 500));
    final after = tester
        .widget<Transform>(motionFinder)
        .transform
        .storage
        .toList();
    expect(after, before);

    await tester.tap(find.byKey(const Key('hide-release-workflow')));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('renders desktop monitor with log tabs and hidden running run', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 27, 10);
    harness.controller.releaseWorkflow.currentRun.value = ReleaseWorkflowRun(
      id: 'desktop-monitor-release',
      projectPath: harness.projectDirectory.path,
      projectName: 'Demo App',
      track: 'beta',
      currentBranch: 'main',
      currentVersion: '1.0.0+1',
      proposedVersion: '1.0.1+2',
      changedFiles: const ['pubspec.yaml'],
      supportsSplitBuildDeploy: true,
      steps: [
        ReleaseWorkflowStepRun(
          kind: ReleaseWorkflowStepKind.preflight,
          label: 'Preflight',
          status: ReleaseStepStatus.succeeded,
          startedAt: now,
          finishedAt: now,
          logLines: const ['Preflight ok.'],
        ),
        ReleaseWorkflowStepRun(
          kind: ReleaseWorkflowStepKind.build,
          label: 'Build AAB',
          status: ReleaseStepStatus.running,
          startedAt: now,
        ),
        const ReleaseWorkflowStepRun(
          kind: ReleaseWorkflowStepKind.deploy,
          label: 'Deploy',
        ),
      ],
      createdAt: now,
      startedAt: now,
    );
    harness.controller.runner.logLines.assignAll(['Building release AAB...']);
    await _pumpHome(tester, harness, reduceMotion: true);

    await tester.tap(find.byKey(const Key('run-release-workflow')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const Key('release-workflow-timeline-horizontal')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('release-log-view-toggle')), findsOneWidget);
    expect(find.text('RUNNING'), findsWidgets);
    expect(find.byKey(const Key('stop-release-workflow')), findsOneWidget);
    expect(find.text('Building release AAB...'), findsWidgets);

    await tester.tap(find.text('All'));
    await tester.pump();
    expect(find.text('All logs'), findsOneWidget);
    expect(find.textContaining('Preflight ok.'), findsOneWidget);

    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.tap(find.byKey(const Key('copy-release-workflow-log')));
    await tester.pump();
    expect(copiedText, contains('Building release AAB...'));

    Navigator.of(
      tester.element(find.byKey(const Key('release-workflow-dialog'))),
      rootNavigator: true,
    ).pop();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('shows retry and artifact controls for failed releases', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 27, 10);
    harness.controller.releaseWorkflow.currentRun.value = ReleaseWorkflowRun(
      id: 'failed-release',
      projectPath: harness.projectDirectory.path,
      projectName: 'Demo App',
      track: 'internal',
      currentBranch: 'main',
      currentVersion: '1.0.0+1',
      proposedVersion: '1.0.1+2',
      changedFiles: const [],
      supportsSplitBuildDeploy: true,
      steps: [
        ReleaseWorkflowStepRun(
          kind: ReleaseWorkflowStepKind.build,
          label: 'Build AAB',
          status: ReleaseStepStatus.failed,
          startedAt: now,
          finishedAt: now.add(const Duration(seconds: 4)),
          logLines: const ['Build failed.'],
          error: 'Gradle exited 1',
          artifactPath: 'build/app/outputs/bundle/release/app-release.aab',
          retryable: true,
        ),
      ],
      createdAt: now,
      startedAt: now,
      finishedAt: now.add(const Duration(seconds: 4)),
      artifactPath: 'build/app/outputs/bundle/release/app-release.aab',
    );
    await _pumpHome(tester, harness);

    await tester.tap(find.byKey(const Key('run-release-workflow')));
    await tester.pumpAndSettle();

    expect(find.text('FAILED'), findsWidgets);
    expect(find.byKey(const Key('retry-release-workflow')), findsOneWidget);
    expect(find.byKey(const Key('open-release-artifact')), findsOneWidget);
    expect(find.byKey(const Key('stop-release-workflow')), findsNothing);

    await tester.tap(find.byKey(const Key('hide-release-workflow')));
    await tester.pumpAndSettle();
  });

  testWidgets('renders a completed release timeline on a narrow window', (
    tester,
  ) async {
    await _pumpHome(tester, harness);
    final now = DateTime(2026, 7, 27, 10);
    harness.controller.releaseWorkflow.currentRun.value = ReleaseWorkflowRun(
      id: 'widget-release',
      projectPath: harness.projectDirectory.path,
      projectName: 'Demo App',
      track: 'internal',
      currentBranch: 'main',
      currentVersion: '1.0.0+1',
      proposedVersion: '1.0.1+2',
      changedFiles: const ['pubspec.yaml'],
      supportsSplitBuildDeploy: true,
      steps: [
        ReleaseWorkflowStepRun(
          kind: ReleaseWorkflowStepKind.preflight,
          label: 'Preflight',
          status: ReleaseStepStatus.succeeded,
          startedAt: now,
          finishedAt: now,
        ),
        ReleaseWorkflowStepRun(
          kind: ReleaseWorkflowStepKind.release,
          label: 'Release',
          status: ReleaseStepStatus.succeeded,
          startedAt: now,
          finishedAt: now.add(const Duration(seconds: 5)),
          logLines: const ['CH Play release verified.'],
        ),
      ],
      createdAt: now,
      startedAt: now,
      finishedAt: now.add(const Duration(seconds: 5)),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('run-release-workflow')));
    await tester.pumpAndSettle();

    final view = tester.view;
    view.physicalSize = const Size(880, 900);
    view.devicePixelRatio = 1;
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('release-workflow-progress')), findsOneWidget);
    expect(
      find.byKey(const Key('release-workflow-timeline-vertical')),
      findsOneWidget,
    );
    expect(find.text('Preflight'), findsWidgets);
    expect(find.text('Release'), findsWidgets);
    expect(find.text('New Release'), findsOneWidget);
    await tester.tap(find.byKey(const Key('hide-release-workflow')));
    await tester.pumpAndSettle();
  });

  testWidgets('shows Android JKS generation in extended actions', (
    tester,
  ) async {
    await _pumpHome(tester, harness);

    await tester.tap(find.text('Extend'));
    await tester.pumpAndSettle();

    expect(find.text('Generate Android JKS'), findsOneWidget);

    await tester.tap(find.text('Generate Android JKS'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'JKS password'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'JKS password'),
      'manual-menu-pass',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Generate').last);
    await tester.pump();

    expect(harness.androidKeystores.calls, hasLength(1));
    expect(
      harness.androidKeystores.calls.single.storePassword,
      'manual-menu-pass',
    );
  });

  testWidgets('switches right panel feature tabs', (tester) async {
    await _pumpHome(tester, harness);

    expect(find.text('Release notes'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('options-tab-resources')));
    await tester.tap(
      find.byKey(const Key('options-tab-resources')).hitTestable(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('resource-options')), findsOneWidget);
    expect(find.byKey(const Key('resource-panel-mode')), findsOneWidget);
    expect(
      find.byKey(const Key('resource-catalog-add-resource')),
      findsOneWidget,
    );

    await tester.tap(find.text('Telegram'));
    await tester.pumpAndSettle();
    expect(find.text('Telegram bot token'), findsOneWidget);
    expect(find.text('Auto send release updates'), findsOneWidget);
    expect(find.byKey(const Key('installer-telegram-options')), findsOneWidget);
    final installerButton = find.byKey(const Key('build-send-installer'));
    expect(installerButton, findsOneWidget);
    expect(tester.widget<FilledButton>(installerButton).onPressed, isNull);

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

  testWidgets('shows resource catalog and masks passwords by default', (
    tester,
  ) async {
    await _pumpHome(tester, harness);

    await tester.ensureVisible(find.byKey(const Key('options-tab-resources')));
    await tester.tap(
      find.byKey(const Key('options-tab-resources')).hitTestable(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.runAsync(() async {
      await harness.controller.upsertResourceCatalogItem(
        ResourceCatalogItem(
          id: 'resource-1',
          kind: ResourceCatalogKind.googleSheet,
          title: 'Task tracker',
          url: 'https://docs.google.com/spreadsheets/d/demo',
          updatedAt: DateTime.utc(2026, 8, 3),
        ),
      );
      await harness.controller.upsertResourcePasswordEntry(
        ResourcePasswordEntry(
          id: 'password-1',
          secretKey: 'secret-key-1',
          site: 'Admin portal',
          loginUrl: 'https://admin.example.com',
          username: 'release@example.com',
          updatedAt: DateTime.utc(2026, 8, 3),
        ),
        password: 'top-secret-pass',
      );
    });
    await tester.pump();

    expect(find.text('Task tracker'), findsOneWidget);
    expect(find.text('Admin portal'), findsOneWidget);
    expect(find.text('release@example.com'), findsOneWidget);
    expect(find.textContaining('top-secret-pass'), findsNothing);
    expect(find.text('********'), findsWidgets);

    await tester.runAsync(
      () => harness.controller.revealResourcePassword(
        harness.controller.resourcePasswordEntries.single,
      ),
    );
    await tester.pump();
    expect(find.text('top-secret-pass'), findsOneWidget);
  });

  testWidgets('scans resources and enables plain zip export', (tester) async {
    File(
      '${harness.projectDirectory.path}${Platform.pathSeparator}.env',
    ).writeAsStringSync('API_KEY=secret-value\n');
    await _pumpHome(tester, harness);

    await tester.ensureVisible(find.byKey(const Key('options-tab-resources')));
    await tester.tap(
      find.byKey(const Key('options-tab-resources')).hitTestable(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    harness.controller.setResourcePanelMode(ResourcePanelMode.collector);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('resource-scan')), findsOneWidget);
    await tester.runAsync(harness.controller.scanResources);
    await tester.pump();

    expect(harness.controller.resourceFindings, hasLength(1));
    expect(
      harness.controller.resourceFindings.single.detectedKeyNames,
      contains('API_KEY'),
    );
    expect(
      harness.controller.resourceFindings.single.maskedPreview.join('\n'),
      isNot(contains('secret-value')),
    );
    expect(find.textContaining('secret-value'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('resource-export-bundle')))
          .onPressed,
      isNotNull,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('resource-select-all')),
        matching: find.text('All'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('resource-select-all')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('resource-clear-selection')))
          .onPressed,
      isNotNull,
    );
    expect(find.byKey(const Key('resource-passphrase')), findsNothing);
    expect(find.byKey(const Key('resource-environment')), findsNothing);

    harness.controller.setResourcePreset(ResourceCollectionPreset.custom);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('resource-kind-signingKey')), findsOneWidget);
  });

  testWidgets('shows signing credential status and manual resource fields', (
    tester,
  ) async {
    final keyDirectory = Directory(
      '${harness.projectDirectory.path}${Platform.pathSeparator}android'
      '${Platform.pathSeparator}fastlane${Platform.pathSeparator}keys',
    )..createSync(recursive: true);
    File(
      '${keyDirectory.path}${Platform.pathSeparator}release.jks',
    ).writeAsBytesSync([0, 1, 2]);
    File(
      '${harness.projectDirectory.path}${Platform.pathSeparator}android'
      '${Platform.pathSeparator}key.properties',
    ).writeAsStringSync(
      'keyAlias=release\n'
      'storeFile=../fastlane/keys/release.jks\n'
      'storePassword=store-secret\n'
      'keyPassword=key-secret\n',
    );

    await _pumpHome(tester, harness);
    await tester.ensureVisible(find.byKey(const Key('options-tab-resources')));
    await tester.tap(
      find.byKey(const Key('options-tab-resources')).hitTestable(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    harness.controller.setResourcePanelMode(ResourcePanelMode.collector);
    await tester.pump(const Duration(milliseconds: 300));
    harness.controller.setResourcePreset(ResourceCollectionPreset.custom);
    harness.controller.toggleResourceTargetKind(
      ResourceTargetKind.signingKey,
      true,
    );
    await tester.runAsync(harness.controller.scanResources);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final credential =
        harness.controller.resourceSigningCredentials.values.single;
    expect(credential.status, SigningCredentialStatus.resolved);
    expect(credential.source, SigningCredentialSource.projectFile);
    expect(
      find.byKey(const Key('resource-include-signing-credentials')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('resource-key-alias')), findsOneWidget);
    expect(find.textContaining('Resolved'), findsWidgets);
    expect(find.textContaining('store-secret'), findsNothing);
    expect(find.textContaining('key-secret'), findsNothing);

    final selectedBeforeTyping = harness.controller.selectedResourceFindingIds
        .toSet();
    final findingCountBeforeTyping = harness.controller.resourceFindings.length;
    final statusBeforeTyping = harness.controller.resourceStatus.value;
    await tester.enterText(
      find.byKey(const Key('resource-store-password')),
      'manual-store-secret',
    );
    await tester.pump();

    expect(
      harness.controller.resourceStorePasswordController.text,
      'manual-store-secret',
    );
    expect(
      harness.controller.resourceFindings,
      hasLength(findingCountBeforeTyping),
    );
    expect(
      harness.controller.selectedResourceFindingIds.toSet(),
      selectedBeforeTyping,
    );
    expect(harness.controller.resourceStatus.value, statusBeforeTyping);

    harness.controller.resourceKeyAliasController.text = 'manual-release';
    final exportTarget = Directory.systemTemp.createTempSync(
      'arc_resource_widget_export_',
    );
    addTearDown(() {
      if (exportTarget.existsSync()) {
        exportTarget.deleteSync(recursive: true);
      }
    });
    harness.controller.resourceTargetPathController.text = exportTarget.path;
    final result = await tester.runAsync(
      () => harness.controller.exportResources(),
    );
    await tester.pump();

    expect(result, isNotNull, reason: harness.controller.resourceStatus.value);
    expect(
      harness.controller.resourceStatus.value,
      isNot(contains('Select at least one resource file')),
    );
    final updated = harness.controller.resourceSigningCredentials.values.single;
    expect(updated.source, SigningCredentialSource.manual);
    expect(updated.keyAlias, 'manual-release');
    expect(updated.storePassword, 'manual-store-secret');
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
    await tester.enterText(
      find.widgetWithText(TextField, 'JKS password'),
      'manual-dialog-pass',
    );
    await tester.pump();
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
      harness.androidKeystores.calls.single.storePassword,
      'manual-dialog-pass',
    );
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
      'manual-dialog-pass',
    );

    await tester.tap(find.text('Key password matches store password'));
    await tester.pump();
    expect(
      _textFieldByLabel(tester, 'Key password').controller?.text,
      'manual-dialog-pass',
    );
  });
}

Future<void> _pumpHome(
  WidgetTester tester,
  _Harness harness, {
  bool reduceMotion = false,
}) async {
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
      builder: reduceMotion
          ? (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            )
          : null,
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

/// The request workbench opens on the Params tab; most assertions need a
/// different tab first.
Future<void> _openApiToolTab(WidgetTester tester, String tabKey) async {
  await tester.tap(find.byKey(Key(tabKey)));
  await tester.pumpAndSettle();
}

/// Sidebar create/overflow actions now live behind the `New` and `...` menus.
Future<void> _openApiToolMenu(WidgetTester tester, String menuKey) async {
  await tester.tap(find.byKey(Key(menuKey)));
  await tester.pumpAndSettle();
}

TextField _textFieldByLabel(WidgetTester tester, String label) {
  return tester
      .widgetList<TextField>(find.byType(TextField))
      .firstWhere((field) => field.decoration?.labelText == label);
}

TextSpan? _highlightSpanForText(
  WidgetTester tester,
  Key fieldKey,
  String text,
) {
  final finder = find.byKey(fieldKey);
  final field = tester.widget<TextField>(finder);
  final span = field.controller?.buildTextSpan(
    context: tester.element(finder),
    style: const TextStyle(),
    withComposing: false,
  );
  for (final child in span?.children ?? const <InlineSpan>[]) {
    if (child is TextSpan && child.text == text) {
      return child;
    }
  }
  return null;
}

Future<void> _dragEnvToken(
  WidgetTester tester,
  String name,
  Key targetKey,
) async {
  final source = find.byKey(Key('api-tool-env-token-$name'));
  final target = find.byKey(targetKey);
  if (source.evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('api-tool-env-vars-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(source, findsOneWidget);
  expect(target, findsOneWidget);

  await tester.drag(
    source,
    tester.getCenter(target) - tester.getCenter(source),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

class _Harness {
  _Harness({
    required this.controller,
    required this.projectDirectory,
    required this.androidKeystores,
    required this.cicdDoctor,
    required this.cicdInstaller,
  });

  final HomeController controller;
  final Directory projectDirectory;
  final _FakeAndroidKeystoreGenerationService androidKeystores;
  final _FakeCiCdDoctorService cicdDoctor;
  final _FakeCiCdInstallerService cicdInstaller;

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
    final cicdDoctor = _FakeCiCdDoctorService();
    final cicdInstaller = _FakeCiCdInstallerService();
    final connect = ReleaseCenterConnect();
    final geminiEnv = GeminiEnvService(rootDirectory: root);
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
    final releaseInstallerArtifacts = ReleaseInstallerArtifactService(
      buildExecutor: _NoopReleaseInstallerBuildExecutor(),
      isWindows: () => true,
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
    final resourceCatalogPasswords = ResourceCatalogPasswordStoreService(
      secureStore: secureStore,
    );
    final resourceCatalogCrypto = ResourceCatalogCryptoService(env: geminiEnv);
    final resourceCatalogExcel = ResourceCatalogExcelService(
      crypto: resourceCatalogCrypto,
      passwordStore: resourceCatalogPasswords,
    );

    Get.put<ProjectStoreService>(store);
    Get.put<ThemeService>(theme);
    Get.put<ScriptCatalogService>(catalog);
    Get.put<AndroidCicdCloneService>(androidCicdCloner);
    Get.put<AndroidKeystoreGenerationService>(androidKeystores);
    Get.put<CiCdDependencyDoctorService>(cicdDoctor);
    Get.put<CiCdDependencyInstallerService>(cicdInstaller);
    Get.put<ReleaseCenterConnect>(connect);
    Get.put<GeminiEnvService>(geminiEnv);
    Get.put<ReleaseNoteGenerationService>(ReleaseNoteGenerationService());
    Get.put<TelegramCredentialStoreService>(telegramCredentials);
    Get.put<TelegramReleaseNotificationService>(telegramNotifications);
    Get.put<GoogleDriveCredentialStoreService>(googleDriveCredentials);
    Get.put<GoogleDriveReleaseUploadService>(googleDriveUploads);
    Get.put<NotificationCredentialStoreService>(notificationCredentials);
    Get.put<CommandNotificationService>(notifications);
    Get.put<ReleaseRunnerService>(runner);
    Get.put<ReleaseApkArtifactService>(releaseApkArtifacts);
    Get.put<ReleaseInstallerArtifactService>(releaseInstallerArtifacts);
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
    Get.put<ResourceCatalogPasswordStoreService>(resourceCatalogPasswords);
    Get.put<ResourceCatalogCryptoService>(resourceCatalogCrypto);
    Get.put<ResourceCatalogExcelService>(resourceCatalogExcel);

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
        releaseInstallerArtifacts: releaseInstallerArtifacts,
        telegramReleaseNotifications: telegramNotifications,
        googleDriveReleaseUploads: googleDriveUploads,
        chPlayInspector: chPlayInspector,
        chPlayCredentialStore: chPlayCredentialStore,
        chPlayVersionChecker: Get.find<ChPlayVersionCheckService>(),
        appStoreInspector: appStoreInspector,
        appStoreCredentialStore: appStoreCredentialStore,
        appStoreVersionChecker: Get.find<AppStoreVersionCheckService>(),
        resourceCatalogPasswords: resourceCatalogPasswords,
        resourceCatalogExcel: resourceCatalogExcel,
        cicdDoctor: cicdDoctor,
        cicdInstaller: cicdInstaller,
      ),
    );

    return _Harness(
      controller: controller,
      projectDirectory: projectDirectory,
      androidKeystores: androidKeystores,
      cicdDoctor: cicdDoctor,
      cicdInstaller: cicdInstaller,
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

class _FakeCiCdDoctorService extends CiCdDependencyDoctorService {
  int checkCalls = 0;

  @override
  Future<CiCdDependencySnapshot> checkAll({String? projectPath}) async {
    checkCalls += 1;
    return CiCdDependencySnapshot(
      platform: CiCdSetupPlatform.windows,
      checkedAt: DateTime(2026, 8, 10, 9, 30),
      projectPath: projectPath ?? '',
      checks: const [
        CiCdDependencyCheck(
          id: 'winget',
          label: 'Windows Package Manager',
          group: CiCdSetupGroup.core,
          status: CiCdDependencyStatus.installed,
          version: '1.9.0',
        ),
        CiCdDependencyCheck(
          id: 'git',
          label: 'Git',
          group: CiCdSetupGroup.core,
          status: CiCdDependencyStatus.missing,
          detail: 'git was not found on PATH.',
        ),
        CiCdDependencyCheck(
          id: 'flutter',
          label: 'Flutter SDK',
          group: CiCdSetupGroup.core,
          status: CiCdDependencyStatus.installed,
          version: '3.35.1',
        ),
        CiCdDependencyCheck(
          id: 'jdk',
          label: 'JDK 17',
          group: CiCdSetupGroup.android,
          status: CiCdDependencyStatus.installed,
          version: '17.0.11',
        ),
        CiCdDependencyCheck(
          id: 'android-licenses',
          label: 'Android SDK licenses',
          group: CiCdSetupGroup.android,
          status: CiCdDependencyStatus.manual,
          detail: 'Run sdkmanager --licenses once after SDK setup.',
        ),
        CiCdDependencyCheck(
          id: 'fastlane',
          label: 'Fastlane',
          group: CiCdSetupGroup.rubyFastlane,
          status: CiCdDependencyStatus.missing,
          detail: 'fastlane was not found on PATH.',
        ),
        CiCdDependencyCheck(
          id: 'firebase-cli',
          label: 'Firebase CLI',
          group: CiCdSetupGroup.optionalTools,
          status: CiCdDependencyStatus.missing,
          detail: 'firebase was not found on PATH.',
        ),
      ],
    );
  }
}

class _FakeCiCdInstallerService extends CiCdDependencyInstallerService {
  final runStepIds = <String>[];

  @override
  Future<int> runInstallStep({
    required CiCdInstallStep step,
    required ReleaseRunnerService runner,
  }) async {
    runStepIds.add(step.id);
    runner.appendSystemLog('fake install ${step.id}');
    return 0;
  }
}

class _FakeAndroidKeystoreGenerationService
    extends AndroidKeystoreGenerationService {
  final calls = <_GenerateKeystoreCall>[];

  @override
  Future<AndroidKeystoreGenerationResult> generate({
    required String projectPath,
    String keyAlias = defaultAndroidKeyAlias,
    String? storePassword,
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
        storePassword: storePassword?.trim() ?? '',
        forceRecreate: forceRecreate,
      ),
    );

    final keystorePath =
        '$projectPath${Platform.pathSeparator}android'
        '${Platform.pathSeparator}fastlane${Platform.pathSeparator}keys'
        '${Platform.pathSeparator}$alias.jks';
    final password = (storePassword?.trim().isEmpty ?? true)
        ? 'dialog-secret'
        : storePassword!.trim();
    return AndroidKeystoreGenerationResult(
      keystorePath: keystorePath,
      envPropertiesPath:
          '$projectPath${Platform.pathSeparator}android'
          '${Platform.pathSeparator}env.properties',
      keyPropertiesPath:
          '$projectPath${Platform.pathSeparator}android'
          '${Platform.pathSeparator}key.properties',
      keyAlias: alias,
      storePassword: password,
      keyPassword: password,
      envKeystorePath: 'fastlane/keys/$alias.jks',
      keyPropertiesStoreFile: '../fastlane/keys/$alias.jks',
    );
  }
}

class _GenerateKeystoreCall {
  const _GenerateKeystoreCall({
    required this.projectPath,
    required this.keyAlias,
    required this.storePassword,
    required this.forceRecreate,
  });

  final String projectPath;
  final String keyAlias;
  final String storePassword;
  final bool forceRecreate;
}

class _NoopReleaseInstallerBuildExecutor
    implements ReleaseInstallerBuildExecutor {
  @override
  Future<int> buildWindowsRelease(ReleaseProject project) async => 0;

  @override
  Future<int> packageWindowsInstaller({
    required ReleaseProject project,
    required String versionName,
  }) async {
    return 0;
  }
}

class _FakeApiToolService extends ApiToolService {
  final requests = <ApiToolRequest>[];
  final timeouts = <Duration?>[];

  @override
  Future<ApiToolResponse> send(
    ApiToolRequest request, {
    Duration? timeout,
    ApiToolCancellationToken? cancelToken,
  }) async {
    requests.add(request);
    timeouts.add(timeout);
    return const ApiToolResponse(
      statusCode: 200,
      reasonPhrase: 'OK',
      headers: {
        'content-type': ['application/json'],
      },
      body: '{\n  "ok": true\n}',
      bodyTruncated: false,
      durationMs: 18,
    );
  }
}
