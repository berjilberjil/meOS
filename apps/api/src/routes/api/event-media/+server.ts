import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { eventMediaKey, mediaRoomFor, signObjects, uploadObject } from '$lib/server/storage';
import { decodeBase64Capped, isMediaId } from '$lib/server/media';
import { readJsonBody } from '$lib/server/http';
import { enforceRateLimit } from '$lib/server/security';
import { audit } from '$lib/server/audit';

const MAX_MEDIA_BYTES = 60_000_000;
/** base64 is 4/3 the decoded size, plus a little JSON envelope. */
const MAX_REQUEST_BYTES = 81_000_000;
const SIGNED_URL_TTL_SECONDS = 600;

function ipOf(getClientAddress: () => string): string {
  try {
    return getClientAddress();
  } catch {
    return 'unknown';
  }
}

// Event photos/videos live in R2 instead of inside the encrypted `meos.events`
// blob, which was 2 MB of base64 re-synced on every poll. SvelteKit only allows
// GET/POST/... exports from a +server.ts, so the key helper lives in $lib.

// Sign a batch of media ids for reading. `?ids=a,b,c`
export const GET: RequestHandler = async ({ url, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  enforceRateLimit(`event-media-get:${locals.user.id}`, 120, 60_000);
  const ids = (url.searchParams.get('ids') ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => isMediaId(s));
  if (ids.length === 0) return json({});
  if (ids.length > 200) throw error(400, 'Too many ids');

  const keys = ids.map((id) => eventMediaKey(locals.user!.id, id));
  const signed = await signObjects(keys, SIGNED_URL_TTL_SECONDS);
  const out: Record<string, string> = {};
  for (const id of ids) {
    const u = signed[eventMediaKey(locals.user!.id, id)];
    if (u) out[id] = u;
  }
  return json(out);
};

// Upload one sealed media object. Body: { id, ciphertextBase64 }.
export const POST: RequestHandler = async ({ request, locals, getClientAddress }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  enforceRateLimit(`event-media-put:${locals.user.id}`, 30, 60_000);
  const body = (await readJsonBody(
    request,
    MAX_REQUEST_BYTES,
    'That media is too large to upload'
  )) as Record<string, unknown>;
  const id = String(body.id ?? '').trim();
  const b64 = String(body.ciphertextBase64 ?? '');
  if (!isMediaId(id)) throw error(400, 'Bad id');
  if (!b64) throw error(400, 'Missing ciphertext');

  const bytes = decodeBase64Capped(b64, MAX_MEDIA_BYTES);
  // Video is capped on-device; this is a backstop, not the real limit.
  if (!bytes) throw error(400, 'Bad media size');
  // The per-object cap alone is not a limit: 168 of them is R2's whole free
  // tier, which is account-wide, so one user could stop sync for everyone.
  if (!(await mediaRoomFor(`event-media/${locals.user.id}/`, bytes.length))) {
    throw error(413, 'Your media storage is full. Delete some memories to make room.');
  }

  await uploadObject(eventMediaKey(locals.user.id, id), bytes, 'application/octet-stream');
  void audit({
    event: 'media_upload',
    outcome: 'success',
    userId: locals.user.id,
    ip: ipOf(getClientAddress),
    userAgent: request.headers.get('user-agent'),
    meta: { kind: 'event_media', bytes: bytes.length }
  });
  return json({ ok: true, id });
};
