import 'package:flutter/foundation.dart';

import '../models/mail_item.dart';
import '../services/mail_cleaner_settings_store.dart';
import '../services/mail_imap_service.dart';

/// Where the cleaning run currently stands.
enum MailCleanerStage {
  disconnected,
  connecting,
  connected,
  scanning,
  scanned,
  deleting,
}

/// Owns one mail-cleaning session: the connection, what the scan found, and
/// which messages the current selection would delete.
///
/// A [ChangeNotifier] rather than a GetX controller, for the same reason as the
/// Plan Studio module: the session belongs to the open page and must be torn
/// down — connection included — when that page closes.
class MailCleanerController extends ChangeNotifier {
  MailCleanerController({
    MailImapService? imap,
    MailCleanerSettingsStore? settingsStore,
  }) : _imap = imap ?? MailImapService(),
       _settingsStore = settingsStore ?? MailCleanerSettingsStore();

  final MailImapService _imap;
  final MailCleanerSettingsStore _settingsStore;

  // ----- Connection details ------------------------------------------------
  String host = const MailCleanerSettings().host;
  int port = const MailCleanerSettings().port;
  String account = '';
  String folder = const MailCleanerSettings().folder;

  /// Whether the password may be kept in the OS keychain between sessions.
  bool rememberPassword = false;

  /// The password read back from the keychain, for the form to prefill.
  String? savedPassword;

  MailCleanerStage stage = MailCleanerStage.disconnected;
  String? error;

  MailboxQuota? quota;
  int folderTotal = 0;
  List<String> folders = const [];

  bool get hasUidPlus => _imap.hasUidPlus;

  bool get isGmail => _imap.isGmail;

  /// Whether deleting on this server stays recoverable, by going through Trash.
  bool get deleteIsRecoverable => _imap.deleteIsRecoverable;

  String? get trashName => _imap.trash?.path;

  // ----- What the scan found ----------------------------------------------
  List<MailItem> allMail = const [];
  List<SubjectGroup> groups = const [];

  /// Names of the groups ticked in the analysis table.
  final Set<String> selectedGroups = {};

  /// Rules the user typed in.
  final List<SubjectRule> rules = [];

  /// Keep `Re:` / `Fwd:` messages — on by default, as the safe choice.
  bool keepReplies = true;

  MailTaskProgress? progress;
  final List<String> logLines = [];

  /// Messages flagged `\Deleted` that have not been expunged yet.
  int flaggedCount = 0;

  /// Reads back the remembered connection so the form does not start empty.
  Future<void> loadSettings() async {
    final settings = await _settingsStore.read();
    host = settings.host;
    port = settings.port;
    account = settings.account;
    folder = settings.folder;
    rememberPassword = settings.rememberPassword;
    savedPassword = settings.rememberPassword
        ? await _settingsStore.readPassword()
        : null;
    notifyListeners();
  }

  Future<void> _saveSettings({String? password}) async {
    await _settingsStore.save(
      MailCleanerSettings(
        host: host,
        port: port,
        account: account,
        folder: folder,
        rememberPassword: rememberPassword,
      ),
    );
    if (rememberPassword && password != null) {
      await _settingsStore.savePassword(password);
    }
  }

  void _log(String line) {
    final now = DateTime.now();
    final clock =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    logLines.insert(0, '[$clock] $line');
    if (logLines.length > 500) logLines.removeLast();
  }

  void _setStage(MailCleanerStage next) {
    stage = next;
    notifyListeners();
  }

  // ----- Matched messages --------------------------------------------------

  /// The messages the current selection would delete.
  List<MailItem> get matchedMail {
    final active = rules.where((rule) => rule.enabled).toList();
    return allMail.where((mail) {
      if (keepReplies && mail.isReply) return false;
      if (selectedGroups.contains(mail.group)) return true;
      return active.any((rule) => rule.matches(mail));
    }).toList();
  }

  int get matchedCount => matchedMail.length;

  int get matchedBytes => matchedMail.fold(0, (sum, mail) => sum + mail.size);

  /// How many `Re:`/`Fwd:` messages [keepReplies] is currently sparing.
  int get keptReplyCount {
    if (!keepReplies) return 0;
    final active = rules.where((rule) => rule.enabled).toList();
    return allMail
        .where(
          (mail) =>
              mail.isReply &&
              (selectedGroups.contains(mail.group) ||
                  active.any((rule) => rule.matches(mail))),
        )
        .length;
  }

