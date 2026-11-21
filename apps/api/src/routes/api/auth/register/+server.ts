import { json, error } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';
import type { RequestHandler } from './$types';
import { sql } from '$lib/server/db';
import {
  verifyPassword,
  hashPassword,
  createSession,
  cookieOptions,
  SESSION_COOKIE,
  signupAllowed
} from '$lib/server/auth';
import { readJsonBody } from '$lib/server/http';
import { enforceRateLimit } from '$lib/server/security';
import { audit, hashIp } from '$lib/server/audit';

const USERNAME_RE = /^[a-z0-9][a-z0-9._-]{2,63}$/;
const MAX_PASSWORD = 200;

function setupTokenMatches(given: string, expected: string): boolean {
  const a = new TextEncoder().encode(given);
  const b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i]! ^ b[i]!;
  return diff === 0;
}

function ipOf(getClientAddress: () => string): string {
  try {
    return getClientAddress();
  } catch {
    return 'unknown';
  }
}

/**
 * Create the owner account.
 *
 * The repo is single-owner and `CLAUDE.md` promises public signup is disabled,
 * but this route used to accept anyone. It now works only while the database
 * has no users (first-run setup) or when the operator explicitly sets
 * `MEOS_ALLOW_SIGNUP=true`. That keeps a fresh deployment usable without
 * exposing account creation — and the shared AI, voice and R2 allowances that
 * come with it — to the public internet.
 */
export const POST: RequestHandler = async ({ request, cookies, url, getClientAddress }) => {
  const body = (await readJsonBody(request, 8_192)) as Record<string, unknown>;
  const name = String(body.username ?? '').trim().toLowerCase();
  const password = String(body.password ?? '');
  const setupToken = String(body.setupToken ?? '');
  const ip = ipOf(getClientAddress);
  const userAgent = request.headers.get('user-agent');
  // Signup is normally closed; when it is open, do not let one address create
  // accounts in a loop.
  enforceRateLimit(`register:${ip}`, 5, 60 * 60 * 1000);

  const [{ n } = { n: 0 }] = await sql`select count(*) as n from users`;
  if (!signupAllowed(Number(n), env.MEOS_ALLOW_SIGNUP)) {
    void audit({ event: 'register', outcome: 'denied', ip, userAgent, meta: { reason: 'closed' } });
    throw error(403, 'Registration is closed.');
  }
  // Optional first-run gate. Set MEOS_SETUP_TOKEN before deploying and send it
  // with the first registration; after that, signup is closed anyway.
  if (env.MEOS_SETUP_TOKEN && !setupTokenMatches(setupToken, env.MEOS_SETUP_TOKEN)) {
    void audit({ event: 'register', outcome: 'denied', ip, userAgent, meta: { reason: 'setup_token' } });
    throw error(403, 'A valid setup token is required.');
  }

  if (!USERNAME_RE.test(name)) {
    throw error(400, 'Use 3–64 lowercase letters, numbers, dots, dashes or underscores');
  }
  // Eight, matching the vault passphrase minimum the same person is about to
  // set two screens later. Four was brute-forceable in minutes even with the
  // login throttle in front of it, and this account holds every synced module
  // plus the salts and wrapped keys that enable an offline attack on the
  // passphrase itself.
  if (password.length < 8) throw error(400, 'Password must be at least 8 characters');
  if (password.length > MAX_PASSWORD) throw error(400, 'Password is too long');

  const passwordHash = await hashPassword(password);
  // `on conflict do nothing` closes the select-then-insert race: two concurrent
  // requests can no longer produce a 500 constraint error instead of a 409.
  const rows = await sql`
    insert into users (username, password_hash)
    values (${name}, ${passwordHash})
    on conflict (username) do nothing
    returning id, username`;
  const user = rows[0];
  if (!user) throw error(409, 'That username is taken');

  const token = await createSession(Number(user.id), {
    userAgent: userAgent?.slice(0, 160) ?? null,
    ipHash: await hashIp(ip)
  });
  cookies.set(SESSION_COOKIE, token, cookieOptions(url));
  void audit({ event: 'register', outcome: 'success', userId: Number(user.id), ip, userAgent });
  return json({ id: user.id, username: user.username });
};
