import 'package:app_management_center/app/models/resource_collection.dart';

/// What a file in a release kit is for, as its README explains it.
enum ReleaseKitFileKind {
  env,
  properties,
  playServiceAccount,
  keystore,
  appStoreKey,
  appStoreConfig,
  signingCredentials,
}

/// One file in a release kit. [path] is relative to the kit folder.
class ReleaseKitFile {
  const ReleaseKitFile(this.path, this.kind, {this.fromStore = false});

  ReleaseKitFile.finding(ResourceFinding finding)
    : this(finding.relativePath, switch (finding.kind) {
        ResourceTargetKind.envFile => ReleaseKitFileKind.env,
        ResourceTargetKind.properties => ReleaseKitFileKind.properties,
        ResourceTargetKind.fastlaneServiceAccount =>
          ReleaseKitFileKind.playServiceAccount,
        ResourceTargetKind.signingKey => ReleaseKitFileKind.keystore,
        ResourceTargetKind.appStoreKey => ReleaseKitFileKind.appStoreKey,
      });

  final String path;
  final ReleaseKitFileKind kind;

  /// Written from AMC's secure store rather than copied from the project.
  final bool fromStore;
}

/// Folder inside the kit for keys that come from AMC's secure store.
const releaseKitStoreFolder = 'amc_keys';

