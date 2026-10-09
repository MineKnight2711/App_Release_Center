import { env } from 'cloudflare:test';
import { exports } from 'cloudflare:workers';
import { beforeEach, describe, expect, it } from 'vitest';

const BASE = 'https://amc-api.test';
let clientIp = '';

beforeEach(async () => {
  // A fresh client IP per test keeps the real login rate limiter from tripping.
  clientIp = `10.0.0.${Math.floor(Math.random() * 250)}-${crypto.randomUUID()}`;
  await env.DB.batch(
    [
      'qa_account_audit',
      'qa_account_leases',
      'qa_account_status',
      'qa_accounts',
      'qa_vault_meta',
      'api_tool_documents',
      'team_invites',
      'team_members',
      'teams',
      'sessions',
      'users',
    ].map(
      (table) => env.DB.prepare(`DELETE FROM ${table}`),
    ),
  );
});

async function call(
  method: string,
  path: string,
  options: { token?: string; body?: unknown } = {},
): Promise<{ status: number; body: any }> {
  const headers: Record<string, string> = { 'CF-Connecting-IP': clientIp };
  if (options.token) headers.Authorization = `Bearer ${options.token}`;
  if (options.body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await exports.default.fetch(
    new Request(`${BASE}${path}`, {
      method,
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    }),
  );
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}

/** Stand-in for the client's PBKDF2 output: unpadded base64url of 32 bytes. */
async function passwordKey(seed: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(seed));
  return btoa(String.fromCharCode(...new Uint8Array(digest)))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/, '');
}

async function registerUser(email: string, displayName = email.split('@')[0]) {
  const response = await call('POST', '/v1/auth/register', {
    body: { email, passwordKey: await passwordKey(`pw:${email}`), displayName },
  });
  expect(response.status).toBe(201);
  return response.body as { token: string; user: { uid: string } };
}

async function adminWithTeam() {
  const admin = await registerUser('admin@example.com', 'Admin');
  const team = await call('POST', '/v1/teams', { token: admin.token, body: { name: 'Release Team' } });
  expect(team.status).toBe(201);
  return { admin, teamId: team.body.membership.teamId as string };
}

async function joinAsDev(teamId: string, adminToken: string, email = 'dev@example.com') {
  const invite = await call('POST', `/v1/teams/${teamId}/invites`, {
    token: adminToken,
    body: { role: 'dev' },
  });
  expect(invite.status).toBe(201);
  const dev = await registerUser(email, 'Dev');
  const joined = await call('POST', '/v1/teams/join', {
    token: dev.token,
    body: { inviteCode: invite.body.code },
  });
  expect(joined.status).toBe(200);
  return dev;
}

describe('auth', () => {
  it('reports health', async () => {
    expect(await call('GET', '/v1/health')).toEqual({ status: 200, body: { ok: true } });
  });

  it('registers, signs in, and signs out with server-side sessions', async () => {
    const registered = await registerUser('Dev@Example.com', 'Dev');
    expect(registered.token).toMatch(/^amc_/);

    const duplicate = await call('POST', '/v1/auth/register', {
      body: { email: 'dev@example.com', passwordKey: await passwordKey('other'), displayName: 'X' },
    });
    expect(duplicate.status).toBe(409);
    expect(duplicate.body.error.code).toBe('email-already-in-use');

    const wrong = await call('POST', '/v1/auth/login', {
      body: { email: 'dev@example.com', passwordKey: await passwordKey('wrong') },
    });
    expect(wrong.status).toBe(401);
    expect(wrong.body.error.code).toBe('invalid-credential');

    const login = await call('POST', '/v1/auth/login', {
      body: { email: 'DEV@example.com', passwordKey: await passwordKey('pw:Dev@Example.com') },
    });
    expect(login.status).toBe(200);
    expect(login.body.user.email).toBe('dev@example.com');

    const me = await call('GET', '/v1/me', { token: login.body.token });
    expect(me.body).toEqual({
      user: { uid: registered.user.uid, email: 'dev@example.com', displayName: 'Dev' },
      membership: null,
    });

    expect((await call('POST', '/v1/auth/logout', { token: login.body.token })).status).toBe(204);
    const afterLogout = await call('GET', '/v1/me', { token: login.body.token });
    expect(afterLogout.status).toBe(401);
    // Other sessions stay valid.
    expect((await call('GET', '/v1/me', { token: registered.token })).status).toBe(200);
  });

  it('rejects expired sessions and raw passwords', async () => {
    const user = await registerUser('old@example.com');
    await env.DB.prepare("UPDATE sessions SET expires_at = '2000-01-01T00:00:00.000Z'").run();
    const me = await call('GET', '/v1/me', { token: user.token });
    expect(me.status).toBe(401);
    expect(me.body.error.code).toBe('session-expired');

    const raw = await call('POST', '/v1/auth/login', {
      body: { email: 'old@example.com', passwordKey: 'plain-password' },
    });
    expect(raw.status).toBe(400);
  });

  it('requires a session for protected routes', async () => {
    expect((await call('GET', '/v1/me')).status).toBe(401);
    expect((await call('GET', '/v1/me', { token: 'amc_nope' })).status).toBe(401);
    expect((await call('GET', '/v1/nope')).status).toBe(404);
  });
});

