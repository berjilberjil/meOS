import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql, nowISO } from '$lib/server/db';
import { bumpStateVersion } from '$lib/server/stateVersion';
import { MAX_STATE_VALUE_BYTES } from '$lib/server/stateKeys';
import { readJsonBody } from '$lib/server/http';
import { enforceRateLimit } from '$lib/server/security';
import { audit } from '$lib/server/audit';

/**
 * Per-feature model routing for the logged-in user. Non-secret (just references to
 * key ids + model names), so it rides in app_state and syncs across devices like the
 * rest of the user's state. Shape: { default?: {keyId,model}, features?: {chat?: …} }.
 */
const KEY = 'meos.ai.routes';
const LEGACY_KEY = 'myos.ai.routes';

export const GET: RequestHandler = async ({ locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  enforceRateLimit(`ai-routes-get:${locals.user.id}`, 60, 60_000);
  const rows = await sql`select value from app_state where user_id = ${locals.user.id} and key = ${KEY}`;
  if (rows.length) return json(rows[0].value);
  const legacy = await sql`select value from app_state where user_id = ${locals.user.id} and key = ${LEGACY_KEY}`;
  return json(legacy.length ? legacy[0].value : {});
};

export const PUT: RequestHandler = async ({ request, locals, getClientAddress }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  enforceRateLimit(`ai-routes-put:${locals.user.id}`, 60, 60_000);
  const body = await readJsonBody(request, MAX_STATE_VALUE_BYTES);
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw error(400, 'Routing must be a JSON object');
  }
  await sql`
    insert into app_state (user_id, key, value, updated_at)
    values (${locals.user.id}, ${KEY}, ${sql.json(body)}, ${nowISO()})
    on conflict (user_id, key) do update set value = excluded.value, updated_at = ${nowISO()}`;
  // Without this the state GET's ETag never moves, so every other device keeps
  // getting a 304 and never observes the new routing document.
  await bumpStateVersion(locals.user.id);
  let ip = 'unknown';
  try {
    ip = getClientAddress();
  } catch {
    /* local/test */
  }
  void audit({
    event: 'ai_routes_write',
    outcome: 'success',
    userId: locals.user.id,
    ip,
    userAgent: request.headers.get('user-agent')
  });
  return json({ ok: true });
};
