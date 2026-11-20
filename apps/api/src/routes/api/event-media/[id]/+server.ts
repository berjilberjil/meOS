import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { eventMediaKey, removeObjects } from '$lib/server/storage';
import { isMediaId } from '$lib/server/media';

// Delete one sealed event-media object.
export const DELETE: RequestHandler = async ({ params, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const id = params.id ?? '';
  if (!isMediaId(id)) throw error(400, 'Bad id');
  await removeObjects([eventMediaKey(locals.user.id, id)]);
  return json({ ok: true });
};
