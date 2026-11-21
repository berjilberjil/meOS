import type { ClientConfig, RuntimeConfig } from '../config/types.ts';
import type { ServiceRegistry } from '../services/account.ts';
import type { Logger } from '../services/logger.ts';
import { hashToken, tokenHashMatches } from '../config/env.ts';
import { parseScopes } from './scopes.ts';
import { normalizeMCP, type MCPState } from '../schemas/mcp.ts';
import { STATE_KEYS } from '../schemas/models.ts';

interface CacheEntry {
  at: number;
  state: MCPState;
}

/**
 * Tokens created in the native Settings screen.
 *
 * The gateway is already trusted with the owner's credentials and vault key, so
 * it can decrypt `meos.mcp` and verify a bearer hash. Tokens are cached briefly
 * to avoid a state fetch per request; a revoked token is refused on the next
 * refresh.
 */
export class DynamicClientRegistry {
  private readonly config: RuntimeConfig;
  private readonly services: ServiceRegistry;
  private readonly logger: Logger;
  private readonly ttlMs: number;
  private readonly now: () => number;
  private readonly cache = new Map<string, CacheEntry>();

  constructor(
    config: RuntimeConfig,
    services: ServiceRegistry,
    logger: Logger,
    options: { ttlMs?: number; now?: () => number } = {}
  ) {
    this.config = config;
    this.services = services;
    this.logger = logger;
    this.ttlMs = options.ttlMs ?? 10_000;
    this.now = options.now ?? Date.now;
  }

  /** Forget cached registries; used after the app updates connectors. */
  clear(): void {
    this.cache.clear();
  }

  async authenticate(presentedHash: string): Promise<ClientConfig | null> {
    for (const accountId of this.config.accounts.keys()) {
      const state = await this.load(accountId);
      for (const row of state.clients) {
        if (!tokenHashMatches(presentedHash, row.tokenHash)) continue;
        if (row.revoked) return null;
        if (row.expiresAt && Date.parse(row.expiresAt) <= this.now()) return null;
        let scopes;
        try {
          scopes = parseScopes(row.scopes.join(','));
        } catch {
          return null;
        }
        // Read is the floor, matching the app's UI.
        if (!scopes.includes('read')) return null;
        return {
          id: `app:${row.id}`,
          tokenHash: row.tokenHash,
          scopes,
          accountId,
          expiresAt: row.expiresAt ?? undefined
        };
      }
    }
    return null;
  }

  private async load(accountId: string): Promise<MCPState> {
    const cached = this.cache.get(accountId);
    if (cached && this.now() - cached.at < this.ttlMs) return cached.state;
    try {
      const raw = await this.services.get(accountId).store.read<unknown>(STATE_KEYS.mcp);
      const state = normalizeMCP(raw);
      this.cache.set(accountId, { at: this.now(), state });
      return state;
    } catch (error) {
      // A locked vault or a temporary backend failure must not turn a bad token
      // into a valid one, and must not crash the server. Static env clients keep
      // working; dynamic ones simply fail closed until the next attempt.
      this.logger.warn('mcp_registry_unavailable', {
        account: accountId,
        error: error instanceof Error ? error.name : 'unknown'
      });
      return { schemaVersion: 1, updatedAt: new Date(0).toISOString(), clients: [] };
    }
  }
}

/** Hash a token exactly as the app and env config do. */
export function hashPresentedToken(token: string): string {
  return hashToken(token);
}
