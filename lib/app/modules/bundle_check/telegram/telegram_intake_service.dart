import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/models/telegram_release_settings.dart';
import 'package:app_management_center/app/services/telegram_release_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/bundle_check_models.dart';
import '../services/android_toolchain.dart';
import '../services/bundle_check_service.dart';
import '../services/bundle_inspector.dart';
import '../services/device_smoke_runner.dart';
import 'local_bot_server.dart';
import 'telegram_bot_client.dart';
import 'telegram_intake_store.dart';
import 'telegram_report_formatter.dart';

typedef FileDownloader =
    Future<void> Function(Uri url, File target, {required int maxBytes});

/// The cloud Bot API hands bots files up to this size and no bigger.
const cloudDownloadLimitBytes = 20 * 1024 * 1024;
const _maxBundleBytes = 2 * 1024 * 1024 * 1024;
const _listSize = 8;

class _Job {
  _Job(this.item, this.requestedBy);

  final IndexedAab item;
  final String requestedBy;
}

/// The Telegram side of the AAB checker.
///
/// Long-polls the bot, remembers every `.aab` posted in the chats it may
/// answer in, and on request — `/aab` then a button, `/check` in reply to a
/// file, or a file sent privately — says so in the chat, fetches the file,
/// checks it, optionally runs it on an emulator, and replies with the result.
/// One check at a time; later requests wait in line and are told so.
class TelegramIntakeService extends ChangeNotifier {
  TelegramIntakeService({
    required this.store,
    required this.checker,
    required Future<String?> Function() readToken,
    required TelegramReleaseSettings Function() releaseSettings,
    required Future<void> Function(TelegramReleaseSettings) saveReleaseSettings,
    required Future<(String, String)?> Function() readServerCredentials,
    TelegramHttpClient? http,
    TelegramHttpClient? slowHttp,
    FileDownloader? download,
    LocalBotServer? server,
    Future<void> Function(Duration)? sleep,
    DateTime Function()? now,
  }) : _readToken = readToken,
       _releaseSettings = releaseSettings,
       _saveReleaseSettings = saveReleaseSettings,
       _readServerCredentials = readServerCredentials,
       _http = http ?? DartTelegramHttpClient(),
       _slowHttp = slowHttp ?? LongTimeoutTelegramHttpClient(),
       _download = download ?? downloadToFile,
       server = server ?? LocalBotServer(),
       _sleep = sleep ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  final TelegramIntakeStore store;
  final BundleCheckService checker;
  final LocalBotServer server;
  final Future<String?> Function() _readToken;
  final TelegramReleaseSettings Function() _releaseSettings;
  final Future<void> Function(TelegramReleaseSettings) _saveReleaseSettings;
  final Future<(String, String)?> Function() _readServerCredentials;
  final TelegramHttpClient _http;
  final TelegramHttpClient _slowHttp;
  final FileDownloader _download;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _now;

  TelegramIntakeSettings settings = const TelegramIntakeSettings();
  bool running = false;
  String? botUsername;
  String? lastError;
  DateTime? lastPollAt;
  IndexedAab? current;
  final List<_Job> _queue = [];
  final List<String> activity = [];

  bool _stopRequested = false;
  bool _draining = false;
  Future<void>? _loop;

  int get queued => _queue.length;

  String get apiBaseUrl => _releaseSettings().apiBaseUrl;

  bool get usesLocalServer => apiBaseUrl.trim().isNotEmpty;

  /// Loads settings; brings the local server up when the bot lives there
  /// (release notifications need it even with the checker off); starts
  /// polling when enabled.
  Future<void> init() async {
    settings = await store.readSettings();
    notifyListeners();
    if (usesLocalServer) {
      try {
        await _ensureServer();
      } on LocalBotServerException catch (error) {
        _fail(error.message);
      }
    }
    if (settings.enabled) start();
  }

  Future<void> saveSettings(TelegramIntakeSettings value) async {
    final wasEnabled = settings.enabled;
    settings = value;
    await store.saveSettings(value);
    notifyListeners();
    if (value.enabled && !wasEnabled) start();
    if (!value.enabled && wasEnabled) await stop();
  }

  void start() {
    if (_loop != null) return;
    _stopRequested = false;
    _loop = _pollLoop().whenComplete(() {
      _loop = null;
      running = false;
      notifyListeners();
    });
  }

