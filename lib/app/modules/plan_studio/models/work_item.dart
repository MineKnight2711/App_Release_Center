import 'dart:convert';

enum WorkType { plan, task, note }

enum WorkStatus {
  backlog('Chưa xử lý'),
  ready('Sẵn sàng'),
  inProgress('Đang làm'),
  blocked('Bị chặn'),
  review('Chờ kiểm tra'),
  done('Hoàn tất');

  const WorkStatus(this.label);
  final String label;
}

class StudioProject {
  const StudioProject(this.id, this.path, this.name);
  final String id;
  final String path;
  final String name;
  Map<String, Object?> toJson() => {'id': id, 'path': path, 'name': name};
  factory StudioProject.fromJson(Map<String, dynamic> json) => StudioProject(
    json['id'] as String,
    json['path'] as String,
    json['name'] as String,
  );
}

/// Detached editor snapshots. The repository checks revision before committing.
class WorkItem {
  WorkItem({
    required this.id,
    required this.projectId,
    required this.title,
    this.type = WorkType.task,
    this.number = 0,
    this.status = WorkStatus.backlog,
    this.body = '',
    this.priority = 'P2',
    this.parentId,
    this.sourceRevisionId,
    this.order = 0,
    this.revision = 0,
    this.blockedReason = '',
    this.archived = false,
    String? createdAt,
    String? updatedAt,
    this.completedAt,
    this.dueAtUtc,
    this.dueAllDay = false,
    List<Map<String, dynamic>>? dueHistory,
    List<String>? labels,
    List<Map<String, dynamic>>? checklist,
    List<Map<String, dynamic>>? notes,
    List<Map<String, dynamic>>? activity,
    List<Map<String, dynamic>>? versions,
    Map<String, dynamic>? draft,
  }) : createdAt = createdAt ?? DateTime.now().toUtc().toIso8601String(),
       updatedAt = updatedAt ?? DateTime.now().toUtc().toIso8601String(),
       labels = labels ?? [],
       checklist = checklist ?? [],
       notes = notes ?? [],
       activity = activity ?? [],
       versions = versions ?? [],
       draft = draft ?? {},
       dueHistory = dueHistory ?? [];

  final String id;
  final String projectId;
  int number;
  String title;
  WorkType type;
  WorkStatus status;
  String body;
  String priority;
  String? parentId;
  String? sourceRevisionId;
  int order;
  int revision;
  String blockedReason;
  bool archived;
  final String createdAt;
  String updatedAt;
  String? completedAt;
  String? dueAtUtc;

  /// Date-only deadline: [dueAtUtc] holds the end of that local day.
  bool dueAllDay;

  /// Reschedules of an existing deadline: `{from, to, at}`, all UTC ISO.
  List<Map<String, dynamic>> dueHistory;
  List<String> labels;
  List<Map<String, dynamic>> checklist;
  List<Map<String, dynamic>> notes;
  List<Map<String, dynamic>> activity;
  List<Map<String, dynamic>> versions;
  Map<String, dynamic> draft;

  String get code => 'MPS-${number.toString().padLeft(3, '0')}';
  DateTime? get dueAt => dueAtUtc == null ? null : DateTime.parse(dueAtUtc!);
  WorkItem clone() => WorkItem.fromJson(
    jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'number': number,
    'title': title,
    'type': type.name,
    'status': status.name,
    'body': body,
    'priority': priority,
    'parentId': parentId,
    'sourceRevisionId': sourceRevisionId,
    'order': order,
    'revision': revision,
    'blockedReason': blockedReason,
    'archived': archived,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'completedAt': completedAt,
    'dueAtUtc': dueAtUtc,
    'dueAllDay': dueAllDay,
    'dueHistory': dueHistory,
    'labels': labels,
    'checklist': checklist,
    'notes': notes,
    'activity': activity,
    'versions': versions,
    'draft': draft,
  };

