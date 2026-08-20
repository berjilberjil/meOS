import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { removeObjects } from '$lib/server/storage';
import { mediaKey } from '../+server';

const ID_RE = /^[A-Za-z0-9._-]{1,200}$/;

// Delete one sealed event-media object.
export const DELETE: RequestHandler = async ({ params, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const id = params.id ?? '';
  if (!ID_RE.test(id)) throw error(400, 'Bad id');
  await removeObjects([mediaKey(locals.user.id, id)]);
  return json({ ok: true });
};
