@Tags(['e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/data/release_center_connect.dart';
import 'package:app_management_center/app/models/release_notification.dart';
import 'package:app_management_center/app/models/remote_control.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:app_management_center/app/services/machine_power_service.dart';
import 'package:app_management_center/app/services/mobile_control_credential_store_service.dart';
import 'package:app_management_center/app/services/notification_credential_store_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:app_management_center/app/services/release_runner_service.dart';
import 'package:app_management_center/app/services/remote_control_service.dart';
import 'package:app_management_center/app/services/script_catalog_service.dart';
import 'package:app_management_center/app/services/wake_diagnostics_service.dart';
import 'package:app_management_center/app/services/windows_auto_start_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the desktop agent and the phone against a real relay process.
///
/// Every other test in this repo stubs one side of the wire. This one runs the
/// actual Node relay, so a mismatch between what the phone sends and what the
/// relay accepts — a missing scope, a renamed field, a command landing in the
/// wrong lane — fails here and nowhere else.
void main() {
  const desktopToken = 'e2e-secret';
  _Relay? relay;

  // The relay is a separate Node project with its own dependencies. Where it
  // is not installed these tests have nothing to talk to, and skipping is
  // better than a red suite that says nothing about this code.
  final relayAvailable = _Relay.isAvailable();

  setUpAll(() async {
    if (!relayAvailable) return;
    relay = await _Relay.start(desktopToken: desktopToken);
  });

  tearDownAll(() async {
    await relay?.stop();
  });

  tearDown(Get.reset);

  final skipReason = relayAvailable
      ? null
      : 'Wrangler not installed: run npm install in serverless/notifications.';

  test('a phone shuts down a desktop end to end', () async {
    final harness = await _Harness.create(relay!, scopes: ['run', 'power']);

    await harness.desktop.setAllowPowerControl(true);
    await harness.desktop.setEnabled(true);
    await harness.waitForDesktopOnline();

    // The phone only ever sees the desktop through the relay.
    await harness.phone.refreshMobileDesktopState();
    final state = harness.phone.desktopState.value;
    expect(state, isNotNull);
    expect(state!.online, isTrue);
    expect(
      state.powerControlEnabled,
      isTrue,
      reason: 'the desktop should advertise that it accepts power commands',
    );

    final queued = await harness.phone.enqueuePowerCommand(
      desktopId: state.desktopId,
      action: MachinePowerAction.shutdown,
      delaySeconds: 30,
    );
    expect(queued.status, 'queued');

    final finished = await harness.waitForCommand(
      queued.commandId,
      'completed',
    );
    expect(finished['exitCode'], 0);

    expect(harness.processes.calls, hasLength(1));
    expect(harness.processes.calls.single.executable, 'shutdown.exe');
    expect(harness.processes.calls.single.arguments, ['/s', '/t', '30']);
    expect(harness.desktop.pendingPowerCommand.value, isNotNull);
  }, skip: skipReason);

  test('a power command runs while a release holds the runner', () async {
    final harness = await _Harness.create(relay!, scopes: ['run', 'power']);

    await harness.desktop.setAllowPowerControl(true);
    await harness.desktop.setEnabled(true);
    await harness.waitForDesktopOnline();

    // This is the case the release lane deliberately refuses to serve.
    harness.runner.isRunning.value = true;
    addTearDown(() => harness.runner.isRunning.value = false);

    await harness.phone.refreshMobileDesktopState();
    final queued = await harness.phone.enqueuePowerCommand(
      desktopId: harness.phone.desktopState.value!.desktopId,
      action: MachinePowerAction.lock,
    );

    await harness.waitForCommand(queued.commandId, 'completed');

    expect(harness.processes.calls.single.executable, 'rundll32.exe');
    expect(harness.processes.calls.single.arguments, [
      'user32.dll,LockWorkStation',
    ]);
  }, skip: skipReason);

  test('a shutdown during a release is refused, not obeyed', () async {
    final harness = await _Harness.create(relay!, scopes: ['run', 'power']);

    await harness.desktop.setAllowPowerControl(true);
    await harness.desktop.setEnabled(true);
    await harness.waitForDesktopOnline();

    harness.runner.isRunning.value = true;
    harness.runner.status.value = 'Đang build Demo';
    addTearDown(() => harness.runner.isRunning.value = false);

    await harness.phone.refreshMobileDesktopState();
    final queued = await harness.phone.enqueuePowerCommand(
      desktopId: harness.phone.desktopState.value!.desktopId,
      action: MachinePowerAction.shutdown,
    );

    final finished = await harness.waitForCommand(queued.commandId, 'failed');

    expect('${finished['error']}', contains('Đang chạy'));
    expect(
      harness.processes.calls,
      isEmpty,
      reason: 'nothing should have been run',
    );
  }, skip: skipReason);

  test(
    'the desktop refuses power commands while the gate is closed',
    () async {
      final harness = await _Harness.create(relay!, scopes: ['run', 'power']);

      // Note the gate is left off here; the relay still lets it through because
      // the device has the scope, and the desktop is the second line of defence.
      await harness.desktop.setEnabled(true);
      await harness.waitForDesktopOnline();

      await harness.phone.refreshMobileDesktopState();
      expect(harness.phone.desktopState.value!.powerControlEnabled, isFalse);

      final queued = await harness.phone.enqueuePowerCommand(
        desktopId: harness.phone.desktopState.value!.desktopId,
        action: MachinePowerAction.lock,
      );

      final finished = await harness.waitForCommand(queued.commandId, 'failed');

      expect('${finished['error']}', contains('chưa bật quyền'));
      expect(harness.processes.calls, isEmpty);
    },
    skip: skipReason,
  );

  test('a phone without the power scope is stopped at the relay', () async {
    final harness = await _Harness.create(relay!, scopes: ['run']);

    await expectLater(
      harness.phone.enqueuePowerCommand(
        desktopId: 'default',
        action: MachinePowerAction.lock,
      ),
      throwsA(
        isA<RemoteControlException>().having(
          (error) => error.message,
          'message',
          contains('not allowed'),
        ),
      ),
    );
  }, skip: skipReason);

  test('the heartbeat carries wake diagnostics to the phone', () async {
    final harness = await _Harness.create(relay!, scopes: ['run', 'power']);

    await harness.desktop.setEnabled(true);
    await harness.waitForDesktopOnline();
    await harness.phone.refreshMobileDesktopState();

    final wake = harness.phone.desktopState.value!.wake;
    expect(wake.macAddress, '84:9E:56:EA:B7:F1');
    expect(wake.broadcastAddress, '192.168.1.255');
    expect(wake.wirelessAdapter, isTrue);
    expect(wake.fastStartupEnabled, isTrue);
    expect(
      wake.wakeOnMagicPacket,
      isNull,
      reason: 'unreadable must stay unreadable across the wire',
    );
  }, skip: skipReason);
}

/// The Node relay, run for real.
class _Relay {
  _Relay(this.process, this.baseUrl, this.desktopToken, this.stateDirectory) {
    // Wrangler is chatty, and a child whose pipes nobody reads blocks once the
    // buffer fills — which looks exactly like a server that never starts.
    process.stdout.transform(utf8.decoder).listen(_remember);
    process.stderr.transform(utf8.decoder).listen(_remember);
  }

  final Process process;
  final String baseUrl;
  final String desktopToken;
  final Directory stateDirectory;
  final _output = <String>[];

  void _remember(String chunk) {
    _output.add(chunk);
    if (_output.length > 200) _output.removeAt(0);
  }

  String get _tail => _output.join().trimRight();

  static const _projectDirectory = 'serverless/notifications';

  static bool isAvailable() {
    return File('$_projectDirectory/wrangler.toml').existsSync() &&
        File(_wranglerBinary).existsSync();
  }

  /// The locally installed wrangler, not one resolved through npx: the tests
  /// must run the version the project pins, and npx would go to the network.
  ///
  /// Absolute because Windows runs this through cmd, which reads a path with
  /// forward slashes as a command followed by arguments.
  static String get _wranglerBinary {
    final suffix = Platform.isWindows ? '.cmd' : '';
    return File(
      '$_projectDirectory/node_modules/.bin/wrangler$suffix',
    ).absolute.path;
  }

  static Future<_Relay> start({required String desktopToken}) async {
    final port = await _freePort();
    // Its own D1 state directory, so a previous run cannot leave rows behind
    // and nothing here can reach the deployed database.
    final stateDirectory = Directory.systemTemp.createTempSync('amc-relay-');

    final schema = await Process.run(
      _wranglerBinary,
      [
        'd1',
        'execute',
        'amc-relay',
        '--local',
        '--persist-to',
        stateDirectory.path,
        '--file',
        'worker/schema.sql',
      ],
      workingDirectory: _projectDirectory,
      runInShell: Platform.isWindows,
    );
    if (schema.exitCode != 0) {
      throw StateError(
        'Could not create the local D1 schema: ${schema.stderr}',
      );
    }

    final process = await Process.start(
      _wranglerBinary,
      [
        'dev',
        '--local',
        '--port',
        '$port',
        '--persist-to',
        stateDirectory.path,
        '--var',
        'DESKTOP_API_TOKEN:$desktopToken',
      ],
      workingDirectory: _projectDirectory,
      runInShell: Platform.isWindows,
    );

    final relay = _Relay(
      process,
      'http://127.0.0.1:$port/api',
      desktopToken,
      stateDirectory,
    );
    await relay._waitUntilListening();
    return relay;
  }

  Future<void> _waitUntilListening() async {
    // Wrangler has a workerd runtime to boot, so this is slower than a bare
    // Node process and the window has to allow for it.
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final response = await http
            .get(
              Uri.parse('$baseUrl/config'),
              headers: const {'User-Agent': 'amc-e2e/1.0'},
            )
            .timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) return;
      } catch (_) {
        // Not up yet.
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    final output = _tail;
    await stop();
    throw StateError('Wrangler did not start listening.\n$output');
  }

  Future<void> stop() async {
    // Wrangler spawns workerd as a child, and killing only the parent leaves
    // it holding the port.
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/pid', '${process.pid}', '/T', '/F']);
    } else {
      process.kill();
    }
    await process.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () => -1,
    );
    try {
      if (stateDirectory.existsSync()) {
        stateDirectory.deleteSync(recursive: true);
      }
    } catch (_) {
      // Windows sometimes still holds a handle; a temp directory left behind
      // is not worth failing a test run over.
    }
  }

  Map<String, String> get desktopHeaders => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $desktopToken',
  };

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }
}