  factory WorkItem.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> rows(String key) => (j[key] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final item = WorkItem(
      id: j['id'] as String,
      projectId: j['projectId'] as String,
      number: j['number'] as int,
      title: j['title'] as String,
      type: WorkType.values.byName(j['type'] as String),
      status: WorkStatus.values.byName(j['status'] as String),
      body: j['body'] as String,
      priority: j['priority'] as String,
      parentId: j['parentId'] as String?,
      sourceRevisionId: j['sourceRevisionId'] as String?,
      order: j['order'] as int,
      revision: j['revision'] as int,
      blockedReason: j['blockedReason'] as String,
      archived: j['archived'] as bool,
      createdAt: j['createdAt'] as String,
      updatedAt: j['updatedAt'] as String,
      completedAt: j['completedAt'] as String?,
      dueAtUtc: j['dueAtUtc'] as String?,
      dueAllDay: j['dueAllDay'] as bool? ?? false,
      dueHistory: j['dueHistory'] == null ? [] : rows('dueHistory'),
      labels: (j['labels'] as List).cast<String>(),
      checklist: rows('checklist'),
      notes: rows('notes'),
      activity: rows('activity'),
      versions: rows('versions'),
      draft: Map<String, dynamic>.from(j['draft'] as Map),
    );
    if (item.id.isEmpty ||
        item.projectId.isEmpty ||
        item.title.trim().isEmpty ||
        !['P0', 'P1', 'P2', 'P3'].contains(item.priority) ||
        item.number < 0 ||
        item.revision < 0) {
      throw const FormatException('Bản ghi ticket không hợp lệ.');
    }
    DateTime.parse(item.createdAt);
    DateTime.parse(item.updatedAt);
    if (item.completedAt != null) DateTime.parse(item.completedAt!);
    if (item.dueAtUtc != null) {
      final due = DateTime.parse(item.dueAtUtc!);
      if (!due.isUtc) throw const FormatException('Deadline phải lưu UTC.');
    }
    for (final row in item.dueHistory) {
      if (row['at'] is! String ||
          (row['from'] != null && row['from'] is! String) ||
          (row['to'] != null && row['to'] is! String)) {
        throw const FormatException('Lịch sử hạn không hợp lệ.');
      }
    }
    for (final row in item.checklist) {
      if (row['text'] is! String || row['done'] is! bool) {
        throw const FormatException('Checklist không hợp lệ.');
      }
    }
    for (final row in item.notes) {
      if (row['body'] is! String || row['at'] is! String) {
        throw const FormatException('Ghi chú không hợp lệ.');
      }
    }
    for (final row in item.activity) {
      if (row['text'] is! String || row['at'] is! String) {
        throw const FormatException('Lịch sử không hợp lệ.');
      }
    }
    for (final row in item.versions) {
      if (row['id'] is! String ||
          row['body'] is! String ||
          row['at'] is! String) {
        throw const FormatException('Phiên bản không hợp lệ.');
      }
    }
    for (final key in ['source', 'context', 'model']) {
      if (item.draft[key] != null && item.draft[key] is! String) {
        throw const FormatException('Bản nháp không hợp lệ.');
      }
    }
    final questions = item.draft['questions'];
    final answers = item.draft['answers'];
    if (answers != null &&
        (answers is! List || answers.any((a) => a is! String))) {
      throw const FormatException('Câu trả lời không hợp lệ.');
    }
    if (questions != null) {
      if (questions is! List ||
          questions.length > 3 ||
          answers is! List ||
          answers.length != questions.length) {
        throw const FormatException('Danh sách câu hỏi không hợp lệ.');
      }
      for (final question in questions) {
        if (question is! Map ||
            question['question'] is! String ||
            question['options'] is! List ||
            (question['options'] as List).any((o) => o is! String)) {
          throw const FormatException('Câu hỏi không hợp lệ.');
        }
      }
    }
    final snapshot = item.draft['snapshot'];
    if (snapshot != null &&
        (snapshot is! Map ||
            [
              'source',
              'context',
              'model',
            ].any((k) => snapshot[k] is! String))) {
      throw const FormatException('Context của bản nháp không hợp lệ.');
    }
    return item;
  }
}
