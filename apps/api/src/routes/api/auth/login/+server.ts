import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import {
  verifyPassword,
  hashPassword,
  createSession,
  cookieOptions,
  SESSION_COOKIE,
  loginAllowed,
  recordFailedLogin,
  clearFailedLogins,
  dummyVerify,
  passwordKdf,
  passwordPepperConfigured
} from '$lib/server/auth';
import { isMfaEnabled, verifySecondFactor } from '$lib/server/mfa';
import { readJsonBody } from '$lib/server/http';
import { audit, hashIp } from '$lib/server/audit';

const MAX_USERNAME = 64;
const MAX_PASSWORD = 200;

function ipOf(getClientAddress: () => string): string {
  try {
    return getClientAddress();
  } catch {
    return 'unknown';
  }
}

export const POST: RequestHandler = async ({ request, cookies, url, getClientAddress }) => {
  const body = (await readJsonBody(request, 4_096)) as Record<string, unknown>;
  const name = String(body.username ?? '').trim().toLowerCase();
  const password = String(body.password ?? '');
  const code = String(body.code ?? '').trim().slice(0, 64);
  const ip = ipOf(getClientAddress);
  const userAgent = request.headers.get('user-agent');

  if (!name || name.length > MAX_USERNAME || password.length > MAX_PASSWORD) {
    throw error(401, 'Wrong username or password');
  }

  // Throttled per username AND per IP. verifyPassword is a single PBKDF2 (~2-3ms)
  // and Workers fan out, so an unthrottled endpoint exhausts a short password in
  // minutes — and this account holds every synced module plus the salts and
  // wrapped keys that enable an offline attack on the vault passphrase.
  if (!(await loginAllowed(name, ip))) {
    void audit({ event: 'login', outcome: 'denied', ip, userAgent, meta: { reason: 'rate_limited' } });
    throw error(429, 'Too many attempts. Wait a few minutes and try again.');
  }

  const rows = await sql`select id, username, password_hash from users where username = ${name}`;
  const user = rows[0];
  let passwordOk = false;
  if (user) {
    passwordOk = await verifyPassword(password, String(user.password_hash));
  } else {
    // Same PBKDF2 work as a real account, so timing does not reveal whether
    // this username exists.
    await dummyVerify(password);
  }

  if (!user || !passwordOk) {
    await recordFailedLogin(name, ip);
    void audit({
      event: 'login',
      outcome: 'failure',
      userId: user ? Number(user.id) : null,
      ip,
      userAgent,
      meta: { reason: 'credentials' }
    });
    throw error(401, 'Wrong username or password');
  }

  // Second factor is checked only after the password is proven, so an attacker
  // cannot use this endpoint to enumerate which accounts have MFA.
  const mfaEnabled = await isMfaEnabled(Number(user.id));
  if (mfaEnabled) {
    if (!code) {
      return json(
        { mfaRequired: true, message: 'Enter your authenticator code.' },
        { status: 401 }
      );
    }
    const second = await verifySecondFactor(Number(user.id), code);
    if (!second) {
      await recordFailedLogin(name, ip);
      void audit({
        event: 'login_mfa',
        outcome: 'failure',
        userId: Number(user.id),
        ip,
        userAgent
      });
      throw error(401, 'That code is not valid. Try the next one, or a recovery code.');
    }
  }

  await clearFailedLogins(name, ip);

  // Legacy scrypt hashes cost 50-100ms CPU on Workers — over the free tier's
  // 10ms cap. Rewriting one after a successful login is the only opportunity
  // to migrate it without asking the owner to change their password. This also
  // upgrades v2 to the peppered v3 format when a pepper is configured.
  const stored = String(user.password_hash);
  // Upgrade to the currently configured format once, without rewriting a hash
  // that is already current. `v4` is Argon2id; `v3` is peppered PBKDF2.
  const needsUpgrade = stored.startsWith('v4:')
    ? false // never downgrade Argon2id to PBKDF2
    : stored.startsWith('v3:')
      ? passwordKdf() === 'argon2id'
      : stored.startsWith('v2:')
        ? passwordKdf() === 'argon2id' || passwordPepperConfigured()
        : true; // legacy scrypt
  if (needsUpgrade) {
    try {
      const upgraded = await hashPassword(password);
      await sql`update users set password_hash = ${upgraded}
                where id = ${user.id} and password_hash = ${stored}`;
    } catch {
      // A failed upgrade must not turn a valid sign-in into a 500.
    }
  }

  const token = await createSession(Number(user.id), {
    userAgent: userAgent?.slice(0, 160) ?? null,
    ipHash: await hashIp(ip)
  });
  cookies.set(SESSION_COOKIE, token, cookieOptions(url));
  void audit({
    event: 'login',
    outcome: 'success',
    userId: Number(user.id),
    ip,
    userAgent,
    meta: { mfa: mfaEnabled }
  });
  return json({ id: user.id, username: user.username });
};
