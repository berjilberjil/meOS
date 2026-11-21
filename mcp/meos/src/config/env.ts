import { createHash, timingSafeEqual } from 'node:crypto';
import { parseScopes } from '../auth/scopes.ts';
import type { AccountConfig, ClientConfig, RuntimeConfig, TransportKind } from './types.ts';

export function hashToken(token: string): string {
  return createHash('sha256').update(token, 'utf8').digest('hex');
}

/** Constant-time compare of two SHA-256 hex digests. */
export function tokenHashMatches(candidateHash: string, expectedHash: string): boolean {
  const a = Buffer.from(candidateHash, 'hex');
  const b = Buffer.from(expectedHash, 'hex');
  return a.length === b.length && a.length > 0 && timingSafeEqual(a, b);
}

function requireEnv(env: NodeJS.ProcessEnv, key: string): string {
  const value = env[key]?.trim();
  if (!value) throw new Error(`${key} is required`);
  return value;
}

function parseUrl(raw: string, key: string): string {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new Error(`${key} must be a valid URL`);
  }
  const local = url.hostname === 'localhost' || url.hostname === '127.0.0.1' || url.hostname === '[::1]';
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && local)) {
    throw new Error(`${key} must use https:// (http:// is allowed only for localhost)`);
  }
  return url.toString().replace(/\/$/, '');
}

function oneLine(value: string, key: string): string {
  if (/[\r\n]/.test(value)) throw new Error(`${key} must not contain line breaks`);
  return value;
}

function parseJsonArray<T>(raw: string | undefined, key: string): T[] | null {
  if (!raw?.trim()) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error(`${key} must be valid JSON`);
  }
  if (!Array.isArray(parsed)) throw new Error(`${key} must be a JSON array`);
  return parsed as T[];
}

function parseAccounts(env: NodeJS.ProcessEnv): Map<string, AccountConfig> {
  const requestTimeoutMs = Number(env.MEOS_MCP_REQUEST_TIMEOUT_MS ?? '20000');
  if (!Number.isFinite(requestTimeoutMs) || requestTimeoutMs < 1000) {
    throw new Error('MEOS_MCP_REQUEST_TIMEOUT_MS must be at least 1000');
  }

  const baseUrl = parseUrl(env.MEOS_BASE_URL?.trim() || 'https://meos-api.berjiljacob.workers.dev', 'MEOS_BASE_URL');
  const owner: AccountConfig = {
    id: 'owner',
    baseUrl,
    username: oneLine(requireEnv(env, 'MEOS_USERNAME'), 'MEOS_USERNAME'),
    password: oneLine(requireEnv(env, 'MEOS_PASSWORD'), 'MEOS_PASSWORD'),
    vaultPassphrase: env.MEOS_VAULT_PASSPHRASE?.trim() || undefined,
    vaultRecovery: env.MEOS_VAULT_RECOVERY?.trim() || undefined,
    mfaSecret: env.MEOS_MFA_SECRET ? oneLine(env.MEOS_MFA_SECRET.trim(), 'MEOS_MFA_SECRET') : undefined,
    requestTimeoutMs
  };

  const accounts = new Map<string, AccountConfig>([['owner', owner]]);
  const raw = parseJsonArray<Record<string, unknown>>(env.MEOS_MCP_ACCOUNTS_JSON, 'MEOS_MCP_ACCOUNTS_JSON');
  for (const row of raw ?? []) {
    const id = String(row.id ?? '').trim();
    if (!id) throw new Error('Each MEOS_MCP_ACCOUNTS_JSON entry needs an id');
    if (accounts.has(id)) throw new Error(`Duplicate account id "${id}"`);
    accounts.set(id, {
      id,
      baseUrl: parseUrl(String(row.baseUrl ?? baseUrl), `account ${id} baseUrl`),
      username: oneLine(String(row.username ?? ''), `account ${id} username`),
      password: oneLine(String(row.password ?? ''), `account ${id} password`),
      vaultPassphrase: row.vaultPassphrase ? String(row.vaultPassphrase) : undefined,
      vaultRecovery: row.vaultRecovery ? String(row.vaultRecovery) : undefined,
      mfaSecret: row.mfaSecret ? String(row.mfaSecret) : undefined,
      requestTimeoutMs
    });
  }
  return accounts;
}

