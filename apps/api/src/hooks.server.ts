import type { Handle, HandleServerError } from '@sveltejs/kit';
import { sql, withDB, type D1Database } from '$lib/server/db';
import { withMedia, type R2Bucket } from '$lib/server/storage';
import { SESSION_COOKIE, findSession } from '$lib/server/auth';
import { applySecurityHeaders, corsHeaders, isUnsafe, originAllowed } from '$lib/server/security';
import { audit } from '$lib/server/audit';

// Bot waves (rotating datacenter IPs probing a public *.workers.dev URL)
// were ~2/3 of all invocations on bad days and pushed nearly every request
// over the free tier's 10ms CPU cap. Anything these patterns match is a
// probe no part of this app ever serves, so answering 404 here costs
// microseconds instead of the D1 round-trip plus SvelteKit routing that
// `resolve` pays. Kept deliberately narrow: a false positive here would
// block the app itself, so no broad "weird path" heuristics.
const JUNK_RE = /(?:^|\/)(?:wp-(?:admin|login|content|includes)|phpmyadmin|xmlrpc\.php|\.git(?:\/|$)|\.env(?:$|\.)|\.aws|\.ssh|\.DS_Store|cgi-bin|\.aspx?$)/i;
const JUNK_SUFFIX_RE = /\.(?:php|asp|aspx|jsp|cgi|bak|sql)$/i;

function isScannerJunk(pathname: string): boolean {
  return JUNK_RE.test(pathname) || JUNK_SUFFIX_RE.test(pathname);
}

/** Hard ceiling before SvelteKit allocates a body. Route-level caps are tighter. */
const MAX_GLOBAL_BODY_BYTES = 100_000_000;

function clientIp(event: Parameters<Handle>[0]['event']): string {
  try {
    return event.getClientAddress();
  } catch {
    return 'unknown';
  }
}

// Resolve the session cookie into event.locals.user for every request.
export const handle: Handle = async ({ event, resolve }) => {
  const url = new URL(event.request.url);
  if (isScannerJunk(url.pathname)) {
    return new Response('Not found', { status: 404 });
  }

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
  const url = new URL(event.request.url);
  const method = event.request.method.toUpperCase();

  // Explicit CORS preflight. There is no allowlist by default, so a browser
  // origin gets no permission rather than a wildcard.
  if (method === 'OPTIONS' && url.pathname.startsWith('/api/')) {
    return new Response(null, {
      status: 204,
      headers: {
        ...corsHeaders(event.request),
        'Cache-Control': 'no-store',
        Vary: 'Origin'
      }
    });
  }

  if (url.pathname.startsWith('/api/') && isUnsafe(method)) {
    if (!originAllowed(event.request, url)) {
      void audit({
        event: 'csrf_blocked',
        outcome: 'denied',
        ip: clientIp(event),
        userAgent: event.request.headers.get('user-agent'),
        meta: { path: url.pathname, method }
      });
      return new Response(JSON.stringify({ message: 'Cross-site request refused' }), {
        status: 403,
        headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }
      });
    }
    const declared = Number(event.request.headers.get('content-length') ?? '');
    if (Number.isFinite(declared) && declared > MAX_GLOBAL_BODY_BYTES) {
      return new Response(JSON.stringify({ message: 'Payload too large' }), {
        status: 413,
        headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }
      });
    }
  }

  const token = event.cookies.get(SESSION_COOKIE);
  if (token) {
    try {
      const session = await findSession(token);
      if (session) {
        event.locals.user = { id: session.userId, username: session.username };
        event.locals.sessionToken = token;
        event.locals.sessionId = session.sessionId;
        event.locals.sessionCreatedAt = session.createdAt;
      }
    } catch {
      // NOT "treat as logged out". Falling through unauthenticated turns a
      // server-side outage into a 401 on every route, and the client reads a 401
      // as "the session is gone" — it logs the user out and abandons in-flight
      // saves, because a 401 is (correctly) not worth retrying. A database that
      // is down is a 503: temporary, and the client keeps its session and its
      // unsaved work.
      return new Response('Database unavailable', { status: 503 });
    }
  }

  const response = await resolve(event);
  applySecurityHeaders(response, url);
  // CORS is only added for an explicitly allowlisted browser origin. Native
  // clients send no Origin and are unaffected.
  for (const [key, value] of Object.entries(corsHeaders(event.request))) {
    response.headers.set(key, value);
  }
  // Authenticated payloads must never land in a shared/browser cache. Anatomy
  // is the one public, static route and sets its own long-lived cache header.
  if (url.pathname.startsWith('/api/') && url.pathname !== '/api/anatomy') {
    response.headers.set('Cache-Control', 'private, no-store');
  }
  return response;
};

/**
 * Server errors are logged as a category, never with the request body or a
 * record's contents. SvelteKit already returns a generic error in production;
 * this makes sure our own logs do not become the leak.
 */
export const handleError: HandleServerError = ({ error, status, message }) => {
  const name = error instanceof Error ? error.name : 'UnknownError';
  // Deliberately no stack, no request data, no user identifier, and no error
  // message: a 4xx message is user-facing and may include a record fragment.
  console.error(JSON.stringify({ event: 'server_error', status, name }));
  return { message: status === 500 ? 'Something went wrong on the server.' : message };
};
