import type { AuthContext } from './auth';
import { ApiError, json, noContent, nowIso, readJson } from './http';
import { requireMember } from './teams';

type ApiToolKind = 'collection' | 'folder' | 'request' | 'quickRequest';

const KIND_BY_SEGMENT: Record<string, ApiToolKind> = {
  collections: 'collection',
  folders: 'folder',
  requests: 'request',
  'quick-requests': 'quickRequest',
};

const SNAPSHOT_KEY: Record<ApiToolKind, string> = {
  collection: 'collections',
  folder: 'folders',
  request: 'requests',
  quickRequest: 'quickRequests',
};

// Keeps each bound JSON parameter well under D1's 2 MB value limit.
const CHUNK_BYTES = 900_000;

const UPSERT_SQL = `INSERT INTO api_tool_documents (team_id, kind, id, collection_id, data, updated_at)
  SELECT ?1, ?2, json_extract(value, '$.id'),
    CASE WHEN ?2 = 'collection' THEN json_extract(value, '$.id')
      ELSE coalesce(json_extract(value, '$.collectionId'), '') END,
    value, ?4
  FROM json_each(?3) WHERE true
  ON CONFLICT (team_id, kind, id) DO UPDATE SET
    collection_id = excluded.collection_id,
    data = excluded.data,
    updated_at = excluded.updated_at
  WHERE api_tool_documents.data <> excluded.data`;

export async function loadApiTools(env: Env, auth: AuthContext, teamId: string): Promise<Response> {
  await requireMember(env, auth, teamId);
  const { results } = await env.DB.prepare(
    'SELECT kind, data FROM api_tool_documents WHERE team_id = ?1',
  )
    .bind(teamId)
    .all<{ kind: ApiToolKind; data: string }>();

  const snapshot: Record<string, unknown[]> = {
    collections: [],
    folders: [],
    requests: [],
    quickRequests: [],
  };
  for (const row of results) {
    snapshot[SNAPSHOT_KEY[row.kind]].push(JSON.parse(row.data));
  }
  return json(snapshot);
}

/** Replaces the full set of one kind: upserts changed items, deletes missing ones. */
export async function replaceApiTools(
  request: Request,
  env: Env,
  auth: AuthContext,
  teamId: string,
  segment: string,
): Promise<Response> {
  const kind = requireKind(segment);
  await requireMember(env, auth, teamId, ['admin', 'dev']);
  const body = await readJson(request);
  const items = requireItems(body.items);
  const now = nowIso();

  const statements = [
    env.DB.prepare(
      `DELETE FROM api_tool_documents
       WHERE team_id = ?1 AND kind = ?2 AND id NOT IN (SELECT value FROM json_each(?3))`,
    ).bind(teamId, kind, JSON.stringify(items.map((item) => item.id))),
    ...chunkByJsonSize(items).map((chunk) =>
      env.DB.prepare(UPSERT_SQL).bind(teamId, kind, chunk, now),
    ),
  ];
  await env.DB.batch(statements);
  return noContent();
}

export async function deleteApiToolCollection(
  env: Env,
  auth: AuthContext,
  teamId: string,
  collectionId: string,
): Promise<Response> {
  await requireMember(env, auth, teamId, ['admin', 'dev']);
  await env.DB.batch([
    env.DB.prepare(
      `DELETE FROM api_tool_documents WHERE team_id = ?1 AND kind = 'collection' AND id = ?2`,
    ).bind(teamId, collectionId),
    env.DB.prepare(
      `DELETE FROM api_tool_documents WHERE team_id = ?1 AND kind <> 'collection' AND collection_id = ?2`,
    ).bind(teamId, collectionId),
  ]);
  return noContent();
}

function requireKind(segment: string): ApiToolKind {
  const kind = KIND_BY_SEGMENT[segment];
  if (!kind) {
    throw new ApiError(404, 'not-found', 'Unknown HTTP Tool kind.');
  }
  return kind;
}

function requireItems(value: unknown): Array<{ id: string } & Record<string, unknown>> {
  if (!Array.isArray(value)) {
    throw new ApiError(400, 'invalid-items', 'items must be an array.');
  }
  const seen = new Set<string>();
  const items: Array<{ id: string } & Record<string, unknown>> = [];
  for (const item of value) {
    const id = item && typeof item === 'object' ? (item as { id?: unknown }).id : undefined;
    if (typeof id !== 'string' || !id.trim()) {
      throw new ApiError(400, 'invalid-items', 'Every item needs a non-empty string id.');
    }
    if (seen.has(id)) {
      throw new ApiError(400, 'invalid-items', `Duplicate item id: ${id}`);
    }
    seen.add(id);
    items.push(item as { id: string } & Record<string, unknown>);
  }
  return items;
}

function chunkByJsonSize(items: unknown[]): string[] {
  const chunks: string[] = [];
  let current: string[] = [];
  let size = 2;
  for (const item of items) {
    const encoded = JSON.stringify(item);
    if (current.length > 0 && size + encoded.length + 1 > CHUNK_BYTES) {
      chunks.push(`[${current.join(',')}]`);
      current = [];
      size = 2;
    }
    current.push(encoded);
    size += encoded.length + 1;
  }
  if (current.length > 0) chunks.push(`[${current.join(',')}]`);
  return chunks;
}
