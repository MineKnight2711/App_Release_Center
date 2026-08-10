import 'dart:async';

import 'package:app_release_center/app/models/auth_models.dart';
import 'package:app_release_center/app/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('team role permissions match v1 policy', () {
    expect(TeamRole.admin.canManageTeam, isTrue);
    expect(TeamRole.admin.canEditApiTools, isTrue);
    expect(TeamRole.dev.canManageTeam, isFalse);
    expect(TeamRole.dev.canEditApiTools, isTrue);
  });

  test('login starts a 30 day session and loads team role', () async {
    final now = DateTime(2026, 8, 4, 9);
    final sessionStore = _MemorySessionStore();
    final backend = _FakeAuthBackend(
      signInUser: const AuthBackendUser(
        uid: 'uid-1',
        email: 'dev@example.com',
        displayName: 'Dev',
      ),
    );
    final teamData = _FakeTeamDataSource(
      membership: const TeamMembership(
        teamId: 'team-1',
        teamName: 'Release Team',
        role: TeamRole.dev,
      ),
    );
    final service = await AuthService(
      sessionStore: sessionStore,
      backend: backend,
      teamDataSource: teamData,
      now: () => now,
    ).init(firebaseEnabled: true);

    await service.signIn(email: 'dev@example.com', password: 'secret123');

    expect(service.authStatus.value, AuthStatus.authenticated);
    expect(service.profile.value?.teamId, 'team-1');
    expect(service.profile.value?.role, TeamRole.dev);
    expect(sessionStore.authSession?.signedInAt, now);
    expect(sessionStore.authSession?.expiresAt, now.add(authSessionDuration));
  });

  test('expired persisted session signs out current Firebase user', () async {
    final now = DateTime(2026, 8, 4, 9);
    final sessionStore = _MemorySessionStore(
      AuthSessionMetadata(
        uid: 'uid-1',
        signedInAt: now.subtract(const Duration(days: 31)),
        expiresAt: now.subtract(const Duration(minutes: 1)),
      ),
    );
    final backend = _FakeAuthBackend(
      currentUser: const AuthBackendUser(
        uid: 'uid-1',
        email: 'dev@example.com',
        displayName: 'Dev',
      ),
    );
    final service = await AuthService(
      sessionStore: sessionStore,
      backend: backend,
      teamDataSource: _FakeTeamDataSource(),
      now: () => now,
    ).init(firebaseEnabled: true);

    expect(service.authStatus.value, AuthStatus.unauthenticated);
    expect(service.profile.value, isNull);
    expect(sessionStore.authSession, isNull);
    expect(backend.didSignOut, isTrue);
  });

  test('register with new team creates an Admin profile', () async {
    final now = DateTime(2026, 8, 4, 9);
    final sessionStore = _MemorySessionStore();
    final backend = _FakeAuthBackend(
      createUser: const AuthBackendUser(
        uid: 'uid-admin',
        email: 'admin@example.com',
        displayName: 'Admin',
      ),
    );
    final teamData = _FakeTeamDataSource();
    final service = await AuthService(
      sessionStore: sessionStore,
      backend: backend,
      teamDataSource: teamData,
      now: () => now,
    ).init(firebaseEnabled: true);

    await service.registerWithNewTeam(
      email: 'admin@example.com',
      password: 'secret123',
      displayName: 'Admin',
      teamName: 'Release Team',
    );

    expect(service.authStatus.value, AuthStatus.authenticated);
    expect(service.profile.value?.role, TeamRole.admin);
    expect(service.profile.value?.teamName, 'Release Team');
    expect(teamData.createdTeamName, 'Release Team');
  });
}

class _MemorySessionStore implements AuthSessionStore {
  _MemorySessionStore([this._session]);

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
  _FakeAuthBackend({
    AuthBackendUser? currentUser,
    AuthBackendUser? signInUser,
    AuthBackendUser? createUser,
  }) : _currentUser = currentUser,
       _signInUser = signInUser,
       _createUser = createUser;

  final _controller = StreamController<AuthBackendUser?>.broadcast();
  AuthBackendUser? _currentUser;
  final AuthBackendUser? _signInUser;
  final AuthBackendUser? _createUser;
  bool didSignOut = false;

  @override
  AuthBackendUser? get currentUser => _currentUser;

  @override
  Stream<AuthBackendUser?> authStateChanges() => _controller.stream;

  @override
  Future<AuthBackendUser> signIn({
    required String email,
    required String password,
  }) async {
    final user =
        _signInUser ??
        AuthBackendUser(uid: 'uid-$email', email: email, displayName: '');
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
    final user =
        _createUser ??
        AuthBackendUser(
          uid: 'uid-$email',
          email: email,
          displayName: displayName,
        );
    _currentUser = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    didSignOut = true;
    _currentUser = null;
    _controller.add(null);
  }
}

class _FakeTeamDataSource implements TeamDataSource {
  _FakeTeamDataSource({this.membership});

  TeamMembership? membership;
  String? createdTeamName;

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
  }) async {
    createdTeamName = teamName;
    membership = TeamMembership(
      teamId: 'team-created',
      teamName: teamName,
      role: TeamRole.admin,
    );
    return membership!;
  }

  @override
  Future<TeamMembership> joinTeamWithInvite({
    required String uid,
    required String email,
    required String displayName,
    required String inviteCode,
  }) async {
    membership = const TeamMembership(
      teamId: 'team-invite',
      teamName: 'Invite Team',
      role: TeamRole.dev,
    );
    return membership!;
  }

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
