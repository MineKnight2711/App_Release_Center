import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_release_center/app/models/auth_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

const authSessionDuration = Duration(days: 30);
const defaultInviteDuration = Duration(days: 7);

class AuthServiceException implements Exception {
  const AuthServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthBackendUser {
  const AuthBackendUser({
    required this.uid,
    required this.email,
    required this.displayName,
  });

  final String uid;
  final String email;
  final String displayName;
}

abstract class AuthBackend {
  AuthBackendUser? get currentUser;
  Stream<AuthBackendUser?> authStateChanges();
  Future<AuthBackendUser> signIn({
    required String email,
    required String password,
  });
  Future<AuthBackendUser> createUser({
    required String email,
    required String password,
    required String displayName,
  });
  Future<void> signOut();
}

class FirebaseAuthBackend implements AuthBackend {
  FirebaseAuthBackend({firebase_auth.FirebaseAuth? auth})
    : _auth = auth ?? firebase_auth.FirebaseAuth.instance;

  final firebase_auth.FirebaseAuth _auth;

  @override
  AuthBackendUser? get currentUser => _fromFirebaseUser(_auth.currentUser);

  @override
  Stream<AuthBackendUser?> authStateChanges() {
    return _auth.authStateChanges().map(_fromFirebaseUser);
  }

  @override
  Future<AuthBackendUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthServiceException('Sign in did not return a user.');
      }
      return _fromFirebaseUser(user)!;
    } on firebase_auth.FirebaseAuthException catch (error) {
      throw AuthServiceException(_firebaseAuthMessage(error));
    }
  }

  @override
  Future<AuthBackendUser> createUser({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthServiceException('Registration did not return a user.');
      }
      final trimmedName = displayName.trim();
      if (trimmedName.isNotEmpty) {
        await user.updateDisplayName(trimmedName);
        await user.reload();
      }
      return _fromFirebaseUser(_auth.currentUser ?? user)!;
    } on firebase_auth.FirebaseAuthException catch (error) {
      throw AuthServiceException(_firebaseAuthMessage(error));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  static AuthBackendUser? _fromFirebaseUser(firebase_auth.User? user) {
    if (user == null) return null;
    return AuthBackendUser(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? '',
    );
  }
}

abstract class TeamDataSource {
  Future<void> upsertUserProfile({
    required String uid,
    required String email,
    required String displayName,
  });
  Future<TeamMembership?> loadMembershipForUser(String uid);
  Future<TeamMembership> createTeamForUser({
    required String uid,
    required String email,
    required String displayName,
    required String teamName,
  });
  Future<TeamMembership> joinTeamWithInvite({
    required String uid,
    required String email,
    required String displayName,
    required String inviteCode,
  });
  Future<CreatedTeamInvite> createInvite({
    required String teamId,
    required String createdByUid,
    required TeamRole role,
    required DateTime expiresAt,
  });
  Future<List<TeamMemberProfile>> listMembers(String teamId);
  Future<void> updateMemberRole({
    required String teamId,
    required String uid,
    required TeamRole role,
  });
  Future<void> removeMember({required String teamId, required String uid});
}

class FirebaseTeamDataSource implements TeamDataSource {
  FirebaseTeamDataSource({FirebaseFirestore? firestore, Uuid? uuid})
    : _db = firestore ?? FirebaseFirestore.instance,
      _uuid = uuid ?? const Uuid();

  final FirebaseFirestore _db;
  final Uuid _uuid;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  @override
  Future<void> upsertUserProfile({
    required String uid,
    required String email,
    required String displayName,
  }) async {
    final now = FieldValue.serverTimestamp();
    await _users.doc(uid).set({
      'email': email.trim(),
      'displayName': displayName.trim(),
      'updatedAt': now,
      'lastLoginAt': now,
    }, SetOptions(merge: true));
  }

