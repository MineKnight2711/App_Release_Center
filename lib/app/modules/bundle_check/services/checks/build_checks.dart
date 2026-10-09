import '../../models/bundle_check_models.dart';
import '../android_manifest.dart';
import '../signing_certificate.dart';

/// Play's target-API requirement for updates, by the date it took effect.
///
/// Kept as data, not a formula: Google announces each step, and the next one
/// belongs here only once it is announced.
final playTargetSdkSteps = <(DateTime, int)>[
  (DateTime(2023, 8, 31), 33),
  (DateTime(2024, 8, 31), 34),
  (DateTime(2025, 8, 31), 35),
  (DateTime(2026, 8, 31), 36),
];

/// The target API an update must reach on [now], with the date it started.
(int, DateTime) playTargetSdkRequirement(DateTime now) {
  var current = playTargetSdkSteps.first;
  for (final step in playTargetSdkSteps) {
    if (!now.isBefore(step.$1)) current = step;
  }
  return (current.$2, current.$1);
}

const sixteenKb = 16 * 1024;

/// B01–B13: is this the bundle that should go to Play?
List<CheckResult> runBuildChecks(
  BundleFacts facts, {
  BundleProjectContext? project,
  SignerExpectation? signer,
  BundleCheckReport? previous,
  required DateTime now,
  bool? bundletoolValid,
  String bundletoolMessage = '',
}) {
  return [
    _validity(facts, bundletoolValid, bundletoolMessage),
    _package(facts, project),
    _version(facts, project),
    _signature(facts, signer, now),
    _debuggable(facts),
    _flutterRelease(facts),
    _abis(facts),
    _pageSize(facts),
    _targetSdk(facts, now),
    _permissions(facts, previous),
    _size(facts, previous),
    _mapping(facts),
    _cleartext(facts),
  ];
}

CheckResult _result(
  String id,
  CheckStatus status,
  String title,
  String detail, {
  String hint = '',
  List<String> items = const [],
}) {
  return CheckResult(
    id: id,
    group: CheckGroup.build,
    status: status,
    title: title,
    detail: detail,
    hint: hint,
    items: items,
  );
}

CheckResult _validity(BundleFacts facts, bool? valid, String message) {
  const title = 'File AAB hợp lệ';
  if (!facts.hasBundleConfig) {
    return _result(
      'B01',
      CheckStatus.fail,
      title,
      'Thiếu BundleConfig.pb — file không phải AAB do Gradle/bundletool tạo.',
    );
  }
  if (valid == false) {
    return _result(
      'B01',
      CheckStatus.fail,
      title,
      'bundletool validate báo lỗi.',
      items: [if (message.isNotEmpty) message],
    );
  }
  final modules = facts.modules.join(', ');
  return _result(
    'B01',
    CheckStatus.pass,
    title,
    '${facts.modules.length} module ($modules), ${facts.entryCount} mục, '
        '${formatBytes(facts.fileSize)}. '
        '${valid == true ? 'bundletool validate: OK.' : 'Chưa chạy bundletool validate (chưa có bundletool).'}',
  );
}

CheckResult _package(BundleFacts facts, BundleProjectContext? project) {
  const title = 'Đúng package';
  final package = facts.manifest.packageName;
  if (project == null) {
    return _result(
      'B02',
      CheckStatus.skip,
      title,
      'Package $package. Chưa gắn project nên không có applicationId để so.',
    );
  }
  final expected = project.applicationId;
  if (expected == null || expected.isEmpty) {
    return _result(
      'B02',
      CheckStatus.skip,
      title,
      'Không đọc được applicationId trong android/app/build.gradle của '
          '${project.name}.',
    );
  }
  if (package == expected) {
    return _result(
      'B02',
      CheckStatus.pass,
      title,
      '$package khớp ${project.name}.',
    );
  }
  if (package.startsWith('$expected.')) {
    return _result(
      'B02',
      CheckStatus.pass,
      title,
      '$package = $expected + hậu tố flavor.',
    );
  }
  return _result(
    'B02',
    CheckStatus.fail,
    title,
    'Bundle là $package, project ${project.name} là $expected.',
    hint: 'Nhầm file, hoặc build sai flavor.',
  );
}

