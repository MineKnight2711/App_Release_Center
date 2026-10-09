import 'package:app_management_center/app/modules/mail_cleaner/controllers/mail_cleaner_controller.dart';
import 'package:app_management_center/app/modules/mail_cleaner/models/mail_item.dart';
import 'package:app_management_center/app/modules/mail_cleaner/services/mail_cleaner_settings_store.dart';
import 'package:app_management_center/app/modules/mail_cleaner/services/mail_imap_service.dart';
import 'package:app_management_center/app/services/ch_play_credential_store_service.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const moThu = '[YÊU CẦU MỞ] TÀI KHOẢN VOS SỐ HỢP ĐỒNG 00157/2020';
const khoaThu = '[YÊU CẦU KHÓA] TÀI KHOẢN VOS HẾT SỐ DƯ';
const voice = '[GTEL-VOICE] THÔNG BÁO CƯỚC THÁNG 9';

/// Stands in for the IMAP server: records the commands the controller issues
/// and hands back a fixed mailbox, so the two-step deletion can be checked
/// without touching a real account.
class FakeImap extends MailImapService {
  FakeImap({this.recoverable = false, this.uidPlus = false});

  final bool recoverable;
  final bool uidPlus;

  final flagged = <int>{};
  final moved = <int>[];
  final expunged = <List<int>?>[];
  final openedFolders = <String>[];
  int folderCount = 4;
  List<MailItem> inbox = [
    MailItem(uid: 1, subject: moThu, size: 20000),
    MailItem(uid: 2, subject: 'Re: $moThu', size: 21000),
    MailItem(uid: 3, subject: khoaThu, size: 30000),
    MailItem(uid: 4, subject: voice, size: 900000),
  ];

  @override
  bool get hasUidPlus => uidPlus;

  @override
  bool get hasMove => recoverable;

  @override
  bool get isGmail => recoverable;

  @override
  bool get deleteIsRecoverable => recoverable;

  @override
  Mailbox? get trash => recoverable
      ? Mailbox(
          encodedName: 'Trash',
          encodedPath: '[Gmail]/Trash',
          flags: [MailboxFlag.trash],
          pathSeparator: '/',
        )
      : null;

