import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import {
  verifyPassword,
  hashPassword,
  SESSION_COOKIE,
  loginAllowed,
  recordFailedLogin,
  clearFailedLogins,
  deleteOtherSessions,
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

// Change the login password. Needs a live session AND the current password, so a
// stolen session cookie alone cannot lock the owner out. Wrong guesses share the
// login throttle — this endpoint must not become the unthrottled way to test
// passwords. If MFA is enabled, a current TOTP/recovery code is required too.
// The vault passphrase is separate and untouched.
export const POST: RequestHandler = async ({ request, cookies, locals, getClientAddress }) => {
  const user = locals.user;
  if (!user) throw error(401, 'Not signed in');

  const body = (await readJsonBody(request, 4_096)) as Record<string, unknown>;
  const current = String(body.current ?? '');
  const next = String(body.next ?? '');
  const code = String(body.code ?? '').trim().slice(0, 64);
  const ip = ipOf(getClientAddress);
  const userAgent = request.headers.get('user-agent');

  if (next.length < 8) throw error(400, 'New password must be at least 8 characters.');
  if (next.length > 200) throw error(400, 'New password is too long.');

  if (!(await loginAllowed(user.username, ip))) {
    throw error(429, 'Too many attempts. Wait a few minutes and try again.');
  }

  const rows = await sql`select password_hash from users where id = ${user.id}`;
  if (!rows[0] || !(await verifyPassword(current, String(rows[0].password_hash)))) {
    await recordFailedLogin(user.username, ip);
    void audit({ event: 'password_change', outcome: 'failure', userId: user.id, ip, userAgent });
    throw error(403, 'Current password is wrong.');
  }

  if (await isMfaEnabled(user.id)) {
    if (!code) {
      return json({ mfaRequired: true, message: 'Enter your authenticator code.' }, { status: 401 });
    }
    if (!(await verifySecondFactor(user.id, code))) {
      await recordFailedLogin(user.username, ip);
      void audit({ event: 'password_change', outcome: 'denied', userId: user.id, ip, userAgent, meta: { reason: 'mfa' } });
      throw error(403, 'That authenticator code is not valid.');
    }
  }

  const nextHash = await hashPassword(next);
  await sql`update users set password_hash = ${nextHash} where id = ${user.id}`;
  // Sign out every other device; keep this one.
  const token = cookies.get(SESSION_COOKIE) ?? '';
  const revoked = await deleteOtherSessions(user.id, token);
  if (token) await markReauth(token);
  await clearFailedLogins(user.username, ip);
  void audit({
    event: 'password_change',
    outcome: 'success',
    userId: user.id,
    ip,
    userAgent,
    meta: { other_sessions_revoked: revoked }
  });
  return json({ ok: true, otherSessionsRevoked: revoked });
};
