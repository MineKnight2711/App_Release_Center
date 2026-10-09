import { hmacSha256Base64Url, randomBase64Url, safeEqual, sha256Base64Url } from './crypto';
import { ApiError, json, noContent, nowIso, readJson, str } from './http';
import { loadMembership } from './teams';

const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
// The client sends PBKDF2-SHA256(password) as unpadded base64url of 32 bytes.
const PASSWORD_KEY_PATTERN = /^[A-Za-z0-9_-]{43}$/;
// Used when the email is unknown so failed logins cost the same as real ones.
const UNKNOWN_USER_SALT = 'unknown-user-salt';

export interface AuthContext {
  uid: string;
  email: string;
  displayName: string;
  activeTeamId: string | null;
  tokenHash: string;
}

interface UserRow {
  id: string;
  email: string;
  display_name: string;
  password_salt: string;
  password_hash: string;
}

export async function register(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request);
  const email = requireEmail(body.email);
  const passwordKey = requirePasswordKey(body.passwordKey);
  const displayName = str(body.displayName).slice(0, 80);
  await enforceRateLimit(request, env, `register:${email}`);

  const uid = crypto.randomUUID();
  const salt = randomBase64Url(16);
  const passwordHash = await hashPasswordKey(env, salt, passwordKey);
  const now = nowIso();
  try {
    await env.DB.prepare(
      `INSERT INTO users (id, email, display_name, password_salt, password_hash, created_at, updated_at, last_login_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?6)`,
    )
      .bind(uid, email, displayName, salt, passwordHash, now)
      .run();
  } catch (error) {
    if (String(error).includes('UNIQUE')) {
      throw new ApiError(409, 'email-already-in-use', 'This email is already registered.');
    }
    throw error;
  }

  return json(await createSession(env, { uid, email, displayName }), 201);
}

export async function login(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request);
  const email = requireEmail(body.email);
  const passwordKey = requirePasswordKey(body.passwordKey);
  await enforceRateLimit(request, env, `login:${email}`);

  const user = await env.DB.prepare(
    'SELECT id, email, display_name, password_salt, password_hash FROM users WHERE email = ?1',
  )
    .bind(email)
    .first<UserRow>();
  const computed = await hashPasswordKey(env, user?.password_salt ?? UNKNOWN_USER_SALT, passwordKey);
  if (!user || !safeEqual(computed, user.password_hash)) {
    throw new ApiError(401, 'invalid-credential', 'Email or password is not correct.');
  }

  const now = nowIso();
  await env.DB.batch([
    env.DB.prepare('UPDATE users SET last_login_at = ?2 WHERE id = ?1').bind(user.id, now),
    env.DB.prepare('DELETE FROM sessions WHERE user_id = ?1 AND expires_at <= ?2').bind(user.id, now),
  ]);
  return json(
    await createSession(env, { uid: user.id, email: user.email, displayName: user.display_name }),
  );
}

export async function logout(env: Env, auth: AuthContext): Promise<Response> {
  await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?1').bind(auth.tokenHash).run();
  return noContent();
}

export async function me(env: Env, auth: AuthContext): Promise<Response> {
  return json({
    user: userJson(auth),
    membership: await loadMembership(env, auth.uid, auth.activeTeamId),
  });
}

export async function authenticate(request: Request, env: Env): Promise<AuthContext> {
  const header = request.headers.get('Authorization') ?? '';
  const token = header.startsWith('Bearer ') ? header.slice('Bearer '.length).trim() : '';
  if (!token) {
    throw new ApiError(401, 'unauthenticated', 'Please sign in first.');
  }

  const tokenHash = await sha256Base64Url(token);
  const row = await env.DB.prepare(
    `SELECT u.id, u.email, u.display_name, u.active_team_id
     FROM sessions s JOIN users u ON u.id = s.user_id
     WHERE s.token_hash = ?1 AND s.expires_at > ?2`,
  )
    .bind(tokenHash, nowIso())
    .first<{ id: string; email: string; display_name: string; active_team_id: string | null }>();
  if (!row) {
    throw new ApiError(401, 'session-expired', 'Your session expired. Please sign in again.');
  }

  return {
    uid: row.id,
    email: row.email,
    displayName: row.display_name,
    activeTeamId: row.active_team_id,
    tokenHash,
  };
}

export function userJson(user: { uid: string; email: string; displayName: string }) {
  return { uid: user.uid, email: user.email, displayName: user.displayName };
}

async function createSession(
  env: Env,
  user: { uid: string; email: string; displayName: string },
) {
  const token = `amc_${randomBase64Url(32)}`;
  const createdAt = new Date();
  const expiresAt = new Date(createdAt.getTime() + SESSION_TTL_MS).toISOString();
  await env.DB.prepare(
    'INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?1, ?2, ?3, ?4)',
  )
    .bind(await sha256Base64Url(token), user.uid, createdAt.toISOString(), expiresAt)
    .run();
  return { token, expiresAt, user: userJson(user) };
}

function hashPasswordKey(env: Env, salt: string, passwordKey: string): Promise<string> {
  if (!env.PASSWORD_PEPPER) {
    throw new ApiError(500, 'server-misconfigured', 'PASSWORD_PEPPER is not configured.');
  }
  return hmacSha256Base64Url(env.PASSWORD_PEPPER, `${salt}:${passwordKey}`);
}

async function enforceRateLimit(request: Request, env: Env, key: string): Promise<void> {
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const { success } = await env.LOGIN_LIMITER.limit({ key: `${key}:${ip}` });
  if (!success) {
    throw new ApiError(429, 'too-many-requests', 'Too many attempts. Try again in a minute.');
  }
}

function requireEmail(value: unknown): string {
  const email = str(value).toLowerCase();
  if (!EMAIL_PATTERN.test(email) || email.length > 254) {
    throw new ApiError(400, 'invalid-email', 'Email address is invalid.');
  }
  return email;
}

function requirePasswordKey(value: unknown): string {
  const passwordKey = str(value);
  if (!PASSWORD_KEY_PATTERN.test(passwordKey)) {
    throw new ApiError(400, 'invalid-password-key', 'Password must be derived by the app client.');
  }
  return passwordKey;
}
