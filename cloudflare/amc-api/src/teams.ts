import type { AuthContext } from './auth';
import { randomCode, sha256Base64Url } from './crypto';
import { ApiError, json, noContent, nowIso, readJson, str } from './http';

export type TeamRole = 'admin' | 'dev';

const INVITE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const DEFAULT_INVITE_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_INVITE_MS = 30 * 24 * 60 * 60 * 1000;

export interface Membership {
  teamId: string;
  teamName: string;
  role: TeamRole;
  status: string;
}

export async function loadMembership(
  env: Env,
  uid: string,
  teamId: string | null,
): Promise<Membership | null> {
  if (!teamId) return null;
  const row = await env.DB.prepare(
    `SELECT t.id, t.name, m.role, m.status
     FROM team_members m JOIN teams t ON t.id = m.team_id
     WHERE m.team_id = ?1 AND m.user_id = ?2 AND m.status = 'active'`,
  )
    .bind(teamId, uid)
    .first<{ id: string; name: string; role: TeamRole; status: string }>();
  if (!row) return null;
  return { teamId: row.id, teamName: row.name || 'Team', role: row.role, status: row.status };
}

/** Only active members can see a team; [allowedRoles] narrows writes. */
export async function requireMember(
  env: Env,
  auth: AuthContext,
  teamId: string,
  allowedRoles: readonly TeamRole[] = ['admin', 'dev'],
): Promise<TeamRole> {
  const row = await env.DB.prepare(
    `SELECT role FROM team_members WHERE team_id = ?1 AND user_id = ?2 AND status = 'active'`,
  )
    .bind(teamId, auth.uid)
    .first<{ role: TeamRole }>();
  if (!row) {
    throw new ApiError(403, 'permission-denied', 'Team access is required.');
  }
  if (!allowedRoles.includes(row.role)) {
    throw new ApiError(403, 'permission-denied', 'Your team role does not allow this action.');
  }
  return row.role;
}

export async function createTeam(request: Request, env: Env, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  const name = str(body.name).slice(0, 80);
  if (!name) {
    throw new ApiError(400, 'team-name-required', 'Team name is required.');
  }

  const teamId = crypto.randomUUID();
  const now = nowIso();
  await env.DB.batch([
    env.DB.prepare(
      'INSERT INTO teams (id, name, created_by_uid, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?4)',
    ).bind(teamId, name, auth.uid, now),
    env.DB.prepare(
      `INSERT INTO team_members (team_id, user_id, role, status, joined_at, updated_at)
       VALUES (?1, ?2, 'admin', 'active', ?3, ?3)`,
    ).bind(teamId, auth.uid, now),
    env.DB.prepare('UPDATE users SET active_team_id = ?2, updated_at = ?3 WHERE id = ?1').bind(
      auth.uid,
      teamId,
      now,
    ),
  ]);

  const membership: Membership = { teamId, teamName: name, role: 'admin', status: 'active' };
  return json({ membership }, 201);
}

