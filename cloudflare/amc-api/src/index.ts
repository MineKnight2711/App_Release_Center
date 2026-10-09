import { deleteApiToolCollection, loadApiTools, replaceApiTools } from './apiTools';
import { type AuthContext, authenticate, login, logout, me, register } from './auth';
import { ApiError, errorResponse, json } from './http';
import {
  addQaAudit,
  deleteQaAccount,
  listQaAccounts,
  listQaLeases,
  listQaStatuses,
  putQaAccount,
  putQaStatus,
  readQaMeta,
  releaseQaLease,
  takeQaLease,
  writeQaMeta,
} from './qaVault';
import {
  createInvite,
  createTeam,
  joinTeam,
  listMembers,
  removeMember,
  updateMemberRole,
} from './teams';

type Params = Record<string, string>;
type PublicHandler = (request: Request, env: Env, params: Params) => Promise<Response>;
type SessionHandler = (
  request: Request,
  env: Env,
  auth: AuthContext,
  params: Params,
) => Promise<Response>;

interface Route {
  method: string;
  segments: string[];
  public?: PublicHandler;
  session?: SessionHandler;
}

function route(method: string, path: string, handler: { public?: PublicHandler; session?: SessionHandler }): Route {
  return { method, segments: path.split('/').filter(Boolean), ...handler };
}

const routes: Route[] = [
  route('GET', '/v1/health', { public: async () => json({ ok: true }) }),
  route('POST', '/v1/auth/register', { public: (request, env) => register(request, env) }),
  route('POST', '/v1/auth/login', { public: (request, env) => login(request, env) }),
  route('POST', '/v1/auth/logout', { session: (_, env, auth) => logout(env, auth) }),
  route('GET', '/v1/me', { session: (_, env, auth) => me(env, auth) }),
  route('POST', '/v1/teams', { session: (request, env, auth) => createTeam(request, env, auth) }),
  route('POST', '/v1/teams/join', { session: (request, env, auth) => joinTeam(request, env, auth) }),
  route('POST', '/v1/teams/:teamId/invites', {
    session: (request, env, auth, p) => createInvite(request, env, auth, p.teamId),
  }),
  route('GET', '/v1/teams/:teamId/members', {
    session: (_, env, auth, p) => listMembers(env, auth, p.teamId),
  }),
  route('PATCH', '/v1/teams/:teamId/members/:uid', {
    session: (request, env, auth, p) => updateMemberRole(request, env, auth, p.teamId, p.uid),
  }),
  route('DELETE', '/v1/teams/:teamId/members/:uid', {
    session: (_, env, auth, p) => removeMember(env, auth, p.teamId, p.uid),
  }),
  route('GET', '/v1/teams/:teamId/api-tools', {
    session: (_, env, auth, p) => loadApiTools(env, auth, p.teamId),
  }),
  route('PUT', '/v1/teams/:teamId/api-tools/:kind', {
    session: (request, env, auth, p) => replaceApiTools(request, env, auth, p.teamId, p.kind),
  }),
  route('DELETE', '/v1/teams/:teamId/api-tools/collections/:collectionId', {
    session: (_, env, auth, p) => deleteApiToolCollection(env, auth, p.teamId, p.collectionId),
  }),
  route('GET', '/v1/teams/:teamId/qa-vault/meta', {
    session: (_, env, auth, p) => readQaMeta(env, auth, p.teamId),
  }),
  route('PUT', '/v1/teams/:teamId/qa-vault/meta', {
    session: (request, env, auth, p) => writeQaMeta(request, env, auth, p.teamId),
  }),
  route('GET', '/v1/teams/:teamId/qa-vault/accounts', {
    session: (_, env, auth, p) => listQaAccounts(env, auth, p.teamId),
  }),
  route('PUT', '/v1/teams/:teamId/qa-vault/accounts/:accountId', {
    session: (request, env, auth, p) => putQaAccount(request, env, auth, p.teamId, p.accountId),
  }),
  route('DELETE', '/v1/teams/:teamId/qa-vault/accounts/:accountId', {
    session: (_, env, auth, p) => deleteQaAccount(env, auth, p.teamId, p.accountId),
  }),
  route('GET', '/v1/teams/:teamId/qa-vault/statuses', {
    session: (_, env, auth, p) => listQaStatuses(env, auth, p.teamId),
  }),
  route('PUT', '/v1/teams/:teamId/qa-vault/statuses/:accountId', {
    session: (request, env, auth, p) => putQaStatus(request, env, auth, p.teamId, p.accountId),
  }),
  route('GET', '/v1/teams/:teamId/qa-vault/leases', {
    session: (_, env, auth, p) => listQaLeases(env, auth, p.teamId),
  }),
  route('POST', '/v1/teams/:teamId/qa-vault/leases/:accountId', {
    session: (request, env, auth, p) => takeQaLease(request, env, auth, p.teamId, p.accountId),
  }),
  route('DELETE', '/v1/teams/:teamId/qa-vault/leases/:accountId', {
    session: (request, env, auth, p) => releaseQaLease(request, env, auth, p.teamId, p.accountId),
  }),
  route('POST', '/v1/teams/:teamId/qa-vault/audit', {
    session: (request, env, auth, p) => addQaAudit(request, env, auth, p.teamId),
  }),
];

function match(routeEntry: Route, segments: string[]): Params | null {
  if (routeEntry.segments.length !== segments.length) return null;
  const params: Params = {};
  for (let index = 0; index < segments.length; index++) {
    const expected = routeEntry.segments[index];
    if (expected.startsWith(':')) {
      params[expected.slice(1)] = segments[index];
    } else if (expected !== segments[index]) {
      return null;
    }
  }
  return params;
}

async function dispatch(request: Request, env: Env): Promise<Response> {
  const segments = new URL(request.url).pathname
    .split('/')
    .filter(Boolean)
    .map((segment) => decodeURIComponent(segment));

  let pathMatched = false;
  for (const entry of routes) {
    const params = match(entry, segments);
    if (!params) continue;
    pathMatched = true;
    if (entry.method !== request.method) continue;
    if (entry.public) return entry.public(request, env, params);
    const auth = await authenticate(request, env);
    return entry.session!(request, env, auth, params);
  }
  throw pathMatched
    ? new ApiError(405, 'method-not-allowed', 'Method not allowed.')
    : new ApiError(404, 'not-found', 'Route not found.');
}

export default {
  async fetch(request, env): Promise<Response> {
    try {
      return await dispatch(request, env);
    } catch (error) {
      if (error instanceof ApiError) return errorResponse(error);
      console.error('Unhandled error', error);
      return errorResponse(new ApiError(500, 'internal', 'Unexpected server error.'));
    }
  },
} satisfies ExportedHandler<Env>;
