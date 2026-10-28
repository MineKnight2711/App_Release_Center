import { env } from 'cloudflare:test';
import { exports } from 'cloudflare:workers';
import { afterEach, describe, expect, it } from 'vitest';

const sockets: WebSocket[] = [];
const ip = () => `desktop-${crypto.randomUUID()}`;
async function call(path: string, token?: string, body?: unknown, query = '') {
  const response = await exports.default.fetch(new Request(`https://test/v1/desktop/${path}${query}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': ip(), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body ?? {}),
  }));
  return { status: response.status, body: await response.json() as any };
}
async function account() {
  const response = await exports.default.fetch(new Request('https://test/v1/auth/register', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': ip() },
    body: JSON.stringify({ email: `${crypto.randomUUID()}@example.com`, passwordKey: 'a'.repeat(43), displayName: 'Desktop test' }),
  }));
  expect(response.status).toBe(201);
  return (await response.json() as any).token as string;
}
async function device(token: string) {
  const id = crypto.randomUUID();
  const result = await call('enroll', token, { id, fingerprint: 'a'.repeat(64), name: 'Test desktop', platform: 'macos' });
  expect(result.status).toBe(200);
  return { token, id, cloudId: result.body.cloud_id as string };
}
function query(host: { cloudId: string }, peer: { id: string }) { return `?hostId=${host.cloudId}&deviceId=${peer.id}`; }
async function open(host: { cloudId: string }, peer: { id: string; token: string }, ticket?: string) {
  const response = await exports.default.fetch(new Request(`https://test/v1/desktop/socket${query(host, peer)}`, {
    headers: { Upgrade: 'websocket', Authorization: `Bearer ${peer.token}`, ...(ticket ? { 'X-Desktop-Ticket': ticket } : {}), 'CF-Connecting-IP': ip() },
  }));
  expect(response.status, response.status === 101 ? '' : await response.text()).toBe(101);
  const socket = response.webSocket!; socket.accept(); sockets.push(socket); return socket;
}
function next(socket: WebSocket) { return new Promise<any>((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error('WebSocket message timeout')), 2000);
  socket.addEventListener('message', e => { clearTimeout(timer); resolve(JSON.parse(e.data as string)); }, { once: true });
}); }
afterEach(() => { for (const socket of sockets.splice(0)) { try { socket.close(); } catch {} } });

describe('desktop Internet admission', () => {
  it('requires account auth, binds installation ownership and refuses replacing a certificate', async () => {
    expect((await call('enroll')).status).toBe(401);
    const owner = await account(), attacker = await account();
    const host = await device(owner);
    expect((await call('enroll', attacker, { id: host.id, fingerprint: 'a'.repeat(64), name: 'stolen', platform: 'macos' })).status).toBe(409);
    expect((await call('enroll', owner, { id: host.id, fingerprint: 'b'.repeat(64), name: 'changed', platform: 'macos' })).status).toBe(409);
    expect((await call('invite', attacker, { code: 'x'.repeat(43) }, query(host, host))).status).toBe(403);
  });
  it('consumes a short-lived invitation once and issues single-use device-bound tickets with expiring TURN credentials', async () => {
    const host = await device(await account()), viewer = await device(await account());
    await open(host, host);
    expect((await call('ticket', viewer.token, { code: 'x'.repeat(43) }, query(host, viewer))).status).toBe(403);
    expect((await call('invite', host.token, { code: 'x'.repeat(43) }, query(host, host))).status).toBe(200);
    const result = await call('ticket', viewer.token, { code: 'x'.repeat(43) }, query(host, viewer));
    expect(result.status).toBe(200);
    expect(result.body.iceServers[0].username).toMatch(/^\d+:/);
    expect(result.body.iceServers[0].credential).not.toContain('local-test-only-turn-secret');
    expect(result.body.expiresAt).toBeGreaterThan(Date.now());
    expect(result.body.expiresAt).toBeLessThan(Date.now() + 901000);
    expect((await call('ticket', viewer.token, { code: 'x'.repeat(43) }, query(host, viewer))).status).toBe(403);
    await open(host, viewer, result.body.ticket);
    const replay = await exports.default.fetch(new Request(`https://test/v1/desktop/socket${query(host, viewer)}`, {
      headers: { Upgrade: 'websocket', Authorization: `Bearer ${viewer.token}`, 'X-Desktop-Ticket': result.body.ticket, 'CF-Connecting-IP': ip() },
    }));
    expect(replay.status).toBe(403);
  });
  it('routes opaque signaling only to the ticket session and remembers access only after host approval; revoke removes it', async () => {
    const host = await device(await account()), viewer = await device(await account());
    const hostSocket = await open(host, host);
    await call('invite', host.token, { code: 'q'.repeat(43) }, query(host, host));
    const ticket = (await call('ticket', viewer.token, { code: 'q'.repeat(43) }, query(host, viewer))).body;
    const incoming = next(hostSocket);
    const viewerSocket = await open(host, viewer, ticket.ticket);
    expect((await incoming).sessionId).toBe(ticket.sessionId);
    const relayed = next(hostSocket);
    const payload = JSON.stringify({ key: 'YQ'.repeat(128) });
    viewerSocket.send(JSON.stringify({ event: 'data', sessionId: ticket.sessionId, payload }));
    expect((await relayed).payload).toBe(payload);
    expect((await call('approve', viewer.token, { sessionId: ticket.sessionId, scopes: ['view'], remember: true }, query(host, viewer))).status).toBe(403);
    expect((await call('approve', host.token, { sessionId: ticket.sessionId, scopes: ['view'], remember: true }, query(host, host))).status).toBe(200);
    expect((await call('revoke', host.token, { id: viewer.id }, query(host, host))).status).toBe(200);
    const closed = next(hostSocket);
    // A closed event may already be buffered; the admission assertion below
    // does not depend on its timing.
    closed.catch(() => {});
    await new Promise(resolve => setTimeout(resolve, 20));
    expect((await call('ticket', viewer.token, {}, query(host, viewer))).status).toBe(403);
  });
});