export async function joinTeam(request: Request, env: Env, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  const { teamId, secret } = parseInviteCode(body.inviteCode);
  const codeHash = await sha256Base64Url(`${teamId}:${secret}`);
  const now = nowIso();

  // Single conditional UPDATE: two users racing for one invite cannot both win.
  const invite = await env.DB.prepare(
    `UPDATE team_invites SET status = 'used', used_by_uid = ?3, used_at = ?4
     WHERE team_id = ?1 AND code_hash = ?2 AND status = 'active' AND expires_at > ?4
     RETURNING id, role`,
  )
    .bind(teamId, codeHash, auth.uid, now)
    .first<{ id: string; role: TeamRole }>();
  if (!invite) {
    throw new ApiError(400, 'invalid-invite', 'Invite code is invalid or expired.');
  }

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO team_members (team_id, user_id, role, status, joined_via_invite_id, joined_at, updated_at)
       VALUES (?1, ?2, ?3, 'active', ?4, ?5, ?5)
       ON CONFLICT (team_id, user_id) DO UPDATE SET
         role = CASE WHEN team_members.status = 'active' THEN team_members.role ELSE excluded.role END,
         status = 'active',
         joined_via_invite_id = excluded.joined_via_invite_id,
         updated_at = excluded.updated_at`,
    ).bind(teamId, auth.uid, invite.role, invite.id, now),
    env.DB.prepare('UPDATE users SET active_team_id = ?2, updated_at = ?3 WHERE id = ?1').bind(
      auth.uid,
      teamId,
      now,
    ),
  ]);

  return json({ membership: await loadMembership(env, auth.uid, teamId) });
}

export async function createInvite(
  request: Request,
  env: Env,
  auth: AuthContext,
  teamId: string,
): Promise<Response> {
  await requireMember(env, auth, teamId, ['admin']);
  const body = await readJson(request);
  const role = parseRole(body.role ?? 'dev');
  const expiresAt = inviteExpiry(body.expiresAt);
  const secret = randomCode(INVITE_ALPHABET, 10);
  const id = crypto.randomUUID();

  await env.DB.prepare(
    `INSERT INTO team_invites (id, team_id, code_hash, role, status, created_by_uid, created_at, expires_at)
     VALUES (?1, ?2, ?3, ?4, 'active', ?5, ?6, ?7)`,
  )
    .bind(id, teamId, await sha256Base64Url(`${teamId}:${secret}`), role, auth.uid, nowIso(), expiresAt)
    .run();

  return json({ id, code: `${teamId}:${secret}`, role, expiresAt }, 201);
}

export async function listMembers(env: Env, auth: AuthContext, teamId: string): Promise<Response> {
  await requireMember(env, auth, teamId);
  const { results } = await env.DB.prepare(
    `SELECT m.user_id, m.role, m.status, m.joined_at, u.email, u.display_name
     FROM team_members m JOIN users u ON u.id = m.user_id
     WHERE m.team_id = ?1
     ORDER BY CASE m.role WHEN 'admin' THEN 0 ELSE 1 END, lower(u.email)`,
  )
    .bind(teamId)
    .all<{
      user_id: string;
      role: TeamRole;
      status: string;
      joined_at: string;
      email: string;
      display_name: string;
    }>();

  return json({
    members: results.map((row) => ({
      uid: row.user_id,
      email: row.email,
      displayName: row.display_name,
      role: row.role,
      status: row.status,
      joinedAt: row.joined_at,
    })),
  });
}

export async function updateMemberRole(
  request: Request,
  env: Env,
  auth: AuthContext,
  teamId: string,
  uid: string,
): Promise<Response> {
  await requireMember(env, auth, teamId, ['admin']);
  if (uid === auth.uid) {
    throw new ApiError(400, 'cannot-change-self', 'You cannot change your own role.');
  }
  const body = await readJson(request);
  const role = parseRole(body.role);
  const result = await env.DB.prepare(
    'UPDATE team_members SET role = ?3, updated_at = ?4 WHERE team_id = ?1 AND user_id = ?2',
  )
    .bind(teamId, uid, role, nowIso())
    .run();
  if (result.meta.changes === 0) {
    throw new ApiError(404, 'member-not-found', 'Team member was not found.');
  }
  return noContent();
}

export async function removeMember(
  env: Env,
  auth: AuthContext,
  teamId: string,
  uid: string,
): Promise<Response> {
  await requireMember(env, auth, teamId, ['admin']);
  if (uid === auth.uid) {
    throw new ApiError(400, 'cannot-remove-self', 'You cannot remove yourself.');
  }
  const [deleted] = await env.DB.batch([
    env.DB.prepare('DELETE FROM team_members WHERE team_id = ?1 AND user_id = ?2').bind(teamId, uid),
    env.DB.prepare(
      'UPDATE users SET active_team_id = NULL, updated_at = ?3 WHERE id = ?2 AND active_team_id = ?1',
    ).bind(teamId, uid, nowIso()),
  ]);
  if (deleted.meta.changes === 0) {
    throw new ApiError(404, 'member-not-found', 'Team member was not found.');
  }
  return noContent();
}

function parseInviteCode(value: unknown): { teamId: string; secret: string } {
  const code = str(value);
  const separator = code.indexOf(':');
  if (separator <= 0 || separator === code.length - 1) {
    throw new ApiError(400, 'invalid-invite', 'Invite code is invalid or expired.');
  }
  return {
    teamId: code.slice(0, separator).trim(),
    secret: code.slice(separator + 1).trim().toUpperCase(),
  };
}

function parseRole(value: unknown): TeamRole {
  if (value === 'admin' || value === 'dev') return value;
  throw new ApiError(400, 'invalid-role', 'Role must be admin or dev.');
}

function inviteExpiry(value: unknown): string {
  const now = Date.now();
  const requested = typeof value === 'string' ? Date.parse(value) : Number.NaN;
  const expires =
    Number.isFinite(requested) && requested > now
      ? Math.min(requested, now + MAX_INVITE_MS)
      : now + DEFAULT_INVITE_MS;
  return new Date(expires).toISOString();
}