  /// Stops after the poll in flight returns (at most ~20 seconds).
  Future<void> stop() async {
    _stopRequested = true;
    notifyListeners();
    await _loop;
  }

  Future<void> restart() async {
    await stop();
    if (settings.enabled) start();
  }

  Future<TelegramBotClient> _client({bool slow = false}) async {
    final token = (await _readToken())?.trim() ?? '';
    if (token.isEmpty) {
      throw const TelegramBotException(
        'Chưa có bot token — nhập ở Options > AI Release Notes > Telegram.',
      );
    }
    return TelegramBotClient(
      http: slow ? _slowHttp : _http,
      token: token,
      apiBaseUrl: apiBaseUrl,
    );
  }

  Future<void> _pollLoop() async {
    running = true;
    lastError = null;
    notifyListeners();
    var backoff = 5;
    while (!_stopRequested) {
      try {
        if (usesLocalServer) await _ensureServer();
        final client = await _client();
        botUsername ??= await client.getMeUsername();
        final offset = await store.readOffset();
        final started = DateTime.now();
        final updates = await client.getUpdates(offset: offset);
        // A long poll that comes back empty at once means the server is not
        // holding the request; without a pause this would spin.
        if (updates.isEmpty &&
            DateTime.now().difference(started) < const Duration(seconds: 1)) {
          await _sleep(const Duration(seconds: 1));
        }
        lastPollAt = _now();
        lastError = null;
        backoff = 5;
        for (final update in updates) {
          await handleUpdate(update);
          await store.saveOffset(update.updateId + 1);
        }
        notifyListeners();
      } on TelegramBotException catch (error) {
        _fail(switch (error.code) {
          409 =>
            'Bot đang có webhook, hoặc một chương trình khác đang đọc update '
                '(409). Chỉ một nơi được đọc update của bot.',
          401 || 404 =>
            'Telegram từ chối token (${error.code}). Nếu vừa chuyển server, '
                'kiểm lại địa chỉ Bot API.',
          _ => error.message,
        });
        await _sleep(Duration(seconds: error.code == 409 ? 60 : backoff));
        backoff = (backoff * 2).clamp(5, 60);
      } on LocalBotServerException catch (error) {
        _fail(error.message);
        await _sleep(const Duration(seconds: 60));
      } on FileSystemException catch (error) {
        _fail('Lỗi ghi file của bot: ${error.message}');
        await _sleep(Duration(seconds: backoff));
      }
    }
  }

  /// Handles one update. Public so tests can feed updates without polling.
  Future<void> handleUpdate(TgUpdate update) async {
    final message = update.message;
    final callback = update.callbackQuery;
    if (message != null) await _onMessage(message);
    if (callback != null) await _onCallback(callback);
  }

  bool _chatAllowed(int chatId) {
    if (settings.allowedChatIds.isNotEmpty) {
      return settings.allowedChatIds.contains(chatId);
    }
    return '$chatId' == _releaseSettings().chatId.trim();
  }

  bool _userAllowed(int? userId) =>
      settings.allowedUserIds.isEmpty ||
      (userId != null && settings.allowedUserIds.contains(userId));

  bool _allowed(TgMessage message) {
    if (message.isPrivate) {
      // A private chat is only open to someone named explicitly.
      return _chatAllowed(message.chatId) ||
          (message.fromId != null &&
              settings.allowedUserIds.contains(message.fromId));
    }
    return _chatAllowed(message.chatId);
  }

  Future<void> _onMessage(TgMessage message) async {
    if (!_allowed(message)) return;

    for (final source in [message, ?message.replyTo]) {
      final document = source.document;
      if (document == null || !document.isAab) continue;
      await store.addToIndex(_indexed(source, document));
    }

    final command = parseBotCommand(message.text);
    if (command == null) {
      final document = message.document;
      if (message.isPrivate && document != null && document.isAab) {
        await _enqueue(_indexed(message, document), message.fromName);
      }
      return;
    }
    if (command.bot != null &&
        botUsername != null &&
        command.bot!.toLowerCase() != botUsername!.toLowerCase()) {
      return;
    }
    if (!_userAllowed(message.fromId)) return;

    final client = await _client();
    switch (command.name) {
      case 'check':
        final target = message.replyTo?.document?.isAab == true
            ? message.replyTo!
            : message.document?.isAab == true
            ? message
            : null;
        if (target != null) {
          await _enqueue(_indexed(target, target.document!), message.fromName);
        } else {
          await _sendList(client, message);
        }
      case 'aab':
        await _sendList(client, message);
      case 'status':
        await client.sendMessage(
          message.chatId,
          _statusText(),
          replyTo: message.messageId,
        );
      case 'start' || 'help':
        await client.sendMessage(message.chatId, _helpText());
    }
  }

