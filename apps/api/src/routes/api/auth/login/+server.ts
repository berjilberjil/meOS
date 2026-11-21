import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import {
  verifyPassword,
  hashPassword,
  createSession,
  cookieOptions,
  SESSION_COOKIE,
  loginAllowed,
  recordFailedLogin,
  clearFailedLogins
} from '$lib/server/auth';
import { readJsonBody } from '$lib/server/http';

const MAX_USERNAME = 64;
const MAX_PASSWORD = 200;

export const POST: RequestHandler = async ({ request, cookies, url, getClientAddress }) => {
  const body = (await readJsonBody(request, 4_096)) as Record<string, unknown>;
  const name = String(body.username ?? '').trim().toLowerCase();
  const password = String(body.password ?? '');
  const ip = getClientAddress();

  if (!name || name.length > MAX_USERNAME || password.length > MAX_PASSWORD) {
    throw error(401, 'Wrong username or password');
  }

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

  await clearFailedLogins(name, ip);

  // Legacy scrypt hashes cost 50-100ms CPU on Workers — over the free tier's
  // 10ms cap. Rewriting one after a successful login is the only opportunity
  // to migrate it without asking the owner to change their password.
  if (!String(user.password_hash).startsWith('v2:')) {
    try {
      const upgraded = await hashPassword(password);
      await sql`update users set password_hash = ${upgraded}
                where id = ${user.id} and password_hash = ${user.password_hash}`;
    } catch {
      // A failed upgrade must not turn a valid sign-in into a 500.
    }
  }

  const token = await createSession(user.id);
  cookies.set(SESSION_COOKIE, token, cookieOptions(url));
  return json({ id: user.id, username: user.username });
};