  // ----- Actions -----------------------------------------------------------

  Future<void> connect({
    required String host,
    required int port,
    required String account,
    required String password,
  }) async {
    this.host = host;
    this.port = port;
    this.account = account;
    error = null;
    _setStage(MailCleanerStage.connecting);
    try {
      await _imap.connect(
        host: host,
        port: port,
        account: account,
        password: password,
      );
      _log('Đã kết nối $account@$host:$port');
      if (_imap.isGmail) _log('Nhận diện: Gmail (X-GM-EXT-1).');
      if (_imap.deleteIsRecoverable) {
        _log(
          'Chế độ an toàn: thư sẽ được chuyển vào '
          '"${_imap.trash!.path}" và còn khôi phục được.',
        );
      } else {
        _log(
          'Server không có lệnh MOVE hoặc không tìm thấy Thùng rác — '
          'mọi thao tác xoá ở đây là VĨNH VIỄN.',
        );
        if (!_imap.hasUidPlus) {
          _log('Server không hỗ trợ UIDPLUS — EXPUNGE sẽ xoá mọi thư gắn cờ.');
        }
      }
      folders = await _imap.listFolders();
      // A remembered folder can be gone by now; falling back to the one the
      // server does have beats failing the whole connection over it.
      if (!folders.contains(folder) && folders.isNotEmpty) {
        final fallback = folders.contains('INBOX') ? 'INBOX' : folders.first;
        if (fallback != folder) {
          _log('Không còn thư mục "$folder", chuyển sang "$fallback".');
          folder = fallback;
        }
      }
      folderTotal = await _imap.openFolder(folder);
      quota = await _imap.readQuota();
      flaggedCount = await _imap.countFlagged();
      if (flaggedCount > 0) {
        _log('Cảnh báo: $flaggedCount thư đang gắn cờ \\Deleted từ trước.');
      }
      _log('Thư mục $folder có ${formatCount(folderTotal)} thư.');
      await _saveSettings(password: password);
      _setStage(MailCleanerStage.connected);
    } catch (e) {
      error = _describeError(e);
      _log('Kết nối thất bại: $error');
      _setStage(MailCleanerStage.disconnected);
    }
  }

  Future<void> changeFolder(String path) async {
    if (path == folder) return;
    folder = path;
    allMail = const [];
    groups = const [];
    selectedGroups.clear();
    try {
      folderTotal = await _imap.openFolder(path);
      flaggedCount = await _imap.countFlagged();
      _log('Chuyển sang thư mục $path (${formatCount(folderTotal)} thư).');
      await _saveSettings();
      _setStage(MailCleanerStage.connected);
    } catch (e) {
      error = _describeError(e);
      notifyListeners();
    }
  }

  Future<void> scan() async {
    error = null;
    _setStage(MailCleanerStage.scanning);
    try {
      final mail = await _imap.scanFolder(
        onProgress: (value) {
          progress = value;
          notifyListeners();
        },
      );
      allMail = mail;
      groups = groupMail(mail);
      progress = null;
      _log(
        'Quét xong ${formatCount(mail.length)} thư, '
        '${groups.length} nhóm tiêu đề.',
      );
      _setStage(MailCleanerStage.scanned);
    } catch (e) {
      error = _describeError(e);
      progress = null;
      _log('Quét thất bại: $error');
      _setStage(MailCleanerStage.connected);
    }
  }

  /// Step one: only flags, deletes nothing yet.
  Future<void> flag() async {
    final matched = matchedMail;
    if (matched.isEmpty) return;
    error = null;
    _setStage(MailCleanerStage.deleting);
    try {
      await _imap.flagDeleted(
        matched.map((mail) => mail.uid).toList(),
        onProgress: (value) {
          progress = value;
          notifyListeners();
        },
      );
      progress = null;
      flaggedCount = await _imap.countFlagged();
      _log('Đã gắn cờ ${formatCount(matched.length)} thư — vẫn hoàn tác được.');
      _setStage(MailCleanerStage.scanned);
    } catch (e) {
      error = _describeError(e);
      progress = null;
      _log('Gắn cờ thất bại: $error');
      _setStage(MailCleanerStage.scanned);
    }
  }

