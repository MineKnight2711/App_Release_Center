import 'package:app_management_center/app/data/release_center_connect.dart';
import 'package:app_management_center/app/models/app_store_project.dart';
import 'package:app_management_center/app/models/ios_release.dart';
import 'package:app_management_center/app/models/remote_control.dart';
import 'package:app_management_center/app/services/mobile_control_credential_store_service.dart';
import 'package:app_management_center/app/services/notification_credential_store_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:app_management_center/app/services/remote_control_service.dart';
import 'package:app_management_center/app/services/script_catalog_service.dart';
import 'package:app_management_center/app/views/mobile_release_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ios_build_host_fakes.dart';

Future<RemoteControlService> _phone(
  WidgetTester tester,
  ReleaseCenterConnect relay,
) async {
  late RemoteControlService remote;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    final store = await ProjectStoreService().init();
    await store.saveMobileControlSettings(
      const MobileControlSettings(endpointBaseUrl: 'https://relay.test/api'),
    );
    final tokens = MobileControlCredentialStoreService(
      secureStore: MemorySecureStore(),
    );
    await tokens.saveControlToken('phone-token');
    remote = await RemoteControlService(
      store: store,
      catalog: ScriptCatalogService(),
      runner: ReleaseRunnerService(),
      connect: relay,
      credentialStore: NotificationCredentialStoreService(
        secureStore: MemorySecureStore(),
      ),
      mobileCredentialStore: tokens,
    ).init();
  });
  return remote;
}

