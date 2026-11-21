import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, statSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { homedir } from 'node:os';

/**
 * Persistent OAuth state for the local MCP gateway.
 *
 * Only hashes of authorization codes, access tokens and refresh tokens are
 * stored. A file leak does not hand over a usable token. The file is written
 * atomically with mode 0600 in a 0700 directory; a group/world-readable file
 * is refused at load rather than silently trusted.
 *
 * This is a single-process gateway by design (see README). There is no
 * cross-process locking; running two gateways against one store is a
 * configuration error and is documented.
 */

export type TokenAuthMethod = 'none';

export interface OAuthClient {
  clientId: string;
  clientName: string;
  redirectUris: string[];
  grantTypes: string[];
  responseTypes: string[];
  tokenEndpointAuthMethod: TokenAuthMethod;
  scope: string;
  accountId: string;
  createdAt: string;
  lastUsedAt?: string;
  revokedAt?: string;
}

interface AuthCodeRecord {
  hash: string;
  clientId: string;
  redirectUri: string;
  scope: string;
  accountId: string;
  resource: string;
  codeChallenge: string;
  expiresAt: string;
  usedAt?: string;
}

interface AccessTokenRecord {
  hash: string;
  clientId: string;
  accountId: string;
  scope: string;
  resource: string;
  familyId: string;
  createdAt: string;
  expiresAt: string;
  lastUsedAt?: string;
  revokedAt?: string;
}

interface RefreshTokenRecord {
  hash: string;
  clientId: string;
  accountId: string;
  scope: string;
  resource: string;
  familyId: string;
  createdAt: string;
  expiresAt: string;
  rotatedAt?: string;
  revokedAt?: string;
}

interface StoreData {
  version: 1;
  clients: Record<string, OAuthClient>;
  codes: Record<string, AuthCodeRecord>;
  accessTokens: Record<string, AccessTokenRecord>;
  refreshTokens: Record<string, RefreshTokenRecord>;
}

export interface IssuedTokens {
  accessToken: string;
  refreshToken: string;
  scope: string;
  expiresIn: number;
  refreshExpiresIn: number;
}

export interface AccessGrant {
  clientId: string;
  accountId: string;
  scope: string;
  resource: string;
  expiresAt: string;
  familyId: string;
}

const ACCESS_TTL_SECONDS = 15 * 60;
const REFRESH_TTL_SECONDS = 30 * 24 * 60 * 60;
const CODE_TTL_SECONDS = 5 * 60;
const MAX_CLIENTS = 50;
const MAX_CODES = 100;
const MAX_ACCESS = 1000;
const MAX_REFRESH = 500;

function sha256(value: string): string {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

function rawToken(prefix: string): string {
  return `${prefix}_${randomBytes(32).toString('base64url')}`;
}

function now(): number {
  return Date.now();
}

function iso(ms = now()): string {
  return new Date(ms).toISOString();
}

function validRedirect(uri: string): boolean {
  let url: URL;
  try {
    url = new URL(uri);
  } catch {
    return false;
  }
  if (url.hash || url.username || url.password) return false;
  if (url.protocol === 'https:') return true;
  return url.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname);
}

export function isValidRedirectUri(uri: string): boolean {
  return validRedirect(uri);
}

/** RFC 7636 S256. The verifier is never stored; only the challenge is. */
export function verifyPkce(verifier: string, challenge: string): boolean {
  if (!/^[A-Za-z0-9\-._~]{43,128}$/.test(verifier)) return false;
  const digest = createHash('sha256').update(verifier, 'ascii').digest('base64url');
  const a = Buffer.from(digest);
  const b = Buffer.from(challenge);
  return a.length === b.length && timingSafeEqual(a, b);
}

export class OAuthStore {
  readonly path: string;
  private data: StoreData;

  constructor(path = process.env.MEOS_MCP_OAUTH_STORE?.trim() || `${homedir()}/.meos/mcp/oauth.json`) {
    this.path = resolve(path);
    this.data = this.load();
  }

