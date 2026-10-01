import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createBroker } from './server.mjs';

async function fixture(fn) {
  let calls = 0; let now = 0;
  const server = createBroker({ clientId: 'test', clientSecret: 'private', publicURL: 'https://connector.example', clock: () => now,
    fetcher: async (_, options) => { calls++; assert.equal(options.body.get('client_secret'), 'private'); return Response.json({ access_token: 'access', refresh_token: 'refresh', expires_in: 3600 }); } });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const get = path => fetch(base + path, { redirect: 'manual' });
  const post = (path, data) => fetch(base + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(data) });
  try { await fn({ get, post, calls: () => calls, advance: ms => { now += ms; } }); }
  finally { await new Promise(resolve => server.close(resolve)); }
}

test('OAuth binds state and exchanges a one-time ticket without tokens in redirect', () => fixture(async ({ get, post, calls }) => {
  const state = 'a'.repeat(64);
  const auth = await get(`/authorize?state=${state}`);
  const upstream = new URL(auth.headers.get('location'));
  assert.ok(upstream.searchParams.get('scope').includes('offline'));
  const nonce = upstream.searchParams.get('state');
  assert.notEqual(nonce, state);
  assert.equal((await get('/callback?state=wrong&code=abc')).status, 400);
  const callback = await get(`/callback?state=${nonce}&code=abc`);
  const destination = new URL(callback.headers.get('location'));
  assert.equal(destination.searchParams.get('state'), state);
  assert.ok(!destination.href.includes('access'));
  const ticket = destination.searchParams.get('ticket');
  assert.equal((await post('/exchange', { ticket, state: 'wrong' })).status, 400);
  const response = await post('/exchange', { ticket, state });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).access_token, 'access');
  assert.equal((await post('/exchange', { ticket, state })).status, 400);
  assert.equal((await get(`/callback?state=${nonce}&code=abc`)).status, 400);
  assert.equal(calls(), 1);
}));

test('Expired OAuth state never exchanges credentials', () => fixture(async ({ get, calls, advance }) => {
  const auth = new URL((await get(`/authorize?state=${'b'.repeat(64)}`)).headers.get('location'));
  advance(600_001);
  assert.equal((await get(`/callback?state=${auth.searchParams.get('state')}&code=abc`)).status, 400);
  assert.equal(calls(), 0);
}));

test('Refresh validates input and rotates credentials', () => fixture(async ({ post, calls }) => {
  assert.equal((await post('/refresh', {})).status, 400);
  assert.equal(calls(), 0);
  const response = await post('/refresh', { refresh_token: 'old' });
  assert.equal((await response.json()).refresh_token, 'refresh');
  assert.equal(calls(), 1);
}));

test('OAuth requires an HTTPS origin', () => {
  assert.throws(() => createBroker({ clientId: 'x', clientSecret: 'y', publicURL: 'http://bad' }));
});