  Future<void> _sendList(TelegramBotClient client, TgMessage message) async {
    final items = (await store.indexFor(
      message.chatId,
    )).take(_listSize).toList();
    await client.sendMessage(
      message.chatId,
      formatAabList(items),
      replyTo: message.messageId,
      keyboard: [
        for (final item in items)
          [TgInlineButton(aabButtonLabel(item), 'chk:${item.fileUniqueId}')],
      ],
    );
  }

  Future<void> _onCallback(TgCallbackQuery query) async {
    final client = await _client();
    final chatId = query.message?.chatId;
    if (!query.data.startsWith('chk:') || chatId == null) {
      await client.answerCallbackQuery(query.id);
      return;
    }
    if (!_chatAllowed(chatId) || !_userAllowed(query.fromId)) {
      await client.answerCallbackQuery(
        query.id,
        text: 'Bạn không có quyền kiểm file ở đây.',
      );
      return;
    }
    final unique = query.data.substring(4);
    final item = (await store.indexFor(
      chatId,
    )).where((i) => i.fileUniqueId == unique).firstOrNull;
    if (item == null) {
      await client.answerCallbackQuery(
        query.id,
        text: 'File này không còn trong danh sách.',
      );
      return;
    }
    await client.answerCallbackQuery(
      query.id,
      text: 'Đã nhận ${item.fileName}',
    );
    await _enqueue(item, query.fromName);
  }

  Future<void> _enqueue(IndexedAab item, String requestedBy) async {
    final client = await _client();
    final duplicate =
        current?.fileUniqueId == item.fileUniqueId ||
        _queue.any((job) => job.item.fileUniqueId == item.fileUniqueId);
    if (duplicate) {
      await client.sendMessage(
        item.chatId,
        '${item.fileName} đang được kiểm rồi.',
        replyTo: item.messageId,
      );
      return;
    }
    _queue.add(_Job(item, requestedBy));
    _log('Nhận yêu cầu kiểm ${item.fileName} từ $requestedBy');
    final ahead = _queue.length - 1 + (current == null ? 0 : 1);
    if (ahead > 0) {
      await client.sendMessage(
        item.chatId,
        'Đang xếp hàng (#${ahead + 1}): ${item.fileName}',
        replyTo: item.messageId,
      );
    }
    notifyListeners();
    unawaited(_drain());
  }

