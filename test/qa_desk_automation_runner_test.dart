import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/models/automation_models.dart';
import 'package:app_management_center/app/modules/qa_desk/models/qa_models.dart';
import 'package:app_management_center/app/modules/qa_desk/models/scenario_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/account_vault.dart';
import 'package:app_management_center/app/modules/qa_desk/services/automation_runner.dart';
import 'package:app_management_center/app/modules/qa_desk/services/flow_compiler.dart';
import 'package:app_management_center/app/modules/qa_desk/services/maestro_manager.dart';
import 'package:app_management_center/app/modules/qa_desk/services/safe_process_runner.dart';
import 'package:app_management_center/app/modules/qa_desk/services/vault_cipher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'qa_desk_fakes.dart';

const password = 'S3cret-Owner';

/// What one fake Maestro run does.
class Script {
  const Script({
    required this.exitCode,
    this.loggedIn = true,
    this.failure,
    this.output = const [],
    this.brokenOutput = false,
  });

  final int exitCode;
  final bool loggedIn;

  /// Error of the step after login; null when the run passes.
  final String? failure;
  final List<String> output;

  /// The console breaks half-way, as it did on bytes that were not UTF-8.
  final bool brokenOutput;
}

/// Plays Maestro: writes the output folder it would, prints, exits.
class FakeMaestroRunner extends SafeProcessRunner {
  FakeMaestroRunner(this.scripts);

  final List<Script> scripts;
  final arguments = <List<String>>[];
  final environments = <Map<String, String>>[];

