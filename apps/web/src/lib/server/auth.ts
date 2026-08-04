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

export function cookieOptions() {
  return {
    path: '/',
    httpOnly: true,
    sameSite: 'lax' as const,
    // secure:false so the mac app also works against a plain-HTTP localhost dev
    // backend; production is HTTPS and the cookie is fine either way.
    secure: false,
    maxAge: 60 * 60 * 24 * SESSION_DAYS
  };
}
