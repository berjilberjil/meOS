import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';

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

// Return all of the logged-in user's app state as { key: value }.
export const GET: RequestHandler = async ({ locals, request, setHeaders }) => {
  if (!locals.user) throw error(401, 'Not logged in');

  const [meta] = await sql`
    select max(updated_at) as newest, count(*) as count
    from app_state where user_id = ${locals.user.id}`;
  const etag = stateETag(meta?.newest ?? null, Number(meta?.count ?? 0));

  // Cheap path: the client already has this exact state.
  if (request.headers.get('if-none-match') === etag) {
    return new Response(null, { status: 304, headers: { ETag: etag } });
  }

  const rows = await sql`select key, value from app_state where user_id = ${locals.user.id}`;
  const out: Record<string, unknown> = {};
  for (const r of rows) out[r.key] = r.value;
  setHeaders({ ETag: etag });
  return json(out);
};