/// Setup guide shipped with every resource export, covering Android and iOS
/// whatever the kit holds, so the reader also learns what is missing.
String buildReleaseKitReadme({
  required String projectName,
  required DateTime createdAt,
  required List<ReleaseKitFile> files,
  String? appStoreKeyId,
  String? appStoreIssuerId,
  String? appStoreTeamId,
}) {
  bool has(ReleaseKitFileKind kind) => files.any((file) => file.kind == kind);
  final filledKeyProperties = files
      .where(
        (file) => file.fromStore && file.kind == ReleaseKitFileKind.properties,
      )
      .firstOrNull;
  final misnamedKeys = files
      .where(
        (file) =>
            file.kind == ReleaseKitFileKind.appStoreKey &&
            !file.path.toLowerCase().endsWith('.p8'),
      )
      .map((file) => '`${file.path}`')
      .toList();
  String id(String label, String? value) =>
      value == null ? '$label: chưa có' : '$label `$value`';
  String mark(ReleaseKitFileKind kind) => has(kind) ? '✓' : '✗';
  String pathOf(ReleaseKitFileKind kind, String fallback) => files
      .where((file) => file.kind == kind)
      .map((file) => '`${file.path}`')
      .followedBy([if (!has(kind)) fallback])
      .join(', ');

  final buffer = StringBuffer()
    ..writeln('# Bộ key release · $projectName')
    ..writeln()
    ..writeln('Tạo bởi App Management Center lúc ${_timestamp(createdAt)}.')
    ..writeln()
    ..writeln(
      '> **Bảo mật:** gói này chứa khoá ký app và quyền truy cập store. Chỉ '
      'gửi qua kênh an toàn, không commit vào git, xoá file zip sau khi setup.',
    )
    ..writeln()
    ..writeln('## Nội dung gói')
    ..writeln()
    ..writeln('| File | Loại | Đặt vào |')
    ..writeln('|---|---|---|');
  for (final file in files) {
    buffer.writeln(
      '| `${file.path}` | ${_kindLabel(file.kind)} | ${_placement(file)} |',
    );
  }
  buffer
    ..writeln()
    ..writeln(
      'File lấy từ project giữ nguyên đường dẫn tương đối: giải nén rồi chép '
      'vào thư mục gốc của project là đúng chỗ. File trong '
      '`$releaseKitStoreFolder/` lấy từ kho an toàn của AMC.',
    )
    ..writeln()
    ..writeln('## Android · CH Play')
    ..writeln()
    ..writeln(
      '${mark(ReleaseKitFileKind.keystore)} keystore · '
      '${mark(ReleaseKitFileKind.properties)} key.properties · '
      '${mark(ReleaseKitFileKind.signingCredentials)} mật khẩu keystore · '
      '${mark(ReleaseKitFileKind.playServiceAccount)} service account · '
      '${mark(ReleaseKitFileKind.env)} env',
    )
    ..writeln()
    ..writeln(
      '1. **Keystore** (${pathOf(ReleaseKitFileKind.keystore, 'chưa có trong gói')}): '
      'đặt sao cho `storeFile` trong `android/key.properties` trỏ đúng tới '
      'file (đường dẫn tương đối tính từ `android/app/` theo mẫu Flutter, '
      'hoặc từ `android/` nếu Gradle của project dùng `rootProject.file`).',
    )
    ..writeln(
      '2. **key.properties** '
      '(${pathOf(ReleaseKitFileKind.properties, 'chưa có, tạo theo mẫu')}):',
    )
    ..writeln()
    ..writeln('   ```properties')
    ..writeln('   storePassword=<mật khẩu store>')
    ..writeln('   keyPassword=<mật khẩu key>')
    ..writeln('   keyAlias=<alias>')
    ..writeln('   storeFile=upload-keystore.jks')
    ..writeln('   ```')
    ..writeln()
    ..writeln(
      '   ${filledKeyProperties != null ? 'Đã điền sẵn alias, mật khẩu và `storeFile` trong `${filledKeyProperties.path}`: chép thành `android/key.properties`. ' : ''}'
      '${has(ReleaseKitFileKind.signingCredentials) ? 'Alias và mật khẩu của từng keystore nằm trong `signing_credentials.txt`.' : 'Gói không kèm mật khẩu keystore: lấy từ người giữ key.'}',
    )
    ..writeln(
      '3. **Service account Google Play** '
      '(${pathOf(ReleaseKitFileKind.playServiceAccount, 'chưa có trong gói')}): '
      'trỏ `json_key_file` trong `android/fastlane/Appfile` tới file JSON, '
      'hoặc trong AMC mở card CH Play → **Thông tin đăng nhập** và nhập JSON.'
      '${has(ReleaseKitFileKind.playServiceAccount) ? '' : ' Chưa có thì tạo key trong Google Cloud Console rồi cấp quyền ở Play Console → Users and permissions.'}',
    )
    ..writeln(
      '4. **Env** (${pathOf(ReleaseKitFileKind.env, 'chưa có trong gói')}): '
      'giữ nguyên vị trí; build dùng `--dart-define-from-file` thì trỏ tới '
      'file tương ứng.',
    )
    ..writeln(
      '5. Kiểm tra: `flutter build appbundle --release`, rồi trong AMC chọn '
      '**Chạy release → Android — CH Play → Xem lại release**.',
    )
    ..writeln()
    ..writeln('## iOS · TestFlight / App Store')
    ..writeln()
    ..writeln(
      '${mark(ReleaseKitFileKind.appStoreKey)} key App Store Connect (.p8) · '
      '${mark(ReleaseKitFileKind.appStoreConfig)} Key ID / Issuer ID / Team ID',
    )
    ..writeln()
    ..writeln(
      '${id('Key ID', appStoreKeyId)} · '
      '${id('Issuer ID', appStoreIssuerId)} · '
      '${id('Team ID', appStoreTeamId)}',
    )
    ..writeln()
    ..writeln(
      '1. **Key .p8** (${pathOf(ReleaseKitFileKind.appStoreKey, 'chưa có trong gói')}): '
      'không cần đặt vào repo. Trong AMC mở card App Store → **Thông tin '
      'đăng nhập**, nhập file .p8 và điền Key ID, Issuer ID, Team ID'
      '${has(ReleaseKitFileKind.appStoreConfig) ? ' trong ${pathOf(ReleaseKitFileKind.appStoreConfig, '')}' : ''}.'
      '${has(ReleaseKitFileKind.appStoreKey) ? '' : ' Chưa có key thì tạo ở App Store Connect → Users and Access → Integrations (file .p8 chỉ tải được một lần).'}'
      '${misnamedKeys.isEmpty ? '' : ' ${misnamedKeys.join(', ')} có đuôi `.txt` thừa: AMC vẫn nhập được, nhưng nên đổi tên thành `AuthKey_${appStoreKeyId ?? '<KEY_ID>'}.p8` khi dùng với công cụ khác.'}',
    )
    ..writeln(
      '2. Chạy ngoài AMC (script iOS xuất từ AMC hoặc fastlane): đặt biến '
      '`AMC_KEY_ID`, `AMC_ISSUER_ID`, `AMC_KEY_FILE` (đường dẫn tuyệt đối tới '
      'file .p8), hoặc trong Fastfile:',
    )
    ..writeln()
    ..writeln('   ```ruby')
    ..writeln('   app_store_connect_api_key(')
    ..writeln('     key_id: "${appStoreKeyId ?? '<KEY_ID>'}",')
    ..writeln('     issuer_id: "${appStoreIssuerId ?? '<ISSUER_ID>'}",')
    ..writeln(
      '     key_filepath: "/đường/dẫn/AuthKey_${appStoreKeyId ?? '<KEY_ID>'}.p8",',
    )
    ..writeln('   )')
    ..writeln('   ```')
    ..writeln()
    ..writeln(
      '3. Máy build cần Xcode, CocoaPods và certificate **Apple Distribution** '
      'kèm private key trong Keychain. Gói này không chứa certificate.',
    )
    ..writeln(
      '4. Kiểm tra: trong AMC chọn **Chạy release → iOS → Xem lại release**; '
      'preflight kiểm tra API key, signing và Bundle ID.',
    )
    ..writeln()
    ..writeln('## Sau khi setup')
    ..writeln()
    ..writeln('- Xoá file zip và thư mục đã giải nén.')
    ..writeln('- Lưu mật khẩu keystore vào trình quản lý mật khẩu.')
    ..writeln(
      '- Nghi bị lộ: thu hồi key trên App Store Connect, xoá key service '
      'account trên Google Cloud rồi tạo key mới. Mất keystore upload thì yêu '
      'cầu Google reset upload key trong Play Console.',
    );
  return buffer.toString();
}

