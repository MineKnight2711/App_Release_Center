import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/modules/qa_desk/models/automation_models.dart';
import 'package:app_management_center/app/modules/qa_desk/models/scenario_models.dart';
import 'package:app_management_center/app/modules/qa_desk/services/flow_compiler.dart';
import 'package:app_management_center/app/modules/qa_desk/services/maestro_results.dart';
import 'package:app_management_center/app/modules/qa_desk/services/secret_redactor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const shop = QaApp(
  id: 'shop',
  name: 'Shop',
  environments: [
    QaAppEnvironment(name: 'staging', appId: 'vn.example.shop.staging'),
  ],
  loginFlow: 'flows/login.yaml',
);

TestScenario automated(
  String title,
  List<AutomationStep> steps, {
  String id = 'tao-don',
}) => TestScenario(
  id: id,
  title: title,
  module: 'Đơn',
  suiteId: '',
  automation: AutomationSpec(app: 'shop', role: 'Chủ shop', steps: steps),
);

/// A `commands.json` shaped like the one Maestro 2.11 writes.
String commandsJson({required bool loggedIn, String? failure}) {
  Map<String, dynamic> entry(
    Map<String, dynamic> command, {
    String status = 'COMPLETED',
    int depth = 0,
    String? error,
  }) => {
    'command': command,
    'metadata': {
      'status': status,
      'duration': 1200,
      'depth': depth,
      'error': ?(error == null ? null : {'message': error}),
    },
  };
  return jsonEncode([
    entry({
      'defineVariablesCommand': {
        'env': {'MAESTRO_QA_PASSWORD': 'Pr0beSecret42'},
      },
    }),
    entry({
      'applyConfigurationCommand': {
        'config': {'appId': r'${MAESTRO_QA_APP_ID}'},
      },
    }),
    entry({
      'launchAppCommand': {'appId': r'${MAESTRO_QA_APP_ID}'},
    }),
    entry({
      'runFlowCommand': {'sourceDescription': 'login.yaml'},
    }, status: loggedIn ? 'COMPLETED' : 'FAILED'),
    entry({
      'tapOnElement': {
        'selector': {'textRegex': r'Đăng nhập \(OTP\)'},
      },
    }, depth: 1),
    entry(
      {
        'inputTextCommand': {'text': r'${MAESTRO_QA_PASSWORD}'},
      },
      depth: 1,
      status: loggedIn ? 'COMPLETED' : 'FAILED',
      error: loggedIn ? null : 'Element not found: Mật khẩu',
    ),
    if (loggedIn)
      entry({
        'takeScreenshotCommand': {'path': FlowCompiler.loginMarker},
      }),
    if (loggedIn)
      entry(
        {
          'assertConditionCommand': {
            'condition': {
              'visible': {'textRegex': 'Trang chủ'},
            },
          },
        },
        status: failure == null ? 'COMPLETED' : 'FAILED',
        error: failure,
      ),
  ]);
}