  private load(): StoreData {
    if (!existsSync(this.path)) {
      return { version: 1, clients: {}, codes: {}, accessTokens: {}, refreshTokens: {} };
    }
    const mode = statSync(this.path).mode & 0o777;
    if (mode & 0o077) {
      throw new Error(
        `OAuth store ${this.path} is readable by group/world (mode ${mode.toString(8)}). Run: chmod 600 ${this.path}`
      );
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(readFileSync(this.path, 'utf8'));
    } catch {
      throw new Error(`OAuth store ${this.path} is not valid JSON; refusing to start with a corrupt store.`);
    }
    const d = parsed as Partial<StoreData>;
    if (!d || d.version !== 1 || typeof d.clients !== 'object') {
      throw new Error(`OAuth store ${this.path} has an unsupported shape; refusing to start.`);
    }
    return {
      version: 1,
      clients: d.clients ?? {},
      codes: d.codes ?? {},
      accessTokens: d.accessTokens ?? {},
      refreshTokens: d.refreshTokens ?? {}
    };
  }

  private persist(): void {
    this.prune();
    const dir = dirname(this.path);
    mkdirSync(dir, { recursive: true, mode: 0o700 });
    try {
      chmodSync(dir, 0o700);
    } catch {
      /* best effort */
    }
    const tmp = `${this.path}.${process.pid}.tmp`;
    writeFileSync(tmp, JSON.stringify(this.data, null, 2), { mode: 0o600 });
    renameSync(tmp, this.path);
    try {
      chmodSync(this.path, 0o600);
    } catch {
      /* best effort */
    }
  }

  private prune(): void {
    const t = now();
    for (const [hash, code] of Object.entries(this.data.codes)) {
      if (Date.parse(code.expiresAt) <= t || code.usedAt) delete this.data.codes[hash];
    }
    for (const [hash, token] of Object.entries(this.data.accessTokens)) {
      if (Date.parse(token.expiresAt) <= t || token.revokedAt) delete this.data.accessTokens[hash];
    }
    for (const [hash, token] of Object.entries(this.data.refreshTokens)) {
      if (Date.parse(token.expiresAt) <= t || token.revokedAt) delete this.data.refreshTokens[hash];
    }
    const trim = (record: Record<string, unknown>, max: number) => {
      const keys = Object.keys(record);
      if (keys.length <= max) return;
      for (const key of keys.slice(0, keys.length - max)) delete record[key];
    };
    trim(this.data.codes, MAX_CODES);
    trim(this.data.accessTokens, MAX_ACCESS);
    trim(this.data.refreshTokens, MAX_REFRESH);
  }

  listClients(): OAuthClient[] {
    return Object.values(this.data.clients)
      .filter((c) => !c.revokedAt)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  getClient(clientId: string): OAuthClient | null {
    const client = this.data.clients[clientId];
    return client && !client.revokedAt ? client : null;
  }

  registerClient(input: {
    clientName: string;
    redirectUris: string[];
    scope: string;
    accountId: string;
  }): OAuthClient {
    if (this.listClients().length >= MAX_CLIENTS) {
      throw new Error('Too many registered OAuth clients. Revoke one in the dashboard first.');
    }
    const clientId = `mcpc_${randomBytes(16).toString('base64url')}`;
    const client: OAuthClient = {
      clientId,
      clientName:
        input.clientName.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, 80) || 'Unnamed MCP client',
      redirectUris: input.redirectUris,
      grantTypes: ['authorization_code', 'refresh_token'],
      responseTypes: ['code'],
      tokenEndpointAuthMethod: 'none',
      scope: input.scope,
      accountId: input.accountId,
      createdAt: iso()
    };
    this.data.clients[clientId] = client;
    this.persist();
    return client;
  }

