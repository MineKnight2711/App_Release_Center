@Tags(['e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/data/release_center_connect.dart';
import 'package:app_management_center/app/models/app_store_credentials.dart';
import 'package:app_management_center/app/models/app_store_project.dart';
import 'package:app_management_center/app/models/ios_release.dart';
import 'package:app_management_center/app/models/release_notification.dart';
import 'package:app_management_center/app/models/remote_control.dart';
import 'package:app_management_center/app/services/ios_build_host_service.dart';
import 'package:app_management_center/app/services/machine_power_service.dart';
import 'package:app_management_center/app/services/mobile_control_credential_store_service.dart';
import 'package:app_management_center/app/services/notification_credential_store_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:app_management_center/app/services/remote_control_service.dart';
import 'package:app_management_center/app/services/remote_ios_release_service.dart';
import 'package:app_management_center/app/services/script_catalog_service.dart';
import 'package:app_management_center/app/services/wake_diagnostics_service.dart';
import 'package:app_management_center/app/services/windows_auto_start_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'ios_build_host_fakes.dart';
import 'relay_process.dart';

/// A desktop drives an iOS release on a Mac build host through the real relay.
///
/// The Mac's git work is real and so is everything on the wire: pairing, the
/// scope and desktop binding, sealing, the release lane, progress reports and
/// the control-lane questions. Only Xcode, Flutter and Fastlane are stand-ins.
void main() {
  const desktopToken = 'e2e-ios-secret';
  RelayProcess? relay;
  final relayAvailable = RelayProcess.isAvailable();

  setUpAll(() async {
    if (!relayAvailable) return;
    relay = await RelayProcess.start(desktopToken: desktopToken);
  });

  tearDownAll(() async {
    await relay?.stop();
  });

  tearDown(Get.reset);

  final skipReason = relayAvailable
      ? null
      : 'Wrangler not installed: run npm install in serverless/notifications.';

  const credentials = AppStoreCredentials(
    p8PrivateKey: 'PRIVATE TEST FIXTURE',
    keyId: 'KEY',
    issuerId: 'ISSUER',
    teamId: 'TEAM',
  );
  const settings = IosReleaseSettings(teamId: 'TEAM', remoteFiles: ['.env']);

  test('a desktop runs an iOS release on its paired Mac', () async {
    final harness = await _Harness.create(relay!);
    final windows = harness.client(credentials);

    final link = await windows.linkHost(
      endpointBaseUrl: relay!.baseUrl,
      pairingCode: await harness.pairingCode(['ios']),
    );
    expect(link.desktopId, harness.macId);
    expect(
      link.fingerprint,
      await harness.host.fingerprint(),
      reason: 'the key pinned here must be the one the Mac shows',
    );

    await windows.load(harness.project);
    expect(windows.history, isEmpty);

    final prepared = await windows.prepare(
      project: harness.project,
      settings: settings,
    );
    expect(prepared.status, IosReleaseStatus.prepared);
    expect(prepared.commit, harness.repository.commit);
    expect(prepared.buildNumber, 11);
    expect(
      await File(p.join(prepared.project.path, '.env')).readAsString(),
      'API=production\n',
      reason: 'the gitignored file travels with the step',
    );

    await windows.continueToTestFlight(prepared);
    final ready = windows.current.value!;
    expect(ready.id, prepared.id);
    expect(ready.status, IosReleaseStatus.ready);
    expect(harness.runner.appleActions, containsAll(['query', 'upload']));

    // Everything the relay was handed: no key, no file contents in the clear.
    final sent = jsonEncode(harness.connect.sent);
    expect(sent, isNot(contains('PRIVATE TEST FIXTURE')));
    expect(sent, isNot(contains('API=production')));

    // A fresh session sees the Mac's history and its logs.
    final later = harness.client(credentials);
    await later.load(harness.project);
    expect(later.history.map((run) => run.id), [prepared.id]);
    expect(later.history.single.status, IosReleaseStatus.ready);
    final log = await later.savedLog(later.history.single);
    expect(log.join('\n'), contains('["flutter","build","ipa"'));
    expect(log.join('\n'), isNot(contains('PRIVATE TEST FIXTURE')));
  }, skip: skipReason);

  test('a failed step comes back with the Mac\'s reason', () async {
    final harness = await _Harness.create(relay!);
    final windows = harness.client(credentials);
    await windows.linkHost(
      endpointBaseUrl: relay!.baseUrl,
      pairingCode: await harness.pairingCode(['ios']),
    );

    // A commit only this desktop has.
    await File(
      p.join(harness.repository.clone, 'lib', 'main.dart'),
    ).writeAsString('void main() { print(2); }\n');
    await git(['commit', '-qam', 'not pushed'], harness.repository.clone);

    await expectLater(
      windows.prepare(project: harness.project, settings: settings),
      throwsA(
        isA<RemoteIosReleaseException>().having(
          (error) => error.message,
          'message',
          contains('chưa có trên origin'),
        ),
      ),
    );
    expect(windows.busy.value, isFalse);
  }, skip: skipReason);

  test('the ios scope reaches only the Mac that granted it', () async {
    final harness = await _Harness.create(relay!);
    final command = {
      'type': 'ios',
      'targetDesktopId': harness.macId,
      'payload': {
        'action': 'prepare',
        'projectId': 'app',
        'envelope': 'sealed',
      },
    };

    // A phone paired for release scripts.
    final phone = await harness.linkDevice(await harness.pairingCode(['run']));
    expect((await _post(relay!, 'mobile/commands', command, phone)).$1, 403);

    // A device another desktop granted ios to.
    final other = await harness.linkDevice(
      await harness.pairingCode(['ios'], desktopId: 'some-other-mac'),
    );
    final refused = await _post(relay!, 'mobile/commands', command, other);
    expect(refused.$1, 403);
    expect(refused.$2, contains('paired it'));
  }, skip: skipReason);
}

class _Harness {
  _Harness({
    required this.relay,
    required this.mac,
    required this.host,
    required this.runner,
    required this.store,
    required this.repository,
    required this.macId,
    required this.temp,
  });

  final RelayProcess relay;
  final RemoteControlService mac;
  final IosBuildHostService host;
  final FakeMacRunner runner;
  final ProjectStoreService store;
  final TestRepository repository;
  final String macId;
  final Directory temp;
  final connect = _RecordingConnect();

  static var _sequence = 0;

  AppStoreProject get project => AppStoreProject(
    id: 'app',
    path: repository.clone,
    displayName: 'Demo',
    bundleId: 'com.example.demo',
  );

  static Future<_Harness> create(RelayProcess relay) async {
    SharedPreferences.setMockInitialValues({});
    final store = await ProjectStoreService().init();
    final temp = await Directory.systemTemp.createTemp('remote_ios_e2e_');
    final repository = await TestRepository.create(temp);
    // One Mac id per test: agents from earlier tests may still be polling.
    final macId = 'e2e-mac-${++_sequence}';
    await store.saveRemoteControlSettings(
      RemoteControlSettings(desktopId: macId, allowIosBuild: true),
    );
    await store.saveNotificationSettings(
      const ReleaseNotificationSettings().copyWith(
        endpointBaseUrl: relay.baseUrl,
      ),
    );
    final desktopCredentials = NotificationCredentialStoreService(
      secureStore: MemorySecureStore(),
    );
    await desktopCredentials.saveApiToken(relay.desktopToken);

    final runner = FakeMacRunner();
    final host = IosBuildHostService(
      runner: runner,
      secureStore: MemorySecureStore(),
      root: Directory(p.join(temp.path, 'host')),
      workspaces: Directory(p.join(temp.path, 'workspaces')),
      isMacOS: () => true,
      allowLocalRemotes: true,
    );
    final mac = await RemoteControlService(
      store: store,
      catalog: ScriptCatalogService(),
      runner: runner,
      connect: ReleaseCenterConnect(),
      credentialStore: desktopCredentials,
      mobileCredentialStore: MobileControlCredentialStoreService(
        secureStore: MemorySecureStore(),
      ),
      power: MachinePowerService(processRunner: _quietProcesses),
      wakeDiagnostics: WakeDiagnosticsService(processRunner: _quietProcesses),
      autoStart: WindowsAutoStartService(
        startupDirectory: temp.path,
        executablePath: Platform.resolvedExecutable,
      ),
      iosBuildHost: host,
    ).init();
    await mac.setEnabled(true);

    final harness = _Harness(
      relay: relay,
      mac: mac,
      host: host,
      runner: runner,
      store: store,
      repository: repository,
      macId: macId,
      temp: temp,
    );
    addTearDown(harness.dispose);
    return harness;
  }

  RemoteIosReleaseService client(AppStoreCredentials credentials) =>
      RemoteIosReleaseService(
        store: store,
        connect: connect,
        credentials: (_) async => credentials,
        secureStore: _sharedClientSecrets,
        pollInterval: const Duration(milliseconds: 200),
      );

  /// One secure store for every client in a test, the way one machine has
  /// one keychain.
  final _sharedClientSecrets = MemorySecureStore();

  /// A code the way the Mac's Options screen makes one.
  Future<String> pairingCode(List<String> scopes, {String? desktopId}) async {
    final response = await http.post(
      Uri.parse('${relay.baseUrl}/pairings'),
      headers: relay.desktopHeaders,
      body: jsonEncode({
        'source': 'desktop',
        'scopes': scopes,
        'desktopId': desktopId ?? macId,
      }),
    );
    expect(response.statusCode, 201, reason: response.body);
    return (jsonDecode(response.body) as Map)['pairingCode'] as String;
  }

  Future<String> linkDevice(String code) async {
    final response = await http.post(
      Uri.parse('${relay.baseUrl}/control-devices'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'pairingCode': code}),
    );
    expect(response.statusCode, 201, reason: response.body);
    return (jsonDecode(response.body) as Map)['deviceControlToken'] as String;
  }

  Future<void> dispose() async {
    await mac.setEnabled(false);
    mac.onClose();
    try {
      await temp.delete(recursive: true);
    } catch (_) {
      // Windows can still hold a handle on a git object.
    }
  }
}

Future<(int, String)> _post(
  RelayProcess relay,
  String path,
  Map<String, Object?> body,
  String token,
) async {
  final response = await http.post(
    Uri.parse('${relay.baseUrl}/$path'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode(body),
  );
  return (response.statusCode, response.body);
}

/// Keeps what the desktop handed the relay, to check nothing went in clear.
class _RecordingConnect extends ReleaseCenterConnect {
  final sent = <Object?>[];

  @override
  Future<Response<T>> post<T>(
    String? url,
    dynamic body, {
    String? contentType,
    Map<String, String>? headers,
    Map<String, dynamic>? query,
    Decoder<T>? decoder,
    Progress? uploadProgress,
  }) {
    sent.add(body);
    return super.post<T>(
      url,
      body,
      contentType: contentType,
      headers: headers,
      query: query,
      decoder: decoder,
      uploadProgress: uploadProgress,
    );
  }
}

/// Answers the machine probes a heartbeat makes, so the agent stays quiet.
Future<ProcessResult> _quietProcesses(
  String executable,
  List<String> arguments,
) async {
  if (executable == 'powercfg.exe' && arguments.contains('/a')) {
    return ProcessResult(1, 0, 'Standby (S3)\n', '');
  }
  return ProcessResult(1, 0, '{}', '');
}
