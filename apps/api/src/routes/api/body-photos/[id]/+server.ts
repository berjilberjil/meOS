import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { removeObjects } from '$lib/server/storage';
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

// Delete one synced progress photo (by filename stem, e.g. `2026-08-15__manual-123`).
export const DELETE: RequestHandler = async ({ params, locals, request, getClientAddress }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  enforceRateLimit(`body-photos-delete:${locals.user.id}`, 60, 60_000);
  const id = params.id ?? '';
  if (!isMediaId(id)) throw error(400, 'Bad id');
  const path = `body-photos/${locals.user.id}/${id}.jpg`;
  await removeObjects([path]);
  void audit({
    event: 'media_delete',
    outcome: 'success',
    userId: locals.user.id,
    ip: ipOf(getClientAddress),
    userAgent: request.headers.get('user-agent'),
    meta: { kind: 'body_photo' }
  });
  return json({ ok: true });
};
