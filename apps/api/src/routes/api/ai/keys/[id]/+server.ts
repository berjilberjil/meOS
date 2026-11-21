import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql, nowISO } from '$lib/server/db';
import { encryptSecret, maskKey } from '$lib/server/secrets';
import { ensureAiTable } from '$lib/server/ai';
import { listModels, type ProviderId } from '$lib/server/modelCatalog';
import { readJsonBody } from '$lib/server/http';
import { confirmSensitive } from '$lib/server/sensitive';
import { audit } from '$lib/server/audit';

function ipOf(getClientAddress: () => string): string {
  try {
    return getClientAddress();
  } catch {
    return 'unknown';
  }
}

async function proofResponse(
  proof: Awaited<ReturnType<typeof confirmSensitive>>,
  action: string
): Promise<Response> {
  if (proof.ok) throw new Error('unreachable');
  return json(
    {
      reauthRequired: proof.reason === 'reauth_required',
      mfaRequired: proof.reason === 'mfa_required',
      message:
        proof.reason === 'mfa_required'
          ? 'Enter your authenticator code.'
          : `Confirm your login password to ${action}.`
    },
    { status: proof.reason === 'rate_limited' ? 429 : 403 }
  );
}

/** Update a key: rename, enable/disable, or replace the secret (re-validated). */
export const PATCH: RequestHandler = async ({ params, request, locals, getClientAddress }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  await ensureAiTable();
  const id = Number(params.id);
  if (!Number.isFinite(id)) throw error(400, 'Bad id');

  const owned = await sql`select provider from ai_credentials where id = ${id} and user_id = ${locals.user.id}`;
  if (!owned.length) throw error(404, 'Key not found');
  const provider = owned[0].provider as ProviderId;

  const body = (await readJsonBody(request, 8_192)) as Record<string, unknown>;
  const ip = ipOf(getClientAddress);

  if (typeof body.key === 'string') {
    const proof = await confirmSensitive(
      locals.user,
      locals.sessionToken,
      { password: String(body.password ?? ''), code: String(body.code ?? '') },
      ip,
      true
    );
    if (!proof.ok) return proofResponse(proof, 'replace this AI key');

    const k = body.key.trim();
    if (k.length < 8) throw error(400, 'Enter a valid API key');
    if (k.length > 4_096) throw error(400, 'That API key is too long');
    const res = await listModels(provider, k);
    if (!res.ok) throw error(400, 'The provider rejected that key.');
    const enc = await encryptSecret(k);
    await sql`update ai_credentials
              set secret = ${enc}, masked = ${maskKey(k)}, models = ${sql.json(res.models)}, updated_at = ${nowISO()}
              where id = ${id} and user_id = ${locals.user.id}`;
    void audit({
      event: 'ai_key_replace',
      outcome: 'success',
      userId: locals.user.id,
      ip,
      meta: { provider }
    });
  }

  if (typeof body.label === 'string') {
    await sql`update ai_credentials set label = ${body.label.slice(0, 60)}, updated_at = ${nowISO()}
              where id = ${id} and user_id = ${locals.user.id}`;
  }
  if (typeof body.enabled === 'boolean') {
    await sql`update ai_credentials set enabled = ${body.enabled}, updated_at = ${nowISO()}
              where id = ${id} and user_id = ${locals.user.id}`;
  }

  const out = await sql`
    select id, provider, label, masked, enabled, models
    from ai_credentials where id = ${id} and user_id = ${locals.user.id}`;
  return json({ key: out[0] });
};

export const DELETE: RequestHandler = async ({ params, request, locals, getClientAddress }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  await ensureAiTable();
  const id = Number(params.id);
  if (!Number.isFinite(id)) throw error(400, 'Bad id');

  const body = (await readJsonBody(request, 4_096)) as Record<string, unknown>;
  const ip = ipOf(getClientAddress);
  const proof = await confirmSensitive(
    locals.user,
    locals.sessionToken,
    { password: String(body.password ?? ''), code: String(body.code ?? '') },
    ip,
    true
  );
  if (!proof.ok) return proofResponse(proof, 'delete this AI key');

  await sql`delete from ai_credentials where id = ${id} and user_id = ${locals.user.id}`;
  void audit({ event: 'ai_key_delete', outcome: 'success', userId: locals.user.id, ip, meta: { key_id: id } });
  return json({ ok: true });
};
