import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { OAuthConfig } from '../config/types.ts';
import {
  ALL_SCOPES,
  GRANULAR_SCOPES,
  SCOPE_DESCRIPTIONS,
  isGranularScope,
  type Scope
} from '../auth/scopes.ts';
import { OAuthStore, isValidRedirectUri } from './store.ts';
import type { AuditLog } from '../services/audit.ts';

interface PendingAuthorization {
  id: string;
  csrf: string;
  clientId: string;
  clientName: string;
  redirectUri: string;
  state: string;
  scope: string[];
  resource: string;
  codeChallenge: string;
  createdAt: number;
}

interface Deps {
  config: OAuthConfig;
  store: OAuthStore;
  audit: AuditLog;
  rateLimit: (key: string, max: number, windowMs: number) => void;
}

const PENDING_TTL_MS = 10 * 60 * 1000;
const pending = new Map<string, PendingAuthorization>();

function htmlEscape(value: string): string {
  return value.replace(/[&<>"']/g, (c) =>
    c === '&' ? '&amp;' : c === '<' ? '&lt;' : c === '>' ? '&gt;' : c === '"' ? '&quot;' : '&#39;'
  );
}

function sendJson(res: ServerResponse, status: number, body: unknown): void {
  const text = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(text),
    'Cache-Control': 'no-store',
    Pragma: 'no-cache',
    'X-Content-Type-Options': 'nosniff',
    'X-Robots-Tag': 'noindex, nofollow',
    'Referrer-Policy': 'no-referrer'
  });
  res.end(text);
}

function sendHtml(res: ServerResponse, status: number, html: string): void {
  res.writeHead(status, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
    Pragma: 'no-cache',
    'Content-Security-Policy':
      "default-src 'none'; style-src 'unsafe-inline'; img-src 'none'; script-src 'none'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
    'X-Frame-Options': 'DENY',
    'X-Content-Type-Options': 'nosniff',
    'X-Robots-Tag': 'noindex, nofollow',
    'Referrer-Policy': 'no-referrer',
    'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=()'
  });
  res.end(html);
}

function errorPage(res: ServerResponse, status: number, title: string, detail: string): void {
  sendHtml(
    res,
    status,
    `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${htmlEscape(
      title
    )}</title><style>body{font:16px/1.5 -apple-system,system-ui,sans-serif;max-width:38rem;margin:12vh auto;padding:0 1.2rem;color:#e8e8ee;background:#0b0b0f}h1{font-size:1.5rem}p{color:#a7a7b4}code{background:#1b1b23;padding:.15rem .35rem;border-radius:.3rem}</style></head><body><h1>${htmlEscape(
      title
    )}</h1><p>${htmlEscape(detail)}</p></body></html>`
  );
}

function readBody(req: IncomingMessage, maxBytes = 32 * 1024): Promise<string> {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks: Buffer[] = [];
    req.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > maxBytes) {
        reject(new Error('too_large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', () => reject(new Error('read_failed')));
  });
}

function formValue(params: URLSearchParams, key: string, max = 512): string {
  const value = params.get(key) ?? '';
  return value.length > max ? '' : value;
}

function adminMatches(input: string, expected: string): boolean {
  const a = Buffer.from(input);
  const b = Buffer.from(expected);
  return a.length === b.length && a.length > 0 && timingSafeEqual(a, b);
}

function clientIp(req: IncomingMessage): string {
  const header = req.headers['cf-connecting-ip'] ?? req.headers['x-forwarded-for'] ?? req.socket.remoteAddress;
  if (Array.isArray(header)) return header[0] ?? 'unknown';
  return String(header ?? 'unknown').split(',')[0]!.trim();
}

function isLocalRequest(req: IncomingMessage): boolean {
  const remote = req.socket.remoteAddress ?? '';
  return remote === '127.0.0.1' || remote === '::1' || remote === '::ffff:127.0.0.1';
}

function requestIsProxied(req: IncomingMessage): boolean {
  return Boolean(req.headers['cf-connecting-ip'] || req.headers['x-forwarded-for'] || req.headers['x-real-ip']);
}

function cleanupPending(): void {
  const cutoff = Date.now() - PENDING_TTL_MS;
  for (const [id, p] of pending) {
    if (p.createdAt < cutoff) pending.delete(id);
  }
  while (pending.size > 100) {
    const first = pending.keys().next().value;
    if (!first) break;
    pending.delete(first);
  }
}

