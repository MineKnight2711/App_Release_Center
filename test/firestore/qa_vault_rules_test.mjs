// Firestore rules for QA Desk's demo-account vault, against the emulator.
//
// firebase emulators:exec --only firestore --project demo-amc-rules \
//   "node --test test/firestore/qa_vault_rules_test.mjs"
//
// Uses the emulator's REST API and unsigned ID tokens, so it needs no npm
// packages. The `demo-` project never reaches a real Firebase project.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';

const project = process.env.GCLOUD_PROJECT ?? 'demo-amc-rules';
const host = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
const base = `http://${host}/v1/projects/${project}/databases/(default)/documents`;

function token(uid) {
  const encode = (value) =>
    Buffer.from(JSON.stringify(value)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return [
    encode({ alg: 'none', typ: 'JWT' }),
    encode({
      sub: uid,
      user_id: uid,
      iss: `https://securetoken.google.com/${project}`,
      aud: project,
      iat: now,
      exp: now + 3600,
      auth_time: now,
      firebase: { sign_in_provider: 'custom', identities: {} },
    }),
    '',
  ].join('.');
}

function fields(data) {
  const value = (item) => {
    if (item instanceof Date) return { timestampValue: item.toISOString() };
    if (typeof item === 'boolean') return { booleanValue: item };
    if (typeof item === 'number') return { integerValue: String(item) };
    return { stringValue: String(item) };
  };
  return Object.fromEntries(
    Object.entries(data).map(([key, item]) => [key, value(item)]),
  );
}

async function call(method, path, uid, data) {
  const response = await fetch(`${base}/${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${uid === 'owner' ? 'owner' : token(uid)}`,
      'Content-Type': 'application/json',
    },
    body: data ? JSON.stringify({ fields: fields(data) }) : undefined,
  });
  return response.status;
}

const get = (path, uid) => call('GET', path, uid);
const put = (path, uid, data) => call('PATCH', path, uid, data);
const remove = (path, uid) => call('DELETE', path, uid);
const team = 'teams/t1';
const ok = 200;
const denied = 403;

before(async () => {
  await fetch(
    `http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  await put(team, 'owner', { name: 'QA', createdByUid: 'admin' });
  await put(`${team}/members/admin`, 'owner', { role: 'admin', status: 'active' });
  await put(`${team}/members/dev`, 'owner', { role: 'dev', status: 'active' });
  await put(`${team}/members/dev2`, 'owner', { role: 'dev', status: 'active' });
  await put(`${team}/members/gone`, 'owner', { role: 'dev', status: 'removed' });
  await put(`${team}/qaAccounts/a1`, 'owner', { app: 'shop', secret: 'qav1:x' });
});

test('members read accounts; only admins change them', async () => {
  assert.equal(await get(`${team}/qaAccounts/a1`, 'dev'), ok);
  assert.equal(await get(`${team}/qaAccounts/a1`, 'gone'), denied);
  assert.equal(await get(`${team}/qaAccounts/a1`, 'stranger'), denied);
  assert.equal(await put(`${team}/qaAccounts/a1`, 'dev', { app: 'x' }), denied);
  assert.equal(await put(`${team}/qaAccounts/a2`, 'admin', { app: 'shop' }), ok);
  assert.equal(await remove(`${team}/qaAccounts/a2`, 'dev'), denied);
  assert.equal(await remove(`${team}/qaAccounts/a2`, 'admin'), ok);
});

test('only admins create or change the vault itself', async () => {
  assert.equal(await put(`${team}/qaVault/meta`, 'dev', { check: 'x' }), denied);
  assert.equal(await put(`${team}/qaVault/meta`, 'admin', { check: 'x' }), ok);
  assert.equal(await get(`${team}/qaVault/meta`, 'dev'), ok);
});

test('any member records a login result', async () => {
  assert.equal(
    await put(`${team}/qaAccountStatus/a1`, 'dev', { status: 'loginFailed' }),
    ok,
  );
  assert.equal(
    await put(`${team}/qaAccountStatus/a1`, 'stranger', { status: 'ok' }),
    denied,
  );
});

test('a lease is only taken in one\'s own name, and only when free', async () => {
  const soon = new Date(Date.now() + 10 * 60 * 1000);
  const past = new Date(Date.now() - 60 * 1000);
  const lease = (holderUid, expiresAt) => ({ holderUid, runId: 'r', expiresAt });

  assert.equal(
    await put(`${team}/qaAccountLeases/a1`, 'dev', lease('dev2', soon)),
    denied,
  );
  assert.equal(await put(`${team}/qaAccountLeases/a1`, 'dev', lease('dev', soon)), ok);
  // Renewing one's own lease is allowed; taking someone else's is not.
  assert.equal(await put(`${team}/qaAccountLeases/a1`, 'dev', lease('dev', soon)), ok);
  assert.equal(
    await put(`${team}/qaAccountLeases/a1`, 'dev2', lease('dev2', soon)),
    denied,
  );
  assert.equal(await remove(`${team}/qaAccountLeases/a1`, 'dev2'), denied);

  // Once it has expired, by server time, anyone may take it over.
  await put(`${team}/qaAccountLeases/a1`, 'owner', lease('dev', past));
  assert.equal(
    await put(`${team}/qaAccountLeases/a1`, 'dev2', lease('dev2', soon)),
    ok,
  );
  assert.equal(await remove(`${team}/qaAccountLeases/a1`, 'dev2'), ok);
});

test('the audit trail is append-only and admin-readable', async () => {
  assert.equal(
    await put(`${team}/qaAccountAudit/e1`, 'dev', { uid: 'dev', type: 'lease' }),
    ok,
  );
  assert.equal(
    await put(`${team}/qaAccountAudit/e1`, 'dev', { uid: 'dev', type: 'x' }),
    denied,
  );
  assert.equal(
    await put(`${team}/qaAccountAudit/e2`, 'dev', { uid: 'admin', type: 'lease' }),
    denied,
  );
  assert.equal(await get(`${team}/qaAccountAudit/e1`, 'dev'), denied);
  assert.equal(await get(`${team}/qaAccountAudit/e1`, 'admin'), ok);
  assert.equal(await remove(`${team}/qaAccountAudit/e1`, 'admin'), denied);
});
