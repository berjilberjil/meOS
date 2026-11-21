import { randomBytes, timingSafeEqual } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { OAuthConfig } from '../config/types.ts';
import { OAuthStore } from './store.ts';
import type { AuditLog } from '../services/audit.ts';
import { describeScopes } from '../auth/scopes.ts';
import { adminPasswordMatches, clientIp, errorPage, htmlEscape, readBody, sendHtml, sendJson } from './routes.ts';

interface AdminDeps {
  config: OAuthConfig;
  store: OAuthStore;
  audit: AuditLog;
  rateLimit: (key: string, max: number, windowMs: number) => void;
}

interface AdminSession {
  expiresAt: number;
  csrf: string;
}

const sessions = new Map<string, AdminSession>();
const ADMIN_TTL_MS = 60 * 60 * 1000;
const CSRF_COOKIE = 'meos_mcp_admin_csrf';
const SESSION_COOKIE = 'meos_mcp_admin';

function now(): number {
  return Date.now();
}

function parseCookies(req: IncomingMessage): Record<string, string> {
  const raw = req.headers.cookie ?? '';
  const out: Record<string, string> = {};
  for (const part of raw.split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (!k) continue;
    out[k] = decodeURIComponent(v.join('='));
  }
  return out;
}

function cookie(name: string, value: string, maxAgeSeconds: number, secure: boolean): string {
  return `${name}=${encodeURIComponent(value)}; Path=/admin; HttpOnly; SameSite=Strict; Max-Age=${maxAgeSeconds}${
    secure ? '; Secure' : ''
  }`;
}

function clearCookie(name: string, secure: boolean): string {
  return `${name}=; Path=/admin; HttpOnly; SameSite=Strict; Max-Age=0${secure ? '; Secure' : ''}`;
}

function adminSession(req: IncomingMessage): AdminSession | null {
  const token = parseCookies(req)[SESSION_COOKIE];
  if (!token) return null;
  const session = sessions.get(token);
  if (!session || session.expiresAt <= now()) {
    if (token) sessions.delete(token);
    return null;
  }
  return session;
}

function isSecure(req: IncomingMessage): boolean {
  const forwarded = req.headers['x-forwarded-proto'];
  const proto = Array.isArray(forwarded) ? forwarded[0] : forwarded;
  return Boolean((req.socket as { encrypted?: boolean }).encrypted) || proto === 'https';
}

function proxied(req: IncomingMessage): boolean {
  return Boolean(req.headers['cf-connecting-ip'] || req.headers['x-forwarded-for'] || req.headers['x-real-ip']);
}

function csrfMatches(req: IncomingMessage, submitted: string): boolean {
  const expected = parseCookies(req)[CSRF_COOKIE] ?? '';
  if (!expected || !submitted) return false;
  const a = Buffer.from(expected);
  const b = Buffer.from(submitted);
  return a.length === b.length && timingSafeEqual(a, b);
}

/** The dashboard's own CSRF token lives in the server-side admin session. */
function sessionCsrfMatches(session: AdminSession | null, submitted: string): boolean {
  if (!session || !submitted) return false;
  const a = Buffer.from(session.csrf);
  const b = Buffer.from(submitted);
  return a.length === b.length && timingSafeEqual(a, b);
}

