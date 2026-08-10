enum TeamRole { admin, dev }

extension TeamRoleLabel on TeamRole {
  String get value => switch (this) {
    TeamRole.admin => 'admin',
    TeamRole.dev => 'dev',
  };

  String get label => switch (this) {
    TeamRole.admin => 'Admin',
    TeamRole.dev => 'Dev',
  };

  bool get canManageTeam => this == TeamRole.admin;
  bool get canEditApiTools => this == TeamRole.admin || this == TeamRole.dev;

  static TeamRole fromValue(Object? value) {
    final raw = value?.toString().trim().toLowerCase() ?? '';
    return switch (raw) {
      'admin' => TeamRole.admin,
      'dev' => TeamRole.dev,
      _ => TeamRole.dev,
    };
  }
}

enum AuthStatus {
  initializing,
  unavailable,
  unauthenticated,
  teamRequired,
  authenticated,
}

class AuthSessionMetadata {
  const AuthSessionMetadata({
    required this.uid,
    required this.signedInAt,
    required this.expiresAt,
  });

  final String uid;
  final DateTime signedInAt;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => !expiresAt.isAfter(now);

  Map<String, Object?> toJson() {
    return {
      'uid': uid,
      'signedInAt': signedInAt.toUtc().toIso8601String(),
      'expiresAt': expiresAt.toUtc().toIso8601String(),
    };
  }

  factory AuthSessionMetadata.fromJson(Map<String, Object?> json) {
    return AuthSessionMetadata(
      uid: _string(json['uid']),
      signedInAt:
          _date(json['signedInAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      expiresAt:
          _date(json['expiresAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class CurrentUserProfile {
  const CurrentUserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.teamId,
    required this.teamName,
    required this.role,
    required this.sessionExpiresAt,
  });

  final String uid;
  final String email;
  final String displayName;
  final String teamId;
  final String teamName;
  final TeamRole? role;
  final DateTime sessionExpiresAt;

  bool get hasTeam => teamId.isNotEmpty && role != null;
  bool get canManageTeam => role?.canManageTeam ?? false;
  bool get canEditApiTools => role?.canEditApiTools ?? false;

  CurrentUserProfile copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? teamId,
    String? teamName,
    TeamRole? role,
    DateTime? sessionExpiresAt,
  }) {
    return CurrentUserProfile(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      teamId: teamId ?? this.teamId,
      teamName: teamName ?? this.teamName,
      role: role ?? this.role,
      sessionExpiresAt: sessionExpiresAt ?? this.sessionExpiresAt,
    );
  }
}

class TeamMembership {
  const TeamMembership({
    required this.teamId,
    required this.teamName,
    required this.role,
    this.status = 'active',
  });

  final String teamId;
  final String teamName;
  final TeamRole role;
  final String status;

  bool get isActive => status == 'active';
}

class TeamMemberProfile {
  const TeamMemberProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.status,
    required this.joinedAt,
  });

  final String uid;
  final String email;
  final String displayName;
  final TeamRole role;
  final String status;
  final DateTime? joinedAt;
}

class CreatedTeamInvite {
  const CreatedTeamInvite({
    required this.id,
    required this.code,
    required this.role,
    required this.expiresAt,
  });

  final String id;
  final String code;
  final TeamRole role;
  final DateTime expiresAt;
}

abstract class AuthSessionStore {
  AuthSessionMetadata? get authSession;
  Future<void> saveAuthSession(AuthSessionMetadata session);
  Future<void> clearAuthSession();
}

String _string(Object? value) => value?.toString() ?? '';

DateTime? _date(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}
