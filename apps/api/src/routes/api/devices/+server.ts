import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { listDevices, parseDeviceRegistration, registerDevice } from '$lib/server/devices';

/** Every device signed into this account, most recently active first. */
export const GET: RequestHandler = async ({ locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  return json({ devices: await listDevices(locals.user.id) });
};

/**
 * A heartbeat from the app on this device. Called after sign-in and when the
 * app returns to the foreground; safe to call any number of times because the
 * install id is stable and the upsert refreshes the same row.
 */
export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');

  const body = await request.json().catch(() => ({}));
  const parsed = parseDeviceRegistration(body);
  if (!parsed.ok) throw error(400, parsed.message);

  return json({ device: await registerDevice(locals.user.id, parsed.value) });
};
