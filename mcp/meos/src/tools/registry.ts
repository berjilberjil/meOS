import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';
import { z, type ZodTypeAny } from 'zod';
import type { Scope } from '../auth/scopes.ts';
import { hasEveryScope } from '../auth/scopes.ts';
import type { RateLimiter } from '../auth/rateLimit.ts';
import type { ClientConfig } from '../config/types.ts';
import type { AccountServices } from '../services/account.ts';
import type { Logger } from '../services/logger.ts';
import { errors, isMeosMcpError } from '../utils/errors.ts';
import { fail } from '../utils/result.ts';

export interface ToolContext {
  client: ClientConfig;
  services: AccountServices;
  logger: Logger;
  limiter: RateLimiter;
  now: Date;
  /** HTTP enforces one limit per request and sets this false. */
  enforceRateLimit?: boolean;
}

export type ZodShape = Record<string, z.ZodTypeAny>;

export interface ToolDefinition {
  name: string;
  title: string;
  description: string;
  inputSchema?: ZodShape;
  /** Every scope here is required. Be explicit: read operations include 'read'. */
  scopes: Scope[];
  destructive?: boolean;
  handler: (args: Record<string, any>, ctx: ToolContext) => Promise<CallToolResult> | CallToolResult;
}

/**
 * Registers tools with the gateway's standard permission and error envelope.
 * The context (and therefore the account) is fixed before any tool is exposed,
 * so an argument can never select a user.
 */
export function registerTools(server: McpServer, definitions: ToolDefinition[], ctx: ToolContext): void {
  for (const def of definitions) {
    server.registerTool(
      def.name,
      {
        title: def.title,
        description: def.description,
        inputSchema: def.inputSchema as any,
        annotations: {
          title: def.title,
          readOnlyHint: !def.scopes.includes('write') && !def.destructive,
          destructiveHint: Boolean(def.destructive),
          idempotentHint: !def.scopes.includes('write'),
          openWorldHint: false
        }
      },
      async (args: Record<string, any>) => runTool(def, args ?? {}, ctx)
    );
  }
}

export async function runTool(def: ToolDefinition, args: Record<string, any>, ctx: ToolContext): Promise<CallToolResult> {
  const started = Date.now();
  try {
    if (ctx.enforceRateLimit !== false) ctx.limiter.take(ctx.client.id);
    if (!hasEveryScope(ctx.client.scopes, def.scopes)) {
      const missing = def.scopes.filter((s) => !ctx.client.scopes.includes(s));
      throw errors.forbidden(missing.join(', '), `Client "${ctx.client.id}" has: ${ctx.client.scopes.join(', ') || 'none'}.`);
    }
    if (def.destructive && args.confirm !== true) {
      throw errors.confirmationRequired(def.title);
    }

    // The SDK validates against this schema at the protocol boundary, but doing
    // it here too keeps the guarantee when a handler is invoked directly (tests,
    // resources, future transports) and gives one consistent error shape.
    let parsedArgs = args;
    if (def.inputSchema) {
      const parsed = z.object(def.inputSchema as Record<string, ZodTypeAny>).safeParse(args);
      if (!parsed.success) {
        const issue = parsed.error.issues[0];
        const where = issue?.path?.length ? `${issue.path.join('.')}: ` : '';
        throw errors.invalidInput(`${where}${issue?.message ?? 'invalid arguments'}`);
      }
      parsedArgs = parsed.data as Record<string, any>;
    }

    const result = await def.handler(parsedArgs, ctx);
    ctx.logger.info('tool_call', {
      client: ctx.client.id,
      tool: def.name,
      ok: !result.isError,
      ms: Date.now() - started,
      arg_count: Object.keys(args).length
    });
    return result;
  } catch (e) {
    const known = isMeosMcpError(e);
    const code = known ? e.code : 'internal_error';
    const message = known ? e.message : 'The MeOS MCP server hit an unexpected error.';
    ctx.logger.warn('tool_error', {
      client: ctx.client.id,
      tool: def.name,
      code,
      ms: Date.now() - started
    });
    return fail(code, message, known ? e.hint : undefined);
  }
}
