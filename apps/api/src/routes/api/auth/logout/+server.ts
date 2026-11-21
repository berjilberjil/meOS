import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { deleteSession, SESSION_COOKIE } from '$lib/server/auth';
import { audit } from '$lib/server/audit';

export const POST: RequestHandler = async ({ cookies, locals, request, getClientAddress }) => {
  const token = cookies.get(SESSION_COOKIE);
  if (token) await deleteSession(token);
  cookies.delete(SESSION_COOKIE, { path: '/' });
  let ip = 'unknown';
  try {
    ip = getClientAddress();
  } catch {
    /* local/test */
  }
  void audit({
    event: 'logout',
    outcome: 'success',
    userId: locals.user?.id ?? null,
    ip,
    userAgent: request.headers.get('user-agent')
  });
  return json({ ok: true });
};
