import 'dart:async';
import 'dart:convert';

import 'package:app_management_center/app/data/amc_api_client.dart';
import 'package:app_management_center/app/models/api_tool.dart';
import 'package:app_management_center/app/models/auth_models.dart';
import 'package:app_management_center/app/services/auth_service.dart';
import 'package:app_management_center/app/services/project_store_service.dart';
import 'package:get/get.dart';

class ApiToolRepositoryException implements Exception {
  const ApiToolRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiToolRepositorySnapshot {
  const ApiToolRepositorySnapshot({
    this.collections = const [],
    this.folders = const [],
    this.requests = const [],
    this.quickRequests = const [],
  });

  final List<ApiToolCollectionRoot> collections;
  final List<ApiToolCollectionFolder> folders;
  final List<ApiToolRequest> requests;
  final List<ApiToolQuickRequest> quickRequests;
}

abstract class TeamApiToolDataSource {
  Future<ApiToolRepositorySnapshot> load(String teamId);
  Future<void> deleteCollection(String teamId, String collectionId);
  Future<void> saveCollections(
    String teamId,
    List<ApiToolCollectionRoot> collections,
  );
  Future<void> saveFolders(
    String teamId,
    List<ApiToolCollectionFolder> folders,
  );
  Future<void> saveRequests(String teamId, List<ApiToolRequest> requests);
  Future<void> saveQuickRequests(
    String teamId,
    List<ApiToolQuickRequest> requests,
  );
}

class AmcTeamApiToolDataSource implements TeamApiToolDataSource {
  AmcTeamApiToolDataSource(this._api);

  final AmcApiClient _api;

  @override
  Future<void> deleteCollection(String teamId, String collectionId) async {
    await _api.delete(
      '${_teamPath(teamId)}/collections/${Uri.encodeComponent(collectionId)}',
    );
  }

  @override
  Future<ApiToolRepositorySnapshot> load(String teamId) async {
    final body = await _api.get(_teamPath(teamId));

    final collections =
        _documents(body['collections'])
            .map(ApiToolCollectionRoot.fromJson)
            .where((entry) => entry.id.isNotEmpty)
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final folders =
        _documents(body['folders'])
            .map(ApiToolCollectionFolder.fromJson)
            .where((entry) => entry.id.isNotEmpty)
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final requests =
        _documents(body['requests'])
            .map(ApiToolRequest.fromJson)
            .where((entry) => entry.id.isNotEmpty)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final quickRequests =
        _documents(body['quickRequests'])
            .map(ApiToolQuickRequest.fromJson)
            .where((entry) => entry.id.isNotEmpty)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return ApiToolRepositorySnapshot(
      collections: collections,
      folders: folders,
      requests: requests,
      quickRequests: quickRequests,
    );
  }

  @override
  Future<void> saveCollections(
    String teamId,
    List<ApiToolCollectionRoot> collections,
  ) {
    return _replace(teamId, 'collections', [
      for (final collection in collections) collection.toJson(),
    ]);
  }

  @override
  Future<void> saveFolders(
    String teamId,
    List<ApiToolCollectionFolder> folders,
  ) {
    return _replace(teamId, 'folders', [
      for (final folder in folders) folder.toJson(),
    ]);
  }

  @override
  Future<void> saveRequests(String teamId, List<ApiToolRequest> requests) {
    return _replace(teamId, 'requests', [
      for (final request in requests) request.toJson(),
    ]);
  }

  @override
  Future<void> saveQuickRequests(
    String teamId,
    List<ApiToolQuickRequest> requests,
  ) {
    return _replace(teamId, 'quick-requests', [
      for (final request in requests) request.toJson(),
    ]);
  }

  /// The server replaces the whole set: missing ids are deleted.
  Future<void> _replace(
    String teamId,
    String kind,
    List<Map<String, Object?>> items,
  ) async {
    final kept = items
        .where((item) => item['id']?.toString().trim().isNotEmpty ?? false)
        .toList();
    kept.forEach(_ensureDocumentFits);
    await _api.put('${_teamPath(teamId)}/$kind', body: {'items': kept});
  }

