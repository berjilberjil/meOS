import { createHash } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { homedir } from 'node:os';
import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';

/**
 * Small, file-backed idempotency cache for MCP write tools.
 *
 * A model can retry a tool after a timeout, or a transport can deliver the same
 * JSON-RPC call twice. Without this, a retry could create two tasks or two
 * purchases. Callers opt in with `idempotency_key`; the key is scoped to the
 * client and tool, so one client cannot replay another client's result.
 *
 * Only successful results are cached: a failed write must be retryable. The
 * store keeps 24 hours and at most 500 entries, and is written 0600.
 */

interface Entry {
  at: number;
  result: CallToolResult;
}

const TTL_MS = 24 * 60 * 60 * 1000;
const MAX_ENTRIES = 500;

export class IdempotencyStore {
  readonly path: string;
  private data: Record<string, Entry>;

  constructor(path = process.env.MEOS_MCP_IDEMPOTENCY_STORE?.trim() || `${homedir()}/.meos/mcp/idempotency.json`) {
    this.path = resolve(path);
    this.data = this.load();
  }

  private load(): Record<string, Entry> {
    if (!existsSync(this.path)) return {};
    try {
      const parsed = JSON.parse(readFileSync(this.path, 'utf8')) as unknown;
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return {};
      return parsed as Record<string, Entry>;
    } catch {
      // A corrupt cache must not block writes; it only loses replay protection.
      return {};
    }
  }

  private persist(): void {
    const t = Date.now();
    const live = Object.entries(this.data).filter(([, e]) => t - e.at < TTL_MS);
    if (live.length > MAX_ENTRIES) live.splice(0, live.length - MAX_ENTRIES);
    this.data = Object.fromEntries(live);
    const dir = dirname(this.path);
    mkdirSync(dir, { recursive: true, mode: 0o700 });
    try {
      chmodSync(dir, 0o700);
    } catch {
      /* best effort */
    }
    const tmp = `${this.path}.${process.pid}.tmp`;
    writeFileSync(tmp, JSON.stringify(this.data), { mode: 0o600 });
    renameSync(tmp, this.path);
  }

  private key(clientId: string, tool: string, idempotencyKey: string): string {
    return createHash('sha256').update(`${clientId}\n${tool}\n${idempotencyKey}`).digest('hex');
  }

  get(clientId: string, tool: string, idempotencyKey: string): CallToolResult | null {
    const hash = this.key(clientId, tool, idempotencyKey);
    const entry = this.data[hash];
    if (!entry || Date.now() - entry.at >= TTL_MS) return null;
    return entry.result;
  }

  put(clientId: string, tool: string, idempotencyKey: string, result: CallToolResult): void {
    if (result.isError) return;
    const hash = this.key(clientId, tool, idempotencyKey);
    this.data[hash] = { at: Date.now(), result };
    this.persist();
  }
}
