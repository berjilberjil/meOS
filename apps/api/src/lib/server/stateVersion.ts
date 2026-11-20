import { nowISO, sql } from './db';

/**
 * One indexed row per user, bumped by every write that changes `/api/state`.
 *
 * `state_version` exists because the client polls `/api/state` every few
 * seconds. Deriving the ETag from `max(updated_at), count(*)` over `app_state`
 * scans every row of that user's state on every poll; at a 1.5s foreground poll
 * that was ~1.5M rows read per day per device against a shared free tier.
 */

/** The ETag shape used before `state_version` existed (and as a one-time fallback). */
export function stateETag(newest: string | null, count: number): string {
  return `"${newest ? new Date(newest).getTime() : 0}-${count}"`;
}

function versionETag(version: number, at: string): string {
  return `"v${version}-${new Date(at).getTime()}"`;
}

// A boolean, NOT a shared promise: awaiting I/O that belongs to another request
// is rejected by the Workers runtime. `create table if not exists` is cheap and
// idempotent once the table exists.
let ready = false;
async function ensureStateVersionTable(): Promise<void> {
  if (ready) return;
  await sql`
    create table if not exists state_version (
      user_id integer primary key,
      version integer not null default 0,
      at      text not null
    )`;
  ready = true;
}

/** The user's current state version, seeded from `app_state` on first read. */
export async function readStateVersion(userId: number): Promise<string> {
  await ensureStateVersionTable();
  const rows = await sql`select version, at from state_version where user_id = ${userId}`;
  if (rows.length) return versionETag(Number(rows[0].version), String(rows[0].at));

  // First read after the upgrade: fall back to the old shape once, so a client
  // holding the previous ETag is not told "unchanged" by accident.
  const [meta] = await sql`
    select max(updated_at) as newest, count(*) as count
    from app_state where user_id = ${userId}`;
  return stateETag(meta?.newest ?? null, Number(meta?.count ?? 0));
}

/** Move the user's version on. Called by every route that writes `app_state`. */
export async function bumpStateVersion(userId: number): Promise<void> {
  await ensureStateVersionTable();
  const now = nowISO();
  await sql`
    insert into state_version (user_id, version, at) values (${userId}, 1, ${now})
    on conflict (user_id) do update set version = state_version.version + 1, at = ${now}`;
}
