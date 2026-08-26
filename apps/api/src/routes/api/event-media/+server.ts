import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { eventMediaKey, mediaRoomFor, signObjects, uploadObject } from '$lib/server/storage';

const ID_RE = /^[A-Za-z0-9._-]{1,200}$/;

// Event photos/videos live in R2 instead of inside the encrypted `myos.events`
// blob, which was 2 MB of base64 re-synced on every poll. SvelteKit only allows
// GET/POST/... exports from a +server.ts, so the key helper lives in $lib.

// Sign a batch of media ids for reading. `?ids=a,b,c`
export const GET: RequestHandler = async ({ url, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const ids = (url.searchParams.get('ids') ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => ID_RE.test(s));
  if (ids.length === 0) return json({});
  if (ids.length > 200) throw error(400, 'Too many ids');

  const keys = ids.map((id) => eventMediaKey(locals.user!.id, id));
  const signed = await signObjects(keys, 3600);
  const out: Record<string, string> = {};
  for (const id of ids) {
    const u = signed[eventMediaKey(locals.user!.id, id)];
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
  // The per-object cap alone is not a limit: 168 of them is R2's whole free
  // tier, which is account-wide, so one user could stop sync for everyone.
  if (!(await mediaRoomFor(`event-media/${locals.user.id}/`, bytes.length))) {
    throw error(413, 'Your media storage is full. Delete some memories to make room.');
  }

  await uploadObject(eventMediaKey(locals.user.id, id), bytes, 'application/octet-stream');
  return json({ ok: true, id });
};
