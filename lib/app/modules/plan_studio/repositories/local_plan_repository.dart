import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../models/work_item.dart';
import '../services/deadline.dart';
import 'plan_repository.dart';
import 'reminder_store.dart';
import '../models/plan_reminder.dart';

class LocalPlanRepository implements PlanRepository {
  LocalPlanRepository._(this.db);
  final Database db;
  static const _uuid = Uuid();
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  void notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  late final reminders = ReminderStore(db, notifyChanged);

  static Future<LocalPlanRepository> open({String? path}) async {
    sqfliteFfiInit();
    if (path == null) {
      final root = await getApplicationSupportDirectory();
      final directory = Directory(p.join(root.path, 'plan_studio'));
      await directory.create(recursive: true);
      path = p.join(directory.path, 'studio.sqlite');
    }
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onUpgrade: (db, old, version) async {
          if (old < 2) await ReminderStore.migrate(db);
          if (old < 3) {
            await db.execute(
              'ALTER TABLE reminders ADD COLUMN interval_minutes INTEGER',
            );
          }
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE projects (id TEXT PRIMARY KEY, path TEXT UNIQUE NOT NULL, name TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE tickets (id TEXT PRIMARY KEY, number INTEGER UNIQUE NOT NULL, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE metadata (key TEXT PRIMARY KEY, value INTEGER NOT NULL)',
          );
          await db.insert('metadata', {'key': 'sequence', 'value': 0});
          await ReminderStore.migrate(db);
          await db.execute(
            'ALTER TABLE reminders ADD COLUMN interval_minutes INTEGER',
          );
        },
      ),
    );
    return LocalPlanRepository._(db);
  }

  String _normalize(String path) {
    final result = p.normalize(p.absolute(path));
    return Platform.isWindows ? result.toLowerCase() : result;
  }

  @override
  Future<List<StudioProject>> projects() async => (await db.query(
    'projects',
    orderBy: 'name',
  )).map((j) => StudioProject.fromJson(j)).toList();

  @override
  Future<StudioProject> ensureProject(String path) => db
      .transaction((tx) async {
        final normalized = _normalize(path);
        final rows = await tx.query(
          'projects',
          where: 'path = ?',
          whereArgs: [normalized],
        );
        if (rows.isNotEmpty) return StudioProject.fromJson(rows.first);
        final project = StudioProject(
          _uuid.v4(),
          normalized,
          p.basename(p.normalize(path)),
        );
        await tx.insert('projects', project.toJson());
        return project;
      })
      .then((result) {
        notifyChanged();
        return result;
      });

  @override
  Future<void> relinkProject(String id, String path) async {
    final count = await db.update(
      'projects',
      {'path': _normalize(path)},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count != 1) throw StateError('Không tìm thấy dự án.');
    notifyChanged();
  }

  @override
  Future<StudioProject> renameProject(String id, String name) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) throw StateError('Nhập tên dự án.');
    if (clean.length > 80) throw StateError('Tên dự án tối đa 80 ký tự.');
    final result = await db.transaction((tx) async {
      final rows = await tx.query('projects', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw StateError('Không tìm thấy dự án.');
      await tx.update(
        'projects',
        {'name': clean},
        where: 'id = ?',
        whereArgs: [id],
      );
      final old = StudioProject.fromJson(rows.single);
      return StudioProject(old.id, old.path, clean);
    });
    notifyChanged();
    return result;
  }

  @override
  Future<List<WorkItem>> moveToProject(
    String id,
    int revision,
    String projectId, {
    bool withChildren = true,
  }) => db
      .transaction((tx) async {
        final all = await _read(tx);
        final item = _current(all, id, revision);
        if (item.projectId == projectId) return <WorkItem>[];
        final names = {
          for (final row in await tx.query('projects'))
            row['id'] as String: row['name'] as String,
        };
        if (!names.containsKey(projectId)) {
          throw StateError('Dự án đích không tồn tại.');
        }
        final route = '${names[item.projectId] ?? '?'} → ${names[projectId]}';
        final changed = <String, String>{};
        final moved = <String>{};
        void replace(WorkItem next) =>
            all[all.indexWhere((e) => e.id == next.id)] = next;
        WorkItem relocate(WorkItem t) {
          final next = WorkItem.fromJson({
            ...t.toJson(),
            'projectId': projectId,
          });
          replace(next);
          moved.add(next.id);
          return next;
        }

        final main = relocate(item);
        var action = 'Chuyển dự án: $route';
        if (main.parentId != null) {
          final parent = all.where((e) => e.id == main.parentId).firstOrNull;
          main.parentId = null;
          main.sourceRevisionId = null;
          action += ' · bỏ liên kết ${parent?.code ?? 'plan gốc'}';
        }
        changed[main.id] = action;
        for (final child in all.where((e) => e.parentId == id).toList()) {
          if (withChildren) {
            relocate(child);
            changed[child.id] = 'Chuyển dự án theo ${item.code}: $route';
          } else {
            child.parentId = null;
            child.sourceRevisionId = null;
            changed[child.id] = 'Bỏ liên kết ${item.code} vì plan chuyển dự án';
          }
        }
        for (final entry in all.where((e) => moved.contains(e.id)).toList()) {
          entry.order = _endOrder(all, entry);
        }
        _validate(all);
        final result = <WorkItem>[];
        for (final entry in all.where((e) => changed.containsKey(e.id))) {
          _touch(entry, changed[entry.id]!);
          await _write(tx, entry);
          if (moved.contains(entry.id)) result.add(entry);
        }
        return result;
      })
      .then((result) {
        notifyChanged();
        return result;
      });

  Future<List<WorkItem>> _read(DatabaseExecutor tx) async =>
      (await tx.query('tickets'))
          .map(
            (r) => WorkItem.fromJson(
              jsonDecode(r['payload'] as String) as Map<String, dynamic>,
            ),
          )
          .toList()
        ..sort(
          (a, b) => a.order == b.order
              ? a.number.compareTo(b.number)
              : a.order.compareTo(b.order),
        );
  @override
  Future<List<WorkItem>> items() => _read(db);
  Future<void> _write(DatabaseExecutor tx, WorkItem item) async {
    final previous = await tx.query(
      'tickets',
      where: 'id = ?',
      whereArgs: [item.id],
    );
    final old = previous.isEmpty
        ? null
        : WorkItem.fromJson(jsonDecode(previous.single['payload'] as String));
    await ReminderStore.reconcile(tx, item, old);
    await tx
        .insert('tickets', {
          'id': item.id,
          'number': item.number,
          'payload': jsonEncode(item.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace)
        .then((_) {});
  }

  void _touch(WorkItem item, String action) {
    item.revision++;
    item.updatedAt = DateTime.now().toUtc().toIso8601String();
    item.completedAt = item.status == WorkStatus.done
        ? (item.completedAt ?? item.updatedAt)
        : null;
    item.activity.add({'at': item.updatedAt, 'text': action});
  }

  void _validate(List<WorkItem> all) {
    final byId = {for (final i in all) i.id: i};
    for (final item in all) {
      if (item.title.trim().isEmpty) throw StateError('Nhập tiêu đề ticket.');
      if (item.status == WorkStatus.blocked &&
          item.blockedReason.trim().isEmpty) {
        throw StateError('Cần ghi lý do bị chặn.');
      }
      if ([WorkStatus.review, WorkStatus.done].contains(item.status) &&
          item.checklist.any((row) => row['done'] != true)) {
        throw StateError(
          '${item.code}: hoàn tất checklist trước khi chuyển trạng thái.',
        );
      }
      if (item.parentId != null) {
        final parent = byId[item.parentId];
        if (item.type != WorkType.task ||
            parent == null ||
            parent.type != WorkType.plan ||
            parent.projectId != item.projectId) {
          throw StateError('Task phải thuộc plan cùng dự án.');
        }
      }
      if (item.type == WorkType.plan &&
          item.status == WorkStatus.done &&
          all.any(
            (c) =>
                c.parentId == item.id &&
                !c.archived &&
                c.status != WorkStatus.done,
          )) {
        throw StateError('Còn task chưa hoàn tất trong ${item.code}.');
      }
    }
  }

  Future<int> _next(DatabaseExecutor tx) async {
    final rows = await tx.query(
      'metadata',
      where: 'key = ?',
      whereArgs: ['sequence'],
    );
    final next = (rows.single['value'] as int) + 1;
    await tx.update(
      'metadata',
      {'value': next},
      where: 'key = ?',
      whereArgs: ['sequence'],
    );
    return next;
  }

  WorkItem _current(List<WorkItem> all, String id, int revision) {
    final item = all.where((e) => e.id == id).firstOrNull;
    if (item == null || item.revision != revision) {
      throw StateError(
        'Ticket đã thay đổi. Đóng và mở lại để lấy bản mới; nội dung đang nhập vẫn được giữ.',
      );
    }
    return item;
  }

  Future<void> _reopenParent(
    DatabaseExecutor tx,
    List<WorkItem> all,
    WorkItem child,
  ) async {
    if (child.archived ||
        child.status == WorkStatus.done ||
        child.parentId == null) {
      return;
    }
    final parent = all.where((e) => e.id == child.parentId).firstOrNull;
    if (parent != null && parent.status == WorkStatus.done) {
      parent.status = WorkStatus.inProgress;
      _touch(parent, 'Mở lại vì ${child.code} chưa hoàn tất');
      await _write(tx, parent);
    }
  }

  @override
  Future<WorkItem> save(
    WorkItem snapshot, {
    String action = 'Cập nhật nội dung',
  }) => db
      .transaction((tx) async {
        final item = snapshot.clone();
        final all = await _read(tx);
        final existing = all.where((e) => e.id == item.id).firstOrNull;
        if (existing == null) {
          if (item.revision != 0) throw StateError('Ticket không tồn tại.');
          item.number = await _next(tx);
          item.order = _endOrder(all, item);
        } else {
          _current(all, item.id, item.revision);
          if (item.projectId != existing.projectId ||
              item.number != existing.number) {
            throw StateError('Định danh ticket không thể đổi.');
          }
          if (item.status != existing.status) {
            action = '${existing.status.label} → ${item.status.label}';
            item.order = _endOrder(all, item);
          }
          if (item.archived != existing.archived) {
            action = item.archived ? 'Lưu trữ ticket' : 'Khôi phục ticket';
          }
          if (dueChange(existing, item) case final change?) {
            action =
                item.status == existing.status &&
                    item.archived == existing.archived
                ? change
                : '$action · $change';
            if (existing.dueAtUtc != null &&
                item.dueAtUtc != null &&
                existing.dueAtUtc != item.dueAtUtc) {
              item.dueHistory = [
                ...existing.dueHistory,
                {
                  'from': existing.dueAtUtc,
                  'to': item.dueAtUtc,
                  'at': DateTime.now().toUtc().toIso8601String(),
                },
              ];
            }
          }
        }
        if ((await tx.query(
          'projects',
          where: 'id = ?',
          whereArgs: [item.projectId],
        )).isEmpty) {
          throw StateError('Dự án không tồn tại.');
        }
        all.removeWhere((i) => i.id == item.id);
        all.add(item);
        await _reopenParent(tx, all, item);
        _validate(all);
        _touch(item, existing == null ? 'Tạo ${item.type.name}' : action);
        await _write(tx, item);
        return item;
      })
      .then((result) {
        notifyChanged();
        return result;
      });

  int _endOrder(List<WorkItem> all, WorkItem item) =>
      all
          .where(
            (i) =>
                i.id != item.id &&
                i.projectId == item.projectId &&
                i.status == item.status,
          )
          .fold<int>(
            -1,
            (largest, i) => i.order > largest ? i.order : largest,
          ) +
      1;

  @override
  Future<void> move(
    String id,
    int revision,
    WorkStatus status, {
    String? beforeId,
    String reason = '',
  }) => db
      .transaction((tx) async {
        final all = await _read(tx);
        final item = _current(all, id, revision);
        if (item.archived) {
          throw StateError('Khôi phục ticket trước khi di chuyển.');
        }
        if (beforeId == id) return;
        final previous = item.status;
        final column = all
            .where(
              (e) =>
                  e.id != id &&
                  e.projectId == item.projectId &&
                  e.status == status &&
                  !e.archived,
            )
            .toList();
        var index = beforeId == null
            ? column.length
            : column.indexWhere((e) => e.id == beforeId);
        if (index < 0) throw StateError('Vị trí thả đã thay đổi. Thử lại.');
        item.status = status;
        if (status == WorkStatus.blocked) item.blockedReason = reason;
        column.insert(index, item);
        await _reopenParent(tx, all, item);
        _validate(all);
        for (var n = 0; n < column.length; n++) {
          final entry = column[n];
          if (entry.order != n || entry.id == id) {
            entry.order = n;
            _touch(
              entry,
              entry.id == id && previous != status
                  ? '${previous.label} → ${status.label}'
                  : 'Sắp xếp vị trí',
            );
            await _write(tx, entry);
          }
        }
      })
      .then((_) {
        notifyChanged();
      });

  @override
  Future<List<WorkItem>> createTasks(
    String planId,
    int revision,
    List<String> titles,
  ) => db
      .transaction((tx) async {
        final all = await _read(tx);
        final plan = _current(all, planId, revision);
        if (plan.type != WorkType.plan || plan.archived) {
          throw StateError('Chọn plan đang hoạt động.');
        }
        final sourceId = plan.versions.lastOrNull?['id'] as String?;
        final result = <WorkItem>[];
        for (final title
            in titles.map((t) => t.trim()).where((t) => t.isNotEmpty).toSet()) {
          if (all.any(
            (i) =>
                i.parentId == planId &&
                i.sourceRevisionId == sourceId &&
                i.title == title,
          )) {
            continue;
          }
          final task = WorkItem(
            id: _uuid.v4(),
            projectId: plan.projectId,
            title: title,
            parentId: planId,
            sourceRevisionId: sourceId,
            number: await _next(tx),
            order: all.length,
          );
          _touch(task, 'Tạo từ ${plan.code}');
          all.add(task);
          result.add(task);
          await _write(tx, task);
        }
        if (result.isNotEmpty) {
          if (plan.status == WorkStatus.done) {
            plan.status = WorkStatus.inProgress;
          }
          _touch(plan, 'Tạo ${result.length} task con');
          await _write(tx, plan);
        }
        _validate(all);
        return result;
      })
      .then((result) {
        notifyChanged();
        return result;
      });

  @override
  Future<List<WorkItem>> createMany(List<WorkItem> drafts) => db
      .transaction((tx) async {
        final all = await _read(tx);
        final projects = <String>{};
        final created = <WorkItem>[];
        for (final draft in drafts) {
          final item = draft.clone();
          if (item.revision != 0 || all.any((e) => e.id == item.id)) {
            throw StateError('Ticket đã tồn tại.');
          }
          if (projects.add(item.projectId) &&
              (await tx.query(
                'projects',
                where: 'id = ?',
                whereArgs: [item.projectId],
              )).isEmpty) {
            throw StateError('Dự án không tồn tại.');
          }
          if (item.parentId case final parentId?
              when all.any((e) => e.id == parentId && e.archived)) {
            throw StateError('Chọn plan đang hoạt động.');
          }
          item.number = await _next(tx);
          item.order = _endOrder(all, item);
          all.add(item);
          await _reopenParent(tx, all, item);
          created.add(item);
        }
        _validate(all);
        final added = <String, int>{};
        for (final item in created) {
          _touch(item, 'Tạo ${item.type.name} hàng loạt');
          await _write(tx, item);
          if (item.parentId case final parentId?) {
            added[parentId] = (added[parentId] ?? 0) + 1;
          }
        }
        for (final MapEntry(key: id, value: count) in added.entries) {
          final plan = all.firstWhere((e) => e.id == id);
          _touch(plan, 'Thêm $count task con');
          await _write(tx, plan);
        }
        return created;
      })
      .then((created) {
        notifyChanged();
        return created;
      });

  @override
  Future<String> exportBackup() => db.transaction(
    (tx) async => const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 3,
      'projects': await tx.query('projects'),
      'tickets': (await _read(tx)).map((i) => i.toJson()).toList(),
      'reminders': await tx.rawQuery(
        'SELECT reminders.* FROM reminders INNER JOIN tickets ON tickets.id = reminders.item_id',
      ),
    }),
  );

  /// Import is merge-only: existing IDs and their revisions are never replaced.
  @override
  Future<int> importBackup(String source) async {
    final data = jsonDecode(source) as Map<String, dynamic>;
    if (![1, 2, 3].contains(data['schemaVersion'])) {
      throw const FormatException('Phiên bản backup không được hỗ trợ.');
    }
    final projects = (data['projects'] as List)
        .map((j) => StudioProject.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
    final incoming = (data['tickets'] as List)
        .map((j) => WorkItem.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
    if (projects.map((p) => p.id).toSet().length != projects.length ||
        incoming.map((i) => i.id).toSet().length != incoming.length) {
      throw const FormatException('Backup có ID trùng.');
    }
    _validate(incoming);
    final incomingReminders = [2, 3].contains(data['schemaVersion'])
        ? (data['reminders'] as List)
              .map(
                (j) =>
                    PlanReminder.fromJson(Map<String, dynamic>.from(j as Map)),
              )
              .toList()
        : <PlanReminder>[];
    if (incomingReminders.map((r) => r.id).toSet().length !=
            incomingReminders.length ||
        incomingReminders.any((r) => !incoming.any((i) => i.id == r.itemId))) {
      throw const FormatException(
        'Lịch nhắc trong backup bị trùng hoặc thiếu ticket.',
      );
    }
    return db
        .transaction((tx) async {
          for (final project in projects) {
            if (project.id.isEmpty ||
                project.path.isEmpty ||
                project.name.isEmpty) {
              throw const FormatException('Dự án không hợp lệ.');
            }
            final existing = await tx.query(
              'projects',
              where: 'id = ? OR path = ?',
              whereArgs: [project.id, project.path],
            );
            if (existing.isEmpty) {
              await tx.insert('projects', project.toJson());
            } else if (existing.any(
              (e) => e['id'] != project.id || e['path'] != project.path,
            )) {
              throw StateError(
                'Dự án ${project.name} có đường dẫn/ID xung đột. Backup chưa được nhập.',
              );
            }
          }
          final all = await _read(tx);
          final ids = all.map((i) => i.id).toSet();
          final addedIds = <String>{};
          var count = 0;
          for (final item in incoming) {
            if (ids.contains(item.id)) continue;
            if ((await tx.query(
              'projects',
              where: 'id = ?',
              whereArgs: [item.projectId],
            )).isEmpty) {
              throw const FormatException('Ticket thiếu dự án.');
            }
            item.number = await _next(tx);
            _touch(item, 'Nhập từ backup');
            all.add(item);
            addedIds.add(item.id);
            await _write(tx, item);
            count++;
          }
          _validate(all);
          for (final r in incomingReminders.where(
            (r) => addedIds.contains(r.itemId),
          )) {
            await tx.insert('reminders', {
              ...r.toJson(),
              'id': _uuid.v4(),
              'state': r.active ? 'paused' : r.state.name,
              'revision': 0,
            });
          }
          return count;
        })
        .then((result) {
          notifyChanged();
          return result;
        });
  }

  @override
  Future<void> close() async {
    await db.close();
    await _changes.close();
  }

  /// Ticket mutation, grouped reminder handling and the idempotency receipt
  /// commit together. A cancelled/stale popup cannot change a ticket.
  Future<void> applyReminderAction({
    required String itemId,
    required int itemRevision,
    required Map<String, int> reminderRevisions,
    required String commandId,
    required String action,
    int minutes = 10,
    String reason = '',
    DateTime? now,
  }) async {
    if (![
          'ack',
          'open',
          'snooze',
          'start',
          'done',
          'blocked',
        ].contains(action) ||
        commandId.isEmpty ||
        reminderRevisions.isEmpty) {
      throw ArgumentError('Thao tác nhắc hẹn không hợp lệ.');
    }
    if (action == 'snooze' && ![10, 30, 60].contains(minutes)) {
      throw ArgumentError('Thời gian nhắc lại không hợp lệ.');
    }
    await db.transaction((tx) async {
      if ((await tx.query(
        'reminder_commands',
        where: 'id = ?',
        whereArgs: [commandId],
      )).isNotEmpty) {
        return;
      }
      final time = (now ?? DateTime.now()).toUtc();
      final all = await _read(tx);
      final item = all.where((i) => i.id == itemId).firstOrNull;
      if (item == null || item.archived || item.status == WorkStatus.done) {
        throw StateError('Ticket không còn hoạt động.');
      }
      for (final entry in reminderRevisions.entries) {
        final rows = await tx.query(
          'reminders',
          where: 'id = ?',
          whereArgs: [entry.key],
        );
        if (rows.isEmpty) throw StateError('Lịch nhắc không còn tồn tại.');
        final r = PlanReminder.fromJson(rows.single);
        if (r.itemId != itemId ||
            r.revision != entry.value ||
            !r.active ||
            r.eligibleAt.isAfter(time)) {
          throw StateError('Lịch nhắc đã thay đổi. Vui lòng dùng dữ liệu mới.');
        }
      }
      if (['start', 'done', 'blocked'].contains(action)) {
        _current(all, itemId, itemRevision);
        final previous = item.status;
        item.status = action == 'start'
            ? WorkStatus.inProgress
            : action == 'done'
            ? WorkStatus.done
            : WorkStatus.blocked;
        if (item.status == WorkStatus.blocked) {
          item.blockedReason = reason.trim();
        }
        item.order = _endOrder(all, item);
        await _reopenParent(tx, all, item);
        _validate(all);
        _touch(item, '${previous.label} → ${item.status.label} (nhắc hẹn)');
        await _write(tx, item);
      }
      if (action != 'done') {
        for (final entry in reminderRevisions.entries) {
          final row = (await tx.query(
            'reminders',
            where: 'id = ?',
            whereArgs: [entry.key],
          )).single;
          await tx.update(
            'reminders',
            ReminderStore.transition(
              PlanReminder.fromJson(row),
              action == 'snooze'
                  ? ReminderState.snoozed
                  : ReminderState.acknowledged,
              time,
              minutes: minutes,
            ),
            where: 'id = ?',
            whereArgs: [entry.key],
          );
        }
      }
      await tx.insert('reminder_commands', {
        'id': commandId,
        'at': time.toIso8601String(),
      });
    });
    notifyChanged();
  }

  @override
  Future<void> delete(String id, int revision) => db
      .transaction((tx) async {
        final all = await _read(tx);
        final item = _current(all, id, revision);
        for (final child in all.where((i) => i.parentId == id)) {
          child.parentId = null;
          child.sourceRevisionId = null;
          _touch(child, 'Giữ lại task sau khi xóa plan ${item.code}');
          await _write(tx, child);
        }
        final parent = all.where((i) => i.id == item.parentId).firstOrNull;
        if (parent != null) {
          _touch(parent, 'Xóa task ${item.code}: ${item.title}');
          await _write(tx, parent);
        }
        await ReminderStore.cancelFor(tx, id);
        await tx.delete('tickets', where: 'id = ?', whereArgs: [id]);
        all.removeWhere((i) => i.id == id);
        _validate(all);
      })
      .then((_) {
        notifyChanged();
      });
}
