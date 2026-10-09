import '../../models/bundle_check_models.dart';
import '../env_file.dart';

/// E00–E06: does the bundle carry the configuration the app needs, pointing at
/// the right place?
///
/// No env value ever leaves here unmasked: every one that reaches a result
/// goes through [maskValue] first.
List<CheckResult> runEnvChecks(BundleFacts facts, EnvContract contract) {
  final loaded = _loadedEnv(facts, contract);
  return [
    if (facts.envFiles.isNotEmpty) _preview(facts),
    _envKeys(facts, contract, loaded),
    _environment(facts, contract, loaded),
    _firebase(facts, contract),
    _metaData(facts),
    _requiredStrings(facts, contract),
    _secrets(facts),
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
    group: CheckGroup.env,
    status: status,
    title: title,
    detail: detail,
    hint: hint,
    items: items,
  );
}

/// Env files the app loads: what the project's code names when a project is
/// linked, nothing assumed otherwise.
List<String> _expectedFiles(EnvContract contract) {
  return contract.projectLinked ? contract.envFileNames : const [];
}

/// The values the app actually loads: from the files the code names, or from
/// every env file when that is unknown.
Map<String, String> _loadedEnv(BundleFacts facts, EnvContract contract) {
  final expected = _expectedFiles(contract).toSet();
  final values = <String, String>{};
  for (final file in facts.envFiles) {
    if (expected.isEmpty || expected.contains(file.assetPath)) {
      values.addAll(file.values);
    }
  }
  return values;
}

CheckResult _preview(BundleFacts facts) {
  return _result(
    'E00',
    CheckStatus.info,
    'Env đóng gói trong bundle',
    '${facts.envFiles.length} file: '
        '${facts.envFiles.map((f) => f.assetPath).join(', ')}. Giá trị đã được che.',
    items: [
      for (final file in facts.envFiles)
        for (final entry in file.values.entries)
          '${facts.envFiles.length > 1 ? '${file.assetPath} · ' : ''}'
              '${entry.key} = ${maskValue(entry.value)}',
    ],
  );
}

CheckResult _envKeys(
  BundleFacts facts,
  EnvContract contract,
  Map<String, String> loaded,
) {
  const title = 'File .env và các key';
  final bundledDotenv =
      facts.flutterPackages?.contains('flutter_dotenv') ?? false;
  final expectedFiles = _expectedFiles(contract);

  if (facts.envFiles.isEmpty && expectedFiles.isEmpty) {
    if (!contract.projectLinked && bundledDotenv) {
      return _result(
        'E01',
        CheckStatus.warn,
        title,
        'App có flutter_dotenv nhưng bundle không có file .env nào. Nếu code '
            'gọi dotenv.load() thì app sẽ lỗi ngay khi mở.',
        hint: 'Gắn project để biết code có nạp .env hay không.',
      );
    }
    return _result(
      'E01',
      CheckStatus.skip,
      title,
      contract.usesDotenv
          ? 'Project khai flutter_dotenv nhưng code không gọi dotenv.load(), '
                'bundle cũng không có .env.'
          : 'App không dùng flutter_dotenv và bundle không có file .env.',
    );
  }

  final present = {for (final file in facts.envFiles) file.assetPath};
  final missingFiles = [
    for (final name in expectedFiles)
      if (!present.contains(name)) name,
  ];
  if (missingFiles.isNotEmpty) {
    return _result(
      'E01',
      CheckStatus.fail,
      title,
      'Code gọi dotenv.load() với ${missingFiles.join(', ')} nhưng bundle '
          'không có — app sẽ lỗi ngay khi mở.',
      hint: 'Khai file đó trong phần flutter > assets của pubspec.yaml.',
      items: [for (final name in missingFiles) 'Thiếu flutter_assets/$name'],
    );
  }

  String why(String key) {
    final source = contract.keySources[key];
    return source == null ? '' : ' (theo $source)';
  }

  final failures = <String>[];
  final warnings = <String>[];
  for (final key in contract.requiredKeys) {
    final value = loaded[key];
    if (value == null) {
      failures.add('$key — thiếu${why(key)}');
    } else if (value.trim().isEmpty) {
      failures.add('$key — rỗng${why(key)}');
    } else if (isPlaceholderValue(value)) {
      failures.add('$key — còn giá trị mẫu (${maskValue(value)})');
    }
  }
  for (final key in contract.optionalKeys) {
    if (!loaded.containsKey(key)) warnings.add('$key — thiếu${why(key)}');
  }
  // Keys nobody declared can still be empty or left at a sample value.
  final declared = {...contract.requiredKeys, ...contract.optionalKeys};
  for (final entry in loaded.entries) {
    if (contract.requiredKeys.contains(entry.key)) continue;
    if (entry.value.trim().isEmpty) {
      warnings.add('${entry.key} — rỗng');
    } else if (isPlaceholderValue(entry.value)) {
      warnings.add('${entry.key} — còn giá trị mẫu');
    }
  }

  final checked = !contract.projectLinked
      ? '${loaded.length} key; chưa gắn project nên không biết key nào bắt buộc'
      : declared.isEmpty
      ? '${loaded.length} key; code không đọc key nào bằng tên cố định'
      : '${loaded.length} key trong bundle, ${contract.requiredKeys.length} '
            'bắt buộc và ${contract.optionalKeys.length} nên có theo project';
  if (failures.isNotEmpty) {
    return _result(
      'E01',
      CheckStatus.fail,
      title,
      '${failures.length} key bắt buộc có vấn đề ($checked).',
      hint:
          'Sửa .env của máy build rồi build lại — .env được đóng gói nguyên văn.',
      items: [...failures, ...warnings],
    );
  }
  if (warnings.isNotEmpty) {
    return _result(
      'E01',
      CheckStatus.warn,
      title,
      '${warnings.length} key cần xem lại ($checked).',
      hint: warnings.any((w) => w.contains('.env của project'))
          ? 'Key có trong .env hiện tại của project mà bundle không có: bundle '
                'có thể được build từ .env cũ.'
          : '',
      items: warnings,
    );
  }
  return _result('E01', CheckStatus.pass, title, 'Đủ key ($checked).');
}

