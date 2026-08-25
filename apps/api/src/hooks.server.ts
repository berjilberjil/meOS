import type { Handle } from '@sveltejs/kit';
import { sql, nowISO, withDB, type D1Database } from '$lib/server/db';
import { withMedia, type R2Bucket } from '$lib/server/storage';
import { SESSION_COOKIE } from '$lib/server/auth';

// Resolve the session cookie into event.locals.user for every request.
export const handle: Handle = async ({ event, resolve }) => {
  // D1 arrives per-request on platform.env, so every request runs inside a
  // context that carries the binding down to `sql` (see lib/server/db.ts).
  const env = (event.platform as { env?: { DB?: D1Database; MEDIA?: R2Bucket } } | undefined)?.env;
  const db = env?.DB;
  if (!db) {
    return new Response('Database binding missing', { status: 503 });
  }
  // MEDIA rides along the same way, so R2 list/delete can use the native
  // binding instead of the AWS SDK's XML path (which Workers cannot parse).
  const bucket = env?.MEDIA;
  return withDB(db, () =>
    bucket ? withMedia(bucket, () => handleRequest({ event, resolve })) : handleRequest({ event, resolve })
  );
};

const handleRequest: Handle = async ({ event, resolve }) => {
  const token = event.cookies.get(SESSION_COOKIE);
  if (token) {
    try {
      const rows = await sql`
        select u.id, u.username
        from sessions s
        join users u on u.id = s.user_id
        where s.token = ${token} and s.expires_at > ${nowISO()}
        limit 1`;
      if (rows.length) event.locals.user = { id: rows[0].id, username: rows[0].username };
    } catch {
      /* db unavailable — treat as logged out */
    }
  }
  const response = await resolve(event);
  // Private personal backend — keep every response out of search engines.
  response.headers.set('X-Robots-Tag', 'noindex, nofollow');
  return response;
};