  /// The database stores each HTTP Tool as one JSON value; a value that is too
  /// large fails without naming the request, so it is checked here where the
  /// offending request can still be pointed at by name.
  void _ensureDocumentFits(Map<String, Object?> json) {
    final bytes = documentBytes(json);
    if (bytes <= _maxDocumentBytes) return;
    final name = (json['name'] ?? json['id'] ?? '').toString().trim();
    throw ApiToolRepositoryException(
      '"$name" nặng ${(bytes / 1024).round()} KB, vượt giới hạn '
      '${_maxDocumentBytes ~/ 1024} KB mỗi mục của database nhóm. Bớt body '
      'hoặc giá trị form-data đang chứa payload rồi import lại.',
    );
  }

  static String _teamPath(String teamId) =>
      '/teams/${Uri.encodeComponent(teamId)}/api-tools';

  static Iterable<Map<String, Object?>> _documents(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map(Map<String, Object?>.from);
  }
}

/// Largest HTTP Tool the team database accepts, as encoded JSON.
const int _maxDocumentBytes = 1024 * 1024;

/// What one HTTP Tool costs in the team database: its UTF-8 JSON encoding.
int documentBytes(Map<String, Object?> json) =>
    utf8.encode(jsonEncode(json)).length;

class ApiToolRepositoryService extends GetxService {
  ApiToolRepositoryService({
    required ProjectStoreService localStore,
    AuthService? auth,
    TeamApiToolDataSource? teamDataSource,
  }) : _localStore = localStore,
       _auth = auth,
       _teamDataSource = teamDataSource {
    _loadLocalCache();
  }

  final ProjectStoreService _localStore;
  final AuthService? _auth;
  final TeamApiToolDataSource? _teamDataSource;
  StreamSubscription<CurrentUserProfile?>? _profileSubscription;

  final workspaceLabel = 'Workspace ở máy'.obs;
  final repositoryStatus = ''.obs;
  final isLoading = false.obs;
  final canWriteApiTools = true.obs;

  var _collections = <ApiToolCollectionRoot>[];
  var _folders = <ApiToolCollectionFolder>[];
  var _requests = <ApiToolRequest>[];
  var _quickRequests = <ApiToolQuickRequest>[];

  List<ApiToolCollectionRoot> get apiToolCollections =>
      List.unmodifiable(_collections);
  List<ApiToolCollectionFolder> get apiToolFolders =>
      List.unmodifiable(_folders);
  List<ApiToolRequest> get apiToolRequests => List.unmodifiable(_requests);
  List<ApiToolQuickRequest> get apiToolQuickRequests =>
      List.unmodifiable(_quickRequests);

  bool get isTeamMode => _currentTeamProfile != null && _teamDataSource != null;

  bool get hasLocalApiToolData =>
      _localStore.apiToolCollections.isNotEmpty ||
      _localStore.apiToolFolders.isNotEmpty ||
      _localStore.apiToolRequests.isNotEmpty ||
      _localStore.apiToolQuickRequests.isNotEmpty;

  CurrentUserProfile? get _currentTeamProfile {
    final current = _auth?.profile.value;
    return current != null && current.hasTeam ? current : null;
  }

  Future<ApiToolRepositoryService> init() async {
    _profileSubscription = _auth?.profile.listen((_) => unawaited(refresh()));
    await refresh();
    return this;
  }

  @override
  void onClose() {
    unawaited(_profileSubscription?.cancel());
    super.onClose();
  }