  /// Works through the queue one job at a time. Returns when it is empty.
  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        current = job.item;
        notifyListeners();
        await _process(job);
        current = null;
        notifyListeners();
      }
    } finally {
      _draining = false;
    }
  }

  /// Waits for queued checks to finish; for tests and for shutdown.
  Future<void> idle() async {
    while (_draining || _queue.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> _process(_Job job) async {
    final item = job.item;
    final client = await _client();
    try {
      // Said first, as asked: the chat knows before the download starts.
      await client.sendMessage(
        item.chatId,
        formatDownloading(settings.downloadingMessage, item),
        replyTo: item.messageId,
      );
      _log('Tải ${item.fileName}');
      final file = await _fetch(item);

      _log('Kiểm ${item.fileName}');
      var run = await checker.check(file.path);
      var deviceNote = '';
      if (settings.runOnEmulator) {
        (run, deviceNote) = await _runOnEmulator(run);
      }

      final report = run.report;
      await client.sendMessage(
        item.chatId,
        formatCheckResult(report, deviceNote: deviceNote),
        replyTo: item.messageId,
      );
      final screenshots = report.deviceRun?.screenshots ?? const <String>[];
      if (screenshots.isNotEmpty) {
        final job = await checker.store.jobDirectory(report.id);
        final shot = File(p.join(job.path, screenshots.last));
        if (shot.existsSync()) {
          await client.sendPhoto(
            item.chatId,
            shot,
            caption:
                '${report.fileName} trên ${report.deviceRun!.deviceLabel}, '
                'lúc kết thúc theo dõi.',
            replyTo: item.messageId,
          );
        }
      }
      _log('Xong ${item.fileName}: ${report.overall.label}');
    } on Exception catch (error) {
      final reason = switch (error) {
        TelegramBotException(:final message) => message,
        BundleInspectionException(:final message) => message,
        BundleToolException(:final message) => message,
        LocalBotServerException(:final message) => message,
        FileSystemException(:final message) => 'Lỗi file: $message',
        _ => '$error',
      };
      _log('Lỗi ${item.fileName}: $reason');
      try {
        await client.sendMessage(
          item.chatId,
          '❌ Không kiểm được ${item.fileName}: $reason',
          replyTo: item.messageId,
        );
      } on TelegramBotException {
        // Telegram itself is failing; the log above keeps the reason.
      }
    }
  }

  Future<File> _fetch(IndexedAab item) async {
    final size = item.fileSize ?? 0;
    if (!usesLocalServer && size > cloudDownloadLimitBytes) {
      throw TelegramBotException(
        'File ${formatBytes(size)} vượt giới hạn 20 MB của Bot API cloud. '
        'Chuyển bot sang local Bot API server trong AMC → Kiểm tra AAB → '
        'Bot Telegram.',
      );
    }
    // On a local server getFile returns only once the server has the whole
    // file, which for 170 MB takes a while — hence the slow client.
    final path = await _getFilePath(item);
    final target = await store.fileFor(item);
    if (isAbsoluteServerPath(path)) {
      final source = File(
        mapServerPath(path, settings.serverFilesFrom, settings.serverFilesTo),
      );
      if (!source.existsSync()) {
        throw TelegramBotException(
          'Server báo file ở $path nhưng máy này không thấy '
          '${source.path}. Server chạy trong container thì khai ánh xạ thư '
          'mục trong cài đặt bot.',
        );
      }
      await source.copy(target.path);
    } else {
      final token = (await _readToken())?.trim() ?? '';
      await _download(
        telegramFileUri(apiBaseUrl, token, path),
        target,
        maxBytes: _maxBundleBytes,
      );
    }
    return target;
  }

  Future<String> _getFilePath(IndexedAab item) async {
    // Keep the same bot and endpoint for every attempt. The local Bot API
    // also returns this 400 when a started download stops before completion.
    final client = await _client(slow: true);
    final local = usesLocalServer;
    const maxAttempts = 4;
    for (var attempt = 1; ; attempt++) {
      try {
        return await client.getFilePath(item.fileId);
      } on TelegramBotException catch (error) {
        if (!local ||
            error.code != 400 ||
            !error.message.toLowerCase().contains(
              'wrong file_id or the file is temporarily unavailable',
            )) {
          rethrow;
        }
        if (attempt == maxAttempts) {
          throw TelegramBotException(
            '${error.message}. Local Bot API chưa tải được file sau '
            '$maxAttempts lần thử. Thử gửi lại AAB từ máy vào đúng bot; '
            'nếu vẫn lỗi, kiểm tra log và kết nối mạng của local server. '
            'Lỗi này không đủ để kết luận bot thiếu quyền.',
            code: error.code,
          );
        }
        final delay = Duration(seconds: 1 << attempt);
        _log(
          'Local Bot API chưa tải được ${item.fileName}; '
          'thử lại ${attempt + 1}/$maxAttempts sau ${delay.inSeconds} giây',
        );
        await _sleep(delay);
      }
    }
  }

  /// Installs and opens the bundle on an emulator — never a physical phone,
  /// whose owner did not ask for a file from a chat to land on it.
  Future<(BundleCheckRun, String)> _runOnEmulator(BundleCheckRun run) async {
    try {
      final targets = await checker.listTargets();
      final prefs = await checker.store.readDevicePreferences();
      final emulators = targets.where((t) => t.isEmulator).toList();
      final target =
          emulators.where((t) => t.key == prefs.targetKey).firstOrNull ??
          emulators.where((t) => t.device?.isReady ?? false).firstOrNull ??
          emulators.firstOrNull;
      if (target == null) {
        return (run, 'Không có máy ảo nào nên bỏ qua phần chạy thử.');
      }
      _log('Chạy thử trên ${target.label}');
      final (updated, _) = await checker.runOnDevice(
        run,
        target,
        options: DeviceRunOptions(watchSeconds: settings.watchSeconds),
      );
      return (updated, '');
    } on BundleToolException catch (error) {
      return (run, 'Không chạy thử được: ${error.message}');
    }
  }

  Future<void> _ensureServer() async {
    final executable = settings.serverExecutable.trim();
    if (executable.isEmpty) return; // Run by someone else, e.g. Docker.
    final credentials = await _readServerCredentials();
    if (credentials == null) {
      throw const LocalBotServerException(
        'Thiếu api_id / api_hash để chạy local Bot API server.',
      );
    }
    final started = await server.ensureRunning(
      executable: executable,
      port: settings.serverPort,
      workDirectory: store.serverDirectory,
      apiId: credentials.$1,
      apiHash: credentials.$2,
    );
    if (started) _log('Đã khởi động local Bot API server');
  }

  /// Moves the bot from Telegram's cloud to the local server: starts the
  /// server, logs the bot out of the cloud, and checks it answers locally.
  /// The cloud will not take the bot back for 10 minutes afterwards.
  Future<String> moveToLocalServer() async {
    final wasRunning = _loop != null;
    await stop();
    try {
      await _ensureServer();
      if (!await server.isUp(settings.serverPort)) {
        throw LocalBotServerException(
          'Không thấy local Bot API server ở ${settings.localServerUrl}.',
        );
      }
      final token = (await _readToken())?.trim() ?? '';
      final cloud = TelegramBotClient(http: _http, token: token);
      try {
        await cloud.logOut();
      } on TelegramBotException catch (error) {
        // Already logged out of the cloud is the state we want.
        if (!error.message.toLowerCase().contains('logged out')) rethrow;
      }
      final local = TelegramBotClient(
        http: _http,
        token: token,
        apiBaseUrl: settings.localServerUrl,
      );
      String? username;
      for (var attempt = 0; attempt < 5 && username == null; attempt++) {
        try {
          username = await local.getMeUsername();
        } on TelegramBotException {
          await _sleep(const Duration(seconds: 2));
        }
      }
      if (username == null) {
        throw const TelegramBotException(
          'Bot đã rời cloud nhưng chưa đăng nhập được vào server local. Xem '
          'server.log; cloud chỉ nhận lại bot sau 10 phút.',
        );
      }
      await _saveReleaseSettings(
        _releaseSettings().copyWith(apiBaseUrl: settings.localServerUrl),
      );
      botUsername = username;
      _log('Bot @$username đã chuyển sang ${settings.localServerUrl}');
      return username;
    } finally {
      if (wasRunning || settings.enabled) start();
      notifyListeners();
    }
  }

  /// Moves the bot back to the cloud. Telegram may refuse it for up to 10
  /// minutes after it last left.
  Future<void> moveToCloud() async {
    final wasRunning = _loop != null;
    await stop();
    try {
      try {
        await (await _client()).logOut();
      } on TelegramBotException {
        // The local server may already be gone; the cloud is what matters.
      }
      await _saveReleaseSettings(_releaseSettings().copyWith(apiBaseUrl: ''));
      botUsername = null;
      _log('Bot đã quay về Bot API cloud');
    } finally {
      if (wasRunning || settings.enabled) start();
      notifyListeners();
    }
  }

  Future<String> testConnection() async {
    if (usesLocalServer) await _ensureServer();
    final username = await (await _client()).getMeUsername();
    botUsername = username;
    notifyListeners();
    return username;
  }

  IndexedAab _indexed(TgMessage message, TgDocument document) {
    return IndexedAab(
      chatId: message.chatId,
      messageId: message.messageId,
      fileId: document.fileId,
      fileUniqueId: document.fileUniqueId,
      fileName: document.fileName,
      fileSize: document.fileSize,
      fromName: message.fromName,
      date: message.date,
    );
  }

  String _statusText() {
    final busy = current;
    return [
      busy == null ? 'Rảnh.' : 'Đang kiểm ${busy.fileName}.',
      if (_queue.isNotEmpty) '${_queue.length} file đang chờ.',
      'Server: ${usesLocalServer ? 'local Bot API' : 'Telegram cloud (≤ 20 MB)'}.',
    ].join('\n');
  }

  String _helpText() {
    return 'Bot kiểm tra AAB của App Management Center.\n'
        '/aab — chọn một file .aab đã gửi trong nhóm để kiểm tra\n'
        '/check — reply vào tin có file .aab để kiểm ngay\n'
        '/status — xem bot đang làm gì';
  }

  void _fail(String message) {
    lastError = message;
    _log(message);
    notifyListeners();
  }

  void _log(String line) {
    final time = _now();
    String two(int v) => v.toString().padLeft(2, '0');
    activity.insert(0, '${two(time.hour)}:${two(time.minute)} $line');
    if (activity.length > 40) activity.removeLast();
    notifyListeners();
  }
}

class BotCommand {
  const BotCommand(this.name, this.bot);

  final String name;

  /// The `@bot` a command was addressed to in a group, if any.
  final String? bot;
}

/// `/check@amc_bot args` → `check`, `amc_bot`. Null for plain text.
BotCommand? parseBotCommand(String text) {
  final match = RegExp(
    r'^/([A-Za-z0-9_]+)(?:@([A-Za-z0-9_]+))?(?:\s|$)',
  ).firstMatch(text.trim());
  if (match == null) return null;
  return BotCommand(match.group(1)!.toLowerCase(), match.group(2));
}

/// `file_path` from a `--local` server is absolute on the server's disk.
bool isAbsoluteServerPath(String path) =>
    path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

String mapServerPath(String path, String from, String to) {
  if (from.isEmpty || !path.startsWith(from)) return path;
  final rest = path.substring(from.length).replaceAll('/', p.separator);
  return p.join(to, rest.replaceFirst(RegExp(r'^[\\/]+'), ''));
}

/// Streams [url] to [target], refusing anything over [maxBytes].
Future<void> downloadToFile(
  Uri url,
  File target, {
  required int maxBytes,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final partial = File('${target.path}.part');
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != 200) {
      throw TelegramBotException('Tải file lỗi HTTP ${response.statusCode}.');
    }
    final sink = partial.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.timeout(const Duration(minutes: 2))) {
        received += chunk.length;
        if (received > maxBytes) {
          throw const TelegramBotException('File lớn hơn giới hạn cho phép.');
        }
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
    if (target.existsSync()) await target.delete();
    await partial.rename(target.path);
  } on SocketException catch (error) {
    throw TelegramBotException('Lỗi mạng khi tải file: ${error.message}');
  } on TimeoutException {
    throw const TelegramBotException('Tải file quá hạn.');
  } finally {
    client.close(force: true);
    if (partial.existsSync()) await partial.delete();
  }
}