  @override
  Future<void> connect({
    required String host,
    required int port,
    required String account,
    required String password,
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<String>> listFolders() async => ['INBOX', 'Sent', 'Trash'];

  @override
  Future<int> openFolder(String path) async {
    openedFolders.add(path);
    return folderCount;
  }

  @override
  Future<MailboxQuota?> readQuota() async =>
      const MailboxQuota(used: 900000, limit: 1000000);

  @override
  Future<List<MailItem>> scanFolder({MailProgressCallback? onProgress}) async {
    onProgress?.call(MailTaskProgress(inbox.length, inbox.length, 'Đang đọc…'));
    return inbox;
  }

  @override
  Future<void> flagDeleted(
    List<int> uids, {
    MailProgressCallback? onProgress,
  }) async {
    flagged.addAll(uids);
  }

  @override
  Future<void> moveToTrash(
    List<int> uids, {
    MailProgressCallback? onProgress,
  }) async {
    moved.addAll(uids);
  }

  @override
  Future<void> deleteForever({List<int>? uids}) async => expunged.add(uids);

  @override
  Future<int> clearDeletedFlags() async {
    final cleared = flagged.length;
    flagged.clear();
    return cleared;
  }

  @override
  Future<int> countFlagged() async => flagged.length;
}

class MemorySecureStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async => values.remove(key);
}

MailCleanerController buildController(
  FakeImap imap, {
  MailCleanerSettingsStore? store,
}) {
  return MailCleanerController(
    imap: imap,
    settingsStore:
        store ?? MailCleanerSettingsStore(secureStore: MemorySecureStore()),
  );
}

Future<MailCleanerController> connectedAndScanned(FakeImap imap) async {
  final controller = buildController(imap);
  await controller.connect(
    host: 'pro216.emailserver.vn',
    port: 993,
    account: 'nganty@gtelcts.vn',
    password: 'secret',
  );
  await controller.scan();
  return controller;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('kết nối xong thì mở thư mục, đọc quota và ghi nhật ký', () async {
    final imap = FakeImap();
    final controller = buildController(imap);

    await controller.connect(
      host: 'pro216.emailserver.vn',
      port: 993,
      account: 'nganty@gtelcts.vn',
      password: 'secret',
    );

    expect(controller.stage, MailCleanerStage.connected);
    expect(controller.folders, ['INBOX', 'Sent', 'Trash']);
    expect(controller.folderTotal, 4);
    expect(controller.quota?.nearlyFull, isTrue);
    expect(imap.openedFolders, ['INBOX']);
    expect(controller.logLines.first, contains('INBOX'));
    expect(controller.error, isNull);
    controller.dispose();
  });

  test('server không còn thư mục đã nhớ thì quay về INBOX', () async {
    SharedPreferences.setMockInitialValues({});
    final store = MailCleanerSettingsStore(secureStore: MemorySecureStore());
    await store.save(
      const MailCleanerSettings(account: 'a@b.vn', folder: 'Đã lưu/Cũ'),
    );
    final imap = FakeImap();
    final controller = buildController(imap, store: store);
    await controller.loadSettings();
    expect(controller.folder, 'Đã lưu/Cũ');

    await controller.connect(
      host: 'pro216.emailserver.vn',
      port: 993,
      account: 'a@b.vn',
      password: 'secret',
    );

    expect(controller.folder, 'INBOX');
    expect(imap.openedFolders, ['INBOX']);
    expect(controller.stage, MailCleanerStage.connected);
    controller.dispose();
  });

  test('lỗi đăng nhập được diễn giải bằng tiếng Việt', () async {
    final controller = buildController(_FailingImap());

    await controller.connect(
      host: 'pro216.emailserver.vn',
      port: 993,
      account: 'nganty@gtelcts.vn',
      password: 'sai',
    );

    expect(controller.stage, MailCleanerStage.disconnected);
    expect(controller.error, 'Sai tài khoản hoặc mật khẩu.');
    controller.dispose();
  });

  test('quét xong thì gom nhóm theo dung lượng giảm dần', () async {
    final controller = await connectedAndScanned(FakeImap());

    expect(controller.stage, MailCleanerStage.scanned);
    expect(controller.allMail, hasLength(4));
    expect(controller.groups.first.name, '[GTEL-VOICE]');
    expect(controller.progress, isNull);
    controller.dispose();
  });

  test('chọn nhóm nào thì chỉ thư nhóm đó bị tính, thư Re: được giữ', () async {
    final controller = await connectedAndScanned(FakeImap());

    controller.selectGroup('[YEU CAU MO]', true);

    // UID 2 là "Re:" của đúng nhóm đó nên bị giữ lại theo mặc định.
    expect(controller.matchedMail.map((mail) => mail.uid), [1]);
    expect(controller.keptReplyCount, 1);
    expect(controller.matchedBytes, 20000);

    controller.setKeepReplies(false);
    expect(controller.matchedMail.map((mail) => mail.uid), [1, 2]);
    expect(controller.keptReplyCount, 0);
    controller.dispose();
  });

  test('quy tắc tự nhập cộng dồn với nhóm đã tick, tắt thì loại ra', () async {
    final controller = await connectedAndScanned(FakeImap());

    controller.selectGroup('[YEU CAU MO]', true);
    controller.addRule(SubjectRule(pattern: '[GTEL-VOICE]'));
    expect(controller.matchedMail.map((mail) => mail.uid), [1, 4]);

    controller.toggleRule(0);
    expect(controller.matchedMail.map((mail) => mail.uid), [1]);

    controller.removeRule(0);
    expect(controller.rules, isEmpty);

    controller.clearSelection();
    expect(controller.matchedCount, 0);
    controller.dispose();
  });

  test('bước gắn cờ không xoá thư và đếm lại số thư đang gắn cờ', () async {
    final imap = FakeImap();
    final controller = await connectedAndScanned(imap);
    controller.selectGroup('[GTEL-VOICE]', true);

    await controller.flag();

    expect(imap.flagged, {4});
    expect(imap.expunged, isEmpty);
    expect(imap.moved, isEmpty);
    expect(controller.flaggedCount, 1);
    // Danh sách quét vẫn còn để người dùng xem lại trước bước hai.
    expect(controller.allMail, hasLength(4));
    expect(controller.stage, MailCleanerStage.scanned);
    controller.dispose();
  });

  test('gỡ cờ trả lại hộp thư nguyên vẹn', () async {
    final imap = FakeImap();
    final controller = await connectedAndScanned(imap);
    controller.selectGroup('[GTEL-VOICE]', true);
    await controller.flag();

    await controller.clearFlags();

    expect(imap.flagged, isEmpty);
    expect(controller.flaggedCount, 0);
    expect(imap.expunged, isEmpty);
    controller.dispose();
  });

  test('server không khôi phục được thì bước hai gọi EXPUNGE', () async {
    final imap = FakeImap();
    final controller = await connectedAndScanned(imap);
    controller.selectGroup('[GTEL-VOICE]', true);

    await controller.deleteForever();

    expect(imap.expunged, [
      [4],
    ]);
    expect(imap.moved, isEmpty);
    // Sau khi xoá, kết quả quét cũ không còn đúng nữa nên phải quét lại.
    expect(controller.allMail, isEmpty);
    expect(controller.selectedGroups, isEmpty);
    expect(controller.stage, MailCleanerStage.connected);
    expect(imap.openedFolders, ['INBOX', 'INBOX']);
    controller.dispose();
  });

  test('server có MOVE và Thùng rác thì chuyển thư, không EXPUNGE', () async {
    final imap = FakeImap(recoverable: true);
    final controller = await connectedAndScanned(imap);
    controller.selectGroup('[GTEL-VOICE]', true);

    expect(controller.deleteIsRecoverable, isTrue);
    expect(controller.trashName, '[Gmail]/Trash');

    await controller.moveToTrash();

    expect(imap.moved, [4]);
    expect(imap.expunged, isEmpty);
    expect(controller.allMail, isEmpty);
    expect(controller.stage, MailCleanerStage.connected);
    controller.dispose();
  });

  test('đổi thư mục thì bỏ kết quả quét cũ', () async {
    final imap = FakeImap();
    final controller = await connectedAndScanned(imap);
    controller.selectGroup('[GTEL-VOICE]', true);

    await controller.changeFolder('Sent');

    expect(controller.folder, 'Sent');
    expect(controller.allMail, isEmpty);
    expect(controller.groups, isEmpty);
    expect(controller.selectedGroups, isEmpty);
    expect(imap.openedFolders, ['INBOX', 'Sent']);
    controller.dispose();
  });

  test('ngắt kết nối xoá cả quy tắc và dữ liệu phiên', () async {
    final controller = await connectedAndScanned(FakeImap());
    controller.addRule(SubjectRule(pattern: '[GTEL]'));

    await controller.disconnect();

    expect(controller.stage, MailCleanerStage.disconnected);
    expect(controller.rules, isEmpty);
    expect(controller.allMail, isEmpty);
    expect(controller.quota, isNull);
    expect(controller.folderTotal, 0);
    controller.dispose();
  });

  test('chỉ lưu mật khẩu khi người dùng bật nhớ mật khẩu', () async {
    final secureStore = MemorySecureStore();
    final store = MailCleanerSettingsStore(secureStore: secureStore);
    final controller = buildController(FakeImap(), store: store);

    await controller.connect(
      host: 'pro216.emailserver.vn',
      port: 993,
      account: 'nganty@gtelcts.vn',
      password: 'secret',
    );
    expect(secureStore.values, isEmpty);

    await controller.setRememberPassword(true);
    await controller.connect(
      host: 'pro216.emailserver.vn',
      port: 993,
      account: 'nganty@gtelcts.vn',
      password: 'secret',
    );
    expect(secureStore.values.values, ['secret']);

    // Tắt lại thì mật khẩu phải bị quên ngay, không đợi lần kết nối sau.
    await controller.setRememberPassword(false);
    expect(secureStore.values, isEmpty);
    controller.dispose();
  });

  test('mở lại module thì nhớ host, cổng, tài khoản và thư mục', () async {
    final secureStore = MemorySecureStore();
    final store = MailCleanerSettingsStore(secureStore: secureStore);
    final first = buildController(FakeImap(), store: store);
    await first.setRememberPassword(true);
    await first.connect(
      host: 'imap.gmail.com',
      port: 993,
      account: 'nganty@gtelcts.vn',
      password: 'app-password',
    );
    await first.changeFolder('Sent');
    first.dispose();

    final second = buildController(FakeImap(), store: store);
    await second.loadSettings();

    expect(second.host, 'imap.gmail.com');
    expect(second.port, 993);
    expect(second.account, 'nganty@gtelcts.vn');
    expect(second.folder, 'Sent');
    expect(second.rememberPassword, isTrue);
    expect(second.savedPassword, 'app-password');
    second.dispose();
  });

  test('cấu hình hỏng trong preferences không làm vỡ module', () async {
    SharedPreferences.setMockInitialValues({
      'mail_cleaner_settings': 'không phải JSON',
    });
    final store = MailCleanerSettingsStore(secureStore: MemorySecureStore());

    final settings = await store.read();

    expect(settings.host, 'pro216.emailserver.vn');
    expect(settings.folder, 'INBOX');
    expect(settings.rememberPassword, isFalse);
  });

  test('cổng ngoài khoảng hợp lệ trong file cấu hình bị bỏ qua', () async {
    SharedPreferences.setMockInitialValues({
      'mail_cleaner_settings':
          '{"host":"imap.gmail.com","port":0,"account":"a@b.vn","folder":""}',
    });
    final store = MailCleanerSettingsStore(secureStore: MemorySecureStore());

    final settings = await store.read();

    expect(settings.host, 'imap.gmail.com');
    expect(settings.port, 993);
    expect(settings.folder, 'INBOX');
  });
}

/// Refuses the login the way a server does when the password is wrong.
class _FailingImap extends FakeImap {
  @override
  Future<void> connect({
    required String host,
    required int port,
    required String account,
    required String password,
  }) async {
    throw ImapException(
      ImapClient(isLogEnabled: false),
      'AUTHENTICATIONFAILED Invalid credentials',
    );
  }
}
