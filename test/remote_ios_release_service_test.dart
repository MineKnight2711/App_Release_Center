import 'dart:convert';

import 'package:app_management_center/app/data/release_center_connect.dart';
import 'package:app_management_center/app/models/app_store_credentials.dart';
import 'package:app_management_center/app/models/app_store_project.dart';
import 'package:app_management_center/app/models/ios_build_host.dart';
import 'package:app_management_center/app/models/ios_release.dart';
import 'package:app_management_center/app/models/release_workflow.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:app_management_center/app/services/remote_ios_release_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ios_build_host_fakes.dart';

void main() {
  test(
    'the controlling desktop leaves Xcode build and shows the Mac failure',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await ProjectStoreService().init();
      final key = await X25519().newKeyPair();
      await store.saveIosBuildHostLink(
        IosBuildHostLink(
          endpointBaseUrl: 'https://relay.test/api',
          desktopId: 'mac',
          publicKey: base64.encode((await key.extractPublicKey()).bytes),
        ),
      );
      final secrets = MemorySecureStore();
      await secrets.write(key: 'ios_build_host.control_token', value: 'token');
      const project = AppStoreProject(
        id: 'app',
        path: '/desktop/project',
        displayName: 'Demo',
        bundleId: 'com.example.demo',
      );
      final run = IosReleaseRun(
        id: 'release',
        project: project,
        settings: const IosReleaseSettings(),
        version: '1.2.3',
        buildNumber: 12,
        directory: '/mac/release',
        commit: 'abc123',
        dirty: false,
        createdAt: DateTime.now(),
        status: IosReleaseStatus.building,
      )..lastAction = 'build';
      final connect = _Relay(run);
      final desktop = RemoteIosReleaseService(
        store: store,
        connect: connect,
        secureStore: secrets,
        credentials: (_) async => const AppStoreCredentials(
          p8PrivateKey: 'TEST',
          keyId: 'KEY',
          issuerId: 'ISSUER',
        ),
        pollInterval: Duration.zero,
      );
      // Register the sender's project path before following the remote build.
      await desktop.load(project);
      await expectLater(
        desktop.build(run),
        throwsA(isA<RemoteIosReleaseException>()),
      );
      expect(connect.polls, 2);
      expect(desktop.busy.value, isFalse);
      expect(desktop.status.value, isEmpty);
      expect(desktop.current.value!.status, IosReleaseStatus.failed);
      expect(
        desktop.current.value!.message,
        contains('Source thay đổi trong lúc build'),
      );
      expect(
        desktop.current.value!.stageStatuses()[IosReleaseStage.build],
        ReleaseStepStatus.failed,
      );
      expect(store.iosBuildHostActiveStep, isNull);
      expect(desktop.liveLog.last, contains('Source thay đổi trong lúc build'));
    },
  );

  group('a step that will never report back', () {
    const project = AppStoreProject(
      id: 'app',
      path: '/desktop/project',
      displayName: 'Demo',
      bundleId: 'com.example.demo',
    );
    late ProjectStoreService store;
    late MemorySecureStore secrets;
    late IosReleaseRun run;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = await ProjectStoreService().init();
      final key = await X25519().newKeyPair();
      await store.saveIosBuildHostLink(
        IosBuildHostLink(
          endpointBaseUrl: 'https://relay.test/api',
          desktopId: 'mac',
          displayName: 'Mac mini',
          publicKey: base64.encode((await key.extractPublicKey()).bytes),
        ),
      );
      secrets = MemorySecureStore();
      await secrets.write(key: 'ios_build_host.control_token', value: 'token');
      run = IosReleaseRun(
        id: 'release',
        project: project,
        settings: const IosReleaseSettings(),
        version: '1.2.3',
        buildNumber: 12,
        directory: '/mac/release',
        commit: 'abc123',
        dirty: false,
        createdAt: DateTime.now(),
        status: IosReleaseStatus.building,
      )..lastAction = 'build';
    });

    RemoteIosReleaseService desktop(_StuckRelay relay) =>
        RemoteIosReleaseService(
          store: store,
          connect: relay,
          secureStore: secrets,
          credentials: (_) async => const AppStoreCredentials(
            p8PrivateKey: 'TEST',
            keyId: 'KEY',
            issuerId: 'ISSUER',
          ),
          pollInterval: const Duration(milliseconds: 5),
          stopGrace: const Duration(milliseconds: 80),
        );

    test('is let go once the Mac says it is not running it', () async {
      // The Mac restarted mid-build: the relay still says "running", last
      // touched long ago, and the Mac is idle.
      final relay = _StuckRelay(
        run,
        updatedAt: () => DateTime.now().subtract(const Duration(minutes: 10)),
        activeCommandId: '',
        hostBusy: false,
        macRunStatus: IosReleaseStatus.canceled,
      );
      final windows = desktop(relay);
      await windows.load(project);

      await expectLater(
        windows.build(run),
        throwsA(
          isA<RemoteIosReleaseException>().having(
            (error) => error.message,
            'message',
            contains('không còn chạy bước này'),
          ),
        ),
      );
      expect(windows.busy.value, isFalse);
      expect(store.iosBuildHostActiveStep, isNull);
      // What the Mac really has replaces the stale "building" snapshot.
      expect(windows.current.value!.status, IosReleaseStatus.canceled);
    });

    test('keeps following while the Mac is still on it', () async {
      final relay = _StuckRelay(
        run,
        updatedAt: () => DateTime.now().subtract(const Duration(minutes: 10)),
        activeCommandId: 'step',
        hostBusy: true,
        finishAfterPolls: 4,
      );
      final windows = desktop(relay);
      await windows.load(project);

      await windows.build(run);
      expect(relay.stepPolls, greaterThanOrEqualTo(4));
    });

    test('stop frees the dialog when the Mac never confirms', () async {
      final relay = _StuckRelay(
        run,
        updatedAt: DateTime.now,
        activeCommandId: 'step',
        hostBusy: true,
      );
      final windows = desktop(relay);
      await windows.load(project);

      final following = windows.build(run);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await windows.cancel();

      await expectLater(
        following,
        throwsA(
          isA<RemoteIosReleaseException>().having(
            (error) => error.message,
            'message',
            contains('chưa xác nhận lệnh dừng'),
          ),
        ),
      );
      expect(relay.stops, 1);
      expect(windows.busy.value, isFalse);
      expect(store.iosBuildHostActiveStep, isNull);
    });
  });
}

