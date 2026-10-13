import 'dart:convert';
import 'dart:io';

import 'package:app_management_center/app/data/amc_api_client.dart';
import 'package:app_management_center/app/models/release_project.dart';
import 'package:app_management_center/app/services/release_note_generation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  group('release note app name', () {
    test('parses literal AndroidManifest label', () {
      final label = parseAndroidManifestLabel('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application
      android:name=".App"
      android:label="Customer Portal" />
</manifest>
''');

      expect(label, 'Customer Portal');
    });

    test('resolves AndroidManifest app_name string resource', () async {
      final directory = await Directory.systemTemp.createTemp(
        'app_management_center_release_notes_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });

      await File(
        p.join(
          directory.path,
          'android',
          'app',
          'src',
          'main',
          'AndroidManifest.xml',
        ),
      ).create(recursive: true);
      await File(
        p.join(
          directory.path,
          'android',
          'app',
          'src',
          'main',
          'AndroidManifest.xml',
        ),
      ).writeAsString('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application android:label="@string/app_name" />
</manifest>
''');

      await File(
        p.join(
          directory.path,
          'android',
          'app',
          'src',
          'main',
          'res',
          'values',
          'strings.xml',
        ),
      ).create(recursive: true);
      await File(
        p.join(
          directory.path,
          'android',
          'app',
          'src',
          'main',
          'res',
          'values',
          'strings.xml',
        ),
      ).writeAsString('''
<resources>
  <string name="app_name">VNeTrip &amp; Friends</string>
</resources>
''');

      final name = await readAndroidAppDisplayName(directory.path);

      expect(name, 'VNeTrip & Friends');
    });

    test(
      'falls back to project directory when Android label is absent',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'demo_release_notes_',
        );
        addTearDown(() async {
          if (directory.existsSync()) {
            await directory.delete(recursive: true);
          }
        });

        final name = await resolveReleaseNoteAppName(
          ReleaseProject(
            path: p.join(directory.path, 'my_android_app'),
            scripts: const [],
            fastlaneLanes: const [],
            hasLegacyDistributionPrompt: false,
            hasPlayReleaseTools: true,
          ),
        );

        expect(name, 'My Android App');
      },
    );
  });

  group('generated release note validation', () {
    test('accepts complete user-facing notes', () {
      expect(
        isUsableGeneratedReleaseNote(
          notes:
              'Cảm ơn bạn đã tin tưởng sử dụng VNeTrip. Phiên bản mới cải thiện '
              'trải nghiệm tìm đường và hỗ trợ đa ngôn ngữ thuận tiện hơn. '
              'Hãy cập nhật phiên bản mới để trải nghiệm nhé.',
          appDisplayName: 'VNeTrip',
        ),
        isTrue,
      );
    });

    test('rejects truncated thank-you openings', () {
      expect(
        isUsableGeneratedReleaseNote(
          notes: 'Cảm ơn bạn đã tin tưởng sử dụng',
          appDisplayName: 'VNeTrip',
        ),
        isFalse,
      );
    });

    test('rejects hash-only and planning leak outputs', () {
      expect(
        isUsableGeneratedReleaseNote(
          notes: '`1f4ef85`, `',
          appDisplayName: 'VNeTrip',
        ),
        isFalse,
      );
      expect(
        isUsableGeneratedReleaseNote(
          notes:
              '4. **Final Polish (No markdown, plain text):**\n'
              'Cảm ơn bạn đã tin tưởng sử dụng VNeTrip.',
          appDisplayName: 'VNeTrip',
        ),
        isFalse,
      );
    });
  });

  group('Gemini quota fallback', () {
    late Directory repo;
    late _GeminiStub gemini;

    setUp(() async {
      repo = await _gitRepoWithCommit('feat: faster checkout');
    });

    tearDown(() async {
      await gemini.close();
      await repo.delete(recursive: true);
    });

    Future<GeneratedReleaseNotes> generate(ReleaseNoteFallbackModel? fallback) {
      return ReleaseNoteGenerationService(
        quotaFallback: fallback,
        geminiEndpoint: gemini.endpoint,
      ).generate(
        project: ReleaseProject(
          path: repo.path,
          scripts: const [],
          fastlaneLanes: const [],
          hasLegacyDistributionPrompt: false,
          hasPlayReleaseTools: false,
        ),
        apiKey: 'gemini-key',
        customPrompt: '',
      );
    }

    test('hands the note, retry included, to Workers AI on a 429', () async {
      gemini = await _GeminiStub.start(429, {
        'error': {'status': 'RESOURCE_EXHAUSTED', 'message': 'Quota exceeded'},
      });
      final fallback = _FakeFallback([
        (_) => 'Cảm ơn bạn.', // Too short: the service asks again.
        (app) =>
            'Cảm ơn bạn đã tin tưởng sử dụng $app. Thanh toán giờ nhanh hơn. '
            'Hãy cập nhật ngay để trải nghiệm nhé.',
      ]);

      final result = await generate(fallback);

      expect(result.usedQuotaFallback, isTrue);
      expect(result.notes, contains('Thanh toán giờ nhanh hơn.'));
      expect(gemini.requests, 1, reason: 'the retry skips the spent Gemini');
      expect(fallback.instructions, hasLength(2));
      expect(fallback.instructions.first, contains('release notes'));
      expect(fallback.inputs.first, contains('feat: faster checkout'));
    });

    test('reports the quota error when there is no fallback', () async {
      gemini = await _GeminiStub.start(429, {
        'error': {'message': 'Quota exceeded'},
      });

      await expectLater(
        generate(null),
        throwsA(
          isA<GeminiQuotaExceededException>().having(
            (error) => error.message,
            'message',
            contains('Đã vượt giới hạn gọi Gemini (429)'),
          ),
        ),
      );
    });

    test('keeps other Gemini errors as they are', () async {
      gemini = await _GeminiStub.start(500, {
        'error': {'message': 'boom'},
      });
      final fallback = _FakeFallback([]);

      await expectLater(
        generate(fallback),
        throwsA(
          isA<ReleaseNoteGenerationException>().having(
            (error) => error.message,
            'message',
            startsWith('Dịch vụ Gemini lỗi'),
          ),
        ),
      );
      expect(fallback.inputs, isEmpty);
    });

    test('explains both failures when Workers AI fails too', () async {
      gemini = await _GeminiStub.start(429, {
        'error': {'message': 'Quota exceeded'},
      });
      final fallback = _FakeFallback([
        (_) => throw const ReleaseNoteGenerationException(
          'Workers AI đã hết lượt miễn phí hôm nay.',
        ),
      ]);

      await expectLater(
        generate(fallback),
        throwsA(
          isA<ReleaseNoteGenerationException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Đã vượt giới hạn gọi Gemini'),
              contains('Workers AI dự phòng cũng lỗi'),
              contains('hết lượt miễn phí'),
            ),
          ),
        ),
      );
    });
  });

  group('WorkersAiReleaseNoteModel', () {
    WorkersAiReleaseNoteModel model(
      http.Response Function(http.Request) reply,
    ) {
      return WorkersAiReleaseNoteModel(
        AmcApiClient(
          baseUrl: Uri.parse('https://api.example.com'),
          readToken: () async => 'amc_token',
          httpClient: MockClient((request) async => reply(request)),
        ),
      );
    }

    test('posts the prompt and returns the text', () async {
      late http.Request sent;
      final text = await model((request) {
        sent = request;
        return http.Response(
          jsonEncode({'text': 'Ghi chú', 'model': 'm'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }).generate(instructions: 'rules', input: 'commits');

      expect(text, 'Ghi chú');
      expect(sent.url.path, '/v1/ai/release-notes');
      expect(jsonDecode(sent.body), {
        'instructions': 'rules',
        'input': 'commits',
      });
    });

    test('turns server errors into user-facing messages', () async {
      Future<String> failWith(int status, String code) {
        return model(
              (_) => http.Response(
                jsonEncode({
                  'error': {'code': code, 'message': 'x'},
                }),
                status,
              ),
            )
            .generate(instructions: '', input: 'commits')
            .then((_) => '', onError: (Object error) => '$error');
      }

      expect(
        await failWith(429, 'ai-quota-exceeded'),
        'Workers AI đã hết lượt miễn phí hôm nay.',
      );
      expect(
        await failWith(401, 'unauthenticated'),
        'Cần đăng nhập AMC để dùng Workers AI.',
      );
    });
  });
}

/// A local stand-in for Gemini that answers every request the same way.
class _GeminiStub {
  _GeminiStub._(this._server);

  final HttpServer _server;
  int requests = 0;

  Uri get endpoint =>
      Uri.parse('http://127.0.0.1:${_server.port}/v1beta/interactions');

  static Future<_GeminiStub> start(int status, Object body) async {
    final stub = _GeminiStub._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    stub._server.listen((request) async {
      stub.requests++;
      await request.drain<void>();
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    });
    return stub;
  }

  Future<void> close() => _server.close(force: true);
}

class _FakeFallback implements ReleaseNoteFallbackModel {
  _FakeFallback(this._answers);

  /// Each answer gets the app name the prompt asked for.
  final List<String Function(String appName)> _answers;
  final instructions = <String>[];
  final inputs = <String>[];

  @override
  Future<String> generate({
    required String instructions,
    required String input,
  }) async {
    this.instructions.add(instructions);
    inputs.add(input);
    final appName = RegExp(
      r'App display name: (.+)',
    ).firstMatch(input)!.group(1)!.trim();
    return _answers[inputs.length - 1](appName);
  }
}

Future<Directory> _gitRepoWithCommit(String message) async {
  final directory = await Directory.systemTemp.createTemp('amc_release_git_');
  Future<void> git(List<String> arguments) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: directory.path,
    );
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')}: ${result.stderr}');
    }
  }

  await git(['init', '-q']);
  await git([
    '-c',
    'user.email=dev@example.com',
    '-c',
    'user.name=Dev',
    'commit',
    '--allow-empty',
    '-q',
    '-m',
    message,
  ]);
  return directory;
}
