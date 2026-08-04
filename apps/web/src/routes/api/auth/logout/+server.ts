import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { deleteSession, SESSION_COOKIE } from '$lib/server/auth';

export const POST: RequestHandler = async ({ cookies }) => {
  const token = cookies.get(SESSION_COOKIE);
  if (token) await deleteSession(token);
  cookies.delete(SESSION_COOKIE, { path: '/' });
  return json({ ok: true });
};
