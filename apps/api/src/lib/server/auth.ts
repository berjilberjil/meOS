import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import { sql } from './db';

const DAY = 1000 * 60 * 60 * 24;
export const SESSION_COOKIE = 'myos_session';
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

export async function createSession(userId: number): Promise<string> {
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
