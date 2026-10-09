import 'package:enough_mail/enough_mail.dart';

import '../models/mail_item.dart';

/// How full the mailbox is.
class MailboxQuota {
  const MailboxQuota({required this.used, required this.limit});

  /// Both in bytes.
  final int used;
  final int limit;

  double get ratio => limit == 0 ? 0 : used / limit;

  bool get nearlyFull => ratio >= 0.9;
}

/// Progress of one long-running step.
class MailTaskProgress {
  const MailTaskProgress(this.done, this.total, this.message);

  final int done;
  final int total;
  final String message;

  double get ratio => total == 0 ? 0 : done / total;
}

typedef MailProgressCallback = void Function(MailTaskProgress progress);

/// Wraps `ImapClient` for exactly what cleaning a mailbox out needs.
///
/// Two things learned the hard way from the Email Pro server
/// (pro216.emailserver.vn):
///
/// * It does **not** support UIDPLUS, so `UID EXPUNGE` is unavailable. A plain
///   `EXPUNGE` then removes *every* message flagged `\Deleted` in the folder.
/// * It does **not** support MOVE and its Trash folder refuses messages, so
///   every deletion there is **permanent**.
///
/// That is why deleting is split in two: flagging, which can be undone, and
/// only then `EXPUNGE`, which cannot.
class MailImapService {
  ImapClient? _client;
  Mailbox? _currentMailbox;

  /// The most UIDs to put in one command, to keep the command short enough.
  static const int _uidsPerCommand = 400;

  /// How many message headers to pull per FETCH round.
  static const int _headersPerFetch = 2000;

  bool get isConnected => _client?.isLoggedIn ?? false;

  bool _hasUidPlus = false;
  bool _hasMove = false;
  bool _isGmail = false;
  Mailbox? _trash;

  /// Whether the server supports `UID EXPUNGE` (RFC 4315).
  bool get hasUidPlus => _hasUidPlus;

  /// Whether the server supports the `MOVE` command (RFC 6851).
  ///
  /// Email Pro does **not**, so moving messages to Trash fails there — which
  /// is why every deletion on that server is permanent.
  bool get hasMove => _hasMove;

  /// Connected to Gmail, recognised through the `X-GM-EXT-1` capability.
  bool get isGmail => _isGmail;

  /// The Trash folder found through the `\Trash` special-use attribute, so it
  /// does not depend on the display name's language.
  Mailbox? get trash => _trash;

  /// Whether deleting on this server can go through Trash and stay
  /// recoverable.
  ///
  /// Both halves are needed: a `MOVE` command **and** a Trash folder.
  bool get deleteIsRecoverable => _hasMove && _trash != null;

  Future<void> connect({
    required String host,
    required int port,
    required String account,
    required String password,
  }) async {
    await disconnect();
    final client = ImapClient(isLogEnabled: false);
    await client.connectToServer(host, port, isSecure: true);
    final capabilities = await client.login(account, password);
    final names = capabilities.map((e) => e.name.toUpperCase()).toSet();
    _hasUidPlus = names.contains('UIDPLUS');
    _hasMove = names.contains('MOVE');
    _isGmail = names.contains('X-GM-EXT-1');
    _client = client;

    try {
      final mailboxes = await client.listMailboxes(recursive: true);
      _trash = mailboxes.where((e) => e.isTrash).firstOrNull;
    } catch (_) {
      _trash = null;
    }
  }

  Future<void> disconnect() async {
    final client = _client;
    _client = null;
    _currentMailbox = null;
    if (client == null) return;
    try {
      await client.logout();
    } catch (_) {
      // Closing the connection is cleanup; a failure here need not be shown.
    }
  }

  ImapClient get _requireClient {
    final client = _client;
    if (client == null) throw StateError('Chưa kết nối tới server.');
    return client;
  }

  Future<List<String>> listFolders() async {
    final mailboxes = await _requireClient.listMailboxes(recursive: true);
    return mailboxes.map((e) => e.path).toList();
  }

  /// Opens a folder and returns how many messages it holds.
  Future<int> openFolder(String path) async {
    final client = _requireClient;
    final mailboxes = await client.listMailboxes(recursive: true);
    final mailbox = mailboxes.firstWhere(
      (e) => e.path == path,
      orElse: () => throw StateError('Không tìm thấy thư mục "$path".'),
    );
    _currentMailbox = await client.selectMailbox(mailbox);
    return _currentMailbox?.messagesExists ?? 0;
  }

  Future<MailboxQuota?> readQuota() async {
    try {
      final result = await _requireClient.getQuota(quotaRoot: '""');
      for (final resource in result.resourceLimits) {
        if (resource.name.toUpperCase().contains('STORAGE')) {
          // IMAP reports these in KB.
          return MailboxQuota(
            used: (resource.currentUsage ?? 0) * 1024,
            limit: (resource.usageLimit ?? 0) * 1024,
          );
        }
      }
    } catch (_) {
      // Not every server has QUOTA turned on.
    }
    return null;
  }

  /// Squeezes a UID list into ranges such as `1:300,305,400:900`.
  static List<String> compressRanges(List<int> uids) {
    if (uids.isEmpty) return const [];
    final sorted = uids.toSet().toList()..sort();
    final ranges = <String>[];
    var start = 0;
    while (start < sorted.length) {
      var end = start;
      while (end + 1 < sorted.length && sorted[end + 1] == sorted[end] + 1) {
        end++;
      }
      ranges.add(
        start == end ? '${sorted[start]}' : '${sorted[start]}:${sorted[end]}',
      );
      start = end + 1;
    }
    return ranges;
  }

