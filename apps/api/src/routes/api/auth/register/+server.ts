import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import { hashPassword, createSession, cookieOptions, SESSION_COOKIE } from '$lib/server/auth';

export const POST: RequestHandler = async ({ request, cookies }) => {
  const body = await request.json().catch(() => ({}));
  const name = String(body.username ?? '').trim().toLowerCase();
  const password = String(body.password ?? '');
  if (name.length < 3) throw error(400, 'Username must be at least 3 characters');
  if (password.length < 4) throw error(400, 'Password must be at least 4 characters');

  const existing = await sql`select id from users where username = ${name}`;
  if (existing.length) throw error(409, 'That username is taken');

  const [user] = await sql`
    insert into users (username, password_hash)
    values (${name}, ${hashPassword(password)})
    returning id, username`;

  const token = await createSession(user.id);
  cookies.set(SESSION_COOKIE, token, cookieOptions());
  return json({ id: user.id, username: user.username });
};
