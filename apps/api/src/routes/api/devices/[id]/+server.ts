import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { parseDeviceName, renameDevice } from '$lib/server/devices';

/** Rename one of this account's devices. */
export const PATCH: RequestHandler = async ({ params, request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  if (!params.id || params.id.length > 64) throw error(404, 'Device not found');

  const body = await request.json().catch(() => ({}));
  const name = parseDeviceName((body as Record<string, unknown>).name);
  if (!name) throw error(400, 'Give the device a name');

  const device = await renameDevice(locals.user.id, params.id, name);
  if (!device) throw error(404, 'Device not found');
  return json({ device });
};
