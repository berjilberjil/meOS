import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql, nowISO } from '$lib/server/db';

/**
 * The keys a client is allowed to write, mirroring `StateKey` in the app plus
 * the vault's own metadata row.
 *
 * The route used to take any key name at all, with no cap on the body either.
 * One authenticated account could loop `PUT /api/state/<random-uuid>` with a
 * large payload and consume the shared D1 database and the account-wide
 * 100k-writes-a-day free quota — stopping sync for every other user. An
 * allowlist is also the cheaper guard: it rejects before touching the database.
 */
const KEYS = new Set([
  'myos.fitness', 'myos.fitnessProfile', 'myos.journal', 'myos.journalPresets',
  'myos.notes', 'myos.days', 'myos.profile', 'myos.chat', 'myos.nutrition',
  'myos.training', 'myos.events', 'myos.eventTags', 'myos.watch',
  'myos.belongings', 'myos.fold', 'myos.memory', 'myos.scans', 'myos.taskMode',
  'myos.weekly', 'myos.activity', 'myos.appearance', 'myos.crypto'
]);

/** Well clear of the largest real blob, well under what would hurt the DB. */
const MAX_VALUE_BYTES = 8_000_000;

// Upsert one key of the logged-in user's app state.
export const PUT: RequestHandler = async ({ params, request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  if (!KEYS.has(params.key)) throw error(400, 'Unknown state key');
  // Every other route catches this; without it a malformed body 500s, and a 500
  // is retried four times by the client.
  const value = await request.json().catch(() => {
    throw error(400, 'Body must be JSON');
  });
  if (JSON.stringify(value ?? null).length > MAX_VALUE_BYTES) {
    throw error(413, 'That is too large to sync');
  }
  await sql`
    insert into app_state (user_id, key, value, updated_at)
    values (${locals.user.id}, ${params.key}, ${sql.json(value)}, ${nowISO()})
    on conflict (user_id, key) do update set value = excluded.value, updated_at = ${nowISO()}`;
  return json({ ok: true });
};

// Delete one key of the logged-in user's app state (used to purge removed modules).
export const DELETE: RequestHandler = async ({ params, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  // Deliberately NOT allowlisted: removed modules (myos.finance, myos.portfolio,
  // myos.networth) are purged by key, and those names are no longer in KEYS.
  await sql`delete from app_state where user_id = ${locals.user.id} and key = ${params.key}`;
  return json({ ok: true });
};
