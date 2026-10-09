import 'package:app_management_center/app/modules/bundle_check/models/bundle_check_models.dart';
import 'package:app_management_center/app/modules/bundle_check/services/android_manifest.dart';
import 'package:app_management_center/app/modules/bundle_check/services/checks/build_checks.dart';
import 'package:app_management_center/app/modules/bundle_check/services/checks/env_checks.dart';
import 'package:app_management_center/app/modules/bundle_check/services/env_file.dart';
import 'package:app_management_center/app/modules/bundle_check/services/signing_certificate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bundle_check_fixtures.dart';

final _now = DateTime(2026, 9, 29);

BundleFacts facts({
  int versionCode = 12,
  String versionName = '1.2.0',
  int targetSdk = 36,
  bool debuggable = false,
  bool? cleartext,
  List<String> permissions = const ['android.permission.INTERNET'],
  Map<String, String> metaData = const {},
  SigningCertificate? signer,
  bool unsigned = false,
  List<NativeLibrary>? libraries,
  bool kernelBlob = false,
  Set<String>? packages = const {'flutter_dotenv', 'firebase_core'},
  Map<String, String> env = const {'API_URL': 'https://api.amc.vn'},
  String envFile = '.env',
  Map<String, String> resources = const {},
  Map<String, bool> hits = const {},
  List<String> secretAssets = const [],
  int estimate = 30 * 1024 * 1024,
}) {
  final libs =
      libraries ??
      [
        for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64'])
          for (final name in ['libflutter.so', 'libapp.so'])
            NativeLibrary(
              path: 'base/lib/$abi/$name',
              abi: abi,
              minLoadAlignment: 0x4000,
            ),
      ];
  return BundleFacts(
    filePath: 'app.aab',
    fileSize: 60 * 1024 * 1024,
    sha256: 'abc',
    entryCount: 100,
    modules: const ['base'],
    hasBundleConfig: true,
    manifest: ManifestInfo.parse(
      manifestBytes(
        versionCode: versionCode,
        versionName: versionName,
        targetSdk: targetSdk,
        debuggable: debuggable,
        cleartext: cleartext,
        permissions: permissions,
        metaData: metaData,
      ),
    ),
    signer: unsigned
        ? null
        : signer ?? parsePkcs7SignerCertificate(uploadSignatureBlock),
    signatureError: null,
    nativeLibraries: libs,
    hasLibFlutter: libs.any((l) => l.fileName == 'libflutter.so'),
    libAppAbis: {
      for (final l in libs)
        if (l.fileName == 'libapp.so') l.abi,
    },
    hasKernelBlob: kernelBlob,
    flutterPackages: packages,
    envFiles: [
      if (env.isNotEmpty) BundledEnvFile(assetPath: envFile, values: env),
    ],
    stringResources: resources,
    secretAssets: secretAssets,
    nativeStringHits: hits,
    hasR8Mapping: true,
    hasNativeDebugSymbols: false,
    estimatedArm64DownloadBytes: estimate,
  );
}

CheckResult byId(List<CheckResult> results, String id) =>
    results.singleWhere((r) => r.id == id);

const project = BundleProjectContext(
  name: 'demo',
  path: '/work/demo',
  applicationId: 'vn.amc.demo',
  pubspecVersionName: '1.2.0',
  pubspecVersionCode: 12,
  storeVersionCode: 11,
);

