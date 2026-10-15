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