function supportedScopes(): Scope[] {
  return [...GRANULAR_SCOPES, 'offline_access', 'secret', 'destructive'];
}

function normalizeSelected(raw: string[]): Scope[] {
  const out = new Set<Scope>();
  for (const value of raw) {
    if (!(ALL_SCOPES as readonly string[]).includes(value)) continue;
    const scope = value as Scope;
    if (!supportedScopes().includes(scope)) continue;
    out.add(scope);
    if (isGranularScope(scope) && scope.endsWith('.write')) {
      out.add(scope.replace(/\.write$/, '.read') as Scope);
    }
  }
  return [...out];
}

function scopeCheckbox(scope: Scope, checked: boolean, disabled = false): string {
  const label =
    isGranularScope(scope) ? SCOPE_DESCRIPTIONS[scope] : scope === 'secret'
      ? 'Locked notes and private profile fields'
      : scope === 'destructive'
        ? 'Deletes and purges (also requires confirm)'
        : scope === 'offline_access'
          ? 'Keep access while the assistant is not actively open'
          : '';
  return `<label class="scope"><input type="checkbox" name="scope" value="${htmlEscape(scope)}"${
    checked ? ' checked' : ''
  }${disabled ? ' disabled' : ''}><span><b>${htmlEscape(scope)}</b><br><small>${htmlEscape(label)}</small></span></label>`;
}

