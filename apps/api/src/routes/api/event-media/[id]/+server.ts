import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { eventMediaKey, removeObjects } from '$lib/server/storage';
import { isMediaId } from '$lib/server/media';
import { enforceRateLimit } from '$lib/server/security';
import { audit } from '$lib/server/audit';

function ipOf(getClientAddress: () => string): string {
  try {
    return getClientAddress();
  } catch {
    return 'unknown';
  }
}

// Delete one sealed event-media object.
export const DELETE: RequestHandler = async ({ params, locals, request, getClientAddress }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  enforceRateLimit(`event-media-delete:${locals.user.id}`, 60, 60_000);
  const id = params.id ?? '';
  if (!isMediaId(id)) throw error(400, 'Bad id');
  await removeObjects([eventMediaKey(locals.user.id, id)]);
  void audit({
    event: 'media_delete',
    outcome: 'success',
    userId: locals.user.id,
    ip: ipOf(getClientAddress),
    userAgent: request.headers.get('user-agent'),
    meta: { kind: 'event_media' }
  });
  return json({ ok: true });
};
