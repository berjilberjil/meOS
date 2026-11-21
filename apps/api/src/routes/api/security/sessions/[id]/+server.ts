import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { revokeSession } from '$lib/server/auth';
import { confirmSensitive } from '$lib/server/sensitive';
import { readJsonBody } from '$lib/server/http';
import { audit } from '$lib/server/audit';

function ipOf(getClientAddress: () => string): string {
  try {
    return getClientAddress();
  } catch {
    return 'unknown';
  }
}

/** Revoke one session by its public id. Scoped to the signed-in owner. */
export const DELETE: RequestHandler = async ({ params, locals, request, getClientAddress }) => {
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

  const id = String(params.id ?? '');
  const revoked = await revokeSession(user.id, id);
  void audit({
    event: 'session_revoke',
    outcome: revoked ? 'success' : 'failure',
    userId: user.id,
    ip,
    userAgent: request.headers.get('user-agent'),
    meta: { session: id.slice(0, 16) }
  });
  if (!revoked) throw error(404, 'Session not found.');
  return json({ ok: true });
};
