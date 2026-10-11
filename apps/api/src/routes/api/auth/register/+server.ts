import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import { hashPassword, createSession, cookieOptions, SESSION_COOKIE } from '$lib/server/auth';

export const POST: RequestHandler = async ({ request, cookies, url }) => {
  const body = await request.json().catch(() => ({}));
  const name = String(body.username ?? '').trim().toLowerCase();
  const password = String(body.password ?? '');
  if (name.length < 3) throw error(400, 'Username must be at least 3 characters');
  // Eight, matching the vault passphrase minimum the same person is about to
  // set two screens later. Four was brute-forceable in minutes even with the
  // login throttle in front of it, and this account holds every synced module
  // plus the salts and wrapped keys that enable an offline attack on the
  // passphrase itself.
  if (password.length < 8) throw error(400, 'Password must be at least 8 characters');

  const existing = await sql`select id from users where username = ${name}`;
  if (existing.length) throw error(409, 'That username is taken');

  const passwordHash = await hashPassword(password);
  const [user] = await sql`
    insert into users (username, password_hash)
    values (${name}, ${passwordHash})
    returning id, username`;

  const token = await createSession(user.id);
  cookies.set(SESSION_COOKIE, token, cookieOptions(url));
  return json({ id: user.id, username: user.username });
};
