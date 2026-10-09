import 'package:flutter/foundation.dart';
import '../models/work_item.dart';
import '../repositories/plan_repository.dart';
import '../repositories/local_plan_repository.dart';
import '../models/plan_reminder.dart';

class PlanBoardController extends ChangeNotifier {
  PlanBoardController(this.repository);
  final PlanRepository repository;
  List<StudioProject> projects = [];
  List<WorkItem> items = [];
  List<PlanReminder> reminders = [];
  bool loading = true;
  bool writing = false;
  String? error;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    _notify();
    try {
      projects = await repository.projects();
      items = await repository.items();
      if (repository case final LocalPlanRepository local) {
        reminders = await local.reminders.all();
      }
    } catch (e) {
      error = '$e';
    }
    loading = false;
    _notify();
  }

  Future<T> commit<T>(Future<T> Function() write) async {
    if (writing) throw StateError('Đang lưu, vui lòng thử lại sau.');
    writing = true;
    _notify();
    try {
      final result = await write();
      items = await repository.items();
      if (repository case final LocalPlanRepository local) {
        reminders = await local.reminders.all();
      }
      projects = await repository.projects();
      return result;
    } finally {
      writing = false;
      _notify();
    }
  }

  List<WorkItem> children(String id) =>
      items.where((i) => i.parentId == id && !i.archived).toList();
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
