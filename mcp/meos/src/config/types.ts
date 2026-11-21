import type { Scope } from '../auth/scopes.ts';

export type TransportKind = 'stdio' | 'http';

export interface AccountConfig {
  id: string;
  baseUrl: string;
  username: string;
  password: string;
  /** Unlocks the zero-knowledge vault. Never sent to an MCP client. */
  vaultPassphrase?: string;
  vaultRecovery?: string;
  /** Base32 TOTP seed, only needed when MFA is enabled on this MeOS account. */
  mfaSecret?: string;
  requestTimeoutMs: number;
}

export interface ClientConfig {
  id: string;
  /** SHA-256 of a static bearer token, hex. OAuth clients have no static hash. */
  tokenHash: string | null;
  scopes: Scope[];
  accountId: string;
  /** ISO-8601 instant after which the token is refused. Optional. */
  expiresAt?: string;
  authMethod?: 'static' | 'oauth' | 'stdio';
  /** The registered OAuth client id, when authMethod is oauth. */
  oauthClientId?: string;
}

export interface HttpConfig {
  host: string;
  port: number;
  path: string;
  maxBodyBytes: number;
}

export interface OAuthConfig {
  /** Issuer, e.g. https://mcp.example.com (no trailing slash). */
  issuer: string;
  /** The protected resource: issuer + MCP path. */
  resource: string;
  /** Required to approve a consent request or open the admin dashboard. */
  adminPassword: string;
  storePath: string;
  allowDynamicClientRegistration: boolean;
  /** Refuse /admin through a tunnel/proxy unless explicitly allowed. */
  adminLocalOnly: boolean;
  accessTokenTtlSeconds: number;
}

export interface RuntimeConfig {
  transport: TransportKind;
  http: HttpConfig;
  accounts: Map<string, AccountConfig>;
  clients: Map<string, ClientConfig>;
  stdioClientId: string;
  rateLimit: { windowMs: number; max: number };
  logLevel: 'debug' | 'info' | 'warn' | 'error';
  oauth?: OAuthConfig;
}
