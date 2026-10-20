import type { AuthContext } from './auth';
import { ApiError, json } from './http';
import { requireMember } from './teams';

const DAY = 86_400_000;
const registry = [
  { id: 'bundle.check', name: 'Kiểm tra AAB', tracked: true },
  { id: 'release.android', name: 'Release Android', tracked: false },
  { id: 'release.ios', name: 'Release iOS', tracked: false },
  { id: 'plan.create', name: 'Plan Studio', tracked: false },
  { id: 'qa.run', name: 'QA Desk', tracked: false },
  { id: 'api.send', name: 'API Tools', tracked: false },
  { id: 'safe.item_save', name: 'Safe', tracked: false },
  { id: 'mail.scan', name: 'Mail Cleaner', tracked: false },
  { id: 'flowfin.import', name: 'FlowFin', tracked: false },
  { id: 'remote.release', name: 'Remote Release', tracked: false },
];
const names = ['app.active_day', 'feature.eligible_day', 'feature.opened', 'action.started', 'action.completed', 'action.failed'];
const fields = new Set(['schema_version', 'event_id', 'team_id', 'occurred_at', 'feature_id', 'event_name', 'operation_id', 'platform', 'build_id', 'source', 'duration_ms', 'result_category', 'error_code']);
const identifier = /^[a-zA-Z0-9_-]{1,80}$/;
interface Event {
  event_id: string; team_id: string; occurred_at: string; feature_id: string;
  event_name: string; operation_id?: string; platform: string; build_id: string;
  source: string; duration_ms?: number; result_category?: string; error_code?: string;
}
function parseEvent(input: unknown, now: number): Event | null {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return null;
  const v = input as Record<string, unknown>;
  if (Object.keys(v).some(k => !fields.has(k)) || v.schema_version !== 1) return null;
  if (![v.event_id, v.team_id, v.build_id].every(x => typeof x === 'string' && identifier.test(x))) return null;
  if (!names.includes(v.event_name as string)) return null;
  if (v.feature_id !== (v.event_name === 'app.active_day' ? 'app' : 'bundle.check')) return null;
  if (!['windows', 'macos', 'linux'].includes(v.platform as string)) return null;
  if (!['module', 'file_picker', 'drop', 'recheck'].includes(v.source as string)) return null;
  const at = typeof v.occurred_at === 'string' ? Date.parse(v.occurred_at) : NaN;
  if (!Number.isFinite(at) || at < now - 7 * DAY || at > now + 5 * 60_000) return null;
  const action = (v.event_name as string).startsWith('action.');
  const terminal = v.event_name === 'action.completed' || v.event_name === 'action.failed';
  if (action ? typeof v.operation_id !== 'string' || !identifier.test(v.operation_id) : v.operation_id !== undefined) return null;
  if (terminal) {
    if (!Number.isInteger(v.duration_ms) || (v.duration_ms as number) < 0 || (v.duration_ms as number) > DAY) return null;
  } else if (v.duration_ms !== undefined || v.result_category !== undefined || v.error_code !== undefined) return null;
  if (v.event_name === 'action.completed') {
    if (!['passed', 'issues_found'].includes(v.result_category as string) || v.error_code !== undefined) return null;
  }
  if (v.event_name === 'action.failed') {
    if (!['inspection', 'tool', 'file', 'unexpected'].includes(v.error_code as string) || v.result_category !== undefined) return null;
  }
  return { ...v, occurred_at: new Date(at).toISOString() } as unknown as Event;
}

async function isGlobalAdmin(env: Env, uid: string): Promise<boolean> {
  return !!await env.DB.prepare('SELECT user_id FROM analytics_admins WHERE user_id = ?').bind(uid).first();
}
export async function analyticsAccess(env: Env, auth: AuthContext): Promise<Response> {
  const teams = await env.DB.prepare(`SELECT t.id, t.name FROM teams t JOIN team_members m ON m.team_id=t.id
    WHERE m.user_id=? AND m.role='admin' AND m.status='active' ORDER BY t.name`).bind(auth.uid).all();
  return json({ global: await isGlobalAdmin(env, auth.uid), teams: teams.results });
}

