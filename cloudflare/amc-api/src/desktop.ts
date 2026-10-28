import { DurableObject } from 'cloudflare:workers';
import { authenticate, type AuthContext } from './auth';
import { randomBase64Url, sha256Base64Url } from './crypto';
import { ApiError, errorResponse, json, readJson, str } from './http';

type DesktopEnv = Env & { TURN_SECRET?: string };
type Device = { id: string; owner_id: string; cloud_id: string; fingerprint: string; name: string; platform: string; revoked: number; auth_hash?: string };
type Peer = { role: 'host' | 'viewer'; id: string; owner: string; fingerprint: string; name: string; sessionId: string; expires: number; count: number; window: number; authHash: string };
const idPattern = /^[a-zA-Z0-9-]{16,64}$/;
const tokenPattern = /^[a-zA-Z0-9_-]{43}$/;
const scopes = (v: unknown): string[] => {
  if (!Array.isArray(v) || !v.includes('view') || v.length > 3 || v.some(s => !['view', 'input', 'clipboard'].includes(s))) throw new ApiError(400, 'scope', 'Invalid desktop scopes.');
  return [...new Set(v)];
};
async function limitedBody(request: Request) {
  const reader = request.body?.getReader();
  const chunks: Uint8Array[] = []; let size = 0;
  if (reader) while (true) {
    const next = await reader.read(); if (next.done) break;
    size += next.value.length;
    if (size > 8192) { await reader.cancel(); throw new ApiError(413, 'body-size', 'Desktop request is too large.'); }
    chunks.push(next.value);
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  const text = new TextDecoder().decode(bytes);
  return readJson(new Request('https://internal/', { method: 'POST', body: text }));
}
async function owned(env: Env, auth: AuthContext, id: string): Promise<Device> {
  const device = await env.DB.prepare('SELECT * FROM desktop_devices WHERE id = ?1 AND owner_id = ?2 AND revoked = 0').bind(id, auth.uid).first<Device>();
  if (!device) throw new ApiError(403, 'device', 'Device is not enrolled for this account.');
  return device;
}
export async function desktopDispatch(request: Request, env: Env): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith('/v1/desktop/')) return null;
  if (String(env.DESKTOP_ENABLED) !== 'true') throw new ApiError(503, 'desktop-disabled', 'Internet desktop is not enabled on this server.');
  const auth = await authenticate(request, env);
  const rate = await env.DESKTOP_LIMITER.limit({ key: `${auth.uid}:${request.headers.get('CF-Connecting-IP') ?? 'unknown'}` });
  if (!rate.success) throw new ApiError(429, 'desktop-rate', 'Too many desktop requests.');
  if (url.pathname === '/v1/desktop/enroll' && request.method === 'POST') {
    const body = await limitedBody(request);
    const id = str(body.id), fingerprint = str(body.fingerprint), name = str(body.name), platform = str(body.platform);
    if (!idPattern.test(id) || !/^[a-f0-9]{64}$/.test(fingerprint) || !name || name.length > 80 || /[\x00-\x1f]/.test(name) || platform.length > 20) throw new ApiError(400, 'device', 'Invalid device identity.');
    const previous = await env.DB.prepare('SELECT * FROM desktop_devices WHERE id = ?1').bind(id).first<Device>();
    if (previous && (previous.owner_id !== auth.uid || previous.fingerprint !== fingerprint || previous.revoked)) throw new ApiError(409, 'identity-conflict', 'Existing device identity cannot be replaced. Revoke and use a new installation identity.');
    if (!previous) {
      const count = await env.DB.prepare('SELECT COUNT(*) AS n FROM desktop_devices WHERE owner_id = ?1 AND revoked = 0').bind(auth.uid).first<{ n: number }>();
      if ((count?.n ?? 0) >= 20) throw new ApiError(409, 'device-quota', 'Device quota reached.');
      let inserted = false;
      for (let attempt = 0; attempt < 5 && !inserted; attempt++) {
        const bytes = crypto.getRandomValues(new Uint32Array(2));
        const cloudId = ((BigInt(bytes[0]) << 32n | BigInt(bytes[1])) % 1000000000000n).toString().padStart(12, '0');
        try {
          await env.DB.prepare('INSERT INTO desktop_devices(id, owner_id, cloud_id, fingerprint, name, platform, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)').bind(id, auth.uid, cloudId, fingerprint, name, platform, new Date().toISOString()).run();
          inserted = true;
        } catch (e) { if (!String(e).includes('UNIQUE')) throw e; }
      }
      if (!inserted) throw new ApiError(409, 'device-conflict', 'Try enrollment again.');
    } else {
      await env.DB.prepare('UPDATE desktop_devices SET name = ?2, platform = ?3, updated_at = ?4 WHERE id = ?1').bind(id, name, platform, new Date().toISOString()).run();
    }
    return json(await owned(env, auth, id));
  }
  const hostId = url.searchParams.get('hostId') ?? '';
  const deviceId = url.searchParams.get('deviceId') ?? '';
  const device = await owned(env, auth, deviceId);
  const host = await env.DB.prepare('SELECT * FROM desktop_devices WHERE cloud_id = ?1 AND revoked = 0').bind(hostId).first<Device>();
  if (!host) throw new ApiError(404, 'host', 'Desktop host was not found.');
  const action = url.pathname.slice('/v1/desktop/'.length);
  if (['invite', 'approve', 'revoke', 'disable'].includes(action) && device.id !== host.id) throw new ApiError(403, 'owner', 'Only this host can change access.');
  if (!['socket', 'ticket', 'invite', 'approve', 'revoke', 'disable'].includes(action)) throw new ApiError(404, 'route', 'Unknown desktop action.');
  if ((action === 'socket' ? 'GET' : 'POST') !== request.method) throw new ApiError(405, 'method', 'Invalid desktop method.');
  if (action === 'disable') await env.DB.prepare('UPDATE desktop_devices SET revoked = 1 WHERE id = ?1').bind(host.id).run();
  const headers = new Headers({ 'Content-Type': 'application/json', 'X-Desktop-Peer': JSON.stringify({ ...device, auth_hash: auth.tokenHash }) });
  if (action === 'socket') {
    if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') throw new ApiError(426, 'websocket', 'WebSocket upgrade required.');
    headers.set('Upgrade', 'websocket');
    headers.set('X-Desktop-Ticket', request.headers.get('X-Desktop-Ticket') ?? '');
  }
  return env.DESKTOP_ROOMS.getByName(host.id).fetch(new Request(`https://room/${action}`, {
    method: request.method, headers, body: request.method === 'GET' ? undefined : JSON.stringify(await limitedBody(request)),
  }));
}