function loginPage(csrf: string, error?: string): string {
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MeOS MCP admin</title><style>
:root{color-scheme:dark}body{font:16px/1.5 -apple-system,system-ui,sans-serif;background:#0b0b0f;color:#ececf2;margin:0}
main{max-width:26rem;margin:14vh auto;padding:0 1.2rem}h1{font-size:1.5rem}p{color:#a7a7b4}
input{width:100%;padding:.8rem;border-radius:10px;border:1px solid #33333f;background:#0e0e14;color:#fff}
button{margin-top:.8rem;width:100%;padding:.8rem;border-radius:10px;border:0;background:#f4f4f7;color:#111;font-weight:700;cursor:pointer}
.err{color:#f5b45a}.note{font-size:.9rem}
</style></head><body><main><h1>MeOS MCP admin</h1>
<p class="note">This page is served by the local MCP gateway, not the MeOS backend. It lists AI clients, their scopes and recent tool calls. Use <code>ssh -L 8788:127.0.0.1:8788</code> if you are not on the machine.</p>
${error ? `<p class="err">${htmlEscape(error)}</p>` : ''}
<form method="post" action="/admin/login">
<input type="hidden" name="csrf" value="${htmlEscape(csrf)}">
<input type="password" name="password" placeholder="MCP admin password" autocomplete="current-password" required>
<button>Unlock</button></form></main></body></html>`;
}

function dashboardPage(input: {
  clients: Array<{
    clientId: string;
    clientName: string;
    redirectUris: string[];
    activeScopes: string[];
    tokenCounts: { access: number; refresh: number };
    createdAt: string;
    lastUsedAt?: string;
  }>;
  auditRows: Array<{ ts: string; event: string; client?: string; tool?: string; outcome?: string }>;
  csrf: string;
}): string {
  const clientRows = input.clients
    .map((c) => {
      const scopes = c.activeScopes;
      const connected = c.tokenCounts.access + c.tokenCounts.refresh > 0;
      return `<tr>
<td><b>${htmlEscape(c.clientName)}</b><br><small class="mono">${htmlEscape(c.clientId)}</small><br><small class="mono">${c.redirectUris
        .map(htmlEscape)
        .join('<br>')}</small></td>
<td>${connected ? '<span class="on">Connected</span>' : '<span class="off">No live token</span>'}<br><small>${c.tokenCounts.access} access · ${c.tokenCounts.refresh} refresh</small></td>
<td>${scopes.length ? scopes.map((s) => `<code>${htmlEscape(s)}</code>`).join(' ') : '<span class="off">none</span>'}</td>
<td><small>${htmlEscape(c.createdAt.slice(0, 16))}<br>${htmlEscape(c.lastUsedAt?.slice(0, 16) ?? 'never')}</small></td>
<td><form method="post" action="/admin/revoke">
<input type="hidden" name="csrf" value="${htmlEscape(input.csrf)}">
<input type="hidden" name="client_id" value="${htmlEscape(c.clientId)}">
<button class="danger">Disconnect</button></form></td>
</tr>`;
    })
    .join('');

  const auditRows = input.auditRows
    .map(
      (r) => `<tr><td><small>${htmlEscape(r.ts.slice(0, 19))}</small></td><td>${htmlEscape(r.event)}</td><td><small>${htmlEscape(
        r.client ?? ''
      )}</small></td><td>${htmlEscape(r.tool ?? '')}</td><td>${htmlEscape(r.outcome ?? '')}</td></tr>`
    )
    .join('');

  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MeOS MCP clients</title><style>
:root{color-scheme:dark}body{font:15px/1.5 -apple-system,system-ui,sans-serif;background:#0b0b0f;color:#ececf2;margin:0}
main{max-width:72rem;margin:4vh auto;padding:0 1.2rem}h1{font-size:1.5rem;margin:0}h2{font-size:1.05rem;margin:2rem 0 .6rem}
p{color:#a7a7b4}table{width:100%;border-collapse:collapse;background:#15151d;border:1px solid #262632;border-radius:12px;overflow:hidden}
th,td{text-align:left;padding:.7rem;border-bottom:1px solid #23232e;vertical-align:top}th{color:#c9c9d6;font-size:.8rem;text-transform:uppercase;letter-spacing:.04em}
code{background:#20202a;border-radius:5px;padding:.1rem .3rem;font-size:.78rem}.mono{font-family:ui-monospace,monospace}
.on{color:#64d38a;font-weight:700}.off{color:#8b8b99}.danger{background:#3a1b22;color:#ff9aa8;border:1px solid #5c2a35;border-radius:8px;padding:.45rem .6rem;cursor:pointer}
.row{display:flex;justify-content:space-between;align-items:center;gap:1rem}.note{font-size:.9rem}
</style></head><body><main>
<div class="row"><div><h1>MeOS MCP clients</h1><p class="note">Local gateway · consent, scopes and audit. No data payloads are shown or logged.</p></div>
<form method="post" action="/admin/logout"><input type="hidden" name="csrf" value="${htmlEscape(input.csrf)}"><button class="danger">Lock</button></form></div>
<h2>Connected AI clients</h2>
${
  input.clients.length
    ? `<table><thead><tr><th>Client</th><th>Status</th><th>Granted scopes</th><th>Created / last use</th><th></th></tr></thead><tbody>${clientRows}</tbody></table>`
    : '<p>No clients yet. Connect ChatGPT or another MCP client; it will register and ask for consent.</p>'
}
<h2>Recent gateway activity</h2>
${
  input.auditRows.length
    ? `<table><thead><tr><th>Time</th><th>Event</th><th>Client</th><th>Tool</th><th>Outcome</th></tr></thead><tbody>${auditRows}</tbody></table>`
    : '<p>No activity recorded yet.</p>'
}
</main></body></html>`;
}

function issueAdminSession(): { token: string; csrf: string } {
  const token = randomBytes(32).toString('base64url');
  const csrf = randomBytes(24).toString('base64url');
  sessions.set(token, { expiresAt: now() + ADMIN_TTL_MS, csrf });
  // Bound memory if someone hammers the login endpoint.
  if (sessions.size > 20) {
    const oldest = [...sessions.entries()].sort((a, b) => a[1].expiresAt - b[1].expiresAt)[0];
    if (oldest) sessions.delete(oldest[0]);
  }
  return { token, csrf };
}

export async function handleAdminRequest(
  req: IncomingMessage,
  res: ServerResponse,
  url: URL,
  deps: AdminDeps
): Promise<boolean> {
  const { config, store, audit } = deps;
  const method = (req.method ?? 'GET').toUpperCase();
  // The admin page is normally opened over http://127.0.0.1 even when the
  // public tunnel is HTTPS. Decide the cookie's Secure flag from the actual
  // request, not the public issuer, or the browser drops the session cookie.
  const secure = isSecure(req);

  if (!url.pathname.startsWith('/admin')) return false;

  if (config.adminLocalOnly && proxied(req)) {
    errorPage(
      res,
      403,
      'Admin is local-only',
      'This gateway is reachable through a proxy, so the admin page is refused. Use SSH port-forwarding (ssh -L 8788:127.0.0.1:8788) or set MEOS_MCP_ADMIN_LOCAL_ONLY=false deliberately.'
    );
    return true;
  }

  if (url.pathname === '/admin' && method === 'GET') {
    const session = adminSession(req);
    if (session) {
      const clients = store.listClients().map((c) => {
        const granted = store.grantedScopes(c.clientId);
        const active = store.activeScopes(c.clientId);
        return {
          clientId: c.clientId,
          clientName: c.clientName,
          redirectUris: c.redirectUris,
          // Access tokens expire in 15 minutes; a live refresh token still means
          // the client can reconnect with the last consented grant.
          activeScopes: active.length ? active : granted,
          tokenCounts: store.tokenCounts(c.clientId),
          createdAt: c.createdAt,
          lastUsedAt: c.lastUsedAt
        };
      });
      sendHtml(res, 200, dashboardPage({ clients, auditRows: audit.recent(60), csrf: session.csrf }));
      return true;
    }
    const csrf = randomBytes(24).toString('base64url');
    res.setHeader('Set-Cookie', cookie(CSRF_COOKIE, csrf, 600, secure));
    sendHtml(res, 200, loginPage(csrf));
    return true;
  }

  if (url.pathname === '/admin/login' && method === 'POST') {
    deps.rateLimit(`admin-login:${clientIp(req)}`, 8, 60_000);
    let body = '';
    try {
      body = await readBody(req, 8 * 1024);
    } catch {
      errorPage(res, 413, 'Too large', 'The login request was too large.');
      return true;
    }
    const params = new URLSearchParams(body);
    const csrf = params.get('csrf') ?? '';
    const password = params.get('password') ?? '';
    if (!csrfMatches(req, csrf)) {
      errorPage(res, 400, 'Bad request', 'Reload the admin page and try again.');
      return true;
    }
    if (!adminPasswordMatches(password, config.adminPassword)) {
      audit.record({ event: 'admin_login', outcome: 'failure', ip: clientIp(req), userAgent: req.headers['user-agent'] });
      const fresh = randomBytes(24).toString('base64url');
      res.setHeader('Set-Cookie', cookie(CSRF_COOKIE, fresh, 600, secure));
      sendHtml(res, 401, loginPage(fresh, 'That password is not correct.'));
      return true;
    }
    const { token, csrf: sessionCsrf } = issueAdminSession();
    res.setHeader('Set-Cookie', [
      cookie(SESSION_COOKIE, token, Math.floor(ADMIN_TTL_MS / 1000), secure),
      clearCookie(CSRF_COOKIE, secure)
    ]);
    audit.record({ event: 'admin_login', outcome: 'success', ip: clientIp(req), userAgent: req.headers['user-agent'] });
    res.writeHead(303, { Location: '/admin', 'Cache-Control': 'no-store' });
    res.end();
    return true;
  }

  if (url.pathname === '/admin/logout' && method === 'POST') {
    const session = adminSession(req);
    let body = '';
    try {
      body = await readBody(req, 4 * 1024);
    } catch {
      /* ignore */
    }
    const csrf = new URLSearchParams(body).get('csrf') ?? '';
    if (!sessionCsrfMatches(session, csrf)) {
      errorPage(res, 403, 'Not allowed', 'Reload the admin page.');
      return true;
    }
    const token = parseCookies(req)[SESSION_COOKIE];
    if (token) sessions.delete(token);
    res.setHeader('Set-Cookie', [clearCookie(SESSION_COOKIE, secure), clearCookie(CSRF_COOKIE, secure)]);
    res.writeHead(303, { Location: '/admin', 'Cache-Control': 'no-store' });
    res.end();
    return true;
  }

  if (url.pathname === '/admin/revoke' && method === 'POST') {
    const session = adminSession(req);
    let body = '';
    try {
      body = await readBody(req, 8 * 1024);
    } catch {
      errorPage(res, 413, 'Too large', 'The request was too large.');
      return true;
    }
    const params = new URLSearchParams(body);
    if (!sessionCsrfMatches(session, params.get('csrf') ?? '')) {
      errorPage(res, 403, 'Not allowed', 'Reload the admin page.');
      return true;
    }
    const clientId = params.get('client_id') ?? '';
    const revoked = store.revokeClient(clientId);
    audit.record({
      event: 'oauth_client_revoke',
      outcome: revoked ? 'success' : 'failure',
      client: clientId,
      ip: clientIp(req),
      userAgent: req.headers['user-agent']
    });
    res.writeHead(303, { Location: '/admin', 'Cache-Control': 'no-store' });
    res.end();
    return true;
  }

  if (url.pathname === '/admin/api/clients' && method === 'GET') {
    const session = adminSession(req);
    if (!session) {
      sendJson(res, 401, { error: 'unauthorized' });
      return true;
    }
    sendJson(res, 200, {
      clients: store.listClients().map((c) => ({
        ...c,
        activeScopes: store.activeScopes(c.clientId),
        tokenCounts: store.tokenCounts(c.clientId),
        grantedScopes: store.grantedScopes(c.clientId),
        scopeDescriptions: describeScopes(store.grantedScopes(c.clientId))
      }))
    });
    return true;
  }

  if (url.pathname === '/admin/api/audit' && method === 'GET') {
    const session = adminSession(req);
    if (!session) {
      sendJson(res, 401, { error: 'unauthorized' });
      return true;
    }
    sendJson(res, 200, { events: audit.recent(200) });
    return true;
  }

  errorPage(res, 404, 'Not found', 'Unknown admin route.');
  return true;
}
