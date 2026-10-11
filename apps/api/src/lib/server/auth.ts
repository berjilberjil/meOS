import { sql } from './db';

const DAY = 1000 * 60 * 60 * 24;
export const SESSION_COOKIE = 'meos_session';
export const SESSION_DAYS = 60;

/**
 * Password hashing on the Workers free tier (10ms CPU cap).
 *
 * The old code used node:crypto's scryptSync. Scrypt is deliberately slow —
 * that's its job — and the Workers polyfill makes it worse: ~50-100ms CPU per
 * call, five to ten times the entire per-request budget, so logins and
 * registrations were killed mid-flight. PBKDF2-SHA256 via crypto.subtle is
 * native on Workers and fits comfortably.
 *
 * Stored format is versioned:
 *   v2:<iterations>:<saltHex>:<hashHex>   PBKDF2-SHA256, 64-byte hash
 *   <saltHex>:<hashHex>                   legacy scrypt, still verified
 *
 * 10k iterations + the login rate limit below is the right trade for a
 * single-user personal app: it defeats offline guessing of a decent
 * passphrase without needing an Argon2-grade work factor.
 *
 * Both functions are async now — call sites must await them.
 */

const PBKDF2_ITERATIONS = 10_000;

function toHex(bytes: Uint8Array): string {
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function fromHex(hex: string): Uint8Array<ArrayBuffer> {
  return new Uint8Array((hex.match(/.{2}/g) ?? []).map((h) => parseInt(h, 16)));
}

async function pbkdf2(pw: string, salt: Uint8Array<ArrayBuffer>, iterations: number): Promise<Uint8Array<ArrayBuffer>> {
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(pw),
    'PBKDF2',
    false,
    ['deriveBits']
  );
  return new Uint8Array(
    await crypto.subtle.deriveBits(
      { name: 'PBKDF2', hash: 'SHA-256', salt, iterations },
      keyMaterial,
      512 // 64 bytes, same length the old scrypt hash had
    )
  );
}

export async function hashPassword(pw: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const hash = await pbkdf2(pw, salt, PBKDF2_ITERATIONS);
  return `v2:${PBKDF2_ITERATIONS}:${toHex(salt)}:${toHex(hash)}`;
}

export async function verifyPassword(pw: string, stored: string): Promise<boolean> {
  if (stored.startsWith('v2:')) {
    const [, iters, saltHex, hashHex] = stored.split(':');
    const test = await pbkdf2(pw, fromHex(saltHex), Number(iters));
    const orig = fromHex(hashHex);
    if (orig.length !== test.length) return false;
    // constant-time compare (timingSafeEqual was node:crypto)
    let diff = 0;
    for (let i = 0; i < orig.length; i++) diff |= orig[i]! ^ test[i]!;
    return diff === 0;
  }
  // Legacy scrypt hash: lazy-import the polyfill only for old hashes, so the
  // common path never pays for it. A legacy verify can still trip the free
  // CPU cap once — after deploying, log in once (or change your password) to
  // rewrite the stored hash as v2.
  const { scryptSync, timingSafeEqual } = await import('node:crypto');
  const [salt, hash] = stored.split(':');
  if (!salt || !hash) return false;
  const test = scryptSync(pw, salt, 64);
  const orig = Buffer.from(hash, 'hex');
  return orig.length === test.length && timingSafeEqual(orig, test);
}

export const LOGIN_MAX_ATTEMPTS = 10;
export const LOGIN_WINDOW_MINUTES = 15;

let attemptsReady = false;
async function ensureAttempts(): Promise<void> {
  if (attemptsReady) return;
  await sql`
    create table if not exists login_attempts (
      scope      text not null,
      at         text not null
    )`;
  await sql`create index if not exists login_attempts_scope_idx on login_attempts(scope, at)`;
  attemptsReady = true;
}

function windowStart(): string {
  return new Date(Date.now() - LOGIN_WINDOW_MINUTES * 60_000).toISOString();
}

/** Whether this username/IP pair still has attempts left in the window. */
export async function loginAllowed(username: string, ip: string): Promise<boolean> {
  await ensureAttempts();
  const since = windowStart();
  const rows = await sql`
    select count(*) as n from login_attempts
    where at > ${since} and scope in (${'u:' + username}, ${'i:' + ip})`;
  return Number(rows[0]?.n ?? 0) < LOGIN_MAX_ATTEMPTS;
}

/** Record a failure, and opportunistically drop rows that have aged out. */
export async function recordFailedLogin(username: string, ip: string): Promise<void> {
  await ensureAttempts();
  const now = new Date().toISOString();
  await sql`delete from login_attempts where at <= ${windowStart()}`;
  await sql`insert into login_attempts (scope, at) values (${'u:' + username}, ${now})`;
  await sql`insert into login_attempts (scope, at) values (${'i:' + ip}, ${now})`;
}

/** A clean sign-in clears the username's failures. */
export async function clearFailedLogins(username: string): Promise<void> {
  await ensureAttempts();
  await sql`delete from login_attempts where scope = ${'u:' + username}`;
}

export async function createSession(userId: number): Promise<string> {
  // Sweep this user's dead tokens first. Nothing else ever deleted them —
  // hooks.server.ts filters on expires_at at read time, so they were invisible
  // and accumulated for the life of the account in a database whose free-tier
  // storage is shared by every user.
  await sql`delete from sessions where user_id = ${userId} and expires_at <= ${new Date().toISOString()}`;
  const token = toHex(crypto.getRandomValues(new Uint8Array(32)));
  const expires = new Date(Date.now() + SESSION_DAYS * DAY);
  await sql`insert into sessions (token, user_id, expires_at) values (${token}, ${userId}, ${expires})`;
  return token;
}

export async function deleteSession(token: string): Promise<void> {
  await sql`delete from sessions where token = ${token}`;
}

/**
 * `secure` is decided per request rather than pinned off.
 *
 * It was hardcoded false so the Mac app could talk to a plain-HTTP localhost
 * dev backend — but that flag rides all the way to production, where it tells
 * the browser this session cookie may be sent over plain HTTP. One downgraded
 * request on a shared network is then enough to hand somebody a 60-day session.
 * Dev keeps its exemption by looking at the URL it is actually serving.
 */
export function cookieOptions(url?: URL) {
  const isLocal =
    !!url && (url.protocol === 'http:' && (url.hostname === 'localhost' || url.hostname === '127.0.0.1'));
  return {
    path: '/',
    httpOnly: true,
    sameSite: 'lax' as const,
    secure: !isLocal,
    maxAge: 60 * 60 * 24 * SESSION_DAYS
  };
}
