import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql, nowISO } from '$lib/server/db';
import { ensureConnections } from '$lib/server/mcpServer';

const MAX_CONNECTIONS = 10;

// The owner's MCP connections. Never returns anything secret: the token is
// shown once, in the app, at creation, and the server never had it.
export const GET: RequestHandler = async ({ locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  await ensureConnections();
  const rows = await sql`
    select id, name, created_at as createdAt, last_used_at as lastUsedAt
    from mcp_connections where user_id = ${locals.user.id} order by id desc`;
  return json({ connections: rows });
};

/** Body: { name, tokenHash, wrappedDek } — all made on the device. */
export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const body = await request.json().catch(() => ({}));
  const name = String(body.name ?? '').trim().slice(0, 60);
  const hash = String(body.tokenHash ?? '');
  const wrapped = String(body.wrappedDek ?? '');
  if (!name) throw error(400, 'Give the connection a name');
  if (!/^[0-9a-f]{64}$/.test(hash)) throw error(400, 'Bad token hash');
  // nonce(12) + 32-byte DEK + tag(16) = 60 bytes = 80 base64 chars.
  if (!/^[A-Za-z0-9+/]{80}$/.test(wrapped)) throw error(400, 'Bad wrapped key');

  await ensureConnections();
  const [count] = await sql`select count(*) as n from mcp_connections where user_id = ${locals.user.id}`;
  if (Number(count?.n ?? 0) >= MAX_CONNECTIONS) throw error(400, `At most ${MAX_CONNECTIONS} connections. Remove one first.`);

  const now = nowISO();
  await sql`
    insert into mcp_connections (user_id, name, token_hash, wrapped_dek, created_at)
    values (${locals.user.id}, ${name}, ${hash}, ${wrapped}, ${now})`;
  const [row] = await sql`
    select id, name, created_at as createdAt, last_used_at as lastUsedAt
    from mcp_connections where token_hash = ${hash}`;
  return json({ connection: row });
};