describe('teams', () => {
  it('creates a team with the creator as admin', async () => {
    const { admin, teamId } = await adminWithTeam();
    const me = await call('GET', '/v1/me', { token: admin.token });
    expect(me.body.membership).toEqual({
      teamId,
      teamName: 'Release Team',
      role: 'admin',
      status: 'active',
    });
  });

  it('joins with an invite once and enforces admin-only management', async () => {
    const { admin, teamId } = await adminWithTeam();
    const invite = await call('POST', `/v1/teams/${teamId}/invites`, {
      token: admin.token,
      body: { role: 'dev' },
    });
    const dev = await registerUser('dev@example.com');
    const joined = await call('POST', '/v1/teams/join', {
      token: dev.token,
      body: { inviteCode: invite.body.code.toLowerCase().replace(teamId.toLowerCase(), teamId) },
    });
    expect(joined.body.membership).toMatchObject({ teamId, role: 'dev' });

    const other = await registerUser('other@example.com');
    const reused = await call('POST', '/v1/teams/join', {
      token: other.token,
      body: { inviteCode: invite.body.code },
    });
    expect(reused.status).toBe(400);
    expect(reused.body.error.code).toBe('invalid-invite');

    const devInvite = await call('POST', `/v1/teams/${teamId}/invites`, {
      token: dev.token,
      body: { role: 'admin' },
    });
    expect(devInvite.status).toBe(403);

    const members = await call('GET', `/v1/teams/${teamId}/members`, { token: dev.token });
    expect(members.body.members.map((m: any) => [m.email, m.role])).toEqual([
      ['admin@example.com', 'admin'],
      ['dev@example.com', 'dev'],
    ]);

    const outsiderMembers = await call('GET', `/v1/teams/${teamId}/members`, { token: other.token });
    expect(outsiderMembers.status).toBe(403);
  });

  it('rejects expired invites', async () => {
    const { admin, teamId } = await adminWithTeam();
    const invite = await call('POST', `/v1/teams/${teamId}/invites`, { token: admin.token, body: {} });
    await env.DB.prepare("UPDATE team_invites SET expires_at = '2000-01-01T00:00:00.000Z'").run();
    const dev = await registerUser('dev@example.com');
    const joined = await call('POST', '/v1/teams/join', {
      token: dev.token,
      body: { inviteCode: invite.body.code },
    });
    expect(joined.status).toBe(400);
  });

  it('lets only one of two racing users claim an invite', async () => {
    const { admin, teamId } = await adminWithTeam();
    const invite = await call('POST', `/v1/teams/${teamId}/invites`, { token: admin.token, body: {} });
    const first = await registerUser('a@example.com');
    const second = await registerUser('b@example.com');
    const results = await Promise.all(
      [first, second].map((user) =>
        call('POST', '/v1/teams/join', { token: user.token, body: { inviteCode: invite.body.code } }),
      ),
    );
    expect(results.map((r) => r.status).sort()).toEqual([200, 400]);
  });

  it('changes roles and removes members with immediate effect', async () => {
    const { admin, teamId } = await adminWithTeam();
    const dev = await joinAsDev(teamId, admin.token);

    const self = await call('PATCH', `/v1/teams/${teamId}/members/${admin.user.uid}`, {
      token: admin.token,
      body: { role: 'dev' },
    });
    expect(self.status).toBe(400);

    const promote = await call('PATCH', `/v1/teams/${teamId}/members/${dev.user.uid}`, {
      token: admin.token,
      body: { role: 'admin' },
    });
    expect(promote.status).toBe(204);

    const removed = await call('DELETE', `/v1/teams/${teamId}/members/${dev.user.uid}`, {
      token: admin.token,
    });
    expect(removed.status).toBe(204);

    const me = await call('GET', '/v1/me', { token: dev.token });
    expect(me.body.membership).toBeNull();
    const tools = await call('GET', `/v1/teams/${teamId}/api-tools`, { token: dev.token });
    expect(tools.status).toBe(403);
  });
});

