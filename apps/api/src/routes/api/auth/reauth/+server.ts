import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import {
  verifyPassword,
  loginAllowed,
  recordFailedLogin,
  clearFailedLogins,
  markReauth
} from '$lib/server/auth';
import { isMfaEnabled, verifySecondFactor } from '$lib/server/mfa';
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
 * Re-prove the login password (and MFA, when enabled) for a sensitive action:
 * exporting the vault, enrolling/disabling MFA, rotating server secrets, or
 * revoking sessions. The proof is recorded on this session for five minutes.
 * It never unlocks the vault and never returns a key.
 */
export const POST: RequestHandler = async ({ request, locals, getClientAddress }) => {
  const user = locals.user;
  const token = locals.sessionToken;
  if (!user || !token) throw error(401, 'Not signed in');

  const body = (await readJsonBody(request, 4_096)) as Record<string, unknown>;
  const password = String(body.password ?? '');
  const code = String(body.code ?? '').trim().slice(0, 64);
  const ip = ipOf(getClientAddress);
  const userAgent = request.headers.get('user-agent');

  if (!(await loginAllowed(user.username, ip))) {
    throw error(429, 'Too many attempts. Wait a few minutes and try again.');
  }

  const rows = await sql`select password_hash from users where id = ${user.id}`;
  if (!rows[0] || !(await verifyPassword(password, String(rows[0].password_hash)))) {
    await recordFailedLogin(user.username, ip);
    void audit({ event: 'reauth', outcome: 'failure', userId: user.id, ip, userAgent });
    throw error(403, 'That password is not correct.');
  }

  if (await isMfaEnabled(user.id)) {
    if (!code) {
      return json({ mfaRequired: true, message: 'Enter your authenticator code.' }, { status: 401 });
    }
    if (!(await verifySecondFactor(user.id, code))) {
      await recordFailedLogin(user.username, ip);
      void audit({ event: 'reauth', outcome: 'failure', userId: user.id, ip, userAgent, meta: { reason: 'mfa' } });
      throw error(403, 'That authenticator code is not valid.');
    }
  }

  await markReauth(token);
  await clearFailedLogins(user.username, ip);
  void audit({ event: 'reauth', outcome: 'success', userId: user.id, ip, userAgent });
  return json({ ok: true, validForSeconds: 300 });
};
