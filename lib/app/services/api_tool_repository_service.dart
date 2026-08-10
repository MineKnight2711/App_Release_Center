import 'dart:async';

import 'package:app_release_center/app/models/api_tool.dart';
import 'package:app_release_center/app/models/auth_models.dart';
import 'package:app_release_center/app/services/auth_service.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  });

  final List<ApiToolCollectionRoot> collections;
  final List<ApiToolCollectionFolder> folders;
  final List<ApiToolRequest> requests;
}

abstract class TeamApiToolDataSource {
  Future<ApiToolRepositorySnapshot> load(String teamId);
  Future<void> saveCollections(
    String teamId,
    List<ApiToolCollectionRoot> collections,
  );
  Future<void> saveFolders(
    String teamId,
    List<ApiToolCollectionFolder> folders,
  );
  Future<void> saveRequests(String teamId, List<ApiToolRequest> requests);
}

class FirestoreTeamApiToolDataSource implements TeamApiToolDataSource {
  FirestoreTeamApiToolDataSource({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Future<ApiToolRepositorySnapshot> load(String teamId) async {
    final teamRef = _db.collection('teams').doc(teamId);
    final results = await Future.wait([
      teamRef.collection('apiToolCollections').get(),
      teamRef.collection('apiToolFolders').get(),
      teamRef.collection('apiToolRequests').get(),
    ]);

    final collections =
        results[0].docs
            .map((doc) => ApiToolCollectionRoot.fromJson(doc.data()))
            .where((entry) => entry.id.isNotEmpty)
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final folders =
        results[1].docs
            .map((doc) => ApiToolCollectionFolder.fromJson(doc.data()))
            .where((entry) => entry.id.isNotEmpty)
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final requests =
        results[2].docs
            .map((doc) => ApiToolRequest.fromJson(doc.data()))
            .where((entry) => entry.id.isNotEmpty)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return ApiToolRepositorySnapshot(
      collections: collections,
      folders: folders,
      requests: requests,
    );
  }

  @override
  Future<void> saveCollections(
    String teamId,
    List<ApiToolCollectionRoot> collections,
  ) {
    return _replaceDocuments(
      teamId: teamId,
      collectionName: 'apiToolCollections',
      ids: collections.map((entry) => entry.id),
      jsonById: {
        for (final collection in collections)
          collection.id: collection.toJson(),
      },
    );
  }

  @override
  Future<void> saveFolders(
    String teamId,
    List<ApiToolCollectionFolder> folders,
  ) {
    return _replaceDocuments(
      teamId: teamId,
      collectionName: 'apiToolFolders',
      ids: folders.map((entry) => entry.id),
      jsonById: {for (final folder in folders) folder.id: folder.toJson()},
    );
  }

  @override
  Future<void> saveRequests(String teamId, List<ApiToolRequest> requests) {
    return _replaceDocuments(
      teamId: teamId,
      collectionName: 'apiToolRequests',
      ids: requests.map((entry) => entry.id),
      jsonById: {for (final request in requests) request.id: request.toJson()},
    );
  }

  Future<void> _replaceDocuments({
    required String teamId,
    required String collectionName,
    required Iterable<String> ids,
    required Map<String, Map<String, Object?>> jsonById,
  }) async {
    final collectionRef = _db
        .collection('teams')
        .doc(teamId)
        .collection(collectionName);
    final existing = await collectionRef.get();
    final keepIds = ids.where((id) => id.trim().isNotEmpty).toSet();
    final batch = _db.batch();

    for (final doc in existing.docs) {
      if (!keepIds.contains(doc.id)) {
        batch.delete(doc.reference);
      }
    }

    for (final entry in jsonById.entries) {
      if (entry.key.trim().isEmpty) continue;
      batch.set(collectionRef.doc(entry.key), entry.value);
    }

    await batch.commit();
  }
}

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
  TeamApiToolDataSource? _teamDataSource;
  StreamSubscription<CurrentUserProfile?>? _profileSubscription;

  final workspaceLabel = 'Local workspace'.obs;
  final repositoryStatus = ''.obs;
  final isLoading = false.obs;
  final canWriteApiTools = true.obs;

  var _collections = <ApiToolCollectionRoot>[];
  var _folders = <ApiToolCollectionFolder>[];
  var _requests = <ApiToolRequest>[];

  List<ApiToolCollectionRoot> get apiToolCollections =>
      List.unmodifiable(_collections);
  List<ApiToolCollectionFolder> get apiToolFolders =>
      List.unmodifiable(_folders);
  List<ApiToolRequest> get apiToolRequests => List.unmodifiable(_requests);

  bool get isTeamMode => _currentTeamProfile != null && _teamDataSource != null;

  bool get hasLocalApiToolData =>
      _localStore.apiToolCollections.isNotEmpty ||
      _localStore.apiToolFolders.isNotEmpty ||
      _localStore.apiToolRequests.isNotEmpty;

  CurrentUserProfile? get _currentTeamProfile {
    final current = _auth?.profile.value;
    return current != null && current.hasTeam ? current : null;
  }

  Future<ApiToolRepositoryService> init({required bool firebaseEnabled}) async {
    if (firebaseEnabled) {
      _teamDataSource ??= FirestoreTeamApiToolDataSource();
    }
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
      workspaceLabel.value = 'Local workspace';
      repositoryStatus.value = '';
      canWriteApiTools.value = true;
      return;
    }

    isLoading.value = true;
    workspaceLabel.value = 'Team: ${teamProfile.teamName}';
    canWriteApiTools.value = teamProfile.canEditApiTools;
    try {
      final snapshot = await _teamDataSource!.load(teamProfile.teamId);
      _collections = snapshot.collections;
      _folders = snapshot.folders;
      _requests = snapshot.requests;
      repositoryStatus.value = '';
    } catch (error) {
      _loadLocalCache();
      canWriteApiTools.value = false;
      repositoryStatus.value =
          'Team HTTP Tools are unavailable. Local data is shown read-only.';
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
      await _teamDataSource!.saveCollections(teamProfile.teamId, normalized);
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
      await _teamDataSource!.saveFolders(teamProfile.teamId, normalized);
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
      await _teamDataSource!.saveRequests(teamProfile.teamId, normalized);
      _requests = normalized;
      return;
    }
    await _localStore.saveApiToolRequests(normalized);
    _requests = _localStore.apiToolRequests;
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
        _teamDataSource!.saveCollections(
          teamProfile.teamId,
          normalizedCollections,
        ),
        _teamDataSource!.saveFolders(teamProfile.teamId, normalizedFolders),
        _teamDataSource!.saveRequests(teamProfile.teamId, normalizedRequests),
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
      throw const ApiToolRepositoryException('Sign in to a team first.');
    }
    _ensureWritable();

    final remote = await _teamDataSource!.load(teamProfile.teamId);
    final collections = _mergeById(
      remote.collections,
      _localStore.apiToolCollections,
    );
    final folders = _mergeById(remote.folders, _localStore.apiToolFolders);
    final requests = _mergeById(remote.requests, _localStore.apiToolRequests);

    await Future.wait([
      _teamDataSource!.saveCollections(teamProfile.teamId, collections),
      _teamDataSource!.saveFolders(teamProfile.teamId, folders),
      _teamDataSource!.saveRequests(teamProfile.teamId, requests),
    ]);
    _collections = collections;
    _folders = folders;
    _requests = requests;
    repositoryStatus.value = 'Local HTTP Tools were imported to the team.';
  }

  void _loadLocalCache() {
    _collections = _localStore.apiToolCollections;
    _folders = _localStore.apiToolFolders;
    _requests = _localStore.apiToolRequests;
  }

  void _ensureWritable() {
    if (!canWriteApiTools.value) {
      throw ApiToolRepositoryException(
        repositoryStatus.value.isEmpty
            ? 'You do not have permission to edit HTTP Tools.'
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
  return '';
}
