import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import { encryptSecret, maskKey } from '$lib/server/secrets';
import { listModels, PROVIDERS, type ProviderId } from '$lib/server/modelCatalog';
import { ensureAiTable } from '$lib/server/ai';
import { readJsonBody } from '$lib/server/http';
import { enforceRateLimit } from '$lib/server/security';
import { confirmSensitive } from '$lib/server/sensitive';
import { audit } from '$lib/server/audit';

const MAX_KEY_LENGTH = 4_096;

function ipOf(getClientAddress: () => string): string {
  try {
    return getClientAddress();
  } catch {
    return 'unknown';
  }
}

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

/**
 * Add a key: validate it live (which also fetches its models), then store it
 * encrypted. Connecting a new provider is a sensitive action, so it needs the
 * login password (or a fresh re-auth) in addition to the session.
 */
export const POST: RequestHandler = async ({ request, locals, getClientAddress }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  await ensureAiTable();
  enforceRateLimit(`ai-keys:${locals.user.id}`, 20, 60_000);

  const body = (await readJsonBody(request, 8_192)) as Record<string, unknown>;
  const ip = ipOf(getClientAddress);
  const proof = await confirmSensitive(
    locals.user,
    locals.sessionToken,
    { password: String(body.password ?? ''), code: String(body.code ?? '') },
    ip,
    true
  );
  if (!proof.ok) {
    void audit({ event: 'ai_key_add', outcome: 'denied', userId: locals.user.id, ip, meta: { reason: proof.reason } });
    if (proof.reason === 'rate_limited') throw error(429, 'Too many attempts. Wait a few minutes and try again.');
    return json(
      {
        reauthRequired: proof.reason === 'reauth_required',
        mfaRequired: proof.reason === 'mfa_required',
        message: proof.reason === 'mfa_required'
          ? 'Enter your authenticator code.'
          : 'Confirm your login password to add an AI provider.'
      },
      { status: 403 }
    );
  }

  const provider = String(body.provider ?? '') as ProviderId;
  const key = String(body.key ?? '').trim();
  const label = (String(body.label ?? '').trim() || provider).slice(0, 60);

  if (!PROVIDERS.includes(provider)) throw error(400, 'Unknown provider');
  if (key.length < 8) throw error(400, 'Enter a valid API key');
  if (key.length > MAX_KEY_LENGTH) throw error(400, 'That API key is too long');

  const res = await listModels(provider, key);
  if (!res.ok) throw error(400, 'The provider rejected that key.');

  const enc = await encryptSecret(key);
  const rows = await sql`
    insert into ai_credentials (user_id, provider, label, secret, masked, models)
    values (${locals.user.id}, ${provider}, ${label}, ${enc}, ${maskKey(key)}, ${sql.json(res.models)})
    returning id, provider, label, masked, enabled, models`;
  void audit({
    event: 'ai_key_add',
    outcome: 'success',
    userId: locals.user.id,
    ip,
    userAgent: request.headers.get('user-agent'),
    meta: { provider, models: res.models.length }
  });
  return json({ key: rows[0], models: res.models });
};