// Read incrementally: Content-Length alone cannot protect a chunked request.
async function readBatch(request: Request): Promise<Record<string, unknown>> {
  const reader = request.body?.getReader();
  if (!reader) throw new ApiError(400, 'invalid-json', 'Missing batch.');
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > 128 * 1024) { await reader.cancel(); throw new ApiError(413, 'input-too-large', 'Batch exceeds 128 KB.'); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  try {
    const body = JSON.parse(new TextDecoder().decode(bytes));
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error();
    return body;
  } catch { throw new ApiError(400, 'invalid-json', 'Invalid batch.'); }
}

export async function ingestAnalytics(request: Request, env: Env, auth: AuthContext): Promise<Response> {
  const limited = await env.ANALYTICS_LIMITER.limit({ key: auth.uid });
  if (!limited.success) return Response.json({ error: { code: 'too-many-requests' } }, { status: 429, headers: { 'Retry-After': '60' } });
  const body = await readBatch(request);
  // A queued batch must never be attributed to a different signed-in account.
  if (body.expected_user_id !== auth.uid) throw new ApiError(403, 'analytics-account-mismatch', 'Account changed.');
  if (Object.keys(body).some(k => !['expected_user_id', 'events'].includes(k)) || !Array.isArray(body.events) || body.events.length > 100) {
    throw new ApiError(400, 'invalid-batch', 'Expected at most 100 events.');
  }
  await env.DB.prepare('INSERT OR IGNORE INTO analytics_subjects(user_id,subject_id) VALUES (?,?)').bind(auth.uid, crypto.randomUUID()).run();
  const subject = (await env.DB.prepare('SELECT subject_id FROM analytics_subjects WHERE user_id=?').bind(auth.uid).first<{ subject_id: string }>())!.subject_id;
  const allowedTeams = new Set((await env.DB.prepare(`SELECT team_id FROM team_members WHERE user_id=? AND status='active'`).bind(auth.uid).all<{ team_id: string }>()).results.map(t => t.team_id));
  const now = Date.now();
  const ack: { event_id: string; status: string; reason?: string }[] = [];
  for (const raw of body.events) {
    const event = parseEvent(raw, now);
    const id = typeof raw?.event_id === 'string' ? raw.event_id.slice(0, 80) : '';
    if (!event || !allowedTeams.has(event.team_id)) {
      ack.push({ event_id: id, status: 'rejected', reason: event ? 'team-access' : 'schema-or-time' }); continue;
    }
    const phase = event.operation_id ? (event.event_name === 'action.started' ? 'started' : 'terminal') : null;
    const result = await env.DB.prepare(`INSERT OR IGNORE INTO analytics_events
      (subject_id,event_id,team_id,feature_id,event_name,occurred_at,received_at,day,operation_id,phase,platform,build_id,source,duration_ms,result_category,error_code)
      SELECT ?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16
      WHERE NOT EXISTS (SELECT 1 FROM analytics_events WHERE subject_id=?1 AND operation_id=?9 AND (feature_id!=?4 OR team_id!=?3))`)
      .bind(subject, event.event_id, event.team_id, event.feature_id, event.event_name, event.occurred_at,
        new Date(now).toISOString(), event.occurred_at.slice(0, 10), event.operation_id ?? null, phase,
        event.platform, event.build_id, event.source, event.duration_ms ?? null, event.result_category ?? null, event.error_code ?? null).run();
    const duplicate = result.meta.changes === 0 && await env.DB.prepare('SELECT 1 FROM analytics_events WHERE subject_id=? AND event_id=?').bind(subject, event.event_id).first();
    ack.push({ event_id: id, status: result.meta.changes ? 'accepted' : duplicate ? 'duplicate' : 'rejected', ...(result.meta.changes || duplicate ? {} : { reason: 'operation-conflict' }) });
  }
  return json({ ack });
}