const _nonProdTokens = {
  'dev',
  'develop',
  'development',
  'staging',
  'stg',
  'uat',
  'test',
  'testing',
  'sandbox',
  'qa',
};

bool _keyMeansNonProd(String key) {
  return RegExp(
    r'(^|_)(DEV|DEVELOP|DEVELOPMENT|TEST|TESTING|STAGING|STG|UAT|QA|SANDBOX|LOCAL|DEBUG)(_|$)',
    caseSensitive: false,
  ).hasMatch(key);
}

String? _nonProdHost(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) return null;
  // A public suffix such as .dev does not identify a deployment environment.
  final labels = uri.host.toLowerCase().split('.');
  final tokens = labels.take(labels.length - 1).expand((s) => s.split('-'));
  return tokens.any(_nonProdTokens.contains) ? uri.host : null;
}

CheckResult _environment(
  BundleFacts facts,
  EnvContract contract,
  Map<String, String> loaded,
) {
  const title = 'Trỏ đúng môi trường';
  final failures = <String>[];
  final warnings = <String>[];

  for (final entry in loaded.entries) {
    if (_keyMeansNonProd(entry.key)) continue;
    final expected = contract.envValueFingerprints[entry.key];
    if (expected != null) {
      if (envValueFingerprint(entry.value) != expected) {
        warnings.add(
          '${entry.key} — khác giá trị trong .env hiện tại của project',
        );
      }
      // The actual project env is the baseline. Explicit forbidden strings
      // below still apply, even when the project itself contains them.
      continue;
    }
    if (pointsAtLocalMachine(entry.value)) {
      failures.add('${entry.key} → ${maskValue(entry.value)} (máy dev)');
      continue;
    }
    final host = _nonProdHost(entry.value);
    if (host != null) warnings.add('${entry.key} → $host');
  }

  for (final forbidden in contract.forbiddenStrings) {
    final inEnv = loaded.entries
        .where((entry) => entry.value.contains(forbidden))
        .map((entry) => entry.key);
    for (final key in inEnv) {
      failures.add('$key chứa chuỗi cấm "$forbidden"');
    }
    if (facts.nativeStringHits[forbidden] == true) {
      failures.add('libapp.so chứa chuỗi cấm "$forbidden"');
    }
  }

  if (loaded.isEmpty && contract.forbiddenStrings.isEmpty) {
    return _result(
      'E02',
      CheckStatus.skip,
      title,
      'Không có env trong bundle và chưa khai chuỗi cấm nào.',
    );
  }
  if (failures.isNotEmpty) {
    return _result(
      'E02',
      CheckStatus.fail,
      title,
      'Bundle trỏ tới máy dev hoặc chứa chuỗi cấm.',
      hint: 'Build lại với .env / cấu hình production.',
      items: [...failures, ...warnings],
    );
  }
  if (warnings.isNotEmpty) {
    return _result(
      'E02',
      CheckStatus.warn,
      title,
      contract.envValueFingerprints.isNotEmpty
          ? 'Có giá trị khác .env hiện tại hoặc host thử chưa có trong cấu hình project.'
          : 'Có host trông như môi trường thử. Nếu đúng là production thì bỏ qua.',
      items: warnings,
    );
  }
  return _result(
    'E02',
    CheckStatus.pass,
    title,
    contract.envValueFingerprints.isNotEmpty
        ? 'Các key có trong .env hiện tại đều khớp giá trị; không thấy chuỗi cấm '
              'hay host thử ngoài cấu hình project.'
        : 'Không thấy host máy dev, host thử hay chuỗi cấm.',
  );
}

