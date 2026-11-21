import { hashToken, tokenHashMatches } from '../config/env.ts';
import type { ClientConfig, RuntimeConfig } from '../config/types.ts';
import { errors } from '../utils/errors.ts';
import type { DynamicClientRegistry } from './dynamicClients.ts';

/**
 * Identity for HTTP clients comes only from the bearer token. A `user_id`,
 * `account`, or username in a tool argument is ignored by construction: tool
 * schemas do not contain those fields and the context is fixed before any tool
 * runs.
 */
export async function authenticateBearer(
  config: RuntimeConfig,
  authorization: string | undefined,
  dynamic?: DynamicClientRegistry
): Promise<ClientConfig> {
  if (!authorization) throw errors.unauthenticated();
  const match = /^Bearer\s+(.+)$/i.exec(authorization.trim());
  if (!match) throw errors.unauthenticated('Use "Authorization: Bearer <token>".');
  const presented = hashToken(match[1]!.trim());

  let found: ClientConfig | undefined;
  for (const client of config.clients.values()) {
    if (!client.tokenHash) continue;
    if (tokenHashMatches(presented, client.tokenHash)) found = client;
  }
  if (!found && dynamic) found = (await dynamic.authenticate(presented)) ?? undefined;
  if (!found) throw errors.unauthenticated('The bearer token is not valid.');
  if (found.expiresAt && Date.parse(found.expiresAt) <= Date.now()) {
    throw errors.unauthenticated('The bearer token has expired.');
  }
  return found;
}

export function stdioClient(config: RuntimeConfig): ClientConfig {
  const client = config.clients.get(config.stdioClientId);
  if (!client) throw new Error('stdio client is not configured');
  return client;
}
