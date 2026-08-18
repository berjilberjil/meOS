import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { listObjects, signObjects, uploadObject } from '$lib/server/storage';

const ID_RE = /^[A-Za-z0-9._-]{1,200}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}/;

function prefix(userId: number | string): string {
  return `body-photos/${userId}/`;
}

// List the logged-in user's synced progress photos (any device) with
// short-lived signed URLs. Filenames are `{yyyy-MM-dd}__{id}.jpg`, matching
// the on-device naming scheme, so no separate metadata table is needed.
export const GET: RequestHandler = async ({ locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const p = prefix(locals.user.id);
  const objects = await listObjects(p);
  const paths = objects.map((o) => `${p}${o.name}`);
  const signed = await signObjects(paths, 3600);
  const out = objects
    .map((o) => {
      const stem = o.name.replace(/\.jpe?g$/i, '');
      return {
        id: stem,
        date: stem.slice(0, 10),
        url: signed[`${p}${o.name}`] ?? null,
        updatedAt: o.updatedAt ?? null
      };
    })
    .filter((r) => r.url);
  return json(out);
};

// Upload (or overwrite) one progress photo. Body: { id, date, dataBase64 }.
export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const body = await request.json().catch(() => ({}));
  const id = String(body.id ?? '').trim();
  const date = String(body.date ?? '').trim();
  const b64 = String(body.dataBase64 ?? '');
  if (!DATE_RE.test(date)) throw error(400, 'Bad date');
  if (!ID_RE.test(id)) throw error(400, 'Bad id');
  if (!b64) throw error(400, 'Missing image data');

  const bytes = Buffer.from(b64, 'base64');
  if (bytes.length === 0 || bytes.length > 15_000_000) throw error(400, 'Bad image size');

  const path = `${prefix(locals.user.id)}${id}.jpg`;
  await uploadObject(path, bytes, 'image/jpeg');
  return json({ ok: true, id });
};
