import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { beginMfaSetup, mfaStatus } from '$lib/server/mfa';
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

/**
 * Start TOTP enrollment. Requires the login password (and a current code if MFA
 * is already enabled) — a stolen session alone must not be able to add an
 * attacker-controlled second factor. The response contains the secret and
 * recovery codes exactly once; they are never retrievable again.
 */
export const POST: RequestHandler = async ({ locals, request, getClientAddress }) => {
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
    void audit({
      event: 'mfa_setup_started',
      outcome: 'denied',
      userId: user.id,
      ip,
      userAgent: request.headers.get('user-agent'),
      meta: { reason: proof.reason }
    });
    return json(
      {
        reauthRequired: proof.reason === 'reauth_required',
        mfaRequired: proof.reason === 'mfa_required',
        message: proof.reason === 'mfa_required'
          ? 'Enter your current authenticator code.'
          : 'Confirm your login password to set up two-factor authentication.'
      },
      { status: proof.reason === 'rate_limited' ? 429 : 403 }
    );
  }

  const status = await mfaStatus(user.id);
  if (status.enabled) throw error(409, 'Two-factor authentication is already enabled.');

  let setup;
  try {
    setup = await beginMfaSetup(user.id, user.username);
  } catch (e) {
    throw error(503, (e as Error).message || 'Two-factor setup is not available.');
  }

  void audit({
    event: 'mfa_setup_started',
    outcome: 'success',
    userId: user.id,
    ip,
    userAgent: request.headers.get('user-agent')
  });
  return json(setup);
};
