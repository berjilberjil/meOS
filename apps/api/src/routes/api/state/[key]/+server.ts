import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';

// Upsert one key of the logged-in user's app state.
export const PUT: RequestHandler = async ({ params, request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const value = await request.json();
  await sql`
    insert into app_state (user_id, key, value, updated_at)
    values (${locals.user.id}, ${params.key}, ${sql.json(value)}, now())
    on conflict (user_id, key) do update set value = excluded.value, updated_at = now()`;
  return json({ ok: true });
};

// Delete one key of the logged-in user's app state (used to purge removed modules).
export const DELETE: RequestHandler = async ({ params, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  await sql`delete from app_state where user_id = ${locals.user.id} and key = ${params.key}`;
  return json({ ok: true });
};
