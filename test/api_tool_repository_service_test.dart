import 'dart:async';

import 'package:app_release_center/app/models/api_tool.dart';
import 'package:app_release_center/app/models/auth_models.dart';
import 'package:app_release_center/app/services/api_tool_repository_service.dart';
import 'package:app_release_center/app/services/auth_service.dart';
import 'package:app_release_center/app/services/project_store_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('uses local store when no team profile is active', () async {
    SharedPreferences.setMockInitialValues({});
    final localStore = await ProjectStoreService().init();
    final repository = await ApiToolRepositoryService(
      localStore: localStore,
    ).init(firebaseEnabled: false);
    final request = ApiToolRequest(
      id: 'request-1',
      name: 'Local',
      method: ApiToolMethod.get,
      url: 'https://example.com',
      updatedAt: DateTime(2026, 8, 4),
    );

    await repository.saveApiToolRequests([request]);

    expect(repository.workspaceLabel.value, 'Local workspace');
    expect(localStore.apiToolRequests.single.id, 'request-1');
    expect(repository.apiToolRequests.single.name, 'Local');
  });

  test('writes HTTP Tool collections to team data source', () async {
    SharedPreferences.setMockInitialValues({});
    final localStore = await ProjectStoreService().init();
    final auth = await _teamAuthService().init(firebaseEnabled: true);
    await auth.signIn(email: 'dev@example.com', password: 'secret123');
    final teamData = _FakeTeamApiToolDataSource();
    final repository = await ApiToolRepositoryService(
      localStore: localStore,
      auth: auth,
      teamDataSource: teamData,
    ).init(firebaseEnabled: true);
    final collection = ApiToolCollectionRoot(
      id: 'collection-1',
      name: 'Shared',
      updatedAt: DateTime(2026, 8, 4),
    );

    await repository.saveApiToolCollections([collection]);

    expect(repository.workspaceLabel.value, 'Team: Release Team');
    expect(teamData.savedCollections.single.id, 'collection-1');
    expect(localStore.apiToolCollections, isEmpty);
  });

  test('team repository keeps request history local only', () async {
    SharedPreferences.setMockInitialValues({});
    final localStore = await ProjectStoreService().init();
    final auth = await _teamAuthService().init(firebaseEnabled: true);
    await auth.signIn(email: 'dev@example.com', password: 'secret123');
    final teamData = _FakeTeamApiToolDataSource();
    final repository = await ApiToolRepositoryService(
      localStore: localStore,
      auth: auth,
      teamDataSource: teamData,
    ).init(firebaseEnabled: true);
    final request = ApiToolRequest(
      id: 'request-1',
      name: 'Shared',
      method: ApiToolMethod.post,
      url: 'https://example.com/users',
      updatedAt: DateTime(2026, 8, 4),
    );
    await localStore.saveApiToolHistory([
      ApiToolHistoryEntry(
        id: 'history-1',
        request: request,
        sentAt: DateTime(2026, 8, 4),
        statusCode: 200,
      ),
    ]);

    await repository.saveApiToolRequests([request]);

    expect(teamData.savedRequests.single.id, 'request-1');
    expect(localStore.apiToolHistory.single.id, 'history-1');
    expect(localStore.apiToolRequests, isEmpty);
  });

  test('imports HTTP Tools into local workspace', () async {
    SharedPreferences.setMockInitialValues({});
    final localStore = await ProjectStoreService().init();
    final repository = await ApiToolRepositoryService(
      localStore: localStore,
    ).init(firebaseEnabled: false);
    final now = DateTime(2026, 8, 5);
    final collection = ApiToolCollectionRoot(
      id: 'postman-collection',
      name: 'Postman Import',
      updatedAt: now,
    );
    final folder = ApiToolCollectionFolder(
      id: 'postman-folder',
      collectionId: collection.id,
      name: 'Auth',
      updatedAt: now,
    );
    final request = ApiToolRequest(
      id: 'postman-request',
      name: 'Login',
      method: ApiToolMethod.post,
      url: 'https://example.com/login',
      collectionId: collection.id,
      folderId: folder.id,
      updatedAt: now,
    );

    await repository.importApiTools(
      collections: [collection],
      folders: [folder],
      requests: [request],
    );

    expect(localStore.apiToolCollections.single.id, collection.id);
    expect(localStore.apiToolFolders.single.id, folder.id);
    expect(localStore.apiToolRequests.single.id, request.id);
    expect(repository.apiToolRequests.single.name, 'Login');
  });

  test('imports HTTP Tools into team workspace', () async {
    SharedPreferences.setMockInitialValues({});
    final localStore = await ProjectStoreService().init();
    final auth = await _teamAuthService().init(firebaseEnabled: true);
    await auth.signIn(email: 'dev@example.com', password: 'secret123');
    final teamData = _FakeTeamApiToolDataSource();
    final repository = await ApiToolRepositoryService(
      localStore: localStore,
      auth: auth,
      teamDataSource: teamData,
    ).init(firebaseEnabled: true);
    final now = DateTime(2026, 8, 5);
    final collection = ApiToolCollectionRoot(
      id: 'postman-collection',
      name: 'Postman Import',
      updatedAt: now,
    );
    final request = ApiToolRequest(
      id: 'postman-request',
      name: 'Login',
      method: ApiToolMethod.post,
      url: 'https://example.com/login',
      collectionId: collection.id,
      updatedAt: now,
    );

    await repository.importApiTools(
      collections: [collection],
      folders: const [],
      requests: [request],
    );

    expect(teamData.savedCollections.single.id, collection.id);
    expect(teamData.savedRequests.single.id, request.id);
    expect(localStore.apiToolCollections, isEmpty);
    expect(repository.apiToolRequests.single.name, 'Login');
  });
}

