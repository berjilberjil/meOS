import { hashToken, tokenHashMatches } from '../config/env.ts';
import type { ClientConfig, RuntimeConfig } from '../config/types.ts';
import type { OAuthStore } from '../oauth/store.ts';
import { parseScopes } from './scopes.ts';
import { errors } from '../utils/errors.ts';

/**
 * Identity for HTTP clients comes only from the bearer token. A `user_id`,
 * `account`, or username in a tool argument is ignored by construction: tool
 * schemas do not contain those fields and the context is fixed before any tool
 * runs.
 *
 * Two token kinds are accepted:
 *   - a static token from server-side config (legacy / automation), and
 *   - an OAuth 2.1 access token issued after owner consent (ChatGPT and other
 *     remote MCP clients).
 *
 * OAuth tokens are validated for expiry, revocation, audience and scope. The
 * resulting ClientConfig carries only that grant's scopes.
 */
export function authenticateBearer(config: RuntimeConfig, authorization: string | undefined): ClientConfig {
  if (!authorization) throw errors.unauthenticated();
  const match = /^Bearer\s+(.+)$/i.exec(authorization.trim());
  if (!match) throw errors.unauthenticated('Use "Authorization: Bearer <token>".');
  const presented = hashToken(match[1]!.trim());

  let found: ClientConfig | undefined;
  for (const client of config.clients.values()) {
    if (!client.tokenHash) continue;
    if (tokenHashMatches(presented, client.tokenHash)) found = client;
  }
  if (!found) throw errors.unauthenticated('The bearer token is not valid.');
  if (found.expiresAt && Date.parse(found.expiresAt) <= Date.now()) {
    throw errors.unauthenticated('The bearer token has expired.');
  }
  return found;
}

/** Static token first, then an OAuth access token. Constant-time hash lookup. */
export function authenticateRequest(
  config: RuntimeConfig,
  authorization: string | undefined,
  oauthStore?: OAuthStore
): ClientConfig {
  if (!authorization) throw errors.unauthenticated();
  const match = /^Bearer\s+(.+)$/i.exec(authorization.trim());
  if (!match) throw errors.unauthenticated('Use "Authorization: Bearer <token>".');
  const raw = match[1]!.trim();

  try {
    return authenticateBearer(config, authorization);
  } catch (e) {
    if (!oauthStore || !config.oauth) throw e;
  }

  const grant = oauthStore.authenticateAccess(raw, config.oauth.resource);
  if (!grant) {
    throw errors.unauthenticated('The access token is invalid, expired, revoked, or for a different resource.');
  }
  const client = oauthStore.getClient(grant.clientId);
  if (!client) throw errors.unauthenticated('The OAuth client was revoked.');

  return {
    id: `oauth:${grant.clientId}`,
    tokenHash: null,
    // An empty grant must stay empty. `parseScopes('')` defaults to legacy
    // `read`, which would silently widen a malformed token to every module.
    scopes: grant.scope.trim() ? parseScopes(grant.scope) : [],
    accountId: grant.accountId,
    expiresAt: grant.expiresAt,
    authMethod: 'oauth',
    oauthClientId: grant.clientId
  };
}

export function stdioClient(config: RuntimeConfig): ClientConfig {
  const client = config.clients.get(config.stdioClientId);
  if (!client) throw new Error('stdio client is not configured');
  return client;
}
