import type { AuthContext } from './auth';
import { ApiError, json, noContent, nowIso, readJson, str } from './http';
import { requireMember } from './teams';

// Permissions mirror the QA Desk design: members read the vault and record
// login results; only admins change the vault itself; a lease is taken only
// in one's own name, while free, already one's own, or expired.

export async function readQaMeta(env: Env, auth: AuthContext, teamId: string): Promise<Response> {
  await requireMember(env, auth, teamId);
  const row = await env.DB.prepare('SELECT data FROM qa_vault_meta WHERE team_id = ?1')
    .bind(teamId)
    .first<{ data: string }>();
  return json({ meta: row ? JSON.parse(row.data) : null });
}

export async function writeQaMeta(
  request: Request,
  env: Env,
  auth: AuthContext,
  teamId: string,
): Promise<Response> {
  await requireMember(env, auth, teamId, ['admin']);
  const meta = requireObject((await readJson(request)).meta, 'meta');
  await env.DB.prepare(
    `INSERT INTO qa_vault_meta (team_id, data, updated_at) VALUES (?1, ?2, ?3)
     ON CONFLICT (team_id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`,
  )
    .bind(teamId, JSON.stringify(meta), nowIso())
    .run();
  return noContent();
}

export async function listQaAccounts(env: Env, auth: AuthContext, teamId: string): Promise<Response> {
  await requireMember(env, auth, teamId);
  return json({ accounts: await documentsById(env, 'qa_accounts', 'id', teamId) });
}

export async function putQaAccount(
  request: Request,
  env: Env,
  auth: AuthContext,
  teamId: string,
  accountId: string,
): Promise<Response> {
  await requireMember(env, auth, teamId, ['admin']);
  const document = requireObject((await readJson(request)).document, 'document');
  await env.DB.prepare(
    `INSERT INTO qa_accounts (team_id, id, data, updated_at) VALUES (?1, ?2, ?3, ?4)
     ON CONFLICT (team_id, id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`,
  )
    .bind(teamId, accountId, JSON.stringify(document), nowIso())
    .run();
  return noContent();
}

export async function deleteQaAccount(
  env: Env,
  auth: AuthContext,
  teamId: string,
  accountId: string,
): Promise<Response> {
  await requireMember(env, auth, teamId, ['admin']);
  await env.DB.prepare('DELETE FROM qa_accounts WHERE team_id = ?1 AND id = ?2')
    .bind(teamId, accountId)
    .run();
  return noContent();
}

export async function listQaStatuses(env: Env, auth: AuthContext, teamId: string): Promise<Response> {
  await requireMember(env, auth, teamId);
  return json({ statuses: await documentsById(env, 'qa_account_status', 'account_id', teamId) });
}

export async function putQaStatus(
  request: Request,
  env: Env,
  auth: AuthContext,
  teamId: string,
  accountId: string,
): Promise<Response> {
  await requireMember(env, auth, teamId);
  const status = requireObject((await readJson(request)).status, 'status');
  await env.DB.prepare(
    `INSERT INTO qa_account_status (team_id, account_id, data, updated_at) VALUES (?1, ?2, ?3, ?4)
     ON CONFLICT (team_id, account_id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`,
  )
    .bind(teamId, accountId, JSON.stringify(status), nowIso())
    .run();
  return noContent();
}

export async function listQaLeases(env: Env, auth: AuthContext, teamId: string): Promise<Response> {
  await requireMember(env, auth, teamId);
  const { results } = await env.DB.prepare(
    `SELECT account_id, holder_uid, holder_name, machine, run_id, expires_at
     FROM qa_account_leases WHERE team_id = ?1`,
  )
    .bind(teamId)
    .all<{
      account_id: string;
      holder_uid: string;
      holder_name: string;
      machine: string;
      run_id: string;
      expires_at: string;
    }>();
  const leases: Record<string, unknown> = {};
  for (const row of results) {
    leases[row.account_id] = {
      holderUid: row.holder_uid,
      holderName: row.holder_name,
      machine: row.machine,
      runId: row.run_id,
      expiresAt: row.expires_at,
    };
  }
  return json({ leases });
}

/** One conditional upsert, so two machines racing for an account cannot both win. */
export async function takeQaLease(
  request: Request,
  env: Env,
  auth: AuthContext,
  teamId: string,
  accountId: string,
): Promise<Response> {
  await requireMember(env, auth, teamId);
  const body = await readJson(request);
  const expiresAtMs = Date.parse(str(body.expiresAt));
  if (!Number.isFinite(expiresAtMs)) {
    throw new ApiError(400, 'invalid-lease', 'expiresAt must be an ISO-8601 time.');
  }
  const result = await env.DB.prepare(
    `INSERT INTO qa_account_leases (team_id, account_id, holder_uid, holder_name, machine, run_id, expires_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
     ON CONFLICT (team_id, account_id) DO UPDATE SET
       holder_uid = excluded.holder_uid,
       holder_name = excluded.holder_name,
       machine = excluded.machine,
       run_id = excluded.run_id,
       expires_at = excluded.expires_at
     WHERE qa_account_leases.holder_uid = excluded.holder_uid
        OR qa_account_leases.expires_at <= ?8`,
  )
    .bind(
      teamId,
      accountId,
      auth.uid,
      str(body.holderName).slice(0, 120),
      str(body.machine).slice(0, 120),
      str(body.runId).slice(0, 120),
      new Date(expiresAtMs).toISOString(),
      nowIso(),
    )
    .run();
  return json({ acquired: result.meta.changes > 0 });
}

export async function releaseQaLease(
  request: Request,
  env: Env,
  auth: AuthContext,
  teamId: string,
  accountId: string,
): Promise<Response> {
  await requireMember(env, auth, teamId);
  const runId = new URL(request.url).searchParams.get('runId') ?? '';
  await env.DB.prepare(
    `DELETE FROM qa_account_leases
     WHERE team_id = ?1 AND account_id = ?2 AND holder_uid = ?3 AND run_id = ?4`,
  )
    .bind(teamId, accountId, auth.uid, runId)
    .run();
  return noContent();
}

export async function addQaAudit(
  request: Request,
  env: Env,
  auth: AuthContext,
  teamId: string,
): Promise<Response> {
  await requireMember(env, auth, teamId);
  const event = requireObject((await readJson(request)).event, 'event');
  // The author is the session's user, whatever the event claims.
  const stamped = { ...event, uid: auth.uid };
  await env.DB.prepare(
    'INSERT INTO qa_account_audit (team_id, uid, data, server_at) VALUES (?1, ?2, ?3, ?4)',
  )
    .bind(teamId, auth.uid, JSON.stringify(stamped), nowIso())
    .run();
  return noContent();
}

async function documentsById(
  env: Env,
  table: 'qa_accounts' | 'qa_account_status',
  idColumn: 'id' | 'account_id',
  teamId: string,
): Promise<Record<string, unknown>> {
  const { results } = await env.DB.prepare(
    `SELECT ${idColumn} AS id, data FROM ${table} WHERE team_id = ?1`,
  )
    .bind(teamId)
    .all<{ id: string; data: string }>();
  return Object.fromEntries(results.map((row) => [row.id, JSON.parse(row.data)]));
}

function requireObject(value: unknown, name: string): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ApiError(400, 'invalid-body', `${name} must be a JSON object.`);
  }
  return value as Record<string, unknown>;
}