function parseClients(
  env: NodeJS.ProcessEnv,
  accounts: Map<string, AccountConfig>,
  transport: TransportKind,
  oauthEnabled = false
): Map<string, ClientConfig> {
  const clients = new Map<string, ClientConfig>();
  const raw = parseJsonArray<Record<string, unknown>>(env.MEOS_MCP_CLIENTS_JSON, 'MEOS_MCP_CLIENTS_JSON');

  const defaultScopes = parseScopes(env.MEOS_MCP_SCOPES ?? 'read');

  for (const row of raw ?? []) {
    const id = String(row.id ?? '').trim();
    if (!id) throw new Error('Each MEOS_MCP_CLIENTS_JSON entry needs an id');
    if (clients.has(id)) throw new Error(`Duplicate client id "${id}"`);
    const token = row.token ? String(row.token) : '';
    const sha = row.token_sha256 ? String(row.token_sha256).trim().toLowerCase() : '';
    if (!token && !sha) throw new Error(`Client "${id}" needs token or token_sha256`);
    if (sha && !/^[a-f0-9]{64}$/.test(sha)) throw new Error(`Client "${id}" token_sha256 must be 64 hex characters`);
    const accountId = String(row.account ?? 'owner').trim();
    if (!accounts.has(accountId)) throw new Error(`Client "${id}" references unknown account "${accountId}"`);
    const expiresAt = row.expires_at ? String(row.expires_at).trim() : undefined;
    if (expiresAt && !Number.isFinite(Date.parse(expiresAt))) {
      throw new Error(`Client "${id}" has an invalid expires_at (use an ISO-8601 instant)`);
    }
    clients.set(id, {
      id,
      tokenHash: sha || hashToken(token),
      scopes: row.scopes ? parseScopes(Array.isArray(row.scopes) ? row.scopes.join(',') : String(row.scopes)) : defaultScopes,
      accountId,
      expiresAt,
      authMethod: 'static'
    });
  }

  if (transport === 'stdio') {
    // stdio is already a local, user-launched pipe. No bearer token is involved;
    // the process environment is the authentication boundary.
    clients.set('stdio', {
      id: 'stdio',
      tokenHash: null,
      scopes: defaultScopes,
      accountId: 'owner',
      authMethod: 'stdio'
    });
  } else if (clients.size === 0) {
    const token = env.MEOS_MCP_HTTP_TOKEN?.trim();
    if (token) {
      clients.set('default', {
        id: 'default',
        tokenHash: hashToken(token),
        scopes: defaultScopes,
        accountId: 'owner',
        authMethod: 'static'
      });
    } else if (!oauthEnabled) {
      throw new Error(
        'HTTP transport refuses to start without credentials. Set MEOS_MCP_HTTP_TOKEN, MEOS_MCP_CLIENTS_JSON, or OAuth (MEOS_MCP_PUBLIC_URL + MEOS_MCP_ADMIN_PASSWORD).'
      );
    }
    // OAuth-only mode: no static token is required; every request must present
    // an access token issued through consent.
  }

  if (transport === 'stdio' && clients.size > 1) {
    // Extra tokens are simply unused on stdio; keep them for parity but make
    // clear that stdio still authenticates as the local client only.
  }

  // Two clients sharing a token would make scope selection depend on iteration
  // order. Refuse the configuration instead of guessing.
  const seenTokens = new Map<string, string>();
  for (const client of clients.values()) {
    if (!client.tokenHash) continue;
    const existing = seenTokens.get(client.tokenHash);
    if (existing) throw new Error(`Clients "${existing}" and "${client.id}" share the same bearer token`);
    seenTokens.set(client.tokenHash, client.id);
  }
  return clients;
}

