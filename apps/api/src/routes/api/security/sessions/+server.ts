import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { deleteOtherSessions, listSessions } from '$lib/server/auth';
import { confirmSensitive } from '$lib/server/sensitive';
import { readJsonBody } from '$lib/server/http';
import { enforceRateLimit } from '$lib/server/security';
import { audit } from '$lib/server/audit';

function ipOf(getClientAddress: () => string): string {
  try {
    return getClientAddress();
  } catch {
    return 'unknown';
  }
}

/** Every live session for this account, with the current one marked. */
export const GET: RequestHandler = async ({ locals }) => {
  if (!locals.user) throw error(401, 'Not signed in');
  enforceRateLimit(`sessions-list:${locals.user.id}`, 60, 60_000);
  return json({ sessions: await listSessions(locals.user.id, locals.sessionToken) });
};

/** Sign out every other device. Current session stays. Requires the password. */
export const DELETE: RequestHandler = async ({ locals, request, getClientAddress }) => {
  const user = locals.user;
  const token = locals.sessionToken;
  if (!user || !token) throw error(401, 'Not signed in');

  const body = (await readJsonBody(request, 4_096)) as Record<string, unknown>;
  const ip = ipOf(getClientAddress);
  const proof = await confirmSensitive(
    user,
    token,
    { password: String(body.password ?? ''), code: String(body.code ?? '') },
    ip,
    true
  );
  if (!proof.ok) {
    return json(
      {
        reauthRequired: proof.reason === 'reauth_required',
        mfaRequired: proof.reason === 'mfa_required',
        message: proof.reason === 'mfa_required'
          ? 'Enter your authenticator code.'
          : 'Confirm your login password first.'
      },
      { status: proof.reason === 'rate_limited' ? 429 : 403 }
    );
  }

  const revoked = await deleteOtherSessions(user.id, token);
  void audit({
    event: 'sessions_revoke_others',
    outcome: 'success',
    userId: user.id,
    ip,
    userAgent: request.headers.get('user-agent'),
    meta: { revoked }
  });
  return json({ ok: true, revoked });
};
