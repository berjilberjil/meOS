import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { enableMfa, mfaStatus } from '$lib/server/mfa';
import { deleteOtherSessions, hasFreshReauth } from '$lib/server/auth';
import { readJsonBody } from '$lib/server/http';
import { audit } from '$lib/server/audit';

/** Confirm the first TOTP code and turn the factor on. */
export const POST: RequestHandler = async ({ request, locals, getClientAddress }) => {
  const user = locals.user;
  const token = locals.sessionToken;
  if (!user || !token) throw error(401, 'Not signed in');
  if (!(await hasFreshReauth(token))) {
    return json({ reauthRequired: true, message: 'Confirm your login password again.' }, { status: 403 });
  }

  const body = (await readJsonBody(request, 2_048)) as Record<string, unknown>;
  const code = String(body.code ?? '').trim();
  const ok = await enableMfa(user.id, code);
  let ip = 'unknown';
  try {
    ip = getClientAddress();
  } catch {
    /* local/test */
  }
  void audit({
    event: 'mfa_enable',
    outcome: ok ? 'success' : 'failure',
    userId: user.id,
    ip,
    userAgent: request.headers.get('user-agent')
  });
  if (!ok) throw error(400, 'That code is not valid. Check the time on your device and try the next code.');
  // A session created before MFA was enabled should not keep its old trust.
  await deleteOtherSessions(user.id, token);
  return json(await mfaStatus(user.id));
};