/// A relay holding one step that stays "running" until told otherwise, and a
/// Mac that answers history questions.
class _StuckRelay extends ReleaseCenterConnect {
  _StuckRelay(
    this.run, {
    required this.updatedAt,
    required this.activeCommandId,
    required this.hostBusy,
    this.macRunStatus = IosReleaseStatus.building,
    this.finishAfterPolls,
  });

  final IosReleaseRun run;
  final DateTime Function() updatedAt;
  final String activeCommandId;
  final bool hostBusy;
  final IosReleaseStatus macRunStatus;
  final int? finishAfterPolls;
  int stepPolls = 0;
  int stops = 0;

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
    if (url!.endsWith('/stop')) {
      stops++;
      return Response<T>(statusCode: 201, body: <String, Object?>{} as T);
    }
    final id = (body as Map)['type'] == 'iosQuery' ? 'query' : 'step';
    return Response<T>(
      statusCode: 201,
      body:
          {
                'command': {'commandId': id, 'status': 'queued'},
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
    if (url.endsWith('/mobile/desktops')) {
      return Response<T>(
        statusCode: 200,
        body:
            {
                  'desktops': [
                    {
                      'desktopId': 'mac',
                      'displayName': 'Mac mini',
                      'online': true,
                      'state': {
                        'isRunning': hostBusy,
                        'activeCommandId': activeCommandId,
                        'iosBuildHost': {'enabled': true},
                      },
                    },
                  ],
                }
                as T,
      );
    }
    if (url.endsWith('/mobile/commands/query')) {
      final onMac = iosRunFromWire(iosRunToWire(run))..status = macRunStatus;
      return Response<T>(
        statusCode: 200,
        body:
            {
                  'command': {
                    'commandId': 'query',
                    'status': 'completed',
                    'result': {
                      'runs': [iosRunToWire(onMac)],
                    },
                  },
                }
                as T,
      );
    }
    final finished =
        finishAfterPolls != null && ++stepPolls >= finishAfterPolls!;
    if (finishAfterPolls == null) stepPolls++;
    return Response<T>(
      statusCode: 200,
      body:
          {
                'command': {
                  'commandId': 'step',
                  'status': finished ? 'completed' : 'running',
                  'updatedAt': updatedAt().toUtc().toIso8601String(),
                  'result': {'run': iosRunToWire(run)},
                  'logLines': ['Running Xcode build...'],
                },
              }
              as T,
    );
  }
}

class _Relay extends ReleaseCenterConnect {
  _Relay(this.run);
  final IosReleaseRun run;
  int polls = 0;

  @override
  Future<Response<T>> post<T>(
    String? url,
    dynamic body, {
    String? contentType,
    Map<String, String>? headers,
    Map<String, dynamic>? query,
    Decoder<T>? decoder,
    Progress? uploadProgress,
  }) async => Response<T>(
    statusCode: 201,
    body:
        {
              'command': {'commandId': 'build', 'status': 'queued'},
            }
            as T,
  );

  @override
  Future<Response<T>> get<T>(
    String url, {
    Map<String, String>? headers,
    String? contentType,
    Map<String, dynamic>? query,
    Decoder<T>? decoder,
  }) async {
    if (url.endsWith('/mobile/desktops')) {
      return Response<T>(statusCode: 200, body: {'desktops': []} as T);
    }
    final failed = ++polls > 1;
    const error = 'Source thay đổi trong lúc build. Chuẩn bị lại release.';
    if (failed) {
      run.status = IosReleaseStatus.failed;
      run.message = error;
    }
    return Response<T>(
      statusCode: 200,
      body:
          {
                'command': {
                  'commandId': 'build',
                  'status': failed ? 'failed' : 'running',
                  'error': failed ? error : null,
                  'result': {'run': iosRunToWire(run)},
                  'logLines': [failed ? error : 'Running Xcode build...'],
                },
              }
              as T,
    );
  }
}