describe('api tools', () => {
  it('replaces each kind as a set and cascades collection deletes', async () => {
    const { admin, teamId } = await adminWithTeam();
    const dev = await joinAsDev(teamId, admin.token);
    const put = (kind: string, items: unknown[]) =>
      call('PUT', `/v1/teams/${teamId}/api-tools/${kind}`, { token: dev.token, body: { items } });

    expect((await put('collections', [{ id: 'c1', name: 'Core' }, { id: 'c2', name: 'Other' }])).status).toBe(204);
    expect((await put('folders', [{ id: 'f1', collectionId: 'c1', name: 'Auth' }])).status).toBe(204);
    expect(
      (
        await put('requests', [
          { id: 'r1', collectionId: 'c1', name: 'Login', url: 'https://x/login' },
          { id: 'r2', collectionId: 'c2', name: 'Ping' },
        ])
      ).status,
    ).toBe(204);
    expect((await put('quick-requests', [{ id: 'q1', collectionId: 'c1' }])).status).toBe(204);

    const loaded = await call('GET', `/v1/teams/${teamId}/api-tools`, { token: admin.token });
    expect(loaded.body.collections).toHaveLength(2);
    expect(loaded.body.requests).toContainEqual({
      id: 'r1',
      collectionId: 'c1',
      name: 'Login',
      url: 'https://x/login',
    });

    // Unchanged rows keep their timestamp; removed rows disappear.
    await env.DB.prepare("UPDATE api_tool_documents SET updated_at = 'old' WHERE id = 'r1'").run();
    await put('requests', [{ id: 'r1', collectionId: 'c1', name: 'Login', url: 'https://x/login' }]);
    const rows = await env.DB.prepare(
      "SELECT id, updated_at FROM api_tool_documents WHERE kind = 'request'",
    ).all<{ id: string; updated_at: string }>();
    expect(rows.results).toEqual([{ id: 'r1', updated_at: 'old' }]);

    const deleted = await call('DELETE', `/v1/teams/${teamId}/api-tools/collections/c1`, {
      token: dev.token,
    });
    expect(deleted.status).toBe(204);
    const after = await call('GET', `/v1/teams/${teamId}/api-tools`, { token: dev.token });
    expect(after.body).toEqual({
      collections: [{ id: 'c2', name: 'Other' }],
      folders: [],
      requests: [],
      quickRequests: [],
    });
  });

  it('validates items and blocks non-members', async () => {
    const { admin, teamId } = await adminWithTeam();
    const duplicate = await call('PUT', `/v1/teams/${teamId}/api-tools/requests`, {
      token: admin.token,
      body: { items: [{ id: 'a' }, { id: 'a' }] },
    });
    expect(duplicate.status).toBe(400);
    const unknownKind = await call('PUT', `/v1/teams/${teamId}/api-tools/widgets`, {
      token: admin.token,
      body: { items: [] },
    });
    expect(unknownKind.status).toBe(404);

    const outsider = await registerUser('outsider@example.com');
    const blocked = await call('PUT', `/v1/teams/${teamId}/api-tools/requests`, {
      token: outsider.token,
      body: { items: [] },
    });
    expect(blocked.status).toBe(403);
  });
});

