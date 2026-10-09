import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/automation_models.dart';
import '../models/qa_models.dart';
import '../models/scenario_models.dart';
import 'account_vault.dart';
import 'app_installer.dart';
import 'flow_compiler.dart';
import 'maestro_manager.dart';
import 'maestro_results.dart';
import 'safe_process_runner.dart';
import 'secret_redactor.dart';

/// Something that keeps a scenario from running, found before it starts.
class AutomationProblem {
  const AutomationProblem(this.kind, this.message, {this.blocking = true});

  final AutomationProblemKind kind;
  final String message;
  final bool blocking;
}

enum AutomationProblemKind {
  setup,
  vault,
  config,
  account,
  writesOnProduction,
  productionGuard,

  /// Not a blocker, but the page asks before running against production.
  production,
}

class AutomationOutcome {
  const AutomationOutcome({
    required this.status,
    this.exitCode,
    this.screenshotPath,
    this.detailsPath,
  });

  final RunStatus status;
  final int? exitCode;
  final String? screenshotPath;

  /// `steps.json`: the commands Maestro ran, for the results page.
  final String? detailsPath;
}

class LoginCheckResult {
  const LoginCheckResult({
    required this.ok,
    required this.message,
    this.screenshotPath,
  });

  final bool ok;
  final String message;
  final String? screenshotPath;
}

/// Runs scenarios QA Desk operates itself: picks and holds a demo account,
/// puts the right build on the device, runs Maestro with the account in its
/// environment only, masks every secret in what it leaves behind, and reads
/// back what happened step by step.
class AutomationRunner {
  AutomationRunner({
    required this.vault,
    required this.maestro,
    required this.processRunner,
    this.installer,
    this.compiler = const FlowCompiler(),
    this.guard = const ProductionGuard(),
    this.reader = const MaestroResultReader(),
    this.leaseWait = const Duration(minutes: 5),
    this.leasePoll = const Duration(seconds: 15),
    this.leaseRenew = const Duration(minutes: 1),
  });

  final AccountVault vault;
  final MaestroManager maestro;
  final SafeProcessRunner processRunner;
  final AppInstaller? installer;
  final FlowCompiler compiler;
  final ProductionGuard guard;
  final MaestroResultReader reader;
  final Duration leaseWait;
  final Duration leasePoll;
  final Duration leaseRenew;

  MaestroStatus? _status;

  /// Accounts that failed to log in during the current batch: later
  /// scenarios with them stop at once instead of failing the same way.
  final _failedLogins = <String>{};

  MaestroStatus? get status => _status;

  Future<MaestroStatus> refreshStatus() async =>
      _status = await maestro.status();

  /// The Maestro command for the process runner, once Maestro and Java are
  /// ready.
  ManagedTool? get command {
    final status = _status;
    return status == null ? null : maestro.command(status);
  }

  void beginBatch() => _failedLogins.clear();

  static File flowFile(QaSource source, TestScenario scenario) => File(
    p.join(
      source.path,
      '.fiza-qa',
      scenario.automation!.flow.isEmpty
          ? FlowCompiler.flowPathFor(scenario)
          : scenario.automation!.flow,
    ),
  );

