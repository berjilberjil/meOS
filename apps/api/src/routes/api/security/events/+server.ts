import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { countRecent, listSecurityEvents } from '$lib/server/audit';
import { enforceRateLimit } from '$lib/server/security';

/**
 * Recent security metadata for the signed-in owner. No payloads, no raw IPs,
 * no tokens. This is what a dashboard or the native app can show without
 * turning the audit log into another copy of the vault.
 */
export const GET: RequestHandler = async ({ locals, url }) => {
  if (!locals.user) throw error(401, 'Not signed in');
  enforceRateLimit(`security-events:${locals.user.id}`, 60, 60_000);
  const limit = Number(url.searchParams.get('limit') ?? '100');
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const [events, failedLogins, deniedRequests] = await Promise.all([
    listSecurityEvents(locals.user.id, Number.isFinite(limit) ? limit : 100),
    countRecent(locals.user.id, 'login', 'failure', since),
    countRecent(locals.user.id, 'csrf_blocked', 'denied', since, true)
  ]);
  const alerts: string[] = [];
  if (failedLogins >= 5) alerts.push(`${failedLogins} failed sign-ins in the last 24 hours.`);
  if (deniedRequests > 0) alerts.push(`${deniedRequests} cross-site requests were refused.`);
  return json({ events, alerts, window: '24h' });
};
