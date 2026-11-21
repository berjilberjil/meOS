import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { ClientConfig } from './config/types.ts';
import type { AccountServices } from './services/account.ts';
import type { Logger } from './services/logger.ts';
import type { RateLimiter } from './auth/rateLimit.ts';
import { allTools } from './tools/index.ts';
import { registerTools, type ToolContext } from './tools/registry.ts';
import { registerResources } from './resources/index.ts';
import { registerPrompts } from './prompts/index.ts';

export interface BuildServerOptions {
  client: ClientConfig;
  services: AccountServices;
  logger: Logger;
  limiter: RateLimiter;
  /** HTTP applies one limit per request; stdio applies it per tool call. */
  enforceRateLimit?: boolean;
}

export const SERVER_INSTRUCTIONS = `
MeOS is a private, single-owner personal operating system: finance snapshot, health and fitness,
per-day tasks and habits, life goals, notes, events and reminders, diet, learning videos and an AI memory bank.

Start with meos_get_capabilities when you need to know what exists. Do not assume a MeOS feature that
is not in the tool list; in particular there is no transaction ledger, no standalone reminder record, and
no note tag system.

Data rules:
- Identity and account scope come from the server's authenticated MeOS session. There is no user id argument.
- A client is read-only unless the owner granted write scopes. Destructive tools also require confirm=true.
- Health, fitness, diet and body-photo data need the health scope. Locked notes and profile private details
  need the secret scope. Body-photo bytes are never returned — only metadata.
- All finance figures come from Fold's stored snapshot or the Stuff ledger. Never recompute a balance from
  transactions, and never invent a missing number.
- Event occurrences are projected from recurrence rules; the app owns device notifications. Updating one
  event never clears another's reminders.
- Prefer paginated tools over dumping entire modules.
`.trim();

export function buildServer(options: BuildServerOptions): McpServer {
  const { client, services, logger, limiter } = options;
  const server = new McpServer(
    { name: 'meos', version: '1.0.0', title: 'MeOS' },
    {
      instructions: SERVER_INSTRUCTIONS,
      // Bounds an abusive tools/call payload independently of HTTP body size.
      maxToolInputElements: 5000
    }
  );

  const ctx: ToolContext = {
    client,
    services,
    logger,
    limiter,
    now: new Date(),
    enforceRateLimit: options.enforceRateLimit ?? true
  };

  registerTools(server, allTools, ctx);
  registerResources(server, ctx);
  registerPrompts(server);
  return server;
}
