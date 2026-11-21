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
  requestTimeoutMs: number;
}

export interface ClientConfig {
  id: string;
  /** SHA-256 of the bearer token, hex. The raw token is never retained. */
  tokenHash: string | null;
  scopes: Scope[];
  accountId: string;
  /** ISO-8601 instant after which the token is refused. Optional. */
  expiresAt?: string;
}

export interface HttpConfig {
  host: string;
  port: number;
  path: string;
  maxBodyBytes: number;
}

export interface RuntimeConfig {
  transport: TransportKind;
  http: HttpConfig;
  accounts: Map<string, AccountConfig>;
  clients: Map<string, ClientConfig>;
  stdioClientId: string;
  rateLimit: { windowMs: number; max: number };
  logLevel: 'debug' | 'info' | 'warn' | 'error';
}