  /// Packs ranges into command strings no longer than [limit] characters.
  static List<String> batchRanges(List<String> ranges, {int limit = 2000}) {
    final commands = <String>[];
    final buffer = StringBuffer();
    for (final range in ranges) {
      if (buffer.isNotEmpty && buffer.length + 1 + range.length > limit) {
        commands.add(buffer.toString());
        buffer.clear();
      }
      if (buffer.isNotEmpty) buffer.write(',');
      buffer.write(range);
    }
    if (buffer.isNotEmpty) commands.add(buffer.toString());
    return commands;
  }

  /// Reads the UID, size and subject of every message in the open folder.
  ///
  /// Only the `Subject` header is fetched, which is far lighter than pulling
  /// whole messages.
  Future<List<MailItem>> scanFolder({MailProgressCallback? onProgress}) async {
    final client = _requireClient;

    onProgress?.call(
      const MailTaskProgress(0, 1, 'Đang hỏi server danh sách thư…'),
    );
    final search = await client.uidSearchMessages(searchCriteria: 'ALL');
    final uids = search.matchingSequence?.toList() ?? const <int>[];
    if (uids.isEmpty) return [];

    final mail = <MailItem>[];
    for (var offset = 0; offset < uids.length; offset += _headersPerFetch) {
      final slice = uids.sublist(
        offset,
        (offset + _headersPerFetch).clamp(0, uids.length),
      );
      final sequence = MessageSequence.parse(
        batchRanges(compressRanges(slice), limit: 8000).join(','),
        isUidSequence: true,
      );
      final fetched = await client.uidFetchMessages(
        sequence,
        '(UID RFC822.SIZE BODY.PEEK[HEADER.FIELDS (SUBJECT)])',
      );
      for (final message in fetched.messages) {
        final uid = message.uid;
        if (uid == null) continue;
        mail.add(
          MailItem(
            uid: uid,
            subject: (message.decodeSubject() ?? '').trim(),
            size: message.size ?? 0,
          ),
        );
      }
      onProgress?.call(
        MailTaskProgress(mail.length, uids.length, 'Đang đọc tiêu đề thư…'),
      );
    }
    return mail;
  }

  /// Step one — set the `\Deleted` flag. **Undone** by [clearDeletedFlags].
  Future<void> flagDeleted(
    List<int> uids, {
    MailProgressCallback? onProgress,
  }) async {
    final client = _requireClient;
    final commands = batchRanges(
      compressRanges(uids),
      limit: _uidsPerCommand * 5,
    );
    var done = 0;
    for (final command in commands) {
      final sequence = MessageSequence.parse(command, isUidSequence: true);
      await client.uidStore(sequence, [r'\Deleted'], action: StoreAction.add);
      done += sequence.toList().length;
      onProgress?.call(
        MailTaskProgress(done, uids.length, 'Đang đánh dấu thư…'),
      );
    }
  }

  /// Moves messages to Trash, which stays **recoverable**.
  ///
  /// Used for Gmail and any server carrying `MOVE`. On Gmail, flagging
  /// `\Deleted` and expunging within one label only *removes the label*
  /// instead of the message; making it leave the mailbox takes a move to
  /// Trash.
  Future<void> moveToTrash(
    List<int> uids, {
    MailProgressCallback? onProgress,
  }) async {
    final client = _requireClient;
    final target = _trash;
    if (target == null) {
      throw StateError('Không tìm thấy thư mục Thùng rác trên server này.');
    }
    final commands = batchRanges(
      compressRanges(uids),
      limit: _uidsPerCommand * 5,
    );
    var done = 0;
    for (final command in commands) {
      final sequence = MessageSequence.parse(command, isUidSequence: true);
      await client.uidMove(sequence, targetMailbox: target);
      done += sequence.toList().length;
      onProgress?.call(
        MailTaskProgress(done, uids.length, 'Đang chuyển thư vào Thùng rác…'),
      );
    }
  }

  /// Step two — the real deletion. **Cannot be undone.**
  Future<void> deleteForever({List<int>? uids}) async {
    final client = _requireClient;
    if (_hasUidPlus && uids != null && uids.isNotEmpty) {
      final commands = batchRanges(
        compressRanges(uids),
        limit: _uidsPerCommand * 5,
      );
      for (final command in commands) {
        await client.uidExpunge(
          MessageSequence.parse(command, isUidSequence: true),
        );
      }
    } else {
      await client.expunge();
    }
  }

  /// The escape hatch — clears `\Deleted` off every message, deleting nothing.
  ///
  /// Returns how many messages were unflagged.
  Future<int> clearDeletedFlags() async {
    final client = _requireClient;
    final search = await client.uidSearchMessages(searchCriteria: 'DELETED');
    final uids = search.matchingSequence?.toList() ?? const <int>[];
    if (uids.isEmpty) return 0;
    final commands = batchRanges(
      compressRanges(uids),
      limit: _uidsPerCommand * 5,
    );
    for (final command in commands) {
      final sequence = MessageSequence.parse(command, isUidSequence: true);
      await client.uidStore(sequence, [
        r'\Deleted',
      ], action: StoreAction.remove);
    }
    return uids.length;
  }

  /// Counts the messages flagged `\Deleted` that have not been removed yet.
  Future<int> countFlagged() async {
    final search = await _requireClient.uidSearchMessages(
      searchCriteria: 'DELETED',
    );
    return search.matchingSequence?.toList().length ?? 0;
  }
}
