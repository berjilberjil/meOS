import { sql } from '$lib/server/db';
import {
  hasFreshReauth,
  loginAllowed,
  recordFailedLogin,
  clearFailedLogins,
  verifyPassword,
  markReauth
} from './auth';
import { isMfaEnabled, verifySecondFactor } from './mfa';

export type ProofResult =
  | { ok: true }
  | { ok: false; reason: 'reauth_required' }
  | { ok: false; reason: 'mfa_required' }
  | { ok: false; reason: 'invalid' }
  | { ok: false; reason: 'rate_limited' };

/**
 * Confirm a sensitive action with either:
 *   - a fresh re-auth already recorded on this session (within 5 minutes), or
 *   - the login password (and MFA code, when enabled) supplied with this call.
 *
 * The password path marks the session fresh so a following action in the same
 * flow does not ask twice. It never touches the vault passphrase or the DEK.
 */
export async function confirmSensitive(
  user: { id: number; username: string },
  sessionToken: string | undefined,
  input: { password?: string; code?: string },
  ip: string,
  requirePassword = false
): Promise<ProofResult> {
  if (!sessionToken) return { ok: false, reason: 'reauth_required' };

  const password = String(input.password ?? '');
  if (!password) {
    // A fresh login is not proof against a cookie stolen in the first five
    // minutes. High-risk actions pass requirePassword=true so only the password
    // (plus MFA) counts.
    if (requirePassword) return { ok: false, reason: 'reauth_required' };
    return (await hasFreshReauth(sessionToken)) ? { ok: true } : { ok: false, reason: 'reauth_required' };
  }

  if (!(await loginAllowed(user.username, ip))) return { ok: false, reason: 'rate_limited' };

  const rows = await sql`select password_hash from users where id = ${user.id}`;
  if (!rows[0] || !(await verifyPassword(password, String(rows[0].password_hash)))) {
    await recordFailedLogin(user.username, ip);
    return { ok: false, reason: 'invalid' };
  }

  if (await isMfaEnabled(user.id)) {
    const code = String(input.code ?? '').trim();
    if (!code) return { ok: false, reason: 'mfa_required' };
    if (!(await verifySecondFactor(user.id, code))) {
      await recordFailedLogin(user.username, ip);
      return { ok: false, reason: 'invalid' };
    }
  }

  await markReauth(sessionToken);
  await clearFailedLogins(user.username, ip);
  return { ok: true };
}