class _Harness {
  _Harness({
    required this.desktop,
    required this.phone,
    required this.runner,
    required this.processes,
    required this.relay,
    required this.desktopId,
  });

  final RemoteControlService desktop;
  final RemoteControlService phone;
  final ReleaseRunnerService runner;
  final _FakeProcesses processes;
  final _Relay relay;
  final String desktopId;

  static var _sequence = 0;

  static Future<_Harness> create(
    _Relay relay, {
    required List<String> scopes,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final store = await ProjectStoreService().init();
    // A desktop id per test. Agents from earlier tests can still be inside a
    // long poll when the next one starts, and sharing an id would let them
    // claim each other's commands.
    final desktopId = 'e2e-desktop-${++_sequence}';
    await store.saveRemoteControlSettings(
      RemoteControlSettings(desktopId: desktopId),
    );
    await store.saveNotificationSettings(
      const ReleaseNotificationSettings().copyWith(
        endpointBaseUrl: relay.baseUrl,
      ),
    );

    final desktopCredentials = NotificationCredentialStoreService(
      secureStore: _MemorySecureKeyValueStore(),
    );
    await desktopCredentials.saveApiToken(relay.desktopToken);

    final processes = _FakeProcesses();
    final runner = ReleaseRunnerService();

    final desktop = await RemoteControlService(
      store: store,
      catalog: ScriptCatalogService(),
      runner: runner,
      connect: ReleaseCenterConnect(),
      credentialStore: desktopCredentials,
      mobileCredentialStore: MobileControlCredentialStoreService(
        secureStore: _MemorySecureKeyValueStore(),
      ),
      power: MachinePowerService(processRunner: processes.run),
      wakeDiagnostics: WakeDiagnosticsService(
        processRunner: processes.runDiagnostics,
      ),
      autoStart: WindowsAutoStartService(
        startupDirectory: Directory.systemTemp.path,
        executablePath: Platform.resolvedExecutable,
      ),
    ).init();

    // Pair a phone the way the desktop's Options screen does.
    final pairing = await _postJson('${relay.baseUrl}/pairings', {
      'source': 'desktop',
      'scopes': scopes,
    }, relay.desktopHeaders);

    final phone = await RemoteControlService(
      store: store,
      catalog: ScriptCatalogService(),
      runner: ReleaseRunnerService(),
      connect: ReleaseCenterConnect(),
      credentialStore: NotificationCredentialStoreService(
        secureStore: _MemorySecureKeyValueStore(),
      ),
      mobileCredentialStore: MobileControlCredentialStoreService(
        secureStore: _MemorySecureKeyValueStore(),
      ),
    ).init();

    await phone.linkMobileDevice(
      endpointBaseUrl: relay.baseUrl,
      pairingCode: '${pairing['pairingCode']}',
      pairingId: '${pairing['pairingId']}',
      deviceName: 'E2E phone',
    );

    final harness = _Harness(
      desktop: desktop,
      phone: phone,
      runner: runner,
      processes: processes,
      relay: relay,
      desktopId: desktopId,
    );
    addTearDown(harness.dispose);
    return harness;
  }

  Future<void> dispose() async {
    await desktop.setEnabled(false);
    desktop.onClose();
    phone.onClose();
  }

  Future<void> waitForDesktopOnline() async {
    await _until(() async {
      final body = await _getJson(
        '${relay.baseUrl}/mobile/desktop-state',
        phone.mobileSettings.value.deviceControlToken,
      );
      final desktop = body['desktop'];
      return desktop is Map &&
          desktop['online'] == true &&
          desktop['desktopId'] == desktopId;
    }, what: 'desktop to report online');
  }

  /// Waits for the agent to pick the command up and finish it.
  Future<Map<String, Object?>> waitForCommand(
    String commandId,
    String status,
  ) async {
    Map<String, Object?>? command;
    await _until(() async {
      final body = await _getJson(
        '${relay.baseUrl}/mobile/commands/$commandId',
        phone.mobileSettings.value.deviceControlToken,
      );
      command = Map<String, Object?>.from(body['command'] as Map);
      return command!['status'] == status;
    }, what: 'command $commandId to reach $status');
    return command!;
  }

  Future<void> _until(
    Future<bool> Function() condition, {
    required String what,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('Timed out waiting for $what.');
  }
}

Future<Map<String, Object?>> _postJson(
  String url,
  Map<String, Object?> body,
  Map<String, String> headers,
) async {
  final response = await http.post(
    Uri.parse(url),
    headers: headers,
    body: jsonEncode(body),
  );
  if (response.statusCode >= 300) {
    throw StateError(
      'POST $url failed: ${response.statusCode} ${response.body}',
    );
  }
  return Map<String, Object?>.from(jsonDecode(response.body) as Map);
}

Future<Map<String, Object?>> _getJson(String url, String token) async {
  final response = await http.get(
    Uri.parse(url),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (response.statusCode >= 300) {
    throw StateError(
      'GET $url failed: ${response.statusCode} ${response.body}',
    );
  }
  return Map<String, Object?>.from(jsonDecode(response.body) as Map);
}

class _FakeProcesses {
  /// Power actions only. The agent also probes the machine on every
  /// heartbeat, and recording those would drown out what the phone asked for.
  final calls = <({String executable, List<String> arguments})>[];

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final probe = _probeAnswer(executable, arguments);
    if (probe != null) return probe;

    calls.add((executable: executable, arguments: arguments));
    return ProcessResult(1, 0, '', '');
  }

  ProcessResult? _probeAnswer(String executable, List<String> arguments) {
    if (executable == 'tasklist.exe') {
      return ProcessResult(1, 0, 'INFO: No tasks are running.', '');
    }
    if (executable == 'powercfg.exe' && arguments.contains('/a')) {
      return ProcessResult(
        1,
        0,
        'The following sleep states are available on this system:\n'
            '    Standby (S3)\n    Hibernate\n',
        '',
      );
    }
    return null;
  }

  /// Answers the diagnostics and lock-state probes without recording them, so
  /// assertions about `calls` stay about power actions alone.
  ///
  /// The JSON is output captured from a real Windows machine.
  Future<ProcessResult> runDiagnostics(
    String executable,
    List<String> arguments,
  ) async {
    return ProcessResult(
      1,
      0,
      '{"adapterName":"Wi-Fi","physicalMediaType":"Native 802.11",'
          '"mac":"84-9E-56-EA-B7-F1","ipv4":"192.168.1.225",'
          '"prefixLength":24,"wakeOnMagicPacket":null,'
          '"hiberbootEnabled":1,"disableArso":null,"bitlockerPin":null}',
      '',
    );
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
