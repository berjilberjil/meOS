/**
 * App-managed MCP connectors.
 *
 * The native Settings screen writes this encrypted document. It contains only
 * SHA-256 hashes and scopes; the raw bearer token is shown once in the app and
 * is never synced.
 */

export interface MCPClientRecord {
  id: string;
  name: string;
  tokenHash: string;
  tokenPrefix: string;
  scopes: string[];
  createdAt: string;
  expiresAt?: string | null;
  revoked?: boolean;
  [key: string]: unknown;
}

export interface MCPState {
  schemaVersion: number;
  updatedAt: string;
  gatewayURL?: string;
  publicURL?: string;
  clients: MCPClientRecord[];
  [key: string]: unknown;
}

export function normalizeMCP(raw: unknown): MCPState {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return { schemaVersion: 1, updatedAt: new Date().toISOString(), clients: [] };
  }
  const source = raw as Record<string, unknown>;
  const clients = Array.isArray(source.clients)
    ? source.clients
        .filter((row): row is Record<string, unknown> => Boolean(row) && typeof row === 'object' && !Array.isArray(row))
        .map((row) => ({
          id: String(row.id ?? ''),
          name: String(row.name ?? ''),
          tokenHash: String(row.tokenHash ?? '').toLowerCase(),
          tokenPrefix: String(row.tokenPrefix ?? ''),
          scopes: Array.isArray(row.scopes) ? row.scopes.map(String) : [],
          createdAt: String(row.createdAt ?? ''),
          expiresAt: row.expiresAt ? String(row.expiresAt) : null,
          revoked: row.revoked === true
        }))
        .filter((row) => /^[a-f0-9]{64}$/.test(row.tokenHash) && row.id)
    : [];
  return {
    ...source,
    schemaVersion: typeof source.schemaVersion === 'number' ? source.schemaVersion : 1,
    updatedAt: typeof source.updatedAt === 'string' ? source.updatedAt : new Date().toISOString(),
    gatewayURL: typeof source.gatewayURL === 'string' ? source.gatewayURL : undefined,
    publicURL: typeof source.publicURL === 'string' ? source.publicURL : undefined,
    clients
  };
}
