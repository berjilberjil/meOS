import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { parseDeviceName, renameDevice } from '$lib/server/devices';
import { readJsonBody } from '$lib/server/http';
import { enforceRateLimit } from '$lib/server/security';

/** Rename one of this account's devices. */
export const PATCH: RequestHandler = async ({ params, request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  enforceRateLimit(`devices-patch:${locals.user.id}`, 60, 60_000);
  if (!params.id || params.id.length > 64) throw error(404, 'Device not found');

  const body = (await readJsonBody(request, 4_096)) as Record<string, unknown>;
  const name = parseDeviceName((body as Record<string, unknown>).name);
  if (!name) throw error(400, 'Give the device a name');

  const device = await renameDevice(locals.user.id, params.id, name);
  if (!device) throw error(404, 'Device not found');
  return json({ device });
};