  revokeClient(clientId: string): boolean {
    const client = this.data.clients[clientId];
    if (!client) return false;
    client.revokedAt = iso();
    for (const [hash, token] of Object.entries(this.data.accessTokens)) {
      if (token.clientId === clientId) delete this.data.accessTokens[hash];
    }
    for (const [hash, token] of Object.entries(this.data.refreshTokens)) {
      if (token.clientId === clientId) delete this.data.refreshTokens[hash];
    }
    for (const [hash, code] of Object.entries(this.data.codes)) {
      if (code.clientId === clientId) delete this.data.codes[hash];
    }
    this.persist();
    return true;
  }

  createCode(input: {
    clientId: string;
    redirectUri: string;
    scope: string;
    accountId: string;
    resource: string;
    codeChallenge: string;
  }): string {
    const raw = rawToken('mcpc');
    this.data.codes[sha256(raw)] = {
      hash: sha256(raw),
      clientId: input.clientId,
      redirectUri: input.redirectUri,
      scope: input.scope,
      accountId: input.accountId,
      resource: input.resource,
      codeChallenge: input.codeChallenge,
      expiresAt: iso(now() + CODE_TTL_SECONDS * 1000)
    };
    this.persist();
    return raw;
  }

  /**
   * Consume an authorization code exactly once, binding it to the client,
   * redirect URI, verifier and resource. Any mismatch returns null.
   */
  takeCode(input: {
    code: string;
    clientId: string;
    redirectUri: string;
    codeVerifier: string;
    resource: string;
  }): { accountId: string; scope: string; resource: string } | null {
    const hash = sha256(input.code);
    const record = this.data.codes[hash];
    if (!record || record.clientId !== input.clientId) return null;
    if (record.usedAt || Date.parse(record.expiresAt) <= now()) return null;
    if (record.redirectUri !== input.redirectUri) return null;
    if (record.resource !== input.resource) return null;
    if (!verifyPkce(input.codeVerifier, record.codeChallenge)) return null;
    record.usedAt = iso();
    this.persist();
    return { accountId: record.accountId, scope: record.scope, resource: record.resource };
  }

  issueTokens(input: {
    clientId: string;
    accountId: string;
    scope: string;
    resource: string;
    familyId?: string;
  }): IssuedTokens {
    if (!input.scope.trim()) throw new Error('Refusing to issue a token with no scopes');
    const familyId = input.familyId ?? `fam_${randomBytes(12).toString('base64url')}`;
    const accessToken = rawToken('meos_at');
    const refreshToken = rawToken('meos_rt');
    const accessHash = sha256(accessToken);
    const refreshHash = sha256(refreshToken);
    const t = now();

    this.data.accessTokens[accessHash] = {
      hash: accessHash,
      clientId: input.clientId,
      accountId: input.accountId,
      scope: input.scope,
      resource: input.resource,
      familyId,
      createdAt: iso(t),
      expiresAt: iso(t + ACCESS_TTL_SECONDS * 1000)
    };
    this.data.refreshTokens[refreshHash] = {
      hash: refreshHash,
      clientId: input.clientId,
      accountId: input.accountId,
      scope: input.scope,
      resource: input.resource,
      familyId,
      createdAt: iso(t),
      expiresAt: iso(t + REFRESH_TTL_SECONDS * 1000)
    };
    const client = this.data.clients[input.clientId];
    if (client) client.lastUsedAt = iso(t);
    this.persist();

    return {
      accessToken,
      refreshToken,
      scope: input.scope,
      expiresIn: ACCESS_TTL_SECONDS,
      refreshExpiresIn: REFRESH_TTL_SECONDS
    };
  }

  authenticateAccess(raw: string, expectedResource: string): AccessGrant | null {
    const hash = sha256(raw);
    const record = this.data.accessTokens[hash];
    if (!record || record.revokedAt) return null;
    if (Date.parse(record.expiresAt) <= now()) {
      delete this.data.accessTokens[hash];
      this.persist();
      return null;
    }
    if (record.resource !== expectedResource) return null;

    // Touch at most once a minute; a write per MCP request would be wasteful.
    const last = record.lastUsedAt ? Date.parse(record.lastUsedAt) : 0;
    if (now() - last > 60_000) {
      record.lastUsedAt = iso();
      const client = this.data.clients[record.clientId];
      if (client) client.lastUsedAt = record.lastUsedAt;
      this.persist();
    }
    return {
      clientId: record.clientId,
      accountId: record.accountId,
      scope: record.scope,
      resource: record.resource,
      expiresAt: record.expiresAt,
      familyId: record.familyId
    };
  }