void main() {
  tearDown(Get.reset);

  testWidgets('a phone reviews and starts a CH Play release', (tester) async {
    final relay = _Relay();
    final remote = await _phone(tester, relay);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MobileReleaseTab(remote: remote)),
      ),
    );
    await _settle(tester);

    expect(find.text('Demo · CH Play'), findsOneWidget);
    expect(find.text('Xem lại release'), findsOneWidget);
    // The project's own track is preselected, production needs a tick.
    final review = find.byKey(const Key('mobile-release-android-prepare'));
    expect(tester.widget<FilledButton>(review).onPressed, isNull);
    await tester.tap(find.text('internal'));
    await tester.pump();

    await tester.tap(review);
    await _settle(tester);

    expect(relay.sent.last, {
      'platform': 'android',
      'action': 'prepare',
      'projectPath': 'C:/Work/demo',
      'track': 'internal',
    });
    expect(
      find.text('1.0.0+1 → 1.0.1+2 · internal · nhánh main'),
      findsOneWidget,
    );
    expect(find.text('Build AAB'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mobile-release-android-start')));
    await _settle(tester);
    expect(relay.sent.last, {
      'platform': 'android',
      'action': 'start',
      'confirmProduction': false,
    });

    // Dispose so the tab's timers stop.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a phone prepares an App Store release and sends it on', (
    tester,
  ) async {
    final relay = _IosRelay();
    final remote = await _phone(tester, relay);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MobileReleaseTab(remote: remote)),
      ),
    );
    await _settle(tester);

    expect(find.text('Demo iOS · App Store'), findsOneWidget);
    expect(find.textContaining('build trên Mac mini'), findsOneWidget);
    expect(find.widgetWithText(TextField, '2.1.13'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mobile-release-ios-prepare')));
    await _settle(tester);
    expect(relay.sent.last, {
      'platform': 'ios',
      'action': 'prepare',
      'projectId': 'ios',
      'version': '2.1.13',
      'notes': 'Sửa lỗi đăng nhập',
    });

    expect(find.text('2.1.13+32 · Đã xem lại'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mobile-release-ios-testflight')));
    await _settle(tester);
    expect(relay.sent.last, {
      'platform': 'ios',
      'action': 'continue',
      'projectId': 'ios',
      'runId': '7',
    });

    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
}

/// The relay and the desktop behind it, answering the way a desktop with one
/// CH Play project would.
class _Relay extends ReleaseCenterConnect {
  final sent = <Map<String, Object?>>[];
  var _started = false;

  Map<String, Object?> get _run => {
    'id': 'r1',
    'projectPath': 'C:/Work/demo',
    'projectName': 'Demo',
    'track': 'internal',
    'currentBranch': 'main',
    'currentVersion': '1.0.0+1',
    'proposedVersion': '1.0.1+2',
    'steps': [
      {
        'kind': 'build',
        'label': 'Build AAB',
        'status': _started ? 'succeeded' : 'pending',
      },
    ],
    'createdAt': '2026-10-15T08:00:00Z',
    if (_started) 'startedAt': '2026-10-15T08:01:00Z',
  };

  @override
  Future<Response<T>> post<T>(
    String? url,
    dynamic body, {
    String? contentType,
    Map<String, String>? headers,
    Map<String, dynamic>? query,
    Decoder<T>? decoder,
    Progress? uploadProgress,
  }) async {
    final command = Map<String, Object?>.from(body as Map);
    final payload = Map<String, Object?>.from(command['payload']! as Map);
    final isStep = command['type'] == 'release';
    if (isStep) {
      sent.add(payload);
      if (payload['action'] == 'start') _started = true;
    }
    return Response<T>(
      statusCode: 201,
      body:
          {
                'command': {
                  'commandId': isStep ? 'step' : 'control',
                  'status': 'queued',
                  'payload': payload,
                },
              }
              as T,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String url, {
    Map<String, String>? headers,
    String? contentType,
    Map<String, dynamic>? query,
    Decoder<T>? decoder,
  }) async {
    if (url.endsWith('/mobile/desktop-state')) {
      return Response<T>(
        statusCode: 200,
        body:
            {
                  'desktop': {
                    'desktopId': 'pc',
                    'online': true,
                    'state': <String, Object?>{},
                  },
                }
                as T,
      );
    }
    final step = url.endsWith('/step');
    return Response<T>(
      statusCode: 200,
      body:
          {
                'command': {
                  'commandId': step ? 'step' : 'control',
                  'status': 'completed',
                  'result': step
                      ? {'androidRun': _run}
                      : {
                          'android': [
                            {
                              'path': 'C:/Work/demo',
                              'name': 'Demo',
                              'applicationId': 'com.example.demo',
                              'track': 'production',
                            },
                          ],
                          'ios': const [],
                          'androidRun': sent.isEmpty ? null : _run,
                          'androidBusy': false,
                        },
                },
              }
              as T,
    );
  }
}

/// A desktop whose iOS releases build on a Mac mini.
class _IosRelay extends ReleaseCenterConnect {
  final sent = <Map<String, Object?>>[];
  IosReleaseRun? _run;

  Map<String, dynamic>? get _wire => _run == null ? null : iosRunToWire(_run!);

  @override
  Future<Response<T>> post<T>(
    String? url,
    dynamic body, {
    String? contentType,
    Map<String, String>? headers,
    Map<String, dynamic>? query,
    Decoder<T>? decoder,
    Progress? uploadProgress,
  }) async {
    final command = Map<String, Object?>.from(body as Map);
    final payload = Map<String, Object?>.from(command['payload']! as Map);
    final isStep = command['type'] == 'release';
    if (isStep) {
      sent.add(payload);
      _run = IosReleaseRun(
        id: '7',
        project: const AppStoreProject(
          id: 'ios',
          path: '/mac/ios',
          displayName: 'Demo iOS',
          bundleId: 'com.example.ios',
        ),
        settings: const IosReleaseSettings(notes: 'Sửa lỗi đăng nhập'),
        version: '2.1.13',
        buildNumber: 32,
        directory: '/mac/runs/7',
        commit: 'abc',
        dirty: false,
        createdAt: DateTime(2026, 10, 15),
        status: payload['action'] == 'prepare'
            ? IosReleaseStatus.prepared
            : IosReleaseStatus.processing,
      );
    }
    return Response<T>(
      statusCode: 201,
      body:
          {
                'command': {
                  'commandId': isStep ? 'step' : 'control-${payload['action']}',
                  'status': 'queued',
                  'payload': payload,
                },
              }
              as T,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String url, {
    Map<String, String>? headers,
    String? contentType,
    Map<String, dynamic>? query,
    Decoder<T>? decoder,
  }) async {
    if (url.endsWith('/mobile/desktop-state')) {
      return Response<T>(
        statusCode: 200,
        body:
            {
                  'desktop': {'desktopId': 'pc', 'online': true, 'state': {}},
                }
                as T,
      );
    }
    final Map<String, Object?> result;
    if (url.endsWith('/step')) {
      result = {'iosRun': _wire};
    } else if (url.endsWith('/control-project')) {
      result = {
        'projectId': 'ios',
        'version': '2.1.13',
        'notes': 'Sửa lỗi đăng nhập',
        'host': 'Mac mini',
        'busy': false,
        'runs': [?_wire],
      };
    } else {
      result = {
        'android': const [],
        'ios': [
          {
            'id': 'ios',
            'path': 'C:/Work/ios',
            'name': 'Demo iOS',
            'bundleId': 'com.example.ios',
          },
        ],
        'iosHost': 'Mac mini',
        'iosBusy': false,
      };
    }
    return Response<T>(
      statusCode: 200,
      body:
          {
                'command': {
                  'commandId': 'x',
                  'status': 'completed',
                  'result': result,
                },
              }
              as T,
    );
  }
}
