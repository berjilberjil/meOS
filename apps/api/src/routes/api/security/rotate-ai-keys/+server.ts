import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql, nowISO } from '$lib/server/db';
import { activeSecretsKeyId, rotateSecret } from '$lib/server/secrets';
import { ensureAiTable } from '$lib/server/ai';
import { mfaStatus } from '$lib/server/mfa';
import { confirmSensitive } from '$lib/server/sensitive';
import { enforceRateLimit } from '$lib/server/security';
import { readJsonBody } from '$lib/server/http';
import { audit } from '$lib/server/audit';

function ipOf(getClientAddress: () => string): string {
  try {
    return getClientAddress();
  } catch {
    return 'unknown';
  }
}

/**
 * Re-encrypt server-held secrets under the active `MEOS_SECRETS_KEYS` entry.
 *
 * Procedure: add the new key to the ring, point `MEOS_SECRETS_KEY_ID` at it,
 * deploy, then call this once with the login password (and MFA code). Keep the
 * old key in the ring until this returns — it decrypts the rows being migrated.
 * Never remove a key that is still referenced by ciphertext.
 */
export const POST: RequestHandler = async ({ locals, request, getClientAddress }) => {
  const user = locals.user;
  const token = locals.sessionToken;
  if (!user || !token) throw error(401, 'Not signed in');
  enforceRateLimit(`rotate-secrets:${user.id}`, 3, 60 * 60 * 1000);

  const body = (await readJsonBody(request, 4_096)) as Record<string, unknown>;
  const ip = ipOf(getClientAddress);
  const proof = await confirmSensitive(
    user,
    token,
    { password: String(body.password ?? ''), code: String(body.code ?? '') },
    ip,
    true
  );
  if (!proof.ok) {
    return json(
      {
        reauthRequired: proof.reason === 'reauth_required',
        mfaRequired: proof.reason === 'mfa_required',
        message: proof.reason === 'mfa_required'
          ? 'Enter your authenticator code.'
          : 'Confirm your login password before rotating server secrets.'
      },
      { status: proof.reason === 'rate_limited' ? 429 : 403 }
    );
  }

  let rotated = 0;
  // Ensures the AI/MFA tables exist on a database that predates them.
  await ensureAiTable();
  await mfaStatus(user.id);
  const keys = await sql`select id, secret from ai_credentials where user_id = ${user.id}`;
  for (const row of keys) {
    const next = await rotateSecret(String(row.secret));
    await sql`update ai_credentials set secret = ${next}, updated_at = ${nowISO()}
              where id = ${row.id} and user_id = ${user.id}`;
    rotated++;
  }

  const mfa = await sql`select secret from user_mfa where user_id = ${user.id}`;
  if (mfa[0]?.secret) {
    const next = await rotateSecret(String(mfa[0].secret));
    await sql`update user_mfa set secret = ${next} where user_id = ${user.id}`;
  }

  void audit({
    event: 'secrets_rotate',
    outcome: 'success',
    userId: user.id,
    ip,
    userAgent: request.headers.get('user-agent'),
    meta: { active_key: activeSecretsKeyId(), rows: rotated }
  });
  return json({ ok: true, activeKey: activeSecretsKeyId(), rotated });
};