  @override
  Future<RunningProcess> start({
    required QaSuite suite,
    required String workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    final script = scripts[arguments.length];
    arguments.add(suite.arguments);
    environments.add(environment);
    final args = suite.arguments;
    final out = args[args.indexOf('--test-output-dir') + 1];
    final flow = Directory(p.join(out, '2026-10-02_101010', 'flow'));
    await Directory(p.join(flow.path, 'screenshots')).create(recursive: true);
    Map<String, dynamic> entry(
      Map<String, dynamic> command, {
      bool failed = false,
      int depth = 0,
      String? error,
    }) => {
      'command': command,
      'metadata': {
        'status': failed ? 'FAILED' : 'COMPLETED',
        'duration': 100,
        'depth': depth,
        'error': ?(error == null ? null : {'message': error}),
      },
    };
    final failedLogin = !script.loggedIn;
    await File(p.join(flow.path, 'commands.json')).writeAsString(
      jsonEncode([
        entry({
          'defineVariablesCommand': {
            'env': {'MAESTRO_QA_PASSWORD': environment['MAESTRO_QA_PASSWORD']},
          },
        }),
        entry({'launchAppCommand': <String, dynamic>{}}),
        entry({
          'runFlowCommand': {'sourceDescription': 'login.yaml'},
        }, failed: failedLogin),
        entry(
          {
            'inputTextCommand': {'text': environment['MAESTRO_QA_PASSWORD']},
          },
          depth: 1,
          failed: failedLogin,
          error: failedLogin
              ? 'Sai mật khẩu ${environment['MAESTRO_QA_PASSWORD']}'
              : null,
        ),
        if (script.loggedIn)
          entry({
            'takeScreenshotCommand': {'path': FlowCompiler.loginMarker},
          }),
        if (script.loggedIn)
          entry(
            {
              'assertConditionCommand': {
                'condition': {
                  'visible': {'textRegex': 'Trang chủ'},
                },
              },
            },
            failed: script.failure != null,
            error: script.failure,
          ),
      ]),
    );
    if (script.loggedIn) {
      await Directory(p.join(flow.path, 'takeScreenshot')).create();
      await File(
        p.join(flow.path, 'takeScreenshot', 'qa-login-ok.png'),
      ).writeAsBytes(const [1]);
    }
    if (script.exitCode != 0) {
      await File(
        p.join(flow.path, 'screenshots', 'step-5.png'),
      ).writeAsBytes(const [1]);
    }
    final console = StreamController<String>();
    final process = FakeRunning(console, Completer<int>());
    for (final line in script.output) {
      process.emit(line);
    }
    if (script.brokenOutput) {
      console.addError(
        const FormatException('Missing extension byte', null, 13),
      );
    }
    process.emit('');
    process.emit('╭──────╮');
    process.finish(script.exitCode);
    return process;
  }
}

const emulator = DeviceInfo(
  id: 'emulator-5554',
  name: 'Pixel',
  platform: 'android-x64',
  category: 'mobile',
  isEmulator: true,
);

const shopApp = QaApp(
  id: 'shop',
  name: 'Shop',
  environments: [
    QaAppEnvironment(name: 'staging', appId: 'vn.example.shop.staging'),
    QaAppEnvironment(
      name: 'production',
      appId: 'vn.example.shop',
      production: true,
    ),
  ],
  loginFlow: 'flows/login.yaml',
  cleanupFlow: 'flows/cleanup.yaml',
  productionGuard: ['Xoá'],
);

TestScenario scenario({
  String id = 'xem-don',
  bool writes = false,
  List<AutomationStep> steps = const [
    AutomationStep(type: AutomationStepType.launch),
    AutomationStep(type: AutomationStepType.login),
    AutomationStep(type: AutomationStepType.assertVisible, target: 'Trang chủ'),
  ],
}) => TestScenario(
  id: id,
  title: 'Kịch bản $id',
  module: 'Đơn',
  suiteId: '',
  automation: AutomationSpec(
    app: 'shop',
    role: 'Chủ shop',
    writes: writes,
    steps: steps,
  ),
);

void main() {
  late Directory sandbox;
  late QaSource source;
  late LocalAccountVault vault;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('qa_runner_');
    source = QaSource(
      id: 'shop',
      name: 'Shop',
      path: sandbox.path,
      type: SourceType.flutter,
      suites: const [],
      apps: const [shopApp],
    );
    vault = LocalAccountVault(store: MemorySecretStore(), machine: 'pc');
    await vault.load();
    for (final environment in ['staging', 'production']) {
      await vault.save(
        DemoAccount(
          id: 'owner-$environment',
          app: 'shop',
          environment: environment,
          role: 'Chủ shop',
          username: '0912345678',
          password: password,
          access: environment == 'production'
              ? AccountAccess.readOnly
              : AccountAccess.readWrite,
        ),
      );
    }
  });

  tearDown(() => sandbox.delete(recursive: true));

  AutomationRunner runnerWith(
    FakeMaestroRunner processes, {
    bool ready = true,
    Duration leaseWait = Duration.zero,
  }) => AutomationRunner(
    vault: vault,
    maestro: ReadyMaestro(ready: ready),
    processRunner: processes,
    leaseWait: leaseWait,
    leasePoll: const Duration(milliseconds: 5),
  );

  Future<(AutomationOutcome, List<String>)> execute(
    AutomationRunner runner,
    TestScenario item, {
    String environment = 'staging',
    DeviceInfo? device = emulator,
  }) async {
    final logs = <String>[];
    final outcome = await runner.execute(
      source: source,
      scenario: item,
      environmentName: environment,
      runId: 'run-${DateTime.now().microsecondsSinceEpoch}',
      device: device,
      outputDirectory: Directory(
        p.join(sandbox.path, 'out-${DateTime.now().microsecondsSinceEpoch}'),
      ),
      log: logs.add,
      started: (_) {},
      cancelled: () => false,
    );
    return (outcome, logs);
  }

  group('problems', () {
    test('Maestro, the vault, the environment and accounts', () async {
      final runner = runnerWith(FakeMaestroRunner([]), ready: false);
      await runner.refreshStatus();
      expect(
        runner.problems(source, scenario(), 'staging').map((p) => p.kind),
        [AutomationProblemKind.setup],
      );

      await runner.refreshStatus();
      final ready = runnerWith(FakeMaestroRunner([]));
      await ready.refreshStatus();
      expect(ready.problems(source, scenario(), 'staging'), isEmpty);
      expect(
        ready.problems(source, scenario(), 'uat').single.kind,
        AutomationProblemKind.config,
      );

      await vault.delete('owner-staging');
      expect(
        ready.problems(source, scenario(), 'staging').single.message,
        contains('chưa có tài khoản "Chủ shop"'),
      );
    });

    test('production: never writes, guarded labels, and a warning', () async {
      final runner = runnerWith(FakeMaestroRunner([]));
      await runner.refreshStatus();

      final writing = runner.problems(
        source,
        scenario(writes: true),
        'production',
      );
      expect(
        writing.map((problem) => problem.kind),
        contains(AutomationProblemKind.writesOnProduction),
      );
      expect(writing.first.blocking, isTrue);

      final reading = runner.problems(source, scenario(), 'production');
      expect(reading.single.kind, AutomationProblemKind.production);
      expect(reading.single.blocking, isFalse);

      final deleting = scenario(
        id: 'xoa',
        steps: const [
          AutomationStep(type: AutomationStepType.tap, target: 'Xoá đơn'),
        ],
      );
      await runner.writeFlow(source, deleting);
      final guarded = runner.problems(source, deleting, 'production');
      expect(guarded.single.kind, AutomationProblemKind.productionGuard);
      expect(guarded.single.message, contains('Xoá'));
    });
  });

  test('runs Maestro with the account in its environment only, and masks '
      'it everywhere', () async {
    final processes = FakeMaestroRunner([
      const Script(exitCode: 0, output: ['typed $password into the field']),
    ]);
    final runner = runnerWith(processes);
    await runner.refreshStatus();

    final (outcome, logs) = await execute(runner, scenario());

    expect(outcome.status, RunStatus.passed);
    final env = processes.environments.single;
    expect(env['MAESTRO_QA_USERNAME'], '0912345678');
    expect(env['MAESTRO_QA_PASSWORD'], password);
    expect(env['MAESTRO_QA_APP_ID'], 'vn.example.shop.staging');
    expect(env['MAESTRO_QA_ENVIRONMENT'], 'staging');
    expect(env['MAESTRO_QA_ROLE'], 'Chủ shop');
    expect(env['MAESTRO_CLI_NO_ANALYTICS'], '1');
    final args = processes.arguments.single;
    expect(args.first, 'test');
    expect(args, containsAllInOrder(['--device', 'emulator-5554']));
    expect(args, contains('--no-ansi'));

    // The flow was written from the steps, without any account value.
    final flow = File(
      p.join(sandbox.path, '.fiza-qa', 'flows', 'xem-don.yaml'),
    );
    expect(flow.readAsStringSync(), isNot(contains(password)));

    expect(logs, contains('typed •••• into the field'));
    expect(logs.any((line) => line.contains(password)), isFalse);
    expect(logs.any((line) => line.contains('╭')), isFalse);
    expect(logs.first, contains('0912•••678'));

    final details = jsonDecode(File(outcome.detailsPath!).readAsStringSync());
    expect(details['loginFailed'], isFalse);
    expect(
      (details['steps'] as List).map((step) => step['label']),
      contains('Đã qua đăng nhập'),
    );
    for (final file in Directory(
      p.dirname(outcome.detailsPath!),
    ).listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.png')) continue;
      expect(
        file.readAsStringSync(),
        isNot(contains(password)),
        reason: file.path,
      );
    }
    expect(vault.leases, isEmpty, reason: 'the lease is given back');
  });

  test('a failed login marks the account and skips it for the rest of the '
      'batch', () async {
    final processes = FakeMaestroRunner([
      const Script(exitCode: 1, loggedIn: false),
      const Script(exitCode: 0),
    ]);
    final runner = runnerWith(processes);
    await runner.refreshStatus();
    runner.beginBatch();

    final (first, firstLogs) = await execute(runner, scenario());
    expect(first.status, RunStatus.failed);
    expect(first.screenshotPath, endsWith('step-5.png'));
    expect(firstLogs, contains('Lỗi: Sai mật khẩu ••••'));
    final account = vault.accounts.firstWhere(
      (item) => item.id == 'owner-staging',
    );
    expect(account.status, AccountStatus.loginFailed);
    expect(account.statusMessage, 'Sai mật khẩu ••••');

    final (second, secondLogs) = await execute(runner, scenario(id: 'khac'));
    expect(second.status, RunStatus.failed);
    expect(processes.arguments, hasLength(1), reason: 'Maestro not started');
    expect(secondLogs.single, contains('bỏ qua'));

    // A new batch tries again, and a login that works clears the mark.
    runner.beginBatch();
    final (third, _) = await execute(runner, scenario(id: 'khac'));
    expect(third.status, RunStatus.passed);
    expect(
      vault.accounts.firstWhere((item) => item.id == 'owner-staging').status,
      AccountStatus.ok,
    );
  });

  test('a failure after login is the app, not the account', () async {
    final runner = runnerWith(
      FakeMaestroRunner([
        const Script(exitCode: 1, failure: 'Assertion is false'),
      ]),
    );
    await runner.refreshStatus();

    final (outcome, logs) = await execute(runner, scenario());

    expect(outcome.status, RunStatus.failed);
    expect(logs, contains('Bước lỗi: Thấy "Trang chủ"'));
    expect(
      vault.accounts.firstWhere((item) => item.id == 'owner-staging').status,
      AccountStatus.ok,
    );
  });

  test('a writing scenario cleans up after itself on staging', () async {
    final processes = FakeMaestroRunner([
      const Script(exitCode: 0),
      const Script(exitCode: 0),
    ]);
    final runner = runnerWith(processes);
    await runner.refreshStatus();

    final (outcome, logs) = await execute(runner, scenario(writes: true));

    expect(outcome.status, RunStatus.passed);
    expect(processes.arguments, hasLength(2));
    expect(
      processes.arguments.last[1],
      p.join(sandbox.path, '.fiza-qa', 'flows/cleanup.yaml'),
    );
    expect(logs, contains(startsWith('Dọn dữ liệu')));
  });

  test('waits for an account someone else holds, then gives up', () async {
    final runner = runnerWith(
      FakeMaestroRunner([]),
      leaseWait: const Duration(milliseconds: 20),
    );
    await runner.refreshStatus();
    final account = vault.accounts.firstWhere(
      (item) => item.id == 'owner-staging',
    );
    await vault.acquire(account, runId: 'someone-else');

    final (outcome, logs) = await execute(runner, scenario());

    expect(outcome.status, RunStatus.failed);
    expect(logs.first, contains('đang chờ'));
    expect(logs.last, contains('thôi chờ'));
  });

  test(
    'a production run checks the guard on a flow written just now',
    () async {
      final processes = FakeMaestroRunner([]);
      final runner = runnerWith(processes);
      await runner.refreshStatus();
      final deleting = scenario(
        id: 'xoa-moi',
        steps: const [
          AutomationStep(type: AutomationStepType.tap, target: 'Xoá đơn'),
        ],
      );
      // No flow on disk yet, so the pre-run check sees nothing to block.
      expect(
        runner
            .problems(source, deleting, 'production')
            .where((problem) => problem.blocking),
        isEmpty,
      );

      final (outcome, logs) = await execute(
        runner,
        deleting,
        environment: 'production',
      );

      expect(outcome.status, RunStatus.failed);
      expect(logs.last, contains('nhãn bị cấm'));
      expect(processes.arguments, isEmpty);
    },
  );

  test(
    'a broken console still gives the result, with the account masked',
    () async {
      final runner = runnerWith(
        FakeMaestroRunner([
          const Script(
            exitCode: 1,
            failure: 'Assertion is false',
            brokenOutput: true,
          ),
        ]),
      );
      await runner.refreshStatus();

      final (outcome, logs) = await execute(runner, scenario());

      expect(outcome.status, RunStatus.failed);
      expect(logs, contains(startsWith('Không đọc tiếp được output')));
      expect(logs, contains('Bước lỗi: Thấy "Trang chủ"'));
      expect(outcome.detailsPath, isNotNull);
      for (final file in Directory(
        p.dirname(outcome.detailsPath!),
      ).listSync(recursive: true).whereType<File>()) {
        if (file.path.endsWith('.png')) continue;
        expect(
          file.readAsStringSync(),
          isNot(contains(password)),
          reason: file.path,
        );
      }
    },
  );

  test('Maestro is told to write UTF-8 whatever the Windows code page', () {
    final command = ReadyMaestro().command(
      const MaestroStatus(installed: true, javaVersion: 21, java: 'java.exe'),
    )!;
    expect(
      command.prefix,
      containsAll(['-Dstdout.encoding=UTF-8', '-Dstderr.encoding=UTF-8']),
    );
    expect(command.prefix.last, 'maestro.cli.AppKt');
  });

  test('an Android scenario needs a device', () async {
    final runner = runnerWith(FakeMaestroRunner([]));
    await runner.refreshStatus();

    final (outcome, logs) = await execute(runner, scenario(), device: null);

    expect(outcome.status, RunStatus.failed);
    expect(logs.single, contains('chưa chọn thiết bị'));
  });
}
