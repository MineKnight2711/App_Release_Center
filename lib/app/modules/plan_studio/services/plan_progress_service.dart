import '../models/work_item.dart';

class PlanProgress {
  PlanProgress(WorkItem item, List<WorkItem> all) {
    if (item.type == WorkType.plan) {
      final children = all.where((i) => i.parentId == item.id && !i.archived);
      total = children.length;
      done = children.where((i) => i.status == WorkStatus.done).length;
      blocked = children.where((i) => i.status == WorkStatus.blocked).length;
      next = children
          .where((i) => i.status != WorkStatus.done)
          .take(3)
          .map((i) => '${i.code} · ${i.title}')
          .toList();
      label = total == 0 ? 'Chưa có task' : '$done/$total task hoàn tất';
    } else {
      total = item.checklist.length;
      done = item.checklist.where((r) => r['done'] == true).length;
      next = item.checklist
          .where((r) => r['done'] != true)
          .take(3)
          .map((r) => r['text'] as String)
          .toList();
      label = total == 0 ? item.status.label : '$done/$total mục checklist';
    }
  }
  int total = 0, done = 0, blocked = 0;
  late final String label;
  List<String> next = [];
  double? get fraction => total == 0 ? null : done / total;
}