/// Plain guide written next to a password-locked kit as `<name>.README.md`.
///
/// The setup README stays inside the zip, so the kit carries its own
/// instructions however it is forwarded. Inside an encrypted zip it cannot be
/// read before unlocking, though, and Finder, macOS `unzip` and Windows
/// Explorer reject AES zips, so this file only says how to open the kit. It
/// holds no keys, IDs or file list and is safe to send with the zip.
String buildLockedKitGuide({
  required String projectName,
  required String archiveName,
  required DateTime createdAt,
}) {
  final buffer = StringBuffer()
    ..writeln('# Bộ key release · $projectName (có mật khẩu)')
    ..writeln()
    ..writeln(
      '`$archiveName` tạo bởi App Management Center lúc '
      '${_timestamp(createdAt)}, mã hoá AES-256. File này nằm ngoài zip '
      'để đọc được trước khi giải nén và không chứa key hay mật khẩu.',
    )
    ..writeln()
    ..writeln(
      'Mật khẩu được gửi riêng: hỏi người gửi gói nếu chưa có, và đừng gửi '
      'mật khẩu cùng kênh với file zip.',
    )
    ..writeln()
    ..writeln('## Giải nén')
    ..writeln()
    ..writeln(
      'Finder (Archive Utility), lệnh `unzip` có sẵn trên macOS và trình '
      'giải nén mặc định của Windows Explorer không mở được zip AES. Dùng:',
    )
    ..writeln()
    ..writeln(
      '- **macOS:** Keka hoặc The Unarchiver (miễn phí). Hoặc Terminal: '
      '`tar -xf $archiveName`; `tar` có sẵn và hỏi mật khẩu cho từng file '
      'trong gói.',
    )
    ..writeln(
      '- **Windows:** 7-Zip, chuột phải `$archiveName` → 7-Zip → '
      '**Extract Here**.',
    )
    ..writeln(
      '- **Dòng lệnh 7-Zip:** `7z x $archiveName` (macOS: '
      '`brew install sevenzip`, lệnh là `7zz`). Hỏi mật khẩu một lần.',
    )
    ..writeln()
    ..writeln(
      'Gõ mật khẩu khi được hỏi, đừng truyền qua `-p` hay `--passphrase`: '
      'lịch sử shell sẽ lưu lại.',
    )
    ..writeln()
    ..writeln('## Sau khi giải nén')
    ..writeln()
    ..writeln(
      'Hướng dẫn setup Android và iOS nằm trong `$projectName/README.md`. '
      'Setup xong thì xoá file zip, thư mục đã giải nén và file này.',
    );
  return buffer.toString();
}

String _kindLabel(ReleaseKitFileKind kind) => switch (kind) {
  ReleaseKitFileKind.env => 'File env',
  ReleaseKitFileKind.properties => 'File properties',
  ReleaseKitFileKind.playServiceAccount => 'Service account Google Play',
  ReleaseKitFileKind.keystore => 'Keystore Android',
  ReleaseKitFileKind.appStoreKey => 'Key App Store Connect',
  ReleaseKitFileKind.appStoreConfig => 'Key ID, Issuer ID, Team ID',
  ReleaseKitFileKind.signingCredentials => 'Alias và mật khẩu keystore',
};

String _placement(ReleaseKitFile file) {
  if (file.kind == ReleaseKitFileKind.signingCredentials) {
    return 'Trình quản lý mật khẩu, không đặt vào project';
  }
  if (file.kind == ReleaseKitFileKind.appStoreKey ||
      file.kind == ReleaseKitFileKind.appStoreConfig) {
    return 'Ngoài repo, nhập vào AMC (xem phần iOS)';
  }
  if (!file.fromStore) return 'Cùng đường dẫn trong project';
  return switch (file.kind) {
    ReleaseKitFileKind.keystore => 'Khớp `storeFile` trong key.properties',
    ReleaseKitFileKind.properties => 'Chép thành `android/key.properties`',
    _ => 'Xem phần Android',
  };
}

String _timestamp(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
