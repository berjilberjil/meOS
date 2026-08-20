import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { signObjects, uploadObject } from '$lib/server/storage';

const ID_RE = /^[A-Za-z0-9._-]{1,200}$/;

// Event photos/videos live in R2 instead of inside the encrypted `myos.events`
// blob, which was 2 MB of base64 re-synced on every poll. The bytes stored here
// are AES-GCM ciphertext sealed on-device with the vault DEK — this server never
// sees a key, so an object is opaque to Cloudflare and to us.
export function mediaKey(userId: number | string, id: string): string {
  return `event-media/${userId}/${id}`;
}

// Sign a batch of media ids for reading. `?ids=a,b,c`
export const GET: RequestHandler = async ({ url, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const ids = (url.searchParams.get('ids') ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => ID_RE.test(s));
  if (ids.length === 0) return json({});
  if (ids.length > 200) throw error(400, 'Too many ids');

  const keys = ids.map((id) => mediaKey(locals.user!.id, id));
  const signed = await signObjects(keys, 3600);
  const out: Record<string, string> = {};
  for (const id of ids) {
    const u = signed[mediaKey(locals.user!.id, id)];
    if (u) out[id] = u;
  }
  return json(out);
};

// Upload one sealed media object. Body: { id, ciphertextBase64 }.
export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const body = await request.json().catch(() => ({}));
  const id = String(body.id ?? '').trim();
  const b64 = String(body.ciphertextBase64 ?? '');
  if (!ID_RE.test(id)) throw error(400, 'Bad id');
  if (!b64) throw error(400, 'Missing ciphertext');

  const bytes = Buffer.from(b64, 'base64');
  // Video is capped on-device; this is a backstop, not the real limit.
  if (bytes.length === 0 || bytes.length > 60_000_000) throw error(400, 'Bad media size');

  await uploadObject(mediaKey(locals.user.id, id), bytes, 'application/octet-stream');
  return json({ ok: true, id });
};
