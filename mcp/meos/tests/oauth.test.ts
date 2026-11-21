import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHarness, testConfig } from './support/harness.ts';
import { createHttpServer } from '../src/http.ts';
import { ServiceRegistry } from '../src/services/account.ts';
import { RateLimiter } from '../src/auth/rateLimit.ts';
import { silentLogger } from '../src/services/logger.ts';
import { AuditLog } from '../src/services/audit.ts';
import type { AccountConfig } from '../src/config/types.ts';

function pkce(): { verifier: string; challenge: string } {
  const verifier = randomBytes(48).toString('base64url');
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  return { verifier, challenge };
}

function mcpHeaders(token: string): Record<string, string> {
  return {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
    // The MCP Streamable HTTP transport requires both media types even when
    // the server answers with JSON.
    Accept: 'application/json, text/event-stream'
  };
}

function form(fields: Record<string, string | string[]>): string {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries(fields)) {
    if (Array.isArray(v)) for (const item of v) p.append(k, item);
    else p.set(k, v);
  }
  return p.toString();
}

async function startOAuthServer() {
  const h = await createHarness();
  const dir = mkdtempSync(join(tmpdir(), 'meos-oauth-'));
  const account: AccountConfig = {
    id: 'a',
    baseUrl: h.baseUrl,
    username: h.accounts.a.username,
    password: h.accounts.a.password,
    vaultPassphrase: h.accounts.a.passphrase,
    requestTimeoutMs: 5000
  };
  const config = testConfig({
    accounts: new Map([
      ['a', account],
      // OAuth clients are registered against the owner account, matching the
      // single-owner production configuration.
      ['owner', { ...account, id: 'owner' }]
    ]),
    clients: new Map(),
    oauth: {
      issuer: 'http://127.0.0.1:0',
      resource: 'http://127.0.0.1:0/mcp',
      adminPassword: 'test-admin-password-123',
      storePath: join(dir, 'oauth.json'),
      allowDynamicClientRegistration: true,
      adminLocalOnly: true,
      accessTokenTtlSeconds: 900
    }
  });
  const audit = new AuditLog(join(dir, 'audit.log'));
  const http = createHttpServer({
    config,
    registry: new ServiceRegistry(config.accounts, silentLogger),
    limiter: new RateLimiter(60_000, 1000),
    logger: silentLogger,
    audit
  });
  await new Promise<void>((resolve) => http.listen(0, '127.0.0.1', resolve));
  const address = http.address();
  const port = typeof address === 'object' && address ? address.port : 0;
  const base = `http://127.0.0.1:${port}`;
  config.oauth!.issuer = base;
  config.oauth!.resource = `${base}/mcp`;
  return {
    h,
    base,
    config,
    close: async () => {
      await new Promise<void>((resolve) => http.close(() => resolve()));
      await h.close();
    }
  };
}

async function register(base: string): Promise<{ clientId: string; redirectUri: string }> {
  const redirectUri = 'http://127.0.0.1:9999/callback';
  const res = await fetch(`${base}/oauth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_name: 'Test ChatGPT',
      redirect_uris: [redirectUri],
      token_endpoint_auth_method: 'none',
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'],
      scope: 'meos.profile.read meos.finance.read'
    })
  });
  assert.equal(res.status, 201);
  const body: any = await res.json();
  return { clientId: body.client_id, redirectUri };
}

async function authorize(
  base: string,
  clientId: string,
  redirectUri: string,
  challenge: string,
  scopes: string,
  approvedScopes?: string[]
): Promise<string> {
  const params = new URLSearchParams({
    response_type: 'code',
    client_id: clientId,
    redirect_uri: redirectUri,
    code_challenge: challenge,
    code_challenge_method: 'S256',
    state: 'state-123',
    scope: scopes,
    resource: `${base}/mcp`
  });
  const page = await fetch(`${base}/oauth/authorize?${params}`);
  assert.equal(page.status, 200);
  const html = await page.text();
  const requestId = /name="request_id" value="([^"]+)"/.exec(html)?.[1];
  const csrf = /name="csrf" value="([^"]+)"/.exec(html)?.[1];
  assert.ok(requestId && csrf);
  const selected = approvedScopes ?? scopes.split(/\s+/).filter(Boolean);
  const res = await fetch(`${base}/oauth/authorize`, {
    method: 'POST',
    redirect: 'manual',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form({
      request_id: requestId!,
      csrf: csrf!,
      decision: 'allow',
      admin_password: 'test-admin-password-123',
      scope: selected
    })
  });
  assert.equal(res.status, 302);
  const location = res.headers.get('location')!;
  const code = new URL(location).searchParams.get('code');
  assert.ok(code);
  return code!;
}

async function exchange(
  base: string,
  clientId: string,
  redirectUri: string,
  code: string,
  verifier: string
): Promise<any> {
  const res = await fetch(`${base}/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form({
      grant_type: 'authorization_code',
      client_id: clientId,
      redirect_uri: redirectUri,
      code,
      code_verifier: verifier,
      resource: `${base}/mcp`
    })
  });
  return { status: res.status, body: await res.json() };
}

