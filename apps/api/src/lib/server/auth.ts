import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import { sql } from './db';

const DAY = 1000 * 60 * 60 * 24;
export const SESSION_COOKIE = 'meos_session';
export const SESSION_DAYS = 60;

export function hashPassword(pw: string): string {
  const salt = randomBytes(16).toString('hex');
  const hash = scryptSync(pw, salt, 64).toString('hex');
  return `${salt}:${hash}`;
}

export function verifyPassword(pw: string, stored: string): boolean {
  const [salt, hash] = stored.split(':');
  if (!salt || !hash) return false;
  const test = scryptSync(pw, salt, 64);
  const orig = Buffer.from(hash, 'hex');
  return orig.length === test.length && timingSafeEqual(orig, test);
}

/**
 * Failed sign-in attempts, so a password cannot simply be guessed.
 *
 * `verifyPassword` is one scrypt at Node defaults — roughly 50 ms — and Workers
 * fan out, so an unthrottled login endpoint exhausts a short password in minutes
 * from concurrent clients. The account is worth taking: it holds every synced
 * module and `meos.crypto`, whose salts and wrapped DEKs enable an offline
 * attack on the passphrase itself.
 *
 * Counted per username AND per IP, because either alone is trivially sidestepped.
 */
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
  const token = randomBytes(32).toString('hex');
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
