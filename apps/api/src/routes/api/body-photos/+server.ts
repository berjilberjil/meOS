import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { listObjects, mediaRoomFor, signObjects, uploadObject } from '$lib/server/storage';
import { decodeBase64Capped, isMediaId } from '$lib/server/media';
import { readJsonBody } from '$lib/server/http';
import { enforceRateLimit } from '$lib/server/security';
import { audit } from '$lib/server/audit';

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_PHOTO_BYTES = 15_000_000;
/** base64 is 4/3 the decoded size, plus a little JSON envelope. */
const MAX_REQUEST_BYTES = 21_000_000;
/** Short enough that a leaked URL stops working long before it is useful. */
const SIGNED_URL_TTL_SECONDS = 600;

function prefix(userId: number | string): string {
  return `body-photos/${userId}/`;
}

function ipOf(getClientAddress: () => string): string {
  try {
    return getClientAddress();
  } catch {
    return 'unknown';
  }
}

// List the logged-in user's synced progress photos (any device) with
// short-lived signed URLs. Filenames are `{yyyy-MM-dd}__{id}.jpg`, matching
// the on-device naming scheme, so no separate metadata table is needed.
export const GET: RequestHandler = async ({ locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  enforceRateLimit(`body-photos-get:${locals.user.id}`, 60, 60_000);
  const p = prefix(locals.user.id);
  const objects = await listObjects(p);
  const paths = objects.map((o) => `${p}${o.name}`);
  const signed = await signObjects(paths, SIGNED_URL_TTL_SECONDS);
  const out = objects
    .map((o) => {
      const stem = o.name.replace(/\.jpe?g$/i, '');
      return {
        id: stem,
        date: stem.slice(0, 10),
        url: signed[`${p}${o.name}`] ?? null,
        updatedAt: o.updatedAt ?? null,
        // Size only. The bytes themselves are vault ciphertext.
        bytes: o.bytes ?? null
      };
    })
    .filter((r) => r.url);
  return json(out);
};

// Upload (or overwrite) one progress photo. Body: { id, date, dataBase64 }.
// The bytes are sealed on-device before they get here; this route never sees a
// JPEG, and the server cannot decode one.
export const POST: RequestHandler = async ({ request, locals, getClientAddress }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  enforceRateLimit(`body-photos-put:${locals.user.id}`, 30, 60_000);
  const body = (await readJsonBody(
    request,
    MAX_REQUEST_BYTES,
    'That photo is too large to upload'
  )) as Record<string, unknown>;
  const id = String(body.id ?? '').trim();
  const date = String(body.date ?? '').trim();
  const b64 = String(body.dataBase64 ?? '');
  if (!DATE_RE.test(date)) throw error(400, 'Bad date');
  if (!isMediaId(id)) throw error(400, 'Bad id');
  if (!b64) throw error(400, 'Missing image data');

  const bytes = decodeBase64Capped(b64, MAX_PHOTO_BYTES);
  if (!bytes) throw error(400, 'Bad image size');
  // R2's free tier is account-wide, so one user filling it stops everyone.
  if (!(await mediaRoomFor(prefix(locals.user.id), bytes.length))) {
    throw error(413, 'Your photo storage is full. Delete some to make room.');
  }

  const path = `${prefix(locals.user.id)}${id}.jpg`;
  await uploadObject(path, bytes, 'application/octet-stream');
  void audit({
    event: 'media_upload',
    outcome: 'success',
    userId: locals.user.id,
    ip: ipOf(getClientAddress),
    userAgent: request.headers.get('user-agent'),
    meta: { kind: 'body_photo', bytes: bytes.length }
  });
  return json({ ok: true, id });
};