  @override
  Future<TeamMembership?> loadMembershipForUser(String uid) async {
    final userSnapshot = await _users.doc(uid).get();
    final userData = userSnapshot.data();
    final teamId = _string(userData?['activeTeamId']);
    if (teamId.isEmpty) return null;

    final teamRef = _db.collection('teams').doc(teamId);
    final results = await Future.wait([
      teamRef.get(),
      teamRef.collection('members').doc(uid).get(),
    ]);
    final teamSnapshot = results[0];
    final memberSnapshot = results[1];
    final teamData = teamSnapshot.data();
    final memberData = memberSnapshot.data();

    if (!teamSnapshot.exists || !memberSnapshot.exists || memberData == null) {
      return null;
    }

    final status = _string(memberData['status']);
    if (status != 'active') return null;

    return TeamMembership(
      teamId: teamId,
      teamName: _string(teamData?['name']).isEmpty
          ? 'Team'
          : _string(teamData?['name']),
      role: TeamRoleLabel.fromValue(memberData['role']),
      status: status,
    );
  }

  @override
  Future<TeamMembership> createTeamForUser({
    required String uid,
    required String email,
    required String displayName,
    required String teamName,
  }) async {
    final trimmedName = teamName.trim();
    if (trimmedName.isEmpty) {
      throw const AuthServiceException('Team name is required.');
    }

    final teamRef = _db.collection('teams').doc();
    final userRef = _users.doc(uid);
    final memberRef = teamRef.collection('members').doc(uid);

    await _db.runTransaction((transaction) async {
      final now = FieldValue.serverTimestamp();
      transaction.set(teamRef, {
        'name': trimmedName,
        'createdByUid': uid,
        'createdAt': now,
        'updatedAt': now,
      });
      transaction.set(memberRef, {
        'uid': uid,
        'role': TeamRole.admin.value,
        'status': 'active',
        'joinedAt': now,
        'updatedAt': now,
      });
      transaction.set(userRef, {
        'email': email.trim(),
        'displayName': displayName.trim(),
        'activeTeamId': teamRef.id,
        'updatedAt': now,
        'lastLoginAt': now,
      }, SetOptions(merge: true));
    });

    return TeamMembership(
      teamId: teamRef.id,
      teamName: trimmedName,
      role: TeamRole.admin,
    );
  }

  @override
  Future<TeamMembership> joinTeamWithInvite({
    required String uid,
    required String email,
    required String displayName,
    required String inviteCode,
  }) async {
    final parsed = _parseInviteCode(inviteCode);
    final inviteHash = await _inviteCodeHash(parsed.teamId, parsed.secret);
    final inviteQuery = await _db
        .collection('teams')
        .doc(parsed.teamId)
        .collection('invites')
        .where('codeHash', isEqualTo: inviteHash)
        .limit(1)
        .get();
    if (inviteQuery.docs.isEmpty) {
      throw const AuthServiceException('Invite code is invalid or expired.');
    }

    final teamRef = _db.collection('teams').doc(parsed.teamId);
    final inviteRef = inviteQuery.docs.first.reference;
    final memberRef = teamRef.collection('members').doc(uid);
    final userRef = _users.doc(uid);
    late TeamMembership membership;

    await _db.runTransaction((transaction) async {
      final inviteSnapshot = await transaction.get(inviteRef);
      if (!inviteSnapshot.exists) {
        throw const AuthServiceException('Invite code is invalid or expired.');
      }

      final invite = inviteSnapshot.data();
      final expiresAt = _date(invite?['expiresAt']);
      if (_string(invite?['status']) != 'active' ||
          expiresAt == null ||
          !expiresAt.isAfter(DateTime.now())) {
        throw const AuthServiceException('Invite code is invalid or expired.');
      }

      final role = TeamRoleLabel.fromValue(invite?['role']);
      final now = FieldValue.serverTimestamp();
      transaction.set(memberRef, {
        'uid': uid,
        'role': role.value,
        'status': 'active',
        'joinedViaInviteId': inviteRef.id,
        'joinedAt': now,
        'updatedAt': now,
      });
      transaction.set(userRef, {
        'email': email.trim(),
        'displayName': displayName.trim(),
        'activeTeamId': parsed.teamId,
        'updatedAt': now,
        'lastLoginAt': now,
      }, SetOptions(merge: true));
      transaction.update(inviteRef, {
        'status': 'used',
        'usedByUid': uid,
        'usedAt': now,
      });
      membership = TeamMembership(
        teamId: parsed.teamId,
        teamName: 'Team',
        role: role,
      );
    });

    return await loadMembershipForUser(uid) ?? membership;
  }

