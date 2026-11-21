import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql, nowISO } from '$lib/server/db';
import { bumpStateVersion } from '$lib/server/stateVersion';
import { isAllowedStateKey, MAX_STATE_VALUE_BYTES } from '$lib/server/stateKeys';
import { utf8Bytes } from '$lib/server/http';

// Upsert one key of the logged-in user's app state.
export const PUT: RequestHandler = async ({ params, request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  if (!isAllowedStateKey(params.key)) throw error(400, 'Unknown state key');

  // Read and parse behind the same byte cap. `request.json()` would allocate an
  // oversized body before the check, and D1 rejects values above 2 MB anyway.
  const declared = Number(request.headers.get('content-length') ?? '');
  if (Number.isFinite(declared) && declared > MAX_STATE_VALUE_BYTES) {
    throw error(413, 'That is too large to sync');
  }
  const raw = await request.text().catch(() => {
    throw error(400, 'Body must be JSON');
  });
  if (utf8Bytes(raw) > MAX_STATE_VALUE_BYTES) throw error(413, 'That is too large to sync');
  let value: unknown;
  try {
    value = raw.trim() ? JSON.parse(raw) : {};
  } catch {
    throw error(400, 'Body must be JSON');
  }

  await sql`
    insert into app_state (user_id, key, value, updated_at)
    values (${locals.user.id}, ${params.key}, ${sql.json(value)}, ${nowISO()})
    on conflict (user_id, key) do update set value = excluded.value, updated_at = ${nowISO()}`;
  await bumpStateVersion(locals.user.id);
  return json({ ok: true });
};

// Delete one key of the logged-in user's app state (used to purge removed modules).
export const DELETE: RequestHandler = async ({ params, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  if (!params.key || params.key.length > 120) throw error(400, 'Bad key');
  // Deliberately NOT allowlisted: removed modules (myos.finance, myos.portfolio,
  // myos.networth) are purged by key, and those names are no longer in the set.
  await sql`delete from app_state where user_id = ${locals.user.id} and key = ${params.key}`;
  await bumpStateVersion(locals.user.id);
  return json({ ok: true });
};
