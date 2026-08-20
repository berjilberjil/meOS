import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql, nowISO } from '$lib/server/db';
import { encryptSecret, maskKey } from '$lib/server/secrets';
import { listModels, type ProviderId } from '$lib/server/modelCatalog';

/** Update a key: rename, enable/disable, or replace the secret (re-validated). */
export const PATCH: RequestHandler = async ({ params, request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const id = Number(params.id);
  if (!Number.isFinite(id)) throw error(400, 'Bad id');

  const owned = await sql`select provider from ai_credentials where id = ${id} and user_id = ${locals.user.id}`;
  if (!owned.length) throw error(404, 'Key not found');
  const provider = owned[0].provider as ProviderId;

  const body = await request.json().catch(() => ({}));

  if (typeof body.label === 'string') {
    await sql`update ai_credentials set label = ${body.label.slice(0, 60)}, updated_at = ${nowISO()}
              where id = ${id} and user_id = ${locals.user.id}`;
  }
  if (typeof body.enabled === 'boolean') {
    await sql`update ai_credentials set enabled = ${body.enabled}, updated_at = ${nowISO()}
              where id = ${id} and user_id = ${locals.user.id}`;
  }
  if (typeof body.key === 'string' && body.key.trim().length >= 8) {
    const k = body.key.trim();
    const res = await listModels(provider, k);
    if (!res.ok) throw error(400, `Key check failed: ${res.error ?? 'invalid key'}`);
    await sql`update ai_credentials
              set secret = ${encryptSecret(k)}, masked = ${maskKey(k)}, models = ${sql.json(res.models)}, updated_at = ${nowISO()}
              where id = ${id} and user_id = ${locals.user.id}`;
  }

  const out = await sql`
    select id, provider, label, masked, enabled, models
    from ai_credentials where id = ${id} and user_id = ${locals.user.id}`;
  return json({ key: out[0] });
};

export const DELETE: RequestHandler = async ({ params, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const id = Number(params.id);
  if (!Number.isFinite(id)) throw error(400, 'Bad id');
  await sql`delete from ai_credentials where id = ${id} and user_id = ${locals.user.id}`;
  return json({ ok: true });
};