  /// Moves messages to Trash — for Gmail and any server carrying MOVE.
  /// Recoverable from Trash.
  Future<void> moveToTrash() async {
    final matched = matchedMail;
    if (matched.isEmpty) return;
    error = null;
    _setStage(MailCleanerStage.deleting);
    try {
      await _imap.moveToTrash(
        matched.map((mail) => mail.uid).toList(),
        onProgress: (value) {
          progress = value;
          notifyListeners();
        },
      );
      _log(
        'Đã chuyển ${formatCount(matched.length)} thư vào "$trashName" — '
        'còn khôi phục được.',
      );

      folderTotal = await _imap.openFolder(folder);
      quota = await _imap.readQuota();
      allMail = const [];
      groups = const [];
      selectedGroups.clear();
      progress = null;
      _log(
        'Thư mục $folder còn ${formatCount(folderTotal)} thư. Hãy quét lại.',
      );
      _setStage(MailCleanerStage.connected);
    } catch (e) {
      error = _describeError(e);
      progress = null;
      _log('Chuyển Thùng rác thất bại: $error');
      _setStage(MailCleanerStage.scanned);
    }
  }

  /// Step two: the real deletion, which cannot be undone.
  Future<void> deleteForever() async {
    error = null;
    _setStage(MailCleanerStage.deleting);
    try {
      final uids = matchedMail.map((mail) => mail.uid).toList();
      progress = const MailTaskProgress(0, 1, 'Đang xoá vĩnh viễn…');
      notifyListeners();
      await _imap.deleteForever(uids: uids);
      _log('ĐÃ XOÁ VĨNH VIỄN ${formatCount(uids.length)} thư.');

      folderTotal = await _imap.openFolder(folder);
      quota = await _imap.readQuota();
      flaggedCount = await _imap.countFlagged();
      allMail = const [];
      groups = const [];
      selectedGroups.clear();
      progress = null;
      _log(
        'Thư mục $folder còn ${formatCount(folderTotal)} thư. Hãy quét lại.',
      );
      _setStage(MailCleanerStage.connected);
    } catch (e) {
      error = _describeError(e);
      progress = null;
      _log('Xoá thất bại: $error');
      _setStage(MailCleanerStage.scanned);
    }
  }

  /// The escape hatch: clears `\Deleted`, losing no message.
  Future<void> clearFlags() async {
    error = null;
    try {
      final cleared = await _imap.clearDeletedFlags();
      flaggedCount = await _imap.countFlagged();
      _log(
        cleared == 0
            ? 'Không có thư nào đang gắn cờ.'
            : 'Đã gỡ cờ $cleared thư — không thư nào bị xoá.',
      );
      notifyListeners();
    } catch (e) {
      error = _describeError(e);
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _imap.disconnect();
    allMail = const [];
    groups = const [];
    selectedGroups.clear();
    rules.clear();
    quota = null;
    folderTotal = 0;
    _log('Đã ngắt kết nối.');
    _setStage(MailCleanerStage.disconnected);
  }

  // ----- Rules -------------------------------------------------------------

  void addRule(SubjectRule rule) {
    rules.add(rule);
    notifyListeners();
  }

  void removeRule(int index) {
    rules.removeAt(index);
    notifyListeners();
  }

  void toggleRule(int index) {
    rules[index].enabled = !rules[index].enabled;
    notifyListeners();
  }

  void selectGroup(String name, bool selected) {
    if (selected) {
      selectedGroups.add(name);
    } else {
      selectedGroups.remove(name);
    }
    notifyListeners();
  }

  void clearSelection() {
    selectedGroups.clear();
    notifyListeners();
  }

  void setKeepReplies(bool value) {
    keepReplies = value;
    notifyListeners();
  }

  /// Turns remembering the password on or off, forgetting it straight away.
  Future<void> setRememberPassword(bool value) async {
    rememberPassword = value;
    if (!value) savedPassword = null;
    notifyListeners();
    await _saveSettings();
  }

  String logText() => logLines.reversed.join('\n');

  String _describeError(Object error) {
    final text = error.toString();
    if (text.contains('AUTHENTICATIONFAILED') ||
        text.toLowerCase().contains('login failed') ||
        text.contains('Invalid credentials')) {
      return 'Sai tài khoản hoặc mật khẩu.';
    }
    if (text.contains('SocketException') || text.contains('TimeoutException')) {
      return 'Không kết nối được tới server. Kiểm tra mạng, host và cổng.';
    }
    if (text.contains('HandshakeException')) {
      return 'Lỗi chứng chỉ SSL của server.';
    }
    return text.replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    _imap.disconnect();
    super.dispose();
  }
}