AuthService _teamAuthService() {
  return AuthService(
    sessionStore: _MemorySessionStore(),
    backend: _FakeAuthBackend(
      const AuthBackendUser(
        uid: 'uid-1',
        email: 'dev@example.com',
        displayName: 'Dev',
      ),
    ),
    teamDataSource: _FakeTeamDataSource(
      const TeamMembership(
        teamId: 'team-1',
        teamName: 'Release Team',
        role: TeamRole.dev,
      ),
    ),
    now: () => DateTime(2026, 8, 4),
  );
}

class _FakeTeamApiToolDataSource implements TeamApiToolDataSource {
  ApiToolRepositorySnapshot snapshot = const ApiToolRepositorySnapshot();
  List<ApiToolCollectionRoot> savedCollections = const [];
  List<ApiToolCollectionFolder> savedFolders = const [];
  List<ApiToolRequest> savedRequests = const [];

  @override
  Future<ApiToolRepositorySnapshot> load(String teamId) async => snapshot;

  @override
  Future<void> saveCollections(
    String teamId,
    List<ApiToolCollectionRoot> collections,
  ) async {
    savedCollections = collections;
    snapshot = ApiToolRepositorySnapshot(
      collections: collections,
      folders: snapshot.folders,
      requests: snapshot.requests,
    );
  }

  @override
  Future<void> saveFolders(
    String teamId,
    List<ApiToolCollectionFolder> folders,
  ) async {
    savedFolders = folders;
    snapshot = ApiToolRepositorySnapshot(
      collections: snapshot.collections,
      folders: folders,
      requests: snapshot.requests,
    );
  }

  @override
  Future<void> saveRequests(
    String teamId,
    List<ApiToolRequest> requests,
  ) async {
    savedRequests = requests;
    snapshot = ApiToolRepositorySnapshot(
      collections: snapshot.collections,
      folders: snapshot.folders,
      requests: requests,
    );
  }
}

class _MemorySessionStore implements AuthSessionStore {
  AuthSessionMetadata? _session;

  @override
  AuthSessionMetadata? get authSession => _session;

  @override
  Future<void> saveAuthSession(AuthSessionMetadata session) async {
    _session = session;
  }

  @override
  Future<void> clearAuthSession() async {
    _session = null;
  }
}

class _FakeAuthBackend implements AuthBackend {
  _FakeAuthBackend(this.user);

  final AuthBackendUser user;
  final _controller = StreamController<AuthBackendUser?>.broadcast();
  AuthBackendUser? _currentUser;

  @override
  AuthBackendUser? get currentUser => _currentUser;

  @override
  Stream<AuthBackendUser?> authStateChanges() => _controller.stream;

  @override
  Future<AuthBackendUser> signIn({
    required String email,
    required String password,
  }) async {
    _currentUser = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<AuthBackendUser> createUser({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _currentUser = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _controller.add(null);
  }
}

class _FakeTeamDataSource implements TeamDataSource {
  const _FakeTeamDataSource(this.membership);

  final TeamMembership membership;

  @override
  Future<void> upsertUserProfile({
    required String uid,
    required String email,
    required String displayName,
  }) async {}

  @override
  Future<TeamMembership?> loadMembershipForUser(String uid) async => membership;

  @override
  Future<TeamMembership> createTeamForUser({
    required String uid,
    required String email,
    required String displayName,
    required String teamName,
  }) async => membership;

  @override
  Future<TeamMembership> joinTeamWithInvite({
    required String uid,
    required String email,
    required String displayName,
    required String inviteCode,
  }) async => membership;

  @override
  Future<CreatedTeamInvite> createInvite({
    required String teamId,
    required String createdByUid,
    required TeamRole role,
    required DateTime expiresAt,
  }) async {
    return CreatedTeamInvite(
      id: 'invite-1',
      code: '$teamId:CODE',
      role: role,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<List<TeamMemberProfile>> listMembers(String teamId) async => const [];

  @override
  Future<void> updateMemberRole({
    required String teamId,
    required String uid,
    required TeamRole role,
  }) async {}

  @override
  Future<void> removeMember({
    required String teamId,
    required String uid,
  }) async {}
}
