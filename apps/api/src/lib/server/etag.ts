/**
 * Whether an `If-None-Match` header names `etag`, using the weak comparison
 * RFC 9110 §13.1.2 prescribes for it.
 *
 * Cloudflare rewrites a strong ETag to weak (`W/"…"`) whenever it compresses
 * the response, so the client stores and echoes back `W/"v5810-…"` while the
 * server mints `"v5810-…"`. A plain `===` never matched: the 304 path was dead,
 * every poll paid for the full state, and that blew the free tier's 10ms CPU
 * limit — so the poll 503'd, the client never got a fresh ETag, and the next
 * poll did it all again.
 */
export function etagMatches(header: string | null, etag: string): boolean {
  if (!header) return false;
  const opaque = (t: string) => t.trim().replace(/^W\//, '');
  const want = opaque(etag);
  return header.split(',').some((t) => t.trim() === '*' || opaque(t) === want);
}