  /**
   * Rotate a refresh token. Reuse of an already-rotated token is treated as
   * theft: the whole token family is revoked, including the current access and
   * refresh tokens. This is RFC 6749 §10.4 / OAuth 2.1 guidance.
   */
  rotateRefresh(input: {
    refreshToken: string;
    clientId: string;
    resource: string;
  }): IssuedTokens | 'invalid' | 'reused' {
    const hash = sha256(input.refreshToken);
    const record = this.data.refreshTokens[hash];
    if (!record || record.clientId !== input.clientId) return 'invalid';
    if (record.revokedAt || Date.parse(record.expiresAt) <= now()) return 'invalid';
    if (record.resource !== input.resource) return 'invalid';

    if (record.rotatedAt) {
      this.revokeFamily(record.familyId);
      return 'reused';
    }

    record.rotatedAt = iso();
    const issued = this.issueTokens({
      clientId: record.clientId,
      accountId: record.accountId,
      scope: record.scope,
      resource: record.resource,
      familyId: record.familyId
    });
    this.persist();
    return issued;
  }

  private revokeFamily(familyId: string): void {
    for (const [hash, token] of Object.entries(this.data.accessTokens)) {
      if (token.familyId === familyId) token.revokedAt = iso();
      void hash;
    }
    for (const [hash, token] of Object.entries(this.data.refreshTokens)) {
      if (token.familyId === familyId) token.revokedAt = iso();
      void hash;
    }
    this.persist();
  }

  /** RFC 7009 revocation; always succeeds for an unknown token. */
  revokeToken(raw: string): void {
    const accessHash = sha256(raw);
    const access = this.data.accessTokens[accessHash];
    if (access) {
      access.revokedAt = iso();
      this.revokeFamily(access.familyId);
    }
    const refreshHash = sha256(raw);
    const refresh = this.data.refreshTokens[refreshHash];
    if (refresh) {
      refresh.revokedAt = iso();
      this.revokeFamily(refresh.familyId);
    }
    this.persist();
  }

  /** Last time a client was seen, for the dashboard. */
  lastUsed(clientId: string): string | null {
    return this.data.clients[clientId]?.lastUsedAt ?? null;
  }

  /** Scopes on any live access token for a client (consent may narrow the request). */
  activeScopes(clientId: string): string[] {
    const scopes = new Set<string>();
    for (const token of Object.values(this.data.accessTokens)) {
      if (token.clientId !== clientId || token.revokedAt) continue;
      if (Date.parse(token.expiresAt) <= now()) continue;
      for (const s of token.scope.split(/\s+/)) if (s) scopes.add(s);
    }
    return [...scopes].sort();
  }

  /** Live access + refresh token counts. */
  tokenCounts(clientId: string): { access: number; refresh: number } {
    const t = now();
    let access = 0;
    let refresh = 0;
    for (const token of Object.values(this.data.accessTokens)) {
      if (token.clientId === clientId && !token.revokedAt && Date.parse(token.expiresAt) > t) access++;
    }
    for (const token of Object.values(this.data.refreshTokens)) {
      if (token.clientId === clientId && !token.revokedAt && Date.parse(token.expiresAt) > t && !token.rotatedAt) refresh++;
    }
    return { access, refresh };
  }

  /** Effective scopes for a client, even if its access token has expired. */
  grantedScopes(clientId: string): string[] {
    const scopes = new Set<string>();
    for (const token of Object.values(this.data.refreshTokens)) {
      if (token.clientId !== clientId || token.revokedAt) continue;
      for (const s of token.scope.split(/\s+/)) if (s) scopes.add(s);
    }
    return [...scopes].sort();
  }

  /** Only used by tests. */
  flush(): void {
    this.persist();
  }
}