CheckResult _version(BundleFacts facts, BundleProjectContext? project) {
  const title = 'Version';
  final manifest = facts.manifest;
  final code = manifest.versionCode;
  final label = '${manifest.versionName ?? '?'}+${code ?? '?'}';
  if (code == null) {
    return _result(
      'B03',
      CheckStatus.fail,
      title,
      'Manifest không có versionCode.',
    );
  }
  if (project == null) {
    return _result(
      'B03',
      CheckStatus.info,
      title,
      '$label. Chưa gắn project nên không so với pubspec hay CH Play.',
    );
  }

  var status = CheckStatus.pass;
  final lines = <String>['Bundle: $label.'];
  var hint = '';

  final store = project.storeVersionCode;
  if (store == null) {
    lines.add('Chưa có versionCode CH Play trong phiên này.');
  } else if (code <= store) {
    status = CheckStatus.fail;
    lines.add('CH Play đã có $store — Play sẽ từ chối versionCode $code.');
    hint = 'Tăng versionCode trong pubspec.yaml rồi build lại.';
  } else {
    lines.add('Lớn hơn bản trên CH Play ($store).');
  }

  final pubspecCode = project.pubspecVersionCode;
  if (pubspecCode != null &&
      (pubspecCode != code ||
          project.pubspecVersionName != manifest.versionName)) {
    if (status == CheckStatus.pass) status = CheckStatus.warn;
    lines.add(
      'pubspec đang là ${project.pubspecVersionName}+$pubspecCode — '
      'bundle build từ version khác.',
    );
  }
  return _result('B03', status, title, lines.join(' '), hint: hint);
}

CheckResult _signature(
  BundleFacts facts,
  SignerExpectation? expectation,
  DateTime now,
) {
  const title = 'Chữ ký';
  final signer = facts.signer;
  if (facts.signatureError != null) {
    return _result('B04', CheckStatus.fail, title, facts.signatureError!);
  }
  if (signer == null) {
    return _result(
      'B04',
      CheckStatus.fail,
      title,
      'AAB chưa ký. Play không nhận bundle chưa ký.',
    );
  }
  final who = '${signer.subjectLine} · SHA-256 ${_short(signer.sha256)}';
  if (signer.isAndroidDebug) {
    return _result(
      'B04',
      CheckStatus.fail,
      title,
      'Ký bằng debug key ($who).',
      hint:
          'Gradle rơi về debug signing khi android/env.properties hoặc '
          'key.properties thiếu keystore. Kiểm ANDROID_JKS_PATH, KEY_ALIAS, '
          'STORE_PASSWORD rồi build lại.',
    );
  }
  if (signer.notAfter != null && signer.notAfter!.isBefore(now)) {
    return _result(
      'B04',
      CheckStatus.fail,
      title,
      'Chứng chỉ ký đã hết hạn từ ${_date(signer.notAfter!)} ($who).',
    );
  }

  final rawExpected = expectation?.sha256;
  final expected = rawExpected == null
      ? null
      : SigningCertificate.normalizeFingerprint(rawExpected);
  if (expected != null && expected.isNotEmpty) {
    if (expected == signer.sha256) {
      return _result(
        'B04',
        CheckStatus.pass,
        title,
        'Khớp upload key (${expectation!.source}). $who.',
      );
    }
    return _result(
      'B04',
      CheckStatus.fail,
      title,
      'Khác upload key. Bundle: $who. Mong đợi: SHA-256 ${_short(expected)} '
          '(${expectation!.source}).',
      hint: 'Play sẽ từ chối nếu đây không phải upload key đã đăng ký.',
    );
  }

  final lookup = expectation?.lookupError;
  return _result(
    'B04',
    CheckStatus.pass,
    title,
    'Không phải debug key. $who.'
        '${lookup == null ? '' : ' Không đọc được keystore để so: $lookup'}',
    hint: 'Chưa có fingerprint chuẩn — bấm "Ghim chữ ký" nếu đây là đúng key.',
  );
}

CheckResult _debuggable(BundleFacts facts) {
  const title = 'Không phải bản debug';
  final flags = [
    if (facts.manifest.debuggable) 'android:debuggable="true"',
    if (facts.manifest.testOnly) 'android:testOnly="true"',
  ];
  if (flags.isNotEmpty) {
    return _result(
      'B05',
      CheckStatus.fail,
      title,
      'Manifest có ${flags.join(' và ')}. Play từ chối bundle như vậy.',
    );
  }
  return _result(
    'B05',
    CheckStatus.pass,
    title,
    'Không debuggable, không testOnly.',
  );
}

