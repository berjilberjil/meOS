import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';
import { z, type ZodTypeAny } from 'zod';
import type { Scope } from '../auth/scopes.ts';
import { canUseTool, hasEveryScope, requiredScopesForTool } from '../auth/scopes.ts';
import type { RateLimiter } from '../auth/rateLimit.ts';
import type { ClientConfig } from '../config/types.ts';
import type { AccountServices } from '../services/account.ts';
import type { Logger } from '../services/logger.ts';
import type { AuditLog } from '../services/audit.ts';
import type { IdempotencyStore } from '../services/idempotency.ts';
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
  /** Metadata-only local audit log. Optional in tests. */
  audit?: AuditLog;
  /** File-backed replay protection for write tools. Optional in tests. */
  idempotency?: IdempotencyStore;
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
  /** Financially significant write: also requires `confirm: true`. */
  confirmation?: boolean;
  handler: (args: Record<string, any>, ctx: ToolContext) => Promise<CallToolResult> | CallToolResult;
}

/**
 * Registers tools with the gateway's standard permission and error envelope.
 * The context (and therefore the account) is fixed before any tool is exposed,
 * so an argument can never select a user.
 */
/**
 * Add the optional `idempotency_key` to write tools only. Read tools stay
 * smaller, and a handler never has to know the field exists.
 */
export function schemaFor(def: ToolDefinition): ZodShape | undefined {
  const write = def.scopes.includes('write') || Boolean(def.destructive);
  if (!write) return def.inputSchema;
  return {
    ...(def.inputSchema ?? {}),
    ...(def.destructive || def.confirmation ? { confirm: z.boolean().optional() } : {}),
    idempotency_key: z.string().min(8).max(120).optional()
  };
}

export function registerTools(server: McpServer, definitions: ToolDefinition[], ctx: ToolContext): void {
  for (const def of definitions) {
    // tools/list is a discovery surface too: a client without a module scope
    // should not even see that module's tools.
    if (!canUseTool(ctx.client.scopes, def)) continue;
    const required = requiredScopesForTool(def);
    server.registerTool(
      def.name,
      {
        title: def.title,
        description: def.description,
        inputSchema: schemaFor(def) as any,
        annotations: {
          title: def.title,
          readOnlyHint: !required.some((s) => s.endsWith('.write')) && !def.destructive,
          destructiveHint: Boolean(def.destructive),
          idempotentHint: !required.some((s) => s.endsWith('.write')),
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
    const required = requiredScopesForTool(def);
    if (!hasEveryScope(ctx.client.scopes, required)) {
      throw errors.forbidden(
        required.join(', '),
        `Client "${ctx.client.id}" has: ${ctx.client.scopes.join(', ') || 'none'}.`
      );
    }
    if ((def.destructive || def.confirmation) && args.confirm !== true) {
      throw errors.confirmationRequired(def.title);
    }

    // The SDK validates against this schema at the protocol boundary, but doing
    // it here too keeps the guarantee when a handler is invoked directly (tests,
    // resources, future transports) and gives one consistent error shape.
    let parsedArgs = args;
    const schema = schemaFor(def);
    if (schema) {
      const parsed = z.object(schema as Record<string, ZodTypeAny>).safeParse(args);
      if (!parsed.success) {
        const issue = parsed.error.issues[0];
        const where = issue?.path?.length ? `${issue.path.join('.')}: ` : '';
        throw errors.invalidInput(`${where}${issue?.message ?? 'invalid arguments'}`);
      }
      parsedArgs = parsed.data as Record<string, any>;
    }

    const idempotencyKey =
      typeof parsedArgs.idempotency_key === 'string' ? parsedArgs.idempotency_key : null;
    if (idempotencyKey && ctx.idempotency) {
      const replay = ctx.idempotency.get(ctx.client.id, def.name, idempotencyKey);
      if (replay) {
        ctx.logger.info('tool_replay', { client: ctx.client.id, tool: def.name, ms: Date.now() - started });
        ctx.audit?.record({
          event: 'tool_replay',
          client: ctx.client.id,
          tool: def.name,
          outcome: 'success',
          ms: Date.now() - started
        });
        return replay;
      }
    }

    const result = await def.handler(parsedArgs, ctx);
    if (idempotencyKey && ctx.idempotency) {
      // The write already happened. A cache failure must not turn it into an
      // error the model retries (which would duplicate it).
      try {
        ctx.idempotency.put(ctx.client.id, def.name, idempotencyKey, result);
      } catch {
        ctx.logger.warn('idempotency_write_failed', { client: ctx.client.id, tool: def.name });
      }
    }
    const ms = Date.now() - started;
    ctx.logger.info('tool_call', {
      client: ctx.client.id,
      tool: def.name,
      ok: !result.isError,
      ms,
      arg_count: Object.keys(args).length
    });
    ctx.audit?.record({
      event: 'tool_call',
      client: ctx.client.id,
      tool: def.name,
      outcome: result.isError ? 'failure' : 'success',
      ms
    });
    return result;
  } catch (e) {
    const known = isMeosMcpError(e);
    const code = known ? e.code : 'internal_error';
    const message = known ? e.message : 'The MeOS MCP server hit an unexpected error.';
    const ms = Date.now() - started;
    ctx.logger.warn('tool_error', {
      client: ctx.client.id,
      tool: def.name,
      code,
      ms
    });
    ctx.audit?.record({
      event: 'tool_call',
      client: ctx.client.id,
      tool: def.name,
      outcome: code === 'forbidden' || code === 'confirmation_required' ? 'denied' : 'error',
      ms,
      meta: { code }
    });
    return fail(code, message, known ? e.hint : undefined);
  }
}
