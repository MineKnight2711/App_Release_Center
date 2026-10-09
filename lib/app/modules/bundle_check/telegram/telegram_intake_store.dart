import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// How the AAB bot behaves. The Bot API server address lives in
/// `TelegramReleaseSettings.apiBaseUrl`, shared with release notifications.
class TelegramIntakeSettings {
  const TelegramIntakeSettings({
    this.enabled = false,
    this.allowedChatIds = const [],
    this.allowedUserIds = const [],
    this.downloadingMessage = defaultDownloadingMessage,
    this.runOnEmulator = true,
    this.watchSeconds = 20,
    this.serverExecutable = '',
    this.serverPort = 8081,
    this.serverFilesFrom = '',
    this.serverFilesTo = '',
  });

  static const defaultDownloadingMessage =
      "I'm downloading and checking the aab";

  final bool enabled;

  /// Chats the bot answers in. Empty: only the release chat.
  final List<int> allowedChatIds;

  /// People allowed to trigger a check. Empty: anyone in an allowed chat.
  final List<int> allowedUserIds;

  /// Said in the chat before the file is fetched.
  final String downloadingMessage;

  /// Also install and open the bundle, on an emulator only.
  final bool runOnEmulator;
  final int watchSeconds;

  /// `telegram-bot-api.exe` AMC starts when the local server is not up.
  final String serverExecutable;
  final int serverPort;

  /// When the server runs in a container, where its file paths appear on
  /// this machine: paths starting with [serverFilesFrom] are read from
  /// [serverFilesTo] instead.
  final String serverFilesFrom;
  final String serverFilesTo;

  String get localServerUrl => 'http://127.0.0.1:$serverPort';

  TelegramIntakeSettings copyWith({
    bool? enabled,
    List<int>? allowedChatIds,
    List<int>? allowedUserIds,
    String? downloadingMessage,
    bool? runOnEmulator,
    int? watchSeconds,
    String? serverExecutable,
    int? serverPort,
    String? serverFilesFrom,
    String? serverFilesTo,
  }) {
    return TelegramIntakeSettings(
      enabled: enabled ?? this.enabled,
      allowedChatIds: allowedChatIds ?? this.allowedChatIds,
      allowedUserIds: allowedUserIds ?? this.allowedUserIds,
      downloadingMessage: downloadingMessage ?? this.downloadingMessage,
      runOnEmulator: runOnEmulator ?? this.runOnEmulator,
      watchSeconds: watchSeconds ?? this.watchSeconds,
      serverExecutable: serverExecutable ?? this.serverExecutable,
      serverPort: serverPort ?? this.serverPort,
      serverFilesFrom: serverFilesFrom ?? this.serverFilesFrom,
      serverFilesTo: serverFilesTo ?? this.serverFilesTo,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'allowedChatIds': allowedChatIds,
    'allowedUserIds': allowedUserIds,
    'downloadingMessage': downloadingMessage,
    'runOnEmulator': runOnEmulator,
    'watchSeconds': watchSeconds,
    'serverExecutable': serverExecutable,
    'serverPort': serverPort,
    'serverFilesFrom': serverFilesFrom,
    'serverFilesTo': serverFilesTo,
  };

  factory TelegramIntakeSettings.fromJson(Map<String, Object?> json) {
    List<int> ids(String key) => [
      for (final value in (json[key] as List?) ?? const [])
        if (value is num) value.toInt() else ?int.tryParse('$value'),
    ];
    final message = (json['downloadingMessage'] as String?)?.trim() ?? '';
    final port = (json['serverPort'] as num?)?.toInt() ?? 8081;
    return TelegramIntakeSettings(
      enabled: json['enabled'] as bool? ?? false,
      allowedChatIds: ids('allowedChatIds'),
      allowedUserIds: ids('allowedUserIds'),
      downloadingMessage: message.isEmpty ? defaultDownloadingMessage : message,
      runOnEmulator: json['runOnEmulator'] as bool? ?? true,
      watchSeconds: ((json['watchSeconds'] as num?)?.toInt() ?? 20).clamp(
        5,
        300,
      ),
      serverExecutable: json['serverExecutable'] as String? ?? '',
      serverPort: port > 0 && port < 65536 ? port : 8081,
      serverFilesFrom: json['serverFilesFrom'] as String? ?? '',
      serverFilesTo: json['serverFilesTo'] as String? ?? '',
    );
  }
}

/// An `.aab` someone posted in a chat the bot can see.
class IndexedAab {
  const IndexedAab({
    required this.chatId,
    required this.messageId,
    required this.fileId,
    required this.fileUniqueId,
    required this.fileName,
    required this.date,
    this.fileSize,
    this.fromName = '',
  });