  @override
  Future<CreatedTeamInvite> createInvite({
    required String teamId,
    required String createdByUid,
    required TeamRole role,
    required DateTime expiresAt,
  }) async {
    final secret = _newInviteSecret();
    final code = '$teamId:$secret';
    final invite = CreatedTeamInvite(
      id: _uuid.v4(),
      code: code,
      role: role,
      expiresAt: expiresAt,
    );
    await _db
        .collection('teams')
        .doc(teamId)
        .collection('invites')
        .doc(invite.id)
        .set({
          'codeHash': await _inviteCodeHash(teamId, secret),
          'role': role.value,
          'status': 'active',
          'createdByUid': createdByUid,
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(expiresAt.toUtc()),
        });
    return invite;
  }

  @override
  Future<List<TeamMemberProfile>> listMembers(String teamId) async {
    final membersSnapshot = await _db
        .collection('teams')
        .doc(teamId)
        .collection('members')
        .get();
    final members = <TeamMemberProfile>[];
    for (final doc in membersSnapshot.docs) {
      final data = doc.data();
      final userSnapshot = await _users.doc(doc.id).get();
      final userData = userSnapshot.data();
      members.add(
        TeamMemberProfile(
          uid: doc.id,
          email: _string(userData?['email']),
          displayName: _string(userData?['displayName']),
          role: TeamRoleLabel.fromValue(data['role']),
          status: _string(data['status']).isEmpty
              ? 'active'
              : _string(data['status']),
          joinedAt: _date(data['joinedAt']),
        ),
      );
    }
    members.sort((a, b) {
      final byRole = a.role.index.compareTo(b.role.index);
      if (byRole != 0) return byRole;
      return a.email.toLowerCase().compareTo(b.email.toLowerCase());
    });
    return members;
  }