/// Like [DartTelegramHttpClient] but waits up to 15 minutes, for the
/// `getFile` call a local server answers only once the file is on its disk.
class LongTimeoutTelegramHttpClient implements TelegramHttpClient {
  LongTimeoutTelegramHttpClient({DartTelegramHttpClient? uploads})
    : _uploads = uploads ?? DartTelegramHttpClient();

  final DartTelegramHttpClient _uploads;

  @override
  Future<TelegramHttpResponse> postJson(
    Uri url,
    Map<String, Object?> body,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(url);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(
        const Duration(minutes: 15),
      );
      final raw = await response.transform(utf8.decoder).join();
      Object? decoded;
      try {
        decoded = raw.trim().isEmpty ? null : jsonDecode(raw);
      } on FormatException {
        decoded = raw;
      }
      return TelegramHttpResponse(
        statusCode: response.statusCode,
        body: decoded,
      );
    } on TimeoutException {
      throw const TelegramReleaseNotificationException(
        'Server Bot API không trả file trong 15 phút.',
      );
    } on SocketException catch (error) {
      throw TelegramReleaseNotificationException(
        'Lỗi mạng khi gọi Bot API: ${error.message}',
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<TelegramHttpResponse> postMultipartFile(
    Uri url, {
    required Map<String, String> fields,
    required String fileField,
    required File file,
    required String fileName,
    required String contentType,
  }) {
    return _uploads.postMultipartFile(
      url,
      fields: fields,
      fileField: fileField,
      file: file,
      fileName: fileName,
      contentType: contentType,
    );
  }
}