  /// Writes the scenario's flow from its steps; returns the path it used,
  /// relative to `.fiza-qa/`.
  Future<String> writeFlow(QaSource source, TestScenario scenario) async {
    final spec = scenario.automation!;
    final app = source.app(spec.app);
    if (app == null) {
      throw FlowCompileException(
        'App "${spec.app}" không có trong .fiza-qa/project.yaml.',
      );
    }
    final relative = spec.flow.isEmpty
        ? FlowCompiler.flowPathFor(scenario)
        : spec.flow;
    final file = File(p.join(source.path, '.fiza-qa', relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(compiler.compile(scenario, app), flush: true);
    return relative;
  }

  /// Everything that would stop [scenario] in [environmentName], checked
  /// without touching the device or the network.
  List<AutomationProblem> problems(
    QaSource source,
    TestScenario scenario,
    String environmentName,
  ) {
    final spec = scenario.automation;
    if (spec == null) return const [];
    final problems = <AutomationProblem>[];
    final status = _status;
    if (status == null || !status.ready) {
      problems.add(
        AutomationProblem(
          AutomationProblemKind.setup,
          status?.problem ?? 'Chưa kiểm tra Maestro.',
        ),
      );
    }
    final app = source.app(spec.app);
    if (app == null) {
      problems.add(
        AutomationProblem(
          AutomationProblemKind.config,
          '${scenario.title}: app "${spec.app}" không có trong '
          '.fiza-qa/project.yaml của ${source.name}.',
        ),
      );
      return problems;
    }
    final environment = app.environment(environmentName);
    if (environment == null) {
      problems.add(
        AutomationProblem(
          AutomationProblemKind.config,
          '${app.name} không khai môi trường "$environmentName".',
        ),
      );
      return problems;
    }
    if (spec.writes && environment.isProduction) {
      problems.add(
        AutomationProblem(
          AutomationProblemKind.writesOnProduction,
          '${scenario.title} ghi dữ liệu nên không được chạy trên production.',
        ),
      );
    } else if (!spec.allowsEnvironment(environment)) {
      problems.add(
        AutomationProblem(
          AutomationProblemKind.config,
          '${scenario.title} không được phép chạy trên "$environmentName".',
        ),
      );
    }
    if (vault.state != VaultState.ready) {
      problems.add(
        AutomationProblem(AutomationProblemKind.vault, switch (vault.state) {
          VaultState.needsSetup => 'Team chưa có kho tài khoản demo.',
          VaultState.locked => 'Kho tài khoản đang khoá trên máy này.',
          VaultState.failed => vault.error ?? 'Không mở được kho tài khoản.',
          _ => 'Kho tài khoản đang tải.',
        }),
      );
    } else if (vault.pick(
          app: app.id,
          environment: environment.name,
          role: spec.role,
        ) ==
        null) {
      problems.add(
        AutomationProblem(
          AutomationProblemKind.account,
          'Kho chưa có tài khoản "${spec.role}" cho ${app.name} · '
          '${environment.name}.',
        ),
      );
    }
    if (environment.isProduction) {
      final flow = flowFile(source, scenario);
      final hits = flow.existsSync()
          ? guard.guardedTaps(flow, app.productionGuard)
          : const <String>[];
      if (hits.isNotEmpty) {
        problems.add(
          AutomationProblem(
            AutomationProblemKind.productionGuard,
            '${scenario.title} bấm vào nhãn bị cấm trên production: '
            '${hits.join(', ')}.',
          ),
        );
      } else {
        problems.add(
          AutomationProblem(
            AutomationProblemKind.production,
            '${scenario.title} chạy trên PRODUCTION với tài khoản chỉ đọc.',
            blocking: false,
          ),
        );
      }
    }
    return problems;
  }

  Future<AutomationOutcome> execute({
    required QaSource source,
    required TestScenario scenario,
    required String environmentName,
    required String runId,
    required DeviceInfo? device,
    required Directory outputDirectory,
    required void Function(String line) log,
    required void Function(RunningProcess process) started,
    required bool Function() cancelled,
    Map<String, String> extraEnvironment = const {},
    Iterable<String> extraSecrets = const [],
  }) async {
    final spec = scenario.automation!;
    final blocking = problems(
      source,
      scenario,
      environmentName,
    ).where((problem) => problem.blocking).toList();
    if (blocking.isNotEmpty) {
      for (final problem in blocking) {
        log(problem.message);
      }
      return const AutomationOutcome(status: RunStatus.failed);
    }
    final app = source.app(spec.app)!;
    final environment = app.environment(environmentName)!;
    if (app.platform == QaAppPlatform.android && device == null) {
      log('Kịch bản Android cần thiết bị nhưng chưa chọn thiết bị.');
      return const AutomationOutcome(status: RunStatus.failed);
    }

    final account = vault.pick(
      app: app.id,
      environment: environment.name,
      role: spec.role,
    )!;
    final production = environment.isProduction;
    final redactor = SecretRedactor([...account.secretValues, ...extraSecrets]);
    void say(String line) => log(redactor.redact(line));

    if (_failedLogins.contains(account.id)) {
      say(
        'Tài khoản "${account.role}" (${account.maskedUsername}) đã không '
        'đăng nhập được ở kịch bản trước trong lượt này; bỏ qua.',
      );
      return const AutomationOutcome(status: RunStatus.failed);
    }

    final lease = await _hold(account, runId, say, cancelled);
    if (lease == null) {
      return AutomationOutcome(
        status: cancelled() ? RunStatus.cancelled : RunStatus.failed,
      );
    }
    final renewal = Timer.periodic(
      leaseRenew,
      (_) => unawaited(vault.acquire(account, runId: runId)),
    );
    try {
      say(
        'Tài khoản: ${account.role} · ${environment.name} '
        '(${account.maskedUsername})'
        '${production ? ' · CHỈ ĐỌC trên production' : ''}',
      );
      if (app.platform == QaAppPlatform.android && installer != null) {
        try {
          say(
            await installer!.ensure(
              serial: device!.id,
              appId: environment.appId,
              environment: environment.name,
              projectPath: source.path,
              build: environment.build,
              emulator: device.isEmulator,
            ),
          );
        } on AppInstallException catch (error) {
          say(error.message);
          return const AutomationOutcome(status: RunStatus.failed);
        }
      }

      // The steps are the source of truth: a flow written by an older QA Desk
      // or edited by hand would run something else than the test case says.
      final flow = flowFile(source, scenario);
      await writeFlow(source, scenario);
      if (production) {
        // The pre-run check read the flow as it was before this write.
        final hits = guard.guardedTaps(flow, app.productionGuard);
        if (hits.isNotEmpty) {
          say(
            '${scenario.title} bấm vào nhãn bị cấm trên production: '
            '${hits.join(', ')}.',
          );
          return const AutomationOutcome(status: RunStatus.failed);
        }
      }
      await outputDirectory.create(recursive: true);
      final runDirectory = Directory(p.join(outputDirectory.path, 'run'));
      final environmentVariables = {
        ...extraEnvironment,
        ...maestro.environment(_status!),
        ...account.flowEnvironment,
        'MAESTRO_QA_APP_ID': environment.appId,
        'MAESTRO_QA_APP_URL': environment.url,
        'MAESTRO_QA_ENVIRONMENT': environment.name,
        'MAESTRO_QA_ROLE': account.role,
        'MAESTRO_QA_RUN_ID': _shortId(runId),
      };
      final exitCode = await _maestro(
        flow: flow,
        app: app,
        device: device,
        report: File(p.join(outputDirectory.path, 'report.xml')),
        runDirectory: runDirectory,
        environment: environmentVariables,
        workingDirectory: source.path,
        say: say,
        started: started,
      );
      await redactor.redactDirectory(outputDirectory);
      final report = reader.read(
        runDirectory,
        loginFlow:
            spec.steps.any((step) => step.type == AutomationStepType.login)
            ? app.loginFlow
            : '',
      );
      final details = File(p.join(outputDirectory.path, 'steps.json'));
      await details.writeAsString(
        jsonEncode({
          'loggedIn': report.loggedIn,
          'usedLogin': report.usedLogin,
          'loginFailed': report.loginFailed,
          'steps': [for (final step in report.steps) step.toJson()],
        }),
        flush: true,
      );
      final status = cancelled()
          ? RunStatus.cancelled
          : exitCode == 0
          ? RunStatus.passed
          : RunStatus.failed;

      final failed = report.failedStep;
      if (failed != null) {
        say('Bước lỗi: ${failed.label}');
        if (failed.error.isNotEmpty) say('Lỗi: ${failed.error}');
      }
      if (report.loginFailed) {
        _failedLogins.add(account.id);
        await vault.setStatus(
          account.id,
          AccountStatus.loginFailed,
          redactor.redact(failed?.error ?? 'Không qua được bước đăng nhập.'),
        );
        say(
          'Tài khoản "${account.role}" không đăng nhập được; đã đánh dấu '
          'trong kho.',
        );
      } else if (report.loggedIn &&
          account.status == AccountStatus.loginFailed) {
        await vault.setStatus(account.id, AccountStatus.ok, '');
      }

      if (spec.writes &&
          !production &&
          report.loggedIn &&
          app.cleanupFlow.isNotEmpty &&
          !cancelled()) {
        say('Dọn dữ liệu kịch bản đã tạo (${app.cleanupFlow})');
        final cleanup = await _maestro(
          flow: File(p.join(source.path, '.fiza-qa', app.cleanupFlow)),
          app: app,
          device: device,
          report: File(p.join(outputDirectory.path, 'cleanup.xml')),
          runDirectory: Directory(p.join(outputDirectory.path, 'cleanup')),
          environment: environmentVariables,
          workingDirectory: source.path,
          say: (line) => say('[dọn dữ liệu] $line'),
          started: started,
        );
        await redactor.redactDirectory(outputDirectory);
        if (cleanup != 0) say('Dọn dữ liệu không xong; kiểm tra staging.');
      }

      return AutomationOutcome(
        status: status,
        exitCode: exitCode,
        screenshotPath: status == RunStatus.failed
            ? report.failureScreenshot
            : null,
        detailsPath: details.path,
      );
    } finally {
      renewal.cancel();
      await vault.release(lease);
      // Also when the run stopped half-way: Maestro has already written the
      // account's values into its output.
      await _redactQuietly(redactor, outputDirectory, say);
    }
  }

  /// Logs [account] in alone, to check it before relying on it.
  Future<LoginCheckResult> checkLogin({
    required QaSource source,
    required QaApp app,
    required DemoAccount account,
    required DeviceInfo? device,
    required Directory outputDirectory,
    required void Function(String line) log,
  }) async {
    final status = _status ?? await refreshStatus();
    if (!status.ready) {
      return LoginCheckResult(ok: false, message: status.problem!);
    }
    final environment = app.environment(account.environment);
    if (environment == null) {
      return LoginCheckResult(
        ok: false,
        message: '${app.name} không khai môi trường "${account.environment}".',
      );
    }
    if (app.platform == QaAppPlatform.android && device == null) {
      return const LoginCheckResult(
        ok: false,
        message: 'Chọn thiết bị trước khi thử đăng nhập.',
      );
    }
    final redactor = SecretRedactor(account.secretValues);
    final runId = 'login-${DateTime.now().microsecondsSinceEpoch}';
    final lease = await vault.acquire(account, runId: runId);
    if (lease == null) {
      final holder = vault.leases[account.id];
      return LoginCheckResult(
        ok: false,
        message:
            'Tài khoản đang được ${holder?.holderName ?? 'người khác'} '
            'dùng.',
      );
    }
    try {
      await outputDirectory.create(recursive: true);
      if (app.platform == QaAppPlatform.android && installer != null) {
        log(
          await installer!.ensure(
            serial: device!.id,
            appId: environment.appId,
            environment: environment.name,
            projectPath: source.path,
            build: environment.build,
            emulator: device.isEmulator,
          ),
        );
      }
      final flow = File(p.join(outputDirectory.path, 'login_check.yaml'));
      final loginFlow = p.join(source.path, '.fiza-qa', app.loginFlow);
      await flow.writeAsString(compiler.loginCheck(app, loginFlow));
      final runDirectory = Directory(p.join(outputDirectory.path, 'run'));
      final exitCode = await _maestro(
        flow: flow,
        app: app,
        device: device,
        report: File(p.join(outputDirectory.path, 'report.xml')),
        runDirectory: runDirectory,
        environment: {
          ...maestro.environment(status),
          ...account.flowEnvironment,
          'MAESTRO_QA_APP_ID': environment.appId,
          'MAESTRO_QA_APP_URL': environment.url,
          'MAESTRO_QA_ENVIRONMENT': environment.name,
          'MAESTRO_QA_ROLE': account.role,
        },
        workingDirectory: source.path,
        say: (line) => log(redactor.redact(line)),
        started: (_) {},
      );
      await redactor.redactDirectory(outputDirectory);
      final report = reader.read(runDirectory, loginFlow: app.loginFlow);
      final ok = exitCode == 0 && report.loggedIn;
      final message = ok
          ? 'Đăng nhập được.'
          : redactor.redact(
              report.failedStep?.error.isNotEmpty == true
                  ? report.failedStep!.error
                  : 'Không qua được bước đăng nhập.',
            );
      await vault.setStatus(
        account.id,
        ok ? AccountStatus.ok : AccountStatus.loginFailed,
        ok ? '' : message,
      );
      return LoginCheckResult(
        ok: ok,
        message: message,
        screenshotPath: report.failureScreenshot,
      );
    } on AppInstallException catch (error) {
      return LoginCheckResult(ok: false, message: error.message);
    } on FlowCompileException catch (error) {
      return LoginCheckResult(ok: false, message: error.message);
    } finally {
      await vault.release(lease);
      await _redactQuietly(
        redactor,
        outputDirectory,
        (line) => log(redactor.redact(line)),
      );
    }
  }

  static Future<void> _redactQuietly(
    SecretRedactor redactor,
    Directory directory,
    void Function(String line) say,
  ) async {
    try {
      await redactor.redactDirectory(directory);
    } on Object catch (error) {
      say(
        'Không che hết được giá trị tài khoản trong ${directory.path}: $error',
      );
    }
  }

  Future<AccountLease?> _hold(
    DemoAccount account,
    String runId,
    void Function(String) say,
    bool Function() cancelled,
  ) async {
    final deadline = DateTime.now().add(leaseWait);
    var announced = false;
    while (true) {
      final lease = await vault.acquire(account, runId: runId);
      if (lease != null) return lease;
      if (cancelled()) return null;
      final holder = vault.leases[account.id];
      if (DateTime.now().isAfter(deadline)) {
        say(
          'Tài khoản "${account.role}" vẫn đang được '
          '${holder?.holderName ?? 'người khác'} dùng; thôi chờ.',
        );
        return null;
      }
      if (!announced) {
        announced = true;
        say(
          'Tài khoản "${account.role}" đang được '
          '${holder?.holderName ?? 'người khác'} dùng'
          '${holder == null ? '' : ' tới ${_clock(holder.expiresAt)}'}; '
          'đang chờ…',
        );
      }
      await Future<void>.delayed(leasePoll);
    }
  }

  Future<int> _maestro({
    required File flow,
    required QaApp app,
    required DeviceInfo? device,
    required File report,
    required Directory runDirectory,
    required Map<String, String> environment,
    required String workingDirectory,
    required void Function(String line) say,
    required void Function(RunningProcess process) started,
  }) async {
    final arguments = [
      'test',
      flow.path,
      '--no-ansi',
      '--format',
      'JUNIT',
      '--output',
      report.path,
      '--test-output-dir',
      runDirectory.path,
      if (device != null && app.platform == QaAppPlatform.android) ...[
        '--device',
        device.id,
      ],
      if (app.platform == QaAppPlatform.web) ...['-p', 'web'],
    ];
    final suite = QaSuite(
      id: 'maestro',
      name: 'Maestro',
      executable: 'maestro',
      arguments: arguments,
    );
    say('> maestro test ${p.basename(flow.path)}');
    final process = await processRunner.start(
      suite: suite,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    started(process);
    var deviceUnseen = false;
    try {
      await for (final raw in process.output) {
        // Maestro colours its errors even with --no-ansi.
        final line = raw.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
        if (_noise(line)) continue;
        if (line.contains('was requested, but it is not connected')) {
          deviceUnseen = true;
        }
        say(line);
      }
    } on Object catch (error) {
      // Losing the console must not lose the run: its result is read from
      // the output folder once Maestro exits.
      say('Không đọc tiếp được output của Maestro: $error');
    }
    if (deviceUnseen) {
      say(
        'Maestro không thấy thiết bị dù adb thấy. Thường do đang cắm một '
        'điện thoại chưa cho phép USB debugging (unauthorized): mở khoá điện '
        'thoại và bấm Cho phép, hoặc rút cáp, rồi chạy lại.',
      );
    }
    return process.exitCode;
  }

  /// Maestro's box-drawn cloud advert and blank lines.
  static bool _noise(String line) {
    final trimmed = line.replaceAll('[stderr] ', '').trim();
    if (trimmed.isEmpty) return true;
    return RegExp(r'^[?│╭╮╰╯─\s]+$').hasMatch(trimmed) ||
        trimmed.contains('maestro cloud') ||
        trimmed.contains('Maestro Cloud') ||
        trimmed.contains('Debug tests faster');
  }

  static String _shortId(String runId) {
    final digits = runId.replaceAll(RegExp(r'\D'), '');
    return digits.length <= 6 ? digits : digits.substring(digits.length - 6);
  }

  static String _clock(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }
}
