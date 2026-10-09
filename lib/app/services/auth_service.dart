import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:app_management_center/app/data/amc_api_client.dart';
import 'package:app_management_center/app/models/auth_models.dart';
import 'package:app_management_center/app/services/auth_token_store_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:get/get.dart';

const authSessionDuration = Duration(days: 30);
const defaultInviteDuration = Duration(days: 7);
const minimumPasswordLength = 8;
const passwordKeyIterations = 100000;

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

  /// Loads the persisted sign-in, if any, into [currentUser].
  Future<void> restore();
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

/// Stretches the password on the client so the raw password never leaves the
/// machine and the Worker only runs a cheap HMAC (Free plan CPU limit).
Future<String> derivePasswordKey({
  required String email,
  required String password,
  int iterations = passwordKeyIterations,
}) {
  final salt = 'amc-auth-v1:${email.trim().toLowerCase()}';
  return Isolate.run(() async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: utf8.encode(salt));
    return base64UrlEncode(await key.extractBytes()).replaceAll('=', '');
  });
}

class AmcAuthBackend implements AuthBackend {
  AmcAuthBackend({
    required AmcApiClient api,
    required AuthTokenStoreService tokenStore,
    Future<String> Function({required String email, required String password})?
    deriveKey,
  }) : _api = api,
       _tokenStore = tokenStore,
       _deriveKey = deriveKey ?? derivePasswordKey;

  final AmcApiClient _api;
  final AuthTokenStoreService _tokenStore;
  final Future<String> Function({
    required String email,
    required String password,
  })
  _deriveKey;
  AuthBackendUser? _currentUser;

  @override
  AuthBackendUser? get currentUser => _currentUser;

  @override
  Future<void> restore() async {
    final token = await _tokenStore.readToken();
    if (token == null || token.isEmpty) {
      _currentUser = null;
      return;
    }
    try {
      final body = await _api.get('/me');
      _currentUser = _userFromJson(body['user']);
    } on AmcApiException catch (error) {
      if (!error.isUnauthorized) rethrow;
      await _tokenStore.saveToken(null);
      _currentUser = null;
    }
  }

  @override
  Future<AuthBackendUser> signIn({
    required String email,
    required String password,
  }) async {
    final body = await _api.post(
      '/auth/login',
      authenticated: false,
      body: {
        'email': email.trim(),
        'passwordKey': await _deriveKey(email: email, password: password),
      },
    );
    return _acceptSession(body);
  }

  @override
  Future<AuthBackendUser> createUser({
    required String email,
    required String password,
    required String displayName,
  }) async {
    if (password.length < minimumPasswordLength) {
      throw const AuthServiceException(
        'Mật khẩu phải có ít nhất $minimumPasswordLength ký tự.',
      );
    }
    final body = await _api.post(
      '/auth/register',
      authenticated: false,
      body: {
        'email': email.trim(),
        'passwordKey': await _deriveKey(email: email, password: password),
        'displayName': displayName.trim(),
      },
    );
    return _acceptSession(body);
  }

  @override
  Future<void> signOut() async {
    try {
      if ((await _tokenStore.readToken())?.isNotEmpty ?? false) {
        await _api.post('/auth/logout');
      }
    } on AmcApiException {
      // The local sign-out still completes when the server is unreachable.
    } finally {
      await _tokenStore.saveToken(null);
      _currentUser = null;
    }
  }

  Future<AuthBackendUser> _acceptSession(Map<String, Object?> body) async {
    final token = body['token']?.toString() ?? '';
    final user = _userFromJson(body['user']);
    if (token.isEmpty || user == null) {
      throw const AuthServiceException('Server không trả về phiên đăng nhập.');
    }
    await _tokenStore.saveToken(token);
    _currentUser = user;
    return user;
  }

  static AuthBackendUser? _userFromJson(Object? value) {
    if (value is! Map) return null;
    final uid = _string(value['uid']);
    if (uid.isEmpty) return null;
    return AuthBackendUser(
      uid: uid,
      email: _string(value['email']),
      displayName: _string(value['displayName']),
    );
  }
}

