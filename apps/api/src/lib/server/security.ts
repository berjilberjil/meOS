import { error } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';

/**
 * Transport-level hardening shared by every route.
 *
 * The app is a native client talking to a JSON API, not a website. These
 * helpers therefore default to *deny*: no CORS origin is allowed unless the
 * operator names one, no cross-site unsafe request is accepted, and no HTML
 * response is frameable or script-injectable.
 */

export const UNSAFE_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

export function isUnsafe(method: string): boolean {
  return UNSAFE_METHODS.has(method.toUpperCase());
}

function splitList(raw: string | undefined): string[] {
  return (raw ?? '')
    .split(/[\s,]+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

/** Exact origins from `MEOS_CORS_ORIGINS`, never a wildcard. */
export function allowedCorsOrigins(): string[] {
  return splitList(env.MEOS_CORS_ORIGINS);
}

/** Origins allowed to make cookie-authenticated unsafe requests. */
export function trustedOrigins(url: URL): string[] {
  return [url.origin, ...splitList(env.MEOS_TRUSTED_ORIGINS)];
}

/**
 * CSRF defence in depth.
 *
 * The session cookie is SameSite=Strict, every mutating endpoint parses JSON,
 * and no CORS origin is allowed by default — three independent reasons a
 * cross-site form/fetch cannot act as the owner. This check closes the
 * remaining cases (an explicitly configured trusted origin, a browser that
 * still sends an Origin/Sec-Fetch-Site header):
 *
 *   - no Origin and no Sec-Fetch-Site  -> native app / CLI, allow
 *   - Origin present                   -> must be an exact trusted origin
 *   - Sec-Fetch-Site: cross-site        -> always reject
 */
export function originAllowed(request: Request, url: URL): boolean {
  const fetchSite = request.headers.get('sec-fetch-site');
  if (fetchSite === 'cross-site') return false;

  const origin = request.headers.get('origin');
  if (!origin) return true;
  if (origin === 'null') return false;
  return trustedOrigins(url).includes(origin);
}

export function corsHeaders(request: Request): Record<string, string> {
  const origin = request.headers.get('origin');
  if (!origin) return {};
  if (!allowedCorsOrigins().includes(origin)) return {};
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Credentials': 'true',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'content-type, if-none-match, x-meos-reauth',
    'Access-Control-Expose-Headers': 'etag',
    'Access-Control-Max-Age': '600',
    Vary: 'Origin'
  };
}

/** Headers that are safe (and useful) on both JSON and HTML responses. */
export function applySecurityHeaders(response: Response, url: URL): void {
  const h = response.headers;
  h.set('X-Content-Type-Options', 'nosniff');
  h.set('X-Frame-Options', 'DENY');
  h.set('Referrer-Policy', 'no-referrer');
  h.set('X-Robots-Tag', 'noindex, nofollow');
  h.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()');
  h.set('Cross-Origin-Opener-Policy', 'same-origin');
  h.set('Cross-Origin-Resource-Policy', 'same-origin');
  h.set('X-Permitted-Cross-Domain-Policies', 'none');
  if (url.protocol === 'https:') {
    h.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  }
}

/**
 * A tiny per-isolate sliding window. This is deliberately *not* the primary
 * defence: login throttling is durable in D1, and AI spend is bounded in D1.
 * It is a cheap burst limiter for state/media/export routes so one runaway or
 * stolen client cannot hammer D1/R2. Across isolates the effective limit is
 * `max * isolate_count`; that is documented, not pretended away.
 */
export class SlidingWindowLimiter {
  private readonly buckets = new Map<string, number[]>();
  private readonly now: () => number;
  private lastSweep = 0;

  constructor(now: () => number = Date.now) {
    this.now = now;
  }

  take(key: string, max: number, windowMs: number): { ok: true } | { ok: false; retryAfter: number } {
    const now = this.now();
    const bucket = this.buckets.get(key) ?? [];
    const live = bucket.filter((t) => now - t < windowMs);
    if (live.length >= max) {
      const oldest = live[0] ?? now;
      this.buckets.set(key, live);
      return { ok: false, retryAfter: Math.max(1, Math.ceil((windowMs - (now - oldest)) / 1000)) };
    }
    live.push(now);
    this.buckets.set(key, live);

    // Bound memory. One sweep every minute is enough for a single-owner app.
    if (now - this.lastSweep > 60_000) {
      this.lastSweep = now;
      for (const [k, hits] of this.buckets) {
        const kept = hits.filter((t) => now - t < windowMs);
        if (kept.length) this.buckets.set(k, kept);
        else this.buckets.delete(k);
      }
    }
    return { ok: true };
  }
}

export const apiLimiter = new SlidingWindowLimiter();

/** Throw a 429 when the bucket is exhausted. */
export function enforceRateLimit(key: string, max: number, windowMs: number): void {
  const result = apiLimiter.take(key, max, windowMs);
  if (!result.ok) {
    throw error(429, `Too many requests. Try again in ${result.retryAfter}s.`);
  }
}

/**
 * A request-id for correlating an audit row with an application log without
 * logging the request itself.
 */
export function requestId(): string {
  return crypto.randomUUID();
}
