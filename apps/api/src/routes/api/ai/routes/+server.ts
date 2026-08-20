import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql, nowISO } from '$lib/server/db';

/**
 * Per-feature model routing for the logged-in user. Non-secret (just references to
 * key ids + model names), so it rides in app_state and syncs across devices like the
 * rest of the user's state. Shape: { default?: {keyId,model}, features?: {chat?: …} }.
 */
const KEY = 'myos.ai.routes';

export const GET: RequestHandler = async ({ locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const rows = await sql`select value from app_state where user_id = ${locals.user.id} and key = ${KEY}`;
  return json(rows.length ? rows[0].value : {});
};

export const PUT: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const value = await request.json().catch(() => ({}));
  await sql`
    insert into app_state (user_id, key, value, updated_at)
    values (${locals.user.id}, ${KEY}, ${sql.json(value)}, ${nowISO()})
    on conflict (user_id, key) do update set value = excluded.value, updated_at = ${nowISO()}`;
  return json({ ok: true });
};