test('OAuth: dynamic registration, PKCE consent, token and scoped MCP access', async () => {
  const s = await startOAuthServer();
  try {
    const { clientId, redirectUri } = await register(s.base);
    const { verifier, challenge } = pkce();
    const code = await authorize(s.base, clientId, redirectUri, challenge, 'meos.profile.read meos.finance.read');
    const token = await exchange(s.base, clientId, redirectUri, code, verifier);
    assert.equal(token.status, 200);
    assert.equal(token.body.token_type, 'Bearer');
    assert.ok(token.body.refresh_token);

    const init = await fetch(`${s.base}/mcp`, {
      method: 'POST',
      headers: mcpHeaders(token.body.access_token),
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'test', version: '1' } } })
    });
    assert.equal(init.status, 200, await init.text());

    const list = await fetch(`${s.base}/mcp`, {
      method: 'POST',
      headers: mcpHeaders(token.body.access_token),
      body: JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} })
    });
    assert.equal(list.status, 200);
    const listed: any = await list.json();
    const names = listed.result.tools.map((t: any) => t.name);
    assert.ok(names.includes('meos_finance_get_summary'));
    assert.equal(names.includes('meos_notes_create'), false);

    const call = await fetch(`${s.base}/mcp`, {
      method: 'POST',
      headers: mcpHeaders(token.body.access_token),
      body: JSON.stringify({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'meos_finance_get_summary', arguments: {} } })
    });
    assert.equal(call.status, 200);
    const called: any = await call.json();
    assert.equal(called.result.structuredContent.success, true);

    const denied = await fetch(`${s.base}/mcp`, {
      method: 'POST',
      headers: mcpHeaders(token.body.access_token),
      body: JSON.stringify({ jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'meos_notes_create', arguments: { title: 'x', body: 'y' } } })
    });
    const deniedBody: any = await denied.json();
    assert.equal(deniedBody.result.isError, true);
  } finally {
    await s.close();
  }
});

test('OAuth: a wrong verifier, code reuse and a revoked token are rejected', async () => {
  const s = await startOAuthServer();
  try {
    const { clientId, redirectUri } = await register(s.base);
    const { verifier, challenge } = pkce();
    const code = await authorize(s.base, clientId, redirectUri, challenge, 'meos.profile.read');

    const wrong = await exchange(s.base, clientId, redirectUri, code, randomBytes(48).toString('base64url'));
    assert.equal(wrong.status, 400);
    assert.equal(wrong.body.error, 'invalid_grant');

    const good = await exchange(s.base, clientId, redirectUri, code, verifier);
    assert.equal(good.status, 200);

    const replay = await exchange(s.base, clientId, redirectUri, code, verifier);
    assert.equal(replay.status, 400);

    const revoke = await fetch(`${s.base}/oauth/revoke`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form({ token: good.body.access_token })
    });
    assert.equal(revoke.status, 200);

    const after = await fetch(`${s.base}/mcp`, {
      method: 'POST',
      headers: mcpHeaders(good.body.access_token),
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} })
    });
    assert.equal(after.status, 401);
    assert.match(after.headers.get('www-authenticate') ?? '', /resource_metadata/);
  } finally {
    await s.close();
  }
});