void main() {
  group('FlowCompiler', () {
    test('writes steps as a Maestro flow that reads the account from env', () {
      final flow = const FlowCompiler().compile(
        automated("Tạo đơn (nháp) của 'shop'", const [
          AutomationStep(type: AutomationStepType.launch, clearState: true),
          AutomationStep(type: AutomationStepType.login),
          AutomationStep(type: AutomationStepType.tap, target: 'Tạo đơn'),
          AutomationStep(
            type: AutomationStepType.input,
            target: 'Tên khách',
            value: r'QA ${MAESTRO_QA_RUN_ID}',
          ),
          AutomationStep(
            type: AutomationStepType.assertVisible,
            target: 'Tổng (VNĐ)',
          ),
          AutomationStep(
            type: AutomationStepType.tap,
            target: 'save-button',
            byId: true,
          ),
          AutomationStep(type: AutomationStepType.waitFor, target: 'Đã lưu'),
          AutomationStep(type: AutomationStepType.back),
        ]),
        shop,
      );

      expect(
        flow,
        '# Sinh bởi QA Desk từ test case "Tạo đơn (nháp) của \'shop\'". '
        'Sửa các bước trong QA Desk: lưu lại sẽ ghi đè file này.\n'
        r'# Chữ khớp trọn một dòng của phần tử: (?s)(?:.*\n)?…(?:\n.*)?, '
        'vì Flutter gộp chữ của cả một thẻ thành nhiều dòng.\n'
        'appId: \${MAESTRO_QA_APP_ID}\n'
        "name: 'Tạo đơn (nháp) của ''shop'''\n"
        '---\n'
        '- launchApp:\n'
        '    clearState: true\n'
        "- runFlow: 'login.yaml'\n"
        '- takeScreenshot: qa-login-ok\n'
        r"- tapOn: '(?s)(?:.*\n)?Tạo đơn(?:\n.*)?'"
        '\n'
        r"- tapOn: '(?s)(?:.*\n)?Tên khách(?:\n.*)?'"
        '\n'
        '- waitForAnimationToEnd\n'
        '- eraseText\n'
        "- inputText: 'QA \${MAESTRO_QA_RUN_ID}'\n"
        r"- assertVisible: '(?s)(?:.*\n)?Tổng \(VNĐ\)(?:\n.*)?'"
        '\n'
        '- tapOn:\n'
        "    id: 'save-button'\n"
        '- extendedWaitUntil:\n'
        '    visible:\n'
        r"      text: '(?s)(?:.*\n)?Đã lưu(?:\n.*)?'"
        '\n'
        '    timeout: 20000\n'
        '- back\n',
      );
    });

    test('opens a web app by url', () {
      const web = QaApp(
        id: 'shop',
        name: 'Shop web',
        platform: QaAppPlatform.web,
        environments: [
          QaAppEnvironment(name: 'staging', url: 'https://staging.example'),
        ],
      );
      final flow = const FlowCompiler().compile(
        automated('Mở', const [
          AutomationStep(type: AutomationStepType.launch),
        ]),
        web,
      );
      expect(flow, contains('url: \${MAESTRO_QA_APP_URL}\n'));
      expect(flow, isNot(contains('appId:')));
    });

    test('refuses a login step without a login flow, or a step with no '
        'target', () {
      const noLogin = QaApp(id: 'shop', name: 'Shop');
      expect(
        () => const FlowCompiler().compile(
          automated('A', const [
            AutomationStep(type: AutomationStepType.login),
          ]),
          noLogin,
        ),
        throwsA(isA<FlowCompileException>()),
      );
      expect(
        () => const FlowCompiler().compile(
          automated('A', const [AutomationStep(type: AutomationStepType.tap)]),
          shop,
        ),
        throwsA(isA<FlowCompileException>()),
      );
    });

    test('checks a login on its own with the login flow by absolute path', () {
      final flow = const FlowCompiler().loginCheck(
        shop,
        r'C:\work\shop app\.fiza-qa\flows\login.yaml',
      );
      expect(flow, contains("- runFlow: 'C:/work/shop app/.fiza-qa/flows/"));
      expect(flow, contains('    clearState: true\n'));
      expect(flow, contains('- takeScreenshot: qa-login-ok'));
    });

    test('a label matches a whole line of merged Flutter text, or any part '
        'of it', () {
      // Maestro wants the whole text of an element to match.
      bool matches(String pattern, String text) => RegExp(
        '^(?:${pattern.replaceFirst('(?s)', '')})\$',
        dotAll: true,
      ).hasMatch(text);
      const card = 'Ca hôm nay\nDoanh thu\n0\nTổng đơn hàng\n0';

      final line = FlowCompiler.textSelector('Tổng đơn hàng');
      expect(matches(line, card), isTrue);
      expect(matches(line, 'Tổng đơn hàng'), isTrue);
      expect(matches(FlowCompiler.textSelector('đơn hàng'), card), isFalse);
      expect(
        matches(FlowCompiler.textSelector('Đăng nhập'), 'Nhớ đăng nhập'),
        isFalse,
      );
      expect(
        matches(FlowCompiler.textSelector('Tổng (VNĐ)'), 'Tổng (VNĐ)'),
        isTrue,
      );

      final part = FlowCompiler.textSelector('đơn hàng', partial: true);
      expect(matches(part, card), isTrue);
      expect(matches(part, 'Tạo đơn hàng'), isTrue);

      expect(FlowCompiler.readSelector(line), (
        text: 'Tổng đơn hàng',
        partial: false,
      ));
      expect(FlowCompiler.readSelector(part), (
        text: 'đơn hàng',
        partial: true,
      ));
      expect(FlowCompiler.readSelector(r'Tổng \(VNĐ\)'), (
        text: 'Tổng (VNĐ)',
        partial: false,
      ));
    });

    test('a partial step says so and survives a round trip', () {
      const step = AutomationStep(
        type: AutomationStepType.assertVisible,
        target: 'đơn hàng',
        partial: true,
      );
      expect(step.summary, 'Thấy "đơn hàng" (khớp một phần)');
      final back = AutomationStep.fromJson(step.toJson());
      expect(back.partial, isTrue);
      final flow = const FlowCompiler().compile(automated('A', [back]), shop);
      expect(flow, contains(r"- assertVisible: '(?s).*đơn hàng.*'"));
    });

    test('a title becomes a flow name Windows accepts as a folder', () {
      // Maestro makes a folder of the name: ":" stopped it before it ran.
      expect(
        FlowCompiler.flowName('Đơn hàng: tạo nháp / "mới"?'),
        'Đơn hàng- tạo nháp - -mới--',
      );
      expect(FlowCompiler.flowName('Xong...  '), 'Xong');
      expect(FlowCompiler.flowName(' : '), '-');
      expect(FlowCompiler.flowName('...'), 'flow');
      final flow = const FlowCompiler().compile(
        automated('Đơn: xem', const [
          AutomationStep(type: AutomationStepType.launch),
        ]),
        shop,
      );
      expect(flow, contains("name: 'Đơn- xem'\n"));
    });

    test('names each scenario flow after its id', () {
      expect(
        FlowCompiler.flowPathFor(automated('A', const [], id: 'đơn mới/1')),
        'flows/_n_m_i_1.yaml',
      );
    });
  });

  group('ProductionGuard', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('qa_guard_');
    });

    tearDown(() => sandbox.delete(recursive: true));

    test('finds forbidden labels through sub-flows, ignoring case and '
        'accents', () async {
      await File(p.join(sandbox.path, 'main.yaml')).writeAsString('''
appId: x
---
- tapOn: 'Lưu'
- runFlow: sub.yaml
- repeat:
    times: 2
    commands:
      - longPressOn: 'Thanh  toán ngay'
''');
      await File(p.join(sandbox.path, 'sub.yaml')).writeAsString('''
appId: x
---
- tapOn:
    text: 'XOÁ ĐƠN'
- tapOn:
    id: 'Thanh toán'
- runFlow: main.yaml
''');
      final hits = const ProductionGuard().guardedTaps(
        File(p.join(sandbox.path, 'main.yaml')),
        const ['Xoá', 'Thanh toán', 'Huỷ'],
      );
      // By id is invisible to the guard; the loop back to main stops.
      expect(hits, ['Thanh toán', 'Xoá']);
    });

    test('reads regex-escaped labels as written', () async {
      await File(p.join(sandbox.path, 'main.yaml')).writeAsString(r'''
appId: x
---
- tapOn: 'Xoá \(vĩnh viễn\)'
''');
      expect(
        const ProductionGuard().guardedTaps(
          File(p.join(sandbox.path, 'main.yaml')),
          const ['xoa (vinh vien)'],
        ),
        ['xoa (vinh vien)'],
      );
    });

    test('reads the labels QA Desk compiles', () async {
      final flow = File(p.join(sandbox.path, 'compiled.yaml'));
      await flow.writeAsString(
        const FlowCompiler().compile(
          automated('Huỷ', const [
            AutomationStep(type: AutomationStepType.tap, target: 'Huỷ đơn'),
            AutomationStep(
              type: AutomationStepType.tap,
              target: 'thanh toán',
              partial: true,
            ),
          ]),
          shop,
        ),
      );
      expect(
        const ProductionGuard().guardedTaps(flow, const [
          'Huỷ đơn',
          'Thanh toán',
        ]),
        ['Huỷ đơn', 'Thanh toán'],
      );
    });
  });

  group('SecretRedactor', () {
    test('masks the longest secret whole and leaves short values', () {
      final redactor = SecretRedactor(const ['abcdef', 'abc', 'ab']);
      expect(redactor.redact('x abcdef y abc z ab'), 'x •••• y •••• z ab');
    });

    test('rewrites text files and leaves images alone', () async {
      final sandbox = await Directory.systemTemp.createTemp('qa_redact_');
      addTearDown(() => sandbox.delete(recursive: true));
      final json = File(p.join(sandbox.path, 'a', 'commands.json'));
      await json.parent.create();
      await json.writeAsString('{"text":"Pr0beSecret42"}');
      final image = File(p.join(sandbox.path, 'a', 'shot.png'));
      await image.writeAsString('Pr0beSecret42');

      final changed = await SecretRedactor(const [
        'Pr0beSecret42',
      ]).redactDirectory(sandbox);

      expect(changed, 1);
      expect(json.readAsStringSync(), '{"text":"••••"}');
      expect(image.readAsStringSync(), 'Pr0beSecret42');
    });
  });

  group('MaestroResultReader', () {
    test('turns commands into readable steps without typed values', () {
      final steps = const MaestroResultReader().parseCommands(
        commandsJson(loggedIn: true, failure: 'Assertion is false'),
      );
      expect(
        MaestroResultReader.describe('tapOnElement', {
          'selector': {'textRegex': FlowCompiler.textSelector('Tạo đơn')},
        }),
        'Bấm "Tạo đơn"',
      );
      expect(
        MaestroResultReader.describe('tapOnElement', {
          'selector': {
            'textRegex': FlowCompiler.textSelector('đơn', partial: true),
          },
        }),
        'Bấm chữ có "đơn"',
      );
      expect(steps.map((step) => step.label), [
        'Mở app',
        'Chạy flow login.yaml',
        'Bấm "Đăng nhập (OTP)"',
        r'Nhập "${MAESTRO_QA_PASSWORD}"',
        'Đã qua đăng nhập',
        'Thấy "Trang chủ"',
      ]);
      expect(steps[2].depth, 1);
      expect(steps.last.failed, isTrue);
      expect(steps.last.error, 'Assertion is false');
      expect(
        steps.any((step) => step.label.contains('Pr0beSecret42')),
        isFalse,
      );
    });

    test('tells a failed login from a failure after it', () async {
      final sandbox = await Directory.systemTemp.createTemp('qa_reader_');
      addTearDown(() => sandbox.delete(recursive: true));
      Future<Directory> run(String name, String commands, bool marker) async {
        final flow = Directory(
          p.join(sandbox.path, name, '2026-10-02_101010', 'Tạo đơn'),
        );
        await Directory(
          p.join(flow.path, 'screenshots'),
        ).create(recursive: true);
        await File(p.join(flow.path, 'commands.json')).writeAsString(commands);
        await File(
          p.join(flow.path, 'screenshots', 'step-7-assert.png'),
        ).writeAsBytes(const [1]);
        if (marker) {
          await Directory(p.join(flow.path, 'takeScreenshot')).create();
          await File(
            p.join(flow.path, 'takeScreenshot', 'qa-login-ok.png'),
          ).writeAsBytes(const [1]);
        }
        return Directory(p.join(sandbox.path, name));
      }

      final later = const MaestroResultReader().read(
        await run(
          'later',
          commandsJson(loggedIn: true, failure: 'Assertion is false'),
          true,
        ),
        loginFlow: 'flows/login.yaml',
      );
      expect(later.usedLogin, isTrue);
      expect(later.loggedIn, isTrue);
      expect(later.loginFailed, isFalse);
      expect(later.failedStep?.label, 'Thấy "Trang chủ"');
      expect(later.failureScreenshot, endsWith('step-7-assert.png'));

      final login = const MaestroResultReader().read(
        await run('login', commandsJson(loggedIn: false), false),
        loginFlow: 'flows/login.yaml',
      );
      // Maestro lists only what it got to: the marker is simply absent, and
      // the login flow is the step that failed.
      expect(login.loggedIn, isFalse);
      expect(login.loginFailed, isTrue);
      expect(login.failedStep?.error, 'Element not found: Mật khẩu');

      final launch = const MaestroResultReader().read(
        await run(
          'launch',
          jsonEncode([
            {
              'command': {
                'launchAppCommand': {'appId': 'x'},
              },
              'metadata': {
                'status': 'FAILED',
                'duration': 10,
                'depth': 0,
                'error': {'message': 'App not installed'},
              },
            },
          ]),
          false,
        ),
        loginFlow: 'flows/login.yaml',
      );
      // The app never started: not the account's fault.
      expect(launch.loginFailed, isFalse);
    });

    test('an empty folder is an empty report', () {
      final report = const MaestroResultReader().read(
        Directory(p.join(Directory.systemTemp.path, 'qa_missing_folder_x')),
      );
      expect(report.steps, isEmpty);
      expect(report.loginFailed, isFalse);
    });
  });
}
