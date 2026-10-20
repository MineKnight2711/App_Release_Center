import type { AuthContext } from './auth';
import { randomBase64Url, safeEqual, sha256Base64Url } from './crypto';
import { ApiError, json, noContent, nowIso, readJson, str } from './http';
import sharePageHtml from './sharePage.html';

// A share link carries one safe item, encrypted in the app (AES-256-GCM) with
// a key derived from a secret in the link's #fragment and, when set, a
// password (PBKDF2). Browsers never send the fragment, so this Worker only
// ever holds ciphertext. What it does decide is who may fetch that ciphertext:
// the opener proves it knows the fragment (and password) with an access key
// derived alongside the encryption key, whose SHA-256 is all that is stored.

const SHARE_ID_PATTERN = /^[A-Za-z0-9_-]{22}$/;
const KEY_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const CIPHERTEXT_PATTERN = /^[A-Za-z0-9_-]+$/;
// 1 MiB of item plus nonce and tag, as base64url, stays under D1's 2 MB value limit.
const MAX_CIPHERTEXT_CHARS = 1_500_000;
const MAX_HOURS = 30 * 24;
const MAX_VIEWS = 100;
const MIN_ITERATIONS = 100_000;
const MAX_ITERATIONS = 5_000_000;
/** Wrong passwords a link survives before it destroys its ciphertext. */
export const MAX_FAILED_ATTEMPTS = 10;
const MAX_LIVE_SHARES_PER_OWNER = 200;
/** How long a dead link stays in its owner's list before it is forgotten. */
const KEEP_DEAD_MS = 30 * 24 * 60 * 60 * 1000;

interface ShareRow {
  id: string;
  item_id: string;
  live: number;
  password_salt: string;
  kdf_iterations: number;
  max_views: number | null;
  views: number;
  failed_attempts: number;
  created_at: string;
  expires_at: string;
  last_viewed_at: string | null;
}

const SHARE_COLUMNS = `id, item_id, ciphertext != '' AS live, password_salt, kdf_iterations,
  max_views, views, failed_attempts, created_at, expires_at, last_viewed_at`;

export async function createShare(request: Request, env: Env, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  const id = str(body.id);
  if (!SHARE_ID_PATTERN.test(id)) {
    throw new ApiError(400, 'invalid-share', 'id must be 16 random bytes as base64url.');
  }
  const ciphertext = str(body.ciphertext);
  if (!CIPHERTEXT_PATTERN.test(ciphertext) || ciphertext.length < 40) {
    throw new ApiError(400, 'invalid-share', 'ciphertext must be base64url.');
  }
  if (ciphertext.length > MAX_CIPHERTEXT_CHARS) {
    throw new ApiError(413, 'share-too-large', 'The shared item is larger than 1 MB.');
  }
  const accessHash = str(body.accessHash);
  if (!KEY_PATTERN.test(accessHash)) {
    throw new ApiError(400, 'invalid-share', 'accessHash must be a base64url SHA-256.');
  }
  const passwordSalt = str(body.passwordSalt);
  const iterations = passwordSalt ? integer(body.kdfIterations, MIN_ITERATIONS, MAX_ITERATIONS) : 0;
  if (passwordSalt && !SHARE_ID_PATTERN.test(passwordSalt)) {
    throw new ApiError(400, 'invalid-share', 'passwordSalt must be 16 bytes as base64url.');
  }
  if (iterations === null) {
    throw new ApiError(400, 'invalid-share', `kdfIterations must be ${MIN_ITERATIONS}–${MAX_ITERATIONS}.`);
  }
  const hours = integer(body.expiresInHours, 1, MAX_HOURS);
  if (hours === null) {
    throw new ApiError(400, 'invalid-share', `expiresInHours must be 1–${MAX_HOURS}.`);
  }
  const maxViews = body.maxViews === null || body.maxViews === undefined ? null : integer(body.maxViews, 1, MAX_VIEWS);
  if (maxViews === null && body.maxViews !== null && body.maxViews !== undefined) {
    throw new ApiError(400, 'invalid-share', `maxViews must be null or 1–${MAX_VIEWS}.`);
  }

  const now = new Date();
  const nowText = now.toISOString();
  await forgetDeadShares(env, now);
  const live = await env.DB.prepare(
    `SELECT COUNT(*) AS count FROM safe_shares WHERE owner_uid = ?1 AND ciphertext != ''`,
  )
    .bind(auth.uid)
    .first<{ count: number }>();
  if ((live?.count ?? 0) >= MAX_LIVE_SHARES_PER_OWNER) {
    throw new ApiError(
      429,
      'share-limit',
      `At most ${MAX_LIVE_SHARES_PER_OWNER} live links per account. Revoke some first.`,
    );
  }

  const expiresAt = new Date(now.getTime() + hours * 60 * 60 * 1000).toISOString();
  try {
    await env.DB.prepare(
      `INSERT INTO safe_shares (id, owner_uid, item_id, ciphertext, access_hash, password_salt,
         kdf_iterations, max_views, created_at, expires_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)`,
    )
      .bind(
        id,
        auth.uid,
        str(body.itemId).slice(0, 120),
        ciphertext,
        accessHash,
        passwordSalt,
        iterations,
        maxViews,
        nowText,
        expiresAt,
      )
      .run();
  } catch (error) {
    if (String(error).includes('UNIQUE')) {
      throw new ApiError(409, 'share-exists', 'A share with this id already exists.');
    }
    throw error;
  }

  const row = await readShare(env, id);
  return json({ share: shareJson(row!, nowText), url: shareUrl(request, id) }, 201);
}