CheckResult _flutterRelease(BundleFacts facts) {
  const title = 'Flutter build release';
  if (!facts.isFlutter) {
    return _result('B06', CheckStatus.skip, title, 'Không phải app Flutter.');
  }
  if (facts.hasKernelBlob) {
    return _result(
      'B06',
      CheckStatus.fail,
      title,
      'Có flutter_assets/kernel_blob.bin — đây là build debug (JIT).',
      hint: 'Build bằng flutter build appbundle --release.',
    );
  }
  final flutterAbis = {
    for (final library in facts.nativeLibraries)
      if (library.fileName == 'libflutter.so') library.abi,
  };
  final missing = [
    for (final abi in flutterAbis)
      if (!facts.libAppAbis.contains(abi)) '$abi thiếu libapp.so',
    for (final abi in facts.libAppAbis)
      if (!flutterAbis.contains(abi)) '$abi thiếu libflutter.so',
  ];
  if (facts.libAppAbis.isEmpty || missing.isNotEmpty) {
    return _result(
      'B06',
      CheckStatus.fail,
      title,
      'Thiếu thư viện Flutter cho một số ABI — app sẽ crash trên máy đó.',
      items: facts.libAppAbis.isEmpty ? ['Không có libapp.so nào'] : missing,
    );
  }
  return _result(
    'B06',
    CheckStatus.pass,
    title,
    'AOT release cho ${(facts.libAppAbis.toList()..sort()).join(', ')}.',
  );
}

CheckResult _abis(BundleFacts facts) {
  const title = 'ABI';
  final abis = facts.abis;
  if (abis.isEmpty) {
    return _result('B07', CheckStatus.pass, title, 'Không có thư viện native.');
  }
  final sorted = abis.toList()..sort();
  final problems = [
    if (abis.contains('armeabi-v7a') && !abis.contains('arm64-v8a'))
      'Có armeabi-v7a nhưng thiếu arm64-v8a',
    if (abis.contains('x86') && !abis.contains('x86_64'))
      'Có x86 nhưng thiếu x86_64',
  ];
  if (problems.isNotEmpty) {
    return _result(
      'B07',
      CheckStatus.fail,
      title,
      'Play yêu cầu bản 64-bit cho mọi ABI 32-bit. Có: ${sorted.join(', ')}.',
      items: problems,
    );
  }
  final emulatorNote = abis.contains('x86_64')
      ? ''
      : ' Không có x86_64 nên không chạy thử được trên emulator x86_64.';
  return _result(
    'B07',
    CheckStatus.pass,
    title,
    '${sorted.join(', ')}.$emulatorNote',
  );
}

CheckResult _pageSize(BundleFacts facts) {
  const title = 'Căn trang 16 KB';
  final libraries = facts.nativeLibraries.where((l) => l.is64BitAbi).toList();
  if (libraries.isEmpty) {
    return _result(
      'B08',
      CheckStatus.pass,
      title,
      'Không có thư viện native 64-bit nào phải căn.',
    );
  }
  final misaligned = [
    for (final library in libraries)
      if (library.minLoadAlignment case final alignment?
          when alignment < sixteenKb)
        '${library.abi}/${library.fileName}: ${alignment ~/ 1024} KB',
  ];
  final unreadable = [
    for (final library in libraries)
      if (library.minLoadAlignment == null)
        '${library.abi}/${library.fileName}',
  ];
  final targetSdk = facts.manifest.targetSdk ?? 0;
  if (misaligned.isNotEmpty) {
    return _result(
      'B08',
      targetSdk >= 35 ? CheckStatus.fail : CheckStatus.warn,
      title,
      '${misaligned.length}/${libraries.length} thư viện 64-bit chưa căn 16 KB. '
          'Play bắt buộc với targetSdk ≥ 35 từ 01/11/2025.',
      hint:
          'Nâng plugin hoặc SDK chứa thư viện đó lên bản hỗ trợ 16 KB; tự build '
          'native thì dùng NDK r28+.',
      items: misaligned,
    );
  }
  if (unreadable.isNotEmpty) {
    return _result(
      'B08',
      CheckStatus.warn,
      title,
      'Không đọc được header ELF của ${unreadable.length} thư viện.',
      items: unreadable,
    );
  }
  return _result(
    'B08',
    CheckStatus.pass,
    title,
    '${libraries.length} thư viện 64-bit đều căn ≥ 16 KB.',
  );
}

CheckResult _targetSdk(BundleFacts facts, DateTime now) {
  const title = 'targetSdk';
  final target = facts.manifest.targetSdk;
  final min = facts.manifest.minSdk;
  final (required, since) = playTargetSdkRequirement(now);
  if (target == null) {
    return _result(
      'B09',
      CheckStatus.fail,
      title,
      'Manifest không có targetSdkVersion.',
    );
  }
  if (target < required) {
    final extension = required == 36 && now.isBefore(DateTime(2026, 11, 1))
        ? ' Có thể xin gia hạn trên Play Console tới 01/11/2026.'
        : '';
    return _result(
      'B09',
      CheckStatus.fail,
      title,
      'targetSdk $target, minSdk ${min ?? '?'}. Từ ${_date(since)} Play chỉ '
          'nhận bản cập nhật có targetSdk ≥ $required.$extension',
      hint: 'Nâng targetSdkVersion trong android/app/build.gradle.',
    );
  }
  return _result(
    'B09',
    CheckStatus.pass,
    title,
    'targetSdk $target (Play cần ≥ $required), minSdk ${min ?? '?'}.',
  );
}