function consentPage(pendingAuth: PendingAuthorization, requested: string[]): string {
  const rows = [
    ...GRANULAR_SCOPES.filter((s) => s.endsWith('.read')),
    ...GRANULAR_SCOPES.filter((s) => s.endsWith('.write')),
    'secret' as Scope,
    'destructive' as Scope,
    'offline_access' as Scope
  ]
    .map((scope) => {
      const checked = scope === 'meos.profile.read' || scope === 'offline_access';
      return scopeCheckbox(scope, checked);
    })
    .join('');

  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Authorize ${htmlEscape(
    pendingAuth.clientName
  )}</title><style>
:root{color-scheme:dark}*{box-sizing:border-box}body{font:16px/1.5 -apple-system,system-ui,sans-serif;margin:0;background:#0b0b0f;color:#ececf2}
main{max-width:44rem;margin:6vh auto;padding:0 1.2rem}h1{font-size:1.6rem;margin:0 0 .4rem}h2{font-size:1rem;margin:1.6rem 0 .6rem;color:#c9c9d6}
p{color:#a7a7b4}.card{background:#15151d;border:1px solid #262632;border-radius:14px;padding:1rem;margin:1rem 0}
.scope{display:flex;gap:.7rem;align-items:flex-start;padding:.45rem 0;border-bottom:1px solid #20202a}.scope:last-child{border:0}
input[type=checkbox]{margin-top:.25rem}input[type=password]{width:100%;padding:.7rem;border-radius:10px;border:1px solid #33333f;background:#0e0e14;color:#fff}
button{padding:.8rem 1.1rem;border-radius:10px;border:0;font-weight:700;cursor:pointer}.allow{background:#f4f4f7;color:#111}.deny{background:#2a2a35;color:#eee}
.row{display:flex;gap:.6rem;justify-content:flex-end;margin-top:1rem}.warn{color:#f5b45a}.mono{font-family:ui-monospace,monospace;font-size:.85rem;word-break:break-all}
</style></head><body><main>
<h1>Authorize ${htmlEscape(pendingAuth.clientName)}</h1>
<p>This AI client wants to read from your private MeOS vault. It will receive only the modules you tick below, through the tools those scopes allow.</p>
<div class="card"><b>Client</b><br>${htmlEscape(pendingAuth.clientName)}<br><small class="mono">${htmlEscape(
    pendingAuth.clientId
  )}</small><br><b>Redirect</b><br><small class="mono">${htmlEscape(pendingAuth.redirectUri)}</small></div>
${
  requested.length
    ? `<p><b>Requested by the client:</b> <span class="mono">${htmlEscape(requested.join(' '))}</span></p>`
    : ''
}
<form method="post" action="/oauth/authorize">
<input type="hidden" name="request_id" value="${htmlEscape(pendingAuth.id)}">
<input type="hidden" name="csrf" value="${htmlEscape(pendingAuth.csrf)}">
<h2>Data access</h2>
<div class="card">${rows}</div>
<h2>Confirm</h2>
<div class="card">
<p>Enter the MeOS MCP admin password to approve. This is not your MeOS login or vault passphrase.</p>
<input type="password" name="admin_password" autocomplete="current-password" required>
<p class="warn">Only approve a client you started configuring. The assistant will see the data it requests; MeOS cannot make a third-party AI provider unsee it.</p>
</div>
<div class="row"><button class="deny" name="decision" value="deny" formnovalidate>Deny</button><button class="allow" name="decision" value="allow">Allow selected</button></div>
</form></main></body></html>`;
}

function redirectWith(res: ServerResponse, uri: string, params: Record<string, string>): true {
  const url = new URL(uri);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  res.writeHead(302, {
    Location: url.toString(),
    'Cache-Control': 'no-store',
    'Referrer-Policy': 'no-referrer'
  });
  res.end();
  return true;
}

/**
 * Handle OAuth + metadata + admin. Returns true when the request was handled.
 * The caller has already ensured the request is not /mcp.
 */
export async function handleOAuthRequest(
  req: IncomingMessage,
  res: ServerResponse,
  url: URL,
  deps: Deps
): Promise<boolean> {
  const { config, store, audit } = deps;
  const method = (req.method ?? 'GET').toUpperCase();

  if (url.pathname === '/.well-known/oauth-protected-resource' ||
      url.pathname === '/.well-known/oauth-protected-resource/mcp') {
    if (method !== 'GET') {
      sendJson(res, 405, { error: 'method_not_allowed' });
      return true;
    }
    sendJson(res, 200, {
      resource: config.resource,
      authorization_servers: [config.issuer],
      scopes_supported: supportedScopes(),
      bearer_methods_supported: ['header']
    });
    return true;
  }

  if (url.pathname === '/.well-known/oauth-authorization-server' ||
      url.pathname === '/.well-known/oauth-authorization-server/mcp') {
    if (method !== 'GET') {
      sendJson(res, 405, { error: 'method_not_allowed' });
      return true;
    }
    sendJson(res, 200, {
      issuer: config.issuer,
      authorization_endpoint: `${config.issuer}/oauth/authorize`,
      token_endpoint: `${config.issuer}/oauth/token`,
      registration_endpoint: config.allowDynamicClientRegistration ? `${config.issuer}/oauth/register` : undefined,
      revocation_endpoint: `${config.issuer}/oauth/revoke`,
      scopes_supported: supportedScopes(),
      response_types_supported: ['code'],
      response_modes_supported: ['query'],
      grant_types_supported: ['authorization_code', 'refresh_token'],
      token_endpoint_auth_methods_supported: ['none'],
      code_challenge_methods_supported: ['S256']
    });
    return true;
  }

  if (url.pathname === '/oauth/authorize') {
    if (method === 'GET') return authorizeGet(req, res, url, deps);
    if (method === 'POST') return authorizePost(req, res, deps);
    sendJson(res, 405, { error: 'method_not_allowed' });
    return true;
  }

  if (url.pathname === '/oauth/token') {
    if (method !== 'POST') {
      sendJson(res, 405, { error: 'method_not_allowed' });
      return true;
    }
    return token(req, res, deps);
  }

  if (url.pathname === '/oauth/revoke') {
    if (method !== 'POST') {
      sendJson(res, 405, { error: 'method_not_allowed' });
      return true;
    }
    return revoke(req, res, deps);
  }

  if (url.pathname === '/oauth/register') {
    if (method !== 'POST') {
      sendJson(res, 405, { error: 'method_not_allowed' });
      return true;
    }
    return register(req, res, deps);
  }

  if (url.pathname === '/admin' || url.pathname.startsWith('/admin/')) {
    // Admin is served by admin.ts; returning false lets the caller route it.
    return false;
  }

  return false;
}

async function authorizeGet(req: IncomingMessage, res: ServerResponse, url: URL, deps: Deps): Promise<boolean> {
  const { config, store, audit } = deps;
  deps.rateLimit(`oauth-authorize:${clientIp(req)}`, 30, 60_000);

  const clientId = formValue(url.searchParams, 'client_id', 128);
  const redirectUri = formValue(url.searchParams, 'redirect_uri', 2_000);
  const responseType = formValue(url.searchParams, 'response_type', 40);
  const state = formValue(url.searchParams, 'state', 1_000);
  const challenge = formValue(url.searchParams, 'code_challenge', 200);
  const challengeMethod = formValue(url.searchParams, 'code_challenge_method', 10);
  const resource = formValue(url.searchParams, 'resource', 2_000) || config.resource;
  const rawScope = formValue(url.searchParams, 'scope', 2_000);

  const client = store.getClient(clientId);
  if (!client) {
    errorPage(res, 400, 'Unknown client', 'This client is not registered, or its access was revoked. Register it again in ChatGPT.');
    audit.record({ event: 'oauth_authorize', outcome: 'denied', ip: clientIp(req), userAgent: req.headers['user-agent'], meta: { reason: 'unknown_client' } });
    return true;
  }
  if (!client.redirectUris.includes(redirectUri) || !isValidRedirectUri(redirectUri)) {
    errorPage(res, 400, 'Invalid redirect', 'The redirect URI does not exactly match the one registered for this client.');
    audit.record({ event: 'oauth_authorize', outcome: 'denied', client: clientId, ip: clientIp(req), meta: { reason: 'redirect_mismatch' } });
    return true;
  }
  if (responseType !== 'code') {
    return redirectWith(res, redirectUri, { error: 'unsupported_response_type', state });
  }
  if (challengeMethod !== 'S256' || !/^[A-Za-z0-9\-._~]{43,128}$/.test(challenge)) {
    return redirectWith(res, redirectUri, { error: 'invalid_request', error_description: 'PKCE S256 is required', state });
  }
  if (resource !== config.resource) {
    return redirectWith(res, redirectUri, { error: 'invalid_target', state });
  }

  // Ignore scopes we do not implement (`openid`, `email`, …) rather than
  // failing the whole authorization. We never grant an unsupported scope.
  const requested = (rawScope || 'meos.profile.read')
    .split(/\s+/)
    .map((s) => s.trim())
    .filter((s): s is Scope => (supportedScopes() as string[]).includes(s));

  cleanupPending();
  const id = `apr_${randomBytes(18).toString('base64url')}`;
  const pendingAuth: PendingAuthorization = {
    id,
    csrf: randomBytes(24).toString('base64url'),
    clientId: client.clientId,
    clientName: client.clientName,
    redirectUri,
    state,
    scope: requested,
    resource,
    codeChallenge: challenge,
    createdAt: Date.now()
  };
  pending.set(id, pendingAuth);

  sendHtml(res, 200, consentPage(pendingAuth, requested));
  audit.record({
    event: 'oauth_authorize_shown',
    client: clientId,
    ip: clientIp(req),
    userAgent: req.headers['user-agent'],
    meta: { scopes: requested.length }
  });
  return true;
}

async function authorizePost(req: IncomingMessage, res: ServerResponse, deps: Deps): Promise<boolean> {
  const { config, store, audit } = deps;
  deps.rateLimit(`oauth-authorize-post:${clientIp(req)}`, 20, 60_000);

  let body: string;
  try {
    body = await readBody(req, 64 * 1024);
  } catch {
    errorPage(res, 413, 'Request too large', 'The consent form was too large.');
    return true;
  }
  const params = new URLSearchParams(body);
  const id = formValue(params, 'request_id', 128);
  const csrf = formValue(params, 'csrf', 128);
  const decision = formValue(params, 'decision', 20);
  const adminPassword = formValue(params, 'admin_password', 256);
  const request = pending.get(id);

  if (!request || request.csrf !== csrf) {
    errorPage(res, 400, 'Expired request', 'This authorization request is no longer valid. Start again from your AI client.');
    return true;
  }

  if (decision === 'deny') {
    pending.delete(id);
    audit.record({ event: 'oauth_authorize', outcome: 'denied', client: request.clientId, ip: clientIp(req), meta: { reason: 'owner_denied' } });
    return redirectWith(res, request.redirectUri, { error: 'access_denied', state: request.state });
  }

  if (!adminMatches(adminPassword, config.adminPassword)) {
    audit.record({
      event: 'oauth_authorize',
      outcome: 'denied',
      client: request.clientId,
      ip: clientIp(req),
      meta: { reason: 'admin_password' }
    });
    // Do not destroy the pending request on a typo; let the owner retry.
    sendHtml(
      res,
      403,
      consentPage(request, request.scope).replace(
        '<div class="row">',
        '<div class="card"><b>That admin password was not correct.</b></div><div class="row">'
      )
    );
    return true;
  }

  const selected = normalizeSelected(params.getAll('scope'));
  if (!selected.length) {
    errorPage(res, 400, 'No access selected', 'Select at least one module, or press Deny.');
    return true;
  }

  pending.delete(id);
  const code = store.createCode({
    clientId: request.clientId,
    redirectUri: request.redirectUri,
    scope: selected.join(' '),
    accountId: store.getClient(request.clientId)?.accountId ?? 'owner',
    resource: request.resource,
    codeChallenge: request.codeChallenge
  });
  audit.record({
    event: 'oauth_authorize',
    outcome: 'success',
    client: request.clientId,
    ip: clientIp(req),
    userAgent: req.headers['user-agent'],
    meta: { scopes: selected.length, has_write: selected.some((s) => s.endsWith('.write')) }
  });
  return redirectWith(res, request.redirectUri, {
    code,
    state: request.state,
    // RFC 9207 mix-up defence; harmless for clients that ignore it.
    iss: config.issuer
  });
}

async function token(req: IncomingMessage, res: ServerResponse, deps: Deps): Promise<boolean> {
  const { config, store, audit } = deps;
  deps.rateLimit(`oauth-token:${clientIp(req)}`, 60, 60_000);

  let body: string;
  try {
    body = await readBody(req, 32 * 1024);
  } catch {
    sendJson(res, 413, { error: 'invalid_request', error_description: 'The token request was too large.' });
    return true;
  }
  const params = new URLSearchParams(body);
  const grantType = formValue(params, 'grant_type', 40);
  const clientId = formValue(params, 'client_id', 128);
  const resource = formValue(params, 'resource', 2_000) || config.resource;
  if (resource !== config.resource) {
    sendJson(res, 400, { error: 'invalid_target' });
    return true;
  }
  if (!store.getClient(clientId)) {
    sendJson(res, 400, { error: 'invalid_client' });
    return true;
  }

  if (grantType === 'authorization_code') {
    const code = formValue(params, 'code', 512);
    const redirectUri = formValue(params, 'redirect_uri', 2_000);
    const verifier = formValue(params, 'code_verifier', 256);
    const taken = store.takeCode({ code, clientId, redirectUri, codeVerifier: verifier, resource });
    if (!taken) {
      audit.record({ event: 'oauth_token', outcome: 'failure', client: clientId, ip: clientIp(req), meta: { grant: 'authorization_code' } });
      sendJson(res, 400, { error: 'invalid_grant' });
      return true;
    }
    const issued = store.issueTokens({
      clientId,
      accountId: taken.accountId,
      scope: taken.scope,
      resource: taken.resource
    });
    audit.record({
      event: 'oauth_token',
      outcome: 'success',
      client: clientId,
      ip: clientIp(req),
      meta: { grant: 'authorization_code', scopes: taken.scope.split(' ').length }
    });
    sendJson(res, 200, {
      access_token: issued.accessToken,
      token_type: 'Bearer',
      expires_in: issued.expiresIn,
      refresh_token: issued.refreshToken,
      scope: issued.scope
    });
    return true;
  }

  if (grantType === 'refresh_token') {
    const refreshToken = formValue(params, 'refresh_token', 512);
    const rotated = store.rotateRefresh({ refreshToken, clientId, resource });
    if (rotated === 'reused') {
      audit.record({ event: 'oauth_refresh_reuse', outcome: 'denied', client: clientId, ip: clientIp(req) });
      sendJson(res, 400, { error: 'invalid_grant' });
      return true;
    }
    if (rotated === 'invalid') {
      sendJson(res, 400, { error: 'invalid_grant' });
      return true;
    }
    audit.record({ event: 'oauth_token', outcome: 'success', client: clientId, ip: clientIp(req), meta: { grant: 'refresh_token' } });
    sendJson(res, 200, {
      access_token: rotated.accessToken,
      token_type: 'Bearer',
      expires_in: rotated.expiresIn,
      refresh_token: rotated.refreshToken,
      scope: rotated.scope
    });
    return true;
  }

  sendJson(res, 400, { error: 'unsupported_grant_type' });
  return true;
}

async function revoke(req: IncomingMessage, res: ServerResponse, deps: Deps): Promise<boolean> {
  deps.rateLimit(`oauth-revoke:${clientIp(req)}`, 30, 60_000);
  let body = '';
  try {
    body = await readBody(req, 16 * 1024);
  } catch {
    /* still return 200 */
  }
  const params = new URLSearchParams(body);
  const token = formValue(params, 'token', 1_000);
  if (token) {
    deps.store.revokeToken(token);
    deps.audit.record({ event: 'oauth_revoke', outcome: 'success', ip: clientIp(req) });
  }
  // RFC 7009: always 200, even for an unknown token, so callers cannot probe.
  res.writeHead(200, { 'Cache-Control': 'no-store' });
  res.end();
  return true;
}

async function register(req: IncomingMessage, res: ServerResponse, deps: Deps): Promise<boolean> {
  const { config, store, audit } = deps;
  if (!config.allowDynamicClientRegistration) {
    sendJson(res, 403, { error: 'registration_not_supported' });
    return true;
  }
  deps.rateLimit(`oauth-register:${clientIp(req)}`, 10, 60 * 60_000);

  let body: string;
  try {
    body = await readBody(req, 32 * 1024);
  } catch {
    sendJson(res, 413, { error: 'invalid_client_metadata' });
    return true;
  }
  let raw: unknown;
  try {
    raw = JSON.parse(body);
  } catch {
    sendJson(res, 400, { error: 'invalid_client_metadata', error_description: 'Body must be JSON' });
    return true;
  }
  const data = raw as Record<string, unknown>;
  const redirectUris = Array.isArray(data.redirect_uris)
    ? data.redirect_uris.map(String).filter(Boolean)
    : [];
  if (redirectUris.length < 1 || redirectUris.length > 5 || redirectUris.some((u) => !isValidRedirectUri(u))) {
    sendJson(res, 400, {
      error: 'invalid_redirect_uri',
      error_description: 'Use 1–5 exact https:// (or localhost http://) redirect URIs, no fragments.'
    });
    return true;
  }
  if (data.token_endpoint_auth_method && data.token_endpoint_auth_method !== 'none') {
    sendJson(res, 400, { error: 'invalid_client_metadata', error_description: 'Only public clients with PKCE are supported.' });
    return true;
  }
  if (data.grant_types && (!Array.isArray(data.grant_types) || data.grant_types.some((g) => !['authorization_code', 'refresh_token'].includes(String(g))))) {
    sendJson(res, 400, { error: 'invalid_client_metadata' });
    return true;
  }
  if (data.response_types && (!Array.isArray(data.response_types) || !data.response_types.includes('code'))) {
    sendJson(res, 400, { error: 'invalid_client_metadata' });
    return true;
  }
  let scope = 'meos.profile.read offline_access';
  if (typeof data.scope === 'string' && data.scope.trim()) {
    const parsed = data.scope
      .split(/\s+/)
      .map((s) => s.trim())
      .filter((s): s is Scope => (supportedScopes() as string[]).includes(s));
    scope = parsed.length ? [...new Set(parsed)].join(' ') : 'meos.profile.read';
  }

  try {
    const client = store.registerClient({
      clientName: typeof data.client_name === 'string' ? data.client_name : 'MCP client',
      redirectUris,
      scope,
      accountId: 'owner'
    });
    audit.record({
      event: 'oauth_register',
      outcome: 'success',
      client: client.clientId,
      ip: clientIp(req),
      userAgent: req.headers['user-agent'],
      meta: { redirects: redirectUris.length }
    });
    sendJson(res, 201, {
      client_id: client.clientId,
      client_id_issued_at: Math.floor(Date.parse(client.createdAt) / 1000),
      client_name: client.clientName,
      redirect_uris: client.redirectUris,
      grant_types: client.grantTypes,
      response_types: client.responseTypes,
      token_endpoint_auth_method: client.tokenEndpointAuthMethod,
      scope: client.scope
    });
  } catch (e) {
    sendJson(res, 400, { error: 'invalid_client_metadata', error_description: (e as Error).message });
  }
  return true;
}

/** Verify the admin password for the dashboard. */
export function adminPasswordMatches(input: string, expected: string): boolean {
  return adminMatches(input, expected);
}

export { clientIp, isLocalRequest, requestIsProxied, sendHtml, sendJson, htmlEscape, readBody, errorPage };
