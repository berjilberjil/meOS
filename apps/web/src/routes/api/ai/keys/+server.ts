import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import { encryptSecret, maskKey } from '$lib/server/secrets';
import { listModels, PROVIDERS, type ProviderId } from '$lib/server/modelCatalog';
import { ensureAiTable } from '$lib/server/ai';

/** List the user's AI provider keys — masked, never the raw secret. */
export const GET: RequestHandler = async ({ locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  await ensureAiTable();
  const keys = await sql`
    select id, provider, label, masked, enabled, models
    from ai_credentials where user_id = ${locals.user.id}
    order by created_at asc`;
  return json({ keys });
};

/** Add a key: validate it live (which also fetches its models), then store encrypted. */
export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  await ensureAiTable();

  const body = await request.json().catch(() => ({}));
  const provider = String(body.provider ?? '') as ProviderId;
  const key = String(body.key ?? '').trim();
  const label = (String(body.label ?? '').trim() || provider).slice(0, 60);

  if (!PROVIDERS.includes(provider)) throw error(400, 'Unknown provider');
  if (key.length < 8) throw error(400, 'Enter a valid API key');

  const res = await listModels(provider, key);
  if (!res.ok) throw error(400, `Key check failed: ${res.error ?? 'invalid key'}`);

  const rows = await sql`
    insert into ai_credentials (user_id, provider, label, secret, masked, models)
    values (${locals.user.id}, ${provider}, ${label}, ${encryptSecret(key)}, ${maskKey(key)}, ${sql.json(res.models)})
    returning id, provider, label, masked, enabled, models`;
  return json({ key: rows[0], models: res.models });
};
