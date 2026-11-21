import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { mfaStatus } from '$lib/server/mfa';

/** Whether this account has a second factor. No secret material is returned. */
export const GET: RequestHandler = async ({ locals }) => {
  if (!locals.user) throw error(401, 'Not signed in');
  return json(await mfaStatus(locals.user.id));
};
