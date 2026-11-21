import { error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import { etagMatches } from '$lib/server/etag';
import { readStateVersion } from '$lib/server/stateVersion';

// Return all of the logged-in user's app state as { key: value }.
export const GET: RequestHandler = async ({ locals, request }) => {
  if (!locals.user) throw error(401, 'Not logged in');

  const etag = await readStateVersion(locals.user.id);

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