test('OAuth: refresh rotation and reuse detection revokes the family', async () => {
  const s = await startOAuthServer();
  try {
    const { clientId, redirectUri } = await register(s.base);
    const { verifier, challenge } = pkce();
    const code = await authorize(s.base, clientId, redirectUri, challenge, 'meos.profile.read');
    const first = await exchange(s.base, clientId, redirectUri, code, verifier);
    assert.equal(first.status, 200);

    const rotated = await fetch(`${s.base}/oauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form({
        grant_type: 'refresh_token',
        client_id: clientId,
        refresh_token: first.body.refresh_token,
        resource: `${s.base}/mcp`
      })
    });
    assert.equal(rotated.status, 200);
    const second: any = await rotated.json();

    // Reusing the old refresh token is theft: the family is revoked.
    const reuse = await fetch(`${s.base}/oauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form({
        grant_type: 'refresh_token',
        client_id: clientId,
        refresh_token: first.body.refresh_token,
        resource: `${s.base}/mcp`
      })
    });
    assert.equal(reuse.status, 400);

    const after = await fetch(`${s.base}/mcp`, {
      method: 'POST',
      headers: mcpHeaders(second.access_token),
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} })
    });
    assert.equal(after.status, 401);
  } finally {
    await s.close();
  }
});

test('OAuth: admin login, dashboard and immediate client revocation', async () => {
  const s = await startOAuthServer();
  try {
    const { clientId } = await register(s.base);
    const loginPage = await fetch(`${s.base}/admin`);
    assert.equal(loginPage.status, 200);
    const html = await loginPage.text();
    const csrf = /name="csrf" value="([^"]+)"/.exec(html)?.[1];
    const csrfCookie = loginPage.headers.getSetCookie().find((c) => c.startsWith('meos_mcp_admin_csrf='));
    assert.ok(csrf && csrfCookie);

    const login = await fetch(`${s.base}/admin/login`, {
      method: 'POST',
      redirect: 'manual',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Cookie: csrfCookie!.split(';')[0]!
      },
      body: form({ csrf: csrf!, password: 'test-admin-password-123' })
    });
    assert.equal(login.status, 303, await login.text());
    const sessionCookie = login.headers.getSetCookie().find((c) => c.startsWith('meos_mcp_admin='));
    assert.ok(sessionCookie);

    const dashboard = await fetch(`${s.base}/admin`, { headers: { Cookie: sessionCookie!.split(';')[0]! } });
    assert.equal(dashboard.status, 200);
    const dashboardHtml = await dashboard.text();
    assert.match(dashboardHtml, /Test ChatGPT/);

    const api = await fetch(`${s.base}/admin/api/clients`, {
      headers: { Cookie: sessionCookie!.split(';')[0]! }
    });
    assert.equal(api.status, 200);
    const clients: any = await api.json();
    assert.ok(clients.clients.some((c: any) => c.clientId === clientId));

    const revoke = await fetch(`${s.base}/admin/revoke`, {
      method: 'POST',
      redirect: 'manual',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Cookie: sessionCookie!.split(';')[0]!
      },
      body: form({ client_id: clientId, csrf: /name="csrf" value="([^"]+)"/.exec(dashboardHtml)![1]! })
    });
    assert.equal(revoke.status, 303);

    const apiAfter = await fetch(`${s.base}/admin/api/clients`, {
      headers: { Cookie: sessionCookie!.split(';')[0]! }
    });
    const after: any = await apiAfter.json();
    assert.equal(after.clients.some((c: any) => c.clientId === clientId), false);
  } finally {
    await s.close();
  }
});

test('OAuth: unsafe registration redirect URIs are refused', async () => {
  const s = await startOAuthServer();
  try {
    for (const uri of ['javascript:alert(1)', 'http://evil.example/cb', 'https://ok.example/cb#frag']) {
      const res = await fetch(`${s.base}/oauth/register`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ client_name: 'bad', redirect_uris: [uri] })
      });
      assert.equal(res.status, 400, uri);
    }
  } finally {
    await s.close();
  }
});