void main() {
  group('Build', () {
    test('bundle chuẩn không có lỗi nào', () {
      final results = runBuildChecks(facts(), project: project, now: _now);
      expect(
        results.where((r) => r.status == CheckStatus.fail).map((r) => r.id),
        isEmpty,
      );
      expect(byId(results, 'B02').status, CheckStatus.pass);
      expect(byId(results, 'B03').status, CheckStatus.pass);
    });

    test('ký bằng debug key → B04 lỗi, kèm hướng sửa env.properties', () {
      final result = byId(
        runBuildChecks(
          facts(signer: parsePkcs7SignerCertificate(debugSignatureBlock)),
          now: _now,
        ),
        'B04',
      );
      expect(result.status, CheckStatus.fail);
      expect(result.hint, contains('env.properties'));
    });

    test('chưa ký → B04 lỗi', () {
      expect(
        byId(runBuildChecks(facts(unsigned: true), now: _now), 'B04').status,
        CheckStatus.fail,
      );
    });

    test('so fingerprint mong đợi, không phân biệt cách viết', () {
      final match = runBuildChecks(
        facts(),
        signer: SignerExpectation(
          sha256: uploadSignatureSha256.toLowerCase().replaceAll(':', ''),
          source: 'android/env.properties',
        ),
        now: _now,
      );
      expect(byId(match, 'B04').status, CheckStatus.pass);

      final mismatch = runBuildChecks(
        facts(),
        signer: const SignerExpectation(
          sha256: debugSignatureSha256,
          source: 'đã ghim trong AMC',
        ),
        now: _now,
      );
      expect(byId(mismatch, 'B04').status, CheckStatus.fail);
      expect(byId(mismatch, 'B04').detail, contains('đã ghim trong AMC'));
    });

    test('versionCode không lớn hơn CH Play → B03 lỗi', () {
      final result = byId(
        runBuildChecks(facts(versionCode: 11), project: project, now: _now),
        'B03',
      );
      expect(result.status, CheckStatus.fail);
      expect(result.detail, contains('11'));
    });

    test('lệch pubspec → B03 cảnh báo', () {
      final result = byId(
        runBuildChecks(
          facts(versionCode: 13, versionName: '1.3.0'),
          project: project,
          now: _now,
        ),
        'B03',
      );
      expect(result.status, CheckStatus.warn);
    });

    test('package khác project → B02 lỗi; có hậu tố flavor thì đạt', () {
      const other = BundleProjectContext(
        name: 'x',
        path: '/x',
        applicationId: 'vn.amc.other',
      );
      expect(
        byId(runBuildChecks(facts(), project: other, now: _now), 'B02').status,
        CheckStatus.fail,
      );
      const base = BundleProjectContext(
        name: 'x',
        path: '/x',
        applicationId: 'vn.amc',
      );
      expect(
        byId(runBuildChecks(facts(), project: base, now: _now), 'B02').status,
        CheckStatus.pass,
      );
    });

    test('debuggable → B05 lỗi; kernel_blob → B06 lỗi', () {
      final results = runBuildChecks(
        facts(debuggable: true, kernelBlob: true),
        now: _now,
      );
      expect(byId(results, 'B05').status, CheckStatus.fail);
      expect(byId(results, 'B06').status, CheckStatus.fail);
    });

    test('32-bit thiếu 64-bit → B07 lỗi', () {
      final result = byId(
        runBuildChecks(
          facts(
            libraries: const [
              NativeLibrary(
                path: 'base/lib/armeabi-v7a/libapp.so',
                abi: 'armeabi-v7a',
                minLoadAlignment: 0x1000,
              ),
            ],
          ),
          now: _now,
        ),
        'B07',
      );
      expect(result.status, CheckStatus.fail);
    });

    test('thư viện 64-bit căn 4 KB → B08 lỗi khi targetSdk ≥ 35', () {
      final libs = [
        const NativeLibrary(
          path: 'base/lib/arm64-v8a/libold.so',
          abi: 'arm64-v8a',
          minLoadAlignment: 0x1000,
        ),
        // 32-bit libraries are exempt from the 16 KB rule.
        const NativeLibrary(
          path: 'base/lib/armeabi-v7a/libold.so',
          abi: 'armeabi-v7a',
          minLoadAlignment: 0x1000,
        ),
      ];
      final fail = byId(
        runBuildChecks(facts(libraries: libs), now: _now),
        'B08',
      );
      expect(fail.status, CheckStatus.fail);
      expect(fail.items, ['arm64-v8a/libold.so: 4 KB']);
      expect(
        byId(
          runBuildChecks(facts(libraries: libs, targetSdk: 34), now: _now),
          'B08',
        ).status,
        CheckStatus.warn,
      );
    });

    test('targetSdk theo mốc Play', () {
      expect(playTargetSdkRequirement(DateTime(2026, 8, 30)).$1, 35);
      expect(playTargetSdkRequirement(DateTime(2026, 8, 31)).$1, 36);
      final result = byId(
        runBuildChecks(facts(targetSdk: 35), now: _now),
        'B09',
      );
      expect(result.status, CheckStatus.fail);
      expect(result.detail, contains('01/11/2026'));
    });

    test('permission nhạy cảm mới → B10 cảnh báo', () {
      final previous = BundleCheckReport(
        id: 'old',
        createdAt: DateTime(2026, 9, 1),
        sourcePath: 'old.aab',
        fileName: 'old.aab',
        fileSize: 1,
        sha256: 'old',
        packageName: 'vn.amc.demo',
        versionName: '1.1.0',
        versionCode: 11,
        minSdk: 24,
        targetSdk: 36,
        permissions: const ['android.permission.INTERNET'],
        abis: const [],
        estimatedArm64DownloadBytes: 20 * 1024 * 1024,
        results: const [],
      );
      final results = runBuildChecks(
        facts(
          permissions: const [
            'android.permission.INTERNET',
            'android.permission.CAMERA',
          ],
        ),
        previous: previous,
        now: _now,
      );
      expect(byId(results, 'B10').status, CheckStatus.warn);
      expect(byId(results, 'B10').items.single, contains('CAMERA'));
      // 30 MB against 20 MB is +50%.
      expect(byId(results, 'B11').status, CheckStatus.warn);
    });

    test('cleartext → B13 cảnh báo', () {
      expect(
        byId(runBuildChecks(facts(cleartext: true), now: _now), 'B13').status,
        CheckStatus.warn,
      );
    });
  });

  group('Env', () {
    test(
      'actual project env overrides host heuristics; drift stays masked',
      () {
        final baseline = EnvContract(
          projectLinked: true,
          envValueFingerprints: {
            'API_URL': envValueFingerprint('https://dev.trivita.ai'),
            'SECRET': envValueFingerprint('original-sensitive-value'),
          },
        ).withOverride(const EnvContractOverride());
        final matching = byId(
          runEnvChecks(
            facts(
              env: const {
                'API_URL': 'https://dev.trivita.ai',
                'SECRET': 'original-sensitive-value',
              },
            ),
            baseline,
          ),
          'E02',
        );
        expect(matching.status, CheckStatus.pass);
        final changed = byId(
          runEnvChecks(
            facts(
              env: const {
                'API_URL': 'https://dev.trivita.ai',
                'SECRET': 'changed-sensitive-value',
              },
            ),
            baseline,
          ),
          'E02',
        );
        expect(changed.status, CheckStatus.warn);
        expect(changed.items.single, contains('SECRET'));
        expect(changed.items.join(), isNot(contains('sensitive-value')));
      },
    );

    test('explicit forbidden strings still fail a matching project env', () {
      final result = byId(
        runEnvChecks(
          facts(env: const {'API_URL': 'https://staging.example.com'}),
          EnvContract(
            envValueFingerprints: {
              'API_URL': envValueFingerprint('https://staging.example.com'),
            },
            forbiddenStrings: const ['staging.example.com'],
          ),
        ),
        'E02',
      );
      expect(result.status, CheckStatus.fail);
    });

    test('workers.dev suffix alone is not a test environment', () {
      final result = byId(
        runEnvChecks(
          facts(
            env: const {
              'API_MONITOR_URL': 'https://flow-api.example.workers.dev',
            },
          ),
          const EnvContract(),
        ),
        'E02',
      );
      expect(result.status, CheckStatus.pass);
    });

    const linked = EnvContract(
      projectLinked: true,
      usesDotenv: true,
      envFileNames: ['.env'],
      requiredKeys: ['API_URL', 'API_KEY'],
      optionalKeys: ['MIN_APP_VERSION'],
      keySources: {'API_KEY': '.env.example'},
    );

    test('code nạp .env mà bundle không có → E01 lỗi', () {
      final result = byId(runEnvChecks(facts(env: const {}), linked), 'E01');
      expect(result.status, CheckStatus.fail);
      expect(result.items.single, contains('.env'));
    });

    test('thiếu key bắt buộc, giá trị mẫu → lỗi; thiếu key tuỳ chọn → kèm', () {
      final result = byId(
        runEnvChecks(facts(env: const {'API_URL': 'change-me'}), linked),
        'E01',
      );
      expect(result.status, CheckStatus.fail);
      expect(result.items, [
        'API_URL — còn giá trị mẫu (ch••••me)',
        'API_KEY — thiếu (theo .env.example)',
        'MIN_APP_VERSION — thiếu',
      ]);
    });

    test('project không nạp .env thì bỏ qua, không đòi file', () {
      const noLoad = EnvContract(projectLinked: true, usesDotenv: true);
      final result = byId(runEnvChecks(facts(env: const {}), noLoad), 'E01');
      expect(result.status, CheckStatus.skip);
    });

    test(
      'chưa gắn project mà có flutter_dotenv nhưng không có .env → cảnh báo',
      () {
        final result = byId(
          runEnvChecks(facts(env: const {}), const EnvContract()),
          'E01',
        );
        expect(result.status, CheckStatus.warn);
      },
    );

    test('trỏ về máy dev → E02 lỗi; key tên DEV được bỏ qua', () {
      final results = runEnvChecks(
        facts(
          env: const {
            'API_URL': 'http://10.0.2.2:8080',
            'TRIVITA_DEV_BASE_URL': 'http://localhost:1',
            'CDN': 'https://staging.amc.vn',
          },
        ),
        const EnvContract(),
      );
      final result = byId(results, 'E02');
      expect(result.status, CheckStatus.fail);
      expect(result.items.first, startsWith('API_URL'));
      expect(result.items, contains('CDN → staging.amc.vn'));
      expect(result.items.join(), isNot(contains('TRIVITA_DEV')));
    });

    test('chuỗi cấm trong libapp.so → E02 lỗi', () {
      final result = byId(
        runEnvChecks(
          facts(hits: const {'staging.amc.vn': true}),
          const EnvContract(forbiddenStrings: ['staging.amc.vn']),
        ),
        'E02',
      );
      expect(result.status, CheckStatus.fail);
    });

    test('Firebase dev nằm trong bản production → E03 lỗi', () {
      const contract = EnvContract(
        projectLinked: true,
        usesFirebase: true,
        firebaseCandidates: {
          'amc-dev': 'firebase_options.dart',
          'amc-prod': 'google-services.json (production)',
        },
        expectedFirebaseProjectId: 'amc-prod',
      );
      final wrong = byId(
        runEnvChecks(
          facts(hits: const {'amc-dev': true, 'amc-prod': false}),
          contract,
        ),
        'E03',
      );
      expect(wrong.status, CheckStatus.fail);
      expect(wrong.detail, contains('amc-dev'));

      final right = byId(
        runEnvChecks(
          facts(hits: const {'amc-dev': false, 'amc-prod': true}),
          contract,
        ),
        'E03',
      );
      expect(right.status, CheckStatus.pass);
    });

    test(
      'bundle không có firebase_core → E03 bỏ qua dù project có cấu hình',
      () {
        final result = byId(
          runEnvChecks(
            facts(packages: const {'flutter_dotenv'}),
            const EnvContract(projectLinked: true, usesFirebase: true),
          ),
          'E03',
        );
        expect(result.status, CheckStatus.skip);
        expect(result.detail, contains('firebase_core'));
      },
    );

    test('meta-data còn placeholder → E04 lỗi, giá trị bị che', () {
      final result = byId(
        runEnvChecks(
          facts(metaData: const {'com.google.android.geo.API_KEY': r'${MAPS}'}),
          const EnvContract(),
        ),
        'E04',
      );
      expect(result.status, CheckStatus.fail);
    });

    test('chuỗi bắt buộc thiếu → E05 cảnh báo', () {
      final result = byId(
        runEnvChecks(
          facts(hits: const {'api.amc.vn': false}),
          const EnvContract(requiredStrings: ['api.amc.vn']),
        ),
        'E05',
      );
      expect(result.status, CheckStatus.warn);
    });

    test('bí mật trong .env hay private key trong assets → E06 cảnh báo', () {
      final result = byId(
        runEnvChecks(
          facts(
            env: const {'CLIENT_SECRET': 's3cr3t-value'},
            secretAssets: const ['base/assets/key.pem'],
          ),
          const EnvContract(),
        ),
        'E06',
      );
      expect(result.status, CheckStatus.warn);
      expect(result.items.join('\n'), isNot(contains('s3cr3t')));
    });

    test('bản xem trước env không bao giờ lộ giá trị thật', () {
      final preview = byId(
        runEnvChecks(
          facts(env: const {'API_KEY': 'AIzaSyVerySecretValue'}),
          const EnvContract(),
        ),
        'E00',
      );
      expect(preview.items.single, 'API_KEY = AI••••ue');
    });
  });
}
