import { env } from 'cloudflare:test';
import { exports } from 'cloudflare:workers';
import { describe, expect, it } from 'vitest';
import { cleanupAnalytics } from '../src/analytics';

async function call(method: string, path: string, token: string, body?: unknown) {
  const response = await exports.default.fetch(new Request(`https://amc-api.test/v1/analytics/${path}`, {
    method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  }));
  return { status: response.status, body: await response.json() as any };
}
async function principal(role = 'admin') {
  const uid = crypto.randomUUID(), team = crypto.randomUUID(), token = `amc_${crypto.randomUUID()}`;
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  const hash = btoa(String.fromCharCode(...new Uint8Array(digest))).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare('INSERT INTO users(id,email,password_salt,password_hash,created_at,updated_at,active_team_id) VALUES (?,?,?,?,?,?,?)').bind(uid, `${uid}@test.invalid`, 's', 'h', now, now, team),
    env.DB.prepare('INSERT INTO teams(id,name,created_by_uid,created_at,updated_at) VALUES (?,?,?,?,?)').bind(team, 'Analytics test', uid, now, now),
    env.DB.prepare('INSERT INTO team_members(team_id,user_id,role,joined_at,updated_at) VALUES (?,?,?,?,?)').bind(team, uid, role, now, now),
    env.DB.prepare('INSERT INTO sessions(token_hash,user_id,created_at,expires_at) VALUES (?,?,?,?)').bind(hash, uid, now, new Date(Date.now() + 86400000).toISOString()),
  ]);
  return { uid, team, token };
}
function event(team: string, overrides: Record<string, unknown> = {}) {
  return { schema_version: 1, event_id: crypto.randomUUID(), team_id: team,
    feature_id: 'bundle.check', event_name: 'action.started', operation_id: crypto.randomUUID(),
    occurred_at: new Date(Date.now() - 1000).toISOString(), platform: 'windows', build_id: 'pilot', source: 'file_picker', ...overrides };
}
const ingest = (p: Awaited<ReturnType<typeof principal>>, events: unknown[]) => call('POST', 'events', p.token, { expected_user_id: p.uid, events });

describe('feature analytics pilot', () => {
  it('deduplicates retries and conflicting terminal events, including results arriving first', async () => {
    const p = await principal();
    const started = event(p.team);
    const completed = event(p.team, { operation_id: started.operation_id, event_name: 'action.completed', duration_ms: 20, result_category: 'issues_found' });
    expect((await ingest(p, [completed, started])).body.ack.map((a: any) => a.status)).toEqual(['accepted', 'accepted']);
    expect((await ingest(p, [started, completed])).body.ack.map((a: any) => a.status)).toEqual(['duplicate', 'duplicate']);
    const failure = event(p.team, { operation_id: started.operation_id, event_name: 'action.failed', duration_ms: 20, error_code: 'file' });
    expect((await ingest(p, [failure])).body.ack[0].status).toBe('rejected');
    const report = await call('GET', `features?team=${p.team}&days=30`, p.token);
    expect(report.status).toBe(200);
    expect(report.body.features[0]).toMatchObject({ users: 1, uses: 1, completed: 1, failed: 0, unresolved: 0 });
    expect(report.body.features[1]).toMatchObject({ tracked: false, uses: 0 });
  });

  it('rejects sensitive fields, invalid timestamps, scopes, and account switches without poisoning a batch', async () => {
    const p = await principal(), other = await principal();
    const response = await ingest(p, [
      event(p.team, { path: 'C:/private/passwords' }),
      event(p.team, { occurred_at: new Date(Date.now() - 8 * 86400000).toISOString() }),
      event(p.team, { occurred_at: new Date(Date.now() + 3600000).toISOString() }),
      event(other.team), event(p.team),
    ]);
    expect(response.body.ack.map((a: any) => a.status)).toEqual(['rejected','rejected','rejected','rejected','accepted']);
    expect((await call('POST', 'events', other.token, { expected_user_id: p.uid, events: [event(other.team)] })).status).toBe(403);
    expect((await call('POST', 'events', p.token, { expected_user_id: p.uid, events: [], extra: 'secret' })).status).toBe(400);
    expect((await ingest(p, Array.from({ length: 101 }, () => event(p.team)))).status).toBe(400);
    expect((await ingest(p, [event(p.team, { secret: 'x'.repeat(140000) })])).status).toBe(413);
  });

  it('enforces team and global permissions on the server', async () => {
    const p = await principal(), dev = await principal('dev'), other = await principal();
    expect((await call('GET', 'features', p.token)).status).toBe(403);
    expect((await call('GET', `features?team=${other.team}`, p.token)).status).toBe(403);
    expect((await call('GET', `features?team=${dev.team}`, dev.token)).status).toBe(403);
    expect((await call('GET', 'access', dev.token)).body).toEqual({ global: false, teams: [] });
    await env.DB.prepare('INSERT INTO analytics_admins(user_id) VALUES (?)').bind(p.uid).run();
    expect((await call('GET', 'access', p.token)).body.global).toBe(true);
    expect((await call('GET', 'features', p.token)).status).toBe(200);
    expect((await call('GET', 'features?days=999', p.token)).status).toBe(400);
    expect((await call('GET', 'features', 'bad-token')).status).toBe(401);
  });

  it('counts distinct accounts across days and platforms, with unresolved results separate', async () => {
    const p = await principal();
    const yesterday = new Date(Date.now() - 86400000).toISOString();
    await ingest(p, [event(p.team, { occurred_at: yesterday }), event(p.team, { platform: 'macos' })]);
    const report = (await call('GET', `features?team=${p.team}`, p.token)).body.features[0];
    expect(report).toMatchObject({ users: 1, eligible_users: 1, uses: 2, returning_users: 1, unresolved: 2, completed: 0 });
    expect((await call('GET', `features?team=${p.team}&platform=windows`, p.token)).body.features[0]).toMatchObject({ uses: 1, returning_users: 0 });
  });

  it('matches outcomes to starts in the selected period and removes expired data', async () => {
    const p = await principal();
    const started = event(p.team);
    await ingest(p, [started, event(p.team, { operation_id: started.operation_id, event_name: 'action.completed', duration_ms: 50, result_category: 'passed' })]);
    // Simulate an older start outside a 7-day query, while its terminal is in range.
    await env.DB.prepare('UPDATE analytics_events SET occurred_at=? WHERE event_id=?').bind(new Date(Date.now() - 10 * 86400000).toISOString(), started.event_id).run();
    expect((await call('GET', `features?team=${p.team}&days=7`, p.token)).body.features[0]).toMatchObject({ uses: 0, completed: 0 });
    await env.DB.prepare('UPDATE analytics_events SET occurred_at=? WHERE event_id=?').bind(new Date(Date.now() - 100 * 86400000).toISOString(), started.event_id).run();
    await cleanupAnalytics(env);
    expect(await env.DB.prepare('SELECT 1 FROM analytics_events WHERE event_id=?').bind(started.event_id).first()).toBeNull();
  });
});
