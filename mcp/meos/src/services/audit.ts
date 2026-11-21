import { createHash, randomBytes } from 'node:crypto';
import {
  appendFileSync,
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  statSync,
  writeFileSync
} from 'node:fs';
import { dirname, resolve } from 'node:path';
import { homedir } from 'node:os';

/**
 * Append-only MCP audit log.
 *
 * Metadata only: client id, tool name, outcome, duration, request id, and a
 * salted hash of the caller's address. Never tool arguments, tool results,
 * bearer tokens, vault passphrases, note text, finance figures, or file bytes.
 *
 * The file lives beside the OAuth store with mode 0600. It rotates at 5 MB and
 * keeps three generations, so a long-running gateway cannot fill the disk.
 */

export interface AuditEvent {
  event: string;
  client?: string;
  tool?: string;
  outcome?: 'success' | 'failure' | 'denied' | 'error';
  ms?: number;
  requestId?: string;
  ip?: string;
  userAgent?: string;
  meta?: Record<string, string | number | boolean>;
}

export interface AuditRow {
  ts: string;
  event: string;
  client?: string;
  tool?: string;
  outcome?: string;
  ms?: number;
  request_id?: string;
  ip_hash?: string;
  ua_hash?: string;
  meta?: Record<string, string | number | boolean>;
}

const FORBIDDEN =
  /token|authorization|cookie|password|passphrase|secret|\bkey\b|api[-_]?key|body|content|note|journal|amount|balance|account|ciphertext|args|params/i;

function safeMeta(meta: Record<string, string | number | boolean> | undefined): Record<string, string | number | boolean> | undefined {
  if (!meta) return undefined;
  const out: Record<string, string | number | boolean> = {};
  for (const [k, v] of Object.entries(meta)) {
    if (!/^[a-z][a-z0-9_.-]{0,40}$/i.test(k) || FORBIDDEN.test(k)) continue;
    if (typeof v === 'string') out[k] = v.slice(0, 120);
    else out[k] = v;
  }
  return Object.keys(out).length ? out : undefined;
}

export class AuditLog {
  readonly path: string;
  private readonly saltPath: string;
  private salt: Buffer;

  constructor(path = process.env.MEOS_MCP_AUDIT_LOG?.trim() || `${homedir()}/.meos/mcp/audit.log`) {
    this.path = resolve(path);
    this.saltPath = `${path}.salt`;
    mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
    try {
      chmodSync(dirname(path), 0o700);
    } catch {
      /* best effort */
    }
    this.salt = this.loadSalt();
  }

  private loadSalt(): Buffer {
    if (existsSync(this.saltPath)) {
      try {
        const salt = readFileSync(this.saltPath);
        if (salt.length >= 16) return salt;
      } catch {
        /* regenerate below */
      }
    }
    const salt = randomBytes(32);
    writeFileSync(this.saltPath, salt, { mode: 0o600 });
    return salt;
  }

  hash(value: string | undefined): string | undefined {
    if (!value) return undefined;
    return createHash('sha256').update(this.salt).update(value, 'utf8').digest('hex').slice(0, 32);
  }

  record(event: AuditEvent): void {
    const row: AuditRow = {
      ts: new Date().toISOString(),
      event: event.event.slice(0, 60),
      ...(event.client ? { client: event.client.slice(0, 80) } : {}),
      ...(event.tool ? { tool: event.tool.slice(0, 80) } : {}),
      ...(event.outcome ? { outcome: event.outcome } : {}),
      ...(event.ms != null ? { ms: Math.max(0, Math.round(event.ms)) } : {}),
      ...(event.requestId ? { request_id: event.requestId.slice(0, 64) } : {}),
      ...(event.ip ? { ip_hash: this.hash(event.ip) } : {}),
      ...(event.userAgent ? { ua_hash: this.hash(event.userAgent) } : {}),
      ...(safeMeta(event.meta) ? { meta: safeMeta(event.meta) } : {})
    };
    try {
      this.rotateIfNeeded();
      appendFileSync(this.path, JSON.stringify(row) + '\n', { mode: 0o600 });
    } catch {
      // Audit must not break the request. stderr is the fallback, metadata only.
      process.stderr.write(JSON.stringify({ event: 'audit_write_failed', at: row.ts }) + '\n');
    }
  }

  private rotateIfNeeded(): void {
    try {
      if (!existsSync(this.path)) return;
      if (statSync(this.path).size < 5 * 1024 * 1024) return;
      for (let i = 2; i >= 1; i--) {
        const from = `${this.path}.${i}`;
        if (existsSync(from)) renameSync(from, `${this.path}.${i + 1}`);
      }
      renameSync(this.path, `${this.path}.1`);
    } catch {
      /* if rotation fails, keep appending to the current file */
    }
  }

  /** Newest-first rows for the local dashboard. Bounded. */
  recent(limit = 100): AuditRow[] {
    try {
      if (!existsSync(this.path)) return [];
      const text = readFileSync(this.path, 'utf8');
      const lines = text.trim().split('\n').filter(Boolean);
      const out: AuditRow[] = [];
      for (const line of lines.slice(-Math.max(1, Math.min(500, limit)))) {
        try {
          out.push(JSON.parse(line) as AuditRow);
        } catch {
          /* skip a torn line */
        }
      }
      return out.reverse();
    } catch {
      return [];
    }
  }
}