  final int chatId;
  final int messageId;
  final String fileId;

  /// Stable across bots and re-posts; the key the pick buttons carry.
  final String fileUniqueId;
  final String fileName;
  final int? fileSize;
  final String fromName;
  final DateTime date;

  Map<String, Object?> toJson() => {
    'chatId': chatId,
    'messageId': messageId,
    'fileId': fileId,
    'fileUniqueId': fileUniqueId,
    'fileName': fileName,
    'fileSize': fileSize,
    'fromName': fromName,
    'date': date.toIso8601String(),
  };

  static IndexedAab? fromJson(Object? json) {
    if (json is! Map) return null;
    final chatId = json['chatId'];
    final messageId = json['messageId'];
    final fileId = json['fileId'];
    final unique = json['fileUniqueId'];
    if (chatId is! num ||
        messageId is! num ||
        fileId is! String ||
        unique is! String) {
      return null;
    }
    return IndexedAab(
      chatId: chatId.toInt(),
      messageId: messageId.toInt(),
      fileId: fileId,
      fileUniqueId: unique,
      fileName: json['fileName'] as String? ?? 'app.aab',
      fileSize: (json['fileSize'] as num?)?.toInt(),
      fromName: json['fromName'] as String? ?? '',
      date:
          DateTime.tryParse(json['date'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Everything the bot keeps on disk, under `<bundle_check>/telegram/`:
/// settings, the update offset, the per-chat index of AABs, and the files
/// it fetched (newest [keepFiles] kept).
class TelegramIntakeStore {
  TelegramIntakeStore({
    required this.root,
    this.keepPerChat = 30,
    this.keepFiles = 6,
  });

  final Directory root;
  final int keepPerChat;
  final int keepFiles;

  File get _settingsFile => File(p.join(root.path, 'settings.json'));
  File get _stateFile => File(p.join(root.path, 'state.json'));
  File get _indexFile => File(p.join(root.path, 'index.json'));
  Directory get filesDirectory => Directory(p.join(root.path, 'files'));

  /// Working directory for a local server AMC starts itself.
  Directory get serverDirectory => Directory(p.join(root.path, 'server'));

  Future<TelegramIntakeSettings> readSettings() async {
    final json = await _readJson(_settingsFile);
    return json is Map
        ? TelegramIntakeSettings.fromJson(Map<String, Object?>.from(json))
        : const TelegramIntakeSettings();
  }

  Future<void> saveSettings(TelegramIntakeSettings value) =>
      _writeJson(_settingsFile, value.toJson());

  Future<int?> readOffset() async {
    final json = await _readJson(_stateFile);
    return json is Map ? (json['offset'] as num?)?.toInt() : null;
  }

  Future<void> saveOffset(int offset) =>
      _writeJson(_stateFile, {'offset': offset});

  Future<List<IndexedAab>> readIndex() async {
    final json = await _readJson(_indexFile);
    if (json is! List) return [];
    return [for (final item in json) ?IndexedAab.fromJson(item)];
  }

  /// Adds [entry] unless the same file is already listed for that chat, and
  /// keeps only the newest [keepPerChat] per chat.
  Future<void> addToIndex(IndexedAab entry) async {
    final all = await readIndex();
    all.removeWhere(
      (item) =>
          item.chatId == entry.chatId &&
          item.fileUniqueId == entry.fileUniqueId,
    );
    all.add(entry);
    all.sort((a, b) => b.date.compareTo(a.date));
    final perChat = <int, int>{};
    all.retainWhere((item) {
      final count = (perChat[item.chatId] ?? 0) + 1;
      perChat[item.chatId] = count;
      return count <= keepPerChat;
    });
    await _writeJson(_indexFile, [for (final item in all) item.toJson()]);
  }

  Future<List<IndexedAab>> indexFor(int chatId) async {
    return [
      for (final item in await readIndex())
        if (item.chatId == chatId) item,
    ];
  }

  /// Where a fetched file goes. Older fetches are removed first.
  Future<File> fileFor(IndexedAab entry) async {
    await filesDirectory.create(recursive: true);
    final existing = filesDirectory.listSync().whereType<File>().toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final old in existing.skip(keepFiles - 1)) {
      try {
        old.deleteSync();
      } on FileSystemException {
        continue;
      }
    }
    final safe = entry.fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File(p.join(filesDirectory.path, '${entry.fileUniqueId}_$safe'));
  }

  static Future<Object?> _readJson(File file) async {
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(await file.readAsString());
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _writeJson(File file, Object? value) async {
    await root.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    await temp.rename(file.path);
  }
}
