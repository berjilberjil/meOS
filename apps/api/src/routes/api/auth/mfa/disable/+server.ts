import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import {
  verifyPassword,
  deleteOtherSessions,
  loginAllowed,
  recordFailedLogin,
  clearFailedLogins
} from '$lib/server/auth';
import { disableMfa, verifySecondFactor, mfaStatus } from '$lib/server/mfa';
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
 * Turn the second factor off. Requires the login password AND a current
 * authenticator/recovery code: a stolen session plus a stolen password still
 * cannot remove the factor without the device.
 */
export const POST: RequestHandler = async ({ request, locals, getClientAddress }) => {
  const user = locals.user;
  const token = locals.sessionToken;
  if (!user || !token) throw error(401, 'Not signed in');

  const body = (await readJsonBody(request, 4_096)) as Record<string, unknown>;
  const password = String(body.password ?? '');
  const code = String(body.code ?? '').trim();
  const ip = ipOf(getClientAddress);

  // This endpoint verifies a password, so it must share the login throttle;
  // otherwise it becomes an unthrottled password oracle for a stolen session.
  if (!(await loginAllowed(user.username, ip))) {
    throw error(429, 'Too many attempts. Wait a few minutes and try again.');
  }

  const rows = await sql`select password_hash from users where id = ${user.id}`;
  const passwordOk = Boolean(rows[0]) && (await verifyPassword(password, String(rows[0]!.password_hash)));
  // Only spend/consume a recovery code after the password is proven.
  const codeOk = passwordOk ? await verifySecondFactor(user.id, code) : false;

  if (!passwordOk || !codeOk) {
    await recordFailedLogin(user.username, ip);
    void audit({
      event: 'mfa_disable',
      outcome: 'failure',
      userId: user.id,
      ip,
      userAgent: request.headers.get('user-agent')
    });
    throw error(403, 'Password or authenticator code is not valid.');
  }

  await disableMfa(user.id);
  await deleteOtherSessions(user.id, token);
  await clearFailedLogins(user.username, ip);
  void audit({
    event: 'mfa_disable',
    outcome: 'success',
    userId: user.id,
    ip,
    userAgent: request.headers.get('user-agent')
  });
  return json(await mfaStatus(user.id));
};
