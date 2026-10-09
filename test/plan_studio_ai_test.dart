import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_management_center/app/modules/plan_studio/controllers/plan_editor_controller.dart';
import 'package:app_management_center/app/modules/plan_studio/models/work_item.dart';
import 'package:app_management_center/app/modules/plan_studio/repositories/local_plan_repository.dart';
import 'package:app_management_center/app/modules/plan_studio/services/ollama_plan_service.dart';

class DelayedAi extends Ollama {
  final result = Completer<String>();
  final called = Completer<void>();
  @override
  Future<String> plan(
    String model,
    String source,
    String context,
    List<Map<String, String>> answers,
  ) {
    called.complete();
    return result.future;
  }
}

void main() {
  test('rejects malformed choices and missing technical sections', () async {
    expect(
      () => Question.fromJson({
        'question': 'Where?',
        'options': ['A', 'A'],
      }),
      throwsFormatException,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          request.uri.path == '/api/tags'
              ? {
                  'models': [
                    {'name': 'qwen3:8b', 'size': 1234},
                    {
                      'name': 'cloud-model',
                      'size': 1234,
                      'remote_host': 'remote',
                    },
                  ],
                }
              : {
                  'message': {
                    'content': jsonEncode({
                      'Business Requirement': 'only one section',
                    }),
                  },
                },
        ),
      );
      await request.response.close();
    });
    final ai = Ollama(baseUri: Uri.parse('http://127.0.0.1:${server.port}'));
    addTearDown(() async {
      ai.cancel();
      await subscription.cancel();
      await server.close(force: true);
    });
    expect(await ai.models(), ['qwen3:8b']);
    await expectLater(
      ai.plan('qwen3:8b', 'Requirement', '', []),
      throwsFormatException,
    );
  });

  test(
    'valid local response yields nine sections and confirmed context',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        await request.drain<void>();
        request.response.write(
          jsonEncode(
            request.uri.path == '/api/tags'
                ? {
                    'models': [
                      {'name': 'local', 'size': 12},
                    ],
                  }
                : {
                    'message': {
                      'content': jsonEncode({
                        for (final section in sections)
                          section: 'Nội dung $section',
                      }),
                    },
                  },
          ),
        );
        await request.response.close();
      });
      final ai = Ollama(baseUri: Uri.parse('http://127.0.0.1:${server.port}'));
      addTearDown(() async {
        ai.cancel();
        await subscription.cancel();
        await server.close(force: true);
      });
      final plan = await ai.plan('local', 'Yêu cầu gốc', 'Flutter', [
        {'question': 'Nền tảng?', 'answer': 'Android'},
      ]);
      expect(plan, contains('## 9. Test Cases'));
      expect(plan, contains('Nền tảng? → Android'));
    },
  );

  group('editor persistence and canceled AI', () {
    late LocalPlanRepository repository;
    late WorkItem item;
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('studio-editor-');
      repository = await LocalPlanRepository.open(
        path: '${directory.path}/studio.sqlite',
      );
      final project = await repository.ensureProject(directory.path);
      item = await repository.save(
        WorkItem(
          id: 'plan',
          projectId: project.id,
          title: 'Plan',
          type: WorkType.plan,
          body: 'Bản gốc',
          draft: {
            'snapshot': {
              'source': 'Requirement',
              'context': 'Flutter',
              'model': 'local',
            },
            'questions': [],
            'answers': [],
          },
        ),
      );
    });
    tearDown(() async {
      await repository.close();
      await directory.delete(recursive: true);
    });

    test('canceled late response cannot replace an edited plan', () async {
      final ai = DelayedAi();
      final editor = PlanEditorController(repository, item, ai: ai);
      addTearDown(editor.dispose);
      final request = editor.generate();
      await ai.called.future;
      editor.cancel();
      editor.change((i) => i.body = 'Bản đã sửa');
      ai.result.complete('Kết quả cũ');
      await request;
      expect(await editor.flush(), isTrue);
      expect((await repository.items()).single.body, 'Bản đã sửa');
      expect(editor.item.versions, isEmpty);
    });

    test(
      'regeneration preserves original version and does not mark plan done',
      () async {
        final ai = DelayedAi();
        final editor = PlanEditorController(repository, item, ai: ai);
        addTearDown(editor.dispose);
        final request = editor.generate();
        await ai.called.future;
        ai.result.complete('Plan mới');
        await request;
        final saved = (await repository.items()).single;
        expect(saved.versions.map((v) => v['body']), ['Bản gốc', 'Plan mới']);
        expect(saved.status, WorkStatus.backlog);
        expect(saved.draft['step'], 2);
      },
    );

    test(
      'deletion cancels pending autosave even with invalid unsaved edits',
      () async {
        final editor = PlanEditorController(repository, item);
        addTearDown(editor.dispose);
        editor.change((i) => i.title = '');
        await editor.delete();
        expect(editor.dirty, isFalse);
        expect(await editor.flush(), isTrue);
        expect(await repository.items(), isEmpty);
      },
    );

    test(
      'persistence failure keeps dirty text available for recovery',
      () async {
        final editor = PlanEditorController(repository, item);
        addTearDown(editor.dispose);
        await repository.move(item.id, item.revision, WorkStatus.ready);
        editor.change((i) => i.body = 'Nội dung chưa lưu');
        expect(await editor.flush(), isFalse);
        expect(editor.dirty, isTrue);
        expect(editor.item.body, 'Nội dung chưa lưu');
        expect(editor.error, contains('Ticket đã thay đổi'));
        expect((await repository.items()).single.body, 'Bản gốc');
      },
    );
  });
}
