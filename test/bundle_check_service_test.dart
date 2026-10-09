import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/modules/bundle_check/models/bundle_check_models.dart';
import 'package:app_management_center/app/modules/bundle_check/services/android_toolchain.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_check_service.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_check_store.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_inspector.dart';
import 'package:app_management_center/app/modules/bundle_check/services/env_file.dart';
import 'package:app_management_center/app/modules/bundle_check/services/project_contract_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'bundle_check_fixtures.dart';

class _Projects implements BundleProjectSource {
  _Projects(this.items);

  final List<BundleProjectCandidate> items;

  @override
  Future<List<BundleProjectCandidate>> candidates() async => items;

  @override
  Future<KeystoreRef?> savedKeystore(BundleProjectCandidate candidate) async =>
      null;
}

/// Answers `keytool -list` with a fixed fingerprint and records every call,
/// so the tests can check the password never reaches the command line.
class _FakeRunner implements BundleProcessRunner {
  _FakeRunner(this.keystoreSha256);

  final String keystoreSha256;
  final calls = <(String, List<String>, Map<String, String>?)>[];

  @override
  Future<BundleProcessResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    calls.add((executable, arguments, environment));
    return BundleProcessResult(
      exitCode: 0,
      stdout: 'Certificate fingerprints:\n\t SHA256: $keystoreSha256\n',
    );
  }

  @override
  Future<bool> startDetached(String executable, List<String> arguments) async =>
      false;
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('bundle_service'));
  tearDown(() => temp.deleteSync(recursive: true));

  Directory project({
    String dart = '',
    String? envExample,
    String? env,
    Map<String, String> googleServices = const {},
    String? envProperties,
    String? firebaseOptions,
  }) {
    final root = Directory(p.join(temp.path, 'demo_app'))..createSync();
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
      'name: demo\nversion: 1.2.0+12\ndependencies:\n'
      '  flutter_dotenv: ^5.0.0\n  firebase_core: ^3.0.0\n',
    );
    Directory(p.join(root.path, 'lib')).createSync();
    File(p.join(root.path, 'lib', 'main.dart')).writeAsStringSync(dart);
    if (firebaseOptions != null) {
      File(
        p.join(root.path, 'lib', 'firebase_options.dart'),
      ).writeAsStringSync(firebaseOptions);
    }
    if (envExample != null) {
      File(p.join(root.path, '.env.example')).writeAsStringSync(envExample);
    }
    if (env != null) File(p.join(root.path, '.env')).writeAsStringSync(env);
    final app = Directory(p.join(root.path, 'android', 'app'))
      ..createSync(recursive: true);
    File(p.join(app.path, 'build.gradle')).writeAsStringSync(
      'android {\n defaultConfig {\n applicationId "vn.amc.demo"\n }\n}\n',
    );
    for (final entry in googleServices.entries) {
      final dir = entry.key == 'main'
          ? app
          : (Directory(p.join(app.path, 'src', entry.key))
              ..createSync(recursive: true));
      File(p.join(dir.path, 'google-services.json')).writeAsStringSync(
        jsonEncode({
          'project_info': {'project_id': entry.value},
        }),
      );
    }
    if (envProperties != null) {
      File(
        p.join(root.path, 'android', 'env.properties'),
      ).writeAsStringSync(envProperties);
      File(
        p.join(root.path, 'android', 'release.jks'),
      ).writeAsStringSync('not a real keystore');
    }
    return root;
  }

  group('Scanner', () {
    test('phân loại key bắt buộc / tuỳ chọn theo cách code đọc', () {
      final sink = _Sink();
      scanDotenvUsage('''
        await dotenv.load(fileName: '.env.production');
        final a = dotenv.get('REQUIRED_GET');
        final b = dotenv.get('WITH_FALLBACK', fallback: '');
        final c = dotenv.env['NULLABLE'];
        final d = dotenv.env[ 'FORCED' ]!;
        final e = dotenv.maybeGet(
          'MAYBE',
        );
      ''', sink);
      expect(sink.files, {'.env.production'});
      expect(sink.required, {'REQUIRED_GET', 'FORCED'});
      expect(sink.optional, {'WITH_FALLBACK', 'NULLABLE', 'MAYBE'});
    });

    test('firebase_options chỉ lấy khối android', () {
      expect(
        parseFirebaseOptionsProjectIds('''
          static const FirebaseOptions web = FirebaseOptions(projectId: 'web-only');
          static const FirebaseOptions android = FirebaseOptions(
            apiKey: 'x',
            projectId: 'amc-dev',
          );
        '''),
        ['amc-dev'],
      );
    });

    test('suy ra contract từ project, chỉ đọc tên key của .env', () async {
      final root = project(
        dart:
            "void main() async { await dotenv.load(fileName: '.env'); "
            "dotenv.get('API_URL'); dotenv.env['MIN_APP_VERSION']; }",
        envExample: 'API_URL=\nAPI_KEY=\n',
        env: 'API_URL=https://api.amc.vn\nLOCAL_ONLY=secret\n',
        googleServices: {'dev': 'amc-dev', 'production': 'amc-prod'},
        firebaseOptions:
            "static const FirebaseOptions android = FirebaseOptions(projectId: 'amc-dev');",
      );
      final contract = await const ProjectContractScanner().scan(root.path);
      expect(contract.projectLinked, isTrue);
      expect(contract.envFileNames, ['.env']);
      expect(contract.requiredKeys, ['API_URL']);
      expect(contract.optionalKeys, isNot(contains('API_KEY')));
      expect(contract.optionalKeys, ['LOCAL_ONLY']);
      expect(contract.keySources['LOCAL_ONLY'], '.env của project');
      expect(
        contract.envValueFingerprints['LOCAL_ONLY'],
        envValueFingerprint('secret'),
      );
      expect(contract.expectedFirebaseProjectId, 'amc-prod');
      expect(
        contract.firebaseCandidates.keys,
        containsAll(['amc-dev', 'amc-prod']),
      );
      // Raw values never enter the contract's diagnostics.
      expect(contract.sources.join(), isNot(contains('secret')));
    });
  });

  group('Pipeline', () {
    test('AAB tổng hợp: đọc, kiểm, lưu, so với lần trước', () async {
      final root = project(
        dart:
            "void main() async { await dotenv.load(fileName: '.env'); "
            "dotenv.get('API_URL'); dotenv.get('API_KEY'); }",
        googleServices: {'production': 'amc-prod'},
        firebaseOptions:
            "static const FirebaseOptions android = FirebaseOptions(projectId: 'amc-dev');",
        envProperties:
            'ANDROID_JKS_PATH=release.jks\nKEY_ALIAS=upload\n'
            'STORE_PASSWORD=hunter2\n',
      );
      final runner = _FakeRunner(uploadSignatureSha256);
      final service = BundleCheckService(
        store: BundleCheckStore(root: Directory(p.join(temp.path, 'store'))),
        projects: _Projects([
          BundleProjectCandidate(
            name: 'demo_app',
            path: root.path,
            applicationId: 'vn.amc.demo',
            storeVersionCode: 11,
          ),
        ]),
        runner: runner,
        tools: const JavaTools(java: 'java', keytool: 'keytool'),
        inspectInBackground: false,
      );

      final first = writeAab(
        p.join(temp.path, 'app-v12.aab'),
        signatureBlock: uploadSignatureBlock,
        envFiles: const {'.env': 'API_URL=https://api.amc.vn\n'},
        libAppStrings: 'noise amc-dev noise',
        alignment: 0x1000,
      );
      final run = await service.check(first.path);
      final report = run.report;
      CheckResult result(String id) =>
          report.results.singleWhere((r) => r.id == id);

      expect(report.packageName, 'vn.amc.demo');
      expect(report.projectName, 'demo_app');
      expect(result('B04').status, CheckStatus.pass);
      expect(result('B04').detail, contains('android/env.properties'));
      expect(result('B08').status, CheckStatus.fail);
      expect(
        result('E01').items,
        contains(
          'API_KEY — thiếu (theo code bắt buộc (dotenv.get / env[...]!))',
        ),
      );
      expect(result('E03').status, CheckStatus.fail);
      expect(result('E03').detail, contains('amc-dev'));

      // The keystore password travels by environment, never by argument.
      final keytool = runner.calls.single;
      expect(keytool.$2.join(' '), isNot(contains('hunter2')));
      expect(keytool.$3!.values, contains('hunter2'));

      // Saved to history, without any env value.
      final saved = await service.store.history();
      expect(saved.single.id, report.id);
      final json = File(
        p.join(
          (await service.store.jobDirectory(report.id)).path,
          'report.json',
        ),
      ).readAsStringSync();
      expect(json, isNot(contains('api.amc.vn/')));
      expect(json, isNot(contains('hunter2')));

      // A second build of the same package is compared with the first.
      final second = writeAab(
        p.join(temp.path, 'app-v13.aab'),
        manifest: manifestBytes(
          versionCode: 13,
          versionName: '1.3.0',
          permissions: const [
            'android.permission.INTERNET',
            'android.permission.RECORD_AUDIO',
          ],
        ),
        signatureBlock: uploadSignatureBlock,
      );
      final next = (await service.check(second.path)).report;
      final permissions = next.results.singleWhere((r) => r.id == 'B10');
      expect(permissions.status, CheckStatus.warn);
      expect(permissions.detail, contains('1.2.0+12'));
    });

    test(
      'ghim chữ ký rồi đổi key → B04 lỗi; không gắn project vẫn áp dụng',
      () async {
        final service = BundleCheckService(
          store: BundleCheckStore(root: Directory(p.join(temp.path, 'store'))),
          projects: _Projects(const []),
          runner: _FakeRunner(''),
          tools: const JavaTools(java: 'java', keytool: 'keytool'),
          inspectInBackground: false,
        );
        final upload = writeAab(
          p.join(temp.path, 'upload.aab'),
          signatureBlock: uploadSignatureBlock,
        );
        final first = await service.check(upload.path);
        expect(first.project, isNull);
        await service.pinSigner(first.report);

        final debug = writeAab(
          p.join(temp.path, 'debug.aab'),
          signatureBlock: debugSignatureBlock,
          signatureName: 'META-INF/ANDROIDD.EC',
        );
        final second = await service.check(debug.path);
        final b04 = second.report.results.singleWhere((r) => r.id == 'B04');
        expect(b04.status, CheckStatus.fail);
      },
    );

    test('file không phải AAB báo lỗi dễ hiểu', () async {
      final service = BundleCheckService(
        store: BundleCheckStore(root: Directory(p.join(temp.path, 'store'))),
        projects: _Projects(const []),
        runner: _FakeRunner(''),
        tools: const JavaTools(java: 'java', keytool: 'keytool'),
        inspectInBackground: false,
      );
      final notAab = File(p.join(temp.path, 'x.aab'))
        ..writeAsStringSync('nope');
      await expectLater(
        service.check(notAab.path),
        throwsA(isA<BundleInspectionException>()),
      );
    });

    test('lịch sử chỉ giữ số job cấu hình', () async {
      final store = BundleCheckStore(
        root: Directory(p.join(temp.path, 'store')),
        keepJobs: 2,
      );
      for (var i = 0; i < 3; i++) {
        await store.save(
          BundleCheckReport(
            id: 'job$i',
            createdAt: DateTime(2026, 9, 1 + i),
            sourcePath: 'a.aab',
            fileName: 'a.aab',
            fileSize: 1,
            sha256: 's$i',
            packageName: 'p',
            versionName: '1',
            versionCode: i,
            minSdk: 1,
            targetSdk: 1,
            permissions: const [],
            abis: const [],
            estimatedArm64DownloadBytes: 0,
            results: const [],
          ),
        );
      }
      expect((await store.history()).map((r) => r.id), ['job2', 'job1']);
    });
  });

  // Runs the whole pipeline on a real AAB when one is supplied:
  //   AAB_CHECK_FIXTURE=D:\builds\app-release.aab flutter test test/bundle_check_service_test.dart
  final fixture = Platform.environment['AAB_CHECK_FIXTURE'];
  final fixtureProject = Platform.environment['AAB_CHECK_PROJECT'];
  final fixtureBundletool = Platform.environment['AAB_CHECK_BUNDLETOOL'];
  test(
    'AAB thật từ AAB_CHECK_FIXTURE',
    () async {
      final service = BundleCheckService(
        store: BundleCheckStore(root: Directory(p.join(temp.path, 'store'))),
        projects: _Projects(const []),
        inspectInBackground: false,
      );
      final report = (await service.check(
        fixture!,
        project: fixtureProject == null
            ? null
            : BundleProjectCandidate(
                name: 'Fixture project',
                path: fixtureProject,
              ),
      )).report;
      if (fixtureProject != null) {
        final key = readProjectKeystore(fixtureProject);
        expect(key, isNotNull);
        expect(File(key!.path).existsSync(), isTrue);
        // ignore: avoid_print
        print('Resolved keystore: ${key.path}');
        if (fixtureBundletool != null) {
          final apk =
              await BundletoolClient(
                runner: const IoBundleProcessRunner(),
                tools: JavaTools.locate(),
                jar: File(fixtureBundletool),
              ).buildUniversalApk(
                bundlePath: fixture,
                outputDirectory: Directory(p.join(temp.path, 'signed-apk')),
                apkFileName: 'fixture.apk',
                keystore: key,
              );
          expect(await apk.length(), greaterThan(0));
          // ignore: avoid_print
          print('Signed universal APK built successfully.');
        }
      }
      for (final result in report.results) {
        // ignore: avoid_print
        print(
          '${result.id} ${result.status.name} ${result.title}: ${result.detail}',
        );
      }
      expect(report.results, isNotEmpty);
    },
    skip: fixture == null
        ? 'Đặt AAB_CHECK_FIXTURE để chạy trên AAB thật.'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

class _Sink implements DotenvUsageSink {
  final required = <String>{};
  final optional = <String>{};
  final files = <String>{};

  @override
  void requiredKey(String key) => required.add(key);

  @override
  void optionalKey(String key) => optional.add(key);

  @override
  void envFile(String name) => files.add(name);
}
