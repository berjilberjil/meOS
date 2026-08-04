import type { Handle } from '@sveltejs/kit';
import { sql } from '$lib/server/db';
import { SESSION_COOKIE } from '$lib/server/auth';

// Resolve the session cookie into event.locals.user for every request.
export const handle: Handle = async ({ event, resolve }) => {
  const token = event.cookies.get(SESSION_COOKIE);
  if (token) {
    try {
      const rows = await sql`
        select u.id, u.username
        from sessions s
        join users u on u.id = s.user_id
        where s.token = ${token} and s.expires_at > now()
        limit 1`;
      if (rows.length) event.locals.user = { id: rows[0].id, username: rows[0].username };
    } catch {
      /* db unavailable — treat as logged out */
    }
  }
  return resolve(event);
};
