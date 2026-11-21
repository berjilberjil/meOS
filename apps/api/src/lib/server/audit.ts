import { env } from '$env/dynamic/private';
import { nowISO, sql } from './db';

/**
 * Security audit trail.
 *
 * This table is intentionally *metadata only*. It answers "who did what, from
 * where, and did it work" without becoming a second copy of the vault:
 *
 *   - never a request body, note text, journal entry, amount or file name;
 *   - never a token, password, passphrase, API key or ciphertext;
 *   - IP addresses are stored as a salted hash, not raw;
 *   - user agents are truncated and control characters are stripped.
 *
 * Writes are best-effort. An audit failure must not turn a successful login or
 * a completed state write into a 500. The trade-off is documented in
 * SECURITY.md: if D1 is unavailable the security event is lost with it.
 */

export type AuditOutcome = 'success' | 'failure' | 'denied' | 'error';

export interface AuditInput {
  event: string;
  outcome: AuditOutcome;
  userId?: number | null;
  ip?: string | null;
  userAgent?: string | null;
  /** Allowlisted, non-content metadata only. See `cleanMeta`. */
  meta?: Record<string, unknown>;
}

const MAX_META_KEYS = 12;
const MAX_META_STRING = 120;

/** Keys that must never reach the audit table, even by accident. */
const FORBIDDEN_META =
  /token|authorization|cookie|password|passphrase|secret|api[-_]?key|ciphertext|body|content|note|journal|amount|balance|account[-_]?number|card|otp|mfa[-_]?secret/i;

function text(value: unknown, max = MAX_META_STRING): string | null {
  if (typeof value !== 'string') return null;
  return (
    value
      .replace(/[\u0000-\u001f\u007f]/g, '')
      .trim()
      .slice(0, max) || null
  );
}

export function cleanMeta(meta: Record<string, unknown> | undefined): string | null {
  if (!meta) return null;
  const out: Record<string, string | number | boolean> = {};
  let n = 0;
  for (const [key, value] of Object.entries(meta)) {
    if (n >= MAX_META_KEYS) break;
    if (!/^[a-z][a-z0-9_.-]{0,40}$/i.test(key) || FORBIDDEN_META.test(key)) continue;
    if (typeof value === 'string') {
      const v = text(value);
      if (v) out[key] = v;
    } else if (typeof value === 'number' && Number.isFinite(value)) {
      out[key] = Math.trunc(value);
    } else if (typeof value === 'boolean') {
      out[key] = value;
    }
    n++;
  }
  return Object.keys(out).length ? JSON.stringify(out) : null;
}

/** Salted, stable pseudonym for an IP address. Never reversible in practice. */
export async function hashIp(ip: string | null | undefined): Promise<string | null> {
  const value = text(ip, 200);
  if (!value) return null;
  const salt =
    env.MEOS_AUDIT_SALT ||
    env.MEOS_SECRETS_KEY ||
    env.MYOS_SECRETS_KEY ||
    'meos-audit-no-salt';
  const data = new TextEncoder().encode(`${salt}\n${value}`);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(digest)].slice(0, 16).map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function cleanUserAgent(ua: string | null | undefined): string | null {
  return text(ua, 160);
}

let ensured = false;
async function ensureAuditTable(): Promise<void> {
  if (ensured) return;
  await sql`
    create table if not exists security_events (
      id         integer primary key autoincrement,
      at         text not null,
      user_id    integer,
      event      text not null,
      outcome    text not null,
      ip_hash    text,
      user_agent text,
      meta       text
    )`;
  await sql`create index if not exists security_events_user_at_idx on security_events(user_id, at)`;
  await sql`create index if not exists security_events_event_at_idx on security_events(event, at)`;
  ensured = true;
}

/** Record one security event. Never throws. */
export async function audit(input: AuditInput): Promise<void> {
  try {
    await ensureAuditTable();
    const ipHash = await hashIp(input.ip ?? null);
    await sql`
      insert into security_events (at, user_id, event, outcome, ip_hash, user_agent, meta)
      values (${nowISO()}, ${input.userId ?? null}, ${input.event.slice(0, 80)}, ${input.outcome},
              ${ipHash}, ${cleanUserAgent(input.userAgent)}, ${cleanMeta(input.meta)})`;

    // Keep the table bounded without a scheduled job. 1-in-200 writes is enough
    // at this app's volume; the delete is indexed by `at` only through the
    // user index, so use the event/time index where possible.
    if (Math.random() < 0.005) {
      const cutoff = new Date(Date.now() - 180 * 24 * 60 * 60 * 1000).toISOString();
      await sql`delete from security_events where at < ${cutoff}`;
    }
  } catch {
    // Audit must never be able to break the request it is observing.
  }
}

export interface SecurityEventRow {
  id: number;
  at: string;
  event: string;
  outcome: string;
  ipHash: string | null;
  userAgent: string | null;
  meta: unknown;
}

/** Newest events for one owner. No other user's rows are ever selected. */
export async function listSecurityEvents(userId: number, limit = 100): Promise<SecurityEventRow[]> {
  await ensureAuditTable();
  const capped = Math.max(1, Math.min(500, Math.trunc(limit)));
  const rows = await sql`
    select id, at, event, outcome, ip_hash, user_agent, meta
    from security_events
    where user_id = ${userId}
    order by at desc, id desc
    limit ${capped}`;
  return rows.map((r) => ({
    id: Number(r.id),
    at: String(r.at),
    event: String(r.event),
    outcome: String(r.outcome),
    ipHash: r.ip_hash == null ? null : String(r.ip_hash),
    userAgent: r.user_agent == null ? null : String(r.user_agent),
    meta: r.meta ?? null
  }));
}

/** Count failures of one event type for a user since a cutoff (for alerts). */
export async function countRecent(
  userId: number,
  event: string,
  outcome: AuditOutcome,
  sinceISO: string,
  includeAnonymous = false
): Promise<number> {
  await ensureAuditTable();
  const rows = includeAnonymous
    ? await sql`
        select count(*) as n from security_events
        where (user_id = ${userId} or user_id is null)
          and event = ${event} and outcome = ${outcome} and at >= ${sinceISO}`
    : await sql`
        select count(*) as n from security_events
        where user_id = ${userId} and event = ${event} and outcome = ${outcome} and at >= ${sinceISO}`;
  return Number(rows[0]?.n ?? 0);
}