/// Team operations for the signed-in user; the server derives the user from
/// the session token.
abstract class TeamDataSource {
  Future<TeamMembership?> loadMembership();
  Future<TeamMembership> createTeam(String teamName);
  Future<TeamMembership> joinTeamWithInvite(String inviteCode);
  Future<CreatedTeamInvite> createInvite({
    required String teamId,
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

class AmcTeamDataSource implements TeamDataSource {
  AmcTeamDataSource(this._api);

  final AmcApiClient _api;

  @override
  Future<TeamMembership?> loadMembership() async {
    final body = await _api.get('/me');
    return _membershipFromJson(body['membership']);
  }

  @override
  Future<TeamMembership> createTeam(String teamName) async {
    final trimmedName = teamName.trim();
    if (trimmedName.isEmpty) {
      throw const AuthServiceException('Phải nhập tên nhóm.');
    }
    final body = await _api.post('/teams', body: {'name': trimmedName});
    return _requireMembership(body['membership']);
  }

  @override
  Future<TeamMembership> joinTeamWithInvite(String inviteCode) async {
    final body = await _api.post(
      '/teams/join',
      body: {'inviteCode': inviteCode.trim()},
    );
    return _requireMembership(body['membership']);
  }

  @override
  Future<CreatedTeamInvite> createInvite({
    required String teamId,
    required TeamRole role,
    required DateTime expiresAt,
  }) async {
    final body = await _api.post(
      '/teams/${Uri.encodeComponent(teamId)}/invites',
      body: {
        'role': role.value,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
      },
    );
    return CreatedTeamInvite(
      id: _string(body['id']),
      code: _string(body['code']),
      role: TeamRoleLabel.fromValue(body['role']),
      expiresAt: _date(body['expiresAt']) ?? expiresAt,
    );
  }

  @override
  Future<List<TeamMemberProfile>> listMembers(String teamId) async {
    final body = await _api.get(
      '/teams/${Uri.encodeComponent(teamId)}/members',
    );
    final members = body['members'] is List
        ? body['members'] as List
        : const [];
    return [
      for (final member in members.whereType<Map>())
        TeamMemberProfile(
          uid: _string(member['uid']),
          email: _string(member['email']),
          displayName: _string(member['displayName']),
          role: TeamRoleLabel.fromValue(member['role']),
          status: _string(member['status']).isEmpty
              ? 'active'
              : _string(member['status']),
          joinedAt: _date(member['joinedAt']),
        ),
    ];
  }

  @override
  Future<void> updateMemberRole({
    required String teamId,
    required String uid,
    required TeamRole role,
  }) async {
    await _api.patch(
      '/teams/${Uri.encodeComponent(teamId)}/members/${Uri.encodeComponent(uid)}',
      body: {'role': role.value},
    );
  }

  @override
  Future<void> removeMember({
    required String teamId,
    required String uid,
  }) async {
    await _api.delete(
      '/teams/${Uri.encodeComponent(teamId)}/members/${Uri.encodeComponent(uid)}',
    );
  }

  static TeamMembership _requireMembership(Object? value) {
    final membership = _membershipFromJson(value);
    if (membership == null) {
      throw const AuthServiceException(
        'Server không trả về quyền truy cập nhóm.',
      );
    }
    return membership;
  }

  static TeamMembership? _membershipFromJson(Object? value) {
    if (value is! Map) return null;
    final teamId = _string(value['teamId']);
    final status = _string(value['status']);
    if (teamId.isEmpty || (status.isNotEmpty && status != 'active')) {
      return null;
    }
    return TeamMembership(
      teamId: teamId,
      teamName: _string(value['teamName']).isEmpty
          ? 'Team'
          : _string(value['teamName']),
      role: TeamRoleLabel.fromValue(value['role']),
      status: status.isEmpty ? 'active' : status,
    );
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
  final AuthBackend? _backend;
  final TeamDataSource? _teamDataSource;

  final authStatus = AuthStatus.initializing.obs;
  final profile = Rxn<CurrentUserProfile>();
  final authError = ''.obs;
  final isBusy = false.obs;
  var _backendConfigured = false;

  bool get backendConfigured => _backendConfigured;
  bool get isAuthenticated =>
      authStatus.value == AuthStatus.authenticated && profile.value != null;

  Future<AuthService> init({required bool backendConfigured}) async {
    _backendConfigured =
        backendConfigured && _backend != null && _teamDataSource != null;
    if (!_backendConfigured) {
      authStatus.value = AuthStatus.unavailable;
      return this;
    }

    try {
      await _backend!.restore();
    } catch (error) {
      authError.value = 'Không khôi phục được đăng nhập: $error';
    }
    await _syncUser(_backend!.currentUser);
    return this;
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
      final membership = await _requireTeamDataSource().createTeam(teamName);
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
        inviteCode,
      );
      _setProfile(user, membership);
    });
  }

  Future<void> createTeamForCurrentUser(String teamName) async {
    await _runAuthAction(() async {
      final user = _requireCurrentUser();
      final membership = await _requireTeamDataSource().createTeam(teamName);
      _setProfile(user, membership);
    });
  }

  Future<void> joinCurrentUserWithInvite(String inviteCode) async {
    await _runAuthAction(() async {
      final user = _requireCurrentUser();
      final membership = await _requireTeamDataSource().joinTeamWithInvite(
        inviteCode,
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
      throw const AuthServiceException('Chỉ Admin mới tạo được lời mời.');
    }
    return _requireTeamDataSource().createInvite(
      teamId: current.teamId,
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
      throw const AuthServiceException('Chỉ Admin mới đổi được vai trò.');
    }
    if (uid == current.uid) {
      throw const AuthServiceException(
        'Bạn không đổi được vai trò của chính mình.',
      );
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
      throw const AuthServiceException('Chỉ Admin mới xoá được thành viên.');
    }
    if (uid == current.uid) {
      throw const AuthServiceException('Bạn không tự xoá mình được.');
    }
    await _requireTeamDataSource().removeMember(
      teamId: current.teamId,
      uid: uid,
    );
  }

  Future<void> reloadProfile() async {
    await _syncUser(_requireBackend().currentUser);
  }

  Future<void> signOut() async {
    await _sessionStore.clearAuthSession();
    profile.value = null;
    authStatus.value = AuthStatus.unauthenticated;
    await _requireBackend().signOut();
  }

  /// Called when the server rejects the stored session (expired or revoked).
  Future<void> handleSessionRejected() async {
    if (profile.value == null) return;
    authError.value = 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.';
    await signOut();
  }

  Future<void> _syncUser(AuthBackendUser? user) async {
    if (!_backendConfigured) return;
    if (user == null) {
      profile.value = null;
      authStatus.value = AuthStatus.unauthenticated;
      return;
    }

    final session = _sessionStore.authSession;
    if (session != null &&
        session.uid == user.uid &&
        session.isExpired(_now())) {
      authError.value = 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.';
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
      final membership = await _requireTeamDataSource().loadMembership();
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
      authError.value = 'Không tải được quyền truy cập nhóm: $error';
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
    _ensureBackendAvailable();
    if (isBusy.value) return;
    isBusy.value = true;
    authError.value = '';
    try {
      await action();
    } on AuthServiceException catch (error) {
      authError.value = error.message;
      rethrow;
    } on AmcApiException catch (error) {
      authError.value = error.message;
      throw AuthServiceException(error.message);
    } catch (error) {
      authError.value = 'Xác thực lỗi: $error';
      throw AuthServiceException(authError.value);
    } finally {
      isBusy.value = false;
    }
  }

  AuthBackend _requireBackend() {
    final backend = _backend;
    if (backend == null) {
      throw const AuthServiceException('Chưa cấu hình server đăng nhập.');
    }
    return backend;
  }

  TeamDataSource _requireTeamDataSource() {
    final dataSource = _teamDataSource;
    if (dataSource == null) {
      throw const AuthServiceException('Chưa cấu hình database của nhóm.');
    }
    return dataSource;
  }

  AuthBackendUser _requireCurrentUser() {
    final user = _requireBackend().currentUser;
    if (user == null) {
      throw const AuthServiceException('Hãy đăng nhập trước.');
    }
    return user;
  }

  CurrentUserProfile _requireProfile() {
    final current = profile.value;
    if (current == null || !current.hasTeam) {
      throw const AuthServiceException('Cần có quyền truy cập nhóm.');
    }
    return current;
  }

  void _ensureBackendAvailable() {
    if (!_backendConfigured) {
      throw const AuthServiceException('Chưa cấu hình server đăng nhập.');
    }
  }
}

String _string(Object? value) => value?.toString() ?? '';

DateTime? _date(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}
