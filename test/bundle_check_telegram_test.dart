import 'dart:io';

import 'package:app_management_center/app/models/telegram_release_settings.dart';
import 'package:app_management_center/app/modules/bundle_check/models/bundle_check_models.dart';
import 'package:app_management_center/app/modules/bundle_check/services/android_toolchain.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_check_service.dart';
import 'package:app_management_center/app/modules/bundle_check/services/bundle_check_store.dart';
import 'package:app_management_center/app/modules/bundle_check/telegram/local_bot_server.dart';
import 'package:app_management_center/app/modules/bundle_check/telegram/telegram_bot_client.dart';
import 'package:app_management_center/app/modules/bundle_check/telegram/telegram_intake_service.dart';
import 'package:app_management_center/app/modules/bundle_check/telegram/telegram_intake_store.dart';
import 'package:app_management_center/app/modules/bundle_check/telegram/telegram_report_formatter.dart';
import 'package:app_management_center/app/services/telegram_release_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'bundle_check_fixtures.dart';

const _group = -1001234;
const _token = '123:secret';

/// A Bot API server in memory: records every call in order and answers
/// from a script.
class _Telegram implements TelegramHttpClient {
  _Telegram({required this.filePath});

  /// What getFile returns — an absolute path, as a `--local` server does.
  String filePath;
  final fileErrors = <String>[];
  final calls = <(Uri, Map<String, Object?>)>[];
  final List<List<Map<String, Object?>>> updates = [];
  var _nextMessageId = 500;
  void Function()? onEmptyUpdates;

  Iterable<Map<String, Object?>> sent(String method) =>
      calls.where((c) => c.$1.pathSegments.last == method).map((c) => c.$2);

  List<String> get methods => [for (final c in calls) c.$1.pathSegments.last];

  @override
  Future<TelegramHttpResponse> postJson(
    Uri url,
    Map<String, Object?> body,
  ) async {
    calls.add((url, body));
    final method = url.pathSegments.last;
    Object? result = true;
    switch (method) {
      case 'getMe':
        result = {'id': 1, 'username': 'amc_aab_bot'};
      case 'sendMessage':
        result = {'message_id': _nextMessageId++};
      case 'getFile':
        if (fileErrors.isNotEmpty) {
          return TelegramHttpResponse(
            statusCode: 400,
            body: {
              'ok': false,
              'error_code': 400,
              'description': fileErrors.removeAt(0),
            },
          );
        }
        result = {'file_id': body['file_id'], 'file_path': filePath};
      case 'getUpdates':
        if (updates.isEmpty) {
          onEmptyUpdates?.call();
          result = const [];
        } else {
          result = updates.removeAt(0);
        }
    }
    return TelegramHttpResponse(
      statusCode: 200,
      body: {'ok': true, 'result': result},
    );
  }

  @override
  Future<TelegramHttpResponse> postMultipartFile(
    Uri url, {
    required Map<String, String> fields,
    required String fileField,
    required File file,
    required String fileName,
    required String contentType,
  }) async {
    calls.add((url, fields));
    return const TelegramHttpResponse(
      statusCode: 200,
      body: {'ok': true, 'result': {}},
    );
  }
}

class _NoDevices implements BundleProcessRunner {
  @override
  Future<BundleProcessResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    Duration timeout = const Duration(minutes: 2),
  }) async => const BundleProcessResult(
    exitCode: 0,
    stdout: 'List of devices attached\n',
  );

  @override
  Future<bool> startDetached(String executable, List<String> arguments) async =>
      false;
}

class _NoProjects implements BundleProjectSource {
  @override
  Future<List<BundleProjectCandidate>> candidates() async => const [];

  @override
  Future<KeystoreRef?> savedKeystore(BundleProjectCandidate candidate) async =>
      null;
}

Map<String, Object?> _message({
  int id = 10,
  int chat = _group,
  int from = 7,
  String text = '',
  Map<String, Object?>? document,
  Map<String, Object?>? replyTo,
  String type = 'supergroup',
}) => {
  'message_id': id,
  'date': 1790700000,
  'chat': {'id': chat, 'type': type, 'title': 'Release'},
  'from': {'id': from, 'first_name': 'Dat'},
  'text': ?(text.isEmpty ? null : text),
  'document': ?document,
  'reply_to_message': ?replyTo,
};

Map<String, Object?> _aab({
  String unique = 'AgADu1',
  String name = 'app-release.aab',
  int size = 120 * 1024 * 1024,
}) => {
  'file_id': 'BQAC-$unique',
  'file_unique_id': unique,
  'file_name': name,
  'file_size': size,
};

TgUpdate _update(
  int id, {
  Map<String, Object?>? message,
  Map<String, Object?>? callback,
}) => TgUpdate.fromJson({
  'update_id': id,
  'message': ?message,
  'callback_query': ?callback,
})!;