function parseOAuth(env: NodeJS.ProcessEnv, path: string): RuntimeConfig['oauth'] {
  const publicUrl = env.MEOS_MCP_PUBLIC_URL?.trim();
  const adminPassword = env.MEOS_MCP_ADMIN_PASSWORD?.trim();
  if (!publicUrl && !adminPassword) return undefined;
  if (!publicUrl) {
    throw new Error('MEOS_MCP_ADMIN_PASSWORD is set but MEOS_MCP_PUBLIC_URL is missing. OAuth needs the public HTTPS base URL.');
  }
  if (!adminPassword) {
    throw new Error(
      'MEOS_MCP_PUBLIC_URL is set but MEOS_MCP_ADMIN_PASSWORD is missing. The consent screen and dashboard require an admin password.'
    );
  }
  if (adminPassword.length < 12) {
    throw new Error('MEOS_MCP_ADMIN_PASSWORD must be at least 12 characters. Generate: openssl rand -base64 24');
  }
  oneLine(adminPassword, 'MEOS_MCP_ADMIN_PASSWORD');

  let issuer: URL;
  try {
    issuer = new URL(publicUrl);
  } catch {
    throw new Error('MEOS_MCP_PUBLIC_URL must be a valid URL');
  }
  const local = issuer.hostname === 'localhost' || issuer.hostname === '127.0.0.1' || issuer.hostname === '[::1]';
  if (issuer.protocol !== 'https:' && !(issuer.protocol === 'http:' && local)) {
    throw new Error('MEOS_MCP_PUBLIC_URL must use https:// (http:// only for localhost)');
  }
  if (issuer.search || issuer.hash) throw new Error('MEOS_MCP_PUBLIC_URL must not contain a query or fragment');
  if (issuer.pathname !== '/' && issuer.pathname !== '') {
    throw new Error('MEOS_MCP_PUBLIC_URL must be an origin (no path)');
  }
  const base = issuer.origin;
  const resource = `${base}${path}`;

  const allowDcr = env.MEOS_MCP_ALLOW_DCR !== 'false';
  const adminLocalOnly = env.MEOS_MCP_ADMIN_LOCAL_ONLY !== 'false';

  return {
    issuer: base,
    resource,
    adminPassword,
    storePath: env.MEOS_MCP_OAUTH_STORE?.trim() || '',
    allowDynamicClientRegistration: allowDcr,
    adminLocalOnly,
    accessTokenTtlSeconds: 900
  };
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): RuntimeConfig {
  const transport = (env.MEOS_MCP_TRANSPORT?.trim().toLowerCase() || 'stdio') as TransportKind;
  if (transport !== 'stdio' && transport !== 'http') {
    throw new Error('MEOS_MCP_TRANSPORT must be "stdio" or "http"');
  }

  const accounts = parseAccounts(env);
  // OAuth is parsed first so an OAuth-only HTTP gateway is allowed to start
  // without a static bearer token.
  const path = env.MEOS_MCP_HTTP_PATH?.trim() || '/mcp';
  if (!path.startsWith('/') || /[?#]/.test(path)) {
    throw new Error('MEOS_MCP_HTTP_PATH must start with "/" and contain no query or fragment');
  }
  if (['/admin', '/oauth', '/.well-known', '/healthz'].some((p) => path === p || path.startsWith(`${p}/`))) {
    throw new Error('MEOS_MCP_HTTP_PATH must not shadow /admin, /oauth, /.well-known or /healthz');
  }
  const oauth = parseOAuth(env, path);
  const clients = parseClients(env, accounts, transport, Boolean(oauth));

  const rateMax = Number(env.MEOS_MCP_RATE_LIMIT ?? '120');
  if (!Number.isFinite(rateMax) || rateMax < 1) throw new Error('MEOS_MCP_RATE_LIMIT must be a positive number');

  const maxBody = Number(env.MEOS_MCP_MAX_BODY_BYTES ?? String(2 * 1024 * 1024));
  if (!Number.isFinite(maxBody) || maxBody < 1024 || maxBody > 16 * 1024 * 1024) {
    throw new Error('MEOS_MCP_MAX_BODY_BYTES must be between 1024 and 16777216');
  }

  const port = Number(env.MEOS_MCP_HTTP_PORT ?? '8788');
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('MEOS_MCP_HTTP_PORT must be an integer between 1 and 65535');
  }

  const logLevel = (env.MEOS_MCP_LOG_LEVEL?.trim().toLowerCase() || 'info') as RuntimeConfig['logLevel'];
  if (!['debug', 'info', 'warn', 'error'].includes(logLevel)) {
    throw new Error('MEOS_MCP_LOG_LEVEL must be debug, info, warn or error');
  }

  const host = env.MEOS_MCP_HTTP_HOST?.trim() || '127.0.0.1';
  if (!host) throw new Error('MEOS_MCP_HTTP_HOST must not be empty');
  const allowRemote = env.MEOS_MCP_ALLOW_REMOTE === 'true';
  if (!allowRemote && !['127.0.0.1', '::1', 'localhost'].includes(host)) {
    throw new Error(
      `Refusing to bind Streamable HTTP to ${host}. Set MEOS_MCP_ALLOW_REMOTE=true only behind TLS and a trusted proxy.`
    );
  }

  return {
    transport,
    http: {
      host,
      port,
      path,
      maxBodyBytes: maxBody
    },
    accounts,
    clients,
    stdioClientId: 'stdio',
    rateLimit: { windowMs: 60_000, max: rateMax },
    logLevel,
    oauth
  };
}