export async function analyticsFeatures(request: Request, env: Env, auth: AuthContext): Promise<Response> {
  const params = new URL(request.url).searchParams;
  const team = params.get('team') || null;
  if (team) {
    if (!await isGlobalAdmin(env, auth.uid)) await requireMember(env, auth, team, ['admin']);
  } else if (!await isGlobalAdmin(env, auth.uid)) throw new ApiError(403, 'permission-denied', 'Global analytics access is required.');
  const days = Number(params.get('days') ?? 30);
  const platform = params.get('platform') || null;
  if (![7, 30, 90].includes(days) || (platform && !['windows', 'macos', 'linux'].includes(platform))) throw new ApiError(400, 'invalid-filter', 'Unsupported filter.');
  const start = new Date(); start.setUTCHours(0, 0, 0, 0); start.setUTCDate(start.getUTCDate() - days + 1);
  const now = new Date().toISOString();
  const bindings = [start.toISOString(), now, team, platform];
  const rows = await env.DB.prepare(`WITH selected AS (
      SELECT * FROM analytics_events WHERE occurred_at>=?1 AND occurred_at<=?2 AND (?3 IS NULL OR team_id=?3) AND (?4 IS NULL OR platform=?4)
    ), per_user AS (
      SELECT feature_id,subject_id,COUNT(DISTINCT day) AS active_days FROM selected WHERE event_name='action.started' GROUP BY feature_id,subject_id
    ) SELECT feature_id,
      COUNT(DISTINCT CASE WHEN event_name IN ('feature.eligible_day','action.started') THEN subject_id END) AS eligible_users,
      COUNT(DISTINCT CASE WHEN event_name='action.started' THEN subject_id END) AS users,
      SUM(event_name='feature.opened') AS opens, SUM(event_name='action.started') AS uses,
      SUM(event_name='action.started' AND EXISTS(SELECT 1 FROM analytics_events e WHERE e.subject_id=selected.subject_id AND e.operation_id=selected.operation_id AND e.event_name='action.completed' AND e.occurred_at<=?2)) AS completed,
      SUM(event_name='action.started' AND EXISTS(SELECT 1 FROM analytics_events e WHERE e.subject_id=selected.subject_id AND e.operation_id=selected.operation_id AND e.event_name='action.failed' AND e.occurred_at<=?2)) AS failed,
      (SELECT COUNT(*) FROM per_user u WHERE u.feature_id=selected.feature_id AND active_days>=2) AS returning_users,
      MAX(received_at) AS last_received_at
      FROM selected GROUP BY feature_id`).bind(...bindings).all<Record<string, unknown>>();
  // Match outcomes across the window boundary; never infer failures from missing events.
  const pending = await env.DB.prepare(`SELECT s.feature_id,COUNT(*) AS unresolved FROM analytics_events s
    WHERE s.event_name='action.started' AND s.occurred_at>=?1 AND s.occurred_at<=?2 AND (?3 IS NULL OR s.team_id=?3) AND (?4 IS NULL OR s.platform=?4)
    AND NOT EXISTS(SELECT 1 FROM analytics_events e WHERE e.subject_id=s.subject_id AND e.operation_id=s.operation_id AND e.phase='terminal' AND e.occurred_at<=?2)
    GROUP BY s.feature_id`).bind(...bindings).all<{ feature_id: string; unresolved: number }>();
  const activeCount = await env.DB.prepare(`SELECT COUNT(DISTINCT subject_id) AS count FROM analytics_events WHERE event_name='app.active_day'
    AND occurred_at>=?1 AND occurred_at<=?2 AND (?3 IS NULL OR team_id=?3) AND (?4 IS NULL OR platform=?4)`).bind(...bindings).first<{ count: number }>();
  return json({ days, timezone: 'UTC', generated_at: now, active_users: activeCount?.count ?? 0,
    coverage: 'Pilot: chỉ bundle.check có tracking; chỉ quan sát tài khoản bật thống kê. Chưa biết độ phủ toàn bộ cài đặt.',
    features: registry.map(f => {
      const r = rows.results.find(r => r.feature_id === f.id);
      return { ...f, eligible_users: 0, users: 0, opens: 0, uses: 0, completed: 0, failed: 0, returning_users: 0,
        last_received_at: null, ...r, unresolved: pending.results.find(p => p.feature_id === f.id)?.unresolved ?? 0 };
    }), last_received_at: rows.results.reduce<string | null>((latest, r) => typeof r.last_received_at === 'string' && (!latest || r.last_received_at > latest) ? r.last_received_at : latest, null) });
}

export async function cleanupAnalytics(env: Env): Promise<void> {
  // Bounded work per invocation; indexed cutoff avoids affecting the shared relay DB.
  const cutoff = new Date(Date.now() - 90 * DAY).toISOString();
  await env.DB.prepare(`DELETE FROM analytics_events WHERE rowid IN
    (SELECT rowid FROM analytics_events WHERE occurred_at < ? ORDER BY occurred_at LIMIT 5000)`).bind(cutoff).run();
}