CheckResult _permissions(BundleFacts facts, BundleCheckReport? previous) {
  const title = 'Permission';
  final current = facts.manifest.permissions.toSet();
  if (previous == null) {
    final dangerous = current.where(dangerousPermissions.contains).length;
    return _result(
      'B10',
      CheckStatus.info,
      title,
      '${current.length} permission, $dangerous cần người dùng cho phép. '
          'Lần đầu kiểm package này nên chưa có gì để so.',
      items: (current.toList()..sort()).map(_shortPermission).toList(),
    );
  }
  final before = previous.permissions.toSet();
  final added = current.difference(before).toList()..sort();
  final removed = before.difference(current).toList()..sort();
  final addedDangerous = added.where(dangerousPermissions.contains).toList();
  final since = 'so với ${previous.versionLabel}';
  if (added.isEmpty && removed.isEmpty) {
    return _result('B10', CheckStatus.pass, title, 'Không đổi $since.');
  }
  return _result(
    'B10',
    addedDangerous.isNotEmpty ? CheckStatus.warn : CheckStatus.info,
    title,
    '${added.length} thêm, ${removed.length} bớt $since.'
        '${addedDangerous.isEmpty ? '' : ' Có permission nhạy cảm mới — kiểm xem có cố ý không.'}',
    items: [
      for (final permission in added)
        '+ ${_shortPermission(permission)}'
            '${dangerousPermissions.contains(permission) ? ' (nhạy cảm)' : ''}',
      for (final permission in removed) '− ${_shortPermission(permission)}',
    ],
  );
}

CheckResult _size(BundleFacts facts, BundleCheckReport? previous) {
  const title = 'Kích thước';
  final estimate = facts.estimatedArm64DownloadBytes;
  final base =
      'File ${formatBytes(facts.fileSize)} · ước tính phần arm64 ≈ '
      '${formatBytes(estimate)}';
  if (previous == null || previous.estimatedArm64DownloadBytes <= 0) {
    return _result('B11', CheckStatus.info, title, '$base.');
  }
  final before = previous.estimatedArm64DownloadBytes;
  final growth = (estimate - before) / before;
  final percent =
      '${growth >= 0 ? '+' : ''}${(growth * 100).toStringAsFixed(1)}%';
  return _result(
    'B11',
    growth > 0.15 ? CheckStatus.warn : CheckStatus.pass,
    title,
    '$base ($percent so với ${previous.versionLabel}).',
    hint: growth > 0.15
        ? 'Tăng hơn 15% — xem có asset, font hay thư viện native nào mới vào.'
        : '',
  );
}

CheckResult _mapping(BundleFacts facts) {
  const title = 'Mapping để giải mã crash';
  final parts = [
    facts.hasR8Mapping
        ? 'Có mapping R8.'
        : 'Không có mapping R8 (R8 tắt, hoặc mapping không được đóng gói).',
    facts.hasNativeDebugSymbols
        ? 'Có debug symbol native.'
        : 'Không có debug symbol native.',
  ];
  return _result(
    'B12',
    facts.hasR8Mapping ? CheckStatus.pass : CheckStatus.info,
    title,
    parts.join(' '),
  );
}

CheckResult _cleartext(BundleFacts facts) {
  const title = 'HTTP không mã hoá';
  if (facts.manifest.usesCleartextTraffic == true) {
    return _result(
      'B13',
      CheckStatus.warn,
      title,
      'usesCleartextTraffic="true": app được gọi HTTP thường tới mọi domain.',
      hint:
          'Nếu chỉ vài domain cần HTTP, dùng networkSecurityConfig thay vì mở '
          'cho tất cả.',
    );
  }
  return _result(
    'B13',
    CheckStatus.pass,
    title,
    facts.manifest.hasNetworkSecurityConfig
        ? 'Dùng networkSecurityConfig.'
        : 'Không bật cleartext cho toàn app.',
  );
}

String _short(String fingerprint) {
  return fingerprint.length > 23
      ? '${fingerprint.substring(0, 23)}…'
      : fingerprint;
}

String _date(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

String _shortPermission(String permission) {
  return permission.startsWith('android.permission.')
      ? permission.substring('android.permission.'.length)
      : permission;
}