CheckResult _firebase(BundleFacts facts, EnvContract contract) {
  const title = 'Firebase project';
  final resourceProject = facts.stringResources['project_id'];
  final bundledFirebase =
      facts.stringResources.containsKey('google_app_id') ||
      (facts.flutterPackages?.contains('firebase_core') ??
          contract.usesFirebase);
  if (!bundledFirebase) {
    // NOTICES lists every package compiled in; without firebase_core there
    // is no Firebase to point anywhere, whatever the project folder holds.
    final known = facts.flutterPackages != null;
    return _result(
      'E03',
      CheckStatus.skip,
      title,
      contract.usesFirebase && known
          ? 'Project có cấu hình Firebase nhưng bản build này không có '
                'firebase_core.'
          : 'App không dùng Firebase.',
    );
  }

  final found = <String, String>{
    for (final id in contract.firebaseCandidates.keys)
      if (facts.nativeStringHits[id] == true) id: 'libapp.so',
    ?resourceProject: 'resources (google-services)',
  };
  final expected = contract.expectedFirebaseProjectId;
  if (expected != null && facts.nativeStringHits[expected] == true) {
    found.putIfAbsent(expected, () => 'libapp.so');
  }
  String describe(String id) {
    final source = contract.firebaseCandidates[id];
    return source == null ? id : '$id ($source)';
  }

  final foundLines = [
    for (final entry in found.entries)
      '${describe(entry.key)} — thấy trong ${entry.value}',
  ];

  if (expected == null) {
    if (found.isEmpty) {
      return _result(
        'E03',
        contract.firebaseCandidates.isEmpty
            ? CheckStatus.skip
            : CheckStatus.warn,
        title,
        contract.firebaseCandidates.isEmpty
            ? 'Chưa gắn project nên không biết project Firebase nào là đúng.'
            : 'Không thấy project Firebase nào của dự án trong bundle.',
      );
    }
    return _result(
      'E03',
      found.length > 1 ? CheckStatus.warn : CheckStatus.info,
      title,
      found.length > 1
          ? 'Bundle mang nhiều project Firebase; chưa khai project nào là đúng.'
          : 'Bundle dùng ${found.keys.single}. Khai project mong đợi trong '
                'contract để kiểm chặt hơn.',
      items: foundLines,
    );
  }

  final others = found.keys.where((id) => id != expected).toList();
  if (!found.containsKey(expected)) {
    return _result(
      'E03',
      others.isEmpty ? CheckStatus.warn : CheckStatus.fail,
      title,
      others.isEmpty
          ? 'Không thấy $expected trong bundle, cũng không thấy project nào khác.'
          : 'Bundle dùng ${others.join(', ')} thay vì $expected.',
      hint: others.isEmpty
          ? ''
          : 'Kiểm firebase_options.dart và google-services.json của flavor '
                'đang build.',
      items: [...foundLines, 'Mong đợi: ${describe(expected)}'],
    );
  }
  if (others.isNotEmpty) {
    return _result(
      'E03',
      CheckStatus.warn,
      title,
      'Có $expected nhưng cũng có ${others.join(', ')}.',
      items: foundLines,
    );
  }
  return _result('E03', CheckStatus.pass, title, 'Dùng ${describe(expected)}.');
}

