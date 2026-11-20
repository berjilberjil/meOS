/**
 * Shared validation for the two R2 media routes.
 *
 * IDs become part of the object key, so they must never contain `/`, `.` or
 * `..`. The previous regex allowed both dot names; no traversal was possible
 * because slashes were rejected, but a literal `..` key is still nonsense and
 * can be normalised by HTTP stacks in surprising ways.
 */
export const MEDIA_ID_RE = /^[A-Za-z0-9._-]{1,200}$/;

export function isMediaId(id: string): boolean {
  return id !== '.' && id !== '..' && MEDIA_ID_RE.test(id);
}

const BASE64_RE = /^[A-Za-z0-9+/]*={0,2}$/;

/** Exact decoded length of a base64 string, or `null` if it is not base64. */
export function base64DecodedBytes(input: string): number | null {
  const clean = input.replace(/\s+/g, '');
  if (!clean || clean.length % 4 !== 0 || !BASE64_RE.test(clean)) return null;
  const padding = clean.endsWith('==') ? 2 : clean.endsWith('=') ? 1 : 0;
  return (clean.length / 4) * 3 - padding;
}

/**
 * Decode only if the result fits `maxBytes`. The length check happens before
 * `Buffer.from`, so an oversized request never allocates the decoded copy.
 */
export function decodeBase64Capped(input: string, maxBytes: number): Buffer | null {
  const size = base64DecodedBytes(input);
  if (size === null || size === 0 || size > maxBytes) return null;
  return Buffer.from(input, 'base64');
}
