import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql, nowISO } from '$lib/server/db';
import { decryptSecret } from '$lib/server/secrets';
import { listModels, type ProviderId } from '$lib/server/modelCatalog';

/** Re-validate a stored key and refresh its cached model list. */
export const POST: RequestHandler = async ({ params, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const id = Number(params.id);
  if (!Number.isFinite(id)) throw error(400, 'Bad id');

  const rows = await sql`select provider, secret from ai_credentials where id = ${id} and user_id = ${locals.user.id}`;
  if (!rows.length) throw error(404, 'Key not found');

  let apiKey: string;
  try {
    apiKey = await decryptSecret(rows[0].secret as string);
  } catch {
    throw error(500, 'Could not decrypt this key — MEOS_SECRETS_KEY may have changed. Re-enter it.');
  }

  const res = await listModels(rows[0].provider as ProviderId, apiKey);
  if (!res.ok) throw error(400, `Key check failed: ${res.error ?? 'invalid key'}`);

  await sql`update ai_credentials set models = ${sql.json(res.models)}, updated_at = ${nowISO()}
            where id = ${id} and user_id = ${locals.user.id}`;
  return json({ ok: true, models: res.models });
};
