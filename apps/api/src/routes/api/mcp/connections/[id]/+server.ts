import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import { ensureConnections } from '$lib/server/mcpServer';

/** Revoke a connection. Its token stops working on the very next request. */
export const DELETE: RequestHandler = async ({ params, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const id = Number(params.id);
  if (!Number.isInteger(id)) throw error(400, 'Bad id');
  await ensureConnections();
  await sql`delete from mcp_connections where id = ${id} and user_id = ${locals.user.id}`;
  return json({ ok: true });
};
