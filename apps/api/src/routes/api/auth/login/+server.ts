import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import { verifyPassword, createSession, cookieOptions, SESSION_COOKIE } from '$lib/server/auth';

export const POST: RequestHandler = async ({ request, cookies }) => {
  const body = await request.json().catch(() => ({}));
  const name = String(body.username ?? '').trim().toLowerCase();
  const password = String(body.password ?? '');

  const rows = await sql`select id, username, password_hash from users where username = ${name}`;
  const user = rows[0];
  if (!user || !verifyPassword(password, user.password_hash)) {
    throw error(401, 'Wrong username or password');
  }

  const token = await createSession(user.id);
  cookies.set(SESSION_COOKIE, token, cookieOptions());
  return json({ id: user.id, username: user.username });
};
