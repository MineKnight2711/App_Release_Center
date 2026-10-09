import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/work_item.dart';
import '../repositories/plan_repository.dart';
import '../services/ollama_plan_service.dart';

class PlanEditorController extends ChangeNotifier {
  PlanEditorController(this.repository, WorkItem snapshot, {Ollama? ai})
    : item = snapshot.clone(),
      ai = ai ?? Ollama();
  final PlanRepository repository;
  final Ollama ai;
  WorkItem item;
  bool dirty = false, saving = false, busy = false;
  String? error;
  List<String> models = [];
  Timer? _timer;
  Future<bool>? _pending;
  int _edit = 0, _generation = 0;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void change(void Function(WorkItem) edit) {
    edit(item);
    dirty = true;
    _edit++;
    error = null;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), flush);
    _notify();
  }

  Future<bool> flush() {
    _timer?.cancel();
    return _pending ??= _save().whenComplete(() => _pending = null);
  }

  Future<void> delete() async {
    cancel();
    _timer?.cancel();
    // A save already in flight must finish before the deletion transaction.
    // Unsaved edits need not be valid when the user is deleting the ticket.
    await _pending;
    await repository.delete(item.id, item.revision);
    dirty = false;
    _notify();
  }

  Future<bool> _save() async {
    saving = true;
    _notify();
    try {
      while (dirty) {
        final edit = _edit;
        final saved = await repository.save(item.clone());
        item.number = saved.number;
        item.revision = saved.revision;
        item.activity = saved.activity;
        item.updatedAt = saved.updatedAt;
        item.completedAt = saved.completedAt;
        item.dueHistory = saved.dueHistory;
        if (edit == _edit) dirty = false;
      }
      error = null;
      return true;
    } catch (e) {
      error = '$e';
      return false;
    } finally {
      saving = false;
      _notify();
    }
  }

  Future<void> loadModels() => _work(() async {
    final token = _generation;
    final available = await ai.models();
    if (!_valid(token)) return;
    models = available;
    if (models.isEmpty) throw StateError('Ollama chưa có model local.');
    if (!models.contains(item.draft['model'])) {
      change(
        (i) => i.draft['model'] = models.contains('qwen3:8b')
            ? 'qwen3:8b'
            : models.first,
      );
    }
  });

  Future<void> clarify() => _work(() async {
    final token = _generation;
    final source = (item.draft['source'] as String? ?? '').trim();
    final context = item.draft['context'] as String? ?? '';
    final model = item.draft['model'] as String?;
    if (source.isEmpty || model == null) {
      throw StateError('Nhập yêu cầu và chọn model local.');
    }
    if (source.length + context.length > 14000) {
      throw StateError('Tối đa 14.000 ký tự yêu cầu và context.');
    }
    if (!await flush() || !_valid(token)) return;
    final questions = await ai.questions(model, source, context);
    if (!_valid(token)) return;
    change((i) {
      i.draft['questions'] = questions
          .map((q) => {'question': q.text, 'options': q.options})
          .toList();
      i.draft['answers'] = List.filled(questions.length, '');
      i.draft['step'] = 1;
      i.draft['snapshot'] = {
        'source': source,
        'context': context,
        'model': model,
      };
    });
    await flush();
    if (questions.isEmpty && _valid(token)) await _generate(token);
  });

  Future<void> generate() => _work(() => _generate(_generation));
  Future<void> _generate(int token) async {
    final snapshot = Map<String, dynamic>.from(
      item.draft['snapshot'] as Map? ?? {},
    );
    if (snapshot.isEmpty) throw StateError('Bắt đầu từ bước Làm rõ yêu cầu.');
    final questions = item.draft['questions'] as List? ?? [];
    final answers = item.draft['answers'] as List? ?? [];
    if (answers.length != questions.length ||
        answers.any((a) => a.toString().trim().isEmpty)) {
      throw StateError('Trả lời đủ câu hỏi, hoặc chọn Chưa rõ.');
    }
    final confirmed = <Map<String, String>>[
      for (var n = 0; n < questions.length; n++)
        {
          'question': questions[n]['question'] as String,
          'answer': answers[n] as String,
        },
    ];
    if (!await flush() || !_valid(token)) return;
    final body = await ai.plan(
      snapshot['model'] as String,
      snapshot['source'] as String,
      snapshot['context'] as String,
      confirmed,
    );
    if (!_valid(token)) return;
    change((i) {
      if (i.body.isNotEmpty &&
          (i.versions.isEmpty || i.versions.last['body'] != i.body)) {
        _version(i, 'Trước khi tạo lại');
      }
      i.body = body;
      i.draft['step'] = 2;
      _version(i, 'Ollama / ${snapshot['model']}');
    });
    await flush();
  }

  void _version(WorkItem i, String label) => i.versions.add({
    'id': const Uuid().v4(),
    'body': i.body,
    'at': DateTime.now().toUtc().toIso8601String(),
    'label': label,
    'input': jsonDecode(jsonEncode(i.draft)),
  });
  void checkpoint() => change((i) => _version(i, 'Bản chỉnh sửa'));
  bool _valid(int token) => !_disposed && busy && token == _generation;
  Future<void> _work(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    final token = ++_generation;
    _notify();
    try {
      await action();
    } catch (e) {
      if (_valid(token)) error = '$e';
    } finally {
      if (token == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  void cancel() {
    _generation++;
    ai.cancel();
    busy = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    cancel();
    super.dispose();
  }
}
