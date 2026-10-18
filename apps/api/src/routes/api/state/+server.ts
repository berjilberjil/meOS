import { error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import { etagMatches } from '$lib/server/etag';

/**
 * ETag for a user's whole state: newest write + row count. `updated_at` is
 * bumped on every upsert (see [key]/+server.ts), and the count catches DELETEs,
 * which remove a row rather than touching a timestamp.
 *
 * This exists because the clients poll this endpoint every few seconds. Without
 * a 304 they re-download the entire state — megabytes — just to be told nothing
 * changed. That is what put the project 1,254% over its egress quota.
 */
function stateETag(newest: string | null, count: number): string {
  return `"${newest ? new Date(newest).getTime() : 0}-${count}"`;
}

/**
 * One indexed row per user, bumped by every write.
 *
 * The ETag used to be `max(updated_at), count(*)` over `app_state`, which has no
 * covering index — so every poll scanned all of that user's ~24 rows, and a 200
 * paid for the scan twice. At a 1.5s foreground poll that is ~1.5 M rows read
 * per day per foregrounded device, against a D1 free tier of 5 M rows/day that
 * is shared by every user: three or four active devices exhausted it, and D1
 * then rejects every query for everyone until midnight UTC.
 */
let versionsReady = false;
async function ensureVersions(): Promise<void> {
  if (versionsReady) return;
  await sql`
    create table if not exists state_version (
      user_id integer primary key,
      version integer not null default 0,
      at      text not null
    )`;
  versionsReady = true;
}

/** The user's current state version, seeded from the table it replaces. */
async function stateVersion(userId: number): Promise<string> {
  await ensureVersions();
  const rows = await sql`select version, at from state_version where user_id = ${userId}`;
  if (rows.length) return `"v${rows[0].version}-${new Date(String(rows[0].at)).getTime()}"`;
  // First read after the upgrade: fall back to the old shape once, so a client
  // holding the previous ETag is not told "unchanged" by accident.
  const [meta] = await sql`
    select max(updated_at) as newest, count(*) as count
    from app_state where user_id = ${userId}`;
  return stateETag(meta?.newest ?? null, Number(meta?.count ?? 0));
}

// Return all of the logged-in user's app state as { key: value }.
export const GET: RequestHandler = async ({ locals, request }) => {
  if (!locals.user) throw error(401, 'Not logged in');

  const etag = await stateVersion(locals.user.id);

  // Cheap path: the client already has this exact state.
  if (etagMatches(request.headers.get('if-none-match'), etag)) {
    return new Response(null, { status: 304, headers: { ETag: etag } });
  }

  // Every value is already JSON text, so splice it in raw. Selecting `value`
  // would have `sql` JSON.parse each one only for `json()` to stringify it
  // straight back — the bulk of this route's CPU against a 10ms budget.
  const rows = await sql`select key, value as raw from app_state where user_id = ${locals.user.id}`;
  const body = '{' + rows.map((r) => `${JSON.stringify(r.key)}:${r.raw}`).join(',') + '}';
  return new Response(body, {
    headers: { 'Content-Type': 'application/json', ETag: etag }
  });
};
