import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { removeObjects } from '$lib/server/storage';

const ID_RE = /^[A-Za-z0-9._-]{1,200}$/;

// Delete one synced progress photo (by filename stem, e.g. `2026-08-15__manual-123`).
export const DELETE: RequestHandler = async ({ params, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const id = params.id ?? '';
  if (!ID_RE.test(id)) throw error(400, 'Bad id');
  const path = `body-photos/${locals.user.id}/${id}.jpg`;
  await removeObjects([path]);
  return json({ ok: true });
};
