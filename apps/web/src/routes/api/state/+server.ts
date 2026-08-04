import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';

// Return all of the logged-in user's app state as { key: value }.
export const GET: RequestHandler = async ({ locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const rows = await sql`select key, value from app_state where user_id = ${locals.user.id}`;
  const out: Record<string, unknown> = {};
  for (const r of rows) out[r.key] = r.value;
  return json(out);
};
