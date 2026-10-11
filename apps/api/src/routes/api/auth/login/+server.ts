import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import {
  verifyPassword,
  createSession,
  cookieOptions,
  SESSION_COOKIE,
  loginAllowed,
  recordFailedLogin,
  clearFailedLogins
} from '$lib/server/auth';

export const POST: RequestHandler = async ({ request, cookies, url, getClientAddress }) => {
  const body = await request.json().catch(() => ({}));
  const name = String(body.username ?? '').trim().toLowerCase();
  const password = String(body.password ?? '');
  const ip = getClientAddress();

  // Throttled per username AND per IP. verifyPassword is a single PBKDF2 (~2-3ms)
  // and Workers fan out, so an unthrottled endpoint exhausts a short password in
  // minutes — and this account holds every synced module plus the salts and
  // wrapped keys that enable an offline attack on the vault passphrase.
  if (!(await loginAllowed(name, ip))) {
    throw error(429, 'Too many attempts. Wait a few minutes and try again.');
  }

  const rows = await sql`select id, username, password_hash from users where username = ${name}`;
  const user = rows[0];
  if (!user || !(await verifyPassword(password, user.password_hash))) {
    await recordFailedLogin(name, ip);
    throw error(401, 'Wrong username or password');
  }

  await clearFailedLogins(name);
  const token = await createSession(user.id);
  cookies.set(SESSION_COOKIE, token, cookieOptions(url));
  return json({ id: user.id, username: user.username });
};