describe('qa vault', () => {
  it('lets members read and record status, and only admins change the vault', async () => {
    const { admin, teamId } = await adminWithTeam();
    const dev = await joinAsDev(teamId, admin.token);
    const base = `/v1/teams/${teamId}/qa-vault`;

    expect((await call('GET', `${base}/meta`, { token: dev.token })).body).toEqual({ meta: null });
    const devMeta = await call('PUT', `${base}/meta`, { token: dev.token, body: { meta: { salt: 'x' } } });
    expect(devMeta.status).toBe(403);
    expect((await call('PUT', `${base}/meta`, { token: admin.token, body: { meta: { salt: 's1' } } })).status).toBe(204);
    expect((await call('GET', `${base}/meta`, { token: dev.token })).body.meta).toEqual({ salt: 's1' });

    const devAccount = await call('PUT', `${base}/accounts/a1`, {
      token: dev.token,
      body: { document: { role: 'buyer' } },
    });
    expect(devAccount.status).toBe(403);
    await call('PUT', `${base}/accounts/a1`, {
      token: admin.token,
      body: { document: { role: 'buyer', cipher: 'c' } },
    });
    expect((await call('GET', `${base}/accounts`, { token: dev.token })).body.accounts).toEqual({
      a1: { role: 'buyer', cipher: 'c' },
    });

    expect(
      (await call('PUT', `${base}/statuses/a1`, { token: dev.token, body: { status: { ok: true } } })).status,
    ).toBe(204);
    expect((await call('GET', `${base}/statuses`, { token: admin.token })).body.statuses).toEqual({
      a1: { ok: true },
    });

    expect((await call('DELETE', `${base}/accounts/a1`, { token: admin.token })).status).toBe(204);
    expect((await call('GET', `${base}/accounts`, { token: dev.token })).body.accounts).toEqual({});

    const outsider = await registerUser('outsider@example.com');
    expect((await call('GET', `${base}/accounts`, { token: outsider.token })).status).toBe(403);
  });

  it('grants a lease to one holder until it expires or is released', async () => {
    const { admin, teamId } = await adminWithTeam();
    const dev = await joinAsDev(teamId, admin.token);
    const lease = (token: string, runId: string, expiresAt: string) =>
      call('POST', `/v1/teams/${teamId}/qa-vault/leases/a1`, {
        token,
        body: { holderName: 'X', machine: 'mac', runId, expiresAt, holderUid: 'spoofed' },
      });
    const later = new Date(Date.now() + 60_000).toISOString();

    expect((await lease(admin.token, 'run-1', later)).body).toEqual({ acquired: true });
    expect((await lease(dev.token, 'run-2', later)).body).toEqual({ acquired: false });
    // The holder renews its own lease.
    expect((await lease(admin.token, 'run-1', later)).body).toEqual({ acquired: true });

    const leases = await call('GET', `/v1/teams/${teamId}/qa-vault/leases`, { token: dev.token });
    expect(leases.body.leases.a1).toMatchObject({ holderUid: admin.user.uid, runId: 'run-1' });

    // Someone else cannot release it, and a stale run id does nothing.
    await call('DELETE', `/v1/teams/${teamId}/qa-vault/leases/a1?runId=run-1`, { token: dev.token });
    await call('DELETE', `/v1/teams/${teamId}/qa-vault/leases/a1?runId=old`, { token: admin.token });
    expect((await lease(dev.token, 'run-2', later)).body).toEqual({ acquired: false });

    await call('DELETE', `/v1/teams/${teamId}/qa-vault/leases/a1?runId=run-1`, { token: admin.token });
    expect((await lease(dev.token, 'run-2', later)).body).toEqual({ acquired: true });

    // An expired lease can be taken over.
    await env.DB.prepare("UPDATE qa_account_leases SET expires_at = '2000-01-01T00:00:00.000Z'").run();
    expect((await lease(admin.token, 'run-3', later)).body).toEqual({ acquired: true });
  });

  it('stamps audit events with the session user', async () => {
    const { admin, teamId } = await adminWithTeam();
    const response = await call('POST', `/v1/teams/${teamId}/qa-vault/audit`, {
      token: admin.token,
      body: { event: { action: 'reveal', uid: 'someone-else' } },
    });
    expect(response.status).toBe(204);
    const row = await env.DB.prepare('SELECT uid, data FROM qa_account_audit').first<{
      uid: string;
      data: string;
    }>();
    expect(row?.uid).toBe(admin.user.uid);
    expect(JSON.parse(row!.data)).toEqual({ action: 'reveal', uid: admin.user.uid });
  });
});