  @override
  Future<void> updateMemberRole({
    required String teamId,
    required String uid,
    required TeamRole role,
  }) async {
    await _db
        .collection('teams')
        .doc(teamId)
        .collection('members')
        .doc(uid)
        .set({
          'role': role.value,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  @override
  Future<void> removeMember({required String teamId, required String uid}) {
    return _db
        .collection('teams')
        .doc(teamId)
        .collection('members')
        .doc(uid)
        .delete();
  }

  String _newInviteSecret() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
      10,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}

class AuthService extends GetxService {
  AuthService({
    required AuthSessionStore sessionStore,
    AuthBackend? backend,
    TeamDataSource? teamDataSource,
    DateTime Function()? now,
  }) : _sessionStore = sessionStore,
       _backend = backend,
       _teamDataSource = teamDataSource,
       _now = now ?? DateTime.now;

  final AuthSessionStore _sessionStore;
  final DateTime Function() _now;
  AuthBackend? _backend;
  TeamDataSource? _teamDataSource;
  StreamSubscription<AuthBackendUser?>? _authSubscription;

  final authStatus = AuthStatus.initializing.obs;
  final profile = Rxn<CurrentUserProfile>();
  final authError = ''.obs;
  final isBusy = false.obs;
  var _firebaseEnabled = false;

  bool get firebaseEnabled => _firebaseEnabled;
  bool get isAuthenticated =>
      authStatus.value == AuthStatus.authenticated && profile.value != null;

  Future<AuthService> init({required bool firebaseEnabled}) async {
    _firebaseEnabled = firebaseEnabled;
    if (!firebaseEnabled) {
      authStatus.value = AuthStatus.unavailable;
      return this;
    }

    _backend ??= FirebaseAuthBackend();
    _teamDataSource ??= FirebaseTeamDataSource();
    _authSubscription = _backend!.authStateChanges().listen(
      (user) => unawaited(_syncFirebaseUser(user)),
      onError: (Object error) {
        authError.value = 'Could not read sign-in state: $error';
        authStatus.value = AuthStatus.unauthenticated;
      },
    );

    await _syncFirebaseUser(_backend!.currentUser);
    return this;
  }

  @override
  void onClose() {
    unawaited(_authSubscription?.cancel());
    super.onClose();
  }

  Future<void> signIn({required String email, required String password}) async {
    await _runAuthAction(() async {
      final user = await _requireBackend().signIn(
        email: email,
        password: password,
      );
      await _startSession(user.uid);
      await _loadProfile(user);
    });
  }

  Future<void> registerWithNewTeam({
    required String email,
    required String password,
    required String displayName,
    required String teamName,
  }) async {
    await _runAuthAction(() async {
      final user = await _requireBackend().createUser(
        email: email,
        password: password,
        displayName: displayName,
      );
      await _startSession(user.uid);
      await _requireTeamDataSource().upsertUserProfile(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
      );
      final membership = await _requireTeamDataSource().createTeamForUser(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        teamName: teamName,
      );
      _setProfile(user, membership);
    });
  }

  Future<void> registerWithInvite({
    required String email,
    required String password,
    required String displayName,
    required String inviteCode,
  }) async {
    await _runAuthAction(() async {
      final user = await _requireBackend().createUser(
        email: email,
        password: password,
        displayName: displayName,
      );
      await _startSession(user.uid);
      final membership = await _requireTeamDataSource().joinTeamWithInvite(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        inviteCode: inviteCode,
      );
      _setProfile(user, membership);
    });
  }

  Future<void> createTeamForCurrentUser(String teamName) async {
    await _runAuthAction(() async {
      final user = _requireCurrentUser();
      final membership = await _requireTeamDataSource().createTeamForUser(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        teamName: teamName,
      );
      _setProfile(user, membership);
    });
  }

  Future<void> joinCurrentUserWithInvite(String inviteCode) async {
    await _runAuthAction(() async {
      final user = _requireCurrentUser();
      final membership = await _requireTeamDataSource().joinTeamWithInvite(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        inviteCode: inviteCode,
      );
      _setProfile(user, membership);
    });
  }

  Future<CreatedTeamInvite> createInvite({
    TeamRole role = TeamRole.dev,
    Duration duration = defaultInviteDuration,
  }) async {
    final current = _requireProfile();
    if (!current.canManageTeam) {
      throw const AuthServiceException('Only Admin can create invites.');
    }
    return _requireTeamDataSource().createInvite(
      teamId: current.teamId,
      createdByUid: current.uid,
      role: role,
      expiresAt: _now().add(duration),
    );
  }

  Future<List<TeamMemberProfile>> listMembers() async {
    final current = _requireProfile();
    return _requireTeamDataSource().listMembers(current.teamId);
  }

  Future<void> updateMemberRole({
    required String uid,
    required TeamRole role,
  }) async {
    final current = _requireProfile();
    if (!current.canManageTeam) {
      throw const AuthServiceException('Only Admin can change roles.');
    }
    if (uid == current.uid) {
      throw const AuthServiceException('You cannot change your own role.');
    }
    await _requireTeamDataSource().updateMemberRole(
      teamId: current.teamId,
      uid: uid,
      role: role,
    );
  }

  Future<void> removeMember(String uid) async {
    final current = _requireProfile();
    if (!current.canManageTeam) {
      throw const AuthServiceException('Only Admin can remove members.');
    }
    if (uid == current.uid) {
      throw const AuthServiceException('You cannot remove yourself.');
    }
    await _requireTeamDataSource().removeMember(
      teamId: current.teamId,
      uid: uid,
    );
  }

  Future<void> reloadProfile() async {
    await _syncFirebaseUser(_requireBackend().currentUser);
  }

  Future<void> signOut() async {
    await _sessionStore.clearAuthSession();
    profile.value = null;
    authStatus.value = AuthStatus.unauthenticated;
    await _requireBackend().signOut();
  }

  Future<void> _syncFirebaseUser(AuthBackendUser? user) async {
    if (!_firebaseEnabled) return;
    if (user == null) {
      profile.value = null;
      authStatus.value = AuthStatus.unauthenticated;
      return;
    }

    final session = _sessionStore.authSession;
    if (session != null &&
        session.uid == user.uid &&
        session.isExpired(_now())) {
      authError.value = 'Your session expired. Please sign in again.';
      await signOut();
      return;
    }
    if (session == null || session.uid != user.uid) {
      await _startSession(user.uid);
    }
    await _loadProfile(user);
  }

  Future<void> _loadProfile(AuthBackendUser user) async {
    try {
      authStatus.value = AuthStatus.initializing;
      await _requireTeamDataSource().upsertUserProfile(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
      );
      final membership = await _requireTeamDataSource().loadMembershipForUser(
        user.uid,
      );
      _setProfile(user, membership);
    } catch (error) {
      profile.value = CurrentUserProfile(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        teamId: '',
        teamName: '',
        role: null,
        sessionExpiresAt: _sessionStore.authSession?.expiresAt ?? _now(),
      );
      authError.value = 'Could not load team access: $error';
      authStatus.value = AuthStatus.teamRequired;
    }
  }

  void _setProfile(AuthBackendUser user, TeamMembership? membership) {
    final session = _sessionStore.authSession;
    profile.value = CurrentUserProfile(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      teamId: membership?.teamId ?? '',
      teamName: membership?.teamName ?? '',
      role: membership?.role,
      sessionExpiresAt: session?.expiresAt ?? _now().add(authSessionDuration),
    );
    authError.value = '';
    authStatus.value = membership == null
        ? AuthStatus.teamRequired
        : AuthStatus.authenticated;
  }

  Future<void> _startSession(String uid) async {
    final signedInAt = _now();
    await _sessionStore.saveAuthSession(
      AuthSessionMetadata(
        uid: uid,
        signedInAt: signedInAt,
        expiresAt: signedInAt.add(authSessionDuration),
      ),
    );
  }

  Future<void> _runAuthAction(Future<void> Function() action) async {
    _ensureFirebaseAvailable();
    if (isBusy.value) return;
    isBusy.value = true;
    authError.value = '';
    try {
      await action();
    } on AuthServiceException catch (error) {
      authError.value = error.message;
      rethrow;
    } on FirebaseException catch (error) {
      authError.value = _firebaseFirestoreMessage(error);
      throw AuthServiceException(authError.value);
    } catch (error) {
      authError.value = 'Authentication failed: $error';
      throw AuthServiceException(authError.value);
    } finally {
      isBusy.value = false;
    }
  }

  AuthBackend _requireBackend() {
    final backend = _backend;
    if (backend == null) {
      throw const AuthServiceException('Firebase Auth is not configured.');
    }
    return backend;
  }

  TeamDataSource _requireTeamDataSource() {
    final dataSource = _teamDataSource;
    if (dataSource == null) {
      throw const AuthServiceException('Team database is not configured.');
    }
    return dataSource;
  }

  AuthBackendUser _requireCurrentUser() {
    final user = _requireBackend().currentUser;
    if (user == null) {
      throw const AuthServiceException('Please sign in first.');
    }
    return user;
  }

  CurrentUserProfile _requireProfile() {
    final current = profile.value;
    if (current == null || !current.hasTeam) {
      throw const AuthServiceException('Team access is required.');
    }
    return current;
  }

  void _ensureFirebaseAvailable() {
    if (!_firebaseEnabled) {
      throw const AuthServiceException('Firebase is not configured.');
    }
  }
}

String _firebaseAuthMessage(firebase_auth.FirebaseAuthException error) {
  return switch (error.code) {
    'email-already-in-use' => 'This email is already registered.',
    'invalid-email' => 'Email address is invalid.',
    'invalid-credential' => 'Email or password is not correct.',
    'user-not-found' => 'Email or password is not correct.',
    'wrong-password' => 'Email or password is not correct.',
    'weak-password' => 'Password is too weak.',
    _ => error.message ?? 'Firebase Auth failed.',
  };
}

String _firebaseFirestoreMessage(FirebaseException error) {
  final code = error.code.trim().toLowerCase();
  final message = error.message?.trim();
  if (code == 'permission-denied' || code == 'unknown') {
    final suffix = message == null || message.isEmpty ? '' : ' $message';
    return 'Team database permission failed.$suffix';
  }
  final suffix = message == null || message.isEmpty ? '' : ': $message';
  return 'Team database failed (${error.code})$suffix';
}

_ParsedInviteCode _parseInviteCode(String value) {
  final trimmed = value.trim();
  final separator = trimmed.indexOf(':');
  if (separator <= 0 || separator == trimmed.length - 1) {
    throw const AuthServiceException('Invite code is invalid or expired.');
  }
  return _ParsedInviteCode(
    teamId: trimmed.substring(0, separator).trim(),
    secret: trimmed.substring(separator + 1).trim().toUpperCase(),
  );
}

Future<String> _inviteCodeHash(String teamId, String secret) async {
  final digest = await Sha256().hash(utf8.encode('$teamId:$secret'));
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}

String _string(Object? value) => value?.toString() ?? '';

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate().toLocal();
  if (value is DateTime) return value.toLocal();
  final raw = value?.toString();
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

class _ParsedInviteCode {
  const _ParsedInviteCode({required this.teamId, required this.secret});

  final String teamId;
  final String secret;
}
