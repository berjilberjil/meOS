import { sql, nowISO } from '$lib/server/db';
import { tokenHash, unwrapDek, openState } from '$lib/server/mcpVault';
import { handleRpc, visibleNotes, type NoteRecord } from '$lib/server/mcpNotes';

/**
 * MCP connections: one row per AI app the owner has connected, created and
 * revoked from Settings → AI connections. Holds only `sha256(token)` and the
 * DEK sealed under a key derived from the token (see mcpVault.ts), so a
 * database leak alone opens nothing. Deleting the row revokes the token.
 */
let tableReady = false;
export async function ensureConnections(): Promise<void> {
  if (tableReady) return;
  await sql`
    create table if not exists mcp_connections (
      id           integer primary key autoincrement,
      user_id      integer not null references users(id) on delete cascade,
      name         text not null,
      token_hash   text not null unique,
      wrapped_dek  text not null,
      created_at   text not null,
      last_used_at text
    )`;
  tableReady = true;
}

/** No cookies are involved, so any origin may call; the bearer token is the auth. */
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type, Accept, Mcp-Protocol-Version, Mcp-Session-Id',
  'Access-Control-Expose-Headers': 'WWW-Authenticate'
};

function reply(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: { ...CORS, ...(body === null ? {} : { 'Content-Type': 'application/json' }), ...extra }
  });
}

function unauthorized(message: string): Response {
  return reply({ jsonrpc: '2.0', id: null, error: { code: -32001, message } }, 401, {
    'WWW-Authenticate': 'Bearer realm="meos"'
  });
}

export function preflight(): Response {
  return new Response(null, { status: 204, headers: CORS });
}

/** Stateless Streamable HTTP: no server-to-client stream to open. */
export function noStream(): Response {
  return new Response('This MCP server is stateless; POST JSON-RPC to this URL.', {
    status: 405,
    headers: { ...CORS, Allow: 'POST, OPTIONS' }
  });
}

/** Handle one MCP POST. `urlToken` is set when the token came in the path. */
export async function serveMcp(request: Request, urlToken?: string): Promise<Response> {
  const auth = request.headers.get('authorization') ?? '';
  const token = (auth.match(/^Bearer\s+(\S+)$/i)?.[1] ?? urlToken ?? '').trim();
  if (!token) return unauthorized('Missing token. Create a connection in MeOS → Settings → AI connections.');

  await ensureConnections();
  const hash = await tokenHash(token);
  const rows = await sql`select id, user_id, wrapped_dek, last_used_at from mcp_connections where token_hash = ${hash}`;
  if (!rows.length) return unauthorized('This connection was revoked or never existed.');
  const conn = rows[0];

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return reply({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } }, 400);
  }

  // Decrypt at most once per request, and only if a tool actually needs it.
  let notes: Promise<NoteRecord[]> | null = null;
  const loadNotes = () =>
    (notes ??= (async () => {
      const dek = await unwrapDek(token, String(conn.wrapped_dek));
      if (!dek) throw new Error('This connection no longer matches your vault. Create a new one in MeOS.');
      const found = await sql`
        select key, value from app_state
        where user_id = ${conn.user_id} and key in ('meos.notes', 'myos.notes')`;
      const row = found.find((r) => r.key === 'meos.notes') ?? found[0];
      if (!row) return [];
      return visibleNotes(await openState(row.value, dek, String(row.key)));
    })());

  const answer = async (msg: unknown) => {
    try {
      return await handleRpc(msg as Parameters<typeof handleRpc>[0], loadNotes);
    } catch (e) {
      const id = (msg as { id?: unknown })?.id ?? null;
      return { jsonrpc: '2.0', id, error: { code: -32603, message: e instanceof Error ? e.message : 'Internal error' } };
    }
  };

  const out = Array.isArray(body)
    ? (await Promise.all(body.map(answer))).filter((r) => r !== null)
    : await answer(body);

  // "Last used" in Settings. Hourly is plenty, and spares a D1 write per call.
  const hourAgo = new Date(Date.now() - 3_600_000).toISOString();
  if (!conn.last_used_at || String(conn.last_used_at) < hourAgo) {
    await sql`update mcp_connections set last_used_at = ${nowISO()} where id = ${conn.id}`;
  }

  if (out === null || (Array.isArray(out) && !out.length)) return reply(null, 202);
  return reply(out);
}