void main() {
  late Directory temp;
  late _Telegram telegram;
  late TelegramReleaseSettings release;
  late TelegramIntakeService service;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('bundle_telegram');
    // The "server's disk", where a --local server puts downloaded files.
    Directory(
      p.join(temp.path, 'server', 'documents'),
    ).createSync(recursive: true);
    final serverFile = writeAab(
      p.join(temp.path, 'server', 'documents', 'file_0.aab'),
      signatureBlock: uploadSignatureBlock,
    );
    telegram = _Telegram(filePath: serverFile.path);
    release = const TelegramReleaseSettings(
      chatId: '$_group',
      apiBaseUrl: 'http://127.0.0.1:8081',
    );
    service = TelegramIntakeService(
      store: TelegramIntakeStore(root: Directory(p.join(temp.path, 'tg'))),
      checker: BundleCheckService(
        store: BundleCheckStore(root: Directory(p.join(temp.path, 'store'))),
        projects: _NoProjects(),
        runner: _NoDevices(),
        tools: const JavaTools(java: 'java', keytool: 'keytool'),
        inspectInBackground: false,
      ),
      readToken: () async => _token,
      releaseSettings: () => release,
      saveReleaseSettings: (value) async => release = value,
      readServerCredentials: () async => ('12345', 'abcdef'),
      http: telegram,
      slowHttp: telegram,
      server: LocalBotServer(
        probe: (_) async => true,
        start: (_, _, _) async => true,
        sleep: (_) async {},
      ),
      sleep: (_) async {},
    );
    service.settings = const TelegramIntakeSettings(enabled: true);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('AAB gửi trong nhóm được ghi vào danh sách, nhóm lạ bị lờ đi', () async {
    await service.handleUpdate(_update(1, message: _message(document: _aab())));
    await service.handleUpdate(
      _update(
        2,
        message: _message(chat: -999, document: _aab(unique: 'x')),
      ),
    );
    final index = await service.store.readIndex();
    expect(index.single.fileName, 'app-release.aab');
    expect(index.single.chatId, _group);
    expect(telegram.sent('sendMessage'), isEmpty);
  });

  test(
    '/aab liệt kê file để chọn, bấm nút thì nói trước rồi mới tải',
    () async {
      await service.handleUpdate(
        _update(1, message: _message(document: _aab())),
      );
      await service.handleUpdate(
        _update(2, message: _message(id: 11, text: '/aab@amc_aab_bot')),
      );

      final list = telegram.sent('sendMessage').single;
      final keyboard =
          ((list['reply_markup'] as Map)['inline_keyboard'] as List).single
              as List;
      final button = keyboard.single as Map;
      expect(button['callback_data'], 'chk:AgADu1');
      expect(button['text'], contains('app-release.aab'));

      await service.handleUpdate(
        _update(
          3,
          callback: {
            'id': 'cb1',
            'data': 'chk:AgADu1',
            'from': {'id': 7, 'first_name': 'Dat'},
            'message': _message(id: 12),
          },
        ),
      );
      await service.idle();

      // The sentence goes out before the file is asked for.
      final methods = telegram.methods;
      final sentenceAt = telegram.calls.indexWhere(
        (c) =>
            c.$1.pathSegments.last == 'sendMessage' &&
            '${c.$2['text']}'.startsWith(
              TelegramIntakeSettings.defaultDownloadingMessage,
            ),
      );
      expect(sentenceAt, greaterThan(-1));
      expect(sentenceAt, lessThan(methods.indexOf('getFile')));
      expect(methods, contains('answerCallbackQuery'));

      final result = telegram.sent('sendMessage').last;
      expect('${result['text']}', contains('app-release.aab'));
      expect('${result['text']}', contains('vn.amc.demo'));
      // Replies go under the message that carried the file.
      expect((result['reply_parameters'] as Map)['message_id'], 10);
      // Every call went to the local server, none to the cloud.
      expect(telegram.calls.every((c) => c.$1.host == '127.0.0.1'), isTrue);
    },
  );

  const unavailable =
      'Bad Request: wrong file_id or the file is temporarily unavailable';

  test(
    'local retries interrupted downloads and checks the recovered AAB',
    () async {
      telegram.fileErrors.addAll([unavailable, unavailable]);
      await service.handleUpdate(
        _update(
          1,
          message: _message(
            text: '/check',
            replyTo: _message(id: 9, document: _aab()),
          ),
        ),
      );
      await service.idle();
      final requests = telegram.sent('getFile').toList();
      expect(requests, hasLength(3));
      expect(requests.map((body) => body['file_id']).toSet(), hasLength(1));
      expect(
        telegram.calls.every((call) => call.$1.host == '127.0.0.1'),
        isTrue,
      );
      expect(
        '${telegram.sent('sendMessage').last['text']}',
        contains('vn.amc.demo'),
      );
    },
  );

  test(
    'local stops after four unavailable responses with actionable error',
    () async {
      telegram.fileErrors.addAll(List.filled(5, unavailable));
      await service.handleUpdate(
        _update(
          1,
          message: _message(
            text: '/check',
            replyTo: _message(id: 9, document: _aab()),
          ),
        ),
      );
      await service.idle();
      expect(telegram.sent('getFile'), hasLength(4));
      expect(
        '${telegram.sent('sendMessage').last['text']}',
        contains('4 lần thử'),
      );
      expect(service.current, isNull);
    },
  );

  test('other getFile errors are not retried', () async {
    telegram.fileErrors.add('Bad Request: invalid file_id');
    await service.handleUpdate(
      _update(
        1,
        message: _message(
          text: '/check',
          replyTo: _message(id: 9, document: _aab()),
        ),
      ),
    );
    await service.idle();
    expect(telegram.sent('getFile'), hasLength(1));
    expect(
      '${telegram.sent('sendMessage').last['text']}',
      contains('invalid file_id'),
    );
  });

  test('câu báo trước khi tải chỉnh được', () async {
    service.settings = const TelegramIntakeSettings(
      enabled: true,
      downloadingMessage: 'Đang tải và kiểm tra aab',
    );
    await service.handleUpdate(
      _update(
        1,
        message: _message(
          text: '/check',
          replyTo: _message(id: 9, document: _aab()),
        ),
      ),
    );
    await service.idle();
    expect(
      '${telegram.sent('sendMessage').first['text']}',
      startsWith('Đang tải và kiểm tra aab\n📦 app-release.aab'),
    );
  });

  test('người ngoài danh sách không kích hoạt được, kể cả bằng nút', () async {
    service.settings = const TelegramIntakeSettings(
      enabled: true,
      allowedUserIds: [42],
    );
    await service.handleUpdate(_update(1, message: _message(document: _aab())));
    await service.handleUpdate(_update(2, message: _message(text: '/aab')));
    expect(telegram.sent('sendMessage'), isEmpty);

    await service.handleUpdate(
      _update(
        3,
        callback: {
          'id': 'cb',
          'data': 'chk:AgADu1',
          'from': {'id': 7},
          'message': _message(id: 12),
        },
      ),
    );
    await service.idle();
    expect(
      '${telegram.sent('answerCallbackQuery').single['text']}',
      contains('không có quyền'),
    );
    expect(telegram.methods, isNot(contains('getFile')));
  });

  test('trên cloud, file quá 20 MB bị từ chối trước khi tải', () async {
    release = const TelegramReleaseSettings(chatId: '$_group');
    await service.handleUpdate(
      _update(
        1,
        message: _message(
          text: '/check',
          replyTo: _message(id: 9, document: _aab()),
        ),
      ),
    );
    await service.idle();
    expect(telegram.methods, isNot(contains('getFile')));
    expect('${telegram.sent('sendMessage').last['text']}', contains('20 MB'));
    expect(telegram.calls.first.$1.host, 'api.telegram.org');
  });

  test('cùng file thì báo đang kiểm, file khác thì xếp hàng', () async {
    final first = _update(
      1,
      message: _message(
        text: '/check',
        replyTo: _message(id: 9, document: _aab()),
      ),
    );
    final again = _update(
      2,
      message: _message(
        text: '/check',
        replyTo: _message(id: 9, document: _aab()),
      ),
    );
    final other = _update(
      3,
      message: _message(
        text: '/check',
        replyTo: _message(
          id: 20,
          document: _aab(unique: 'AgADu2', name: 'b.aab'),
        ),
      ),
    );
    await service.handleUpdate(first);
    await service.handleUpdate(again);
    await service.handleUpdate(other);
    await service.idle();
    final texts = [
      for (final m in telegram.sent('sendMessage')) '${m['text']}',
    ];
    expect(texts, contains('app-release.aab đang được kiểm rồi.'));
    expect(texts.any((t) => t.startsWith('Đang xếp hàng (#2): b.aab')), isTrue);
  });

  test('vòng poll lưu offset sau mỗi update', () async {
    telegram.updates.add([
      {'update_id': 77, 'message': _message(document: _aab())},
    ]);
    telegram.onEmptyUpdates = () => service.stop();
    service.start();
    await service.stop();
    expect(await service.store.readOffset(), 78);
    final getUpdates = telegram.sent('getUpdates').first;
    expect(getUpdates['allowed_updates'], contains('callback_query'));
  });

  test('chuyển sang server local: logOut ở cloud, rồi getMe ở local', () async {
    release = const TelegramReleaseSettings(chatId: '$_group');
    // Off, so the move does not restart polling against the in-memory API.
    service.settings = const TelegramIntakeSettings();
    final username = await service.moveToLocalServer();
    expect(username, 'amc_aab_bot');
    expect(release.apiBaseUrl, 'http://127.0.0.1:8081');
    final logOut = telegram.calls.indexWhere(
      (c) => c.$1.pathSegments.last == 'logOut',
    );
    final getMe = telegram.calls.lastIndexWhere(
      (c) => c.$1.pathSegments.last == 'getMe',
    );
    expect(telegram.calls[logOut].$1.host, 'api.telegram.org');
    expect(telegram.calls[getMe].$1.host, '127.0.0.1');
    expect(logOut, lessThan(getMe));
  });

  group('Server local', () {
    test(
      'khởi động với --local, chỉ nghe 127.0.0.1, bí mật qua biến môi trường',
      () async {
        final exe = File(p.join(temp.path, 'telegram-bot-api.exe'))
          ..writeAsStringSync('');
        var up = false;
        late List<String> args;
        late Map<String, String> env;
        final server = LocalBotServer(
          probe: (_) async => up,
          start: (_, a, e) async {
            args = a;
            env = e;
            up = true;
            return true;
          },
          sleep: (_) async {},
        );
        final started = await server.ensureRunning(
          executable: exe.path,
          port: 8081,
          workDirectory: Directory(p.join(temp.path, 'server')),
          apiId: '12345',
          apiHash: 'abcdef',
        );
        expect(started, isTrue);
        expect(args, containsAll(['--local', '--http-ip-address=127.0.0.1']));
        expect(args.join(' '), isNot(contains('abcdef')));
        expect(env, {
          'TELEGRAM_API_ID': '12345',
          'TELEGRAM_API_HASH': 'abcdef',
        });
        // Already up: nothing is started twice.
        expect(
          await server.ensureRunning(
            executable: exe.path,
            port: 8081,
            workDirectory: temp,
            apiId: '1',
            apiHash: '2',
          ),
          isFalse,
        );
      },
    );
  });

  group('Tiện ích', () {
    test('lệnh bot, đường dẫn server, ánh xạ thư mục', () {
      expect(parseBotCommand('/check@amc_bot extra')?.name, 'check');
      expect(parseBotCommand('/check@amc_bot')?.bot, 'amc_bot');
      expect(parseBotCommand('hello /check'), isNull);
      expect(isAbsoluteServerPath('/var/lib/tg/doc.aab'), isTrue);
      expect(isAbsoluteServerPath(r'C:\tg\doc.aab'), isTrue);
      expect(isAbsoluteServerPath('documents/file_1.aab'), isFalse);
      expect(
        mapServerPath('/var/lib/tg/documents/a.aab', '/var/lib/tg', r'D:\tg'),
        p.join(r'D:\tg', 'documents', 'a.aab'),
      );
      expect(
        telegramMethodUri('http://127.0.0.1:8081/', 't', 'getMe').toString(),
        'http://127.0.0.1:8081/bott/getMe',
      );
      expect(
        telegramMethodUri('', 't', 'getMe').toString(),
        'https://api.telegram.org/bott/getMe',
      );
    });

    test('tin kết quả không mang giá trị env hay log dài', () {
      final report = BundleCheckReport(
        id: 'r',
        createdAt: DateTime(2026, 9, 30),
        sourcePath: 'a.aab',
        fileName: 'a.aab',
        fileSize: 1,
        sha256: 'x',
        packageName: 'vn.amc.demo',
        versionName: '1.0',
        versionCode: 1,
        minSdk: 24,
        targetSdk: 36,
        permissions: const [],
        abis: const [],
        estimatedArm64DownloadBytes: 0,
        results: const [
          CheckResult(
            id: 'E00',
            group: CheckGroup.env,
            status: CheckStatus.info,
            title: 'Env',
            items: ['API_KEY = AI••••ue'],
          ),
          CheckResult(
            id: 'E02',
            group: CheckGroup.env,
            status: CheckStatus.fail,
            title: 'Trỏ đúng môi trường',
            detail: 'Bundle trỏ tới máy dev.',
            items: ['API_URL → http://10.0.2.2/…'],
          ),
          CheckResult(
            id: 'R05',
            group: CheckGroup.run,
            status: CheckStatus.warn,
            title: 'Chạy ổn định',
            detail: 'Log có 1 lỗi.',
            items: ['flutter: Unhandled Exception: boom', '    #0 main'],
          ),
        ],
      );
      final text = formatCheckResult(report);
      expect(text, startsWith('❌ Có lỗi — a.aab'));
      expect(text, contains('E02 Trỏ đúng môi trường'));
      expect(text, isNot(contains('API_KEY')));
      expect(text, isNot(contains('10.0.2.2')));
      expect(text, contains('Unhandled Exception: boom'));
      expect(text, isNot(contains('#0 main')));
    });
  });
}
