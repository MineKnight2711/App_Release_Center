import '../models/work_item.dart';

abstract class PlanRepository {
  Future<List<StudioProject>> projects();
  Future<StudioProject> ensureProject(String path);

  /// Points the project at a moved folder; the display name is kept.
  Future<void> relinkProject(String id, String path);

  /// Changes only the display name; the folder link is untouched.
  Future<StudioProject> renameProject(String id, String name);

  /// Moves a ticket to another project in one transaction and returns every
  /// ticket that changed project. A plan takes its tasks along unless
  /// [withChildren] is false, in which case they stay and are detached; a task
  /// leaves its plan behind, because a task must share its plan's project.
  Future<List<WorkItem>> moveToProject(
    String id,
    int revision,
    String projectId, {
    bool withChildren = true,
  });
  Future<List<WorkItem>> items();
  Future<WorkItem> save(WorkItem item, {String action = 'Cập nhật nội dung'});

  /// Deletes this ticket; children of a deleted plan are retained and detached.
  Future<void> delete(String id, int revision);
  Future<void> move(
    String id,
    int revision,
    WorkStatus status, {
    String? beforeId,
    String reason = '',
  });
  Future<List<WorkItem>> createTasks(
    String planId,
    int revision,
    List<String> titles,
  );

  /// Adds new tickets in one transaction: all of them are created or none.
  /// Each lands at the end of its column; a done parent plan is reopened.
  Future<List<WorkItem>> createMany(List<WorkItem> drafts);
  Future<String> exportBackup();
  Future<int> importBackup(String source);
  Future<void> close();
}
