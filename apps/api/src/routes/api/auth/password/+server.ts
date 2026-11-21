import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import {
  verifyPassword,
  hashPassword,
  SESSION_COOKIE,
  loginAllowed,
  recordFailedLogin,
  clearFailedLogins
} from '$lib/server/auth';
import { readJsonBody } from '$lib/server/http';

// Change the login password. Needs a live session AND the current password, so a
// stolen session cookie alone cannot lock the owner out. Wrong guesses share the
// login throttle — this endpoint must not become the unthrottled way to test
// passwords. The vault passphrase is separate and untouched.
export const POST: RequestHandler = async ({ request, cookies, locals, getClientAddress }) => {
  const user = locals.user;
  if (!user) throw error(401, 'Not signed in');

  const body = (await readJsonBody(request, 4_096)) as Record<string, unknown>;
  const current = String(body.current ?? '');
  const next = String(body.next ?? '');
  const ip = getClientAddress();

  if (next.length < 8) throw error(400, 'New password must be at least 8 characters.');
  if (next.length > 200) throw error(400, 'New password is too long.');

  if (!(await loginAllowed(user.username, ip))) {
    throw error(429, 'Too many attempts. Wait a few minutes and try again.');
  }

  const rows = await sql`select password_hash from users where id = ${user.id}`;
  if (!rows[0] || !(await verifyPassword(current, rows[0].password_hash))) {
    await recordFailedLogin(user.username, ip);
    throw error(403, 'Current password is wrong.');
  }

  const nextHash = await hashPassword(next);
  await sql`update users set password_hash = ${nextHash} where id = ${user.id}`;
  // Sign out every other device; keep this one.
  const token = cookies.get(SESSION_COOKIE) ?? '';
  await sql`delete from sessions where user_id = ${user.id} and token <> ${token}`;
  await clearFailedLogins(user.username, ip);
  return json({ ok: true });
};