  Future<void> refresh() async {
    final teamProfile = _currentTeamProfile;
    if (teamProfile == null || _teamDataSource == null) {
      _loadLocalCache();
      workspaceLabel.value = 'Workspace ở máy';
      repositoryStatus.value = '';
      canWriteApiTools.value = true;
      return;
    }

    isLoading.value = true;
    workspaceLabel.value = 'Nhóm: ${teamProfile.teamName}';
    canWriteApiTools.value = teamProfile.canEditApiTools;
    try {
      final snapshot = await _teamDataSource.load(teamProfile.teamId);
      _collections = snapshot.collections;
      _folders = snapshot.folders;
      _requests = snapshot.requests;
      _quickRequests = snapshot.quickRequests;
      repositoryStatus.value = '';
    } catch (error) {
      _loadLocalCache();
      canWriteApiTools.value = false;
      repositoryStatus.value =
          'Không truy cập được HTTP Tools của nhóm. Dữ liệu ở máy chỉ xem được.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> saveApiToolCollections(
    List<ApiToolCollectionRoot> collections,
  ) async {
    _ensureWritable();
    final normalized = collections.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final teamProfile = _currentTeamProfile;
    if (teamProfile != null && _teamDataSource != null) {
      await _teamDataSource.saveCollections(teamProfile.teamId, normalized);
      _collections = normalized;
      return;
    }
    await _localStore.saveApiToolCollections(normalized);
    _collections = _localStore.apiToolCollections;
  }

  Future<void> saveApiToolFolders(List<ApiToolCollectionFolder> folders) async {
    _ensureWritable();
    final normalized = folders.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final teamProfile = _currentTeamProfile;
    if (teamProfile != null && _teamDataSource != null) {
      await _teamDataSource.saveFolders(teamProfile.teamId, normalized);
      _folders = normalized;
      return;
    }
    await _localStore.saveApiToolFolders(normalized);
    _folders = _localStore.apiToolFolders;
  }

  Future<void> saveApiToolRequests(List<ApiToolRequest> requests) async {
    _ensureWritable();
    final normalized = requests.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final teamProfile = _currentTeamProfile;
    if (teamProfile != null && _teamDataSource != null) {
      await _teamDataSource.saveRequests(teamProfile.teamId, normalized);
      _requests = normalized;
      return;
    }
    await _localStore.saveApiToolRequests(normalized);
    _requests = _localStore.apiToolRequests;
  }

  Future<void> saveApiToolQuickRequests(
    List<ApiToolQuickRequest> requests,
  ) async {
    _ensureWritable();
    final normalized = requests.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final teamProfile = _currentTeamProfile;
    if (teamProfile != null && _teamDataSource != null) {
      await _teamDataSource.saveQuickRequests(teamProfile.teamId, normalized);
      _quickRequests = normalized;
      return;
    }
    await _localStore.saveApiToolQuickRequests(normalized);
    _quickRequests = _localStore.apiToolQuickRequests;
  }

  Future<void> deleteApiToolCollection(String collectionId) async {
    _ensureWritable();
    final normalizedId = collectionId.trim();
    if (normalizedId.isEmpty) {
      throw const ApiToolRepositoryException('Chọn collection cần xoá.');
    }

    final collections = _collections
        .where((entry) => entry.id != normalizedId)
        .toList(growable: false);
    final folders = _folders
        .where((entry) => entry.collectionId != normalizedId)
        .toList(growable: false);
    final requests = _requests
        .where((entry) => entry.collectionId != normalizedId)
        .toList(growable: false);
    final quickRequests = _quickRequests
        .where((entry) => entry.collectionId != normalizedId)
        .toList(growable: false);

    final teamProfile = _currentTeamProfile;
    if (teamProfile != null && _teamDataSource != null) {
      await _teamDataSource.deleteCollection(teamProfile.teamId, normalizedId);
      _collections = collections;
      _folders = folders;
      _requests = requests;
      _quickRequests = quickRequests;
      return;
    }

    await Future.wait([
      _localStore.saveApiToolCollections(collections),
      _localStore.saveApiToolFolders(folders),
      _localStore.saveApiToolRequests(requests),
      _localStore.saveApiToolQuickRequests(quickRequests),
    ]);
    _loadLocalCache();
  }

  Future<void> importApiTools({
    required List<ApiToolCollectionRoot> collections,
    required List<ApiToolCollectionFolder> folders,
    required List<ApiToolRequest> requests,
  }) async {
    _ensureWritable();
    final normalizedCollections = [..._collections, ...collections]
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final normalizedFolders = [..._folders, ...folders]
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final normalizedRequests = [..._requests, ...requests]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final teamProfile = _currentTeamProfile;
    if (teamProfile != null && _teamDataSource != null) {
      await Future.wait([
        _teamDataSource.saveCollections(
          teamProfile.teamId,
          normalizedCollections,
        ),
        _teamDataSource.saveFolders(teamProfile.teamId, normalizedFolders),
        _teamDataSource.saveRequests(teamProfile.teamId, normalizedRequests),
      ]);
      _collections = normalizedCollections;
      _folders = normalizedFolders;
      _requests = normalizedRequests;
      return;
    }

    await Future.wait([
      _localStore.saveApiToolCollections(normalizedCollections),
      _localStore.saveApiToolFolders(normalizedFolders),
      _localStore.saveApiToolRequests(normalizedRequests),
    ]);
    _collections = _localStore.apiToolCollections;
    _folders = _localStore.apiToolFolders;
    _requests = _localStore.apiToolRequests;
  }

  Future<void> importLocalApiToolsToTeam() async {
    final teamProfile = _currentTeamProfile;
    if (teamProfile == null || _teamDataSource == null) {
      throw const ApiToolRepositoryException(
        'Đăng nhập vào một nhóm trước đã.',
      );
    }
    _ensureWritable();

    final remote = await _teamDataSource.load(teamProfile.teamId);
    final collections = _mergeById(
      remote.collections,
      _localStore.apiToolCollections,
    );
    final folders = _mergeById(remote.folders, _localStore.apiToolFolders);
    final requests = _mergeById(remote.requests, _localStore.apiToolRequests);
    final quickRequests = _mergeById(
      remote.quickRequests,
      _localStore.apiToolQuickRequests,
    );

    await Future.wait([
      _teamDataSource.saveCollections(teamProfile.teamId, collections),
      _teamDataSource.saveFolders(teamProfile.teamId, folders),
      _teamDataSource.saveRequests(teamProfile.teamId, requests),
      _teamDataSource.saveQuickRequests(teamProfile.teamId, quickRequests),
    ]);
    _collections = collections;
    _folders = folders;
    _requests = requests;
    _quickRequests = quickRequests;
    repositoryStatus.value = 'Đã đưa HTTP Tools ở máy lên nhóm.';
  }

  void _loadLocalCache() {
    _collections = _localStore.apiToolCollections;
    _folders = _localStore.apiToolFolders;
    _requests = _localStore.apiToolRequests;
    _quickRequests = _localStore.apiToolQuickRequests;
  }

  void _ensureWritable() {
    if (!canWriteApiTools.value) {
      throw ApiToolRepositoryException(
        repositoryStatus.value.isEmpty
            ? 'Bạn không có quyền sửa HTTP Tools.'
            : repositoryStatus.value,
      );
    }
  }
}

List<T> _mergeById<T extends Object>(List<T> base, List<T> overrides) {
  final byId = <String, T>{};
  for (final entry in base) {
    byId[_idOf(entry)] = entry;
  }
  for (final entry in overrides) {
    final id = _idOf(entry);
    if (id.isNotEmpty) byId[id] = entry;
  }
  return byId.values.toList(growable: false);
}

String _idOf(Object entry) {
  if (entry is ApiToolCollectionRoot) return entry.id;
  if (entry is ApiToolCollectionFolder) return entry.id;
  if (entry is ApiToolRequest) return entry.id;
  if (entry is ApiToolQuickRequest) return entry.id;
  return '';
}
