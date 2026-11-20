import { error } from '@sveltejs/kit';

const encoder = new TextEncoder();

/** UTF-8 byte length. `String.length` counts UTF-16 code units, not bytes. */
export function utf8Bytes(text: string): number {
  return encoder.encode(text).length;
}

/**
 * Read a JSON request body with a hard byte cap before parsing.
 *
 * `request.json()` allocates the parsed object (and the whole body) before any
 * caller-side size check can run. Checking `Content-Length` first and then the
 * actual text keeps oversized payloads out of the isolate entirely. The text
 * itself is measured in UTF-8 bytes because the database limit is bytes.
 */
export async function readJsonBody(
  request: Request,
  maxBytes: number,
  message = 'That payload is too large'
): Promise<unknown> {
  const declared = Number(request.headers.get('content-length') ?? '');
  if (Number.isFinite(declared) && declared > maxBytes) throw error(413, message);

  const raw = await request.text().catch(() => {
    throw error(400, 'Body must be JSON');
  });
  if (utf8Bytes(raw) > maxBytes) throw error(413, message);
  if (!raw.trim()) return {};
  try {
    return JSON.parse(raw);
  } catch {
    throw error(400, 'Body must be JSON');
  }
}