export async function listShares(request: Request, env: Env, auth: AuthContext): Promise<Response> {
  const { results } = await env.DB.prepare(
    `SELECT ${SHARE_COLUMNS} FROM safe_shares WHERE owner_uid = ?1 ORDER BY created_at DESC`,
  )
    .bind(auth.uid)
    .all<ShareRow>();
  const now = nowIso();
  return json({
    shares: results.map((row) => ({ ...shareJson(row, now), url: shareUrl(request, row.id) })),
  });
}

/** Deletes the link outright: it stops working at once, for everyone. */
export async function revokeShare(env: Env, auth: AuthContext, shareId: string): Promise<Response> {
  const result = await env.DB.prepare('DELETE FROM safe_shares WHERE id = ?1 AND owner_uid = ?2')
    .bind(shareId, auth.uid)
    .run();
  if (result.meta.changes === 0) {
    throw new ApiError(404, 'share-not-found', 'No such link in this account.');
  }
  return noContent();
}

/** What the page shows before anything is opened. Opening nothing, it costs no view. */
export async function shareMeta(env: Env, shareId: string): Promise<Response> {
  const row = await readShare(env, shareId);
  const now = nowIso();
  if (!row || !isAlive(row, now)) throw gone();
  return noStore({
    passwordRequired: row.password_salt !== '',
    passwordSalt: row.password_salt,
    kdfIterations: row.kdf_iterations,
    expiresAt: row.expires_at,
    viewsLeft: viewsLeft(row),
  });
}

export async function openShare(request: Request, env: Env, shareId: string): Promise<Response> {
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const { success } = await env.SHARE_LIMITER.limit({ key: `share:${shareId}:${ip}` });
  if (!success) {
    throw new ApiError(429, 'too-many-requests', 'Too many attempts. Try again in a minute.');
  }
  const access = str((await readJson(request)).access);
  if (!KEY_PATTERN.test(access)) {
    throw new ApiError(400, 'invalid-access', 'access must be 32 bytes as base64url.');
  }

  const stored = await env.DB.prepare(
    `SELECT access_hash, password_salt, failed_attempts, ciphertext != '' AS live, expires_at,
       max_views, views FROM safe_shares WHERE id = ?1`,
  )
    .bind(shareId)
    .first<{
      access_hash: string;
      password_salt: string;
      failed_attempts: number;
      live: number;
      expires_at: string;
      max_views: number | null;
      views: number;
    }>();
  const now = nowIso();
  if (!stored || !isAlive(stored, now)) throw gone();

  if (!safeEqual(await sha256Base64Url(access), stored.access_hash)) {
    // The ciphertext is destroyed on the last allowed miss, so a leaked link
    // cannot be worked through a password list from many addresses.
    const failed = await env.DB.prepare(
      `UPDATE safe_shares SET failed_attempts = failed_attempts + 1,
         ciphertext = CASE WHEN failed_attempts + 1 >= ?2 THEN '' ELSE ciphertext END
       WHERE id = ?1 RETURNING failed_attempts`,
    )
      .bind(shareId, MAX_FAILED_ATTEMPTS)
      .first<{ failed_attempts: number }>();
    const attemptsLeft = Math.max(0, MAX_FAILED_ATTEMPTS - (failed?.failed_attempts ?? MAX_FAILED_ATTEMPTS));
    const withPassword = stored.password_salt !== '';
    return noStore(
      {
        error: {
          code: withPassword ? 'wrong-password' : 'invalid-link',
          message: withPassword ? 'The password is not correct.' : 'The link is incomplete or was altered.',
          attemptsLeft,
        },
      },
      403,
    );
  }

  // One conditional update, so two people racing for a one-view link cannot
  // both get it; the second statement wipes the ciphertext the first one just
  // returned when that was the last view.
  const [opened] = await env.DB.batch<{
    ciphertext: string;
    max_views: number | null;
    views: number;
    expires_at: string;
  }>([
    env.DB.prepare(
      `UPDATE safe_shares SET views = views + 1, last_viewed_at = ?2
       WHERE id = ?1 AND ciphertext != '' AND expires_at > ?2
         AND (max_views IS NULL OR views < max_views)
       RETURNING ciphertext, max_views, views, expires_at`,
    ).bind(shareId, now),
    env.DB.prepare(
      `UPDATE safe_shares SET ciphertext = ''
       WHERE id = ?1 AND max_views IS NOT NULL AND views >= max_views`,
    ).bind(shareId),
  ]);
  const row = opened.results[0];
  if (!row) throw gone();
  return noStore({
    ciphertext: row.ciphertext,
    expiresAt: row.expires_at,
    viewsLeft: row.max_views === null ? null : row.max_views - row.views,
  });
}

