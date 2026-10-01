import http from 'node:http';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

const scope = 'offline read:recovery read:cycles read:workout read:sleep read:body_measurement';
const origin = 'https://api.prod.whoop.com';
const callback = 'lockedinfit-whoop://callback';

export function createBroker({ clientId, clientSecret, publicURL, fetcher = fetch, clock = Date.now }) {
  const base = new URL(publicURL);
  if (base.protocol !== 'https:' || base.pathname !== '/' || base.search || base.hash) throw new Error('PUBLIC_URL must be an HTTPS origin');
  if (!clientId || !clientSecret) throw new Error('WHOOP client credentials required');
  const pending = new Map();
  const tickets = new Map();
  const limits = new Map();
  function clean() {
    for (const map of [pending, tickets, limits]) for (const [key, value] of map) if (value.expires <= clock()) map.delete(key);
  }
  const json = (res, status, body) => {
    res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' });
    res.end(JSON.stringify(body));
  };
  const redirect = (res, url) => {
    res.writeHead(302, { location: url, 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' }); res.end();
  };
  async function exchange(fields) {
    const response = await fetcher(`${origin}/oauth/oauth2/token`, {
      method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: clientId, client_secret: clientSecret, ...fields }),
      signal: AbortSignal.timeout(20_000), redirect: 'error'
    });
    if (!response.ok) throw new Error('Token exchange failed');
    const data = await response.json();
    if (typeof data.access_token !== 'string' || typeof data.expires_in !== 'number' || data.expires_in <= 0) throw new Error('Invalid tokens');
    // Whitelist response fields; never echo the client secret or upstream error.
    return { access_token: data.access_token, refresh_token: data.refresh_token, expires_in: data.expires_in };
  }
  async function body(req) {
    if (!req.headers['content-type']?.startsWith('application/json')) throw new Error('JSON required');
    const chunks = []; let size = 0;
    for await (const chunk of req) { size += chunk.length; if (size > 8192) throw new Error('Body too large'); chunks.push(chunk); }
    const data = JSON.parse(Buffer.concat(chunks));
    if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('Invalid body');
    return data;
  }
  return http.createServer(async (req, res) => {
    clean();
    // Use the socket IP: untrusted forwarded headers must not bypass limits.
    const ip = req.socket.remoteAddress;
    const limit = limits.get(ip) ?? { count: 0, expires: clock() + 60_000 };
    limits.set(ip, limit);
    if (++limit.count > 60 || pending.size + tickets.size > 500) return json(res, 429, { error: 'Try again later' });
    try {
      const url = new URL(req.url, base);
      if (req.method === 'GET' && url.pathname === '/health') return json(res, 200, { ok: true });
      if (req.method === 'GET' && url.pathname === '/authorize') {
        const state = url.searchParams.get('state');
        if (!state || !/^[a-zA-Z0-9-]{32,128}$/.test(state)) return json(res, 400, { error: 'Invalid state' });
        const nonce = crypto.randomBytes(32).toString('hex');
        pending.set(nonce, { state, expires: clock() + 10 * 60_000 });
        const target = new URL(`${origin}/oauth/oauth2/auth`);
        target.search = new URLSearchParams({ client_id: clientId, redirect_uri: `${base.origin}/callback`, response_type: 'code', scope, state: nonce });
        return redirect(res, target.href);
      }
      if (req.method === 'GET' && url.pathname === '/callback') {
        const nonce = url.searchParams.get('state');
        const flow = pending.get(nonce);
        pending.delete(nonce);
        if (!flow) return json(res, 400, { error: 'Expired authorization' });
        const target = new URL(callback); target.searchParams.set('state', flow.state);
        const code = url.searchParams.get('code');
        if (!code || url.searchParams.has('error')) { target.searchParams.set('error', 'authorization'); return redirect(res, target.href); }
        const tokens = await exchange({ grant_type: 'authorization_code', code, redirect_uri: `${base.origin}/callback` });
        const ticket = crypto.randomBytes(32).toString('hex');
        tickets.set(ticket, { state: flow.state, tokens, expires: clock() + 60_000 });
        target.searchParams.set('ticket', ticket);
        return redirect(res, target.href);
      }
      if (req.method === 'POST' && url.pathname === '/exchange') {
        const data = await body(req);
        const ticket = tickets.get(data.ticket);
        if (!ticket || ticket.state !== data.state) return json(res, 400, { error: 'Expired ticket' });
        tickets.delete(data.ticket);
        return json(res, 200, ticket.tokens);
      }
      if (req.method === 'POST' && url.pathname === '/refresh') {
        const data = await body(req);
        if (typeof data.refresh_token !== 'string' || !data.refresh_token || data.refresh_token.length > 4096) return json(res, 400, { error: 'Invalid refresh token' });
        return json(res, 200, await exchange({ grant_type: 'refresh_token', refresh_token: data.refresh_token, scope: 'offline' }));
      }
      return json(res, 404, { error: 'Not found' });
    } catch { return json(res, 400, { error: 'WHOOP authorization failed' }); }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const server = createBroker({ clientId: process.env.WHOOP_CLIENT_ID, clientSecret: process.env.WHOOP_CLIENT_SECRET, publicURL: process.env.PUBLIC_URL });
  server.listen(Number(process.env.PORT ?? 8080), '0.0.0.0');
}