/** Private room per host. No media, clipboard or unencrypted signaling is accepted here. */
export class DesktopRoom extends DurableObject<DesktopEnv> {
  private sockets(role?: string) { return this.ctx.getWebSockets().filter(s => !role || (s.deserializeAttachment() as Peer).role === role); }
  private async ice(sessionId: string) {
    const stun = (this.env.STUN_URLS ?? '').split(',').map(s => s.trim()).filter(Boolean);
    if (stun.some(u => !/^stun:[^\s/@]+(?::\d+)?$/.test(u))) throw new ApiError(503, 'stun-config', 'STUN configuration is invalid.');
    const stunServers = stun.length ? [{ urls: stun }] : [];
    const urls = (this.env.TURN_URLS ?? '').split(',').map(s => s.trim()).filter(Boolean);
    if (!urls.length || !this.env.TURN_SECRET) return { iceServers: stunServers, expiresAt: null };
    if (urls.some(u => !/^turns?:[^\s/@]+(?::\d+)?(?:\?transport=(?:tcp|udp))?$/.test(u))) throw new ApiError(503, 'turn-config', 'TURN configuration is invalid.');
    const expiry = Math.floor(Date.now() / 1000) + 900;
    const username = `${expiry}:${sessionId}`;
    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(this.env.TURN_SECRET), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
    const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(username));
    return { iceServers: [...stunServers, { urls, username, credential: btoa(String.fromCharCode(...new Uint8Array(signature))) }], expiresAt: expiry * 1000 };
  }
  async fetch(request: Request): Promise<Response> {
    try {
      const device = JSON.parse(request.headers.get('X-Desktop-Peer')!) as Device;
      const action = new URL(request.url).pathname.slice(1);
      if (action === 'socket') return await this.upgrade(request, device);
      const body = await readJson(request);
      if (action === 'invite') {
        const code = str(body.code);
        if (!tokenPattern.test(code)) throw new ApiError(400, 'invite', 'Invalid invitation.');
        await this.ctx.storage.put('invite', { hash: await sha256Base64Url(code), expires: Date.now() + 300000 });
        return json({ expiresAt: Date.now() + 300000 });
      }
      if (action === 'ticket') {
        if (!this.sockets('host').length) throw new ApiError(409, 'offline', 'The host is offline.');
        if (this.sockets('viewer').length >= 1) throw new ApiError(409, 'busy', 'The host is busy.');
        const pending = await this.ctx.storage.list<{ expires: number }>({ prefix: 'ticket:' });
        if ([...pending.values()].filter(t => t.expires > Date.now()).length >= 4) throw new ApiError(429, 'tickets', 'Too many pending tickets.');
        const codeHash = await sha256Base64Url(str(body.code));
        const allowed = await this.ctx.storage.transaction(async tx => {
          const acl = await tx.get<{ owner: string; fingerprint: string }>(`acl:${device.id}`);
          if (acl?.owner === device.owner_id && acl.fingerprint === device.fingerprint) return true;
          const invite = await tx.get<{ hash: string; expires: number }>('invite');
          if (invite?.hash !== codeHash || invite.expires <= Date.now()) return false;
          await tx.delete('invite'); return true;
        });
        if (!allowed) throw new ApiError(403, 'not-paired', 'Invitation expired or device was revoked.');
        const ticket = randomBase64Url(32), sessionId = crypto.randomUUID();
        await this.ctx.storage.put(`ticket:${await sha256Base64Url(ticket)}`, { device, sessionId, expires: Date.now() + 30000 });
        await this.ctx.storage.setAlarm(Date.now() + 60000);
        return json({ ticket, sessionId, ...await this.ice(sessionId) });
      }
      if (action === 'approve') {
        const granted = scopes(body.scopes);
        const sessionId = str(body.sessionId);
        const socket = this.sockets('viewer').find(s => (s.deserializeAttachment() as Peer).sessionId === sessionId);
        if (!socket) throw new ApiError(409, 'closed', 'Session is no longer present.');
        const peer = socket.deserializeAttachment() as Peer;
        if (body.remember === true) await this.ctx.storage.put(`acl:${peer.id}`, { owner: peer.owner, fingerprint: peer.fingerprint, scopes: granted });
        return json(await this.ice(sessionId));
      }
      if (action === 'revoke') {
        const id = str(body.id);
        if (!idPattern.test(id)) throw new ApiError(400, 'device', 'Invalid controller.');
        await this.ctx.storage.delete(`acl:${id}`);
        for (const socket of this.sockets('viewer')) if ((socket.deserializeAttachment() as Peer).id === id) this.closePeer(socket);
        // Also invalidate unconsumed tickets for the revoked device.
        const tickets = await this.ctx.storage.list<{ device: Device }>({ prefix: 'ticket:' });
        for (const [key, ticket] of tickets) if (ticket.device.id === id) await this.ctx.storage.delete(key);
        return json({ ok: true });
      }
      if (action === 'disable') { for (const s of this.sockets()) s.close(1000, 'disabled'); await this.ctx.storage.deleteAll(); return json({ ok: true }); }
      throw new ApiError(404, 'route', 'Unknown desktop action.');
    } catch (error) { if (error instanceof ApiError) return errorResponse(error); throw error; }
  }
  private async upgrade(request: Request, device: Device) {
    let sessionId = '', role: 'host' | 'viewer' = 'host';
    const ticketValue = request.headers.get('X-Desktop-Ticket') ?? '';
    if (ticketValue) {
      if (!tokenPattern.test(ticketValue)) throw new ApiError(403, 'ticket', 'Invalid ticket.');
      role = 'viewer';
      const ticket = await this.ctx.storage.transaction(async tx => {
        const key = `ticket:${await sha256Base64Url(ticketValue)}`;
        const value = await tx.get<{ device: Device; sessionId: string; expires: number }>(key);
        if (!value || value.expires <= Date.now() || value.device.id !== device.id || value.device.owner_id !== device.owner_id || value.device.fingerprint !== device.fingerprint) return null;
        await tx.delete(key); return value;
      });
      if (!ticket || !this.sockets('host').length || this.sockets('viewer').length) throw new ApiError(403, 'ticket', 'Expired ticket or host unavailable.');
      sessionId = ticket.sessionId;
    } else {
      if (this.ctx.id.name !== device.id) throw new ApiError(403, 'owner', 'Only the host can open this listener.');
      for (const socket of this.sockets()) socket.close(1000, 'host-replaced');
    }
    const pair = new WebSocketPair();
    const peer: Peer = { role, id: device.id, owner: device.owner_id, fingerprint: device.fingerprint, name: device.name, sessionId, expires: Date.now() + (role === 'host' ? 86400000 : 900000), count: 0, window: Date.now(), authHash: device.auth_hash! };
    pair[1].serializeAttachment(peer);
    this.ctx.acceptWebSocket(pair[1]);
    if (role === 'viewer') for (const socket of this.sockets('host')) socket.send(JSON.stringify({ event: 'peer', sessionId, installationId: device.id, name: device.name }));
    await this.ctx.storage.setAlarm(Date.now() + 60000);
    return new Response(null, { status: 101, webSocket: pair[0] });
  }
  webSocketMessage(socket: WebSocket, raw: string | ArrayBuffer) {
    const peer = socket.deserializeAttachment() as Peer;
    if (typeof raw !== 'string' || raw.length > 400000 || Date.now() >= peer.expires) { this.closePeer(socket, 1009); return; }
    if (Date.now() - peer.window >= 10000) { peer.count = 0; peer.window = Date.now(); }
    if (++peer.count > 200) { this.closePeer(socket, 1008); return; }
    socket.serializeAttachment(peer);
    try {
      const value = JSON.parse(raw);
      if (value.event === 'ping') { socket.send('{"event":"pong"}'); return; }
      if (!idPattern.test(value.sessionId) || (peer.role === 'viewer' && value.sessionId !== peer.sessionId)) throw new Error('routing');
      if (value.event === 'close') {
        if (peer.role === 'viewer') this.closePeer(socket);
        else for (const target of this.sockets('viewer')) if ((target.deserializeAttachment() as Peer).sessionId === value.sessionId) this.closePeer(target);
        return;
      }
      if (value.event !== 'data' || typeof value.payload !== 'string' || value.payload.length > 360000) throw new Error('payload');
      const encrypted = JSON.parse(value.payload);
      const base64 = /^[A-Za-z0-9+/]+={0,2}$/;
      if (!(Object.keys(encrypted).length === 1 && typeof encrypted.key === 'string' && encrypted.key.length <= 1024 && base64.test(encrypted.key)) &&
          !(Object.keys(encrypted).length === 2 && Number.isSafeInteger(encrypted.seq) && encrypted.seq >= 0 && typeof encrypted.box === 'string' && encrypted.box.length <= 350000 && base64.test(encrypted.box))) throw new Error('ciphertext');
      for (const target of this.sockets(peer.role === 'host' ? 'viewer' : 'host')) {
        if (peer.role === 'viewer' || (target.deserializeAttachment() as Peer).sessionId === value.sessionId) target.send(JSON.stringify({ event: 'data', sessionId: value.sessionId, payload: value.payload }));
      }
    } catch { this.closePeer(socket, 1008); }
  }
  private closePeer(socket: WebSocket, code = 1000) {
    const peer = socket.deserializeAttachment() as Peer;
    socket.close(code, 'closed');
    if (peer.role === 'viewer') {
      for (const host of this.sockets('host')) host.send(JSON.stringify({ event: 'closed', sessionId: peer.sessionId }));
    } else for (const viewer of this.sockets('viewer')) viewer.close(1000, 'host-offline');
  }
  webSocketClose(socket: WebSocket) { this.closePeer(socket); }
  webSocketError(socket: WebSocket) { this.closePeer(socket); }
  async alarm() {
    for (const socket of this.sockets()) {
      const peer = socket.deserializeAttachment() as Peer;
      const valid = await this.env.DB.prepare('SELECT 1 AS ok FROM sessions s JOIN desktop_devices d ON d.owner_id = s.user_id WHERE s.token_hash = ?1 AND s.expires_at > ?2 AND d.id = ?3 AND d.revoked = 0').bind(peer.authHash, new Date().toISOString(), peer.id).first();
      if (!valid || peer.expires <= Date.now()) this.closePeer(socket);
    }
    const tickets = await this.ctx.storage.list<{ expires: number }>({ prefix: 'ticket:' });
    for (const [key, ticket] of tickets) if (ticket.expires <= Date.now()) await this.ctx.storage.delete(key);
    if (this.sockets().length || tickets.size) await this.ctx.storage.setAlarm(Date.now() + 60000);
  }
}