/** The page that opens a link. All decryption happens in it, in the browser. */
export function sharePage(): Response {
  const nonce = randomBase64Url(18);
  return new Response(sharePageHtml.replaceAll('__NONCE__', nonce), {
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Security-Policy': [
        "default-src 'none'",
        `script-src 'nonce-${nonce}'`,
        `style-src 'nonce-${nonce}'`,
        "connect-src 'self'",
        'img-src data:',
        "base-uri 'none'",
        "form-action 'none'",
        "frame-ancestors 'none'",
      ].join('; '),
      'Cache-Control': 'no-store',
      'Referrer-Policy': 'no-referrer',
      'X-Content-Type-Options': 'nosniff',
      'X-Robots-Tag': 'noindex, nofollow',
      'Cross-Origin-Opener-Policy': 'same-origin',
    },
  });
}

async function readShare(env: Env, shareId: string): Promise<ShareRow | null> {
  return env.DB.prepare(`SELECT ${SHARE_COLUMNS} FROM safe_shares WHERE id = ?1`)
    .bind(shareId)
    .first<ShareRow>();
}

/** Wipes expired ciphertext and drops links that have been dead a while. */
async function forgetDeadShares(env: Env, now: Date): Promise<void> {
  await env.DB.batch([
    env.DB.prepare(`UPDATE safe_shares SET ciphertext = '' WHERE expires_at <= ?1 AND ciphertext != ''`).bind(
      now.toISOString(),
    ),
    env.DB.prepare('DELETE FROM safe_shares WHERE expires_at <= ?1').bind(
      new Date(now.getTime() - KEEP_DEAD_MS).toISOString(),
    ),
  ]);
}

function isAlive(row: { live: number; expires_at: string; max_views: number | null; views: number }, now: string) {
  return row.live === 1 && row.expires_at > now && (row.max_views === null || row.views < row.max_views);
}

function viewsLeft(row: { max_views: number | null; views: number }): number | null {
  return row.max_views === null ? null : Math.max(0, row.max_views - row.views);
}

function shareJson(row: ShareRow, now: string) {
  let status: 'active' | 'expired' | 'used-up' | 'locked' = 'active';
  if (row.failed_attempts >= MAX_FAILED_ATTEMPTS) status = 'locked';
  else if (row.max_views !== null && row.views >= row.max_views) status = 'used-up';
  else if (row.expires_at <= now || row.live !== 1) status = 'expired';
  return {
    id: row.id,
    itemId: row.item_id,
    status,
    passwordProtected: row.password_salt !== '',
    maxViews: row.max_views,
    views: row.views,
    failedAttempts: row.failed_attempts,
    createdAt: row.created_at,
    expiresAt: row.expires_at,
    lastViewedAt: row.last_viewed_at,
  };
}

function shareUrl(request: Request, shareId: string): string {
  return `${new URL(request.url).origin}/s/${shareId}`;
}

function integer(value: unknown, min: number, max: number): number | null {
  return typeof value === 'number' && Number.isInteger(value) && value >= min && value <= max ? value : null;
}

/** Dead, used up, revoked or never existed: the opener learns none of which. */
function gone(): ApiError {
  return new ApiError(404, 'share-gone', 'This link has expired, was used up or was revoked.');
}

function noStore(data: unknown, status = 200): Response {
  return Response.json(data, { status, headers: { 'Cache-Control': 'no-store' } });
}