CheckResult _metaData(BundleFacts facts) {
  const title = 'Meta-data trong manifest';
  final problems = <String>[];
  final keys = <String>[];
  for (final meta in facts.manifest.metaData) {
    final reference = meta.referenceName;
    if (reference != null && !reference.startsWith('string/')) continue;
    final value = reference == null
        ? meta.value
        : facts.stringResources[reference.substring('string/'.length)] ?? '';
    if (value.trim().isEmpty) {
      problems.add('${meta.name} — rỗng');
    } else if (value.contains(r'${')) {
      problems.add(
        '${meta.name} — placeholder chưa thay (${maskValue(value)})',
      );
    } else if (RegExp(
      r'key|token|app_?id|client',
      caseSensitive: false,
    ).hasMatch(meta.name)) {
      keys.add('${meta.name} = ${maskValue(value)}');
    }
  }
  if (problems.isNotEmpty) {
    return _result(
      'E04',
      CheckStatus.fail,
      title,
      '${problems.length} meta-data không có giá trị thật.',
      hint:
          'Thường do manifestPlaceholders hoặc biến trong local.properties chưa đặt trên máy build.',
      items: [...problems, ...keys],
    );
  }
  return _result(
    'E04',
    CheckStatus.pass,
    title,
    '${facts.manifest.metaData.length} meta-data đều có giá trị.',
    items: keys,
  );
}

CheckResult _requiredStrings(BundleFacts facts, EnvContract contract) {
  const title = 'Chuỗi bắt buộc trong code Dart';
  if (contract.requiredStrings.isEmpty) {
    return _result(
      'E05',
      CheckStatus.skip,
      title,
      'Chưa khai chuỗi bắt buộc. Thêm host API production vào contract để '
          'kiểm giá trị --dart-define / firebase_options đã compile vào app.',
    );
  }
  if (facts.libAppAbis.isEmpty) {
    return _result(
      'E05',
      CheckStatus.skip,
      title,
      'Không có libapp.so để tìm.',
    );
  }
  final missing = [
    for (final needle in contract.requiredStrings)
      if (facts.nativeStringHits[needle] != true) needle,
  ];
  if (missing.isNotEmpty) {
    return _result(
      'E05',
      CheckStatus.warn,
      title,
      'Không thấy ${missing.length}/${contract.requiredStrings.length} chuỗi '
          'trong libapp.so. Kiểm bằng cách tìm chuỗi nên có thể sót nếu giá trị bị '
          'mã hoá (vd envied obfuscate).',
      items: missing,
    );
  }
  return _result(
    'E05',
    CheckStatus.pass,
    title,
    'Thấy đủ ${contract.requiredStrings.length} chuỗi trong libapp.so.',
  );
}

CheckResult _secrets(BundleFacts facts) {
  const title = 'Lộ bí mật trong bundle';
  final items = <String>[
    for (final file in facts.envFiles)
      for (final entry in file.values.entries)
        if (looksLikeSecretKeyName(entry.key) && entry.value.trim().isNotEmpty)
          '${entry.key} (${file.assetPath})',
    for (final asset in facts.secretAssets)
      '$asset — private key / service account',
  ];
  if (items.isEmpty) {
    return _result(
      'E06',
      CheckStatus.pass,
      title,
      'Không thấy key bí mật hay file private key trong assets.',
    );
  }
  return _result(
    'E06',
    CheckStatus.warn,
    title,
    '${items.length} bí mật nằm trong assets — ai có file APK cũng đọc được.',
    hint:
        'Chuyển các giá trị này về server, hoặc chấp nhận rủi ro một cách có '
        'chủ ý.',
    items: items,
  );
}
