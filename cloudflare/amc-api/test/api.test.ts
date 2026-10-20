import { env } from 'cloudflare:test';
import { exports } from 'cloudflare:workers';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

const BASE = 'https://amc-api.test';
let clientIp = '';

beforeEach(async () => {
  // A fresh client IP per test keeps the real login rate limiter from tripping.
  clientIp = `10.0.0.${Math.floor(Math.random() * 250)}-${crypto.randomUUID()}`;
  await env.DB.batch(
    [
      'safe_shares',
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
  options: { token?: string; body?: unknown; ip?: string } = {},
): Promise<{ status: number; body: any }> {
  const headers: Record<string, string> = { 'CF-Connecting-IP': options.ip ?? clientIp };
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

describe('ai release notes', () => {
  const realRun = env.AI.run;
  afterEach(() => {
    env.AI.run = realRun;
  });

  /** Replaces Workers AI; each call is recorded and answered by [answer]. */
  function stubAi(answer: (model: string) => unknown) {
    const calls: { model: string; inputs: any }[] = [];
    env.AI.run = (async (model: string, inputs: any) => {
      calls.push({ model, inputs });
      return answer(model);
    }) as any;
    return calls;
  }

  function notes(token: string, body: unknown) {
    return call('POST', '/v1/ai/release-notes', { token, body });
  }

  it('requires a session', async () => {
    const response = await call('POST', '/v1/ai/release-notes', { body: { input: 'x' } });
    expect(response.status).toBe(401);
  });

  it('passes the instructions and input to Workers AI', async () => {
    const user = await registerUser('notes@example.com');
    const calls = stubAi(() => ({ choices: [{ message: { content: '  Cảm ơn bạn.  ' } }] }));

    const response = await notes(user.token, { instructions: 'Be brief.', input: 'fix: login' });

    expect(response).toEqual({
      status: 200,
      body: { text: 'Cảm ơn bạn.', model: '@cf/aisingapore/gemma-sea-lion-v4-27b-it' },
    });
    expect(calls[0].inputs.messages).toEqual([
      { role: 'system', content: 'Be brief.' },
      { role: 'user', content: 'fix: login' },
    ]);
  });

  it('tries the next model, and reports a spent free allocation as 429', async () => {
    const user = await registerUser('notes@example.com');
    stubAi((model) => {
      if (model.includes('sea-lion')) throw new Error('3040: Capacity temporarily exceeded');
      return { response: 'Gemma note' };
    });
    expect((await notes(user.token, { input: 'fix: login' })).body).toEqual({
      text: 'Gemma note',
      model: '@cf/google/gemma-3-12b-it',
    });

    stubAi(() => {
      throw new Error('4006: you have used up your daily free allocation of 10,000 neurons');
    });
    const spent = await notes(user.token, { input: 'fix: login' });
    expect(spent.status).toBe(429);
    expect(spent.body.error.code).toBe('ai-quota-exceeded');

    stubAi(() => ({ response: '' }));
    expect((await notes(user.token, { input: 'fix: login' })).status).toBe(502);
  });

  it('rejects empty and oversized input', async () => {
    const user = await registerUser('notes@example.com');
    const calls = stubAi(() => ({ response: 'unused' }));
    expect((await notes(user.token, { input: '  ' })).status).toBe(400);
    expect((await notes(user.token, { input: 'x'.repeat(40_001) })).status).toBe(413);
    expect(calls).toEqual([]);
  });
});

describe('safe share links', () => {
  function base64Url(bytes: Uint8Array): string {
    return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
  }

  function randomId(): string {
    return base64Url(crypto.getRandomValues(new Uint8Array(16)));
  }

  async function sha256(text: string): Promise<string> {
    return base64Url(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))));
  }

  /** A share as the app uploads it; the Worker never sees anything else. */
  async function newShare(token: string, overrides: Record<string, unknown> = {}) {
    const id = randomId();
    const access = base64Url(crypto.getRandomValues(new Uint8Array(32)));
    const ciphertext = base64Url(crypto.getRandomValues(new Uint8Array(64)));
    const response = await call('POST', '/v1/shares', {
      token,
      body: {
        id,
        itemId: 'item-1',
        ciphertext,
        accessHash: await sha256(access),
        expiresInHours: 24,
        maxViews: null,
        ...overrides,
      },
    });
    return { id, access, ciphertext, response };
  }

  function open(id: string, access: string, ip?: string) {
    return call('POST', `/v1/shares/${id}/open`, { body: { access }, ip });
  }

  it('needs a session to create, and serves the ciphertext to the right key only', async () => {
    const owner = await registerUser('owner@example.com');
    expect((await call('POST', '/v1/shares', { body: {} })).status).toBe(401);

    const share = await newShare(owner.token, {
      passwordSalt: randomId(),
      kdfIterations: 600_000,
    });
    expect(share.response.status).toBe(201);
    expect(share.response.body.url).toBe(`${BASE}/s/${share.id}`);
    expect(share.response.body.share).toMatchObject({
      id: share.id,
      itemId: 'item-1',
      status: 'active',
      passwordProtected: true,
      maxViews: null,
      views: 0,
    });

    const meta = await call('GET', `/v1/shares/${share.id}/meta`);
    expect(meta.status).toBe(200);
    expect(meta.body).toMatchObject({ passwordRequired: true, kdfIterations: 600_000, viewsLeft: null });
    expect(meta.body).not.toHaveProperty('ciphertext');

    const wrong = await open(share.id, base64Url(new Uint8Array(32)));
    expect(wrong.status).toBe(403);
    expect(wrong.body.error).toMatchObject({ code: 'wrong-password', attemptsLeft: 9 });

    const right = await open(share.id, share.access);
    expect(right.status).toBe(200);
    expect(right.body).toMatchObject({ ciphertext: share.ciphertext, viewsLeft: null });

    const listed = await call('GET', '/v1/shares', { token: owner.token });
    expect(listed.body.shares).toHaveLength(1);
    expect(listed.body.shares[0]).toMatchObject({ views: 1, failedAttempts: 1, status: 'active' });
    expect(listed.body.shares[0].lastViewedAt).toBeTruthy();
  });

  it('burns a one-view link after its view and wipes the ciphertext', async () => {
    const owner = await registerUser('owner@example.com');
    const share = await newShare(owner.token, { maxViews: 1 });
    expect((await call('GET', `/v1/shares/${share.id}/meta`)).body.viewsLeft).toBe(1);

    const first = await open(share.id, share.access);
    expect(first.body).toMatchObject({ ciphertext: share.ciphertext, viewsLeft: 0 });
    const second = await open(share.id, share.access);
    expect(second.status).toBe(404);
    expect(second.body.error.code).toBe('share-gone');
    expect((await call('GET', `/v1/shares/${share.id}/meta`)).status).toBe(404);

    const row = await env.DB.prepare('SELECT ciphertext FROM safe_shares WHERE id = ?1')
      .bind(share.id)
      .first<{ ciphertext: string }>();
    expect(row?.ciphertext).toBe('');
    const listed = await call('GET', '/v1/shares', { token: owner.token });
    expect(listed.body.shares[0]).toMatchObject({ status: 'used-up', views: 1, maxViews: 1 });
  });

  it('destroys a link after too many wrong keys, from any address', async () => {
    const owner = await registerUser('owner@example.com');
    const share = await newShare(owner.token);
    const wrongKey = base64Url(new Uint8Array(32));
    let last: { status: number; body: any } | undefined;
    for (let attempt = 0; attempt < 10; attempt++) {
      last = await open(share.id, wrongKey, `10.1.0.${attempt}`);
    }
    expect(last!.status).toBe(403);
    expect(last!.body.error).toMatchObject({ code: 'invalid-link', attemptsLeft: 0 });
    expect((await open(share.id, share.access, '10.2.0.1')).status).toBe(404);
    const listed = await call('GET', '/v1/shares', { token: owner.token });
    expect(listed.body.shares[0].status).toBe('locked');
  });

  it('stops opening once expired', async () => {
    const owner = await registerUser('owner@example.com');
    const share = await newShare(owner.token);
    await env.DB.prepare("UPDATE safe_shares SET expires_at = '2000-01-01T00:00:00.000Z'").run();
    expect((await call('GET', `/v1/shares/${share.id}/meta`)).status).toBe(404);
    expect((await open(share.id, share.access)).status).toBe(404);
    const listed = await call('GET', '/v1/shares', { token: owner.token });
    expect(listed.body.shares[0].status).toBe('expired');
  });

  it('lets only the owner list and revoke', async () => {
    const owner = await registerUser('owner@example.com');
    const other = await registerUser('other@example.com');
    const share = await newShare(owner.token);

    expect((await call('GET', '/v1/shares', { token: other.token })).body.shares).toEqual([]);
    const stolen = await call('DELETE', `/v1/shares/${share.id}`, { token: other.token });
    expect(stolen.status).toBe(404);
    expect((await call('GET', `/v1/shares/${share.id}/meta`)).status).toBe(200);

    expect((await call('DELETE', `/v1/shares/${share.id}`, { token: owner.token })).status).toBe(204);
    expect((await call('GET', `/v1/shares/${share.id}/meta`)).status).toBe(404);
    expect((await call('GET', '/v1/shares', { token: owner.token })).body.shares).toEqual([]);
  });

  it('rejects malformed and oversized shares', async () => {
    const owner = await registerUser('owner@example.com');
    expect((await newShare(owner.token, { id: 'short' })).response.status).toBe(400);
    expect((await newShare(owner.token, { accessHash: 'nope' })).response.status).toBe(400);
    expect((await newShare(owner.token, { expiresInHours: 24 * 31 })).response.status).toBe(400);
    expect((await newShare(owner.token, { maxViews: 0 })).response.status).toBe(400);
    expect((await newShare(owner.token, { passwordSalt: randomId() })).response.status).toBe(400);
    const large = await newShare(owner.token, { ciphertext: 'A'.repeat(1_500_001) });
    expect(large.response.status).toBe(413);
    expect(large.response.body.error.code).toBe('share-too-large');

    const share = await newShare(owner.token);
    const duplicate = await newShare(owner.token, { id: share.id });
    expect(duplicate.response.status).toBe(409);
  });

  it('opens a share sealed by the app with the page algorithm', async () => {
    // From test/safe_share_test.dart; the same steps as src/sharePage.html.
    const vector = {
      id: 'HGW-FZJe6hd71He22BrlUA',
      secret: 'BUjd8zykgy2SfDRVaT6o0ortQKuGtIImb65ahvhaZ3s',
      ciphertext:
        'y5z3ieEzK4sQDZjQVpoclOJXOSvwH1y7PcRmLOZ34H4QXc-Riqdzb8-DxxUWth7B-l7PM8dc' +
        'AHgoYVUk3WAbPwki8Qe1mflHIIrgfOYGskihzKvte2xEtK45mQzP9Zk2',
      accessHash: 'PAaCOW2JQecbbNhHnh3lkOGga25FlKq341DlBVqzj-Y',
      passwordSalt: 'dSU7QM9nq5lVIOYkqv3jPQ',
      kdfIterations: 100_000,
    };
    const owner = await registerUser('owner@example.com');
    const created = await call('POST', '/v1/shares', {
      token: owner.token,
      body: { ...vector, itemId: 'item-1', expiresInHours: 1, maxViews: 1 },
    });
    expect(created.status).toBe(201);

    const fromBase64Url = (text: string) =>
      Uint8Array.from(atob(text.replaceAll('-', '+').replaceAll('_', '/') + '==='.slice((text.length + 3) % 4)), (c) =>
        c.charCodeAt(0),
      );
    const encoder = new TextEncoder();
    const meta = (await call('GET', `/v1/shares/${vector.id}/meta`)).body;
    const passwordKey = await crypto.subtle.importKey('raw', encoder.encode('Correct-Horse-9'), 'PBKDF2', false, [
      'deriveBits',
    ]);
    const stretched = new Uint8Array(
      await crypto.subtle.deriveBits(
        { name: 'PBKDF2', hash: 'SHA-256', salt: fromBase64Url(meta.passwordSalt), iterations: meta.kdfIterations },
        passwordKey,
        256,
      ),
    );
    const root = await crypto.subtle.importKey(
      'raw',
      new Uint8Array([...fromBase64Url(vector.secret), ...stretched]),
      'HKDF',
      false,
      ['deriveBits'],
    );
    const context = encoder.encode(`amc-share.v1:${vector.id}`);
    const derive = async (info: string) =>
      new Uint8Array(
        await crypto.subtle.deriveBits(
          { name: 'HKDF', hash: 'SHA-256', salt: context, info: encoder.encode(info) },
          root,
          256,
        ),
      );

    const opened = await open(vector.id, base64Url(await derive('access')));
    expect(opened.status).toBe(200);
    expect(opened.body.viewsLeft).toBe(0);
    const sealed = fromBase64Url(opened.body.ciphertext);
    const key = await crypto.subtle.importKey('raw', await derive('enc'), 'AES-GCM', false, ['decrypt']);
    const clear = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: sealed.slice(0, 12), additionalData: context, tagLength: 128 },
      key,
      sealed.slice(12),
    );
    expect(JSON.parse(new TextDecoder().decode(clear))).toEqual({
      v: 1,
      kind: 'apiKey',
      title: 'Khoá thử',
      secret: 'sk_live_123',
    });
  });

  it('serves the opening page with a locked-down policy', async () => {
    const response = await exports.default.fetch(new Request(`${BASE}/s/${randomId()}`));
    expect(response.status).toBe(200);
    expect(response.headers.get('Content-Type')).toContain('text/html');
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect(response.headers.get('Referrer-Policy')).toBe('no-referrer');
    const policy = response.headers.get('Content-Security-Policy')!;
    const nonce = /script-src 'nonce-([A-Za-z0-9_-]+)'/.exec(policy)?.[1];
    expect(nonce).toBeTruthy();
    expect(policy).toContain("connect-src 'self'");
    const html = await response.text();
    expect(html).toContain(`<script nonce="${nonce}">`);
    expect(html).not.toContain('__NONCE__');
  });
});
